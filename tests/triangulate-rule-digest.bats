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
  mkdir -p "$work/hooks/lib" "$work/skills/triangulate" "$work/cwd"
  cp "$SCRIPT" "$work/hooks/generate-triangulate-rule-digest.sh"
  # install.sh copies hooks/lib/ (everything but node_modules), so the installed
  # layout carries the shared row parser too — stage it or this exercises a
  # layout that install.sh never produces.
  cp "$(dirname "$SCRIPT")/lib/md-rule-rows.awk" "$work/hooks/lib/"
  printf '%s\n' '| R1 | Rule | Check | Major |' > "$work/skills/triangulate/common-rules.md"

  run bash -c 'cd "$1" && bash "$2"' _ "$work/cwd" "$work/hooks/generate-triangulate-rule-digest.sh"
  [ "$status" -eq 0 ]
  grep -q '^| R1 | Rule | Major |$' "$work/skills/triangulate/common-rules.digest.md"
  run bash -c 'cd "$1" && bash "$2" "" "" --check' _ "$work/cwd" "$work/hooks/generate-triangulate-rule-digest.sh"
  [ "$status" -eq 0 ]
}

@test "committed digest ends with its truncation terminator, exactly once" {
  digest="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/triangulate/common-rules.digest.md"
  # Last NON-EMPTY line, and anchored: the digest is read whole as the routing
  # index and its tail is the RS*/RT* rows, so a reader that stops early loses
  # the security and testing checklists with nothing to notice it by.
  [ "$(sed '/^[[:space:]]*$/d' "$digest" | tail -1)" = '## END-OF-DIGEST' ]
  [ "$(grep -c '^## END-OF-DIGEST$' "$digest")" -eq 1 ]
}

@test "generated digest ends with its terminator, exactly once and last" {
  # The assertions above hold for the committed bytes; these hold for whatever
  # the generator emits. `--check`'s cmp pins the two together for staleness,
  # but it cannot see POSITION: emitting the terminator before the table would
  # keep cmp green while putting the marker inside the region a truncated read
  # already receives.
  work="$BATS_TEST_TMPDIR/terminator"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' \
    '| R1 | First rule | Major |' \
    '| RT9 | Last rule | Critical |' > "$source"

  run bash "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  [ "$(sed '/^[[:space:]]*$/d' "$digest" | tail -1)" = '## END-OF-DIGEST' ]
  [ "$(grep -c '^## END-OF-DIGEST$' "$digest")" -eq 1 ]
  # The row above it is the last table row: nothing may be appended after the
  # terminator either.
  [ "$(sed '/^[[:space:]]*$/d' "$digest" | tail -2 | head -1)" = '| RT9 | Last rule | Critical |' ]
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

@test "an ESCAPED pipe inside the severity cell survives into the digest" {
  # `Critical \| Major` is ONE Markdown cell containing "Critical". Splitting on
  # a bare pipe emits only the trailing "Major", so the escalation disappears
  # from the digest — the routing index a reviewer reads FIRST. And because
  # check-rule-sync.sh compares the digest against this generator's own output,
  # the staleness check confirms the truncated value rather than catching it:
  # the two agree because they are wrong the same way. That is why the parsing
  # lives in one shared library instead of a copy per caller.
  work="$BATS_TEST_TMPDIR/escaped"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' \
    '| R1 | Alpha | Ordinary procedure | Critical \| Major |' \
    '| R2 | Beta | Procedure with `a|b` inline | Major \| Minor |' > "$source"

  run bash "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  grep -q '^| R1 | Alpha | Critical \\| Major |$' "$digest"
  grep -q '^| R2 | Beta | Major \\| Minor |$' "$digest"
  # the failure mode this pins: the ceiling silently reduced to the trailing cell
  if grep -q '^| R1 | Alpha | Major |$' "$digest"; then false; fi
}

@test "the generator refuses to run without its shared row-parsing library" {
  # The library is what makes the generator and the linter agree. If it can go
  # missing and the generator still emits something, the digest becomes a
  # different parse of the same table — silently, since the row-count guard only
  # notices when EVERY row is lost.
  work="$BATS_TEST_TMPDIR/nolib"
  mkdir -p "$work/hooks/lib"
  cp "$SCRIPT" "$work/hooks/"
  printf '%s\n' '| R1 | Alpha | Procedure | Major |' > "$work/common.md"
  run bash "$work/hooks/$(basename "$SCRIPT")" "$work/common.md" "$work/digest.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"md-rule-rows.awk"* ]]
}
