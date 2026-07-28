#!/usr/bin/env bats
# Tests for hooks/block-sensitive-files.sh — verifies the harness-config
# perimeter (~/.claude/hooks/*.sh, settings.json, CLAUDE.md) is denied
# while settings.local.json (the documented override path) remains
# editable, plus the existing secret/lock/.git protections.
#
# JSON whitespace contract (asymmetric, shared by all 7 block-*.sh hooks):
#   - approve decisions are emitted as `{"decision": "approve"}` (spaced)
#   - block decisions are emitted as `{"decision":"block","reason":...}` (compact)
# The asymmetry exists because block uses `printf` with a JSON template
# while approve uses bare `echo` of a hand-written literal. All 7 block-*.bats
# files (this one included) substring-match against this exact spacing.
# A future refactor that unifies the emit format (e.g., pipes both through
# jq) MUST update all 7 test files in the same diff — silently switching
# either format breaks the assertions here. The cleaner long-term fix is
# to parse `$output` via `jq -r '.decision'` in a helper, but that touches
# 7 files and was scoped out of the original fix.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-sensitive-files.sh"

run_hook() {
  local tool_name="$1"
  local file_path="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg p "$file_path" \
    '{tool_name:$n, tool_input:{file_path:$p}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# Existing protections (regression checks)
# ============================================================

@test "deny: .env file edit" {
  run run_hook Edit "/repo/project/.env"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve: .env.example (template)" {
  run run_hook Edit "/repo/project/.env.example"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: credentials.json" {
  run run_hook Write "/repo/project/credentials.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: *.pem" {
  run run_hook Edit "/etc/ssl/server.pem"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: package-lock.json" {
  run run_hook Edit "/repo/project/package-lock.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: file inside .git/" {
  run run_hook Write "/repo/project/.git/config"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# New protections — harness config perimeter (M6)
# ============================================================

@test "deny: ~/.claude/hooks/<name>.sh (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "deny: ~/.claude/hooks/block-destructive-docker.sh" {
  run run_hook Write "$HOME/.claude/hooks/block-destructive-docker.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/settings.json (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/settings.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/CLAUDE.md (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/CLAUDE.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/hooks/<name>.sh (un-expanded tilde)" {
  run run_hook Edit "~/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/settings.json (un-expanded tilde)" {
  run run_hook Edit "~/.claude/settings.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# Override exception — settings.local.json must stay editable (M6 design)
# ============================================================

@test "approve: ~/.claude/settings.local.json (override path)" {
  run run_hook Edit "$HOME/.claude/settings.local.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: literal ~/.claude/settings.local.json (un-expanded tilde)" {
  run run_hook Edit "~/.claude/settings.local.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# Approve cases — non-harness paths must not be blocked
# ============================================================

@test "approve: regular source file" {
  run run_hook Edit "/repo/project/src/main.go"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: README.md anywhere" {
  run run_hook Write "/repo/project/README.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: settings.json NOT under ~/.claude/ (e.g., a project's vscode settings)" {
  run run_hook Edit "/repo/project/.vscode/settings.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: hooks/<name>.sh NOT under ~/.claude/ (e.g., the source repo's hooks/)" {
  run run_hook Edit "/repo/claude-code-config/hooks/block-destructive-docker.sh"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: empty file_path (defensive default)" {
  run run_hook Edit ""
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: non-Edit tool (Bash falls through unchanged)" {
  # block-sensitive-files.sh only inspects file_path; other tool inputs
  # without a file_path approve by default.
  local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  run bash -c "printf '%s' '$input' | bash '$SCRIPT'"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# Installed skill perimeter (C6) — ~/.claude/skills/ is not a mirror of
# the repo's skills/, so editing the installed copy directly must be
# blocked the same way ~/.claude/hooks|settings.json|CLAUDE.md are.
# ============================================================

@test "deny: ~/.claude/skills/<name>/... (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

# The guarded set is install.sh's write set. skills/ and rules/ are installed by
# byte-for-byte the same `rm -rf "$dest"; cp -r` loop, and RTK.md /
# model-routing.md are copied alongside CLAUDE.md — covering one and not the
# others is the class-membership miss this suite exists to make loud.
@test "deny: ~/.claude/rules/<name>/... (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/rules/common/security.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/rules/<name>/... (un-expanded tilde)" {
  run run_hook Edit "~/.claude/rules/common/security.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/hooks/lib/<name> regardless of extension" {
  # install.sh rm -rf's and re-copies hooks/lib/ wholesale, and ast-runner.js
  # is the AST engine the detection hooks call — a .sh-only arm left the most
  # tripwire-adjacent file in the tree editable.
  run run_hook Edit "$HOME/.claude/hooks/lib/ast-runner.js"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/RTK.md and model-routing.md (CLAUDE.md's cited refs)" {
  run run_hook Edit "$HOME/.claude/RTK.md"
  [[ "$output" == *'"decision":"block"'* ]]
  run run_hook Edit "$HOME/.claude/model-routing.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve: ~/.claude/projects/<slug>/memory/*.md is not install-managed" {
  # Auto-memory is written by the running session and never overwritten by
  # install.sh; a guard that swept the whole of ~/.claude would break it.
  run run_hook Edit "$HOME/.claude/projects/some-slug/memory/feedback_example.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: literal ~/.claude/skills/<name>/... (un-expanded tilde)" {
  run run_hook Edit "~/.claude/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/skills/<name>/SKILL.md for a skill with no repo source names the unmanaged case" {
  # install.sh only removes/re-copies the skill directories it is about to
  # write (skills/*/ in the repo), so a skill absent from the repo (e.g.
  # "improve") survives every install untouched. Reusing the repo-managed
  # "edit there and run install.sh" message would be unfollowable guidance
  # here, so the skills arm must say so explicitly — asserting only that a
  # block occurred would not distinguish this branch from fixture 1's.
  run run_hook Edit "$HOME/.claude/skills/improve/SKILL.md"
  [[ "$output" == *'"decision":"block"'* ]]
  echo "$output" | grep -qF "If it has no repo source (install.sh only removes and re-copies the skills it manages, so an unmanaged skill survives every install untouched), add it to the repo's skills/ directory, or exempt it via ~/.claude/settings.local.json."
}

@test "approve: repo's own skills/ directory stays editable (not ~/.claude/skills/)" {
  # The whole "edit the repo, run install.sh" workflow — and this fix's own
  # implementation — depends on the repo copy never being caught by the
  # ~/.claude/skills/ arms above.
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  run run_hook Edit "$repo_root/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: ~/.claude/skills/... still blocked when HOME has a trailing slash" {
  # Regression for the fail-open bug: without normalizing $HOME, a
  # trailing-slash HOME turns "$HOME/.claude/..." into "…//.claude/…",
  # which never matches the single-slash path the tool reports, and the
  # guard silently approves instead of blocking. None of the fixtures
  # above can see this failure mode since they inherit the ambient $HOME.
  local input
  input=$(jq -nc --arg n "Edit" --arg p "$HOME/.claude/skills/triangulate/phases/phase-3-review.md" \
    '{tool_name:$n, tool_input:{file_path:$p}}')
  run bash -c "HOME='$HOME/' bash '$SCRIPT'" <<< "$input"
  [[ "$output" == *'"decision":"block"'* ]]
}
