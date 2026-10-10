#!/usr/bin/env bats
# Tests for hooks/commit-msg-check.sh — an advisory PreToolUse hook: it never
# blocks, and it must never emit a permission decision either, because
# Claude Code honours `{"decision": "approve"}` as an approval that skips the
# permission check for the commit.
#
# The local LLM is the system boundary, so the hook runs from a copy beside a
# stub llm-utils.sh whose llm_request prints $STUB_REVIEW.

bats_require_minimum_version 1.5.0

HOOK_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/commit-msg-check.sh"

setup() {
  HOOK_DIR="$BATS_TEST_TMPDIR/hooks"
  mkdir -p "$HOOK_DIR"
  cp "$HOOK_SRC" "$HOOK_DIR/commit-msg-check.sh"
  cat > "$HOOK_DIR/llm-utils.sh" <<'EOF'
llm_request() {
  cat >/dev/null
  printf '%s\n' "${STUB_REVIEW:-}"
}
EOF
}

run_hook() {
  local tool_name="$1"
  local command="$2"
  jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}' \
    | bash "$HOOK_DIR/commit-msg-check.sh"
}

@test "pass: non-Bash tool prints nothing" {
  run --separate-stderr run_hook Edit ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pass: Bash command that is not a commit prints nothing" {
  STUB_REVIEW="Use a conventional prefix" run --separate-stderr run_hook Bash "git status"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pass: unreachable LLM (empty review) prints nothing" {
  STUB_REVIEW="" run --separate-stderr run_hook Bash 'git commit -m "fix: x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggestion: shown as a systemMessage that carries no decision" {
  STUB_REVIEW='Say "why", not what' run --separate-stderr run_hook Bash 'git commit -m "stuff"'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.systemMessage')" = 'Commit message suggestion from local LLM: Say "why", not what' ]
  printf '%s' "$output" | jq -e 'has("decision") | not'
}

# A pass must print nothing. Claude Code honours `{"decision": "approve"}` as an
# approval that skips the permission check for the call, so an approve here
# would auto-approve every commit this hook reviews.
@test "regression: a call it lets through produces no decision" {
  STUB_REVIEW="OK" run --separate-stderr run_hook Bash 'git commit -m "fix: keep the permission check"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
