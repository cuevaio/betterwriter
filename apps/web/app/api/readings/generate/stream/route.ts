import { Client } from "@upstash/qstash";
import { serve } from "@upstash/workflow/nextjs";
import { and, eq } from "drizzle-orm";
import {
  acquireEntityLock,
  createHeartbeat,
  emitDurableEvent,
  initDurableStream,
  releaseEntityLock,
  resolveActiveStream,
} from "@/lib/ai/durable-stream";
import { generateReadingStream } from "@/lib/ai/reading";
import { createInlineSSEResponse, serializeEntry } from "@/lib/api/durable-sse";
import { requireUserId } from "@/lib/auth";
import { getCurrentDayIndex, getNextBonusDayIndex } from "@/lib/day-index";
import { db } from "@/lib/db";
import { entries, users } from "@/lib/db/schema";

const qstash = new Client({
  token: process.env.QSTASH_TOKEN as string,
});

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
      await releaseEntityLock(userId, "reading", streamId);
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

    await heartbeat.stop();
    await emitDurableEvent(streamId, "complete", {
      entry: serializeEntry(row),
    });

    // Release lock after a short grace period so the inline SSE tail
    // has time to drain the complete event before the lock disappears.
    setTimeout(() => {
      releaseEntityLock(userId, "reading", streamId).catch(() => {});
    }, 5000);
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message:
        error instanceof Error ? error.message : "Failed to stream reading",
      streamId,
    });
    await releaseEntityLock(userId, "reading", streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("reading-generation", async () => {
    const payload = workflow.requestPayload as ReadingGenerationPayload;
    await runReadingGeneration(payload);
  });
});

// POST /api/readings/generate/stream — Unified endpoint.
// Returns 200 JSON when data exists in DB, 202 SSE stream when generating.
export async function POST(request: Request) {
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));
  const hasQstashSigningKeys =
    Boolean(process.env.QSTASH_CURRENT_SIGNING_KEY) ||
    Boolean(process.env.QSTASH_NEXT_SIGNING_KEY);

  // QStash callback: pass directly to the workflow handler.
  if (hasQstashSignature) {
    return workflowPOST(request);
  }

  const userId = await requireUserId(request);

  // STEP 1: DB-FIRST — always check if data already exists.
  const { dayIndex, isBonusReading, currentDayIndex } =
    await resolveReadingDayIndex(userId);

  const existingRows = await db
    .select()
    .from(entries)
    .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
    .limit(1);

  if (existingRows.length > 0 && existingRows[0].readingBody !== null) {
    return Response.json(
      { entry: serializeEntry(existingRows[0]) },
      { status: 200 }
    );
  }

  // STEP 2: Check if a generation is already in-flight.
  const active = await resolveActiveStream(userId, "reading");

  if (active && active.meta.status === "running") {
    // Tail the existing generation with DB fallback.
    return createInlineSSEResponse(
      active.streamId,
      userId,
      dayIndex,
      "reading"
    );
  }

  if (active && active.meta.status === "completed") {
    // Race: generation may have completed between step 1 and now.
    const rows = await db
      .select()
      .from(entries)
      .where(
        and(
          eq(entries.userId, userId),
          eq(entries.dayIndex, active.meta.params.dayIndex as number)
        )
      )
      .limit(1);
    if (rows.length > 0 && rows[0].readingBody !== null) {
      return Response.json({ entry: serializeEntry(rows[0]) }, { status: 200 });
    }
    // Stale completed lock without DB data — release and regenerate.
    await releaseEntityLock(userId, "reading", active.streamId);
  }

  // STEP 3: Start a new generation.
  const streamId = crypto.randomUUID();
  const { acquired, activeStreamId } = await acquireEntityLock(
    userId,
    "reading",
    streamId,
    300
  );

  if (!acquired) {
    // Lost the race — tail the winner's stream.
    return createInlineSSEResponse(activeStreamId, userId, dayIndex, "reading");
  }

  const payload: ReadingGenerationPayload = {
    userId,
    dayIndex,
    streamId,
    isBonusReading,
    currentDayIndex,
  };

  // Dispatch generation.
  if (process.env.NODE_ENV !== "production" && hasQstashSigningKeys) {
    void runReadingGeneration(payload).catch((error) => {
      console.error("Direct-dev reading stream failed", { streamId, error });
    });
  } else {
    const proto = request.headers.get("x-forwarded-proto") || "https";
    const host = request.headers.get("host") || "localhost:3000";
    const callbackUrl = `${proto}://${host}/api/readings/generate/stream`;

    try {
      await qstash.publishJSON({
        url: callbackUrl,
        body: payload,
        headers: {
          Authorization: request.headers.get("Authorization") || "",
        },
      });
    } catch (error) {
      await releaseEntityLock(userId, "reading", streamId);
      console.error("QStash publish failed", error);
      return Response.json(
        { error: "Failed to start generation" },
        { status: 500 }
      );
    }
  }

  // Return SSE stream that tails the generation with DB fallback.
  return createInlineSSEResponse(streamId, userId, dayIndex, "reading");
}
