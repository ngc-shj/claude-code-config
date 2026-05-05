#!/bin/bash
# Find hardcoded literals in a diff that match constants already defined
# elsewhere in the codebase — surface candidate R2 / RT3 violations
# (constants hardcoded in multiple places, or shared constants ignored
# in test files).
#
# Survey of passwd-sso's review history: R2 fired 72 times and RT3 (test
# scope) 46 times — combined the second-largest gap behind R3. The
# fingerprint family (PRs #55-60) flags HIGH-FREQUENCY literals as
# "consider extracting a constant" preventively. This hook is the
# corrective counterpart: when you've ALREADY hardcoded a value that
# matches an EXISTING constant, point at the constant directly so the
# fix is mechanical.
#
# Detection
#   1. Scan unchanged source files for module-level constant declarations
#      whose value is a numeric or string literal:
#        - TS/JS: export const NAME = <literal>
#        - Python: NAME = <literal>      (all-uppercase NAME, no leading whitespace)
#        - Go: const NAME = <literal>    (capitalized NAME)
#   2. Extract `+`-line literals from the diff.
#   3. Emit "did you mean to use NAME?" suggestions for matches.
#
# Severity
#   - String literal match: Major. Strings rarely collide by accident.
#   - Numeric literal match: Minor. Numbers can mean different things in
#     different contexts (30 = seconds vs. retry count vs. batch size);
#     the suggestion is still useful but the user must judge intent.
#
# Out of scope
#   - Constants whose VALUE is an expression (`MS_PER_HOUR = 60 * 60 * 1000`).
#     The map is built from literal-RHS declarations only. Expression
#     RHS would need an evaluator.
#   - Constants in nested blocks or inside functions (only module-level).
#   - Block-form Go declarations (`const ( NAME = 30 )`) — single-line only.
#
# Usage: bash check-hardcoded-reuse.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   STRING_MIN_LENGTH (default: 4)  — suppress short strings (high collision)
#   NUMERIC_MIN_DIGITS (default: 2) — suppress 0/1/single-digit numbers
#   MAX_HITS_PER_LITERAL (default: 5) — cap reported diff sites per match
#
# Output: human-scannable findings grouped by category. Exit 0 always.

set -u

# Single per-script tempdir + EXIT-trap cleanup. Same pattern as the
# fingerprint and propagation hooks.
_HCR_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_HCR_TMPDIR'" EXIT

BASE_REF="${1:-main}"
# String floor at 4 chars catches API paths / error messages / enum
# values; below that, collisions with type discriminators dominate.
STRING_MIN_LENGTH="${STRING_MIN_LENGTH:-4}"
# Numeric floor at 3 digits skips 1-2 digit numbers — those collide
# heavily across protocol byte codes / array indices / loop counts /
# port ranges, producing low-signal suggestions.
NUMERIC_MIN_DIGITS="${NUMERIC_MIN_DIGITS:-3}"
MAX_HITS_PER_LITERAL="${MAX_HITS_PER_LITERAL:-5}"
# Common short tokens that match constants by accident: HTTP methods,
# boolean strings, common type discriminators. These are never useful
# R2 anchors even when a constant happens to share the literal value.
LITERAL_DENYLIST_RE='^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|true|false|null|undefined|none|None|True|False|yes|no|on|off|string|number|boolean|object|array)$'

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

CHANGED_FILES_LIST="$_HCR_TMPDIR/changed.txt"
UNCHANGED_FILES_LIST="$_HCR_TMPDIR/unchanged.txt"
git diff --name-only "$BASE_REF...HEAD" > "$CHANGED_FILES_LIST"

# Source-code whitelist (matches check-propagation.sh's set). Migration
# history and codegen output are excluded — they're append-only / regenerated
# and constants there don't reflect the canonical shared-constant surface.
SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|kts|scala|cs|fs|vb|swift|m|mm|c|h|hpp|hxx|cpp|cc|cxx|php|pl|pm|ex|exs|erl|hrl|elm|clj|cljs|cljc|edn|lua|sh|bash|zsh|fish|graphql|gql)$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"
git ls-files \
  | grep -vxFf "$CHANGED_FILES_LIST" \
  | grep -E "$SOURCE_EXT_RE" \
  | grep -vE "$EXCLUDE_PATH_RE" \
  > "$UNCHANGED_FILES_LIST"

CHANGED_COUNT=$(wc -l < "$CHANGED_FILES_LIST")

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "=== Hardcoded-Reuse Check ==="
  echo "Base: $BASE_REF"
  echo "No changed files in $BASE_REF...HEAD — nothing to check."
  exit 0
fi

# --- Build the constant-value map from unchanged source files ---
# Format per row: VALUE<TAB>NAME<TAB>FILE:LINE
# Numeric values stored bare; string values stored with original quotes
# preserved (so "foo" and 'foo' don't collide on lookup).
NUMERIC_MAP="$_HCR_TMPDIR/numeric_map.tsv"
STRING_MAP="$_HCR_TMPDIR/string_map.tsv"
: > "$NUMERIC_MAP"
: > "$STRING_MAP"

# Pattern catalog. Each (lang, regex, awk-extractor) tuple builds rows
# into the map files. The grep regex is intentionally loose; the awk
# tightens.
extract_constants() {
  local files_list="$1"

  if command -v rg >/dev/null 2>&1; then
    # TS/JS: `export const NAME = N|"S"|'S'`
    xargs -d '\n' -a "$files_list" rg --no-heading --color=never -nH \
      '^\s*(export\s+)?const\s+[A-Z_][A-Z0-9_]+\s*=\s*([0-9]+|"[^"\\]*"|'\''[^'\''\\]*'\'')' 2>/dev/null
    # Python: `NAME = N|"S"|'S'` at column 0, all-uppercase
    xargs -d '\n' -a "$files_list" rg --no-heading --color=never -nH \
      '^[A-Z_][A-Z0-9_]+\s*=\s*([0-9]+|"[^"\\]*"|'\''[^'\''\\]*'\'')' 2>/dev/null
    # Go: `const NAME = N|"S"` (capitalized NAME)
    xargs -d '\n' -a "$files_list" rg --no-heading --color=never -nH \
      '^const\s+[A-Z][A-Za-z0-9_]+\s*=\s*([0-9]+|"[^"\\]*")' 2>/dev/null
  else
    xargs -d '\n' -a "$files_list" grep -HnE \
      '^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Z_][A-Z0-9_]+[[:space:]]*=[[:space:]]*([0-9]+|"[^"]*"|'\''[^'\'']*'\'')' 2>/dev/null
    xargs -d '\n' -a "$files_list" grep -HnE \
      '^[A-Z_][A-Z0-9_]+[[:space:]]*=[[:space:]]*([0-9]+|"[^"]*"|'\''[^'\'']*'\'')' 2>/dev/null
    xargs -d '\n' -a "$files_list" grep -HnE \
      '^const[[:space:]]+[A-Z][A-Za-z0-9_]+[[:space:]]*=[[:space:]]*([0-9]+|"[^"]*")' 2>/dev/null
  fi
}

extract_constants "$UNCHANGED_FILES_LIST" \
  | awk -F: -v num_map="$NUMERIC_MAP" -v str_map="$STRING_MAP" -v min_digits="$NUMERIC_MIN_DIGITS" -v min_strlen="$STRING_MIN_LENGTH" '
      {
        # Recover file (paths rarely contain :) — first colon is file/line
        # separator; rg -n / grep -Hn output is `file:line:content`.
        idx = index($0, ":")
        if (idx == 0) next
        file = substr($0, 1, idx - 1)
        rest = substr($0, idx + 1)
        idx2 = index(rest, ":")
        if (idx2 == 0) next
        lineno = substr(rest, 1, idx2 - 1)
        line = substr(rest, idx2 + 1)
        # Extract NAME (the all-caps identifier on the LHS).
        # Strip leading whitespace, optional `export`, optional `const`.
        sub(/^[[:space:]]+/, "", line)
        sub(/^export[[:space:]]+/, "", line)
        sub(/^const[[:space:]]+/, "", line)
        if (!match(line, /^[A-Z_][A-Z0-9_]*[A-Za-z0-9_]*/)) next
        name = substr(line, RSTART, RLENGTH)
        # Walk past NAME + whitespace + `=` + whitespace.
        rhs = substr(line, RSTART + RLENGTH)
        sub(/^[[:space:]]*=[[:space:]]*/, "", rhs)
        # Match value: numeric, double-quoted, single-quoted.
        if (match(rhs, /^[0-9]+/)) {
          v = substr(rhs, RSTART, RLENGTH)
          if (length(v) >= min_digits) print v "\t" name "\t" file ":" lineno >> num_map
        } else if (match(rhs, /^"[^"]*"/)) {
          v = substr(rhs, RSTART, RLENGTH)
          # Strip outer quotes for the map key (case-insensitive cross-language).
          body = substr(v, 2, length(v) - 2)
          if (length(body) >= min_strlen) print body "\t" name "\t" file ":" lineno >> str_map
        } else if (match(rhs, /^'\''[^'\'']*'\''/)) {
          v = substr(rhs, RSTART, RLENGTH)
          body = substr(v, 2, length(v) - 2)
          if (length(body) >= min_strlen) print body "\t" name "\t" file ":" lineno >> str_map
        }
      }
    '

NUMERIC_CONSTANTS=$(wc -l < "$NUMERIC_MAP")
STRING_CONSTANTS=$(wc -l < "$STRING_MAP")

# --- Output header ---
echo "=== Hardcoded-Reuse Check ==="
echo "Base: $BASE_REF"
echo "Changed files: $CHANGED_COUNT  Unchanged source files: $(wc -l < "$UNCHANGED_FILES_LIST")"
echo "Constants indexed: $NUMERIC_CONSTANTS numeric, $STRING_CONSTANTS string"
echo ""

if [ "$NUMERIC_CONSTANTS" -eq 0 ] && [ "$STRING_CONSTANTS" -eq 0 ]; then
  echo "No shared constants found in unchanged files — nothing to cross-reference."
  exit 0
fi

# --- Diff added literals ---
# Scope to SOURCE files only — markdown/docs/changelog routinely contain
# numeric and string literals (port lists, version numbers, API paths in
# explanatory text) that aren't candidates for constant-extraction.
ADDED_LINES="$_HCR_TMPDIR/added_lines.txt"
git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
  | awk -v src_re="${SOURCE_EXT_RE//\\/\\\\}" -v exclude_re="${EXCLUDE_PATH_RE//\\/\\\\}" '
      /^\+\+\+ b\// {
        sub(/^\+\+\+ b\//, "")
        file = $0
        # Skip non-source files entirely.
        in_source = (file ~ src_re && file !~ exclude_re)
        next
      }
      /^\+\+\+ \/dev\/null/ { in_source = 0; next }
      /^@@/ {
        if (match($0, /\+[0-9]+/)) {
          lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
        }
        next
      }
      /^\+[^+]/ {
        if (in_source) {
          content = substr($0, 2)
          print file "\t" lineno "\t" content
        }
        lineno++
      }
    ' \
  > "$ADDED_LINES"

# Skip values that map to multiple distinct constants — the suggestion
# becomes ambiguous ("did you mean A or B or C?" isn't actionable). Cap
# at 1 by default: ONLY emit when there's exactly one candidate constant
# for the literal. Set higher to see ambiguous suggestions too.
MAX_CANDIDATES_PER_VALUE="${MAX_CANDIDATES_PER_VALUE:-1}"

# --- Numeric literal cross-reference ---
emit_numeric_findings() {
  local hits_emitted=0
  echo "## R2 / RT3 — hardcoded numeric values matching shared constants"
  echo ""

  if [ ! -s "$NUMERIC_MAP" ]; then
    echo "  (no numeric constants indexed)"
    echo ""
    return
  fi

  # For each numeric constant value, collect the set of NAMEs that share it.
  # When more than MAX_CANDIDATES_PER_VALUE distinct names share a value,
  # the suggestion is ambiguous (the reviewer can't tell which constant the
  # diff intends) — skip those rows entirely.
  local agg
  agg="$_HCR_TMPDIR/numeric_agg.tsv"
  awk -F'\t' -v max="$MAX_CANDIDATES_PER_VALUE" '
    {
      key = $1
      uniq_key = key SUBSEP $2
      if (!(uniq_key in seen_name)) {
        seen_name[uniq_key] = 1
        count[key]++
        if (key in candidates) candidates[key] = candidates[key] " | " $2 " (" $3 ")"
        else candidates[key] = $2 " (" $3 ")"
      }
    }
    END {
      for (k in count) {
        if (count[k] <= max) print k "\t" candidates[k]
      }
    }' "$NUMERIC_MAP" > "$agg"

  # Walk added lines; for each numeric token >= min_digits, look up.
  while IFS=$'\t' read -r file lineno content; do
    # Skip diff lines that are themselves CONST declarations (don't suggest
    # using a constant when the user's `+` line IS adding a constant).
    if [[ "$content" =~ ^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Z_] ]]; then
      continue
    fi
    if [[ "$content" =~ ^[A-Z_][A-Z0-9_]+[[:space:]]*= ]]; then
      continue
    fi
    # Tokenize numeric literals on the line.
    local tokens
    tokens=$(echo "$content" | grep -hoE '\b[0-9]+\b' | sort -u)
    local n
    for n in $tokens; do
      [ "${#n}" -ge "$NUMERIC_MIN_DIGITS" ] || continue
      local matches
      matches=$(awk -F'\t' -v n="$n" '$1 == n { print $2; exit }' "$agg")
      if [ -n "$matches" ]; then
        if [ "$hits_emitted" -lt "$MAX_HITS_PER_LITERAL" ] || true; then
          printf '  [Minor] %s:%s — hardcoded `%s` matches existing constant: %s\n' \
            "$file" "$lineno" "$n" "$matches"
          hits_emitted=$((hits_emitted + 1))
        fi
      fi
    done
  done < "$ADDED_LINES"

  [ "$hits_emitted" -eq 0 ] && echo "  (no matches)"
  echo ""
}

# --- String literal cross-reference ---
emit_string_findings() {
  local hits_emitted=0
  echo "## R2 / RT3 — hardcoded string values matching shared constants"
  echo ""

  if [ ! -s "$STRING_MAP" ]; then
    echo "  (no string constants indexed)"
    echo ""
    return
  fi

  # Same dedup-and-cap as the numeric path. String values rarely share
  # multiple distinct names (collision is much rarer than for numbers),
  # but the cap keeps the path symmetric.
  local agg
  agg="$_HCR_TMPDIR/string_agg.tsv"
  awk -F'\t' -v max="$MAX_CANDIDATES_PER_VALUE" '
    {
      key = $1
      uniq_key = key SUBSEP $2
      if (!(uniq_key in seen_name)) {
        seen_name[uniq_key] = 1
        count[key]++
        if (key in candidates) candidates[key] = candidates[key] " | " $2 " (" $3 ")"
        else candidates[key] = $2 " (" $3 ")"
      }
    }
    END {
      for (k in count) {
        if (count[k] <= max) print k "\t" candidates[k]
      }
    }' "$STRING_MAP" > "$agg"

  while IFS=$'\t' read -r file lineno content; do
    # Skip diff lines that are themselves CONST declarations.
    if [[ "$content" =~ ^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Z_] ]]; then
      continue
    fi
    if [[ "$content" =~ ^[A-Z_][A-Z0-9_]+[[:space:]]*= ]]; then
      continue
    fi
    # Tokenize string literals (double / single quoted) on the line.
    local quoted_tokens
    quoted_tokens=$(echo "$content" | grep -hoE "\"[^\"\\\\]{$STRING_MIN_LENGTH,200}\"|'[^'\\\\]{$STRING_MIN_LENGTH,200}'")
    while IFS= read -r quoted; do
      [ -z "$quoted" ] && continue
      local body="${quoted:1:${#quoted}-2}"
      [ -z "$body" ] && continue
      # Skip common-token denylist (HTTP methods, type discriminators).
      if [[ "$body" =~ $LITERAL_DENYLIST_RE ]]; then
        continue
      fi
      local matches
      matches=$(awk -F'\t' -v b="$body" '$1 == b { print $2; exit }' "$agg")
      if [ -n "$matches" ]; then
        printf '  [Major] %s:%s — hardcoded `%s` matches existing constant: %s\n' \
          "$file" "$lineno" "$quoted" "$matches"
        hits_emitted=$((hits_emitted + 1))
      fi
    done <<< "$quoted_tokens"
  done < "$ADDED_LINES"

  [ "$hits_emitted" -eq 0 ] && echo "  (no matches)"
  echo ""
}

emit_numeric_findings
emit_string_findings

echo "=== End Hardcoded-Reuse Check ==="
