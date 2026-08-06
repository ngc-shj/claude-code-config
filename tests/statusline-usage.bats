#!/usr/bin/env bats
# The status line's job here is not decoration: it is the only local surface
# carrying the plan's rate-limit percentages with decimals, so what it LOGS —
# and whether it admits when it could not log — is the thing under test.

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/statusline-usage.sh"
  export CLAUDE_USAGE_LOG="$BATS_TEST_TMPDIR/usage-log.jsonl"
}

# Writes a payload — including the fields that must NOT be logged — to a file
# and echoes the path. A file rather than a function so it survives `bash -c`.
# $1/$2 percentages, $3/$4 reset boundaries.
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
    "five_hour": {"used_percentage": ${1:-12.3}, "resets_at": ${3:-1786000000}},
    "seven_day": {"used_percentage": ${2:-41.8}, "resets_at": ${4:-1786400000}}
  }
}
JSON
  printf '%s' "$f"
}

@test "renders the model and both percentages" {
  run bash "$SCRIPT" < "$(payload)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" == *"5h 12.3%"* ]]
  [[ "$output" == *"7d 41.8%"* ]]
  [[ "$output" != *"usage-log!"* ]]
}

@test "logs the percentages AND their reset boundaries" {
  bash "$SCRIPT" < "$(payload)" >/dev/null
  run jq -c '[.five_hour.used_percentage, .five_hour.resets_at, .seven_day.used_percentage, .seven_day.resets_at]' "$CLAUDE_USAGE_LOG"
  [ "$output" = "[12.3,1786000000,41.8,1786400000]" ]
}

@test "logs ONLY the timestamp, percentages and resets" {
  bash "$SCRIPT" < "$(payload)" >/dev/null
  if grep -q 'SECRET-SESSION' "$CLAUDE_USAGE_LOG"; then false; fi
  if grep -q 'SECRET-PROJECT' "$CLAUDE_USAGE_LOG"; then false; fi
  if grep -q 'SECRET-REPO' "$CLAUDE_USAGE_LOG"; then false; fi
  run jq -r '[paths(scalars) | join(".")] | sort | join(",")' "$CLAUDE_USAGE_LOG"
  [ "$output" = "at,five_hour.resets_at,five_hour.used_percentage,seven_day.resets_at,seven_day.used_percentage" ]
}

@test "the log is not world-readable" {
  bash "$SCRIPT" < "$(payload)" >/dev/null
  run stat -c '%a' "$CLAUDE_USAGE_LOG"
  [ "$output" = "600" ]
}

@test "an unchanged reading is not appended twice" {
  for _ in 1 2 3; do bash "$SCRIPT" < "$(payload)" >/dev/null; done
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "a changed percentage appends" {
  bash "$SCRIPT" < "$(payload 12.3 41.8)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.9 41.8)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
}

@test "a window reset appends even when the percentage repeats" {
  # The failure this guards: after a rollover the figure can land on a value it
  # already held. Without resets_at in the comparison the transition is
  # invisible, and a later subtraction silently spans the boundary.
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1786400000)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1787004800)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
  run jq -s '[.[].seven_day.resets_at] | unique | length' "$CLAUDE_USAGE_LOG"
  [ "$output" = "2" ]
}

@test "concurrent renders of the same reading produce exactly one line" {
  # Measured before the lock existed: 100 parallel runs of one identical
  # payload wrote six lines.
  f="$(payload)"
  for _ in $(seq 60); do bash "$SCRIPT" < "$f" >/dev/null & done
  wait
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "a failed write is announced in the status line, not swallowed" {
  # The design fault this closes: a silent logging failure looks identical to
  # success, so the gap is discovered only after the batch is already spent.
  export CLAUDE_USAGE_LOG="$BATS_TEST_TMPDIR/nowrite/usage-log.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/nowrite"
  chmod 500 "$BATS_TEST_TMPDIR/nowrite"
  run bash "$SCRIPT" < "$(payload)"
  chmod 700 "$BATS_TEST_TMPDIR/nowrite"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" == *"usage-log!"* ]]
}

@test "a payload without rate_limits renders and logs nothing" {
  echo '{"model":{"display_name":"Opus 5"},"cwd":"/tmp/x"}' | bash "$SCRIPT" > "$BATS_TEST_TMPDIR/out"
  run cat "$BATS_TEST_TMPDIR/out"
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" != *"usage-log!"* ]]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}

@test "rate_limits under an unexpected shape records the key names, not the values" {
  echo '{"model":{"display_name":"Opus 5"},"rate_limits":{"weekly":{"pct":77.7}}}' \
    | bash "$SCRIPT" >/dev/null
  run cat "$CLAUDE_USAGE_LOG"
  [[ "$output" == *"weekly"* ]]
  if grep -q '77.7' "$CLAUDE_USAGE_LOG"; then false; fi
}

@test "without jq it renders rather than leaving the status line blank" {
  # jq absent, coreutils present — the realistic failure. Emptying PATH would
  # remove `cat` too and test nothing about jq.
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  for c in cat date mkdir tail basename dirname flock stat; do
    [ -n "$(command -v "$c" || true)" ] && ln -sf "$(command -v "$c")" "$bin/$c"
  done
  f="$(payload)"
  run env PATH="$bin" "$(command -v bash)" "$SCRIPT" < "$f"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}
