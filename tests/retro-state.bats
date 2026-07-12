#!/usr/bin/env bats
# Tests for hooks/retro-state.sh (C2) — the single owner of the retrospect
# state file and the single trusted read path for the retrospect config.
# Fixtures follow the plan's C11 discipline: config fixtures are DERIVED
# from the C5 schema (jq -nc), never touching real $HOME state (RETRO_CONFIG
# / RETRO_STATE env overrides), and every time-dependent case is pinned via
# RETRO_NOW (epoch seconds) — no test depends on the host's real clock.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/retro-state.sh"

# Anchor clock: 2025-07-12T06:00:00Z. Chosen so `_today` (date-granularity)
# has a stable, easy-to-reason-about value across the suite.
NOW=1752300000
TODAY="2025-07-12"

# Always separate stderr from stdout so JSON-parsing assertions on $output
# never trip over a stderr note (e.g. trust-gate / corrupt-state warnings).
run_state() {
  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" "$@"
}

# jq's `todate` on an epoch seconds value — same primitive retro-state.sh
# uses internally, so fixtures and assertions share one source of truth.
iso_of() { jq -nr --argjson n "$1" '$n | todate'; }

setup() {
  CONFIG="$BATS_TEST_TMPDIR/retrospect.config.json"
  STATE="$BATS_TEST_TMPDIR/state/retrospect.json"
  mkdir -p "$BATS_TEST_TMPDIR/state"
}

# Full C5-shaped config: artifacts enabled with 2 repos, github enabled
# with an owner/repo, transcripts and scout present (scout has urls).
write_full_config() {
  jq -nc \
    '{
      version: 1,
      prompt_sources: ["startup"],
      snooze_days: 3,
      correction_markers: ["\\bwrong\\b"],
      sources: {
        artifacts:   {enabled: true,  interval_days: 7,
                       repos: ["~/repos/sibling-a", "~/repos/sibling-b"],
                       glob: "docs/archive/review/*.md"},
        github:      {enabled: true,  interval_days: 7, repos: ["acme/widgets"]},
        transcripts: {enabled: true,  interval_days: 14, root: "~/.claude/projects",
                       allow_remote_llm: false},
        scout:       {enabled: true,  interval_days: 30,
                       urls: ["https://example.com/a", "https://example.com/b"]}
      }
    }' > "$CONFIG"
}

# ============================================================
# seed
# ============================================================

@test "seed: creates state with all four sources last_run=now (ISO from RETRO_NOW)" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  local want
  want=$(iso_of "$NOW")
  for s in artifacts github transcripts scout; do
    run jq -er --arg s "$s" --arg w "$want" '.sources[$s].last_run == $w' "$STATE"
    [ "$status" -eq 0 ]
  done
}

@test "seed: idempotent no-op over existing state without --high-water" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before after
  before=$(jq -c . "$STATE")
  run_state seed
  [ "$status" -eq 0 ]
  after=$(jq -c . "$STATE")
  [ "$before" = "$after" ]
}

@test "seed: --high-water over existing state applies only high_water, preserves last_run" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local last_run_before
  last_run_before=$(jq -r '.sources.artifacts.last_run' "$STATE")

  run_state seed --high-water artifacts=2026-07-01
  [ "$status" -eq 0 ]

  run jq -r '.sources.artifacts.last_run' "$STATE"
  [ "$output" = "$last_run_before" ]
}

@test "seed: --high-water artifacts expands scalar to object keyed by BOTH configured repos" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state seed --high-water artifacts=2026-07-01
  [ "$status" -eq 0 ]

  run jq -e '.sources.artifacts.high_water | type == "object"' "$STATE"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water | has("~/repos/sibling-a")' "$STATE"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water | has("~/repos/sibling-b")' "$STATE"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water["~/repos/sibling-a"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water["~/repos/sibling-b"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

@test "seed: --high-water github expands scalar to object keyed by configured repo (config-string verbatim)" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state seed --high-water github=2026-07-01
  [ "$status" -eq 0 ]

  run jq -e '.sources.github.high_water | type == "object"' "$STATE"
  [ "$status" -eq 0 ]
  run jq -e '.sources.github.high_water["acme/widgets"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

@test "seed: --high-water transcripts stays scalar" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state seed --high-water transcripts=2026-07-01
  [ "$status" -eq 0 ]

  run jq -e '.sources.transcripts.high_water | type == "string"' "$STATE"
  [ "$status" -eq 0 ]
  run jq -r '.sources.transcripts.high_water' "$STATE"
  [ "$output" = "2026-07-01T00:00:00Z" ]
}

@test "seed: scout=<value> is rejected with exit 2" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state seed --high-water scout=2026-07-01
  [ "$status" -eq 2 ]
}

@test "seed: bad high-water value (not ISO) exits 1 and state file is byte-identical" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before after
  before=$(cat "$STATE")

  run_state seed --high-water artifacts=not-a-date
  [ "$status" -eq 1 ]

  after=$(cat "$STATE")
  [ "$before" = "$after" ]
}

# ============================================================
# due
# ============================================================

@test "due: --json emits an array" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e 'type == "array"' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: exact interval boundary (now - last_run == interval_days*86400) is due" {
  write_full_config
  # artifacts interval_days=7 -> 604800s. Seed at NOW - 604800 so the
  # boundary is exact.
  local seed_now=$((NOW - 7 * 86400))
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" seed
  [ "$status" -eq 0 ]

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) != null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: one second less than the interval boundary is not due" {
  write_full_config
  local seed_now=$((NOW - 7 * 86400 + 1))
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" seed
  [ "$status" -eq 0 ]

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) == null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: snoozed source excluded until snoozed_until passes" {
  write_full_config
  # artifacts interval_days=7; seed 10 days before NOW so the interval is
  # already elapsed by the time the snooze window (3 days) also expires.
  local seed_now=$((NOW - 10 * 86400))
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" seed
  [ "$status" -eq 0 ]

  # Snooze artifacts for 3 days, evaluated at seed_now.
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" snooze artifacts 3
  [ "$status" -eq 0 ]

  # Still within the snooze window: not due, even though the interval has
  # already elapsed.
  local mid=$((seed_now + 86400))
  RETRO_NOW="$mid" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) == null' <<<"$output"
  [ "$status" -eq 0 ]

  # After both the snooze window (3 days) and the interval (7 days) have
  # elapsed: due again.
  local later=$((seed_now + 8 * 86400))
  RETRO_NOW="$later" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) != null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: enabled source missing from state entry is due" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  # Strip the artifacts entry entirely.
  jq -c 'del(.sources.artifacts)' "$STATE" > "$BATS_TEST_TMPDIR/state/tmp.json"
  mv "$BATS_TEST_TMPDIR/state/tmp.json" "$STATE"

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) != null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: state file entirely absent means all enabled sources are due" {
  write_full_config
  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '(. | sort) == (["artifacts","github","transcripts","scout"] | sort)' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: config absent yields [] with --json" {
  run_state due --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "due: disabled source is never due" {
  jq -nc \
    '{version: 1, sources: {
        artifacts: {enabled: false, interval_days: 7, repos: []}
      }}' > "$CONFIG"
  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) == null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: --prompt-guard yields [] when last_prompted == today(RETRO_NOW)" {
  write_full_config
  local seed_now=$((NOW - 30 * 86400))
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" seed
  [ "$status" -eq 0 ]
  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" mark-prompted
  [ "$status" -eq 0 ]

  run_state due --json --prompt-guard
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "due: plain due (no --prompt-guard) is unaffected by last_prompted" {
  write_full_config
  local seed_now=$((NOW - 30 * 86400))
  RETRO_NOW="$seed_now" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" seed
  [ "$status" -eq 0 ]
  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" mark-prompted
  [ "$status" -eq 0 ]

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '. as $a | ($a | index("artifacts")) != null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "due: unknown source keys in config are dropped from due --json, with stderr note" {
  jq -nc \
    '{version: 1, sources: {
        artifacts: {enabled: true, interval_days: 7, repos: []},
        evil:      {enabled: true, interval_days: 0, repos: []}
      }}' > "$CONFIG"
  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" due --json
  [ "$status" -eq 0 ]
  local captured_stderr="$stderr"
  run jq -e '. as $a | ($a | index("evil")) == null' <<<"$output"
  [ "$status" -eq 0 ]
  [[ "$captured_stderr" == *"evil"* ]]
}

@test "due: unknown source keys in config are dropped from config --json, with stderr note" {
  jq -nc \
    '{version: 1, sources: {
        artifacts: {enabled: true, interval_days: 7, repos: []},
        evil:      {enabled: true, interval_days: 0, repos: []}
      }}' > "$CONFIG"
  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" config --json
  [ "$status" -eq 0 ]
  local captured_stderr="$stderr"
  run jq -e '.sources | has("evil") | not' <<<"$output"
  [ "$status" -eq 0 ]
  [[ "$captured_stderr" == *"evil"* ]]
}

# ============================================================
# mark-prompted
# ============================================================

@test "mark-prompted: sets last_prompted to today derived from RETRO_NOW" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state mark-prompted
  [ "$status" -eq 0 ]
  run jq -r '.last_prompted' "$STATE"
  [ "$output" = "$TODAY" ]
}

# ============================================================
# mark-run
# ============================================================

@test "mark-run: sets last_run and creates a missing entry" {
  write_full_config
  # No seed — state file entirely absent.
  run_state mark-run artifacts
  [ "$status" -eq 0 ]
  run jq -r '.sources.artifacts.last_run' "$STATE"
  [ "$output" = "$(iso_of "$NOW")" ]
}

@test "mark-run: --high-water-file with valid artifacts shape (object keyed by configured repos) is accepted" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"~/repos/sibling-a": "2026-07-01T00:00:00Z", "~/repos/sibling-b": "2026-07-02T00:00:00Z"}' > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water["~/repos/sibling-a"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

@test "mark-run: --high-water-file with valid github shape (owner/repo keys) is accepted" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"acme/widgets": "2026-07-01T00:00:00Z"}' > "$hwfile"

  run_state mark-run github --high-water-file "$hwfile"
  [ "$status" -eq 0 ]
  run jq -e '.sources.github.high_water["acme/widgets"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

@test "mark-run: --high-water-file with valid transcripts shape (ISO string) is accepted" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '"2026-07-01T00:00:00Z"' > "$hwfile"

  run_state mark-run transcripts --high-water-file "$hwfile"
  [ "$status" -eq 0 ]
  run jq -e '.sources.transcripts.high_water == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

@test "mark-run: --high-water-file with valid scout shape (url keys, 64-hex values) is accepted" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  local hash64
  hash64=$(printf 'a%.0s' {1..64})
  jq -nc --arg h "$hash64" '{"https://example.com/a": $h}' > "$hwfile"

  run_state mark-run scout --high-water-file "$hwfile"
  [ "$status" -eq 0 ]
  run jq -e --arg h "$hash64" '.sources.scout.high_water["https://example.com/a"] == $h' "$STATE"
  [ "$status" -eq 0 ]
}

@test "mark-run: invalid JSON high-water file is rejected, exit 1, state untouched" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before
  before=$(cat "$STATE")
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  printf '{not valid json' > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ]
}

@test "mark-run: bad ISO value in high-water file is rejected, exit 1, state untouched" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before
  before=$(cat "$STATE")
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"~/repos/sibling-a": "not-a-date"}' > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ]
}

@test "mark-run: artifacts key not in configured repos is rejected, exit 1, state untouched" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before
  before=$(cat "$STATE")
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"~/repos/not-configured": "2026-07-01T00:00:00Z"}' > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ]
}

@test "mark-run: scout value not 64-hex is rejected, exit 1, state untouched" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local before
  before=$(cat "$STATE")
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"https://example.com/a": "nothex"}' > "$hwfile"

  run_state mark-run scout --high-water-file "$hwfile"
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ]
}

@test "mark-run: unknown source exits 2" {
  write_full_config
  run_state mark-run nonexistent-source
  [ "$status" -eq 2 ]
}

@test "F-10: config string (tilde form) round-trips verbatim from config through seed high-water to mark-run high-water-file" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state seed --high-water artifacts=2026-07-01
  [ "$status" -eq 0 ]

  # Emulate the prescreen->mark-run hand-off: read the high_water object
  # produced by seed (keyed by the verbatim config string) and feed it
  # straight back through mark-run --high-water-file.
  local hwfile="$BATS_TEST_TMPDIR/hw-roundtrip.json"
  jq -c '.sources.artifacts.high_water' "$STATE" > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 0 ]
  run jq -e '.sources.artifacts.high_water["~/repos/sibling-a"] == "2026-07-01T00:00:00Z"' "$STATE"
  [ "$status" -eq 0 ]
}

# ============================================================
# snooze
# ============================================================

@test "snooze: sets snoozed_until = now + days*86400 (explicit days)" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state snooze artifacts 5
  [ "$status" -eq 0 ]
  run jq -r '.sources.artifacts.snoozed_until' "$STATE"
  [ "$output" = "$(iso_of "$((NOW + 5 * 86400))")" ]
}

@test "snooze: default days come from config snooze_days when not given" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state snooze artifacts
  [ "$status" -eq 0 ]
  # write_full_config sets snooze_days: 3
  run jq -r '.sources.artifacts.snoozed_until' "$STATE"
  [ "$output" = "$(iso_of "$((NOW + 3 * 86400))")" ]
}

@test "snooze: default days fall back to 3 when config has no snooze_days" {
  jq -nc '{version: 1, sources: {artifacts: {enabled: true, interval_days: 7, repos: []}}}' > "$CONFIG"
  run_state seed
  [ "$status" -eq 0 ]
  run_state snooze artifacts
  [ "$status" -eq 0 ]
  run jq -r '.sources.artifacts.snoozed_until' "$STATE"
  [ "$output" = "$(iso_of "$((NOW + 3 * 86400))")" ]
}

@test "snooze: non-numeric days exits 2" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state snooze artifacts abc
  [ "$status" -eq 2 ]
}

# ============================================================
# show / config
# ============================================================

@test "show --json emits raw state" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  run_state show --json
  [ "$status" -eq 0 ]
  run jq -e '.version == 1' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "config --json passes the trust gate for a regular, non-symlink, user-owned file" {
  write_full_config
  run_state config --json
  [ "$status" -eq 0 ]
  run jq -e '.version == 1' <<<"$output"
  [ "$status" -eq 0 ]
}

# ============================================================
# trusted-file refusals — each treated as absent
# ============================================================

@test "trust: symlinked state file is treated as absent (due behaves as absent-state)" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local real="$BATS_TEST_TMPDIR/state/real-state.json"
  mv "$STATE" "$real"
  ln -s "$real" "$STATE"

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '(. | sort) == (["artifacts","github","transcripts","scout"] | sort)' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "trust: symlinked config file yields empty config --json" {
  write_full_config
  local real="$BATS_TEST_TMPDIR/real-config.json"
  mv "$CONFIG" "$real"
  ln -s "$real" "$CONFIG"

  run_state config --json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "trust: FIFO state file is treated as absent (verified without blocking)" {
  write_full_config
  mkfifo "$STATE"

  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" \
    run --separate-stderr timeout 5 bash "$SCRIPT" due --json
  [ "$status" -eq 0 ]
  run jq -e '(. | sort) == (["artifacts","github","transcripts","scout"] | sort)' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "trust: directory as state file is treated as absent" {
  write_full_config
  rm -rf "$STATE"
  mkdir -p "$STATE"

  run_state due --json
  [ "$status" -eq 0 ]
  run jq -e '(. | sort) == (["artifacts","github","transcripts","scout"] | sort)' <<<"$output"
  [ "$status" -eq 0 ]
}

# ============================================================
# corrupt state
# ============================================================

@test "corrupt state: invalid JSON is quarantined and reseeded, exit 0, stderr note" {
  write_full_config
  mkdir -p "$(dirname "$STATE")"
  printf '{not valid json' > "$STATE"

  RETRO_NOW="$NOW" RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" run --separate-stderr bash "$SCRIPT" show --json
  [ "$status" -eq 0 ]
  local captured_stderr="$stderr"
  run jq -e '.version == 1' <<<"$output"
  [ "$status" -eq 0 ]
  [[ "$captured_stderr" == *"corrupt"* ]]

  # Quarantine file exists alongside the state file.
  local quarantine_count
  quarantine_count=$(find "$(dirname "$STATE")" -maxdepth 1 -name "$(basename "$STATE").corrupt.*" | wc -l)
  [ "$quarantine_count" -ge 1 ]
}

# ============================================================
# atomicity smoke
# ============================================================

@test "atomicity: after a failed mark-run validation, state file still parses with jq" {
  write_full_config
  run_state seed
  [ "$status" -eq 0 ]
  local hwfile="$BATS_TEST_TMPDIR/hw.json"
  jq -nc '{"~/repos/sibling-a": "not-a-date"}' > "$hwfile"

  run_state mark-run artifacts --high-water-file "$hwfile"
  [ "$status" -eq 1 ]

  run jq -e . "$STATE"
  [ "$status" -eq 0 ]
}
