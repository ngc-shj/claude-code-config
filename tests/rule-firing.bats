#!/usr/bin/env bats

TOOL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-firing/measure.py"

# A catalogue holding exactly the rules a test cares about. IDs are read from
# here, not from a hardcoded R1-R57 range, so the tool cannot drift out of date
# with the rule set it measures.
setup() {
  CAT="$BATS_TEST_TMPDIR/common-rules.md"
  printf '%s\n' \
    '| ID | Pattern | Procedure | Severity |' \
    '|---|---|---|---|' \
    '| R1 | Alpha | proc | Major |' \
    '| R2 | Beta | proc | Major |' \
    '| RT3 | Gamma | proc | Minor |' > "$CAT"
  REVIEWS="$BATS_TEST_TMPDIR/reviews"
  mkdir -p "$REVIEWS"
}

@test "a rule answered N/A in the Recurring Issue Check is checked, never a finding" {
  # This is the distinction the whole measurement rests on: R10 appeared in 270
  # real reviews and every one of them was a checklist line, not a defect.
  printf '%s\n' \
    '## Findings' \
    '### F1 [Major] something unrelated broke' \
    '- Problem: unrelated' \
    '' \
    '## Recurring Issue Check' \
    '- R1: N/A — no cycles here' \
    '- R2: checked, no issue' > "$REVIEWS/a-review.md"

  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *$'R1\t'*$'\t1\t0\t'* ]]
  [[ "$output" == *$'R2\t'*$'\t1\t0\t'* ]]
}

@test "a rule cited inside a severity-carrying finding counts as fired" {
  printf '%s\n' \
    '### F1 [Critical] R2: constant duplicated across three modules' \
    '- Problem: real defect' \
    '' \
    '## Recurring Issue Check' \
    '- R1: N/A' > "$REVIEWS/b-review.md"

  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *$'R2\t'*$'\t1\t1\t'* ]]
  [[ "$output" == *$'R1\t'*$'\t1\t0\t'* ]]
}

@test "the finding block ends at the next non-finding heading" {
  # Without this, every rule listed after a finding anywhere in the file would
  # be scored as having fired — which would make the dead-rule signal vanish.
  printf '%s\n' \
    '### F1 [Major] a real defect' \
    '- Problem: real' \
    '' \
    '## Recurring Issue Check' \
    '- R1: N/A' \
    '- R2: N/A' > "$REVIEWS/c-review.md"

  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *$'R1\t'*$'\t1\t0\t'* ]]
  [[ "$output" == *$'R2\t'*$'\t1\t0\t'* ]]
}

@test "an ID absent from the catalogue never reaches the raw counts" {
  # The table is driven by catalogue IDs, so a phantom rule cannot show up
  # there however the scan behaves — assert against --json, the one output that
  # would carry it, or the assertion tests nothing.
  printf '%s\n' '### F1 [Major] R99: not a rule in this catalogue' > "$REVIEWS/d-review.md"
  out="$BATS_TEST_TMPDIR/raw.json"
  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --tsv --json "$out"
  [ "$status" -eq 0 ]
  run grep -c 'R99' "$out"
  [ "$output" = "0" ]
}

@test "an ID embedded in a longer token is not counted" {
  # Both anchors carry weight and each fails differently: without the leading
  # one, "ERROR1" scores R1; without the trailing one, "R1x" does. R10 is a
  # live deletion candidate sitting on zero findings, so a pattern that picks
  # up incidental text would erase that zero for reasons having nothing to do
  # with the rule. The fixture carries no bare "R1" — a stray mention would let
  # the assertion pass on its own.
  printf '%s\n' \
    '### F1 [Major] ERROR1 raised by helper R1x during teardown' \
    '- Problem: real' > "$REVIEWS/f-review.md"

  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *$'R1\t'*$'\t0\t0\t'* ]]
}

@test "a rule whose age git cannot determine is never reported as dead" {
  # The fail-safe direction: "we could not date this rule" must not be spelled
  # the same as "this rule had its chance and never fired". Opportunities stay
  # 0, so the dead-rule list stays empty however many reviews checked it.
  for i in 1 2 3; do
    printf '%s\n' '## Recurring Issue Check' '- R1: N/A' > "$REVIEWS/e$i-review.md"
  done
  run python3 "$TOOL" --catalogue "$CAT" --glob "$REVIEWS/*-review.md" --mature 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"never fired with >=1 opportunities: 0"* ]]
}

@test "an empty match set fails loudly rather than reporting every rule dead" {
  # "examined nothing" must not be spelled "found nothing" — a typo'd glob that
  # silently produced a 74-rule deletion list is the failure this prevents.
  run python3 "$TOOL" --catalogue "$CAT" --glob "$BATS_TEST_TMPDIR/nothing-here/*.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no review artifacts matched"* ]]
}

@test "a catalogue with no rule rows fails loudly" {
  empty="$BATS_TEST_TMPDIR/empty.md"
  printf '%s\n' '# no rows here' > "$empty"
  run python3 "$TOOL" --catalogue "$empty" --glob "$REVIEWS/*-review.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no rule rows found"* ]]
}
