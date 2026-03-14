import { Client } from "@upstash/qstash";
import { serve } from "@upstash/workflow/nextjs";
import { and, eq } from "drizzle-orm";
import {
  acquireEntityLock,
  createHeartbeat,
  emitDurableEvent,
  getActiveStreamId,
  initDurableStream,
  releaseEntityLock,
  resolveActiveStream,
} from "@/lib/ai/durable-stream";
import { streamWritingPrompt } from "@/lib/ai/prompt";
import { createDurableSSEResponse } from "@/lib/api/durable-sse";
import { requireUserId } from "@/lib/auth";
import { getCurrentDayIndex } from "@/lib/day-index";
import { db } from "@/lib/db";
import { entries, users } from "@/lib/db/schema";

const qstash = new Client({
  token: process.env.QSTASH_TOKEN as string,
});

function resolveAboutDayIndex(dayIndex: number): number {
  if (dayIndex <= 1) return 0;
  return dayIndex - 2;
}

// GET /api/prompts/generate/stream — Replay + live durable SSE stream.
// The server looks up the active streamId for this user so the client
// does not need to track or send it.
export async function GET(request: Request) {
  const userId = await requireUserId(request);
  const streamId = await getActiveStreamId(userId, "prompt");
  if (!streamId) {
    return Response.json({ error: "No active prompt stream" }, { status: 404 });
  }
  return createDurableSSEResponse(request, streamId);
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
      db.select().from(users).where(eq(users.id, userId)).limit(1),
      db
        .select()
        .from(entries)
        .where(
          and(
            eq(entries.userId, userId),
            eq(entries.dayIndex, targetAboutDayIndex)
          )
        )
        .limit(1),
      db
        .select()
        .from(entries)
        .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
        .limit(1),
    ]);

    if (userRows.length === 0) {
      await heartbeat.stop();
      await emitDurableEvent(streamId, "error", {
        message: "User not found",
        streamId,
      });
      await releaseEntityLock(userId, "prompt", streamId);
      return;
    }

    const readingBody =
      aboutEntryRows.length > 0 ? aboutEntryRows[0].readingBody : null;

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
      }
    );

    await db
      .insert(entries)
      .values({
        id:
          todayEntryRows.length > 0
            ? todayEntryRows[0].id
            : crypto.randomUUID(),
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
    // NOTE: entity lock is intentionally NOT released on success.
    // It stays alive (TTL 24h) so GET can always find the active/completed stream.
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message:
        error instanceof Error ? error.message : "Failed to stream prompt",
      streamId,
    });
    // Release lock on error so the next POST can start a fresh generation.
    await releaseEntityLock(userId, "prompt", streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("prompt-generation", async () => {
    // dayIndex is pre-resolved and included in the payload so the workflow step
    // doesn't need to re-query the DB.
    const payload = workflow.requestPayload as PromptGenerationPayload;
    await runPromptGeneration(payload);
  });
});

// POST /api/prompts/generate/stream — Kick off durable prompt generation.
// The client sends no body; the server owns stream identity.
export async function POST(request: Request) {
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));
  const hasQstashSigningKeys =
    Boolean(process.env.QSTASH_CURRENT_SIGNING_KEY) ||
    Boolean(process.env.QSTASH_NEXT_SIGNING_KEY);

  // QStash callback: pass directly to the workflow handler.
  if (hasQstashSignature) {
    return workflowPOST(request);
  }

  // All user-initiated requests (both dev and production initial call):
  const userId = await requireUserId(request);

  // Step 1: Check for an existing active stream for this user.
  const active = await resolveActiveStream(userId, "prompt");
  if (active) {
    if (active.meta.status === "running") {
      return Response.json(
        { ok: true, mode: "already-running" },
        { status: 200 }
      );
    }
    if (active.meta.status === "completed") {
      // Stream completed — fetch the prompt from DB and return it directly.
      const dayIndex = active.meta.params.dayIndex as number;
      const rows = await db
        .select()
        .from(entries)
        .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
        .limit(1);
      if (rows.length > 0 && rows[0].writingPrompt !== null) {
        return Response.json(
          { ok: true, mode: "completed", prompt: rows[0].writingPrompt },
          { status: 200 }
        );
      }
      // Weird state: stream completed but DB has no data. Clear lock and proceed.
      await releaseEntityLock(userId, "prompt", active.streamId);
    }
  }

  // Step 2: Check if prompt already exists in DB for today.
  const dayIndex = await getCurrentDayIndex(userId);
  const existingRows = await db
    .select()
    .from(entries)
    .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
    .limit(1);

  if (existingRows.length > 0 && existingRows[0].writingPrompt !== null) {
    return Response.json(
      { ok: true, mode: "completed", prompt: existingRows[0].writingPrompt },
      { status: 200 }
    );
  }

  // Step 3: Start a new generation. Server generates the streamId.
  const streamId = crypto.randomUUID();
  const { acquired } = await acquireEntityLock(userId, "prompt", streamId);

  if (!acquired) {
    // Lost a race with a concurrent request — the other request won the lock.
    return Response.json(
      { ok: true, mode: "already-running" },
      { status: 200 }
    );
  }

  const payload: PromptGenerationPayload = { userId, dayIndex, streamId };

  if (process.env.NODE_ENV !== "production" && hasQstashSigningKeys) {
    // Direct-dev path: run in-process as a fire-and-forget.
    void runPromptGeneration(payload).catch((error) => {
      console.error("Direct-dev prompt stream failed", { streamId, error });
    });
    return Response.json({ ok: true, mode: "started" }, { status: 202 });
  }

  // Production path: publish to QStash so it calls back to this endpoint
  // with a valid upstash-signature. The serve() handler then verifies the
  // signature and orchestrates the workflow steps.
  const proto = request.headers.get("x-forwarded-proto") || "https";
  const host = request.headers.get("host") || "localhost:3000";
  const callbackUrl = `${proto}://${host}/api/prompts/generate/stream`;

  await qstash.publishJSON({
    url: callbackUrl,
    body: payload,
    headers: {
      Authorization: request.headers.get("Authorization") || "",
    },
  });
  return Response.json({ ok: true, mode: "started" }, { status: 202 });
}
