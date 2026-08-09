#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/hooks/claude-usage-poll.sh"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_HOME/.claude/state" "$STUB_BIN"

  cat > "$TEST_HOME/.claude/.credentials.json" <<'JSON'
{"claudeAiOauth":{"accessToken":"fake-oauth-token"}}
JSON
  chmod 600 "$TEST_HOME/.claude/.credentials.json"

  cat > "$STUB_BIN/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_STUB_ARGS"
config="$(cat)"
printf '%s\n' "$config" > "$CURL_STUB_CONFIG"

header_file=""
body_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dump-header) header_file="$2"; shift 2 ;;
    --output) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done

printf '%s' "${CURL_STUB_HEADERS:-}" > "$header_file"
printf '%s' "${CURL_STUB_BODY:-}" > "$body_file"
printf '%s' "${CURL_STUB_STATUS:-200}"
exit "${CURL_STUB_RC:-0}"
SH
  chmod +x "$STUB_BIN/curl"

  export HOME="$TEST_HOME"
  export PATH="$STUB_BIN:$PATH"
  export CLAUDE_USAGE_LOG="$BATS_TEST_TMPDIR/usage-log.jsonl"
  export CLAUDE_USAGE_CREDENTIALS="$TEST_HOME/.claude/.credentials.json"
  export CLAUDE_USAGE_STATUSLINE="$REPO_ROOT/hooks/statusline-usage.sh"
  export CLAUDE_USAGE_BACKOFF_FILE="$TEST_HOME/.claude/state/not-before"
  export CLAUDE_USAGE_POLL_LOCK="$TEST_HOME/.claude/state/poll.lock"
  export CLAUDE_USAGE_API_URL="https://api.example.test/api/oauth/usage"
  export CURL_STUB_ARGS="$BATS_TEST_TMPDIR/curl-args"
  export CURL_STUB_CONFIG="$BATS_TEST_TMPDIR/curl-config"
  export CURL_STUB_STATUS=200
  export CURL_STUB_HEADERS=$'HTTP/1.1 200 OK\r\n\r\n'
  export CURL_STUB_BODY='{
    "five_hour":{"utilization":12.5,"resets_at":"2026-08-08T21:00:00.997589+00:00"},
    "seven_day":{"utilization":34,"resets_at":"2026-08-15T10:59:59.997613+00:00"}
  }'
  unset CURL_STUB_RC
}

mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

@test "poller converts the internal API response and records both windows" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run jq -e '
    .five_hour.used_percentage == 12.5
    and .five_hour.resets_at == ("2026-08-08T21:00:00Z" | fromdateiso8601)
    and .seven_day.used_percentage == 34
    and .seven_day.resets_at == ("2026-08-15T10:59:59Z" | fromdateiso8601)
  ' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$CLAUDE_USAGE_LOG")" = 600 ]
}

@test "OAuth token is passed on curl stdin, not argv or diagnostic output" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(cat "$CURL_STUB_CONFIG")" == *"Authorization: Bearer fake-oauth-token"* ]]
  [[ "$(cat "$CURL_STUB_ARGS")" != *"fake-oauth-token"* ]]
  [[ "$output" != *"fake-oauth-token"* ]]
  ! grep -q 'fake-oauth-token' "$CLAUDE_USAGE_LOG"
}

@test "unchanged API readings are polled but not appended twice" {
  bash "$SCRIPT"
  bash "$SCRIPT"

  [ "$(wc -l < "$CLAUDE_USAGE_LOG" | tr -d ' ')" = 1 ]
  [ "$(wc -l < "$CURL_STUB_ARGS" | tr -d ' ')" = 2 ]
}

@test "an out-of-range utilization fails closed" {
  export CURL_STUB_BODY='{"five_hour":{"utilization":101,"resets_at":"2026-08-08T21:00:00Z"}}'
  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected usage response schema"* ]]
  [ ! -e "$CLAUDE_USAGE_LOG" ]
}

@test "an unknown response schema is not written" {
  export CURL_STUB_BODY='{"five_hour":{"used_percentage":12.5,"resets_at":1786222800}}'
  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected usage response schema"* ]]
  [ ! -e "$CLAUDE_USAGE_LOG" ]
}

@test "authentication failures are visible without leaking the token" {
  export CURL_STUB_STATUS=401
  export CURL_STUB_HEADERS=$'HTTP/1.1 401 Unauthorized\r\n\r\n'
  export CURL_STUB_BODY='{"error":"unauthorized"}'
  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"OAuth authentication failed"* ]]
  [[ "$output" != *"fake-oauth-token"* ]]
  [ ! -e "$CLAUDE_USAGE_LOG" ]
}

@test "HTTP 429 enforces a five-minute minimum backoff" {
  export CURL_STUB_STATUS=429
  export CURL_STUB_HEADERS=$'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 120\r\n\r\n'
  export CURL_STUB_BODY='{}'
  before="$(date +%s)"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backing off for 300s"* ]]
  not_before="$(cat "$CLAUDE_USAGE_BACKOFF_FILE")"
  [ "$not_before" -ge "$((before + 300))" ]

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_STUB_ARGS" | tr -d ' ')" = 1 ]
  [ ! -e "$CLAUDE_USAGE_LOG" ]
}

# The floor test above cannot see whether Retry-After was parsed at all: 120 and
# an unparsed header both come out as 300. Only a value ABOVE the floor can tell
# them apart, which is why the header parse went unnoticed while it was broken.
@test "HTTP 429 honours a server backoff longer than the floor" {
  export CURL_STUB_STATUS=429
  export CURL_STUB_HEADERS=$'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 900\r\n\r\n'
  export CURL_STUB_BODY='{}'
  before="$(date +%s)"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backing off for 900s"* ]]
  not_before="$(cat "$CLAUDE_USAGE_BACKOFF_FILE")"
  [ "$not_before" -ge "$((before + 900))" ]
}

@test "HTTP 429 with a header the parse cannot read falls back to the floor" {
  export CURL_STUB_STATUS=429
  export CURL_STUB_HEADERS=$'HTTP/1.1 429 Too Many Requests\r\nRetry-After: Wed, 21 Oct 2026 07:28:00 GMT\r\n\r\n'
  export CURL_STUB_BODY='{}'
  before="$(date +%s)"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backing off for 300s"* ]]
  not_before="$(cat "$CLAUDE_USAGE_BACKOFF_FILE")"
  [ "$not_before" -ge "$((before + 300))" ]
}

@test "transport failure writes no API body or usage record" {
  export CURL_STUB_RC=28
  export CURL_STUB_BODY='{"access_token":"must-not-be-printed"}'
  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"request failed"* ]]
  [[ "$output" != *"must-not-be-printed"* ]]
  [ ! -e "$CLAUDE_USAGE_LOG" ]
}
