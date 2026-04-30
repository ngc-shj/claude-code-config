#!/usr/bin/env bats
# Tests for hooks/block-vcs-history-rewrite.sh — verifies R31 (d) verb
# tokens are denied while safer alternatives (--force-with-lease,
# --force-if-includes) and benign git operations (incl. `reset --hard`)
# are approved.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-vcs-history-rewrite.sh"

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY cases — R31 (d) destructive verbs
# ============================================================

@test "deny: git push --force" {
  run run_hook Bash "git push --force"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git push --force origin main" {
  run run_hook Bash "git push --force origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git push -f" {
  run run_hook Bash "git push -f"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git push -f origin main" {
  run run_hook Bash "git push -f origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git push -fu (combined: force + set-upstream)" {
  run run_hook Bash "git push -fu origin feature/x"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git push -uf origin (combined alt order)" {
  run run_hook Bash "git push -uf origin feature/x"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: bash -c 'git push --force' (wrapper)" {
  run run_hook Bash "bash -c 'git push --force'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git filter-branch" {
  run run_hook Bash "git filter-branch --tree-filter 'rm secrets.txt' HEAD"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: git filter-repo" {
  run run_hook Bash "git filter-repo --invert-paths --path secrets/"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason recommends --force-with-lease" {
  run run_hook Bash "git push --force"
  [[ "$output" == *"force-with-lease"* ]]
}

@test "deny block reason mentions settings.local.json override path" {
  run run_hook Bash "git push -f"
  [[ "$output" == *"settings.local.json"* ]]
}

# ============================================================
# APPROVE cases — safer alternatives must NOT be blocked
# ============================================================

@test "approve: git push --force-with-lease" {
  run run_hook Bash "git push --force-with-lease"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push --force-with-lease=main" {
  run run_hook Bash "git push --force-with-lease=main origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push --force-if-includes" {
  run run_hook Bash "git push --force-if-includes origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE cases — git reset --hard intentionally NOT blocked here
# (existing settings.json permissions.deny covers direct invocations;
# blocking it would produce too many false positives in normal local
# workflow such as squash/fixup/rebase recovery)
# ============================================================

@test "approve: git reset --hard (this hook does not block; permissions.deny does)" {
  run run_hook Bash "git reset --hard HEAD~1"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE cases — benign git operations
# ============================================================

@test "approve: git push (no flags)" {
  run run_hook Bash "git push"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push origin main" {
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push -u origin feature/x (set-upstream, no force)" {
  run run_hook Bash "git push -u origin feature/x"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push --tags" {
  run run_hook Bash "git push --tags"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git filter (filter is a flag prefix, not a subcommand)" {
  # `git log --filter=...` — should not match filter-branch / filter-repo
  run run_hook Bash "git log --diff-filter=M"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git commit -m 'message'" {
  run run_hook Bash "git commit -m 'docs: update README'"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git fetch --force (this is fetch, not push)" {
  run run_hook Bash "git fetch --force origin"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: non-Bash tool (Edit)" {
  run run_hook Edit "/tmp/foo.txt"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: empty command" {
  run run_hook Bash ""
  [[ "$output" == *'"decision": "approve"'* ]]
}
