#!/usr/bin/env bats
# Tests for hooks/verify-references.sh
# Uses --root to point at an ephemeral fixture tree so tests never read real repo files.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/verify-references.sh"

setup() {
  export ROOT_DIR
  ROOT_DIR="$(mktemp -d)"
  mkdir -p "$ROOT_DIR/src" "$ROOT_DIR/lib"
  printf 'a\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"     # 5 lines
  printf '%s\n' one two three > "$ROOT_DIR/lib/bar.py"    # 3 lines
}

teardown() {
  rm -rf "$ROOT_DIR"
}

@test "empty stdin: reports total=0" {
  run bash -c "echo -n '' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=0"* ]]
}

@test "valid reference in range: reported as OK" {
  run bash -c "echo 'See src/foo.ts:3 for details.' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"src/foo.ts:3"* ]]
  [[ "$output" == *"total=1, ok=1, issues=0"* ]]
}

@test "nonexistent file: reported as MISSING" {
  run bash -c "echo 'check src/gone.ts:10' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]]
  [[ "$output" == *"src/gone.ts:10"* ]]
  [[ "$output" == *"total=1, ok=0, issues=1"* ]]
}

@test "out-of-range line: reported as OUT-OF-RANGE" {
  run bash -c "echo 'src/foo.ts:9999' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-RANGE"* ]]
  [[ "$output" == *"src/foo.ts:9999"* ]]
  [[ "$output" == *"file has 5 lines"* ]]
}

@test "range reference (start-end): verifies start line only" {
  run bash -c "echo 'src/foo.ts:2-4' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"src/foo.ts:2-4"* ]]
}

@test "non-filesystem refs (bare words): skipped" {
  # 'localhost:8080' and 'http:3000' should not be treated as file refs
  run bash -c "echo 'localhost:8080 and http:3000 are URIs, src/foo.ts:1 is a file' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1"* ]]
  [[ "$output" == *"src/foo.ts:1"* ]]
}

@test "duplicate refs: deduplicated" {
  run bash -c "printf 'src/foo.ts:1\nsrc/foo.ts:1\nsrc/foo.ts:1\n' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1"* ]]
}

@test "mixed refs: summary counts each category" {
  run bash -c "printf 'src/foo.ts:1\nsrc/gone.ts:5\nlib/bar.py:999\n' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=3, ok=1, issues=2"* ]]
}

@test "unknown flag: exits 1" {
  run bash "$SCRIPT" --bogus arg
  [ "$status" -eq 1 ]
}
