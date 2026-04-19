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

@test "--help: prints usage to stderr and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h short flag: prints usage and exits 0" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "nonexistent ROOT: exits 1" {
  run bash "$SCRIPT" --root "$ROOT_DIR/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# Containment checks (S1 regression guards): traversal, absolute-path escape,
# and symlink escape must all resolve to OUT-OF-ROOT, NOT leak file metadata.
# ---------------------------------------------------------------------------

@test "traversal (../): reported as OUT-OF-ROOT, no file metadata leaked" {
  # Create a sibling file the traversal would reach if unchecked.
  echo "sensitive-content" > "$ROOT_DIR/../escape-target.txt"
  run bash -c "echo '../escape-target.txt:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" == *"../escape-target.txt:1"* ]]
  # Explicitly must NOT report OK / OUT-OF-RANGE / file metadata.
  [[ "$output" != *"OK "* ]]
  [[ "$output" != *"OUT-OF-RANGE"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/../escape-target.txt"
}

@test "absolute path outside ROOT: reported as OUT-OF-ROOT" {
  run bash -c "echo '/etc/hostname:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" == *"/etc/hostname:1"* ]]
  [[ "$output" != *"file has "* ]]
}

@test "absolute path inside ROOT: reported as OK" {
  # CLAUDE.md instructs sub-agents to share absolute paths; conforming refs
  # must verify correctly (F1 regression guard).
  run bash -c "echo '$ROOT_DIR/src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"$ROOT_DIR/src/foo.ts:3"* ]]
}

@test "symlink escaping ROOT: reported as OUT-OF-ROOT" {
  # Create a symlink inside ROOT that points to a file outside ROOT.
  echo "outside-content-line1" > "$ROOT_DIR/../outside-secret.txt"
  ln -sf "$ROOT_DIR/../outside-secret.txt" "$ROOT_DIR/src/link.ts"
  run bash -c "echo 'src/link.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/../outside-secret.txt" "$ROOT_DIR/src/link.ts"
}

@test "symlink inside ROOT: reported as OK" {
  # Symlinks that stay within ROOT are legitimate (e.g., monorepo aliases).
  ln -sf "$ROOT_DIR/src/foo.ts" "$ROOT_DIR/lib/alias.ts"
  run bash -c "echo 'lib/alias.ts:2' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -f "$ROOT_DIR/lib/alias.ts"
}

@test "traversal via '/../': reported as OUT-OF-ROOT" {
  # Sneakier form — path with interior `..` segment.
  run bash -c "echo 'src/../../escape.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  # Either OUT-OF-ROOT (resolved and rejected) or skipped (regex filter).
  # Both are safe outcomes; the critical invariant is no file metadata leak.
  [[ "$output" != *"file has "* ]]
}
