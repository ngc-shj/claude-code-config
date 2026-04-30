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

@test "install: hook chmod +x is verified post-install" {
  # Standard install path — verify executability is asserted.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  for hook in "$TEST_HOME/.claude/hooks"/*.sh; do
    [ -x "$hook" ]
  done
}
