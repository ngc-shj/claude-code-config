#!/usr/bin/env bats
# The status line's job here is not decoration: it is the only local surface
# carrying the plan's rate-limit percentages with decimals, so what it LOGS —
# and whether it admits when it could not log — is the thing under test.

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/statusline-usage.sh"
  export CLAUDE_USAGE_LOG="$BATS_TEST_TMPDIR/usage-log.jsonl"
}

# `stat -c` is GNU, `stat -f` is BSD. This repo targets both.
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# A payload carrying only the five-hour window, which the schema permits.
payload_one_window() {
  local f="$BATS_TEST_TMPDIR/payload-one.json"
  printf '{"model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":1786000000}}}\n' "$1" > "$f"
  printf '%s' "$f"
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
  run mode_of "$CLAUDE_USAGE_LOG"
  [ "$output" = "600" ]
}

@test "an existing world-readable log with an UNCHANGED reading is still tightened" {
  # umask governs creation only, and the unchanged and stale paths both return
  # before the append — so a chmod placed at the append never runs for them.
  bash "$SCRIPT" < "$(payload)" >/dev/null
  chmod 664 "$CLAUDE_USAGE_LOG"
  bash "$SCRIPT" < "$(payload)" >/dev/null
  run mode_of "$CLAUDE_USAGE_LOG"
  [ "$output" = "600" ]
}

@test "a reading that went backwards within the same window is dropped" {
  # A lock orders writes; it does not make a late-arriving old reading true.
  bash "$SCRIPT" < "$(payload 12.4 41.8)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.3 41.7)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "a reset boundary that goes backwards is dropped as stale" {
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1786400000)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1786000000)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "the same reset boundary rounded one second differently is canonicalized" {
  # The internal usage API has returned 10:59:59.997 where the status-line
  # payload reports the same weekly boundary as 11:00:00.
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1786400000)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.4 42.0 1785999999 1786399999)" >/dev/null

  run jq -s -e '
    .[1].five_hour.resets_at == 1786000000
    and .[1].seven_day.resets_at == 1786400000
    and .[1].five_hour.used_percentage == 12.4
    and .[1].seven_day.used_percentage == 42
  ' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
}

@test "a one-second reset representation difference does not permit usage to go backwards" {
  bash "$SCRIPT" < "$(payload 12.3 41.8 1786000000 1786400000)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.2 41.7 1785999999 1786399999)" >/dev/null

  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = 1 ]
}

@test "a drop across a genuine rollover is kept" {
  bash "$SCRIPT" < "$(payload 12.3 97.4 1786000000 1786400000)" >/dev/null
  bash "$SCRIPT" < "$(payload 12.3 2.1 1786000000 1787004800)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
}

@test "a window missing from the payload does not discard the window that is present" {
  # The fault this closes: judging both windows together threw away a valid
  # five-hour update whenever seven_day was absent or stale.
  bash "$SCRIPT" < "$(payload 12.0 41.0)" >/dev/null
  bash "$SCRIPT" < "$(payload_one_window 13.0)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
  run jq -s -r '.[1].seven_day' "$CLAUDE_USAGE_LOG"
  [ "$output" = "null" ]
}

@test "a stale window is nulled while the other window's advance is kept" {
  bash "$SCRIPT" < "$(payload 12.0 41.0)" >/dev/null
  bash "$SCRIPT" < "$(payload 13.0 40.0)" >/dev/null
  # numeric comparison: jq echoes 13.0 as written, so a string match on "13"
  # would be testing the input's formatting rather than the behaviour
  run jq -s -e '.[1] | (.five_hour.used_percentage == 13) and (.seven_day == null)' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
}

@test "a reading where every window is stale is not appended at all" {
  bash "$SCRIPT" < "$(payload 12.0 41.0)" >/dev/null
  bash "$SCRIPT" < "$(payload 11.0 40.0)" >/dev/null
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
}

@test "a stale window is rejected however long the history has grown" {
  # The guarantee must not depend on how far back the comparison looks: with a
  # bounded lookback, advancing one window past it let a stale reading of the
  # OTHER window through as new.
  bash "$SCRIPT" < "$(payload 1.0 50.0)" >/dev/null
  # The intervening lines must carry seven_day = null, or a bounded lookback
  # still finds the value repeated on every line and the test proves nothing.
  i=2
  while [ "$i" -le 25 ]; do
    bash "$SCRIPT" < "$(payload_one_window "$i.0")" >/dev/null
    i=$((i + 1))
  done
  run jq -s -e 'length >= 22 and (.[5].seven_day == null)' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
  before="$(wc -l < "$CLAUDE_USAGE_LOG")"
  bash "$SCRIPT" < "$(payload 26.0 40.0)" >/dev/null       # 7d went backwards
  run jq -s -e --argjson n "$before" '.[$n].seven_day == null' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
}

@test "a window with no resets_at is not recorded as valid" {
  # The header calls a missing field invalid; a percentage with a null boundary
  # would make every later comparison against it meaningless.
  printf '{"model":{"display_name":"O"},"rate_limits":{"five_hour":{"used_percentage":12.3},"seven_day":{"used_percentage":41.8,"resets_at":1786400000}}}\n' > "$BATS_TEST_TMPDIR/p2.json"
  bash "$SCRIPT" < "$BATS_TEST_TMPDIR/p2.json" >/dev/null
  run jq -s -e '.[0] | (.five_hour == null) and (.seven_day.used_percentage == 41.8)' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
}

@test "a healthy log with no state rebuilds its baseline correctly" {
  # The upgrade path: a log written before the state file existed must not lose
  # its history, or the first reading after the upgrade could go backwards.
  bash "$SCRIPT" < "$(payload 10.0 50.0)" >/dev/null
  bash "$SCRIPT" < "$(payload 20.0 60.0)" >/dev/null
  rm -f "$CLAUDE_USAGE_LOG.state"
  bash "$SCRIPT" < "$(payload 15.0 55.0)" >/dev/null    # backwards on both
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
  run head -n 1 "$CLAUDE_USAGE_LOG.state"
  [[ "$output" == *'"used_percentage":20'* ]]
}

@test "a state write that fails is reported, and repairs itself next render" {
  # Two files mean a consistency problem: a state left behind after the log
  # moved would judge the next reading against a value that is no longer the
  # latest, and the duplicate check would stop it ever being noticed.
  bash "$SCRIPT" < "$(payload 10.0 10.0)" >/dev/null
  # Block ONLY the state write: making the directory read-only would block the
  # log append too, and then the warning would prove nothing about the state.
  mkdir -p "$CLAUDE_USAGE_LOG.state.tmp"
  run bash "$SCRIPT" < "$(payload 20.0 20.0)"
  rmdir "$CLAUDE_USAGE_LOG.state.tmp"
  [[ "$output" == *"usage-log!"* ]]

  # Now a value that went backwards must still be rejected — the stale state is
  # detected by its log_tail no longer matching the log and is rebuilt.
  bash "$SCRIPT" < "$(payload 15.0 15.0)" >/dev/null
  run jq -s -e 'map(.five_hour.used_percentage) | index(15) == null' "$CLAUDE_USAGE_LOG"
  [ "$status" -eq 0 ]
}

@test "a state rebuild that fails over a non-empty log is fatal, not fail-open" {
  bash "$SCRIPT" < "$(payload 10.0 10.0)" >/dev/null
  printf 'this is not json\n' >> "$CLAUDE_USAGE_LOG"     # rebuild will fail
  rm -f "$CLAUDE_USAGE_LOG.state"                        # force a rebuild
  run bash "$SCRIPT" < "$(payload 5.0 5.0)"
  [[ "$output" == *"usage-log!"* ]]
  # jq -s over a file that contains the corrupt line would fail on the file,
  # not on the claim, so check the text directly.
  if grep -q '"used_percentage":5' "$CLAUDE_USAGE_LOG"; then false; fi
}

@test "the state file is tightened on the unchanged path too" {
  bash "$SCRIPT" < "$(payload)" >/dev/null
  chmod 664 "$CLAUDE_USAGE_LOG.state"
  bash "$SCRIPT" < "$(payload)" >/dev/null
  run mode_of "$CLAUDE_USAGE_LOG.state"
  [ "$output" = "600" ]
}

@test "an unobtainable lock fails closed and says so" {
  sleep 30 & live=$!
  mkdir -p "$CLAUDE_USAGE_LOG.lock"
  printf '%s\n' "$live" > "$CLAUDE_USAGE_LOG.lock/owner"
  run bash "$SCRIPT" < "$(payload)"
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
  rm -rf "$CLAUDE_USAGE_LOG.lock"
  [[ "$output" == *"usage-log!"* ]]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}

@test "a lock held by a LIVE process is never stolen" {
  # Age is not evidence of death, and neither is an unreadable owner file:
  # stealing on either basis broke a concurrency test under load.
  sleep 30 & live=$!
  mkdir -p "$CLAUDE_USAGE_LOG.lock"
  printf '%s\n' "$live" > "$CLAUDE_USAGE_LOG.lock/owner"
  run bash "$SCRIPT" < "$(payload)"
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
  rm -rf "$CLAUDE_USAGE_LOG.lock"
  [[ "$output" == *"usage-log!"* ]]
}

@test "a lock whose owner is gone is reclaimed" {
  mkdir -p "$CLAUDE_USAGE_LOG.lock"
  printf '999999\n' > "$CLAUDE_USAGE_LOG.lock/owner"
  run bash "$SCRIPT" < "$(payload)"
  [[ "$output" != *"usage-log!"* ]]
  [ -f "$CLAUDE_USAGE_LOG" ]
}

@test "concurrency holds without flock, which macOS does not ship" {
  bin="$BATS_TEST_TMPDIR/noflock"; mkdir -p "$bin"
  # deliberately WITHOUT seq: a plain macOS has none, and handing the test a
  # GNU coreutils seq made it pass while the real platform failed.
  # head and wc are needed to READ the state; without them the script rebuilds
  # on every render, so the test would pass while exercising a path macOS never
  # takes. Every command the script uses belongs here or the simulation is a
  # different simulation.
  for c in cat date mkdir tail head wc basename dirname jq chmod rm mv sleep stat kill; do
    [ -n "$(command -v "$c" || true)" ] && ln -sf "$(command -v "$c")" "$bin/$c"
  done
  [ ! -e "$bin/flock" ]
  f="$(payload)"
  n=0
  while [ "$n" -lt 40 ]; do
    env PATH="$bin" "$(command -v bash)" "$SCRIPT" < "$f" >/dev/null &
    n=$((n + 1))
  done
  wait
  run wc -l < "$CLAUDE_USAGE_LOG"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
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
  n=0
  while [ "$n" -lt 60 ]; do bash "$SCRIPT" < "$f" >/dev/null & n=$((n + 1)); done
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
  for c in cat date mkdir tail head wc basename dirname chmod rm mv sleep stat kill; do
    [ -n "$(command -v "$c" || true)" ] && ln -sf "$(command -v "$c")" "$bin/$c"
  done
  f="$(payload)"
  run env PATH="$bin" "$(command -v bash)" "$SCRIPT" < "$f"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -f "$CLAUDE_USAGE_LOG" ]
}
