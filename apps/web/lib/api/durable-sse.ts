import { and, eq } from "drizzle-orm";
import {
  type DurableEventName,
  getDurableStreamMeta,
  listDurableEventsSince,
  waitForDurableStreamMeta,
} from "@/lib/ai/durable-stream";
import { sseHeaders, writeSSE, writeSSEComment } from "@/lib/ai/streaming";
import { db } from "@/lib/db";
import { type Entry, entries } from "@/lib/db/schema";

/**
 * Serialize an entry row for JSON/SSE responses.
 */
export function serializeEntry(row: Entry) {
  return {
    id: row.id,
    userId: row.userId,
    dayIndex: row.dayIndex,
    calendarDate: row.calendarDate,
    readingBody: row.readingBody ?? null,
    readingCompleted: row.readingCompleted ?? false,
    isBonusReading: row.isBonusReading ?? false,
    writingPrompt: row.writingPrompt ?? null,
    writingText: row.writingText ?? null,
    writingWordCount: row.writingWordCount ?? null,
    writingCompleted: row.writingCompleted ?? false,
    isFreeWrite: row.isFreeWrite ?? false,
    skipped: row.skipped ?? false,
  };
}

/**
 * Check DB for completed data for a given user+dayIndex+kind.
 */
async function checkDBForCompletion(
  userId: string,
  dayIndex: number,
  kind: "reading" | "prompt"
): Promise<Entry | null> {
  const rows = await db
    .select()
    .from(entries)
    .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
    .limit(1);

  if (rows.length === 0) return null;
  const row = rows[0];

  if (kind === "reading" && row.readingBody !== null) return row;
  if (kind === "prompt" && row.writingPrompt !== null) return row;
  return null;
}

/**
 * Create an SSE response that tails a durable stream inline in the POST
 * response. Includes DB fallback: if Redis events stall, periodically
 * checks whether the DB already has the completed data.
 *
 * Returns a 202 streaming response with SSE headers.
 */
export async function createInlineSSEResponse(
  streamId: string,
  userId: string,
  dayIndex: number,
  kind: "reading" | "prompt"
): Promise<Response> {
  let cancelled = false;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let lastSent = 0;
      let closed = false;
      const sleep = (ms: number) =>
        new Promise((resolve) => setTimeout(resolve, ms));

      const send = (id: number, event: DurableEventName, data: unknown) => {
        if (id <= lastSent || closed) return;
        lastSent = id;
        writeSSE(controller, event, data, id);
        if (event === "complete" || event === "error") {
          closed = true;
          try {
            controller.close();
          } catch {
            /* already closed */
          }
        }
      };

      const emitDBComplete = (entry: Entry) => {
        if (closed) return;
        writeSSE(
          controller,
          "complete",
          { entry: serializeEntry(entry) },
          "db-fallback"
        );
        closed = true;
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      };

      writeSSEComment(controller, "connected");

      // Wait for stream metadata to appear (QStash has latency)
      const meta = await waitForDurableStreamMeta(streamId, 5000);

      if (cancelled || closed) return;

      // If stream meta never appeared, check DB as fallback
      if (!meta) {
        const dbEntry = await checkDBForCompletion(userId, dayIndex, kind);
        if (dbEntry) {
          emitDBComplete(dbEntry);
          return;
        }
        writeSSE(controller, "error", {
          message: "Generation did not start in time",
        });
        try {
          controller.close();
        } catch {
          /* already closed */
        }
        return;
      }

      if (meta.userId !== userId) {
        writeSSE(controller, "error", { message: "forbidden", streamId });
        try {
          controller.close();
        } catch {
          /* already closed */
        }
        return;
      }

      // Replay any already-emitted events
      const replay = await listDurableEventsSince(streamId, 0);
      for (const frame of replay) {
        send(frame.id, frame.event, frame.data);
        if (closed) return;
      }

      // Live-tail with DB fallback
      let idleCount = 0;
      let lastActivityAt = Date.now();
      const DB_FALLBACK_INTERVAL_MS = 3000;
      const MAX_STALL_MS = 120_000; // 2 min hard timeout

      while (!closed && !cancelled) {
        const next = await listDurableEventsSince(streamId, lastSent);

        if (next.length > 0) {
          idleCount = 0;
          lastActivityAt = Date.now();
          for (const frame of next) {
            send(frame.id, frame.event, frame.data);
            if (closed) return;
          }
        } else {
          idleCount++;

          // Check stream meta for terminal state
          const latestMeta = await getDurableStreamMeta(streamId);
          if (
            latestMeta?.status === "completed" ||
            latestMeta?.status === "errored"
          ) {
            // Drain any remaining events
            const remaining = await listDurableEventsSince(streamId, lastSent);
            for (const frame of remaining) {
              send(frame.id, frame.event, frame.data);
              if (closed) return;
            }
            // If we still haven't closed (no complete/error event found),
            // fall back to DB
            if (!closed) {
              const dbEntry = await checkDBForCompletion(
                userId,
                dayIndex,
                kind
              );
              if (dbEntry) {
                emitDBComplete(dbEntry);
                return;
              }
              writeSSE(controller, "error", {
                message: "Stream ended without data",
              });
              try {
                controller.close();
              } catch {
                /* already closed */
              }
            }
            return;
          }

          // Periodic DB fallback when stream is idle
          const stallDuration = Date.now() - lastActivityAt;
          if (stallDuration > DB_FALLBACK_INTERVAL_MS) {
            const dbEntry = await checkDBForCompletion(userId, dayIndex, kind);
            if (dbEntry) {
              emitDBComplete(dbEntry);
              return;
            }
          }

          // Hard timeout
          if (stallDuration > MAX_STALL_MS) {
            writeSSE(controller, "error", {
              message: "Generation timed out",
            });
            try {
              controller.close();
            } catch {
              /* already closed */
            }
            return;
          }
        }

        const delay = Math.min(50 * 1.5 ** idleCount, 500);
        await sleep(delay);
      }
    },
    cancel() {
      cancelled = true;
    },
  });

  return new Response(stream, { status: 202, headers: sseHeaders() });
}
