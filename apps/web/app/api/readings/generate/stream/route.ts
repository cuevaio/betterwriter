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
import { generateReadingStream } from "@/lib/ai/reading";
import { createDurableSSEResponse } from "@/lib/api/durable-sse";
import { requireUserId } from "@/lib/auth";
import { getCurrentDayIndex, getNextBonusDayIndex } from "@/lib/day-index";
import { db } from "@/lib/db";
import { entries, users } from "@/lib/db/schema";

const qstash = new Client({
  token: process.env.QSTASH_TOKEN as string,
});

// GET /api/readings/generate/stream — Replay + live durable SSE stream.
// The server looks up the active streamId for this user so the client
// does not need to track or send it.
export async function GET(request: Request) {
  const userId = await requireUserId(request);
  const streamId = await getActiveStreamId(userId, "reading");
  if (!streamId) {
    return Response.json(
      { error: "No active reading stream" },
      { status: 404 }
    );
  }
  return createDurableSSEResponse(request, streamId);
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
    // NOTE: entity lock is intentionally NOT released on success.
    // It stays alive (TTL 24h) so GET can always find the active/completed stream.
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message:
        error instanceof Error ? error.message : "Failed to stream reading",
      streamId,
    });
    // Release lock on error so the next POST can start a fresh generation.
    await releaseEntityLock(userId, "reading", streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("reading-generation", async () => {
    // dayIndex, isBonusReading, and currentDayIndex are pre-resolved and included
    // in the payload so the workflow step doesn't need to re-query the DB.
    const payload = workflow.requestPayload as ReadingGenerationPayload;
    await runReadingGeneration(payload);
  });
});

// POST /api/readings/generate/stream — Kick off durable reading generation.
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
  const active = await resolveActiveStream(userId, "reading");
  if (active) {
    if (active.meta.status === "running") {
      return Response.json(
        { ok: true, mode: "already-running" },
        { status: 200 }
      );
    }
    if (active.meta.status === "completed") {
      // Stream completed — check whether the user has already finished
      // reading this entry. If so, the lock is stale and we release it
      // so a new reading (bonus or next day) can be generated.
      const lockedDayIndex = active.meta.params.dayIndex as number;
      const rows = await db
        .select()
        .from(entries)
        .where(
          and(eq(entries.userId, userId), eq(entries.dayIndex, lockedDayIndex))
        )
        .limit(1);
      if (rows.length > 0 && rows[0].readingBody !== null) {
        if (rows[0].readingCompleted) {
          // User finished this reading — release so next generation can start.
          await releaseEntityLock(userId, "reading", active.streamId);
        } else {
          // User hasn't finished reading — return the entry (reconnection).
          return Response.json(
            {
              ok: true,
              mode: "completed",
              entry: {
                id: rows[0].id,
                userId: rows[0].userId,
                dayIndex: rows[0].dayIndex,
                calendarDate: rows[0].calendarDate,
                readingBody: rows[0].readingBody,
                isBonusReading: rows[0].isBonusReading ?? false,
                writingPrompt: rows[0].writingPrompt ?? null,
                writingText: rows[0].writingText ?? null,
                writingWordCount: rows[0].writingWordCount ?? null,
              },
            },
            { status: 200 }
          );
        }
      } else {
        // Stream completed but DB has no data — clear stale lock.
        await releaseEntityLock(userId, "reading", active.streamId);
      }
    }
  }

  // Step 2: Check if reading already exists in DB for the resolved day.
  const { dayIndex, isBonusReading, currentDayIndex } =
    await resolveReadingDayIndex(userId);
  const existingRows = await db
    .select()
    .from(entries)
    .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
    .limit(1);

  if (existingRows.length > 0 && existingRows[0].readingBody !== null) {
    return Response.json(
      {
        ok: true,
        mode: "completed",
        entry: {
          id: existingRows[0].id,
          userId: existingRows[0].userId,
          dayIndex: existingRows[0].dayIndex,
          calendarDate: existingRows[0].calendarDate,
          readingBody: existingRows[0].readingBody,
          isBonusReading: existingRows[0].isBonusReading ?? false,
          writingPrompt: existingRows[0].writingPrompt ?? null,
          writingText: existingRows[0].writingText ?? null,
          writingWordCount: existingRows[0].writingWordCount ?? null,
        },
      },
      { status: 200 }
    );
  }

  // Step 3: Start a new generation. Server generates the streamId.
  const streamId = crypto.randomUUID();
  const { acquired } = await acquireEntityLock(userId, "reading", streamId);

  if (!acquired) {
    // Lost a race with a concurrent request — the other request won the lock.
    return Response.json(
      { ok: true, mode: "already-running" },
      { status: 200 }
    );
  }

  const payload: ReadingGenerationPayload = {
    userId,
    dayIndex,
    streamId,
    isBonusReading,
    currentDayIndex,
  };

  if (process.env.NODE_ENV !== "production" && hasQstashSigningKeys) {
    // Direct-dev path: run in-process as a fire-and-forget.
    void runReadingGeneration(payload).catch((error) => {
      console.error("Direct-dev reading stream failed", { streamId, error });
    });
    return Response.json({ ok: true, mode: "started" }, { status: 202 });
  }

  // Production path: publish to QStash so it calls back to this endpoint
  // with a valid upstash-signature. The serve() handler then verifies the
  // signature and orchestrates the workflow steps.
  const proto = request.headers.get("x-forwarded-proto") || "https";
  const host = request.headers.get("host") || "localhost:3000";
  const callbackUrl = `${proto}://${host}/api/readings/generate/stream`;

  await qstash.publishJSON({
    url: callbackUrl,
    body: payload,
    headers: {
      Authorization: request.headers.get("Authorization") || "",
    },
  });
  return Response.json({ ok: true, mode: "started" }, { status: 202 });
}
