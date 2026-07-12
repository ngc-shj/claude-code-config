#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/generate-triangulate-rule-digest.sh"

@test "generated triangulate rule digest is current" {
  run bash "$SCRIPT" "" "" --check
  [ "$status" -eq 0 ]
}

@test "digest generator extracts all rule families without descriptions" {
  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' \
    '| R1 | Shared helper | very long guidance | Major |' \
    '| RS2 | Secret rule | more guidance | Critical |' \
    '| RT3 | Test rule | still more guidance | Minor |' > "$source"

  run bash "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  grep -q '^| R1 | Shared helper | Major |$' "$digest"
  grep -q '^| RS2 | Secret rule | Critical |$' "$digest"
  grep -q '^| RT3 | Test rule | Minor |$' "$digest"
  ! grep -q 'very long guidance' "$digest"
}
