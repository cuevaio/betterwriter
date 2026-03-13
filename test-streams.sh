#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
DEVICE_ID="${DEVICE_ID:-dev-user-123}"
POST_MAX_TIME="${POST_MAX_TIME:-90}"
STREAM_WAIT_SECS="${STREAM_WAIT_SECS:-120}"

# ------------------------------------------------------------------
# Obtain a signed JWT from /api/auth
# ------------------------------------------------------------------
echo "== Authenticating device: $DEVICE_ID =="
AUTH_RESPONSE="$(curl -sS --max-time 10 -X POST \
  -H "Content-Type: application/json" \
  -d "{\"deviceId\":\"$DEVICE_ID\"}" \
  "$BASE_URL/api/auth")"

TOKEN="$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)"

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to obtain token. Response:"
  echo "$AUTH_RESPONSE"
  exit 1
fi
echo "Token obtained successfully."
echo ""

run_test() {
  local kind="$1"

  echo ""
  echo "== Testing /api/$kind/generate/stream =="

  local sse_log trigger_log
  sse_log="$(mktemp)"
  trigger_log="$(mktemp)"

  # Step 1: POST — server owns stream identity, no streamId in body.
  curl -sS --max-time "$POST_MAX_TIME" -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{}" \
    "$BASE_URL/api/$kind/generate/stream" \
    >"$trigger_log" 2>&1 || true

  echo "-- Trigger response --"
  cat "$trigger_log"
  echo ""

  # Check if the reading/prompt is already completed (no streaming needed).
  local mode
  mode="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))" <"$trigger_log" 2>/dev/null || true)"

  if [ "$mode" = "completed" ]; then
    echo "Mode: completed (data returned directly, no SSE needed)"
    rm -f "$sse_log" "$trigger_log"
    return
  fi

  echo "Mode: $mode"

  # Step 2: GET — no streamId query param; server looks up the active stream.
  curl -N -sS \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL/api/$kind/generate/stream" \
    >"$sse_log" 2>&1 &
  local sse_pid=$!

  echo "-- Live SSE events --"
  tail -n +1 -f "$sse_log" | while IFS= read -r line; do
    case "$line" in
      id:*|event:*|data:*)
        printf '%s\n' "$line"
        ;;
    esac
  done &
  local monitor_pid=$!

  local deadline=$((SECONDS + STREAM_WAIT_SECS))
  while (( SECONDS < deadline )); do
    if grep -Eq '^event: (complete|error)$' "$sse_log"; then
      break
    fi
    sleep 1
  done

  kill "$sse_pid" >/dev/null 2>&1 || true
  wait "$sse_pid" 2>/dev/null || true
  kill "$monitor_pid" >/dev/null 2>&1 || true
  wait "$monitor_pid" 2>/dev/null || true

  local delta_count terminal_count
  delta_count="$(grep -Ec '^event: delta$' "$sse_log" || true)"
  terminal_count="$(grep -Ec '^event: (complete|error)$' "$sse_log" || true)"
  echo ""
  echo "-- SSE summary --"
  echo "delta events: $delta_count"
  echo "terminal events: $terminal_count"
  if [ "${delta_count:-0}" -le 1 ]; then
    echo "note: <=1 delta often means replay/cached result or non-stream fallback path"
  fi

  if ! grep -Eq '^event: (complete|error)$' "$sse_log"; then
    echo ""
    echo "WARNING: no terminal event seen within ${STREAM_WAIT_SECS}s"
  fi

  rm -f "$sse_log" "$trigger_log"
}

run_test "readings"
run_test "prompts"

echo ""
echo "Done."
