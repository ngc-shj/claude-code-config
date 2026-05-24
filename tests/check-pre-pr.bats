#!/usr/bin/env bats
# Tests for hooks/check-pre-pr.sh — verifies that `git push` and
# `gh pr create` are gated on the project's scripts/pre-pr.sh, while
# non-push commands and projects without the script are no-op.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/check-pre-pr.sh"

setup() {
  TMPREPO=$(mktemp -d)
  (cd "$TMPREPO" && git init -q && git config user.email t@t && git config user.name t)
  ORIG_PWD=$PWD
  cd "$TMPREPO"
  # Unset so the hook falls back to git rev-parse from $TMPREPO instead
  # of using whatever CLAUDE_PROJECT_DIR the test runner inherited.
  unset CLAUDE_PROJECT_DIR
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$TMPREPO"
}

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

write_script() {
  mkdir -p scripts
  printf '%s\n' "$@" > scripts/pre-pr.sh
  chmod +x scripts/pre-pr.sh
}

# ============================================================
# APPROVE — no-op cases
# ============================================================

@test "approve: non-Bash tool" {
  run run_hook Read ""
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: Bash with non-push command" {
  run run_hook Bash "ls -la"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push but no scripts/pre-pr.sh in repo" {
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gh pr create but no scripts/pre-pr.sh in repo" {
  run run_hook Bash "gh pr create --title foo --body bar"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git fetch (not a push verb)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git fetch origin"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git pushd (substring false-positive avoidance)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "pushd /tmp"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: 'git pushd' (verb extending 'push' must not match)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git pushd /some/repo"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: malformed JSON on stdin fails open" {
  run bash -c "printf 'garbage not json' | bash '$SCRIPT'"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$status" -eq 0 ]
}

@test "approve: chmod -x scripts/pre-pr.sh is treated as absent (hook gates on -x)" {
  write_script '#!/bin/bash' 'exit 1'
  chmod -x scripts/pre-pr.sh
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: outside any git repo, no CLAUDE_PROJECT_DIR" {
  cd /
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — pre-pr.sh passes
# ============================================================

@test "approve: git push and pre-pr.sh exits 0" {
  write_script '#!/bin/bash' 'echo ok' 'exit 0'
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gh pr create and pre-pr.sh exits 0" {
  write_script '#!/bin/bash' 'exit 0'
  run run_hook Bash "gh pr create --draft"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# BLOCK — pre-pr.sh fails
# ============================================================

@test "block: git push and pre-pr.sh exits non-zero" {
  write_script '#!/bin/bash' 'echo FAIL' 'exit 1'
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"pre-pr.sh"* ]]
}

@test "block: gh pr create and pre-pr.sh exits non-zero" {
  write_script '#!/bin/bash' 'exit 2'
  run run_hook Bash "gh pr create --title foo"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: git push --force-with-lease still gated by pre-pr.sh" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push --force-with-lease origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: rtk-rewritten git push still gated" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "rtk git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block reason contains pre-pr.sh stdout" {
  write_script '#!/bin/bash' 'echo SENTINEL_OUTPUT' 'exit 1'
  run run_hook Bash "git push"
  [[ "$output" == *"SENTINEL_OUTPUT"* ]]
}

# ============================================================
# BLOCK — shell-separator coverage (F1 fix)
# ============================================================

@test "block: 'git push;echo done' (semicolon separator)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push;echo done"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: 'git push|tee log' (pipe separator)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push|tee log"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: '(git push)' (subshell wrap)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "(git push)"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: 'git push&&echo done' (logical-and)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push&&echo done"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: symlinked scripts/pre-pr.sh still gated" {
  mkdir -p scripts target
  cat > target/real-pre-pr.sh <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x target/real-pre-pr.sh
  ln -s "$(pwd)/target/real-pre-pr.sh" scripts/pre-pr.sh
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# BLOCK — truncation branch (T1)
# ============================================================

@test "block: large pre-pr.sh output is tail-truncated and notes basename" {
  write_script '#!/bin/bash' \
    'python3 -c "import sys; sys.stdout.write(\"X\" * 5000); sys.stdout.write(\"\\nTAIL_SENTINEL\\n\")"' \
    'exit 1'
  run run_hook Bash "git push"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"truncated to last 4000 bytes"* ]]
  [[ "$output" == *"TAIL_SENTINEL"* ]]
  # Truncation note uses basename only — should not contain a leading slash
  # near the "preserved" word, only $TMPDIR/<basename>.
  [[ "$output" == *'preserved in $TMPDIR/pre-pr-gate.'* ]]
}

# ============================================================
# ESCAPE HATCH
# ============================================================

@test "approve: SKIP_PRE_PR_GATE=1 bypasses a failing script" {
  write_script '#!/bin/bash' 'exit 1'
  input=$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')
  run env SKIP_PRE_PR_GATE=1 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$input"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "SKIP_PRE_PR_GATE=1 emits stderr breadcrumb" {
  write_script '#!/bin/bash' 'exit 1'
  input=$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push"}}')
  # `run` merges stderr by default in bats 1.5+; the breadcrumb should appear.
  run env SKIP_PRE_PR_GATE=1 bash -c 'bash "$1" 2>&1' _ "$SCRIPT" <<<"$input"
  [[ "$output" == *"SKIP_PRE_PR_GATE=1"* ]]
  [[ "$output" == *"bypassing"* ]]
}

# ============================================================
# SKILL-DOC CONTRACT (T5)
# Ensures the /triangulate phase docs continue to reference
# scripts/pre-pr.sh literally — if the docs drift to a different name
# (e.g. `npm run pre-pr`), the hook's hardcoded path would silently
# diverge from the doc contract.
# ============================================================

@test "skill docs reference scripts/pre-pr.sh literally" {
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  grep -q 'scripts/pre-pr.sh' "$repo_root/skills/triangulate/phases/phase-2-coding.md"
  grep -q 'scripts/pre-pr.sh' "$repo_root/skills/triangulate/phases/phase-3-review.md"
}
