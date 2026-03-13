import { serve } from "@upstash/workflow/nextjs";
import { and, eq } from "drizzle-orm";
import {
  acquireEntityLock,
  createHeartbeat,
  emitDurableEvent,
  initDurableStream,
  releaseEntityLock,
} from "@/lib/ai/durable-stream";
import { generateReadingStream } from "@/lib/ai/reading";
import { createDurableSSEResponse } from "@/lib/api/durable-sse";
import { streamPayloadSchema } from "@/lib/api/schemas";
import { requireUserId } from "@/lib/auth";
import { getCurrentDayIndex, getNextBonusDayIndex } from "@/lib/day-index";
import { db } from "@/lib/db";
import { entries, users } from "@/lib/db/schema";

// GET /api/readings/generate/stream?streamId=... — Replay + live durable SSE stream
export async function GET(request: Request) {
  return createDurableSSEResponse(request);
}

interface ReadingGenerationPayload {
  userId: string;
  dayIndex: number;
  streamId: string;
  isBonusReading: boolean;
  currentDayIndex: number;
}

/**
 * Determine whether this reading request is for the normal daily reading
 * or a bonus reading, and return the resolved dayIndex + flag.
 */
async function resolveReadingDayIndex(userId: string): Promise<{
  dayIndex: number;
  isBonusReading: boolean;
  currentDayIndex: number;
}> {
  const currentDayIndex = await getCurrentDayIndex(userId);

  // Check if the current day already has a reading generated
  const existing = await db
    .select({ readingBody: entries.readingBody })
    .from(entries)
    .where(
      and(eq(entries.userId, userId), eq(entries.dayIndex, currentDayIndex))
    )
    .limit(1);

  const hasReading = existing.length > 0 && existing[0].readingBody !== null;

  if (!hasReading) {
    return {
      dayIndex: currentDayIndex,
      isBonusReading: false,
      currentDayIndex,
    };
  }

  // Current day already has a reading — this is a bonus
  const bonusDayIndex = await getNextBonusDayIndex(userId);
  return { dayIndex: bonusDayIndex, isBonusReading: true, currentDayIndex };
}

async function runReadingGeneration(payload: ReadingGenerationPayload) {
  const { userId, dayIndex, streamId, isBonusReading, currentDayIndex } =
    payload;

  const { alreadyStarted } = await initDurableStream({
    streamId,
    userId,
    kind: "reading",
    params: { dayIndex, isBonusReading },
  });

  if (alreadyStarted) return;

  const heartbeat = createHeartbeat(streamId);

  try {
    await emitDurableEvent(streamId, "start", {
      type: "reading",
      dayIndex,
      isBonusReading,
      streamId,
    });
    heartbeat.start();

    const [existingRows, userRows] = await Promise.all([
      db
        .select()
        .from(entries)
        .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
        .limit(1),
      db.select().from(users).where(eq(users.id, userId)).limit(1),
    ]);

    if (userRows.length === 0) {
      await heartbeat.stop();
      await emitDurableEvent(streamId, "error", {
        message: "User not found",
        streamId,
      });
      return;
    }

    const reading = await generateReadingStream(
      userId,
      dayIndex,
      async (delta) => {
        await emitDurableEvent(streamId, "delta", { text: delta, streamId });
      },
      currentDayIndex
    );

    const [row] = await db
      .insert(entries)
      .values({
        id: existingRows.length > 0 ? existingRows[0].id : crypto.randomUUID(),
        userId,
        dayIndex,
        calendarDate: new Date().toISOString().split("T")[0],
        readingBody: reading.body,
        isBonusReading,
      })
      .onConflictDoUpdate({
        target: [entries.userId, entries.dayIndex],
        set: { readingBody: reading.body, isBonusReading },
      })
      .returning();

    const completionPayload = {
      id: row.id,
      userId: row.userId,
      dayIndex: row.dayIndex,
      calendarDate: row.calendarDate,
      readingBody: row.readingBody ?? null,
      isBonusReading: row.isBonusReading ?? false,
      writingPrompt: row.writingPrompt ?? null,
      writingText: row.writingText ?? null,
      writingWordCount: row.writingWordCount ?? null,
    };

    await heartbeat.stop();
    await emitDurableEvent(streamId, "complete", completionPayload);
    await releaseEntityLock(userId, "reading", dayIndex, streamId);
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message:
        error instanceof Error ? error.message : "Failed to stream reading",
      streamId,
    });
    await releaseEntityLock(userId, "reading", dayIndex, streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("reading-generation", async () => {
    const raw = workflow.requestPayload as { userId: string; streamId: string };
    const { dayIndex, isBonusReading, currentDayIndex } =
      await resolveReadingDayIndex(raw.userId);
    await runReadingGeneration({
      ...raw,
      dayIndex,
      isBonusReading,
      currentDayIndex,
    });
  });
});

// POST /api/readings/generate/stream — Kick off durable reading generation
export async function POST(request: Request) {
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));
  const hasQstashSigningKeys =
    Boolean(process.env.QSTASH_CURRENT_SIGNING_KEY) ||
    Boolean(process.env.QSTASH_NEXT_SIGNING_KEY);

  if (
    process.env.NODE_ENV !== "production" &&
    hasQstashSigningKeys &&
    !hasQstashSignature
  ) {
    // Direct-dev path: userId comes from JWT, not from body
    const userId = await requireUserId(request);

    const parsed = streamPayloadSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 }
      );
    }
    const { streamId } = parsed.data;

    // Server determines whether this is a normal or bonus reading
    const { dayIndex, isBonusReading, currentDayIndex } =
      await resolveReadingDayIndex(userId);
    const payload: ReadingGenerationPayload = {
      userId,
      dayIndex,
      streamId,
      isBonusReading,
      currentDayIndex,
    };

    // Check entity lock — if a generation is already running for this (user, kind, dayIndex),
    // return the active streamId so the client can connect to it instead.
    const { acquired, activeStreamId } = await acquireEntityLock(
      userId,
      "reading",
      dayIndex,
      streamId
    );

    if (!acquired) {
      return Response.json(
        { ok: true, mode: "already-running", streamId: activeStreamId },
        { status: 200 }
      );
    }

    void runReadingGeneration(payload).catch((error) => {
      console.error("Direct-dev reading stream failed", { streamId, error });
    });

    return Response.json(
      { ok: true, mode: "direct-dev", streamId },
      { status: 202 }
    );
  }

  // Workflow path (production / QStash): inject userId into the body so
  // workflow.requestPayload contains it for the background worker.
  if (!hasQstashSignature) {
    const userId = await requireUserId(request);
    const body = await request.json();
    const enrichedRequest = new Request(request.url, {
      method: request.method,
      headers: request.headers,
      body: JSON.stringify({ ...body, userId }),
    });
    return workflowPOST(enrichedRequest);
  }

  return workflowPOST(request);
}
