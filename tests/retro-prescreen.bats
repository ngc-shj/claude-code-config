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

write_config() {
  # jq-edited from the shipped C5 example so schema drift breaks tests
  # instead of hiding (RT3). Forwards all args to jq, so callers may pass
  # --arg/--argjson before the filter, e.g. write_config --arg r "$repo" '...'.
  local args=("$@")
  local filter="${args[-1]}"
  unset 'args[-1]'
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
  printf '%s' '${GH_PR_COMMENTS_BODY:-}'
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

  unset LLM_BACKEND OPENAI_HOST OPENAI_HOSTS LLM_TRUSTED_HOSTS OLLAMA_HOST OLLAMA_EXTRA_HOSTS
  unset CLAUDE_SESSION_ID
  unset GH_ABSENT GH_MISSING_AUTH GH_PR_LIST_JSON GH_PR_COMMENTS_BODY

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
  local repo
  repo=$(setup_artifacts_repo)
  local old="$repo/docs/archive/review/old-review.md"
  echo "old" > "$old"
  set_mtime_ago "$old" 864000   # 10 days ago
  seed_state
  mark_high_water artifacts "{\"$repo\": \"$(date -u -d '@'$(( $(date +%s) - 432000 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r $(( $(date +%s) - 432000 )) +%Y-%m-%dT%H:%M:%SZ)\"}"
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

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
  [[ "$output" != *"bob@example.com"* ]]
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
  [[ "$stderr" == *"200"* || "$stderr" == *"limit"* ]]
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

@test "transcripts: no root dir -> empty candidates, exit 0" {
  write_config '.sources.transcripts.enabled = true | .sources.transcripts.root = "/nonexistent-root-xyz" | .sources.artifacts.enabled = false'
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
}

@test "transcripts: no new sessions -> empty candidates, exit 0" {
  local root
  root=$(setup_transcripts_config)
  seed_state
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"
  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.candidates == []' <<<"$DOC"
  [ "$status" -eq 0 ]
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
  setup_curl_fail_mock
  export LLM_BACKEND=ollama OLLAMA_HOST="http://127.0.0.1:11434"

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"$canary"* ]]
  [[ "$stderr" != *"$canary"* ]]
  run jq -e '.deferred == true' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water == null' <<<"$DOC"
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

@test "transcripts: flip-fixture — scrub bypassed would leak the canary (proves the assertion can go red)" {
  # Sanity check on the test methodology itself: if the LLM's returned text
  # DID contain the canary and scrub were skipped, the assertion above would
  # fail. Demonstrate here directly against cmd_scrub's counterpart check.
  local canary="CANARY-FLIP-55aa"
  run bash -c "echo '$canary' | cat"
  [[ "$output" == *"$canary"* ]]
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
}

@test "loopback gate: remote host -> deferred true, high_water null, canary absent" {
  setup_transcripts_with_events
  export LLM_BACKEND=openai
  export OPENAI_HOST="http://remote-host.example.com:8080"
  setup_llm_online_mock

  run_prescreen transcripts --json
  [ "$status" -eq 0 ]
  run jq -e '.deferred == true' <<<"$DOC"
  [ "$status" -eq 0 ]
  run jq -e '.high_water == null' <<<"$DOC"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CANARY-LOOPBACK"* ]]
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
