#!/usr/bin/env bats
# Tests for install.sh — focus on M8: pre-flight settings.json JSON
# validation and post-install hook executability check.

bats_require_minimum_version 1.5.0

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"

# install.sh writes to $HOME/.claude. We isolate by setting HOME to a
# temp dir per test, then run install.sh from a SCRIPT_DIR copy that
# we can mutate (e.g., to inject a malformed settings.json).

setup() {
  TEST_HOME="$(mktemp -d)"
  STAGING="$(mktemp -d)"
  # Stage a minimal SCRIPT_DIR layout matching install.sh expectations.
  cp "$REPO_DIR/install.sh" "$STAGING/install.sh"
  chmod +x "$STAGING/install.sh"
  cp "$REPO_DIR/CLAUDE.md" "$STAGING/CLAUDE.md"
  cp "$REPO_DIR/settings.json" "$STAGING/settings.json"
  mkdir -p "$STAGING/hooks"
  # Copy at least one hook so the for-loop executes.
  cp "$REPO_DIR/hooks/block-sensitive-files.sh" "$STAGING/hooks/"
  # Skip skills/ and rules/ for speed — they are independent of M8 tests.
}

teardown() {
  rm -rf "$TEST_HOME" "$STAGING"
}

@test "install: well-formed settings.json proceeds and installs" {
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed settings.json"* ]]
  [[ "$output" == *"Installed hook: block-sensitive-files.sh"* ]]
  [[ "$output" == *"Done."* ]]
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
}

@test "install: malformed settings.json (trailing comma) is rejected before install" {
  # Inject a malformed settings.json into the staging copy.
  printf '{"permissions":{"deny":["Bash(foo)",]}}' > "$STAGING/settings.json"
  # Pre-create a sentinel so we can verify it survives the failed install.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"sentinel":true}' > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]] || [[ "$output" == *"Refusing to install"* ]]
  # Sentinel survived — the malformed file did NOT clobber the previous good copy.
  grep -q sentinel "$TEST_HOME/.claude/settings.json"
}

@test "install: malformed settings.json (unclosed brace) is rejected" {
  printf '{"permissions":{"deny":[' > "$STAGING/settings.json"
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "install: merges into existing settings.json, preserving user top-level keys" {
  # Pre-existing live settings with a user-managed key the template does not own.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"mcpServers":{"ollama":{"command":"x"}},"permissions":{"deny":["Bash(stale)"]}}' \
    > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged settings.json"* ]]

  # User's mcpServers survived the merge.
  run jq -e '.mcpServers.ollama.command == "x"' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  # Template's permissions replaced the user's stale entry (template wins).
  run jq -e '.permissions.deny | index("Bash(stale)") == null' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  # A timestamped backup of the pre-merge file was written.
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  [ -f "${backups[0]}" ]
}

@test "install: merge replaces hooks wholesale (unmanaged event does not survive)" {
  # An attacker-seeded / stale live file with a hook event the template does
  # not own must NOT leak through the merge — permissions and hooks are
  # template-owned.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"evil.sh"}]}]}}' \
    > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  # The unmanaged PostToolUse event is gone; the merged hooks equal the template's.
  run jq -e '.hooks | has("PostToolUse")' "$TEST_HOME/.claude/settings.json"
  [ "$status" -ne 0 ]
}

@test "install: empty live settings.json is backed up and replaced, not aborted" {
  # Regression: jq `*` errors on a null/empty operand. An empty live file must
  # route to replace (exit 0), not abort the whole install.
  mkdir -p "$TEST_HOME/.claude"
  : > "$TEST_HOME/.claude/settings.json"   # zero-byte

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-object settings.json"* ]]
  run jq -e '.permissions' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  [ -f "${backups[0]}" ]
}

@test "install: non-object live settings.json (array) is backed up and replaced" {
  mkdir -p "$TEST_HOME/.claude"
  printf '[1,2,3]' > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-object settings.json"* ]]
  # Replaced with the template (an object with permissions), original preserved in backup.
  run jq -e 'type == "object"' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  grep -q '1,2,3' "${backups[0]}"
}

@test "install: hook chmod +x is verified post-install" {
  # Standard install path — verify executability is asserted.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  for hook in "$TEST_HOME/.claude/hooks"/*.sh; do
    [ -x "$hook" ]
  done
}

@test "install: removes a stale top-level hook not present in source" {
  # Source-of-truth sync: a renamed-away hook left in the live dir is purged.
  mkdir -p "$TEST_HOME/.claude/hooks"
  printf '#!/bin/bash\n' > "$TEST_HOME/.claude/hooks/ollama-utils.sh"
  chmod +x "$TEST_HOME/.claude/hooks/ollama-utils.sh"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed stale hook: ollama-utils.sh"* ]]
  [ ! -e "$TEST_HOME/.claude/hooks/ollama-utils.sh" ]
  # The source hook still installs.
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
}

@test "install: keeps a live hook that still exists in source" {
  # A hook present in the source must be overwritten, never removed by the sync.
  mkdir -p "$TEST_HOME/.claude/hooks"
  printf 'stale-content\n' > "$TEST_HOME/.claude/hooks/block-sensitive-files.sh"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Removed stale hook: block-sensitive-files.sh"* ]]
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
  # Content came from source (the staged copy), not the stale live one.
  ! grep -q 'stale-content' "$TEST_HOME/.claude/hooks/block-sensitive-files.sh"
}
