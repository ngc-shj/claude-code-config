#!/bin/bash
# Rule-ID consistency linter for the triangulate skill files.
#
# The recurring-rule set (R*, RS*, RT*) is declared once as table rows in
# common-rules.md but referenced from several sync points that have gone
# stale in the past (RS6/RT8 template lines were missing from the phase
# files until 2026-07-11):
#   - the Recurring Issue Check template in common-rules.md (`- Rn (...)`)
#   - the expert bracket line (`Security adds RS1-RSn; Testing adds RT1-RTn`)
#   - per-rule template lines in phase-1-plan.md / phase-3-review.md
#     (`- RSn: [status]`, `- RTn: [status]`)
#   - range strings `R1-Rn` / `RS1-RSn` / `RT1-RTn` in SKILL.md, the three
#     phase files, and common-rules.md itself
#
# This linter derives maxR/maxRS/maxRT from the table rows (the single
# source of truth) and verifies:
#   1. table IDs are contiguous from 1 with no duplicates
#   2. the common-rules.md template enumerates exactly R1..maxR
#   3. every range string anchored at 1 ends at the current max
#   4. phase-1 and phase-3 enumerate exactly RS1..maxRS and RT1..maxRT
#   5. no file references a rule ID above the declared max
#   6. the "full procedures on ..." pointer sentence lists exactly the
#      rules that have an Extended-obligations section header
#   7. the generated compact digest matches the source table (when present)
#
# Usage: bash check-rule-sync.sh [triangulate-skill-dir]
#   The default dir resolves to ../skills/triangulate relative to this
#   script, which works both in the repo layout and the installed
#   ~/.claude layout.
#
# Exit: 0 = consistent, 1 = drift found, 2 = files missing/unparsable.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${1:-$SCRIPT_DIR/../skills/triangulate}"

COMMON="$SKILL_DIR/common-rules.md"
SKILL="$SKILL_DIR/SKILL.md"
PHASE1="$SKILL_DIR/phases/phase-1-plan.md"
PHASE2="$SKILL_DIR/phases/phase-2-coding.md"
PHASE3="$SKILL_DIR/phases/phase-3-review.md"
ALL_FILES=("$COMMON" "$SKILL" "$PHASE1" "$PHASE2" "$PHASE3")

for f in "${ALL_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "Error: missing file: $f" >&2
    exit 2
  fi
done

fail=0
drift() {
  printf 'DRIFT: %s\n' "$1"
  fail=1
}

# Validate that the newline-separated ID-number list $2 (label $1) is
# exactly {1..max} with no duplicates. Emits drift lines directly (runs in
# the current shell) and leaves the max in CONTIG_MAX.
CONTIG_MAX=0
check_contiguous() {
  local label="$1" list="$2" n i
  local -A seen=()
  CONTIG_MAX=0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ -n "${seen[$n]:-}" ] && drift "$label: duplicate ID $n"
    seen[$n]=1
    [ "$n" -gt "$CONTIG_MAX" ] && CONTIG_MAX="$n"
  done <<< "$list"
  for ((i = 1; i <= CONTIG_MAX; i++)); do
    [ -z "${seen[$i]:-}" ] && drift "$label: gap — ID $i missing from sequence 1..$CONTIG_MAX"
  done
  return 0
}

# --- 1. source of truth: table rows in common-rules.md ---

check_contiguous "common-rules.md R table" \
  "$(sed -nE 's/^\| R([0-9]+) \|.*/\1/p' "$COMMON")"
MAX_R="$CONTIG_MAX"
check_contiguous "common-rules.md RS table" \
  "$(sed -nE 's/^\| RS([0-9]+) \|.*/\1/p' "$COMMON")"
MAX_RS="$CONTIG_MAX"
check_contiguous "common-rules.md RT table" \
  "$(sed -nE 's/^\| RT([0-9]+) \|.*/\1/p' "$COMMON")"
MAX_RT="$CONTIG_MAX"

if [ "$MAX_R" -eq 0 ] || [ "$MAX_RS" -eq 0 ] || [ "$MAX_RT" -eq 0 ]; then
  echo "Error: could not parse rule tables from $COMMON (R=$MAX_R RS=$MAX_RS RT=$MAX_RT)" >&2
  exit 2
fi

# --- 2. Recurring Issue Check template in common-rules.md ---

check_contiguous "common-rules.md R template block" \
  "$(sed -nE 's/^- R([0-9]+) \(.*/\1/p' "$COMMON")"
if [ "$CONTIG_MAX" -ne "$MAX_R" ]; then
  drift "common-rules.md template block ends at R$CONTIG_MAX but table declares R$MAX_R"
fi

# --- 3. range strings anchored at 1 must end at max (all five files) ---

check_ranges() {
  local file="$1" prefix="$2" max="$3" base k
  base=$(basename "$file")
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    [ "$k" -eq "$max" ] || \
      drift "$base: stale range ${prefix}1-${prefix}$k (table declares ${prefix}1-${prefix}$max)"
  done < <(grep -oE "${prefix}1-${prefix}[0-9]+" "$file" | sed -E "s/^${prefix}1-${prefix}//")
}

for f in "${ALL_FILES[@]}"; do
  check_ranges "$f" R "$MAX_R"
  check_ranges "$f" RS "$MAX_RS"
  check_ranges "$f" RT "$MAX_RT"
done

# --- 4. per-rule template lines in phase-1 / phase-3 ---

for f in "$PHASE1" "$PHASE3"; do
  base=$(basename "$f")
  for prefix in RS RT; do
    case "$prefix" in
      RS) want="$MAX_RS" ;;
      RT) want="$MAX_RT" ;;
    esac
    nums=$(sed -nE "s/^- ${prefix}([0-9]+): .*/\1/p" "$f" | sort -n -u)
    if [ -z "$nums" ]; then
      drift "$base: no '- ${prefix}n: [status]' template lines found"
      continue
    fi
    for ((n = 1; n <= want; n++)); do
      if ! printf '%s\n' "$nums" | grep -qx "$n"; then
        drift "$base: template line '- ${prefix}${n}: [status]' missing (table declares ${prefix}1..${prefix}${want})"
      fi
    done
    top=$(printf '%s\n' "$nums" | tail -n 1)
    if [ "$top" -gt "$want" ]; then
      drift "$base: template line for ${prefix}${top} exceeds table max ${prefix}${want}"
    fi
  done
done

# --- 5. dangling references (ID above declared max) in any file ---

for f in "${ALL_FILES[@]}"; do
  base=$(basename "$f")
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in
      RS*) n="${tok#RS}"; max="$MAX_RS"; pfx=RS ;;
      RT*) n="${tok#RT}"; max="$MAX_RT"; pfx=RT ;;
      R*)  n="${tok#R}";  max="$MAX_R";  pfx=R ;;
    esac
    if [ "$n" -gt "$max" ] || [ "$n" -eq 0 ]; then
      drift "$base: reference to undeclared rule $tok (max is ${pfx}${max})"
    fi
  done < <(grep -oE '(^|[^A-Za-z0-9_])(RT|RS|R)[0-9]+' "$f" \
             | sed -E 's/^[^A-Za-z0-9_]+//' | sort -u)
done

# --- 6. Extended-obligations pointer list matches actual section headers ---

ext_actual=$(awk '/^### Extended obligations/{flag=1; next} /^## /{flag=0} flag' "$COMMON" \
  | sed -nE 's/^\*\*R([0-9]+)[: ].*/\1/p' | sort -n -u)
ext_line=$(grep -m1 'full procedures on R' "$COMMON" || true)
if [ -n "$ext_line" ] || [ -n "$ext_actual" ]; then
  if [ -z "$ext_line" ]; then
    drift "common-rules.md: Extended-obligations section headers exist but no 'full procedures on ...' pointer sentence found"
  elif [ -z "$ext_actual" ]; then
    drift "common-rules.md: 'full procedures on ...' pointer sentence exists but no Extended-obligations section headers found"
  else
    ext_listed=$(printf '%s\n' "$ext_line" \
      | sed -E 's/.*full procedures on //; s/\. .*//' \
      | grep -oE 'R[0-9]+(-R[0-9]+)?' \
      | { while IFS= read -r tok; do
            case "$tok" in
              *-*) a="${tok%%-*}"; a="${a#R}"; b="${tok##*-}"; b="${b#R}"
                   for ((i = a; i <= b; i++)); do echo "$i"; done ;;
              *)   echo "${tok#R}" ;;
            esac
          done; } | sort -n -u)
    if [ "$ext_listed" != "$ext_actual" ]; then
      drift "common-rules.md: 'full procedures on' pointer lists R{$(echo $ext_listed | tr ' ' ',')} but Extended-obligations headers are R{$(echo $ext_actual | tr ' ' ',')}"
    fi
  fi
fi

# --- 7. generated digest matches the source table ---

DIGEST="$SKILL_DIR/common-rules.digest.md"
GENERATOR="$SCRIPT_DIR/generate-triangulate-rule-digest.sh"
if [ -f "$DIGEST" ]; then
  if [ ! -f "$GENERATOR" ]; then
    drift "common-rules.digest.md exists but digest generator is missing"
  elif ! bash "$GENERATOR" "$COMMON" "$DIGEST" --check >/dev/null; then
    drift "common-rules.digest.md is stale; regenerate it from common-rules.md"
  fi
fi

# Every mandatory per-rule detail referenced by the compact table must exist.
while IFS= read -r detail; do
  [ -n "$detail" ] || continue
  if [ ! -f "$SKILL_DIR/$detail" ]; then
    drift "common-rules.md references missing mandatory detail: $detail"
  fi
done < <(grep -oE 'rule-details/(R|RS|RT)[0-9]+\.md' "$COMMON" | sort -u)

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Rule-ID drift detected. Sync points: common-rules.md table + template"
  echo "block, the Extended-obligations pointer sentence, phase-1/phase-3"
  echo "'- RSn/RTn: [status]' lines, and every 'R1-Rn'/'RS1-RSn'/'RT1-RTn'"
  echo "range string in the five checked files."
  exit 1
fi

echo "OK: R1-R$MAX_R / RS1-RS$MAX_RS / RT1-RT$MAX_RT consistent across all sync points"
exit 0
