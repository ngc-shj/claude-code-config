#!/usr/bin/env bats
# Tests for hooks/session-retrospect-check.sh — SessionStart hook that
# surfaces a once-per-day prompt when retrospective mining is due.
#
# The hook is a pure pipe over hooks/retro-state.sh; these tests exercise
# the stdin/stdout contract only (config/state fixtures are pointed at via
# RETRO_CONFIG/RETRO_STATE, time is pinned via RETRO_NOW). Silent paths are
# asserted STRICTLY: `run --separate-stderr` + `[ -z "$output" ]` (empty
# stdout), not merely exit 0.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/session-retrospect-check.sh"
EXAMPLE_CONFIG="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/retrospect.config.json.example"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  CONFIG="$BATS_TEST_TMPDIR/config.json"
  STATE="$BATS_TEST_TMPDIR/state.json"
  export RETRO_CONFIG="$CONFIG"
  export RETRO_STATE="$STATE"
  export RETRO_NOW=1000000000
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# Config fixture DERIVED from retrospect.config.json.example (RT3 fixture
# discipline — schema drift breaks tests instead of hiding), jq-edited to
# make artifacts due immediately (interval_days 0). Falls back to a
# hand-built C5-schema document if the example is absent.
base_config() {
  if [ -f "$EXAMPLE_CONFIG" ]; then
    jq -c '.sources.artifacts.interval_days = 0' "$EXAMPLE_CONFIG"
  else
    jq -nc '{
      version: 1,
      prompt_sources: ["startup"],
      snooze_days: 3,
      sources: {
        artifacts:   {enabled: true,  interval_days: 0,  repos: ["~/sib"], glob: "*.md"},
        github:      {enabled: false, interval_days: 7,  repos: []},
        transcripts: {enabled: false, interval_days: 14, root: "~/.claude/projects"},
        scout:       {enabled: false, interval_days: 30, urls: []}
      }
    }'
  fi
}

write_config() {
  printf '%s' "$1" > "$CONFIG"
}

session_start_stdin() {
  local source="${1:-startup}"
  jq -nc --arg src "$source" \
    '{session_id:"abc", transcript_path:"/tmp/t.jsonl", cwd:"/tmp",
      hook_event_name:"SessionStart", source:$src}'
}

run_hook() {
  local source="${1:-startup}"
  run --separate-stderr bash -c "printf '%s' '$(session_start_stdin "$source")' | bash '$SCRIPT'"
}

# ============================================================
# Silent paths
# ============================================================

@test "silent: no config" {
  # CONFIG left unwritten (absent file).
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: not due (last_run fresh, interval_days not elapsed)" {
  write_config "$(base_config | jq '.sources.artifacts.interval_days = 7')"
  bash "$(dirname "$SCRIPT")/retro-state.sh" mark-run artifacts >/dev/null 2>&1
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: already prompted today" {
  write_config "$(base_config)"
  bash "$(dirname "$SCRIPT")/retro-state.sh" mark-prompted >/dev/null 2>&1
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: source=compact not in prompt_sources" {
  write_config "$(base_config)"
  run_hook compact
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: source=clear not in prompt_sources" {
  write_config "$(base_config)"
  run_hook clear
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: source=resume not in prompt_sources" {
  write_config "$(base_config)"
  run_hook resume
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: corrupt state JSON" {
  # interval_days > 0: quarantine-and-reseed sets last_run=now, so the
  # freshly reseeded source is NOT due — isolates "corrupt state" from
  # "due" (interval_days=0 would make every reseed due, masking this case).
  write_config "$(base_config | jq '.sources.artifacts.interval_days = 7')"
  printf '{not valid json' > "$STATE"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: hostile source key in config (unknown source name)" {
  cfg="$(base_config | jq '.sources.evil = {enabled: true, interval_days: 0}')"
  write_config "$cfg"
  run_hook
  [ "$status" -eq 0 ]
  # Either fully silent, or a sanitized prompt that never names "evil".
  [[ "$output" != *"evil"* ]]
}

# ============================================================
# Due path
# ============================================================

@test "due: artifacts due -> emits SessionStart additionalContext naming artifacts and snooze" {
  write_config "$(base_config)"
  run_hook
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"artifacts"* ]]
  [[ "$ctx" == *"snooze"* ]]
}

@test "due: second invocation same day is silent (mark-prompted took effect)" {
  write_config "$(base_config)"
  run_hook
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ============================================================
# Smoke
# ============================================================

@test "smoke: completes under timeout 5 with representative fixtures" {
  write_config "$(base_config)"
  run --separate-stderr bash -c "printf '%s' '$(session_start_stdin startup)' | timeout 5 bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}
