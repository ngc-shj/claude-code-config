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
#   7. the generated compact digest matches the source table
#   8. the phase manifest: each phase file's front matter agrees with its
#      '### Step' headings (counted outside code fences), its terminator is
#      unique / correctly numbered / last with no lookalike above it, and
#      SKILL.md declares the manifest keys and terminator stems that every
#      other comparison here is made against
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
# The digest is named in SKILL.md's loading protocol as the FIRST read and its
# terminator as a truncation signal, so its absence is a broken pointer, not an
# optional-file case. Checks 7 and the digest-terminator comparison guard on
# `-f` for historical reasons; making it a preflight member is what stops
# "delete the file" passing clean while "corrupt the file" reds.
DIGEST="$SKILL_DIR/common-rules.digest.md"
PHASE1="$SKILL_DIR/phases/phase-1-plan.md"
PHASE2="$SKILL_DIR/phases/phase-2-coding.md"
PHASE3="$SKILL_DIR/phases/phase-3-review.md"
ALL_FILES=("$COMMON" "$SKILL" "$PHASE1" "$PHASE2" "$PHASE3")

for f in "${ALL_FILES[@]}" "$DIGEST"; do
  if [ ! -f "$f" ]; then
    echo "Error: missing file: $f" >&2
    exit 2
  fi
done
# The digest is required to EXIST (above) but deliberately stays out of
# ALL_FILES, which is the scan list for the range-string and dangling-reference
# checks. Its content is generated, and check 7 verifies it byte-for-byte
# against a regeneration — a stronger guarantee than grepping it. Scanning it
# would also flag the generator's own boilerplate example (`rg '^\| (R1|R3|RS2|RT4) \|'`)
# as a dangling reference in any skill dir whose table stops below RT4.

# The phases directory is a check-#8 precondition, and it is verified HERE so
# that a missing one exits 2 before any drift accumulates. Check #8 itself
# contains no `exit`: an exit inside it would discard a fail=1 already set by
# checks 1-7, reporting real rule-ID drift as "missing/unparsable".
if [ ! -d "$SKILL_DIR/phases" ]; then
  echo "Error: missing directory: $SKILL_DIR/phases" >&2
  exit 2
fi

# Checks 3 and 5 scan a fixed list while check 8 sweeps the phases directory.
# Left as-is, a phase file added later would get manifest and terminator
# checking but escape range-string and dangling-reference checking — the same
# member set derived two different ways inside one linter. Append the extras so
# both derivations agree. The three named files stay required, so the
# missing-file preflight above keeps its exit-2 contract.
for extra_phase in "$SKILL_DIR"/phases/phase-*.md; do
  [ -e "$extra_phase" ] || continue
  case "$extra_phase" in
    "$PHASE1"|"$PHASE2"|"$PHASE3") ;;
    *) ALL_FILES+=("$extra_phase") ;;
  esac
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
  # macOS ships bash 3.2, which has no associative arrays: track seen IDs
  # as a delimited string instead so this gate runs on a stock system.
  local label="$1" list="$2" n i seen=" "
  CONTIG_MAX=0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$seen" in *" $n "*) drift "$label: duplicate ID $n" ;; esac
    seen="$seen$n "
    [ "$n" -gt "$CONTIG_MAX" ] && CONTIG_MAX="$n"
  done <<< "$list"
  i=1
  while [ "$i" -le "$CONTIG_MAX" ]; do
    case "$seen" in
      *" $i "*) ;;
      *) drift "$label: gap — ID $i missing from sequence 1..$CONTIG_MAX" ;;
    esac
    i=$((i + 1))
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
            # Patterns are opened with '(' — bash 3.2 (stock on macOS)
            # miscounts parens for a bare `pat)` inside $( ).
            case "$tok" in
              (*-*) a="${tok%%-*}"; a="${a#R}"; b="${tok##*-}"; b="${b#R}"
                    i="$a"
                    while [ "$i" -le "$b" ]; do echo "$i"; i=$((i + 1)); done
                    ;;
              (*)   echo "${tok#R}" ;;
            esac
          done; } | sort -n -u)
    if [ "$ext_listed" != "$ext_actual" ]; then
      drift "common-rules.md: 'full procedures on' pointer lists R{$(echo $ext_listed | tr ' ' ',')} but Extended-obligations headers are R{$(echo $ext_actual | tr ' ' ',')}"
    fi
  fi
fi

# --- 7. generated digest matches the source table ---

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

# Detail files are bidirectional sync points: no orphan files, and their
# heading/full-row identity must match the compact table row.
if [ -d "$SKILL_DIR/rule-details" ]; then
  for detail_file in "$SKILL_DIR"/rule-details/{R,RS,RT}[0-9]*.md; do
    [ -e "$detail_file" ] || continue
    detail="rule-details/$(basename "$detail_file")"
    if ! grep -qF "$detail" "$COMMON"; then
      drift "orphan mandatory rule detail not referenced by common-rules.md: $detail"
      continue
    fi
    id=$(basename "$detail_file" .md)
    table_pattern=$(awk -F'[|]' -v id="$id" '$2 ~ "^ " id " $" {p=$3; gsub(/^ +| +$/, "", p); print p; exit}' "$COMMON")
    detail_heading=$(sed -nE "s/^# $id — (.*)$/\\1/p" "$detail_file" | head -n 1)
    detail_row_pattern=$(awk -F'[|]' -v id="$id" '$2 ~ "^ " id " $" {p=$3; gsub(/^ +| +$/, "", p); print p; exit}' "$detail_file")
    if [ -z "$table_pattern" ] || [ "$detail_heading" != "$table_pattern" ] || [ "$detail_row_pattern" != "$table_pattern" ]; then
      drift "$detail ID/pattern does not match common-rules.md row $id"
    fi
  done
fi

# --- 8. phase manifest: front matter declares what a complete read contains ---
#
# A phase file read only in part is otherwise undetectable: nothing in it says
# how many steps it has, and nothing marks its end. This check makes the two
# facts a truncated reader needs — the step manifest at byte 0 and a terminator
# at the tail — machine-guaranteed accurate, so the SKILL.md obligation to use
# them cannot be reading stale or absent metadata.
#
# SKILL.md is the single author of the terminator stems and of the front-matter
# key names it tells readers to reconcile against; everything here compares
# against the EXTRACTED values, never a literal, so a rename in the phase files
# and this script together still reds against a stale SKILL.md.

# 8j (per-run): SKILL.md's loading protocol.
SKILL_KEYS=""
STEM_PHASE=""
STEM_DIGEST=""
DECL_LINE=$(grep -m1 '^Manifest keys:' "$SKILL" || true)
if [ -z "$DECL_LINE" ]; then
  drift "SKILL.md: loading protocol is missing its 'Manifest keys: ... Terminator stems: ...' declaration line"
else
  # Extraction is scoped to the declaration line, not the whole file: a
  # backticked `key:` token anywhere else in SKILL.md would otherwise inject a
  # phantom key and fire 8i on every good phase file.
  SKILL_KEYS=$(printf '%s\n' "$DECL_LINE" | grep -o '`[a-z_]\{1,\}:`' | tr -d '`:' | sort -u)
  # The parse is by SHAPE: a backticked END-OF-* token followed by the literal
  # parenthetical that says which file it terminates. Rewording the sentence
  # empties the stems, which fails closed (8h short-circuits, I29) but would
  # otherwise be diagnosed as "declares no stem" for a line that declares one —
  # hence the expected shape in the message. SKILL.md carries a comment saying
  # this line is machine-parsed.
  STEM_PHASE=$(printf '%s\n' "$DECL_LINE" | sed -nE 's/.*`(END-OF-[A-Z]+)` \(phase files\).*/\1/p')
  STEM_DIGEST=$(printf '%s\n' "$DECL_LINE" | sed -nE 's/.*`(END-OF-[A-Z]+)` \(the digest\).*/\1/p')
fi
[ -n "$STEM_PHASE" ] || drift "SKILL.md: loading protocol declares no phase-file terminator stem (expected the shape: \`<STEM>\` (phase files))"
[ -n "$STEM_DIGEST" ] || drift "SKILL.md: loading protocol declares no digest terminator stem (expected the shape: \`<STEM>\` (the digest))"
# The third extracted field needs the same guard as the two stems. Without it an
# empty key list makes the 8i loop iterate once on "" and check nothing, so
# SKILL.md could stop naming any manifest key — and stop telling the reader to
# reconcile against them — with the gate still green.
[ -n "$SKILL_KEYS" ] || drift "SKILL.md: loading protocol names no front-matter manifest keys"
grep -q '^### Step' "$SKILL" && drift "SKILL.md: contains a '### Step' enumeration — the step manifest belongs in the phase file's front matter, not here"

# The obligations themselves — the runtime half of the whole mechanism. Without
# this, every check above can pass while SKILL.md no longer tells anyone to look
# at the manifest or the terminator: accurate metadata and nothing reading it,
# which is the shape this linter exists to refuse. Scoped to the protocol block,
# not the whole file, so an unrelated mention of `Read` or of a key name
# elsewhere cannot satisfy it (the same scoping 8i already applies to the
# declaration line — applied here in the fail-closed direction too).
PROTO=$(awk '/^\*\*Truncation protocol\*\*/ { f = 1 } f && /^Manifest keys:/ { exit } f' "$SKILL")
if [ -z "$PROTO" ]; then
  drift "SKILL.md: truncation-protocol block is missing (expected a '**Truncation protocol**' paragraph above the 'Manifest keys:' declaration line)"
else
  printf '%s\n' "$PROTO" | grep -q '`Read`' || \
    drift "SKILL.md: truncation protocol does not name the \`Read\` tool — readers must be told which tool delivers a whole file"
  for stem in "$STEM_PHASE" "$STEM_DIGEST"; do
    [ -n "$stem" ] || continue
    printf '%s\n' "$PROTO" | grep -q "$stem" || \
      drift "SKILL.md: truncation protocol never tells readers to check the '$stem' terminator"
  done
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    printf '%s\n' "$PROTO" | grep -q "$k" || \
      drift "SKILL.md: truncation protocol declares manifest key '$k' but never tells readers to reconcile against it"
  done <<< "$SKILL_KEYS"
fi
# No terminator literal anywhere in SKILL.md may name a stem the declaration
# line does not declare. The protocol states the terminator in prose and the
# phase-transition note repeats it; a rename that misses one of them leaves
# readers hunting for a marker no file carries, and every complete read then
# reads as partial until the reader learns to ignore the rule.
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  case "$tok" in
    "$STEM_PHASE"|"$STEM_DIGEST") ;;
    *) drift "SKILL.md: names terminator '$tok', which is not one of the declared stems" ;;
  esac
done < <(grep -oE 'END-OF-[A-Z]+' "$SKILL" | sort -u)

# Digest terminator, compared against the stem SKILL.md declares (not a literal).
if [ -n "$STEM_DIGEST" ] && [ -f "$DIGEST" ]; then
  digest_last=$(sed '/^[[:space:]]*$/d' "$DIGEST" | tail -1)
  if [ "$digest_last" != "## $STEM_DIGEST" ]; then
    drift "common-rules.digest.md: last line is '$digest_last', expected '## $STEM_DIGEST'"
  fi
fi

# Read a key's value out of a phase file's front-matter window.
fm_get() {
  # $1 file, $2 closing-delimiter line number, $3 key
  sed -n "2,$(($2 - 1))p" "$1" | sed -nE "s/^$3: (.*)$/\1/p" | head -n 1
}

for pf in "$SKILL_DIR"/phases/phase-*.md; do
  # Unreachable by construction: the preflight above exits 2 when any of the
  # three named phase files is missing, so this glob always matches. Retained
  # as defence-in-depth against a future refactor that drops those paths from
  # ALL_FILES — not among the mutation-proven gates.
  [ -e "$pf" ] || continue
  base=$(basename "$pf")
  file_n=$(printf '%s\n' "$base" | sed -nE 's/^phase-([0-9]+)-.*/\1/p')

  # 8a — front-matter block structure. 8a.1 gates 8a.2 gates 8a.3, and any 8a
  # failure gates 8b-8g and 8i: there is no parsed window to report from.
  fm_ok=1
  close=""
  if [ "$(sed -n '1p' "$pf")" != "---" ]; then
    drift "$base: malformed front matter block (line 1 is not '---')"
    fm_ok=0
  else
    close=$(awk 'NR > 1 && /^---$/ { print NR; exit }' "$pf")
    if [ -z "$close" ] || [ "$close" -gt 10 ]; then
      drift "$base: malformed front matter block (closing '---' ${close:-not found} — must be within the first 10 lines)"
      fm_ok=0
    else
      bad=$(sed -n "2,$((close - 1))p" "$pf" | grep -vE '^[a-z_]+: .+$' | head -n 1)
      if [ -n "$bad" ]; then
        drift "$base: malformed front matter block (not 'key: value': $bad)"
        fm_ok=0
      fi
    fi
  fi

  # Fence-aware step-heading scan. Both anchors allow the SAME 0-3 leading
  # spaces, deliberately:
  #   - fences, because these files already contain indented ones (list-item
  #     code blocks) and a column-0-only toggle would scan their contents as
  #     live prose, hiding a step heading moved into one;
  #   - headings, because 1-3 spaces still render as a heading a reader will
  #     execute, so a column-0-only heading anchor lets one be hidden from the
  #     manifest by indenting it a single space.
  # At 4+ spaces the line is an indented code block, not a fence — recognising
  # one there is the fail-OPEN direction, because two such literal backtick
  # lines desync the toggle with even parity and every column-0 line between
  # them is skipped. Ignoring them can only over-count headings, which reds.
  if [ "$(awk '/^ ? ? ?```/ { n++ } END { print (n % 2) }' "$pf")" != "0" ]; then
    drift "$base: unbalanced code fence at EOF — the '### Step' scan cannot be trusted"
  fi
  heading_ids=$(awk '
    /^ ? ? ?```/ { fence = 1 - fence; next }
    fence { next }
    /^ ? ? ?### Step [0-9]+-[0-9]+[a-z]?/ {
      if (match($0, /[0-9]+-[0-9]+[a-z]?/)) print substr($0, RSTART, RLENGTH)
    }
  ' "$pf")
  heading_count=$(printf '%s' "$heading_ids" | grep -c . || true)
  heading_joined=$(printf '%s\n' "$heading_ids" | grep . | tr '\n' ',' | sed 's/,$//; s/,/, /g')

  if [ "$fm_ok" -eq 1 ]; then
    # 8b — exact key set, no missing and no extra.
    keys_have=$(sed -n "2,$((close - 1))p" "$pf" | sed -nE 's/^([a-z_]+):.*/\1/p' | sort | tr '\n' ',' | sed 's/,$//')
    keys_want=$(printf '%s\n' core phase step_ids steps title | sort | tr '\n' ',' | sed 's/,$//')
    [ "$keys_have" = "$keys_want" ] || \
      drift "$base: front matter key set is [$keys_have], expected [$keys_want]"

    fm_phase=$(fm_get "$pf" "$close" phase)
    fm_title=$(fm_get "$pf" "$close" title)
    fm_steps=$(fm_get "$pf" "$close" steps)
    fm_ids=$(fm_get "$pf" "$close" step_ids)
    fm_core=$(fm_get "$pf" "$close" core)

    # 8c — declared phase vs the filename. Only 8c and 8h bind to the
    # filename's <N>; 8d/8e use the generic ID grammar, so mutating `phase:`
    # cannot cascade into them.
    [ "$fm_phase" = "$file_n" ] || \
      drift "$base: front matter declares phase $fm_phase but filename says $file_n"

    # 8d / 8e — declared step count and ID list vs the out-of-fence headings.
    [ "$fm_steps" = "$heading_count" ] || \
      drift "$base: front matter declares $fm_steps steps but file has $heading_count '### Step' headings"
    ids_norm=$(printf '%s\n' "$fm_ids" | sed 's/[[:space:]]*,[[:space:]]*/, /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ "$ids_norm" = "$heading_joined" ] || \
      drift "$base: step_ids [$ids_norm] does not match headings [$heading_joined]"

    # 8f — declared title vs the first heading after the block.
    head_title=$(awk -v start="$((close + 1))" 'NR >= start && /^## / { sub(/^## /, ""); print; exit }' "$pf")
    title_norm=$(printf '%s\n' "$fm_title" | sed 's/^"//; s/"$//')
    [ "$title_norm" = "$head_title" ] || \
      drift "$base: title '$title_norm' does not match heading '$head_title'"

    # 8g — core names a step that is both declared and actually present.
    core_id=$(printf '%s\n' "$fm_core" | sed -nE 's/^[[:space:]]*([0-9]+-[0-9]+[a-z]?).*/\1/p')
    if [ -z "$core_id" ]; then
      drift "$base: core does not begin with a step ID"
    else
      printf '%s\n' "$ids_norm" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -qx "$core_id" \
        || drift "$base: core names step $core_id, which is not in step_ids"
      printf '%s\n' "$heading_ids" | grep -qx "$core_id" \
        || drift "$base: core names step $core_id, which is not a counted '### Step' heading"
    fi

    # 8i — every key SKILL.md tells readers to reconcile against must exist.
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      printf '%s\n' "$keys_have" | tr ',' '\n' | grep -qx "$k" \
        || drift "$base: SKILL.md references front-matter key '$k' which is absent"
    done <<< "$SKILL_KEYS"
  fi

  # 8h — the terminator. Runs unconditionally: its inputs are the filename and
  # the stem from SKILL.md, not the parsed window, and it is the clause a
  # partial reader actually depends on. Skipped only when no stem was declared
  # (I29) — with an empty stem the loose scan below would match every line.
  if [ -n "$STEM_PHASE" ]; then
    term_count=$(grep -c "^## $STEM_PHASE-[0-9]\{1,\}$" "$pf" || true)
    if [ "$term_count" -ne 1 ]; then
      drift "$base: terminator '## $STEM_PHASE-<N>' appears $term_count times, expected exactly 1"
    else
      term_line=$(grep "^## $STEM_PHASE-[0-9]\{1,\}$" "$pf")
      term_n=${term_line##*-}
      [ "$term_n" = "$file_n" ] || \
        drift "$base: terminator declares $term_n but filename says $file_n"
      [ "$(sed '/^[[:space:]]*$/d' "$pf" | tail -1)" = "$term_line" ] || \
        drift "$base: terminator is not the last non-empty line"
    fi
    # Loose lookalike scan. Strict anchoring is right for presence and wrong
    # for uniqueness: the entity that must not be fooled is a model reading
    # rendered markdown, and a trailing space, a three-space indent, a unicode
    # dash or a zero-width space all render identically while defeating an
    # anchored match. Reducing to alphanumerics closes the class rather than
    # enumerating the evasions. Strict-form lines are excluded so 8h.1 and
    # 8h.3 stay separately provable.
    stem_red=$(printf '%s' "$STEM_PHASE" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    last_ne=$(awk 'NF { n = NR } END { print n + 0 }' "$pf")
    decoy=$(awk -v stem="$stem_red" -v lastne="$last_ne" -v strict="^## $STEM_PHASE-[0-9]+$" '
      NR == lastne { next }
      $0 ~ strict { next }
      {
        s = tolower($0)
        gsub(/[^a-z0-9]/, "", s)
        if (index(s, stem) > 0) { print NR; exit }
      }
    ' "$pf")
    [ -z "$decoy" ] || \
      drift "$base: line $decoy resembles a terminator a truncated read would trust"
  fi

  # Counted-set vs readable-set. The strict anchor above deliberately stops at
  # 3 leading spaces so that `### Step`-shaped lines inside legitimate indented
  # code blocks are not counted. But a tab-indented heading, one at 4 spaces
  # inside a list item, and a blockquoted one are all still instructions a
  # reader acts on — and none would appear in step_ids, so the reconciliation
  # the protocol mandates would walk an under-declared manifest. Same shape as
  # the terminator lookalike scan: strict anchoring for the counted set, a loose
  # scan for anything a reader would act on that the strict form missed.
  loose=$(awk '
    /^[[:space:]>]*###[[:space:]]+Step [0-9]+-[0-9]+[a-z]?/ &&
    !/^ ? ? ?### Step [0-9]+-[0-9]+[a-z]?/ { print NR; exit }
  ' "$pf")
  [ -z "$loose" ] || \
    drift "$base: line $loose is a step-shaped heading the manifest scan does not count"
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Rule-ID drift detected. Sync points: common-rules.md table + template"
  echo "block, the Extended-obligations pointer sentence, phase-1/phase-3"
  echo "'- RSn/RTn: [status]' lines, and every 'R1-Rn'/'RS1-RSn'/'RT1-RTn'"
  echo "range string in the five checked files, common-rules.digest.md,"
  echo "mandatory rule-details references/files/ID-pattern identities, and the"
  echo "phase manifest (front matter vs '### Step' headings, terminators, and"
  echo "SKILL.md's declaration of the keys and stems readers rely on)."
  exit 1
fi

echo "OK: R1-R$MAX_R / RS1-RS$MAX_RS / RT1-RT$MAX_RT consistent across all sync points"
exit 0
