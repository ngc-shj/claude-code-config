#!/usr/bin/env bats
# Tests for hooks/retro-prescreen.sh (C4) — zero-Claude-token candidate
# discovery. Config/state are read exclusively through hooks/retro-state.sh
# (RETRO_CONFIG/RETRO_STATE env overrides — never touching real $HOME state).
# LLM seam: LLM_BACKEND pin + curl mock (tests/pre-review.bats /
# tests/openai-backend.bats patterns); _OPENAI_HOST_CACHE and
# XDG_RUNTIME_DIR/XDG_CACHE_HOME point into $BATS_TEST_TMPDIR so the 300s
# availability cache never crosses tests. gh is stubbed via a PATH-prepended
# script dispatching on $1.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/hooks/retro-prescreen.sh"
STATE_CLI="$REPO_ROOT/hooks/retro-state.sh"

NOW=1752300000   # 2025-07-12T06:00:00Z — arbitrary fixed anchor

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

run_prescreen() {
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" \
    run --separate-stderr bash "$SCRIPT" "$@"
  # Preserve the script's stdout/stderr in $DOC/$ERR so a test can run
  # multiple `jq` assertions without a later `run jq` clobbering $output and
  # $stderr (bats resets $output/$status/$stderr on every `run`).
  DOC="$output"
  ERR="$stderr"
}

set_mtime_ago() {
  local file="$1" seconds_ago="$2"
  local target_ts=$(( $(date +%s) - seconds_ago ))
  touch -d "@$target_ts" "$file" 2>/dev/null \
    || python3 -c "import os; os.utime('$file', ($target_ts, $target_ts))" 2>/dev/null || true
}

# Epoch seconds -> the whole-second ISO-8601 spelling the cursors use. One
# definition rather than the format string re-spelled per call site (RT3).
iso_at() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
}

# Set an mtime to an exact whole-second + nanosecond pair. `os.utime(ns=)` is
# the portable spelling — `touch -t` carries only second granularity and
# `touch -d @sec.frac` is GNU-only, so a fraction must be CONSTRUCTED here
# rather than inherited from whenever the file happened to be written.
set_mtime_frac() {
  local file="$1" secs="$2" nsec="$3"
  command -v python3 >/dev/null 2>&1 || skip "python3 required to construct sub-second mtimes"
  python3 -c "import os,sys; t=int(sys.argv[2])*10**9+int(sys.argv[3]); os.utime(sys.argv[1], ns=(t,t))" \
    "$file" "$secs" "$nsec"
}

# Did the filesystem PRESERVE the fraction we just set? Asserted, not inferred:
# on a second-granularity filesystem the sub-second cases would be excluded by
# `find -newer` alone and would pass vacuously. Portable — it compares mtimes
# through python rather than parsing a `stat` format string.
fs_keeps_subsecond() {
  command -v python3 >/dev/null 2>&1 || skip "python3 required to read back a sub-second mtime"
  python3 -c "import os,sys; sys.exit(0 if os.stat(sys.argv[1]).st_mtime_ns % 10**9 else 1)" "$1"
}

write_config() {
  # jq-edited from the shipped C5 example so schema drift breaks tests
  # instead of hiding (RT3). Forwards all args to jq, so callers may pass
  # --arg/--argjson before the filter, e.g. write_config --arg r "$repo" '...'.
  # Negative array subscripts are bash 4.3+; macOS ships 3.2, so index the
  # last element explicitly.
  local args=("$@")
  local last=$(( ${#args[@]} - 1 ))
  local filter="${args[$last]}"
  unset "args[$last]"
  jq "${args[@]}" "$filter" "$REPO_ROOT/retrospect.config.json.example" > "$CONFIG"
}

seed_state() {
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" bash "$STATE_CLI" seed >/dev/null 2>&1
}

mark_high_water() {
  local source="$1" json="$2" f="$BATS_TEST_TMPDIR/hw-$source.json"
  printf '%s' "$json" > "$f"
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" \
    bash "$STATE_CLI" mark-run "$source" --high-water-file "$f" >/dev/null 2>&1
}

# curl mock for scout: GET returns SCOUT_BODY for a URL containing
# SCOUT_URL_MATCH, else empty (curl "success" with no body).
setup_scout_curl_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
URL="${@: -1}"
if [[ -n "${SCOUT_URL_MATCH:-}" && "$URL" == *"$SCOUT_URL_MATCH"* ]]; then
  printf '%s' "${SCOUT_BODY:-hello}"
fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# LLM offline mock: curl fails every request (pre-review.bats pattern).
setup_curl_fail_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# LLM online mock: speaks /v1/models and /v1/chat/completions
# (tests/openai-backend.bats setup_curl_mock, adapted). Echoes a canary-safe
# fixed lesson so distilled-content assertions are deterministic; the canary
# privacy assertions instead check the canary is ABSENT (proving the raw
# excerpt never reached the LLM response we source it from — here we control
# both sides so we assert the LLM's OWN returned text, not raw passthrough).
setup_llm_online_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
URL=""; OUTFILE=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    http://*|https://*) URL="${args[i]}" ;;
    -o) OUTFILE="${args[i+1]}" ;;
  esac
done
case "$URL" in
  */v1/models)
    printf '{"data":[{"id":"unsloth/gpt-oss-20b-GGUF:F16"},{"id":"unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL"}]}'
    exit 0
    ;;
  */v1/chat/completions)
    CONTENT="${LLM_MOCK_CONTENT:-a project-neutral distilled lesson}"
    printf '{"choices":[{"message":{"content":"%s"}}]}' "$CONTENT" > "$OUTFILE"
    printf '200'
    exit 0
    ;;
esac
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# gh stub: dispatches on $1 (pr | api). GH_PR_LIST_JSON / GH_PR_COMMENTS_JSON
# control the payloads; GH_MISSING_AUTH=1 makes `gh auth status` fail;
# GH_ABSENT=1 removes the stub entirely (simulating gh not installed).
setup_gh_mock() {
  if [ "${GH_ABSENT:-0}" = "1" ]; then
    rm -f "$BATS_TEST_TMPDIR/gh"
    return
  fi
  cat > "$BATS_TEST_TMPDIR/gh" <<EOF
#!/bin/bash
if [ "\$1" = "auth" ]; then
  if [ "${GH_MISSING_AUTH:-0}" = "1" ]; then
    exit 1
  fi
  exit 0
fi
if [ "\$1" = "pr" ] && [ "\$2" = "list" ]; then
  printf '%s' '${GH_PR_LIST_JSON:-[]}'
  exit 0
fi
if [ "\$1" = "api" ]; then
  # The hook requests \`--jq '.[].body | @base64'\`, one base64 line per
  # comment. Emit each configured comment body base64-encoded so multi-line
  # bodies survive intact. GH_PR_COMMENTS_BODY is a single comment body;
  # GH_PR_COMMENTS_BODIES (newline-separated, one per line) supplies multiple.
  if [ -n "\${GH_PR_COMMENTS_BODIES:-}" ]; then
    while IFS= read -r _b; do
      [ -n "\$_b" ] && printf '%s' "\$_b" | base64 | tr -d '\n' && printf '\n'
    done <<<"\${GH_PR_COMMENTS_BODIES}"
  elif [ -n "\${GH_PR_COMMENTS_BODY:-}" ]; then
    printf '%s' "\${GH_PR_COMMENTS_BODY}" | base64 | tr -d '\n'
    printf '\n'
  fi
  exit 0
fi
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/gh"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  CONFIG="$BATS_TEST_TMPDIR/retrospect.config.json"
  STATE="$BATS_TEST_TMPDIR/state/retrospect.json"
  mkdir -p "$BATS_TEST_TMPDIR/state"

  # Point every LLM cache/state seam into the tmpdir so the 300s availability
  # cache and round-robin counters never cross tests.
  export _OPENAI_HOST_CACHE="$BATS_TEST_TMPDIR/.openai-cache"
  export _OLLAMA_HOST_CACHE="$BATS_TEST_TMPDIR/.ollama-cache"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/xdg-runtime"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg-cache"
  mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME"
  # The subject's own scratch sink. `llm-utils.sh:_llm_state_dir` falls back to
  # `mktemp -d "${TMPDIR:-/tmp}/claude-llm-hooks-XXXXXX"` when every XDG
  # candidate is unusable, so without this its scratch dirs land in shared
  # system temp instead of the tree this test reclaims (RT11 — scope every
  # mutable sink the subject touches, do not assume the scratch-directory
  # pattern covers it).
  export TMPDIR="$BATS_TEST_TMPDIR"

  unset LLM_BACKEND OPENAI_HOST OPENAI_HOSTS LLM_TRUSTED_HOSTS OLLAMA_HOST OLLAMA_EXTRA_HOSTS
  # The model seam, not just the host seam. The mock pool advertises a fixed
  # model id, so an inherited OPENAI_MODEL naming this machine's real model
  # matches nothing in it, no host is found, and every case that needs the LLM
  # "online" fails — as a property of the developer's shell, not of the code.
  unset OPENAI_MODEL OPENAI_MODEL_THINK OPENAI_MODEL_NOTHINK OPENAI_MODEL_SMALL OPENAI_MODEL_LARGE
  unset OPENAI_REASONING_EFFORT OLLAMA_MODEL_THINK OLLAMA_MODEL_NOTHINK REVIEW_MODEL
  unset CLAUDE_SESSION_ID
  unset GH_ABSENT GH_MISSING_AUTH GH_PR_LIST_JSON GH_PR_COMMENTS_BODY GH_PR_COMMENTS_BODIES
  # The present-instant seam. An inherited value rewrites the clock for every
  # case that relies on the real one, and a value ahead of the system clock is
  # refused with a warning several cases would then fail on for an unrelated
  # reason.
  unset RETRO_PRESCREEN_NOW

  write_config '.'
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# ===========================================================================
# usage / degraded paths
# ===========================================================================

@test "unknown mode: exit 2 with usage" {
  run_prescreen bogus-mode
  [ "$status" -eq 2 ]
}

@test "no mode: exit 2 with usage" {
  run_prescreen
  [ "$status" -eq 2 ]
}

@test "missing config: artifacts mode exits 2" {
  rm -f "$CONFIG"
  run_prescreen artifacts --json
  [ "$status" -eq 2 ]
}

@test "missing config: github mode exits 2" {
  rm -f "$CONFIG"
  run_prescreen github --json
  [ "$status" -eq 2 ]
}

@test "missing config: scout mode exits 2" {
  rm -f "$CONFIG"
  run_prescreen scout --json
  [ "$status" -eq 2 ]
}

@test "missing config: transcripts mode exits 2" {
  rm -f "$CONFIG"
  run_prescreen transcripts --json
  [ "$status" -eq 2 ]
}

# ===========================================================================
# scrub mode — pure stdin -> stdout filter, no config/state read
# ===========================================================================

@test "scrub: does not read config even when RETRO_CONFIG points at garbage" {
  RETRO_CONFIG=/nonexistent/does-not-exist run --separate-stderr \
    bash -c "echo 'plain text' | bash '$SCRIPT' scrub"
  [ "$status" -eq 0 ]
  [ "$output" = "plain text" ]
}

@test "scrub: email address redacted" {
  run bash -c "echo 'contact alice@example.com please' | bash '$SCRIPT' scrub"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"alice@example.com"* ]]
}

@test "scrub: IP address redacted" {
  run bash -c "echo 'server at 192.168.1.42 responded' | bash '$SCRIPT' scrub"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"192.168.1.42"* ]]
}

@test "scrub: IPv6 addresses redacted (compressed, full, loopback) (S2)" {
  run bash -c "echo 'a fe80::1234:5678:9abc:def0 b 2001:db8::1 c ::1' | bash '$SCRIPT' scrub"
  [[ "$output" != *"fe80::1234"* ]]
  [[ "$output" != *"2001:db8::1"* ]]
  [[ "$output" != *"::1"* ]]
  [[ "$output" == *"[REDACTED]"* ]]
}

@test "scrub: IPv6 pass does not eat clock times / host:port / owner:repo prose" {
  run bash -c "echo 'time 12:34:56 host:8080 acme/widgets' | bash '$SCRIPT' scrub"
  [[ "$output" == *"12:34:56"* ]]
  [[ "$output" == *"host:8080"* ]]
  [[ "$output" == *"acme/widgets"* ]]
}

@test "scrub: /home/<user>/ path redacted" {
  run bash -c "echo 'file at /home/alice/project/secret.txt' | bash '$SCRIPT' scrub"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"/home/alice"* ]]
}

@test "scrub: user-specific ~/ path redacted" {
  run bash -c "echo 'edit ~/myproject/notes.md' | bash '$SCRIPT' scrub"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"~/myproject"* ]]
}

@test "scrub: secret-shaped string redacted" {
  run bash -c "echo 'token: abcdEFGH1234ijklMNOP5678qrst' | bash '$SCRIPT' scrub"
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"abcdEFGH1234ijklMNOP5678qrst"* ]]
}

@test "scrub: over-length input is capped" {
  local long
  long=$(head -c 3000 < /dev/zero | tr '\0' 'x')
  run bash -c "printf '%s' '$long' | bash '$SCRIPT' scrub"
  [ "${#output}" -le 2000 ]
}

@test "scrub: allowlisted hook prefix survives unmodified (F-16)" {
  run bash -c "echo 'run: bash ~/.claude/hooks/example.sh' | bash '$SCRIPT' scrub"
  [[ "$output" == *"~/.claude/hooks/example.sh"* ]]
  [[ "$output" != *"[REDACTED]"* ]]
}

@test "scrub: allowlisted skills/rules prefixes also survive" {
  run bash -c "echo 'see ~/.claude/skills/triangulate and ~/.claude/rules/common' | bash '$SCRIPT' scrub"
  [[ "$output" == *"~/.claude/skills/triangulate"* ]]
  [[ "$output" == *"~/.claude/rules/common"* ]]
}

@test "scrub: non-shadowing — allowlisted-prefix token still has embedded email + /home/ redacted (S15-A)" {
  run bash -c "echo '~/.claude/hooks/report-/home/alice/x-alice@example.com.sh' | bash '$SCRIPT' scrub"
  [[ "$output" != *"alice@example.com"* ]]
  [[ "$output" != *"/home/alice"* ]]
}

# ===========================================================================
# artifacts mode
# ===========================================================================

setup_artifacts_repo() {
  local repo="$BATS_TEST_TMPDIR/sibling-repo"
  mkdir -p "$repo/docs/archive/review"
  # The prescreen containment-checks every candidate with realpath, so the paths it
  # emits are symlink-resolved. On macOS $TMPDIR is /var/folders/... symlinked
  # to /private/var/folders/..., so a caller comparing against the unresolved
  # fixture path never matches. Resolve here, at the single point every
  # artifacts test derives its paths from.
  repo="$(cd -P "$repo" && pwd)"
  write_config --arg r "$repo" '.sources.artifacts.repos = [$r] | .sources.github.enabled = false'
  printf '%s' "$repo"
}

@test "artifacts: LLM offline -> file list only, high_water = per-repo max mtime" {
  local repo
  repo=$(setup_artifacts_repo)
  echo "review notes" > "$repo/docs/archive/review/one-review.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  local doc="$output"
  run jq -e '.candidates | length == 1' <<<"$doc"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" '.high_water[$r] | test("^[0-9]{4}-")' <<<"$doc"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].summary == null' <<<"$doc"
  [ "$status" -eq 0 ]
}

@test "artifacts: -newermt high-water excludes files older than the cursor" {
  # East of UTC, so the TZ axis is covered in both directions (the allow-side
  # case below pins a west-of-UTC zone).
  export TZ="Asia/Tokyo"
  local repo
  repo=$(setup_artifacts_repo)
  local old="$repo/docs/archive/review/old-review.md"
  echo "old" > "$old"
  set_mtime_ago "$old" 864000   # 10 days ago
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( $(date +%s) - 432000 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# The cursor is recorded from whole seconds while `find -newer` compares at the
# filesystem's sub-second precision, so a file written inside the cursor's own
# second used to re-qualify on every run — and recomputing the cursor from %Y
# landed on that same second, making it a fixed point that never drained.
@test "artifacts: a file inside the cursor's own second does not re-qualify" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/boundary-review.md"
  echo "boundary" > "$f"

  # CONSTRUCT the fractional mtime rather than observing it: reading it back
  # with `stat -c %y` is GNU-only, so on BSD the case would skip permanently
  # while blaming the filesystem for what is a missing command fallback.
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 844377201
  # Precondition, now asserted rather than inferred: the filesystem must have
  # PRESERVED the fraction. Without it the file is excluded by `-newer` alone
  # and the case would pass vacuously under the buggy implementation too.
  fs_keeps_subsecond "$f" || skip "filesystem did not preserve a sub-second mtime"

  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at "$secs")\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# Split out of the case above so each assertion has its own mutant (RT7 shape
# (g)(i)): under the deny case's mutation bats aborts before reaching this one,
# so it would otherwise ride along unproven.
@test "artifacts: cursor does not regress when every candidate is suppressed" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/boundary-review.md"
  echo "boundary" > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 844377201
  fs_keeps_subsecond "$f" || skip "filesystem did not preserve a sub-second mtime"

  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at "$secs")\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" --arg hw "$(iso_at "$secs")" '.high_water[$r] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# Allow side of the same predicate (RT10): tightening the comparison must not
# swallow a file that genuinely postdates the cursor's second.
@test "artifacts: a file past the cursor's second still qualifies" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/fresh-review.md"
  echo "fresh" > "$f"
  local secs
  secs=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
  seed_state
  # Cursor one second BEFORE the file's own second.
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( secs - 1 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg p "$f" '.candidates[0].path == $p' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# The candidate loop iterates files-per-repo, and every other artifacts fixture
# has cardinality 1 on that dimension — so `> $repo_hw` and `> $repo_max` were
# indistinguishable to the whole suite, though the latter silently drops any
# qualifying file processed after a newer sibling (RT7 empty-oracle sub-clause).
@test "artifacts: two qualifying files in one repo both appear, cursor takes the max" {
  local repo
  repo=$(setup_artifacts_repo)
  local older="$repo/docs/archive/review/a-review.md"
  local newer="$repo/docs/archive/review/b-review.md"
  echo a > "$older"; echo b > "$newer"
  local base=1784047500
  # The `repo_max` mutant only survives if a qualifying file is traversed AFTER
  # one with a strictly greater mtime, so the fixture must not depend on
  # readdir order: ask the production scan for the real order, then give the
  # FIRST-traversed file the LATER mtime.
  local first
  first=$(find "$repo/docs/archive/review" -maxdepth 1 -name '*.md' -print0 \
          | tr '\0' '\n' | head -1)
  [ -n "$first" ]
  local second
  if [ "$first" = "$older" ]; then second="$newer"; else second="$older"; fi
  set_mtime_frac "$first"  "$(( base + 60 ))" 0
  set_mtime_frac "$second" "$base" 0

  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( base - 60 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg p "$older" '[.candidates[].path] | index($p) != null' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg p "$newer" '[.candidates[].path] | index($p) != null' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" --arg hw "$(iso_at $(( base + 60 )))" '.high_water[$r] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# `touch -t` parses its stamp in the LOCAL zone. Rendering that stamp with
# `date -u` shifted the `-newer` reference by the UTC offset, and west of UTC
# the reference landed AFTER the cursor — so the pre-filter dropped candidates
# the authoritative comparison would have accepted. Reds against the -u form.
@test "artifacts: candidate past the cursor still qualifies west of UTC" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/tz-review.md"
  echo tz > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 0
  seed_state
  # Cursor two seconds back: well inside any UTC offset's shift, so only the
  # offset bug can push the reference past the file.
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( secs - 2 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434" TZ="America/New_York"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# A single future-dated artifact must not drive the persisted cursor past the
# present, which would exclude every artifact in the repository from then on
# while the source keeps reporting success and an empty candidate list.
@test "artifacts: a future-dated artifact does not push the cursor past now" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/future-review.md"
  echo future > "$f"
  set_mtime_frac "$f" 4102444800 0   # 2100-01-01T00:00:00Z
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # Still mined this run — the clamp bounds the CURSOR, not the candidate set.
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" --arg now "$(iso_at "$(date -u +%s)")" '.high_water[$r] <= $now' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"future-dated"* ]]
}

# An unreadable mtime must degrade to "everything is new" — the direction
# _mtime_ref_file's own comment commits to — not to "older than any cursor".
# Spelling a failed stat as epoch 0 made the comparison drop the candidate,
# turning a broken toolchain into an empty-and-successful report (R50 (ii)).
@test "artifacts: an unreadable mtime keeps the candidate and warns" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/nostat-review.md"
  echo nostat > "$f"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  # Shadow `stat` only for the subject's own invocation, after every helper
  # that needs a working stat has already run.
  cat > "$BATS_TEST_TMPDIR/stat" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/stat"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  # Pin the sink's exact state (RT11): advancing the cursor here would exclude
  # every artifact in the repo from then on while still reporting success.
  run jq -e --arg r "$repo" '.high_water[$r] == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unreadable mtime"* ]]
}

# Boundary cells for the clamp (RT10 clause 2). RETRO_PRESCREEN_NOW is the
# present-instant seam — distinct from RETRO_NOW, which pins the scheduling
# clock — so both cells are deterministic instead of racing the wall clock.
@test "artifacts: an artifact dated exactly now still advances the cursor" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/now-review.md"
  echo now > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 0
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( secs - 60 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW="$secs"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" --arg hw "$(iso_at "$secs")" '.high_water[$r] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: an artifact one second past now is clamped out of the cursor" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/ahead-review.md"
  echo ahead > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 0
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at $(( secs - 60 )))\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW="$(( secs - 1 ))"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # The clamp withholds the advance; it does not move the cursor forward to now.
  run jq -e --arg r "$repo" --arg hw "$(iso_at $(( secs - 60 )))" '.high_water[$r] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"future-dated"* ]]
}

# A cursor that is ALREADY past the present — written by any run before the
# clamp existed — must be healed, not merely left alone. Clamping the increment
# does nothing for a value that is already ahead, and the loop body never runs
# to announce it, so this is the branch with no other signal.
@test "artifacts: a persisted future cursor is clamped and the source is not blind" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/healed-review.md"
  echo healed > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 0
  seed_state
  mark_high_water artifacts "{\"$repo\": \"2100-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW="$(( secs + 60 ))"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # Healing bounds the damage; it does not recover the window already skipped,
  # so this artifact stays excluded. What matters is that the persisted value
  # is no longer in the future, so the source is not blind from here on.
  run jq -e --arg r "$repo" '.high_water[$r] < "2100-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"past the present"* ]]
}

# When the present cannot be read, neither bound can be applied: the heal has
# nothing to compare against, and an increment cannot be judged as past or
# future. The candidate is KEPT (the permissive direction), and the cursor does
# NOT advance — recording an unjudgeable increment would persist a value the
# next run cannot distinguish from a poisoned one, and an absurd mtime picked up
# on a clock-less run can spell a year `_is_iso` rejects, which discards the
# whole high_water object rather than one entry.
@test "artifacts: an unreadable present keeps the candidate and does not advance the cursor" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/noclock-review.md"
  echo noclock > "$f"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 0
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW="not-a-number"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" '.high_water[$r] == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"bounds disabled"* ]]
}

# `stat` can exit 0 and print something non-numeric (a wrapper, a locale-mangled
# format). jq --argjson then fails and mtime_iso comes back empty — and an empty
# string compares BELOW every cursor, which would silently drop the candidate.
@test "artifacts: a non-numeric mtime keeps the candidate rather than dropping it" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/junkstat-review.md"
  echo junk > "$f"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  cat > "$BATS_TEST_TMPDIR/stat" <<'EOF'
#!/bin/bash
echo "not-a-number"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/stat"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo" '.high_water[$r] == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unreadable mtime"* ]]
}

# The whole-second cursor guard, the clamp and the stat fail-direction were all
# added to cmd_transcripts as well (R3 — same producer/consumer pair, same
# class), and RT7 wants one mutation per arm, so each arm needs its own case.
@test "transcripts: a session inside the cursor's own second does not re-qualify" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/boundary.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  local secs=1784047446
  set_mtime_frac "$f" "$secs" 844377201
  fs_keeps_subsecond "$f" || skip "filesystem did not preserve a sub-second mtime"
  seed_state
  mark_high_water transcripts "\"$(iso_at "$secs")\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: a future-dated session does not push the cursor past now" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/future.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_frac "$f" 4102444800 0   # 2100-01-01T00:00:00Z
  seed_state
  # NON-default, so "the cursor did not move" is distinguishable from "the
  # emitter collapsed to the floor". The freshness rule is bounded on both
  # sides, so a future mtime is no longer mistaken for a file written moments
  # ago and reaches the future-dated branch without pinning a session id.
  mark_high_water transcripts "\"$(iso_at 1784047446)\""
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  # The exact expected cursor, not a range: `<= now` is satisfied by 1970, by
  # the floor, and by any value the emitter collapses to.
  run jq -e --arg hw "$(iso_at 1784047446)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"future-dated"* ]]
}

@test "transcripts: an unreadable session mtime keeps the file and warns without naming it" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/nostat.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  seed_state
  mark_high_water transcripts "\"1970-01-01T00:00:00Z\""
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  cat > "$BATS_TEST_TMPDIR/stat" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/stat"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length >= 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unreadable mtime"* ]]
  # The privacy invariant: no branch may name a transcript path or filename.
  [[ "$ERR" != *"nostat"* ]]
  [[ "$ERR" != *"$root"* ]]
}

# The shell's own redirection error is not covered by the loop's 2>/dev/null
# and would print the absolute transcript path — user name and repository
# location — onto stderr.
@test "transcripts: an unreadable session file never leaks its path to stderr" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/CANARYNAME.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  chmod 000 "$f"
  seed_state
  mark_high_water transcripts "\"1970-01-01T00:00:00Z\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$ERR" != *"CANARYNAME"* ]]
  [[ "$ERR" != *"$root"* ]]
  # No `chmod 644` restore: it sat after the assertions, so bats' abort-on-
  # failure skipped it in exactly the runs that would have needed it. teardown's
  # `rm -rf` reclaims a mode-000 file inside a writable directory.
}

# Same read-in clamp on the transcripts side (R3 — one class, two members).
@test "transcripts: a persisted future cursor is clamped rather than left blind" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/healed.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  seed_state
  mark_high_water transcripts "\"2100-01-01T00:00:00Z\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"past the present"* ]]
}

# End-to-end drain property: the emitted cursor, fed back through mark-run,
# must empty the source. This is also the only case where the cursor compared
# against is the one PRODUCTION computed (jq `todate`) rather than one the test
# hand-spelled with `date`.
@test "artifacts: high_water round-trips into mark-run and drains the source" {
  local repo
  repo=$(setup_artifacts_repo)
  local f="$repo/docs/archive/review/rt-review.md"
  echo roundtrip > "$f"
  # A fractional mtime, so the second pass must be drained by the whole-second
  # ISO authority — with nsec=0 `-newer` alone excludes it and the case would
  # prove only what the pre-filter already gave us.
  set_mtime_frac "$f" 1784047446 500000000
  fs_keeps_subsecond "$f" || skip "filesystem did not preserve a sub-second mtime"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]

  # Feed the produced high_water back in, exactly as Step 9 of the pipeline does.
  local hwfile="$BATS_TEST_TMPDIR/hw-roundtrip.json"
  jq -c '.high_water' <<<"$DOC" > "$hwfile"
  # Read for its own status, and the stored value re-read: a rejected write
  # leaves state untouched, which a drain assertion alone cannot distinguish
  # from a write that happened to store a draining value.
  run bash -c "RETRO_CONFIG='$CONFIG' RETRO_STATE='$STATE' RETRO_NOW='$NOW' bash '$STATE_CLI' mark-run artifacts --high-water-file '$hwfile'"
  [ "$status" -eq 0 ]
  run bash -c "RETRO_CONFIG='$CONFIG' RETRO_STATE='$STATE' RETRO_NOW='$NOW' bash '$STATE_CLI' show --json | jq -c '.sources.artifacts.high_water'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(jq -c . "$hwfile")" ]

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: filename with control characters is rejected with stderr warning" {
  local repo
  repo=$(setup_artifacts_repo)
  local weird="$repo/docs/archive/review/$(printf 'bad\tname')-review.md"
  echo "content" > "$weird" 2>/dev/null || skip "filesystem rejects control-char filenames"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"control characters"* ]]
}

@test "artifacts: out-of-repo symlinked candidate is rejected by containment check" {
  local repo
  repo=$(setup_artifacts_repo)
  local outside="$BATS_TEST_TMPDIR/outside-secret.md"
  echo "secret content" > "$outside"
  ln -s "$outside" "$repo/docs/archive/review/linked-review.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: two-hop symlink chain escaping the repo is rejected (S1)" {
  local repo
  repo=$(setup_artifacts_repo)
  local outside="$BATS_TEST_TMPDIR/outside-secret.md"
  echo "secret content" > "$outside"
  # hop1 -> hop2 (both inside the repo) -> outside (escapes). A one-hop check
  # would accept hop1 because hop2's directory is still inside the repo.
  ln -s "$repo/docs/archive/review/hop2.md" "$repo/docs/archive/review/hop1.md"
  ln -s "$outside" "$repo/docs/archive/review/hop2.md"
  # a legitimate real file to prove non-escaping candidates still pass
  echo "real finding" > "$repo/docs/archive/review/real.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # only real.md survives; both symlink hops are rejected
  run jq -e '[.candidates[].path | test("real.md")] | all and (length == 1)' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"hop1.md"* ]]
  [[ "$DOC" != *"hop2.md"* ]]
}

@test "artifacts: LLM online -> summary bullets pass the scrub" {
  local repo
  repo=$(setup_artifacts_repo)
  echo "review notes" > "$repo/docs/archive/review/one-review.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="Symptom: contact bob@example.com for details"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].summary != null' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"bob@example.com"* ]]
}

@test "artifacts: reachable remote LLM without consent -> raw NOT sent, summary null (egress gate)" {
  local repo
  repo=$(setup_artifacts_repo)
  # An artifact containing internal detail that must NOT leave the machine.
  echo "Symptom: SQLi in /internal/admin endpoint; token AKIAIOSFODNN7EXAMPLE" \
    > "$repo/docs/archive/review/sensitive-review.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  # Backend is reachable (trusted remote + online mock answers), so the probe
  # would succeed — the ONLY thing stopping raw egress is the S3 gate refusing
  # a non-loopback host without allow_remote_llm. artifacts ships consent=false.
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="leaked summary"
  export OPENAI_HOST="http://remote-host.example.com:8080"
  export OPENAI_HOSTS="http://remote-host.example.com:8080"
  export LLM_TRUSTED_HOSTS="remote-host.example.com"
  setup_llm_online_mock

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # No summary was produced — the raw artifact was never sent to the remote LLM.
  run jq -e '.candidates[0].summary == null' <<<"$DOC"
  [ "$status" -eq 0 ]
  # The file is still surfaced as a candidate (file-list-only fallback).
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"skipped"* || "$ERR" == *"consent"* ]]
}

@test "artifacts: remote LLM WITH allow_remote_llm consent -> summary produced" {
  local repo
  repo=$(setup_artifacts_repo)
  write_config --arg r "$repo" \
    '.sources.artifacts.repos = [$r] | .sources.artifacts.allow_remote_llm = true'
  echo "review notes" > "$repo/docs/archive/review/consented-review.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="Symptom: a distilled bullet"
  export OPENAI_HOST="http://remote-host.example.com:8080"
  export OPENAI_HOSTS="http://remote-host.example.com:8080"
  export LLM_TRUSTED_HOSTS="remote-host.example.com"
  setup_llm_online_mock

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].summary != null' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# github mode
# ===========================================================================

setup_github_config() {
  write_config '.sources.github.enabled = true | .sources.github.repos = ["acme/widgets"] | .sources.artifacts.enabled = false'
}

@test "github: gh missing -> stderr warning, empty candidates, exit 0" {
  setup_github_config
  seed_state
  # Truly simulate `gh` absence: build a sandbox PATH that contains only the
  # coreutils the hook needs (symlinked from the real ones) and NO gh, so the
  # hook's `command -v gh` fails regardless of what is installed on the host.
  local sandbox="$BATS_TEST_TMPDIR/nogh-bin"
  mkdir -p "$sandbox"
  local tool
  for tool in bash jq find date sha256sum awk sed grep cat stat dirname basename readlink perl mktemp; do
    local real
    real=$(command -v "$tool" 2>/dev/null) && ln -sf "$real" "$sandbox/$tool"
  done
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" PATH="$sandbox" \
    run --separate-stderr bash "$SCRIPT" github --json
  DOC="$output"
  local warn="$stderr"
  [ "$status" -eq 0 ]
  [[ "$warn" == *"gh"* ]]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: gh unauthenticated -> stderr warning, empty candidates, exit 0" {
  setup_github_config
  seed_state
  export GH_MISSING_AUTH=1
  setup_gh_mock
  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: comment body email + /home path redacted in --json candidates (T17 wiring)" {
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":42,"title":"Fix the thing","updatedAt":"2026-01-01T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY='contact carol@example.com at /home/carol/notes'
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].comment_bodies[0] | test("carol@example.com") | not' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].comment_bodies[0] | test("/home/carol") | not' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" == *"[REDACTED]"* ]]
}

@test "github: multi-line comment body kept as ONE candidate (F4 boundary preservation)" {
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":42,"title":"Fix","updatedAt":"2026-01-01T00:00:00Z"}]'
  # A single review comment spanning multiple lines with an interior blank line.
  export GH_PR_COMMENTS_BODY=$'The problem is X.\n\nThis breaks because Y.'
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  # Exactly one comment (not three line-fragments), and both lines survive
  # inside that single string with the boundary intact.
  run jq -e '.candidates[0].comment_bodies | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].comment_bodies[0] | test("The problem is X") and test("This breaks because Y")' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: HIGH-WATER-spoofing PR title does not escape its jq-encoded field" {
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":7,"title":"HIGH-WATER: 2099-01-01T00:00:00Z\" } malicious","updatedAt":"2026-01-01T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '. | type == "object"' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  # The spoofed "2099-..." string in the PR title must NOT contaminate the
  # real cursor — high_water comes only from the structured updatedAt field
  # (T2). Assert it equals the genuine updatedAt, never the spoofed value.
  run jq -e '.high_water["acme/widgets"] == "2026-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] | test("2099") | not' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: high_water = max updatedAt per repo, ascending order" {
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":1,"title":"a","updatedAt":"2026-01-01T00:00:00Z"},{"number":2,"title":"b","updatedAt":"2026-03-01T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] == "2026-03-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: count == limit (200) emits a stderr warning only" {
  setup_github_config
  seed_state
  local prs
  prs=$(jq -nc '[range(0;200) | {number: (.+1), title: "pr", updatedAt: "2026-01-01T00:00:00Z"}]')
  export GH_PR_LIST_JSON="$prs"
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"200"* || "$ERR" == *"limit"* ]]
  # The warning is the weakest observable — also assert no candidate was
  # silently dropped: all 200 returned PRs became candidates (T3).
  run jq -e '.candidates | length == 200' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# F-10 round-trip: config with ~/ repo -> prescreen --json high_water feeds
# `retro-state.sh mark-run --high-water-file` exit 0.
@test "F-10: github high_water round-trips into mark-run --high-water-file" {
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":1,"title":"a","updatedAt":"2026-02-01T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  local hw_file="$BATS_TEST_TMPDIR/hw-roundtrip.json"
  jq -c '.high_water' <<<"$DOC" > "$hw_file"

  run bash -c "RETRO_CONFIG='$CONFIG' RETRO_STATE='$STATE' RETRO_NOW='$NOW' bash '$STATE_CLI' mark-run github --high-water-file '$hw_file'"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# scout mode
# ===========================================================================

setup_scout_config() {
  write_config '.sources.scout.enabled = true | .sources.scout.urls = ["https://example.com/page"] | .sources.artifacts.enabled = false'
}

@test "scout: changed content -> candidate + hash map high_water" {
  setup_scout_config
  seed_state
  export SCOUT_URL_MATCH="example.com/page"
  export SCOUT_BODY="version 1 content"
  setup_scout_curl_mock

  run_prescreen scout --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == ["https://example.com/page"]' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["https://example.com/page"] | test("^[0-9a-f]{64}$")' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "scout: unchanged hash -> no candidate" {
  setup_scout_config
  seed_state
  export SCOUT_URL_MATCH="example.com/page"
  export SCOUT_BODY="stable content"
  setup_scout_curl_mock
  local hash
  hash=$(printf '%s' "$SCOUT_BODY" | sha256sum | awk '{print $1}')
  mark_high_water scout "{\"https://example.com/page\": \"$hash\"}"

  run_prescreen scout --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "scout: content never emitted" {
  setup_scout_config
  seed_state
  export SCOUT_URL_MATCH="example.com/page"
  export SCOUT_BODY="SECRET-CANARY-CONTENT-XYZ"
  setup_scout_curl_mock

  run_prescreen scout --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"SECRET-CANARY-CONTENT-XYZ"* ]]
  [[ "$stderr" != *"SECRET-CANARY-CONTENT-XYZ"* ]]
}

@test "scout: curl missing -> stderr warning, empty candidates, exit 0" {
  setup_scout_config
  seed_state
  # Shadow curl with a directory prepended to PATH that has every other
  # required tool symlinked in but no curl, so `command -v curl` genuinely
  # fails without needing to touch the real system PATH.
  local shadow="$BATS_TEST_TMPDIR/nocurl"
  mkdir -p "$shadow"
  local tool
  for tool in bash jq sha256sum basename dirname cat sed awk perl grep find date stat; do
    local real
    real=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$real" "$shadow/$tool"
  done
  run --separate-stderr env -i "PATH=$shadow" \
    RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" \
    bash "$SCRIPT" scout --json
  [ "$status" -eq 0 ]
  # The other two thirds of this case's name, previously unasserted.
  [[ "$stderr" == *"curl"* ]]
  run jq -e '.candidates == []' <<<"$output"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# transcripts mode
# ===========================================================================

setup_transcripts_config() {
  local root="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$root"
  write_config --arg r "$root" '.sources.transcripts.enabled = true | .sources.transcripts.root = $r | .sources.artifacts.enabled = false'
  printf '%s' "$root"
}

write_transcript_fixture() {
  local path="$1" canary="$2"
  jq -nc --arg c "$canary" '{type:"tool_result", is_error:true, content:$c}' >> "$path"
  printf '\n' >> "$path"
  jq -nc --arg c "$canary" '{hook_event:{decision:"block"}, content:$c}' >> "$path"
  printf '\n' >> "$path"
  jq -nc --arg c "$canary" '{type:"user", message:{content: ("wrong, " + $c)}}' >> "$path"
  printf '\n' >> "$path"
}

# Every exit path carries the cursor. `_json_empty`'s null makes the
# orchestrator omit --high-water-file, so a cursor healed on that run is
# discarded and the poison survives the run that announced it.
#
# The persisted value is deliberately NOT the seeded default: 1970-01-01T00:00:00Z
# is at once the default, _heal_cursor's floor and a hard-coded epoch 0, so an
# assertion against it cannot tell a correct emitter from one that emits a
# constant floor.
@test "transcripts: the root-absent exit still carries the cursor" {
  write_config '.sources.transcripts.enabled = true | .sources.transcripts.root = "/nonexistent-root-xyz" | .sources.artifacts.enabled = false'
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047446)\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784047500
  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg hw "$(iso_at 1784047446)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: the empty-file-set exit still carries the cursor" {
  local root
  root=$(setup_transcripts_config)
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047446)\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784047500
  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg hw "$(iso_at 1784047446)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# The healing arm of the same exit: a poisoned cursor must come back as the
# floor, not be passed through.
@test "transcripts: the empty-file-set exit heals a poisoned cursor" {
  local root
  root=$(setup_transcripts_config)
  seed_state
  mark_high_water transcripts '"2100-01-01T00:00:00Z"'
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784047500
  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"past the present"* ]]
}

@test "transcripts: canary privacy — LLM offline path: canary absent from stdout and stderr, counts > 0" {
  local root canary
  root=$(setup_transcripts_config)
  canary="CANARY-OFFLINE-9f3e"
  mkdir -p "$root/proj"
  write_transcript_fixture "$root/proj/sess1.jsonl" "$canary"
  # Age the fixture past the 5-minute freshness window so it is not excluded
  # as a still-being-written transcript when CLAUDE_SESSION_ID is unset.
  set_mtime_ago "$root/proj/sess1.jsonl" 600
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047446)\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"$canary"* ]]
  [[ "$stderr" != *"$canary"* ]]
  run jq -e '.deferred == true' <<<"$DOC"
  [ "$status" -eq 0 ]
  # NOT null: pipeline.md writes the high-water file only "(when non-null)", so
  # a null here makes mark-run be skipped entirely and `last_run` never
  # advances -- the source stays permanently due while a poisoned cursor
  # survives the run that announced it. The emitted value is the HEALED read-in
  # cursor, never max_hw, so it records no progress.
  # A NON-DEFAULT persisted cursor: the three candidate emitters (the cursor,
  # max_hw, and a hard-coded floor) are mutually distinguishable only here.
  run jq -e --arg hw "$(iso_at 1784047446)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '[.candidates[].event_count] | add > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: canary privacy — LLM online + loopback: extraction happened, canary absent" {
  local root canary
  root=$(setup_transcripts_config)
  canary="CANARY-ONLINE-a71c"
  mkdir -p "$root/proj"
  write_transcript_fixture "$root/proj/sess1.jsonl" "$canary"
  set_mtime_ago "$root/proj/sess1.jsonl" 600
  seed_state
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"$canary"* ]]
  [[ "$stderr" != *"$canary"* ]]
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.deferred == false' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: correction marker matches ARRAY-shaped user content (F1 real transcript shape)" {
  # Real Claude Code user messages store .message.content as an array of
  # content blocks, not a string. This fixture contains ONLY a user-correction
  # event in that array shape (no tool_result/decision:block events), so it is
  # extracted iff the array-normalizing filter works — proving the
  # correction-marker signal actually fires on the real transcript shape.
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/arr.jsonl"
  jq -nc '{type:"user", message:{content: [{type:"text", text:"no, that is wrong, revert it"}]}}' > "$f"
  printf '\n' >> "$f"
  set_mtime_ago "$f" 600
  seed_state
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  # The array-shaped correction event was extracted and distilled -> a candidate.
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.deferred == false' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: malformed jsonl fixture — payload absent from both streams" {
  local root canary
  root=$(setup_transcripts_config)
  canary="CANARY-MALFORMED-77b1"
  mkdir -p "$root/proj"
  printf '{not valid json containing %s\n' "$canary" > "$root/proj/sess1.jsonl"
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"$canary"* ]]
  [[ "$stderr" != *"$canary"* ]]
}

# The red-proof for the canary-privacy assertions above. It must run the
# SUBJECT: the previous version piped a canary through `cat` and asserted the
# canary came out, which demonstrates that `echo` echoes and would stay green
# with cmd_scrub deleted entirely.
@test "scrub: the redaction the canary cases rely on is load-bearing" {
  local secret="alice@example.com"
  # Through the real filter: redacted.
  run bash -c "echo 'contact $secret now' | bash '$SCRIPT' scrub"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$secret"* ]]
  [[ "$output" == *"[REDACTED]"* ]]
  # Through a copy with the email pass removed: NOT redacted. Without this the
  # assertion above is satisfied by an input that never contained the pattern.
  local mutant="$BATS_TEST_TMPDIR/noscrub.sh"
  sed "s#^  input=\$(printf '%s' \"\$input\" | sed -E 's/\[A-Za-z0-9._%+-\]+@.*#  : \\##" "$SCRIPT" > "$mutant"
  run bash -c "echo 'contact $secret now' | bash '$mutant' scrub"
  [[ "$output" == *"$secret"* ]]
}

@test "transcripts: session-ID basename excluded" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  write_transcript_fixture "$root/proj/current-session.jsonl" "irrelevant"
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export CLAUDE_SESSION_ID="current-session"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: fresh-mtime (<5min) file excluded when session ID unset" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  write_transcript_fixture "$root/proj/fresh.jsonl" "irrelevant"
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: >5min-old file included when session ID unset (touch -d @epoch)" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/old-enough.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: newline-bearing filename does not escape its jq-encoded field" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  # jsonl filenames cannot literally contain a newline on most filesystems;
  # exercise the encoding path via a name with an embedded double-quote/space
  # combination that would break naive string concatenation instead.
  local f="$root/proj/weird name \"quote\".jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '. | type == "object"' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: high_water = max mtime among PROCESSED files only, excluded stays newer" {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local processed="$root/proj/processed.jsonl"
  write_transcript_fixture "$processed" "irrelevant"
  set_mtime_ago "$processed" 600
  local excluded="$root/proj/too-fresh.jsonl"
  write_transcript_fixture "$excluded" "irrelevant"
  # too-fresh.jsonl keeps its natural (just-written) mtime -> excluded by the 5-min rule
  seed_state
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  processed_mtime_iso=$(jq -nr --argjson n "$(stat -c %Y "$processed" 2>/dev/null || stat -f %m "$processed")" '$n | todate')
  run jq -e --arg h "$processed_mtime_iso" '.high_water == $h' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# loopback gate (S3 / T12)
# ===========================================================================

setup_transcripts_with_events() {
  local root canary
  root=$(setup_transcripts_config)
  canary="CANARY-LOOPBACK"
  mkdir -p "$root/proj"
  local f="$root/proj/sess.jsonl"
  write_transcript_fixture "$f" "$canary"
  set_mtime_ago "$f" 600
  seed_state
  # Non-default, and in the past of both the real clock and the fixture mtime:
  # the cursor emitter, a max_hw emitter and a hard-coded floor are then three
  # distinct values instead of all reading 1970-01-01T00:00:00Z.
  mark_high_water transcripts "\"$(iso_at 1784047446)\""
}

@test "loopback gate: reachable remote host without consent -> deferred (S3 isolated, T1)" {
  setup_transcripts_with_events
  export LLM_BACKEND=openai
  # Make the remote host genuinely REACHABLE by the backend (trusted + online
  # mock answers), so the reachability probe SUCCEEDS. The only thing that can
  # still force `deferred` is the S3 egress gate itself refusing a non-loopback
  # host without allow_remote_llm. This isolates S3: if S3 were removed, the
  # probe would pass and Stage 2 would run (deferred=false) — so this test goes
  # red when the gate is disabled, which the previous unreachable-host version
  # could not (the host-trust backstop masked it).
  export OPENAI_HOST="http://remote-host.example.com:8080"
  export OPENAI_HOSTS="http://remote-host.example.com:8080"
  export LLM_TRUSTED_HOSTS="remote-host.example.com"
  setup_llm_online_mock

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.deferred == true' <<<"$DOC"
  [ "$status" -eq 0 ]
  # The deferred emitter carries the healed read-in cursor (see the offline
  # canary case); `null` would make the orchestrator skip mark-run, and a
  # hard-coded floor would be indistinguishable from it under a seeded default.
  run jq -e --arg hw "$(iso_at 1784047446)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"CANARY-LOOPBACK"* ]]
  [[ "$ERR" != *"CANARY-LOOPBACK"* ]]
}

@test "loopback gate: loopback host + online mock -> Stage 2 runs" {
  setup_transcripts_with_events
  export LLM_BACKEND=openai
  export OPENAI_HOST="http://127.0.0.1:8080"
  setup_llm_online_mock

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.deferred == false' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "loopback gate: remote host + allow_remote_llm=true -> Stage 2 runs" {
  local root canary
  root="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$root/proj"
  write_config --arg r "$root" \
    '.sources.transcripts.enabled = true | .sources.transcripts.root = $r
     | .sources.transcripts.allow_remote_llm = true | .sources.artifacts.enabled = false'
  canary="CANARY-ALLOWREMOTE"
  local f="$root/proj/sess.jsonl"
  write_transcript_fixture "$f" "$canary"
  set_mtime_ago "$f" 600
  seed_state
  export LLM_BACKEND=openai
  export OPENAI_HOST="http://remote-host.example.com:8080"
  setup_llm_online_mock

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.deferred == false' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "loopback gate: mixed loopback+remote host list -> deferred (fail-closed)" {
  setup_transcripts_with_events
  export LLM_BACKEND=openai
  export OPENAI_HOSTS="127.0.0.1:8080 remote-host.example.com:8080"
  setup_llm_online_mock

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.deferred == true' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# HIGH-WATER computation per mode (summary re-assertions across sources)
# ===========================================================================

@test "artifacts: high_water is per-repo (two repos, independent cursors)" {
  local repo1="$BATS_TEST_TMPDIR/repo1" repo2="$BATS_TEST_TMPDIR/repo2"
  mkdir -p "$repo1/docs/archive/review" "$repo2/docs/archive/review"
  write_config --arg r1 "$repo1" --arg r2 "$repo2" \
    '.sources.artifacts.repos = [$r1, $r2] | .sources.github.enabled = false'
  echo "x" > "$repo1/docs/archive/review/a.md"
  echo "y" > "$repo2/docs/archive/review/b.md"
  seed_state
  mark_high_water artifacts "{\"$repo1\": \"1970-01-01T00:00:00Z\", \"$repo2\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo1" '.high_water[$r] != null' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg r "$repo2" '.high_water[$r] != null' <<<"$DOC"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# helper unit group (C0) — the primitives every contract rests on
# ===========================================================================

# Sourcing the hook in `scrub` mode exposes the helpers without running a
# cmd_*: `scrub` reads stdin and has no `exit`, so the dispatch returns.
# `llm-utils.sh` is sourced too because `_llm_file_mtime_epoch` lives there — it has
# three consumers that never load this hook, so defining it here would silently
# undefine it for them.
HELPER_PRELUDE="source '$REPO_ROOT/hooks/llm-utils.sh' 2>/dev/null; source '$SCRIPT' scrub </dev/null >/dev/null 2>&1;"
helper() { run bash -c "$HELPER_PRELUDE $1"; }

@test "helpers: _iso_to_epoch and _epoch_to_iso round-trip against literals, both directions" {
  helper '_iso_to_epoch 2026-07-14T16:44:06Z'; [ "$output" = "1784047446" ]
  # Asserted against a LITERAL in each direction, never as f(g(x)) == x, which
  # two functions wrong in mirrored ways both satisfy.
  helper '_epoch_to_iso 1784047446'; [ "$output" = "2026-07-14T16:44:06Z" ]
}

@test "helpers: _iso_to_epoch expands the date-only spelling mark-run stores unnormalized" {
  helper '_iso_to_epoch 2026-07-31'; [ "$output" = "1785456000" ]
}

@test "helpers: _iso_to_epoch clamps a pre-1970 cursor and is silent on both arms" {
  # _is_iso accepts 1969-12-31; jq's fromdate returns -86400. A representable
  # instant before the epoch is not corrupt, so it must not be reported as one.
  #
  # NO `2>/dev/null`: `run` merges stderr into $output, so suppressing it made
  # "silently" unassertable — a warning added to the clamp arm stayed green.
  # The function never writes to stderr on any arm; the CALLER owns the
  # unparseable-cursor warning, which is why both arms below expect bare values.
  run bash -c "$HELPER_PRELUDE _iso_to_epoch 1969-12-31"
  [ "$output" = "0" ]
  helper '_iso_to_epoch 2026-13-45'; [ -z "$output" ]
  helper '_iso_to_epoch not-a-date'; [ -z "$output" ]
}

@test "helpers: _iso_to_epoch is not injectable — the operand cannot choose its own epoch" {
  # The interpolated spelling `jq -nr "\"$iso\" | fromdate"` satisfies every
  # other assertion in this group while returning 4102444800 here (and can read
  # the process environment via jq's `env`). This is the only case that
  # separates the two implementations.
  helper '_iso_to_epoch '"'"'x" | 4102444800 # '"'"''
  [ -z "$output" ]
}

@test "helpers: _epoch_to_iso refuses a value outside the shape _validate_hw accepts" {
  # jq's todate emits 5- and 7-digit years; _is_iso anchors on ^[0-9]{4}, and
  # _validate_hw rejects the WHOLE high_water object on one bad value.
  helper '_epoch_to_iso 253402300800'; [ -z "$output" ]
  helper '_epoch_to_iso 0'; [ "$output" = "1970-01-01T00:00:00Z" ]
}

@test "helpers: _heal_cursor compares as an integer, not lexicographically" {
  # [[ "999999999" > "1784047446" ]] is TRUE. A string comparison would heal
  # away every cursor written before 2001-09-09. Every other fixture in this
  # file uses ten-digit epochs, where the two comparisons agree.
  run bash -c "$HELPER_PRELUDE _heal_cursor 999999999 1784047446 artifacts persisted 2>/dev/null"
  [ "$output" = "999999999" ]
}

@test "helpers: _heal_cursor boundary — at now no heal, one second past resets to the floor" {
  run bash -c "$HELPER_PRELUDE _heal_cursor 1784047446 1784047446 artifacts persisted 2>/dev/null"
  [ "$output" = "1784047446" ]
  run bash -c "$HELPER_PRELUDE _heal_cursor 1784047447 1784047446 artifacts persisted 2>/dev/null"
  [ "$output" = "0" ]
}

@test "helpers: _heal_cursor with no clock returns the value unchanged" {
  run bash -c "$HELPER_PRELUDE _heal_cursor 4102444800 '' artifacts persisted 2>/dev/null"
  [ "$output" = "4102444800" ]
}

@test "helpers: _llm_file_mtime_epoch keeps the two stat arms' exit statuses distinct" {
  local f="$BATS_TEST_TMPDIR/m.txt"; echo x > "$f"
  set_mtime_frac "$f" 1784047446 0
  helper "_llm_file_mtime_epoch '$f'"; [ "$output" = "1784047446" ]

  # `$(a || b)` concatenates BOTH stdouts when `a` prints and then fails, and
  # no numeric guard can tell "123456" from "123" then "456".
  cat > "$BATS_TEST_TMPDIR/stat" <<'EOF'
#!/bin/bash
case "$1" in
  -c) printf '123'; exit 1 ;;
  -f) printf '456'; exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/stat"
  PATH="$BATS_TEST_TMPDIR:$PATH" run bash -c "$HELPER_PRELUDE _llm_file_mtime_epoch '$f'"
  [ "$output" = "456" ]
}

@test "helpers: _repo_relative fails closed to the basename when the strip is a no-op" {
  helper '_repo_relative /a/b/docs/x.md /a/b';       [ "$output" = "docs/x.md" ]
  helper '_repo_relative /a/b/docs/x.md /a/b/';      [ "$output" = "docs/x.md" ]
  # Physical resolved path against a lexical (symlinked) root: the strip cannot
  # match, so no absolute path — and therefore no $HOME — reaches stderr.
  helper '_repo_relative /a/real/docs/x.md /a/link'; [ "$output" = "x.md" ]
}

# ===========================================================================
# cursor survival across the loop's guards (the round-2/3 Critical)
# ===========================================================================
#
# retro-state.sh writes `.high_water = $hw` as a WHOLE-OBJECT REPLACEMENT, so a
# repo missing from the emitted map is DELETED from state, reset to 1970, and
# re-mined in full — re-sending its whole archive to the LLM when
# allow_remote_llm is set. The seed pass runs over the CONFIGURED ARRAY before
# the scan loop, so no guard inside that loop can drop a key.

setup_two_repos() {
  local a="$BATS_TEST_TMPDIR/repoA" b="$BATS_TEST_TMPDIR/repoB"
  mkdir -p "$a/docs/archive/review" "$b/docs/archive/review"
  write_config --arg a "$a" --arg b "$b" \
    '.sources.artifacts.repos = [$a, $b] | .sources.github.enabled = false'
  printf '%s %s' "$a" "$b"
}

@test "artifacts: a repo whose ROOT is absent keeps its persisted cursor" {
  local a b; read -r a b <<<"$(setup_two_repos)"
  echo x > "$a/docs/archive/review/a.md"
  seed_state
  mark_high_water artifacts "{\"$a\": \"1970-01-01T00:00:00Z\", \"$b\": \"$(iso_at 1784047446)\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  rm -rf "$b"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg b "$b" '.high_water | has($b)' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg b "$b" --arg hw "$(iso_at 1784047446)" '.high_water[$b] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  # The silence was half the defect: a dropped repo and a drained repo were
  # byte-identical on both channels.
  [[ "$ERR" == *"repoB"* ]]
  [[ "$ERR" == *"root absent"* ]]
  # ...and the diagnostic names the repo WITHOUT its absolute path.
  [[ "$ERR" != *"$b"* ]]
  [[ "$ERR" != *"$HOME"* ]]
}

@test "artifacts: a repo whose ARCHIVE DIR is absent keeps its persisted cursor" {
  local a b; read -r a b <<<"$(setup_two_repos)"
  echo x > "$a/docs/archive/review/a.md"
  seed_state
  mark_high_water artifacts "{\"$a\": \"1970-01-01T00:00:00Z\", \"$b\": \"$(iso_at 1784047446)\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  rm -rf "$b/docs"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg b "$b" --arg hw "$(iso_at 1784047446)" '.high_water[$b] == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"archive directory absent"* ]]
}

@test "artifacts: a skipped repo whose cursor is POISONED emits the healed value, not the poison" {
  # "equals the persisted value" alone is satisfied by a seed that bypasses the
  # heal — which would re-persist 2100-01-01 for exactly the repo the seed
  # exists to protect.
  local a b; read -r a b <<<"$(setup_two_repos)"
  echo x > "$a/docs/archive/review/a.md"
  seed_state
  mark_high_water artifacts "{\"$a\": \"1970-01-01T00:00:00Z\", \"$b\": \"2100-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784047446
  rm -rf "$b"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e --arg b "$b" '.high_water[$b] == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"past the present"* ]]
}

@test "artifacts: no configured repos emits high_water null, never an empty object" {
  # `{}` passes _validate_hw trivially and the whole-object replacement then
  # wipes every repo's cursor in one write; `null` makes mark-run leave the
  # cursors alone.
  write_config '.sources.artifacts.repos = [] | .sources.github.enabled = false'
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water == null' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: a heal disables raw egress for the run, for EVERY repo" {
  # The poisoned repo is LAST. Deciding the egress verdict per repo inside the
  # scan loop passes a single-repo fixture while shipping the sane repo's raw
  # bytes off-machine on a run in which a heal fired.
  local a b; read -r a b <<<"$(setup_two_repos)"
  echo "Symptom: internal detail" > "$a/docs/archive/review/a.md"
  echo "Symptom: internal detail" > "$b/docs/archive/review/b.md"
  set_mtime_frac "$a/docs/archive/review/a.md" 1784047000 0
  set_mtime_frac "$b/docs/archive/review/b.md" 1784047000 0
  seed_state
  mark_high_water artifacts "{\"$a\": \"1970-01-01T00:00:00Z\", \"$b\": \"2100-01-01T00:00:00Z\"}"
  export LLM_BACKEND=openai
  export LLM_MOCK_CONTENT="Symptom: a distilled bullet"
  export OPENAI_HOST="http://127.0.0.1:8080"
  setup_llm_online_mock
  export RETRO_PRESCREEN_NOW=1784047446

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # Both repos are mined — the heal bounds the CURSOR, not the candidate set...
  run jq -e '.candidates | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  # ...and no summary was produced, i.e. no raw artifact text was sent.
  run jq -e '[.candidates[].summary] | all(. == null)' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"not sent off-machine"* ]]
}

# ===========================================================================
# github: the local adjudicator this source never had
# ===========================================================================

@test "github: a PR at or below the cursor is not a candidate" {
  # Without a local suppression predicate the server's `updated:>=` filter is
  # the only thing deciding membership — the same shape as the `find -newer`
  # pre-filter this change deletes — and LAG_MARGIN would re-mine the trailing
  # day on every run, forever.
  setup_github_config
  seed_state
  mark_high_water github '{"acme/widgets": "2026-07-01T00:00:00Z"}'
  export GH_PR_LIST_JSON='[{"number":1,"title":"old","updatedAt":"2020-01-01T00:00:00Z"},{"number":2,"title":"new","updatedAt":"2026-07-20T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].number == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] == "2026-07-20T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: an unparseable updatedAt keeps the PR and does not advance the cursor" {
  setup_github_config
  seed_state
  mark_high_water github '{"acme/widgets": "2026-07-01T00:00:00Z"}'
  export GH_PR_LIST_JSON='[{"number":9,"title":"junk","updatedAt":"not-a-date"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] == "2026-07-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unparseable updatedAt"* ]]
}

@test "github: gh absent still emits the healed cursor rather than an empty document" {
  # `_json_empty`'s null made the orchestrator skip mark-run entirely, so
  # last_run never advanced and a poisoned cursor survived the degraded run.
  setup_github_config
  seed_state
  mark_high_water github '{"acme/widgets": "2100-01-01T00:00:00Z"}'
  export RETRO_PRESCREEN_NOW=1784047446
  local sandbox="$BATS_TEST_TMPDIR/nogh-bin"
  mkdir -p "$sandbox"
  local tool real
  for tool in bash jq find date sha256sum awk sed grep cat stat dirname basename readlink perl mktemp; do
    real=$(command -v "$tool" 2>/dev/null) && ln -sf "$real" "$sandbox/$tool"
  done
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" RETRO_PRESCREEN_NOW=1784047446 PATH="$sandbox" \
    run --separate-stderr bash "$SCRIPT" github --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] == "1970-01-01T00:00:00Z"' <<<"$output"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# transcripts identity (F-R6) — both streams, at the producer
# ===========================================================================

@test "transcripts: the deferred document names no session file, on either stream" {
  # `counts` is projected onto BOTH the --json document (:750) and the human
  # report (:754), and a transcript's basename IS the session identity. Fixing
  # only the JSON projection left the human stream leaking.
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  local f="$root/proj/SESSCANARY-0000-0000.jsonl"
  write_transcript_fixture "$f" "irrelevant"
  set_mtime_ago "$f" 600
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  # Presence first — an absence assertion over an empty candidate list is
  # satisfied by the defect it is meant to catch.
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates | all(has("index") and (has("file") | not))' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates | all(.index | type == "number")' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"SESSCANARY"* ]]
  [[ "$ERR" != *"SESSCANARY"* ]]

  # The human stream is a second invocation, and it reads the same keys.
  # Presence FIRST: silencing the branch entirely satisfies both absence
  # assertions, and this fixture reaches no other human branch.
  run_prescreen transcripts
  [ "$status" -eq 0 ]
  [[ "$DOC" == *"deferred (counts only, no content)"* ]]
  [ "$(grep -c '^  - session ' <<<"$DOC")" -eq 1 ]
  [[ "$DOC" != *"SESSCANARY"* ]]
  [[ "$ERR" != *"SESSCANARY"* ]]
}

# ===========================================================================
# C8 conformance gate — the deleted mechanism stays deleted
# ===========================================================================
#
# A gate, not a hand-run grep: bash 3.2 and BSD `stat` are not executable here
# (VC1/VC2), so this is the ONLY enforcement those constraints have, and a
# hand-run step with no caller is no enforcement at all.
#
# Every row carries a must-MATCH and a must-NOT-match example, and both are
# asserted for every pattern. Two rounds of review produced three regexes that
# denied conformant code — `date -[ud][[:space:]]` matched the `date -u +%s`
# the clock read requires, an array pattern matched the guarded idiom the hook
# mandates, and a `jq` pattern matched every correct `--arg` call. Reviewing a
# regex by eye does not catch that; asserting its negative example does.
#
# The must-NOT-match examples are drawn from the SUBJECT'S OWN vocabulary
# (`candidate`, `updated_at`, `${a[@]+...}`), because that is where the false
# positives came from — a negative example invented from the retired construct
# cannot detect them.
# Every file this change edits, not just the hook: `_llm_file_mtime_epoch` — the C1
# helper the whole stat-portability row exists for — LIVES in llm-utils.sh, and
# retro-state.sh carries the C13 due heal. A `date -j` or `declare -A`
# reappearing in either was invisible while the subject was $SCRIPT alone.
gate_subjects() {
  printf '%s\n' "$SCRIPT" "$REPO_ROOT/hooks/llm-utils.sh" "$REPO_ROOT/hooks/retro-state.sh"
}

forbidden_rows() {
  cat <<'ROWS'
-newer|find "$d" -newer "$r"|find "$d" -maxdepth 1 -name "$p"
_mtime_ref_file|hw_ref=$(_mtime_ref_file "$c")|_llm_file_mtime_epoch "$f"
\bmapfile\b|\breadarray\b|mapfile -t a < <(f)|map_file_name=x
(^|[^+])"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"|for f in "${files[@]}"; do|for f in ${files[@]+"${files[@]}"}; do
touch -t|touch -t "$s" "$r"|touch "$f"
date -j|epoch=$(date -j -u -f %s "$e")|n=$(date -u +%s)
\bdate\b[^|;&]*-d[[:space:]]|e=$(date -u -d "$iso" +%s)|# a candidate path is handed to find -d for depth-first order
(declare|local|typeset) +-A|declare -A hw_map|declare -a hw_list
\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|last="${repos[-1]}"|last="${repos[1]}"
\bclamp|# clamped to now|healed=$(_heal_cursor "$e" "$n" "$s" persisted)
ROWS
}

@test "C8: the forbidden-pattern set has not shrunk" {
  # "Every row passes" is vacuous when a row is deleted. The count is the only
  # thing that notices a row removed, commented out, or lost to a merge — and a
  # silently-shrinking denylist is the same failure as a gate over an empty
  # subject, one level up. Bump this deliberately when adding a row.
  [ "$(forbidden_rows | grep -c .)" -eq 10 ]
}

@test "C8: the conformance gate examines every subject, each carrying a known token" {
  # R50 clause (ii): a gate that examined nothing reports the same green as a
  # gate that found nothing. A renamed file or a typo'd path must DENY here,
  # not shrink the scanned set silently.
  local src n=0
  while IFS= read -r src; do
    [ -s "$src" ]
    n=$((n + 1))
  done < <(gate_subjects)
  [ "$n" -eq 3 ]
  grep -qE 'cmd_artifacts'      "$SCRIPT"
  grep -qE '_llm_file_mtime_epoch'  "$REPO_ROOT/hooks/llm-utils.sh"
  grep -qE '_validate_hw'       "$REPO_ROOT/hooks/retro-state.sh"
}

@test "C8: every forbidden pattern matches its violating example and spares its conformant one" {
  local line pat yes no
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Rightmost two fields are the examples; everything before is the pattern,
    # which may itself contain `|` alternation.
    no="${line##*|}"; line="${line%|*}"
    yes="${line##*|}"; pat="${line%|*}"
    if ! printf '%s\n' "$yes" | grep -qE -- "$pat"; then
      echo "pattern does not match its violating example: $pat <- $yes"; return 1
    fi
    if printf '%s\n' "$no" | grep -qE -- "$pat"; then
      echo "pattern denies its conformant example: $pat <- $no"; return 1
    fi
  done < <(forbidden_rows)
}

@test "C8: no forbidden pattern appears in the shipped hook's CODE" {
  # The subject is code, not prose: a comment explaining why `-newer` was
  # deleted is documentation worth keeping, and a gate that forbids naming the
  # retired construct would push that explanation out of the file. Only
  # full-line comments are stripped, so an inline `# ...` cannot hide code.
  local subject="$BATS_TEST_TMPDIR/code-only.sh" src
  : > "$subject"
  while IFS= read -r src; do
    [ -s "$src" ]
    grep -v '^[[:space:]]*#' "$src" >> "$subject"
  done < <(gate_subjects)
  [ -s "$subject" ]
  # Positive evidence from EACH subject, so a renamed or emptied file denies
  # here rather than shrinking the scanned set silently.
  grep -qE 'cmd_artifacts' "$subject"
  grep -qE '_llm_file_mtime_epoch' "$subject"
  grep -qE '_validate_hw' "$subject"

  local line pat rc
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="${line%|*}"; line="${line%|*}"; pat="$line"
    # `cmd; rc=$?` aborts under bats' `set -e` before the assignment runs; the
    # `|| rc=$?` form is what actually captures a non-zero status here.
    rc=0
    grep -nE -- "$pat" "$subject" >/dev/null 2>&1 || rc=$?
    # Exactly 1 (clean), never merely non-zero: 2 means grep could not read the
    # subject, which is the case an `if ! grep -q ... 2>/dev/null` reports as
    # clean.
    if [ "$rc" -ne 1 ]; then
      echo "forbidden pattern present in code (or subject unreadable, rc=$rc): $pat"
      grep -nE -- "$pat" "$subject"; return 1
    fi
  done < <(forbidden_rows)
}

# Runs the SAME loop the gate runs, over each row's own violating example, so a
# row deleted, commented out, or typo'd into never matching reds here. Hardcoding
# one pattern proved only that `grep` finds a string the test had just inserted.
@test "C8: every row denies a subject carrying its own violating example" {
  local line pat yes subject rc
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="${line%|*}"; yes="${line##*|}"; pat="${line%|*}"
    subject="$BATS_TEST_TMPDIR/deny.sh"
    { grep -v '^[[:space:]]*#' "$SCRIPT"; printf '%s\n' "$yes"; } > "$subject"
    rc=0
    grep -qE -- "$pat" "$subject" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "gate does not deny its own violating example for: $pat <- $yes"; return 1
    fi
  done < <(forbidden_rows)
}

@test "C8: the gate denies a subject with the pre-filter reinserted (deny-side proof)" {
  local copy="$BATS_TEST_TMPDIR/mutant.sh"
  # Anchored on the shipped `find` predicate, so the mutant is a genuine
  # reinsertion of the deleted pre-filter rather than a no-op sed.
  sed 's|-maxdepth 1 -name "$glob_pat" -print0|-maxdepth 1 -name "$glob_pat" -newer "$ref" -print0|' \
    "$SCRIPT" | grep -v '^[[:space:]]*#' > "$copy"
  run grep -qE -- '-newer' "$copy"
  [ "$status" -eq 0 ]
}

@test "C10: no docstring describes a helper the change deleted" {
  local t
  for t in _mtime_ref_file _find_newer_args _now_iso _clamp_iso; do
    run grep -qF -- "$t" "$SCRIPT"
    [ "$status" -eq 1 ]
  done
  # The env seam that can disable a control is named in the header block.
  run bash -c "grep -n 'RETRO_PRESCREEN_NOW' '$SCRIPT' | head -1 | cut -d: -f1"
  [ "$output" -lt 40 ]
}

# ===========================================================================
# transcripts twins of the artifacts guards (cardinality, clock, stat)
# ===========================================================================
#
# Every transcripts fixture in this file was cardinality 1 — the one at
# `high_water = max mtime among PROCESSED files` has two files but the second is
# excluded by the 5-minute rule, so Stage 1 still saw one. `max_hw` accumulation
# across processed files was therefore unverified on this source while its
# artifacts twin was covered.

setup_two_transcripts() {
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  printf '%s' "$root"
}

# Both orderings, for the reason TC2 needs them: `find`'s order on ext4 is a
# function of the filename and invariant under creation sequence, so the mutant
# only reds when a qualifying file is traversed AFTER a strictly newer sibling.
@test "transcripts: two processed files, cursor takes the max (a-newer ordering)" {
  local root; root=$(setup_two_transcripts)
  write_transcript_fixture "$root/proj/a-sess.jsonl" x
  write_transcript_fixture "$root/proj/b-sess.jsonl" x
  set_mtime_frac "$root/proj/a-sess.jsonl" 1784047560 0
  set_mtime_frac "$root/proj/b-sess.jsonl" 1784047500 0
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047000)\""
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"
  export RETRO_PRESCREEN_NOW=1784048000

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e --arg hw "$(iso_at 1784047560)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: two processed files, cursor takes the max (b-newer ordering)" {
  local root; root=$(setup_two_transcripts)
  write_transcript_fixture "$root/proj/a-sess.jsonl" x
  write_transcript_fixture "$root/proj/b-sess.jsonl" x
  set_mtime_frac "$root/proj/a-sess.jsonl" 1784047500 0
  set_mtime_frac "$root/proj/b-sess.jsonl" 1784047560 0
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047000)\""
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"
  export RETRO_PRESCREEN_NOW=1784048000

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e --arg hw "$(iso_at 1784047560)" '.high_water == $hw' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: a non-numeric clock does not exclude every session" {
  # An empty now_epoch made `$(( 0 - f_epoch ))` negative, so the 5-minute rule
  # excluded EVERY transcript — F-R3 inverted over the whole source, by a value
  # that passes C3's numeric validation nowhere but reaches the rule anyway.
  local root; root=$(setup_two_transcripts)
  write_transcript_fixture "$root/proj/sess.jsonl" x
  set_mtime_ago "$root/proj/sess.jsonl" 600
  seed_state
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"
  export RETRO_PRESCREEN_NOW="not-a-number"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"bounds disabled"* ]]
  # The guard's own observable. Without `[ -n "$now_epoch" ]` the comparison
  # runs with an empty operand and `test` writes a diagnostic to stderr, once
  # per file, on a stream whose whole purpose is single-line signals.
  #
  # Asserted as "every stderr line is one of ours" rather than by matching the
  # shell's wording: that wording is LOCALE-DEPENDENT (it is "整数の式が予期され
  # ます" under ja_JP), so an English substring check silently never fires.
  local stray
  stray=$(grep -cv '^retro-prescreen:' <<<"$ERR" || true)
  [ "$stray" -eq 0 ]
}

@test "transcripts: a non-numeric mtime keeps the file rather than dropping it" {
  local root; root=$(setup_two_transcripts)
  write_transcript_fixture "$root/proj/sess.jsonl" x
  set_mtime_ago "$root/proj/sess.jsonl" 600
  seed_state
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="a generic distilled lesson"
  setup_llm_online_mock
  export OPENAI_HOST="http://127.0.0.1:8080"

  # `stat` exiting 0 with non-numeric output: the value must not become a
  # comparable zero, which would read as "older than any cursor" and drop it.
  cat > "$BATS_TEST_TMPDIR/stat" <<'EOF'
#!/bin/bash
echo "not-a-number"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/stat"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length > 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water == "1970-01-01T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unreadable mtime"* ]]
}

# ===========================================================================
# github: the per-repo cursor map (the artifacts twin was covered, this was not)
# ===========================================================================

@test "github: two repos keep independent cursors in one emitted map" {
  # retro-state.sh applies high_water as a WHOLE-OBJECT replacement, so a loop
  # that overwrites rather than accumulates deletes every repo but the last.
  write_config '.sources.github.enabled = true
                | .sources.github.repos = ["acme/widgets", "acme/gadgets"]
                | .sources.artifacts.enabled = false'
  seed_state
  mark_high_water github '{"acme/widgets": "2026-07-01T00:00:00Z", "acme/gadgets": "2026-07-02T00:00:00Z"}'
  export GH_PR_LIST_JSON='[{"number":1,"title":"a","updatedAt":"2026-07-20T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water | keys | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/widgets"] == "2026-07-20T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water["acme/gadgets"] == "2026-07-20T00:00:00Z"' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "github: a malformed configured repo is skipped, not emitted as a key" {
  # The value becomes a high_water KEY, and _validate_hw's github arm requires
  # owner/repo — one bad element made it reject the whole object, which under
  # the run-for-its-own-status rule aborts the entire retrospect run.
  write_config '.sources.github.enabled = true
                | .sources.github.repos = ["acme/widgets", "https://github.com/o/r"]
                | .sources.artifacts.enabled = false'
  seed_state
  export GH_PR_LIST_JSON='[]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water | keys == ["acme/widgets"]' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"malformed repo"* ]]

  # ...and the emitted map round-trips through the consumer that rejects it.
  local hwf="$BATS_TEST_TMPDIR/hw-gh.json"
  jq -c '.high_water' <<<"$DOC" > "$hwf"
  run bash -c "RETRO_CONFIG='$CONFIG' RETRO_STATE='$STATE' RETRO_NOW='$NOW' bash '$STATE_CLI' mark-run github --high-water-file '$hwf'"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# the aggregate suppression diagnostics (R50 clause (ii)'s own signal)
# ===========================================================================
#
# N >= 2 in every case: at N = 1 the aggregate and per-file spellings are
# indistinguishable, and every artifacts fixture but one is cardinality 1.

@test "artifacts: suppressed files are reported as ONE aggregate line, not one per file" {
  local repo; repo=$(setup_artifacts_repo)
  local i
  for i in 1 2 3; do
    echo x > "$repo/docs/archive/review/old-$i.md"
    set_mtime_frac "$repo/docs/archive/review/old-$i.md" 1784047000 0
  done
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at 1784047500)\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784048000

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 0' <<<"$DOC"
  [ "$status" -eq 0 ]
  # Exactly one line, and it carries the counts — a per-file spelling gives 3.
  [ "$(grep -c 'at or below the cursor' <<<"$ERR")" -eq 1 ]
  [[ "$ERR" == *"3 of 3 at or below the cursor"* ]]
}

@test "transcripts: suppressed sessions are reported as ONE aggregate line" {
  local root; root=$(setup_two_transcripts)
  local i
  for i in 1 2 3; do
    write_transcript_fixture "$root/proj/s-$i.jsonl" x
    set_mtime_frac "$root/proj/s-$i.jsonl" 1784047000 0
  done
  seed_state
  mark_high_water transcripts "\"$(iso_at 1784047500)\""
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784048000

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [ "$(grep -c 'at or below the cursor' <<<"$ERR")" -eq 1 ]
  [[ "$ERR" == *"3 of 3 at or below the cursor"* ]]
}

@test "artifacts: future-dated files are reported as ONE aggregate line naming one exemplar" {
  local repo; repo=$(setup_artifacts_repo)
  local i
  for i in 1 2; do
    echo x > "$repo/docs/archive/review/ahead-$i.md"
    set_mtime_frac "$repo/docs/archive/review/ahead-$i.md" 1784049000 0
  done
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(iso_at 1784047000)\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  export RETRO_PRESCREEN_NOW=1784048000

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'future-dated' <<<"$ERR")" -eq 1 ]
  [[ "$ERR" == *"2 of 2 future-dated"* ]]
  # The exemplar is repo-relative, never absolute (F-R6).
  [[ "$ERR" != *"$repo"* ]]
  [[ "$ERR" != *"$HOME"* ]]
}

# ===========================================================================
# regression cover for the class members Phase 3 found still open
# ===========================================================================

@test "scout: a failed fetch preserves that URL's persisted hash" {
  # retro-state.sh applies high_water as a WHOLE-OBJECT replacement, so a URL
  # dropped from the emitted map is DELETED from state and reported as changed
  # on the next run that reaches it. One unreachable host used to do that; a run
  # where every fetch failed emitted `{}`, which _validate_hw accepts trivially
  # and which then wiped every hash.
  write_config '.sources.scout.enabled = true
                | .sources.scout.urls = ["https://a.example/x", "https://b.example/y"]
                | .sources.artifacts.enabled = false'
  seed_state
  local ha hb
  ha=$(printf 'a' | sha256sum | awk '{print $1}')
  hb=$(printf 'b' | sha256sum | awk '{print $1}')
  mark_high_water scout "{\"https://a.example/x\": \"$ha\", \"https://b.example/y\": \"$hb\"}"

  # Every fetch fails.
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
exit 7
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"

  run_prescreen scout --json
  [ "$status" -eq 0 ]
  run jq -e '.high_water | keys | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e --arg h "$ha" '.high_water["https://a.example/x"] == $h' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: a non-regular file matching the glob is rejected, not read" {
  # `< "$file"` on a FIFO blocks in `cat` before llm_request's timeout — which
  # bounds only curl — can apply, so the hook produced no document at all and
  # the orchestrator never called mark-run. One mkfifo in an untrusted sibling
  # repo denied the pipeline.
  local repo
  repo=$(setup_artifacts_repo)
  echo "real finding" > "$repo/docs/archive/review/real.md"
  mkfifo "$repo/docs/archive/review/trap.md" 2>/dev/null || skip "filesystem does not support FIFOs"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="Symptom: a bullet"
  export OPENAI_HOST="http://127.0.0.1:8080"
  setup_llm_online_mock

  # Bounded: without the terminal-type assertion this blocks in `cat` forever
  # (llm_request's timeout bounds only curl), and an unbounded hang is not a
  # red — it is a stalled suite. RT7 shape (g) requires the guard's absence to
  # surface as a failure.
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" \
    run --separate-stderr timeout 20 bash "$SCRIPT" artifacts --json
  DOC="$output"; ERR="$stderr"
  # 124 is `timeout`'s own status: the guard is gone and the read blocked.
  [ "$status" -ne 124 ]
  [ "$status" -eq 0 ]
  run jq -e '. | type == "object"' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '[.candidates[].path | test("real.md")] | all and (length == 1)' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"trap.md"* ]]
}

@test "github: the PR title passes the scrub, like the comment bodies" {
  # The file header states the scrub is invoked by every source that emits
  # free-text content. A merged-PR title is free-text from the same untrusted
  # API and reaches the --json document, the human report, the mining sub-agent
  # and from there a committed retrospective doc.
  setup_github_config
  seed_state
  export GH_PR_LIST_JSON='[{"number":7,"title":"leak victim@example.com key AKIAIOSFODNN7EXAMPLE","updatedAt":"2026-07-20T00:00:00Z"}]'
  export GH_PR_COMMENTS_BODY=""
  setup_gh_mock

  run_prescreen github --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].title | test("victim@example.com") | not' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].title | test("AKIAIOSFODNN7EXAMPLE") | not' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].title | test("REDACTED")' <<<"$DOC"
  [ "$status" -eq 0 ]

  # The human stream projects the same field.
  run_prescreen github
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"victim@example.com"* ]]
}

@test "artifacts: an in-repo symlink to a real artifact is still a candidate" {
  # The allow half of the non-regular-file rejection. `find -type f` would test
  # the LINK and drop this silently; the terminal-type assertion after the
  # symlink chase is what distinguishes it from a FIFO.
  local repo
  repo=$(setup_artifacts_repo)
  echo "real finding" > "$repo/docs/archive/review/target.md"
  ln -s "$repo/docs/archive/review/target.md" "$repo/docs/archive/review/link.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  # Both the link and its target resolve to the same contained regular file.
  run jq -e '.candidates | length == 2' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '[.candidates[].path | test("target.md")] | all' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: a symlink to a FIFO inside the repo is rejected" {
  # The arm `find -type f` cannot reach: the link itself is not a regular file
  # either way, so only the post-chase terminal-type assertion decides.
  local repo
  repo=$(setup_artifacts_repo)
  echo "real finding" > "$repo/docs/archive/review/real.md"
  mkfifo "$repo/docs/archive/review/pipe" 2>/dev/null || skip "filesystem does not support FIFOs"
  ln -s "$repo/docs/archive/review/pipe" "$repo/docs/archive/review/sneaky.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="Symptom: a bullet"
  export OPENAI_HOST="http://127.0.0.1:8080"
  setup_llm_online_mock

  # Bounded for the same reason as the direct-FIFO case above.
  RETRO_CONFIG="$CONFIG" RETRO_STATE="$STATE" RETRO_NOW="$NOW" \
    run --separate-stderr timeout 20 bash "$SCRIPT" artifacts --json
  DOC="$output"; ERR="$stderr"
  [ "$status" -ne 124 ]
  [ "$status" -eq 0 ]
  run jq -e '[.candidates[].path | test("real.md")] | all and (length == 1)' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$DOC" != *"sneaky.md"* ]]
}

@test "artifacts: an unparseable persisted cursor resets AND disables raw egress" {
  # `_is_iso` is a syntactic regex and `fromdate` is semantic, so 2026-13-01 is
  # storable through seed/mark-run and unreadable here. It resets the cursor to
  # the floor — making the whole corpus a candidate — so it must engage the same
  # egress gate a future cursor does. Keying that gate on the heal alone left
  # this cause, and the no-state-entry cause, shipping raw text.
  local repo
  repo=$(setup_artifacts_repo)
  write_config --arg r "$repo" \
    '.sources.artifacts.repos = [$r] | .sources.artifacts.allow_remote_llm = true | .sources.github.enabled = false'
  echo "Symptom: internal detail" > "$repo/docs/archive/review/a.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"2026-13-01T00:00:00Z\"}"
  export LLM_BACKEND=openai LLM_MOCK_CONTENT="Symptom: a distilled bullet"
  export OPENAI_HOST="http://remote-host.example.com:8080"
  export OPENAI_HOSTS="http://remote-host.example.com:8080"
  export LLM_TRUSTED_HOSTS="remote-host.example.com"
  setup_llm_online_mock

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates | length == 1' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.candidates[0].summary == null' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"unparseable persisted cursor"* ]]
  [[ "$ERR" == *"not sent off-machine"* ]]
}

@test "transcripts: a session id does not disable the freshness rule for OTHER sessions" {
  # The two exclusions are cumulative. Written as if/else, the session id — set
  # on every normal run — meant a concurrent session's in-flight .jsonl was
  # enumerated, extracted and sent raw to the backend.
  local root
  root=$(setup_transcripts_config)
  mkdir -p "$root/proj"
  write_transcript_fixture "$root/proj/mine.jsonl" x
  write_transcript_fixture "$root/proj/OTHERSESSION.jsonl" x
  set_mtime_ago "$root/proj/mine.jsonl" 600
  # The other session's file is being written right now.
  set_mtime_ago "$root/proj/OTHERSESSION.jsonl" 2
  export CLAUDE_SESSION_ID="mine"
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  # `mine` is excluded by identity, `OTHERSESSION` by freshness: nothing left.
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "artifacts: rejected candidates are counted and reported, not silently dropped" {
  # The containment escape is the highest-signal thing this hook can observe
  # about an untrusted repository, and four of _resolve_contained's five
  # rejection paths returned without a word.
  local repo
  repo=$(setup_artifacts_repo)
  local outside="$BATS_TEST_TMPDIR/outside-secret.md"
  echo "secret" > "$outside"
  ln -s "$outside" "$repo/docs/archive/review/escape.md"
  echo "real finding" > "$repo/docs/archive/review/real.md"
  seed_state
  mark_high_water artifacts "{\"$repo\": \"1970-01-01T00:00:00Z\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen artifacts --json
  [ "$status" -eq 0 ]
  run jq -e '[.candidates[].path | test("real.md")] | all and (length == 1)' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$ERR" == *"1 file(s) rejected"* ]]
  # ...and still without naming an absolute path (F-R6).
  [[ "$ERR" != *"$BATS_TEST_TMPDIR"* ]]
}
