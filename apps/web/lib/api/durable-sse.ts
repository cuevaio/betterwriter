import {
  getDurableStreamMeta,
  listDurableEventsSince,
  parseCursor,
  waitForDurableStreamMeta,
} from "@/lib/ai/durable-stream";
import { sseHeaders, writeSSE, writeSSEComment } from "@/lib/ai/streaming";
import { requireUserId } from "@/lib/auth";

/**
 * Create a durable SSE response that replays past events and live-tails new ones.
 * Shared by both the readings and prompts stream GET handlers.
 *
 * @param resolvedStreamId - If provided, use this streamId directly instead of reading
 *   it from the query params. Route handlers that look up the active stream server-side
 *   should pass it here.
 */
export async function createDurableSSEResponse(
  request: Request,
  resolvedStreamId?: string
): Promise<Response> {
  const userId = await requireUserId(request);
  const { searchParams } = new URL(request.url);
  const streamId = resolvedStreamId ?? searchParams.get("streamId");

  if (!streamId) {
    return new Response(JSON.stringify({ error: "streamId is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const cursor = parseCursor(
    request.headers.get("Last-Event-ID") ?? searchParams.get("cursor")
  );
  let cancelled = false;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let lastSent = cursor;
      let closed = false;
      const sleep = (ms: number) =>
        new Promise((resolve) => setTimeout(resolve, ms));
      const send = (
        id: number,
        event: "start" | "delta" | "complete" | "error" | "heartbeat",
        data: unknown
      ) => {
        if (id <= lastSent || closed) return;
        lastSent = id;
        writeSSE(controller, event, data, id);
        if (event === "complete" || event === "error") {
          closed = true;
          controller.close();
        }
      };
      const sendEnd = (status: "completed" | "errored") => {
        if (closed) return;
        writeSSE(controller, "end", { status, streamId }, `end-${lastSent}`);
        closed = true;
        controller.close();
      };

      writeSSEComment(controller, "connected");

      const meta = await waitForDurableStreamMeta(streamId);
      if (cancelled || closed) return;

      if (!meta) {
        writeSSE(controller, "error", {
          message: "stream not found",
          streamId,
        });
        controller.close();
        return;
      }

      if (meta.userId !== userId) {
        writeSSE(controller, "error", { message: "forbidden", streamId });
        controller.close();
        return;
      }

      const replay = await listDurableEventsSince(streamId, cursor);
      for (const frame of replay) {
        send(frame.id, frame.event, frame.data);
        if (closed) return;
      }

      if (
        !closed &&
        replay.length === 0 &&
        (meta.status === "completed" || meta.status === "errored")
      ) {
        sendEnd(meta.status === "completed" ? "completed" : "errored");
        return;
      }

      // Adaptive polling: start fast, back off when idle, reset on activity
      let idleCount = 0;
      const MIN_POLL_MS = 50;
      const MAX_POLL_MS = 500;

      while (!closed) {
        if (cancelled) return;
        const next = await listDurableEventsSince(streamId, lastSent);

        if (next.length > 0) {
          idleCount = 0;
          for (const frame of next) {
            send(frame.id, frame.event, frame.data);
            if (closed) return;
          }
        } else {
          idleCount++;
          const latestMeta = await getDurableStreamMeta(streamId);
          if (
            latestMeta?.status === "completed" ||
            latestMeta?.status === "errored"
          ) {
            sendEnd(
              latestMeta.status === "completed" ? "completed" : "errored"
            );
            return;
          }
        }

        const delay = Math.min(MIN_POLL_MS * 1.5 ** idleCount, MAX_POLL_MS);
        await sleep(delay);
      }
    },
    cancel() {
      cancelled = true;
    },
  });

  return new Response(stream, { headers: sseHeaders() });
}
