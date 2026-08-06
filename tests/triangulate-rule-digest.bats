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

@test "a DOUBLE backslash before a pipe is a delimiter, not an escape" {
  # The parity case, and the dangerous direction. `\|` is an escaped pipe, but
  # `\\|` is a literal backslash followed by a real delimiter — so R2's severity
  # is `Major`, not the whole procedure cell. A parser that matches "backslash
  # pipe" without counting the run treats both as escaped and merges the last
  # two cells, which makes a Procedure cell mentioning "Critical" read as the
  # severity: a ceiling check would then pass on text it never examined, in the
  # digest AND in the linter comparing against it.
  work="$BATS_TEST_TMPDIR/parity"
  mkdir -p "$work"
  source="$work/common.md"
  digest="$work/digest.md"
  printf '%s\n' \
    '| R1 | Alpha | one backslash is an escape `a \| b` | Critical \| Major |' \
    '| R2 | Beta | Check Critical paths \\| Major |' \
    '| R3 | Gamma | three is escape again `x \\\| y` | Minor |' > "$source"

  run bash "$SCRIPT" "$source" "$digest"
  [ "$status" -eq 0 ]
  # odd run: the pipe stays inside the severity cell
  grep -q '^| R1 | Alpha | Critical \\| Major |$' "$digest"
  # even run: the pipe splits, so the severity is just the trailing cell
  grep -q '^| R2 | Beta | Major |$' "$digest"
  grep -q '^| R3 | Gamma | Minor |$' "$digest"
  # the defect: R2's procedure text swallowed into the severity, carrying a
  # "Critical" that is not a ceiling at all
  if grep -q 'Check Critical paths' "$digest"; then false; fi
}

@test "the digest wires the Remedy Floor, and its extraction command extracts it" {
  # The Remedy Floor is a section, not a row, so anchored row extraction never
  # surfaces it — without this pointer the section is unreachable in deployment
  # (round-7 probe: zero of four reviewers read it; ablation: reviewers carrying
  # the pointer produce the floor's clauses, reviewers without it do not).
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  digest="$root/skills/triangulate/common-rules.digest.md"
  rules="$root/skills/triangulate/common-rules.md"

  grep -q 'Every `Fix:` you write must also satisfy the \*\*Remedy Floor\*\*' "$digest"
  grep -qF "awk '/^### Remedy Floor/,/^### Anti-Deferral/'" "$digest"

  # The extraction contract: the command the digest tells reviewers to run must
  # yield the section — non-empty, starting at its heading, containing all five
  # clauses, and bounded (not the rest of the file).
  section="$(awk '/^### Remedy Floor/,/^### Anti-Deferral/' "$rules")"
  [ -n "$section" ]
  [ "$(printf '%s\n' "$section" | head -1)" = '### Remedy Floor' ]
  printf '%s\n' "$section" | grep -q 'Pair the deny side with the allow side'
  printf '%s\n' "$section" | grep -q 'Red-prove each clause of the remedy separately'
  printf '%s\n' "$section" | grep -q 'Fail loudly when the check cannot run'
  printf '%s\n' "$section" | grep -q 'deleting what made the defect visible'
  printf '%s\n' "$section" | grep -q 'Name the boundary and the tie'
  [ "$(printf '%s\n' "$section" | tail -1)" = '### Anti-Deferral Rules' ]
}

@test "the digest wires the Finding Floor, and its extraction command extracts it" {
  # Same reachability problem as the Remedy Floor, measured the same way: with
  # the pointer, the Critical/Major findings that turn out not to be defects
  # fall from 4.12 per review to 1.62 while genuine defects reached stays flat
  # (round 12, n=8/arm, blind-adjudicated). Without it the section is a header
  # nothing routes to.
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  digest="$root/skills/triangulate/common-rules.digest.md"
  rules="$root/skills/triangulate/common-rules.md"

  grep -q 'Every finding you write must also satisfy the \*\*Finding Floor\*\*' "$digest"
  grep -qF "awk '/^### Finding Floor/,/^### Remedy Floor/'" "$digest"

  # The extraction contract: the command the digest names must yield the
  # section — non-empty, starting at its heading, carrying all three clauses,
  # and bounded by the next section rather than running to end of file.
  section="$(awk '/^### Finding Floor/,/^### Remedy Floor/' "$rules")"
  [ -n "$section" ]
  [ "$(printf '%s\n' "$section" | head -1)" = '### Finding Floor' ]
  printf '%s\n' "$section" | grep -q 'Point at the evidence inside the change'
  printf '%s\n' "$section" | grep -q 'requirement you cannot ground is a QUESTION'
  printf '%s\n' "$section" | grep -q 'preference is not a defect'
  [ "$(printf '%s\n' "$section" | tail -1)" = '### Remedy Floor' ]
}

@test "the generator emits the Finding Floor pointer for any source" {
  # Header text, not derived from the source rows: a regeneration from any
  # rules file must carry it, or a future header edit silently drops the only
  # route to the section.
  work="$BATS_TEST_TMPDIR/findptr"
  mkdir -p "$work"
  printf '%s\n' '| R1 | Rule | Check | Major |' > "$work/common.md"
  run bash "$SCRIPT" "$work/common.md" "$work/digest.md"
  [ "$status" -eq 0 ]
  grep -q 'Finding Floor' "$work/digest.md"
  grep -qF "awk '/^### Finding Floor/,/^### Remedy Floor/'" "$work/digest.md"
}

@test "the generator emits the Remedy Floor pointer for any source" {
  # The pointer is generator header text, not derived from the source rows — a
  # regeneration from any rules file must carry it, or a future header edit can
  # silently drop the only route to the section.
  work="$BATS_TEST_TMPDIR/floorptr"
  mkdir -p "$work"
  printf '%s\n' '| R1 | Rule | Check | Major |' > "$work/common.md"
  run bash "$SCRIPT" "$work/common.md" "$work/digest.md"
  [ "$status" -eq 0 ]
  grep -q 'Remedy Floor' "$work/digest.md"
  grep -qF "awk '/^### Remedy Floor/,/^### Anti-Deferral/'" "$work/digest.md"
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
