#!/usr/bin/env bats
# Tests for hooks/block-sensitive-files.sh — verifies the harness-config
# perimeter (~/.claude/hooks/*.sh, settings.json, CLAUDE.md) is denied
# while settings.local.json (the documented override path) remains
# editable, plus the existing secret/lock/.git protections.

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
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "approve: .env.example (template)" {
  run run_hook Edit "/repo/project/.env.example"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: credentials.json" {
  run run_hook Write "/repo/project/credentials.json"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: *.pem" {
  run run_hook Edit "/etc/ssl/server.pem"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: package-lock.json" {
  run run_hook Edit "/repo/project/package-lock.json"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: file inside .git/" {
  run run_hook Write "/repo/project/.git/config"
  [[ "$output" == *'"decision": "block"'* ]]
}

# ============================================================
# New protections — harness config perimeter (M6)
# ============================================================

@test "deny: ~/.claude/hooks/<name>.sh (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision": "block"'* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "deny: ~/.claude/hooks/block-destructive-docker.sh" {
  run run_hook Write "$HOME/.claude/hooks/block-destructive-docker.sh"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: ~/.claude/settings.json (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/settings.json"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: ~/.claude/CLAUDE.md (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/CLAUDE.md"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: literal ~/.claude/hooks/<name>.sh (un-expanded tilde)" {
  run run_hook Edit "~/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "deny: literal ~/.claude/settings.json (un-expanded tilde)" {
  run run_hook Edit "~/.claude/settings.json"
  [[ "$output" == *'"decision": "block"'* ]]
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
