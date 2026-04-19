#!/usr/bin/env bats
# Tests for hooks/scan-shared-utils.sh — focus on path containment (S4).

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/scan-shared-utils.sh"
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "no arg: defaults to git toplevel and runs successfully" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shared Utility Inventory"* ]]
}

@test "arg inside git toplevel: accepted" {
  run bash "$SCRIPT" "$REPO_ROOT/hooks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shared Utility Inventory"* ]]
}

@test "arg outside git toplevel (/etc): rejected with clear error" {
  run bash "$SCRIPT" /etc
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside TRUSTED_ROOT"* ]]
}

@test "arg outside git toplevel (HOME): rejected" {
  # $HOME is almost always outside a project repo.
  run bash "$SCRIPT" "$HOME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside TRUSTED_ROOT"* ]]
}

@test "nonexistent arg: rejected with clear error" {
  run bash "$SCRIPT" /nonexistent-path-xyz-12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "traversal arg (../../etc): rejected" {
  # From $REPO_ROOT/hooks, '../../etc' canonicalizes to a nonexistent sibling
  # of the repo parent — realpath -e fails first, producing "does not exist".
  # Either rejection path is safe (exit 1, never reaches cd/scan).
  run bash -c "cd '$REPO_ROOT/hooks' && bash '$SCRIPT' '../../etc'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside TRUSTED_ROOT"* || "$output" == *"does not exist"* ]]
}

