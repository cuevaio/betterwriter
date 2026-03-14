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
import { streamWritingPrompt } from "@/lib/ai/prompt";
import { createInlineSSEResponse, serializeEntry } from "@/lib/api/durable-sse";
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

    let day0WritingText = "";
    if (dayIndex === 1) {
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

    const [row] = await db
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
      })
      .returning();

    await heartbeat.stop();
    await emitDurableEvent(streamId, "complete", {
      entry: serializeEntry(row),
    });

    // Release lock after a short grace period.
    setTimeout(() => {
      releaseEntityLock(userId, "prompt", streamId).catch(() => {});
    }, 5000);
  } catch (error) {
    await heartbeat.stop();
    await emitDurableEvent(streamId, "error", {
      message:
        error instanceof Error ? error.message : "Failed to stream prompt",
      streamId,
    });
    await releaseEntityLock(userId, "prompt", streamId);
    throw error;
  }
}

const { POST: workflowPOST } = serve(async (workflow) => {
  await workflow.run("prompt-generation", async () => {
    const payload = workflow.requestPayload as PromptGenerationPayload;
    await runPromptGeneration(payload);
  });
});

// POST /api/prompts/generate/stream — Unified endpoint.
// Returns 200 JSON when data exists in DB, 202 SSE stream when generating.
export async function POST(request: Request) {
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));
  const hasQstashSigningKeys =
    Boolean(process.env.QSTASH_CURRENT_SIGNING_KEY) ||
    Boolean(process.env.QSTASH_NEXT_SIGNING_KEY);

  if (hasQstashSignature) {
    return workflowPOST(request);
  }

  const userId = await requireUserId(request);

  // STEP 1: DB-FIRST — always check if data already exists.
  const dayIndex = await getCurrentDayIndex(userId);
  const existingRows = await db
    .select()
    .from(entries)
    .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
    .limit(1);

  if (existingRows.length > 0 && existingRows[0].writingPrompt !== null) {
    return Response.json(
      { entry: serializeEntry(existingRows[0]) },
      { status: 200 }
    );
  }

  // STEP 2: Check if a generation is already in-flight.
  const active = await resolveActiveStream(userId, "prompt");

  if (active && active.meta.status === "running") {
    return createInlineSSEResponse(active.streamId, userId, dayIndex, "prompt");
  }

  if (active && active.meta.status === "completed") {
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
    if (rows.length > 0 && rows[0].writingPrompt !== null) {
      return Response.json({ entry: serializeEntry(rows[0]) }, { status: 200 });
    }
    await releaseEntityLock(userId, "prompt", active.streamId);
  }

  // STEP 3: Start a new generation.
  const streamId = crypto.randomUUID();
  const { acquired, activeStreamId } = await acquireEntityLock(
    userId,
    "prompt",
    streamId,
    300
  );

  if (!acquired) {
    return createInlineSSEResponse(activeStreamId, userId, dayIndex, "prompt");
  }

  const payload: PromptGenerationPayload = { userId, dayIndex, streamId };

  if (process.env.NODE_ENV !== "production" && hasQstashSigningKeys) {
    void runPromptGeneration(payload).catch((error) => {
      console.error("Direct-dev prompt stream failed", { streamId, error });
    });
  } else {
    const proto = request.headers.get("x-forwarded-proto") || "https";
    const host = request.headers.get("host") || "localhost:3000";
    const callbackUrl = `${proto}://${host}/api/prompts/generate/stream`;

    try {
      await qstash.publishJSON({
        url: callbackUrl,
        body: payload,
        headers: {
          Authorization: request.headers.get("Authorization") || "",
        },
      });
    } catch (error) {
      await releaseEntityLock(userId, "prompt", streamId);
      console.error("QStash publish failed", error);
      return Response.json(
        { error: "Failed to start generation" },
        { status: 500 }
      );
    }
  }

  return createInlineSSEResponse(streamId, userId, dayIndex, "prompt");
}
