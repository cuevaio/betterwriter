import { redis } from "@/lib/ai/redis";

export type DurableEventName =
  | "start"
  | "delta"
  | "complete"
  | "error"
  | "heartbeat";

export interface DurableEventFrame<T = unknown> {
  id: number;
  streamId: string;
  event: DurableEventName;
  data: T;
  timestamp: number;
}

export interface DurableStreamMeta {
  streamId: string;
  userId: string;
  kind: "reading" | "prompt";
  status: "running" | "completed" | "errored";
  createdAt: number;
  updatedAt: number;
  params: Record<string, unknown>;
}

const DEFAULT_TTL_SECONDS = Number(
  process.env.DURABLE_STREAM_TTL_SECONDS ?? 300
);

const keys = (streamId: string) => ({
  meta: `stream:meta:${streamId}`,
  events: `stream:events:${streamId}`,
  seq: `stream:seq:${streamId}`,
});

function ttlSeconds() {
  return Number.isFinite(DEFAULT_TTL_SECONDS) && DEFAULT_TTL_SECONDS > 0
    ? DEFAULT_TTL_SECONDS
    : 60 * 60 * 24;
}

export async function initDurableStream(input: {
  streamId: string;
  userId: string;
  kind: "reading" | "prompt";
  params: Record<string, unknown>;
}) {
  const { streamId, userId, kind, params } = input;
  const now = Date.now();
  const k = keys(streamId);

  const meta: DurableStreamMeta = {
    streamId,
    userId,
    kind,
    status: "running",
    createdAt: now,
    updatedAt: now,
    params,
  };

  // Atomic set-if-not-exists: only the first caller wins the race.
  const wasSet = await redis.set(k.meta, meta, { ex: ttlSeconds(), nx: true });

  if (!wasSet) {
    // Another caller already created this stream — verify ownership.
    const existing = await redis.get<DurableStreamMeta>(k.meta);
    if (existing && existing.userId !== userId) {
      throw new Error("Stream belongs to another user");
    }
    return { alreadyStarted: true, meta: existing ?? meta };
  }

  await redis.set(k.seq, 0, { ex: ttlSeconds() });
  return { alreadyStarted: false, meta };
}

export async function getDurableStreamMeta(streamId: string) {
  return redis.get<DurableStreamMeta>(keys(streamId).meta);
}

export async function waitForDurableStreamMeta(
  streamId: string,
  timeoutMs = 2000,
  pollMs = 100
) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const meta = await getDurableStreamMeta(streamId);
    if (meta) return meta;

    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }

  return null;
}

export async function listDurableEventsSince(
  streamId: string,
  lastEventId: number
) {
  const next = await redis.zrange<DurableEventFrame[]>(
    keys(streamId).events,
    `(${lastEventId}`,
    "+inf",
    { byScore: true }
  );
  return next.sort((a, b) => a.id - b.id);
}

export async function emitDurableEvent<T>(
  streamId: string,
  event: DurableEventName,
  data: T
) {
  const now = Date.now();
  const k = keys(streamId);

  // Get the sequence ID first — we need it to build the frame before writing.
  const id = await redis.incr(k.seq);
  const frame: DurableEventFrame<T> = {
    id,
    streamId,
    event,
    data,
    timestamp: now,
  };

  if (event === "delta") {
    // Hot path: just write the event. Skip per-delta TTL refresh (set once on init).
    await redis.zadd(k.events, { score: id, member: frame });
    return frame;
  }

  // Heartbeat + non-delta path: pipeline zadd + TTL refreshes + meta update (updatedAt).
  // Heartbeat updates meta.updatedAt so resolveActiveStream can detect stale/crashed streams.
  const meta = await redis.get<DurableStreamMeta>(k.meta);
  const status =
    event === "complete"
      ? "completed"
      : event === "error"
        ? "errored"
        : (meta?.status ?? "running");

  const p = redis.pipeline();
  p.zadd(k.events, { score: id, member: frame });
  p.expire(k.events, ttlSeconds());
  p.expire(k.seq, ttlSeconds());
  if (meta) {
    p.set(
      k.meta,
      { ...meta, status, updatedAt: now } satisfies DurableStreamMeta,
      {
        ex: ttlSeconds(),
      }
    );
  }
  await p.exec();

  return frame;
}

export function parseCursor(value: string | null | undefined) {
  const n = Number(value ?? "0");
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.floor(n);
}

// ---------------------------------------------------------------------------
// Entity-level dedup lock
// Keyed on (userId, kind) — one active stream per user per kind.
// The lock is released shortly after successful completion (grace period for
// the inline SSE tail to drain), and immediately on error.
// ---------------------------------------------------------------------------

const entityLockKey = (userId: string, kind: string) =>
  `stream:active:${userId}:${kind}`;

/**
 * Try to acquire an entity lock. Returns `{ acquired: true }` if this caller
 * won the lock, or `{ acquired: false, activeStreamId }` with the streamId
 * that currently holds the lock.
 */
export async function acquireEntityLock(
  userId: string,
  kind: string,
  streamId: string,
  lockTtlSeconds = ttlSeconds()
): Promise<{ acquired: boolean; activeStreamId: string }> {
  const key = entityLockKey(userId, kind);
  const wasSet = await redis.set(key, streamId, {
    ex: lockTtlSeconds,
    nx: true,
  });
  if (wasSet) {
    return { acquired: true, activeStreamId: streamId };
  }
  const activeStreamId = await redis.get<string>(key);
  return { acquired: false, activeStreamId: activeStreamId ?? streamId };
}

/**
 * Release the entity lock, but only if we still own it (compare-and-delete).
 * Uses a Lua script for atomicity. Only called on generation error.
 */
export async function releaseEntityLock(
  userId: string,
  kind: string,
  streamId: string
): Promise<void> {
  const key = entityLockKey(userId, kind);
  await redis.eval(
    `if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end`,
    [key],
    [streamId]
  );
}

/**
 * Look up the active streamId for a user+kind without acquiring the lock.
 */
export async function getActiveStreamId(
  userId: string,
  kind: "reading" | "prompt"
): Promise<string | null> {
  return redis.get<string>(entityLockKey(userId, kind));
}

// How long without a heartbeat before we consider a running stream stale
// (indicates server crash / unclean shutdown).
const STALE_RUNNING_MS = 2 * 60 * 1000; // 2 minutes

/**
 * Resolve the active stream for a user+kind, validating that it is still alive.
 * Cleans up stale/errored locks automatically.
 *
 * Returns null if:
 * - No active lock exists
 * - Lock exists but stream meta has expired (TTL lapsed)
 * - Stream errored
 * - Stream is "running" but updatedAt is older than STALE_RUNNING_MS (server crash)
 *
 * Returns { streamId, meta } for running or completed streams.
 */
export async function resolveActiveStream(
  userId: string,
  kind: "reading" | "prompt"
): Promise<{ streamId: string; meta: DurableStreamMeta } | null> {
  const streamId = await getActiveStreamId(userId, kind);
  if (!streamId) return null;

  const meta = await getDurableStreamMeta(streamId);

  if (!meta) {
    // Lock exists but stream data expired — clean up stale lock.
    await redis.del(entityLockKey(userId, kind));
    return null;
  }

  if (meta.status === "errored") {
    // Previous generation errored — clean up so next POST starts fresh.
    await redis.del(entityLockKey(userId, kind));
    return null;
  }

  if (meta.status === "running") {
    const staleCutoff = Date.now() - STALE_RUNNING_MS;
    if (meta.updatedAt < staleCutoff) {
      // Stream appears stuck (server crash / no heartbeat for 10+ min).
      await redis.del(entityLockKey(userId, kind));
      return null;
    }
  }

  return { streamId, meta };
}

/**
 * Create a heartbeat that periodically emits heartbeat events for a durable stream.
 * Keeps SSE connections alive, signals the stream is still active, and refreshes
 * meta.updatedAt so resolveActiveStream can detect crashed/stale streams.
 */
export function createHeartbeat(streamId: string, intervalMs = 5000) {
  let active = false;
  let loop: Promise<void> | null = null;

  return {
    start() {
      if (active) return;
      active = true;
      loop = (async () => {
        while (active) {
          await new Promise((r) => setTimeout(r, intervalMs));
          if (!active) break;
          await emitDurableEvent(streamId, "heartbeat", { streamId });
        }
      })();
    },
    async stop() {
      active = false;
      if (loop) {
        await loop;
        loop = null;
      }
    },
  };
}
