const encoder = new TextEncoder();

export type SSEventName = "start" | "delta" | "complete" | "error" | "heartbeat" | "end";

export function sseHeaders() {
  return {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  };
}

export function writeSSEComment(
  controller: ReadableStreamDefaultController<Uint8Array>,
  comment = "keepalive",
) {
  controller.enqueue(encoder.encode(`: ${comment}\n\n`));
}

export function writeSSE(
  controller: ReadableStreamDefaultController<Uint8Array>,
  event: SSEventName,
  data: unknown,
  id?: number | string,
) {
  const idLine = id === undefined ? "" : `id: ${id}\n`;
  const payload = `${idLine}event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  controller.enqueue(encoder.encode(payload));
}
