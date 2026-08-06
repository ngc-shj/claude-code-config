#!/usr/bin/env bats
# The status line's job here is not decoration: it is the only local surface
# that carries the plan's rate-limit percentages with decimals, so what it
# LOGS is the thing under test.

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/statusline-usage.sh"
  export CLAUDE_USAGE_LOG="$BATS_TEST_TMPDIR/usage-log.jsonl"
}

# Writes a realistic payload — including the fields that must NOT be logged —
# to a file, and echoes the path. A file rather than a function so it survives
# `run bash -c`, which does not inherit shell functions.
payload() {
  local f="$BATS_TEST_TMPDIR/payload.json"
  cat > "$f" <<JSON
{
  "session_id": "SECRET-SESSION-c0ffee",
  "transcript_path": "/home/someone/.claude/projects/SECRET-PROJECT/x.jsonl",
  "cwd": "/home/someone/work/SECRET-REPO",
  "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
  "workspace": {"current_dir": "/home/someone/work/SECRET-REPO"},
  "rate_limits": {
    "five_hour": {"used_percentage": ${1:-12.3}},
    "seven_day": {"used_percentage": ${2:-41.8}}
  }
}
JSON
  printf '%s' "$f"
}

@test "renders the model and both percentages" {
  run bash -c "bash '$SCRIPT' < '$(payload)'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" == *"5h 12.3%"* ]]
  [[ "$output" == *"7d 41.8%"* ]]
}

@test "logs the percentages, and ONLY the percentages" {
  bash "$SCRIPT" < "$(payload)" >/dev/null
  [ -f "$CLAUDE_USAGE_LOG" ]
  run cat "$CLAUDE_USAGE_LOG"
  [[ "$output" == *"12.3"* ]]
  [[ "$output" == *"41.8"* ]]

  # The privacy contract. Everything below is present in the payload and must
  # not reach the log; this is what makes the log safe to keep and to read.
  if grep -q 'SECRET-SESSION' "$CLAUDE_USAGE_LOG"; then false; fi
  if grep -q 'SECRET-PROJECT' "$CLAUDE_USAGE_LOG"; then false; fi
  if grep -q 'SECRET-REPO' "$CLAUDE_USAGE_LOG"; then false; fi
  if grep -q 'transcript_path' "$CLAUDE_USAGE_LOG"; then false; fi

  # Exactly the three keys, so a future edit that widens the record fails here.
  run jq -r 'keys | join(",")' "$CLAUDE_USAGE_LOG"
  [ "$output" = "at,five_hour,seven_day" ]
}

@test "an unchanged reading is not appended twice" {
  for _ in 1 2 3; do bash "$SCRIPT" < "$(payload)" >/dev/null; done
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "a changed reading appends a second line" {
  bash "$SCRIPT" < "$(payload 12.3 41.8)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.9 41.8)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
}

@test "a payload without rate_limits still renders and logs nothing" {
  echo '{"model":{"display_name":"Opus 5"},"cwd":"/tmp/x"}' | bash "$SCRIPT" > "$BATS_TEST_TMPDIR/out"
  run cat "$BATS_TEST_TMPDIR/out"
  [[ "$output" == *"Opus 5"* ]]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}

@test "rate_limits under an unexpected shape records the key names, not the values" {
  echo '{"model":{"display_name":"Opus 5"},"rate_limits":{"weekly":{"pct":77.7}}}' \
    | bash "$SCRIPT" >/dev/null
  [ -f "$CLAUDE_USAGE_LOG" ]
  run cat "$CLAUDE_USAGE_LOG"
  [[ "$output" == *"weekly"* ]]
  # the value must not be recorded — only the shape, so the schema can be fixed
  if grep -q '77.7' "$CLAUDE_USAGE_LOG"; then false; fi
}

@test "without jq it renders rather than leaving the status line blank" {
  # jq absent, coreutils present — the realistic failure. Emptying PATH would
  # remove `cat` too and test nothing about jq.
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  for c in cat date mkdir tail basename dirname; do
    ln -sf "$(command -v "$c")" "$bin/$c"
  done
  f="$(payload)"
  run env PATH="$bin" "$(command -v bash)" "$SCRIPT" < "$f"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}
