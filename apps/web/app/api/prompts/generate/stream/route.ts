import { db } from "@/lib/db";
import { users, entries } from "@/lib/db/schema";
import { eq, and } from "drizzle-orm";
import { requireUserId } from "@/lib/auth";
import { streamWritingPrompt } from "@/lib/ai/prompt";
import {
  emitDurableEvent,
  initDurableStream,
  createHeartbeat,
  acquireEntityLock,
  releaseEntityLock,
} from "@/lib/ai/durable-stream";
import { createDurableSSEResponse } from "@/lib/api/durable-sse";
import { streamPayloadSchema } from "@/lib/api/schemas";
import { getCurrentDayIndex } from "@/lib/day-index";
import { serve } from "@upstash/workflow/nextjs";

function resolveAboutDayIndex(dayIndex: number): number {
  if (dayIndex <= 1) return 0;
  return dayIndex - 2;
}

// GET /api/prompts/generate/stream?streamId=... — Replay + live durable SSE stream
export async function GET(request: Request) {
  return createDurableSSEResponse(request);
}

interface PromptGenerationPayload {
  userId: string;
  dayIndex: number;
  streamId: string;
}

async function runPromptGeneration(payload: PromptGenerationPayload) {
  const { userId, dayIndex, streamId } = payload;

  const targetAboutDayIndex = resolveAboutDayIndex(dayIndex);

  const { alreadyStarted } = await initDurableStream({
    streamId,
    userId,
    kind: "prompt",
    params: { dayIndex, aboutDayIndex: targetAboutDayIndex },
  });

  if (alreadyStarted) return;

  const heartbeat = createHeartbeat(streamId);

  try {
    await emitDurableEvent(streamId, "start", {
      type: "prompt",
      dayIndex,
      aboutDayIndex: targetAboutDayIndex,
      streamId,
    });
    heartbeat.start();

    // Parallelize independent DB reads
    const [userRows, aboutEntryRows, todayEntryRows] = await Promise.all([
      db
        .select()
        .from(users)
        .where(eq(users.id, userId))
        .limit(1),
      db
        .select()
        .from(entries)
        .where(and(eq(entries.userId, userId), eq(entries.dayIndex, targetAboutDayIndex)))
        .limit(1),
      db
        .select()
        .from(entries)
        .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
        .limit(1),
    ]);

    if (userRows.length === 0) {
      await heartbeat.stop();
      await emitDurableEvent(streamId, "error", { message: "User not found", streamId });
      return;
    }

    const readingBody = aboutEntryRows.length > 0 ? aboutEntryRows[0].readingBody : null;

    // For Day 1 prompt, get the Day 0 writing text
    let day0WritingText = "";
    if (dayIndex === 1) {
      // If aboutDayIndex is already 0, we already have it
      if (targetAboutDayIndex === 0 && aboutEntryRows.length > 0) {
        day0WritingText = aboutEntryRows[0].writingText || "";
      } else {
        const day0Entry = await db
          .select()
          .from(entries)
          .where(and(eq(entries.userId, userId), eq(entries.dayIndex, 0)))
          .limit(1);
        day0WritingText = day0Entry[0]?.writingText || "";
      }
    }

    const prompt = await streamWritingPrompt(
      {
        userId,
        dayIndex,
        aboutDayIndex: targetAboutDayIndex,
        readingBody,
        day0WritingText,
      },
      async (delta) => {
        await emitDurableEvent(streamId, "delta", { text: delta, streamId });
      },
    );

    await db
      .insert(entries)
      .values({
        id: todayEntryRows.length > 0 ? todayEntryRows[0].id : crypto.randomUUID(),
        userId,
        dayIndex,
        calendarDate: new Date().toISOString().split("T")[0],
        writingPrompt: prompt,
      })
      .onConflictDoUpdate({
        target: [entries.userId, entries.dayIndex],
        set: { writingPrompt: prompt },
      });

    await heartbeat.stop();
    await emitDurableEvent(streamId, "complete", { prompt, streamId });
    await releaseEntityLock(userId, "prompt", dayIndex, streamId);
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message: error instanceof Error ? error.message : "Failed to stream prompt",
      streamId,
    });
    await releaseEntityLock(userId, "prompt", dayIndex, streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("prompt-generation", async () => {
    const raw = workflow.requestPayload as { userId: string; streamId: string };
    const dayIndex = await getCurrentDayIndex(raw.userId);
    await runPromptGeneration({ ...raw, dayIndex });
  });
});

// POST /api/prompts/generate/stream — Kick off durable prompt generation
export async function POST(request: Request) {
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));
  const hasQstashSigningKeys =
    Boolean(process.env.QSTASH_CURRENT_SIGNING_KEY) || Boolean(process.env.QSTASH_NEXT_SIGNING_KEY);

  if (process.env.NODE_ENV !== "production" && hasQstashSigningKeys && !hasQstashSignature) {
    // Direct-dev path: userId comes from JWT, not from body
    const userId = await requireUserId(request);

    const parsed = streamPayloadSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 },
      );
    }
    const { streamId } = parsed.data;

    // Server always computes the current day for prompt generation
    const dayIndex = await getCurrentDayIndex(userId);

    // Check entity lock — if a generation is already running for this (user, kind, dayIndex),
    // return the active streamId so the client can connect to it instead.
    const { acquired, activeStreamId } = await acquireEntityLock(
      userId,
      "prompt",
      dayIndex,
      streamId,
    );

    if (!acquired) {
      return Response.json(
        { ok: true, mode: "already-running", streamId: activeStreamId },
        { status: 200 },
      );
    }

    void runPromptGeneration({ userId, dayIndex, streamId }).catch((error) => {
      console.error("Direct-dev prompt stream failed", { streamId, error });
    });

    return Response.json({ ok: true, mode: "direct-dev", streamId }, { status: 202 });
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
