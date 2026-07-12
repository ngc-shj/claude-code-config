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

  cat > "$FIX/SKILL.md" <<'EOF'
# Fixture skill
Recurring issue check reference (R1-R3, RS1-RS2, RT1-RT2).
EOF

  cat > "$FIX/phases/phase-1-plan.md" <<'EOF'
## Plan review template
- R1: [status]
- ... (R1-R3)
- RS1: [status]
- RS2: [status]
- RT1: [status]
- RT2: [status]
EOF

  cat > "$FIX/phases/phase-2-coding.md" <<'EOF'
## Coding template
- Functionality expert: R1-R3
- Security expert: R1-R3 + RS1-RS2
- Testing expert: R1-R3 + RT1-RT2
EOF

  cat > "$FIX/phases/phase-3-review.md" <<'EOF'
## Review template
- R1: [status]
- ... (R1-R3)
- RS1: [status]
- RS2: [status]
- RT1: [status]
- RT2: [status]
EOF
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
  sed -i 's/check a/check a **Mandatory full procedure**: `rule-details\/R1.md`/' "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"references missing mandatory detail: rule-details/R1.md"* ]]
}

# ============================================================
# DRIFT cases — one red fixture per linter check
# ============================================================

@test "drift (1a): gap in table IDs (R2 row removed)" {
  sed -i '/^| R2 |/d' "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"gap — ID 2 missing"* ]]
}

@test "drift (1b): duplicate table ID (extra R2 row appended to table)" {
  sed -i 's/^| R3 | Gamma | check c (full set R1-R3) | Major |$/| R3 | Gamma | check c (full set R1-R3) | Major |\n| R2 | Beta again | check b2 | Major |/' \
    "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"duplicate ID 2"* ]]
}

@test "drift (2): template block missing an R line" {
  sed -i '/^- R3 (Gamma): \[status\]$/d' "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"template block"* ]]
}

@test "drift (3): stale range string in SKILL.md (R1-R2 vs table max R3)" {
  sed -i 's/R1-R3/R1-R2/' "$FIX/SKILL.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: SKILL.md: stale range R1-R2"* ]]
}

@test "drift (3): stale RS range string in phase-2" {
  sed -i 's/RS1-RS2/RS1-RS1/' "$FIX/phases/phase-2-coding.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-2-coding.md: stale range RS1-RS1"* ]]
}

@test "drift (4): missing RT status line in phase-1" {
  sed -i '/^- RT2: \[status\]$/d' "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-1-plan.md: template line '- RT2: [status]' missing"* ]]
}

@test "drift (4): missing RS status line in phase-3" {
  sed -i '/^- RS2: \[status\]$/d' "$FIX/phases/phase-3-review.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: phase-3-review.md: template line '- RS2: [status]' missing"* ]]
}

@test "drift (4): status line above table max in phase-1" {
  printf -- '- RT3: [status]\n' >> "$FIX/phases/phase-1-plan.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT:"*"RT3 exceeds table max RT2"* ]]
}

@test "drift (5): dangling reference above max (R99 in phase-2)" {
  printf 'See also R99 for details.\n' >> "$FIX/phases/phase-2-coding.md"
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
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: R1-R3 / RS1-RS2 / RT1-RT2"* ]]
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
  sed -i '/^| R/d' "$FIX/common-rules.md"
  run bash "$SCRIPT" "$FIX"
  [ "$status" -eq 2 ]
}

@test "error: nonexistent skill dir exits 2" {
  run bash "$SCRIPT" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}
