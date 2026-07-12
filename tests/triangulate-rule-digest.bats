#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/generate-triangulate-rule-digest.sh"

@test "generated triangulate rule digest is current" {
  run bash "$SCRIPT" "" "" --check
  [ "$status" -eq 0 ]
}

@test "explicit paths work outside a git repository" {
  work="$BATS_TEST_TMPDIR/non-git"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' '| R1 | Rule | Check | Major |' > "$source"
  run bash -c 'cd "$1" && bash "$2" "$3" "$4"' _ "$work" "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && bash "$2" "$3" "$4" --check' _ "$work" "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
}

@test "installed-layout defaults work outside a git repository" {
  work="$BATS_TEST_TMPDIR/installed"
  mkdir -p "$work/hooks" "$work/skills/triangulate" "$work/cwd"
  cp "$SCRIPT" "$work/hooks/generate-triangulate-rule-digest.sh"
  printf '%s\n' '| R1 | Rule | Check | Major |' > "$work/skills/triangulate/common-rules.md"

  run bash -c 'cd "$1" && bash "$2"' _ "$work/cwd" "$work/hooks/generate-triangulate-rule-digest.sh"
  [ "$status" -eq 0 ]
  grep -q '^| R1 | Rule | Major |$' "$work/skills/triangulate/common-rules.digest.md"
  run bash -c 'cd "$1" && bash "$2" "" "" --check' _ "$work/cwd" "$work/hooks/generate-triangulate-rule-digest.sh"
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

@test "severity extraction tolerates literal pipes in procedure cells" {
  work="$BATS_TEST_TMPDIR/pipes"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' \
    '| RS3 | Boundary validation | Detect `POST|PUT|PATCH` handlers | Major |' \
    '| RS6 | Escape ordering | Detect `/\|/g` before `\\` escaping | Major (Critical at injection sinks) |' \
    '| RT6 | Export coverage | Detect `function|class|const` exports | Major |' > "$source"

  run bash "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  grep -q '^| RS3 | Boundary validation | Major |$' "$digest"
  grep -q '^| RS6 | Escape ordering | Major (Critical at injection sinks) |$' "$digest"
  grep -q '^| RT6 | Export coverage | Major |$' "$digest"
}
