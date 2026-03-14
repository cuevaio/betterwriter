/**
 * test-ensure-user.ts
 *
 * Tests that the ensureUser fix works correctly:
 *   1. Sync auto-creates a user row when the user ID does not exist in the DB.
 *   2. Sync never returns user: null.
 *   3. Reading/prompt generation endpoints work for non-existent users.
 *   4. Sync with entries does not fail FK constraint for a fresh user.
 *
 * Streams reading + prompt generation live to the console so you can read
 * the actual content as it arrives.
 *
 * Prerequisites:
 *   - Dev server running (`bun run dev`) OR set BASE_URL env var.
 *   - .env loaded (AUTH_SECRET needed for signing JWTs directly).
 *
 * Usage:
 *   bun run test-ensure-user.ts
 *   BASE_URL=https://betterwriter.vercel.app bun run test-ensure-user.ts
 */

// Load .env from apps/web so AUTH_SECRET is available for direct JWT signing.
const envPath = new URL("./apps/web/.env", import.meta.url).pathname;
const envFile = await Bun.file(envPath)
  .text()
  .catch(() => "");
for (const line of envFile.split("\n")) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) continue;
  const eqIdx = trimmed.indexOf("=");
  if (eqIdx === -1) continue;
  const key = trimmed.slice(0, eqIdx).trim();
  let val = trimmed.slice(eqIdx + 1).trim();
  if (
    (val.startsWith('"') && val.endsWith('"')) ||
    (val.startsWith("'") && val.endsWith("'"))
  ) {
    val = val.slice(1, -1);
  }
  if (!process.env[key]) {
    process.env[key] = val;
  }
}

import { signJWT } from "./apps/web/lib/auth";

const BASE_URL = process.env.BASE_URL || "http://localhost:3000";
const STREAM_TIMEOUT_MS = 120_000; // 2 minutes for full generation

// -- Colors --
const DIM = "\x1b[2m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const MAGENTA = "\x1b[35m";
const NC = "\x1b[0m";

let pass = 0;
let fail = 0;

function log(msg: string) {
  console.log(`${CYAN}[TEST]${NC} ${msg}`);
}
function ok(msg: string) {
  pass++;
  console.log(`${GREEN}  PASS${NC} ${msg}`);
}
function FAIL(msg: string) {
  fail++;
  console.log(`${RED}  FAIL${NC} ${msg}`);
}
function warn(msg: string) {
  console.log(`${YELLOW}  WARN${NC} ${msg}`);
}

function randomDeviceId(): string {
  return crypto.randomUUID();
}

async function signTokenFor(deviceId: string): Promise<string> {
  const { token } = await signJWT(deviceId);
  return token;
}

async function authAndGetToken(
  deviceId: string
): Promise<{ token: string; response: unknown }> {
  const res = await fetch(`${BASE_URL}/api/auth`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ deviceId }),
  });
  const data = (await res.json()) as Record<string, unknown>;
  return { token: data.token as string, response: data };
}

async function callSync(
  token: string,
  body: Record<string, unknown>
): Promise<{ status: number; data: Record<string, unknown> }> {
  const res = await fetch(`${BASE_URL}/api/sync`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
  const data = (await res.json()) as Record<string, unknown>;
  return { status: res.status, data };
}

/**
 * Stream a generate endpoint live to the console.
 * Parses SSE frames, prints delta text in real-time, shows events.
 */
async function streamToConsole(
  endpoint: string,
  token: string,
  label: string
): Promise<{
  status: number;
  streamedText: string;
  hasUserNotFound: boolean;
  hasStartEvent: boolean;
  hasErrorEvent: boolean;
  completed: boolean;
}> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), STREAM_TIMEOUT_MS);

  try {
    const res = await fetch(`${BASE_URL}${endpoint}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({}),
      signal: controller.signal,
    });

    // -- JSON fast path (200): reading already exists --
    if (
      res.status === 200 &&
      res.headers.get("content-type")?.includes("application/json")
    ) {
      const data = (await res.json()) as Record<string, unknown>;
      const entry = data.entry as Record<string, unknown> | undefined;
      const body =
        (entry?.readingBody as string) ??
        (entry?.writingPrompt as string) ??
        "";

      console.log("");
      console.log(`${DIM}--- ${label} (cached, returned as JSON 200) ---${NC}`);
      console.log(body);
      console.log(`${DIM}--- end ---${NC}`);
      console.log("");

      clearTimeout(timeout);
      return {
        status: 200,
        streamedText: body,
        hasUserNotFound: false,
        hasStartEvent: false,
        hasErrorEvent: false,
        completed: true,
      };
    }

    // -- SSE stream (202): generation in progress --
    if (
      res.status === 202 &&
      res.headers.get("content-type")?.includes("text/event-stream")
    ) {
      const reader = res.body?.getReader();
      const decoder = new TextDecoder();

      let raw = "";
      let streamedText = "";
      let hasUserNotFound = false;
      let hasStartEvent = false;
      let hasErrorEvent = false;
      let completed = false;

      console.log("");
      console.log(`${DIM}--- ${label} (streaming SSE 202) ---${NC}`);

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          const chunk = decoder.decode(value, { stream: true });
          raw += chunk;

          // Parse SSE frames from the accumulated buffer
          const lines = raw.split("\n");
          // Keep the last potentially incomplete line in the buffer
          raw = lines.pop() ?? "";

          let currentEvent = "";
          for (const line of lines) {
            if (line.startsWith("event:")) {
              currentEvent = line.slice(6).trim();

              if (currentEvent === "start") {
                hasStartEvent = true;
                process.stdout.write(`${DIM}[${currentEvent}]${NC} `);
              } else if (currentEvent === "heartbeat") {
                // silent
              } else if (
                currentEvent === "complete" ||
                currentEvent === "end"
              ) {
                completed = true;
                // print newline after streamed text, then event tag
                process.stdout.write(`\n${DIM}[${currentEvent}]${NC}\n`);
              } else if (currentEvent === "error") {
                hasErrorEvent = true;
                process.stdout.write(`\n${RED}[${currentEvent}]${NC} `);
              }
            } else if (line.startsWith("data:")) {
              const data = line.slice(5).trim();

              if (currentEvent === "delta") {
                // Extract the text field and print it live
                try {
                  const parsed = JSON.parse(data);
                  if (parsed.text) {
                    streamedText += parsed.text;
                    process.stdout.write(parsed.text);
                  }
                } catch {
                  // raw text delta
                  streamedText += data;
                  process.stdout.write(data);
                }
              } else if (currentEvent === "error") {
                if (data.includes("User not found")) {
                  hasUserNotFound = true;
                }
                process.stdout.write(`${RED}${data}${NC}`);
              } else if (currentEvent === "complete") {
                // Try to extract the reading body from the complete event
                try {
                  const parsed = JSON.parse(data);
                  const entry = parsed.entry;
                  if (entry?.readingBody && !streamedText) {
                    streamedText = entry.readingBody;
                    process.stdout.write(entry.readingBody);
                  } else if (entry?.writingPrompt && !streamedText) {
                    streamedText = entry.writingPrompt;
                    process.stdout.write(entry.writingPrompt);
                  }
                } catch {
                  // ignore
                }
              }
            }
          }

          // Stop reading after terminal event
          if (completed || hasErrorEvent) {
            reader.cancel();
            break;
          }
        }
      }

      console.log(`${DIM}--- end ---${NC}`);
      console.log("");

      clearTimeout(timeout);
      return {
        status: 202,
        streamedText,
        hasUserNotFound,
        hasStartEvent,
        hasErrorEvent,
        completed,
      };
    }

    // -- Unexpected status --
    const body = await res.text();
    clearTimeout(timeout);
    return {
      status: res.status,
      streamedText: body,
      hasUserNotFound: body.includes("User not found"),
      hasStartEvent: false,
      hasErrorEvent: false,
      completed: false,
    };
  } catch (err: unknown) {
    clearTimeout(timeout);
    if (err instanceof Error && err.name === "AbortError") {
      console.log(
        `\n${YELLOW}[timeout after ${STREAM_TIMEOUT_MS / 1000}s]${NC}`
      );
      return {
        status: 0,
        streamedText: "",
        hasUserNotFound: false,
        hasStartEvent: false,
        hasErrorEvent: false,
        completed: false,
      };
    }
    throw err;
  }
}

// ==========================================================================

async function main() {
  console.log(`\nTesting against: ${BASE_URL}\n`);

  // ========================================================================
  // Test 1: Baseline — auth + sync
  // ========================================================================
  log("Test 1: Baseline — /api/auth + /api/sync returns non-null user");

  const deviceA = randomDeviceId();
  log(`  Device A: ${deviceA}`);

  const { token: tokenA } = await authAndGetToken(deviceA);
  if (!tokenA) {
    FAIL("Could not obtain token for device A");
  } else {
    ok("Authenticated device A via /api/auth");
  }

  const syncA = await callSync(tokenA, { user: { currentStreak: 0 } });
  const userA = syncA.data.user as Record<string, unknown> | null;

  if (syncA.status !== 200) {
    FAIL(`Sync returned status ${syncA.status} (expected 200)`);
  } else if (!userA || !userA.id) {
    FAIL(
      `Sync returned null/empty user. Response: ${JSON.stringify(syncA.data)}`
    );
  } else {
    ok(`Sync returned user.id=${userA.id}`);
  }

  // ========================================================================
  // Test 2: Missing user — sync auto-creates
  // ========================================================================
  log("");
  log(
    "Test 2: Missing user — JWT for non-existent user, /api/sync auto-creates"
  );

  const deviceC = randomDeviceId();
  log(`  Device C (no DB row): ${deviceC}`);

  const tokenC = await signTokenFor(deviceC);
  log("  Signed JWT directly (user does NOT exist in DB)");

  const syncC = await callSync(tokenC, { user: { currentStreak: 1 } });
  const userC = syncC.data.user as Record<string, unknown> | null;

  if (syncC.status !== 200) {
    FAIL(
      `Sync returned status ${syncC.status}. Body: ${JSON.stringify(syncC.data)}`
    );
  } else if (!userC || !userC.id) {
    FAIL(
      `Sync returned null user (ensureUser did NOT create). Response: ${JSON.stringify(syncC.data)}`
    );
  } else {
    ok(`Sync auto-created user and returned user.id=${userC.id}`);
  }
  log(`  currentDayIndex=${syncC.data.currentDayIndex}`);

  // ========================================================================
  // Test 3: Missing user — stream reading live
  // ========================================================================
  log("");
  log("Test 3: Missing user — /api/readings/generate/stream (live output)");

  const deviceD = randomDeviceId();
  log(`  Device D (no DB row): ${deviceD}`);
  const tokenD = await signTokenFor(deviceD);

  log("  Streaming reading...");
  const reading = await streamToConsole(
    "/api/readings/generate/stream",
    tokenD,
    "Reading"
  );

  if (reading.status === 200) {
    ok("Reading returned 200 (cached)");
  } else if (reading.status === 202) {
    if (reading.hasUserNotFound) {
      FAIL("Reading stream emitted 'User not found' (ensureUser did not run)");
    } else if (reading.hasErrorEvent) {
      FAIL("Reading stream emitted an error event");
    } else if (reading.completed) {
      ok(
        `Reading streamed successfully (${reading.streamedText.length} chars)`
      );
    } else if (reading.hasStartEvent) {
      ok("Reading generation started (stream opened, still generating)");
    } else {
      warn("Reading returned 202 but no recognizable events");
    }
  } else if (reading.status === 0) {
    warn("Reading request timed out");
  } else {
    FAIL(`Reading returned HTTP ${reading.status}`);
  }

  // ========================================================================
  // Test 4: Missing user — stream prompt live
  // ========================================================================
  log("");
  log("Test 4: Missing user — /api/prompts/generate/stream (live output)");

  const deviceE = randomDeviceId();
  log(`  Device E (no DB row): ${deviceE}`);
  const tokenE = await signTokenFor(deviceE);

  log("  Streaming prompt...");
  const prompt = await streamToConsole(
    "/api/prompts/generate/stream",
    tokenE,
    "Prompt"
  );

  if (prompt.status === 200) {
    ok("Prompt returned 200 (cached)");
  } else if (prompt.status === 202) {
    if (prompt.hasUserNotFound) {
      FAIL("Prompt stream emitted 'User not found' (ensureUser did not run)");
    } else if (prompt.hasErrorEvent) {
      FAIL("Prompt stream emitted an error event");
    } else if (prompt.completed) {
      ok(`Prompt streamed successfully (${prompt.streamedText.length} chars)`);
    } else if (prompt.hasStartEvent) {
      ok("Prompt generation started (stream opened, still generating)");
    } else {
      warn("Prompt returned 202 but no recognizable events");
    }
  } else if (prompt.status === 0) {
    warn("Prompt request timed out");
  } else {
    FAIL(`Prompt returned HTTP ${prompt.status}`);
  }

  // ========================================================================
  // Test 5: Sync with entries (FK constraint)
  // ========================================================================
  log("");
  log(
    "Test 5: Sync with entries for a fresh user (FK constraint must not fail)"
  );

  const deviceF = randomDeviceId();
  log(`  Device F (no DB row): ${deviceF}`);
  const tokenF = await signTokenFor(deviceF);
  const today = new Date().toISOString().split("T")[0];

  const syncF = await callSync(tokenF, {
    user: { currentStreak: 0 },
    entries: [
      {
        dayIndex: 0,
        calendarDate: today,
        readingCompleted: false,
        writingCompleted: false,
      },
    ],
  });

  const syncFErr = syncF.data.error as string | undefined;
  const userF = syncF.data.user as Record<string, unknown> | null;
  const entriesF = syncF.data.entries as unknown[] | undefined;

  if (syncF.status !== 200) {
    FAIL(
      `Sync with entries returned status ${syncF.status}. Body: ${JSON.stringify(syncF.data)}`
    );
  } else if (syncFErr) {
    FAIL(
      `Sync with entries returned error: ${syncFErr} (FK constraint likely failed)`
    );
  } else if (!userF || !userF.id) {
    FAIL(
      `Sync with entries returned null user. Response: ${JSON.stringify(syncF.data)}`
    );
  } else {
    ok(
      `Sync with entries succeeded for auto-created user (user.id=${userF.id})`
    );
    log(`  entries returned: ${entriesF?.length ?? "?"}`);
  }

  // ========================================================================
  // Summary
  // ========================================================================
  console.log("");
  console.log("===========================================");
  console.log(
    `  Results: ${GREEN}${pass} passed${NC}, ${RED}${fail} failed${NC}`
  );
  console.log("===========================================");

  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error("Test script crashed:", err);
  process.exit(2);
});
