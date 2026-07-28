#!/usr/bin/env bats
# Tests for hooks/check-rule-sync.sh — rule-ID consistency linter for the
# triangulate skill files. The fixture list is DERIVED from the linter's
# check list (one red fixture per check, RT7): (1a) table gap, (1b)
# duplicate table ID, (2) missing template-block R line, (3) stale range
# string, (4) missing phase-1/phase-3 status line, (5) dangling reference,
# (6) Extended-obligations pointer list out of sync with section headers —
# plus exit-2 fixtures (missing file; unparsable table) and a live-repo
# pass run.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/check-rule-sync.sh"
REPO_SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/triangulate"

# In-place sed that works on both BSD (macOS) and GNU sed: `sed -i` wants a
# mandatory suffix arg on BSD and rejects one on GNU, so edit via a temp file.
sed_i() {
  local script="$1" file="$2" tmp
  tmp="$(mktemp)"
  sed "$script" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Phase files now end with a terminator that MUST stay last, so `>>` is no
# longer a body append: it would land after the terminator and trip the
# not-last and lookalike clauses in addition to whatever the test is probing.
append_body() {
  local file="$1" line="$2" tmp
  tmp="$(mktemp)"
  awk -v ins="$line" -v stem="$TERM_STEM" \
    'index($0, "## " stem "-") == 1 { print ins } { print }' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Single source for the terminator stems, which the fixture builder, the
# append helper and the staged-layout tests all need to agree on (RT3). The
# front-matter KEY names are deliberately not hoisted: the two places they
# appear — the fixture's declaration line and the 8i rename fixture — must be
# able to disagree, since making them disagree is exactly what 8i tests.
TERM_STEM="END-OF-PHASE"
DIGEST_STEM="END-OF-DIGEST"

# Build one fixture phase file: manifest, three steps, an INDENTED fenced decoy
# (a step-shaped heading that must not be counted), the R/RS/RT template lines
# the other checks read, and the terminator as the final line.
write_phase() {
  local n="$1" path="$2" title="$3"
  shift 3
  cat > "$path" <<EOF
---
phase: $n
title: "$title"
steps: 3
step_ids: $n-1, $n-2, $n-3
core: $n-1 — fixture core step; no substitute
---

## $title

### Step $n-1: First

### Step $n-2: Second

### Step $n-3: Third

  \`\`\`markdown
### Step $n-9: fenced decoy — must not be counted
  \`\`\`

EOF
  printf '%s\n' "$@" >> "$path"
  printf '\n## %s-%s\n' "$TERM_STEM" "$n" >> "$path"
}

# Build a minimal, fully consistent fixture skill dir (R1-R3 / RS1-RS2 /
# RT1-RT2) that passes every check. Tests then break exactly one sync
# point each.
setup() {
  FIX="$BATS_TEST_TMPDIR/skill"
  mkdir -p "$FIX/phases"

  cat > "$FIX/common-rules.md" <<'EOF'
**All experts must check:**

| # | Pattern | What to grep/check | Severity if missed |
|---|---------|--------------------|--------------------|
| R1 | Alpha | check a | Major |
| R2 | Beta | check b | Major |
| R3 | Gamma | check c (full set R1-R3) | Major |

**Security expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RS1 | Sec one | check | Major |
| RS2 | Sec two | check | Major |

**Testing expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RT1 | Test one | check | Major |
| RT2 | Test two | check | Major |

## Recurring Issue Check
- R1 (Alpha): [status]
- R2 (Beta): [status]
- R3 (Gamma): [status]
- [Expert-specific checks as applicable: Security adds RS1-RS2; Testing adds RT1-RT2]
EOF

  cat > "$FIX/SKILL.md" <<EOF
# Fixture skill
Recurring issue check reference (R1-R3, RS1-RS2, RT1-RT2).

Read phase files whole-file with the \`Read\` tool; confirm the terminator before acting.
Manifest keys: \`step_ids:\`, \`core:\`. Terminator stems: \`$TERM_STEM\` (phase files), \`$DIGEST_STEM\` (the digest).
EOF

  write_phase 1 "$FIX/phases/phase-1-plan.md" "Plan review template" \
    '- R1: [status]' \
    '- ... (R1-R3)' \
    '- RS1: [status]' \
    '- RS2: [status]' \
    '- RT1: [status]' \
    '- RT2: [status]'

  write_phase 2 "$FIX/phases/phase-2-coding.md" "Coding template" \
    '- Functionality expert: R1-R3' \
    '- Security expert: R1-R3 + RS1-RS2' \
    '- Testing expert: R1-R3 + RT1-RT2'

  write_phase 3 "$FIX/phases/phase-3-review.md" "Review template" \
    '- R1: [status]' \
    '- ... (R1-R3)' \
    '- RS1: [status]' \
    '- RS2: [status]' \
    '- RT1: [status]' \
    '- RT2: [status]'

  regen_digest
}

# SKILL.md names the digest as the first read, so the linter now requires it.
# Any test that mutates common-rules.md must regenerate, or check 7's staleness
# comparison fires on top of whatever that test is actually probing.
regen_digest() {
  bash "$(dirname "$SCRIPT")/generate-triangulate-rule-digest.sh" \
    "$FIX/common-rules.md" "$FIX/common-rules.digest.md" >/dev/null
}

# ============================================================
# PASS cases
# ============================================================

@test "pass: consistent fixture exits 0 with OK summary" {
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: R1-R3 / RS1-RS2 / RT1-RT2"* ]]
}

@test "pass: live repo files are drift-free" {
  run bash "$SCRIPT" "$REPO_SKILL_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "drift: referenced mandatory rule detail is missing" {
  sed_i 's/check a/check a **Mandatory full procedure**: `rule-details\/R1.md`/' "$FIX/common-rules.md"
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"references missing mandatory detail: rule-details/R1.md"* ]]
}

@test "drift: orphan mandatory rule detail is rejected" {
  mkdir -p "$FIX/rule-details"
  printf '%s\n' '# R1 — Alpha' > "$FIX/rule-details/R1.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"orphan mandatory rule detail"* ]]
}

@test "drift: mandatory rule detail pattern must match table" {
  mkdir -p "$FIX/rule-details"
  sed_i 's/check a/check a **Mandatory full procedure**: `rule-details\/R1.md`/' "$FIX/common-rules.md"
  printf '%s\n' '# R1 — Wrong pattern' '' '| R1 | Wrong pattern | Procedure | Major |' > "$FIX/rule-details/R1.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ID/pattern does not match"* ]]
}

# ============================================================
# DRIFT cases — one red fixture per linter check
# ============================================================

@test "drift (1a): gap in table IDs (R2 row removed)" {
  sed_i '/^| R2 |/d' "$FIX/common-rules.md"
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"gap — ID 2 missing"* ]]
}

@test "drift (1b): duplicate table ID (extra R2 row appended to table)" {
  sed_i 's/^| R3 | Gamma | check c (full set R1-R3) | Major |$/| R3 | Gamma | check c (full set R1-R3) | Major |\n| R2 | Beta again | check b2 | Major |/' \
    "$FIX/common-rules.md"
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"duplicate ID 2"* ]]
}

@test "drift (2): template block missing an R line" {
  sed_i '/^- R3 (Gamma): \[status\]$/d' "$FIX/common-rules.md"
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"template block"* ]]
}

@test "drift (3): stale range string in SKILL.md (R1-R2 vs table max R3)" {
  sed_i 's/R1-R3/R1-R2/' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: SKILL.md: stale range R1-R2"* ]]
}

@test "drift (3): stale RS range string in phase-2" {
  sed_i 's/RS1-RS2/RS1-RS1/' "$FIX/phases/phase-2-coding.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-2-coding.md: stale range RS1-RS1"* ]]
}

@test "drift (4): missing RT status line in phase-1" {
  sed_i '/^- RT2: \[status\]$/d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-1-plan.md: template line '- RT2: [status]' missing"* ]]
}

@test "drift (4): missing RS status line in phase-3" {
  sed_i '/^- RS2: \[status\]$/d' "$FIX/phases/phase-3-review.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-3-review.md: template line '- RS2: [status]' missing"* ]]
}

@test "drift (4): status line above table max in phase-1" {
  append_body "$FIX/phases/phase-1-plan.md" '- RT3: [status]'
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"RT3 exceeds table max RT2"* ]]
}

@test "drift (5): dangling reference above max (R99 in phase-2)" {
  append_body "$FIX/phases/phase-2-coding.md" 'See also R99 for details.'
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-2-coding.md: reference to undeclared rule R99"* ]]
}

@test "drift (5): dangling RS reference above max" {
  printf 'Consider RS9 here.\n' >> "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: SKILL.md: reference to undeclared rule RS9"* ]]
}

@test "drift (6): extended-obligations pointer list out of sync with headers" {
  cat >> "$FIX/common-rules.md" <<'EOF'

See "Extended obligations" below for full procedures on R1. All other rules are self-contained in the table row above.

### Extended obligations

**R1: Alpha**

Procedure text.

**R2: Beta**

Procedure text.
EOF
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"pointer lists R{1} but Extended-obligations headers are R{1,2}"* ]]
}

@test "pass: extended-obligations pointer with range form matches headers" {
  # Range deliberately NOT anchored at 1 (an anchored-at-1 range that stops
  # short of the table max is check 3's stale-range drift, correctly).
  cat >> "$FIX/common-rules.md" <<'EOF'

See "Extended obligations" below for full procedures on R2-R3. All other rules are self-contained in the table row above.

### Extended obligations

**R2: Beta**

Procedure text.

**R3: Gamma**

Procedure text.
EOF
  regen_digest
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: R1-R3 / RS1-RS2 / RT1-RT2"* ]]
}

# ============================================================
# DRIFT cases — check #8, phase manifest (one fixture per clause)
#
# Mutation targets are pinned where the choice decides the outcome: `8e-sub`
# substitutes the LAST id so it cannot collide with `core`, `fence` relocates
# the LAST step for the same reason, and `8h-dup` inserts after the first `## `
# heading so it does not disturb the title comparison.
# ============================================================

@test "drift (8a.1): front matter opening delimiter removed" {
  sed_i '1d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: malformed front matter block (line 1 is not '---')"* ]]
}

@test "drift (8a.2): front matter closing delimiter removed" {
  sed_i '7d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: malformed front matter block (closing '---'"* ]]
}

@test "drift (8a.3): front matter key with an empty value" {
  sed_i 's/^core: .*/core:/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: malformed front matter block (not 'key: value'"* ]]
}

@test "drift (8b): extra key in the front matter block" {
  sed_i 's/^phase: 1$/phase: 1\nextra: x/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter key set is [core,extra,phase,step_ids,steps,title]"* ]]
}

@test "drift (8c): declared phase disagrees with the filename" {
  sed_i 's/^phase: 1$/phase: 9/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter declares phase 9 but filename says 1"* ]]
}

@test "drift (8d): declared step count disagrees with the headings" {
  sed_i 's/^steps: 3$/steps: 4/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter declares 4 steps but file has 3 '### Step' headings"* ]]
}

@test "drift (8e): step_ids member disagrees with the headings" {
  sed_i 's/^step_ids: 1-1, 1-2, 1-3$/step_ids: 1-1, 1-2, 1-9/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: step_ids [1-1, 1-2, 1-9] does not match headings [1-1, 1-2, 1-3]"* ]]
}

@test "drift (8e): step_ids order disagrees with the headings" {
  # A permutation is the unique mutation that reds an ordered comparison and
  # stays green under a sorted-set one. Keeps 1-1 first so `core` still resolves.
  sed_i 's/^step_ids: 1-1, 1-2, 1-3$/step_ids: 1-1, 1-3, 1-2/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: step_ids [1-1, 1-3, 1-2] does not match headings [1-1, 1-2, 1-3]"* ]]
}

@test "drift (8f): declared title disagrees with the first heading" {
  sed_i 's/^title: .*/title: "Wrong title"/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: title 'Wrong title' does not match heading 'Plan review template'"* ]]
}

@test "drift (8g): core names a step that is neither declared nor actually present" {
  # 1-9 exists ONLY inside the fenced decoy, so this single mutation exercises
  # both halves of 8g — membership in step_ids, and resolution to a heading the
  # fence-aware scan actually counted. Both are asserted: without the second
  # assertion the resolution half has no mutation that reds it.
  sed_i 's/^core: 1-1/core: 1-9/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: core names step 1-9, which is not in step_ids"* ]]
  [[ "$output" == *"phase-1-plan.md: core names step 1-9, which is not a counted '### Step' heading"* ]]
}

@test "drift (I15): an unbalanced code fence is refused rather than scanned" {
  # A lone fence line leaves the toggle stuck, so every heading after it is
  # silently skipped. Inserted before the terminator, after all three steps, so
  # the count is unchanged and this fires on the desync itself.
  append_body "$FIX/phases/phase-1-plan.md" '```'
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: unbalanced code fence at EOF"* ]]
}

@test "drift (I15): a real step heading hidden inside an indented fence is not counted" {
  sed_i 's|^### Step 1-3: Third$|  ```markdown\n### Step 1-3: Third\n  ```|' \
    "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter declares 3 steps but file has 2 '### Step' headings"* ]]
}

@test "drift (I15): the fixture's fenced decoy is counted once its fences are removed" {
  # The inverse direction of the fixture above, and the reason the base fixture
  # carries a decoy at all: without it every pass test is invariant under fence
  # awareness, so nothing distinguishes a fence-aware linter from a naive one.
  sed_i '/^  ```markdown$/d; /^  ```$/d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter declares 3 steps but file has 4 '### Step' headings"* ]]
}

@test "drift (8h.1): a second exact terminator mid-file" {
  sed_i 's|^## Plan review template$|## Plan review template\n\n## END-OF-PHASE-1|' \
    "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: terminator '## END-OF-PHASE-<N>' appears 2 times, expected exactly 1"* ]]
}

@test "drift (8h.1): terminator missing entirely" {
  sed_i '/^## END-OF-PHASE-1$/d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: terminator '## END-OF-PHASE-<N>' appears 0 times, expected exactly 1"* ]]
}

@test "drift (8h.2): terminator number disagrees with the filename" {
  sed_i 's/^## END-OF-PHASE-1$/## END-OF-PHASE-7/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: terminator declares 7 but filename says 1"* ]]
}

@test "drift (8h.3): terminator is not the last non-empty line" {
  printf 'a trailing note\n' >> "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: terminator is not the last non-empty line"* ]]
}

@test "drift (8h.4): a reader-invisible terminator lookalike mid-file" {
  # Indented, trailing space, and a zero-width space inside the stem: all three
  # render identically to the real terminator and all three survive an anchored
  # match. This is why the uniqueness scan reduces to alphanumerics instead of
  # enumerating known evasions.
  sed_i 's|^## Plan review template$|## Plan review template\n  ## END\xe2\x80\x8b-OF-PHASE-1 |' \
    "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: line"*"resembles a terminator a truncated read would trust"* ]]
}

@test "drift (I13): the terminator stem comes from SKILL.md, not a literal in the linter" {
  # Changing the stem in SKILL.md alone reds only if the linter derives it. A
  # hardcoded implementation stays green here — which is the whole point.
  sed_i 's/`END-OF-PHASE`/`END-OF-STAGE`/' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminator '## END-OF-STAGE-<N>' appears 0 times"* ]]
}

@test "drift (8i): SKILL.md names a front-matter key the phase files do not carry" {
  sed_i 's/`step_ids:`/`step_names:`/' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: SKILL.md references front-matter key 'step_names' which is absent"* ]]
}

@test "pass (8i): a backticked key token outside the declaration line is not a manifest key" {
  # The only fixture that distinguishes a declaration-line-scoped extractor from
  # a whole-file one. Without the scope, this injects a phantom key and fires
  # 8i on all three GOOD phase files.
  printf 'Rules may declare `paths:` frontmatter elsewhere.\n' >> "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "drift (8j.1): SKILL.md does not name the Read tool" {
  sed_i 's/the `Read` tool/the appropriate tool/' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: loading protocol missing 'Read'"* ]]
}

@test "drift (8j.2): SKILL.md declares no phase-file terminator stem" {
  sed_i 's/`END-OF-PHASE` (phase files), //' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: loading protocol declares no phase-file terminator stem"* ]]
  # I29: with no stem, the terminator checks short-circuit rather than matching
  # every line through an empty-needle containment test.
  [[ "$output" != *"resembles a terminator"* ]]
}

@test "drift (8j.3): SKILL.md declares no digest terminator stem" {
  # Distinct from 8j.2 (phase stem) and from the staged-layout test, which
  # RENAMES the digest stem and so leaves it non-empty. Removing it is the only
  # mutation that reaches this clause.
  sed_i 's/, `END-OF-DIGEST` (the digest)//' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: loading protocol declares no digest terminator stem"* ]]
}

@test "drift (8i): SKILL.md names no manifest keys at all" {
  # The empty case, not the renamed one. Without its own guard the 8i loop
  # iterates once on the empty string, checks nothing, and reports clean while
  # SKILL.md has stopped telling readers what to reconcile against.
  sed_i 's/Manifest keys: `step_ids:`, `core:`\./Manifest keys: none./' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: loading protocol names no front-matter manifest keys"* ]]
}

@test "drift (8g): core carries no step ID at all" {
  # The 8g fixture mutates core to a WRONG id and takes the else branch; this
  # takes the guard branch. `core: prose` is a well-formed `key: value`, so
  # 8a.3 does not backstop it.
  sed_i 's/^core: .*/core: plan review by three experts, no substitute/' \
    "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: core does not begin with a step ID"* ]]
}

@test "drift (I15): a step heading indented by one space is still counted" {
  # The heading anchor allows the same 0-3 spaces the fence anchor does. A
  # column-0-only anchor would let a step be hidden from the manifest by
  # indenting it a single space, while a reader still sees a heading.
  sed_i 's/^### Step 1-3: Third$/ ### Step 1-3: Third/' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "drift (I15): backticks inside an indented code block do not desync the fence toggle" {
  # A 4-space-indented backtick line is literal text, not a fence. Treating it
  # as one lets two such lines flip the toggle with even parity and hide every
  # heading between them — fail-open. Ignoring them can only over-count, which
  # reds, so this asserts the hidden heading IS counted.
  sed_i 's|^### Step 1-3: Third$|    ```\n### Step 1-8: hidden\n    ```\n### Step 1-3: Third|' \
    "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-1-plan.md: front matter declares 3 steps but file has 4 '### Step' headings"* ]]
}

@test "error: a deleted digest exits 2 rather than passing clean" {
  # SKILL.md names the digest as the first read and its terminator as the
  # truncation signal. Before it joined the preflight, deleting the file passed
  # clean while corrupting it reds — the fail direction inverted.
  rm "$FIX/common-rules.digest.md"
  run -2 --separate-stderr bash "$SCRIPT" "$FIX"
  [[ "$stderr" == *"missing file"*"common-rules.digest.md"* ]]
}

@test "drift (8j.4): SKILL.md carries a step enumeration of its own" {
  printf '### Step 1-1: duplicated manifest\n' >> "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: contains a '### Step' enumeration"* ]]
}

@test "drift (8j): SKILL.md loses its declaration line entirely" {
  sed_i '/^Manifest keys:/d' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKILL.md: loading protocol is missing its 'Manifest keys:"* ]]
}

@test "drift (I7): a new phase file is swept in without a linter edit" {
  # The only assertion that distinguishes the directory sweep from a hard-coded
  # PHASE1/PHASE2/PHASE3 triple: every other fixture mutates a file the triple
  # already names.
  printf '# stray\n' > "$FIX/phases/phase-4-extra.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase-4-extra.md: malformed front matter block (line 1 is not '---')"* ]]
}

# ============================================================
# Installed-layout twin — zero-argument default resolution
#
# `install.sh` produces ~/.claude as a cp -r twin of the repo, and no test
# reached the self-relative default (check-rule-sync.sh's `${1:-...}`) before
# this. Staged under BATS_TEST_TMPDIR rather than run against the real
# ~/.claude, which would mutate live config. BOTH hooks are staged: the real
# skill dir ships a digest, and with the generator absent check #7 drifts.
# ============================================================

stage_installed_layout() {
  STAGE="$BATS_TEST_TMPDIR/inst"
  mkdir -p "$STAGE/hooks" "$STAGE/skills"
  cp "$SCRIPT" "$STAGE/hooks/check-rule-sync.sh"
  cp "$(dirname "$SCRIPT")/generate-triangulate-rule-digest.sh" "$STAGE/hooks/"
  cp -r "$REPO_SKILL_DIR" "$STAGE/skills/"
}

@test "installed layout: zero-argument default resolution is drift-free" {
  stage_installed_layout
  cd "$BATS_TEST_TMPDIR"
  run bash "$STAGE/hooks/check-rule-sync.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "installed layout: the digest terminator is compared against SKILL.md's declared stem" {
  # The digest half of the single-source property. $FIX carries no digest (check
  # #7 is guarded on its presence), so this is the layout where the comparison
  # is observable at all.
  stage_installed_layout
  sed_i 's/`END-OF-DIGEST`/`END-OF-INDEX`/' "$STAGE/skills/triangulate/SKILL.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STAGE/hooks/check-rule-sync.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"common-rules.digest.md: last line is '## END-OF-DIGEST', expected '## END-OF-INDEX'"* ]]
}

# ============================================================
# ERROR cases — exit 2
# ============================================================

@test "error: missing file exits 2 (phase-3 removed)" {
  rm "$FIX/phases/phase-3-review.md"
  run -2 --separate-stderr bash "$SCRIPT" "$FIX"
  [[ "$stderr" == *"missing file"* ]]
}

@test "error: unparsable rule table exits 2" {
  sed_i '/^| R/d' "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 2 ]
}

@test "error: nonexistent skill dir exits 2" {
  run bash "$SCRIPT" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}
