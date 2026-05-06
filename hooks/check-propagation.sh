#!/bin/bash
# Find unpropagated references in unchanged files.
#
# Triangulate aggregate (passwd-sso, 154 reviews) showed R3 (incomplete
# pattern propagation) at 151 findings — the dominant failure mode, larger
# than R1 (104). The fingerprint (PRs #55-60) is a *preventive* tool: it
# tells implementers "this is established, reuse it" before they write
# duplicate code. This hook is the *corrective* counterpart: given a diff,
# it finds places where a change should have been propagated to other
# files but wasn't.
#
# Three detection categories (MVP):
#   C1 Symbol rename:    identifier removed from changed files but still
#                        referenced in unchanged files (candidate rename
#                        gap — the rename in file A leaves stale calls in
#                        file B).
#   C2 Constant change:  `const NAME = OLD` → `const NAME = NEW` in changed
#                        file → unchanged files with hardcoded OLD value
#                        that may have been the same constant inlined.
#   C3 String literal:   string literal removed in diff and still present
#                        verbatim in unchanged files (highest-confidence
#                        category: string literals rarely collide with
#                        unrelated content).
#   C4 Signature change: function/method signature shape changed in diff
#                        (param count, param type, optional/rest/default,
#                        return type) — text-grep callers in unchanged
#                        files for stale-call candidates. Powered by AST
#                        (TypeScript Compiler API for TS/JS); silently
#                        skipped when the AST runtime is unavailable so
#                        C1-C3 still run.
#   C5 Enum coverage:    enum member added in diff and at least one
#                        unchanged file references the enum (qualified
#                        `EnumName.X`) but not the new member. R12: switch
#                        / match exhaustiveness gap. Same AST plumbing as
#                        C4 — silently skipped when the runtime is gone.
#
# Still out of scope:
#   - Regex / validation rule changes (context-dependent semantics)
#   - Cross-file call-graph resolution (caller search is text-based; same
#     FP surface as C1)
#
# Usage: bash check-propagation.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   IDENT_MIN_LENGTH (default: 4)  — drop candidate identifiers shorter than this
#   STRING_MIN_LENGTH (default: 8) — drop candidate string literals shorter than this
#   MAX_HITS_PER_CANDIDATE (default: 8) — cap reported locations per finding
#
# Output: human-scannable findings grouped by category, plus a final
# summary. Exit 0 always (this is a review aid, not a gate).

set -u

# Single per-script tempdir + EXIT-trap cleanup. Same pattern as the
# fingerprint hook so a mid-pipeline failure or signal doesn't leak.
_CP_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CP_TMPDIR'" EXIT

# AST library — provides ast_diff_signatures for C4. Sourcing is idempotent
# and registers all hooks/ast-langs/ plugins. Source path resolution mirrors
# how this hook is laid out under ~/.claude/hooks/ after install.sh runs.
_AST_SIG_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/ast-signature.sh"
if [ -f "$_AST_SIG_LIB" ]; then
  # shellcheck disable=SC1090
  source "$_AST_SIG_LIB"
fi

BASE_REF="${1:-main}"
IDENT_MIN_LENGTH="${IDENT_MIN_LENGTH:-4}"
IDENT_MIN_REMOVALS="${IDENT_MIN_REMOVALS:-2}"   # candidate must appear in >= N removed lines (suppresses single-import-removal noise)
STRING_MIN_LENGTH="${STRING_MIN_LENGTH:-8}"
MAX_HITS_PER_CANDIDATE="${MAX_HITS_PER_CANDIDATE:-8}"

# Trusted root + base-ref validation
TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

# Files changed in the diff. The unchanged set is the SOURCE CODE we want
# to scan for stale references — markdown / changelog / migration history /
# archived plans are deliberately out of scope. Identifiers like `Button`,
# `Also`, `Behavior` are both English words and code identifiers; without
# this scope they pollute every diff with prose-level "stale reference"
# noise that has no R3 meaning.
CHANGED_FILES_LIST="$_CP_TMPDIR/changed.txt"
UNCHANGED_FILES_LIST="$_CP_TMPDIR/unchanged.txt"
git diff --name-only "$BASE_REF...HEAD" > "$CHANGED_FILES_LIST"

# Source-code whitelist (extension-based). Anything not on the whitelist
# is assumed prose / data / migration artifact and excluded.
SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|kts|scala|cs|fs|vb|swift|m|mm|c|h|hpp|hxx|cpp|cc|cxx|php|pl|pm|ex|exs|erl|hrl|elm|clj|cljs|cljc|edn|lua|sh|bash|zsh|fish|graphql|gql)$'
# Migration directories are append-only history — they MUST NOT be updated
# retroactively when production code names change, so any "stale reference"
# in them is by definition not a propagation gap. Same for vendored deps
# and codegen output that the project shouldn't hand-edit.
# Migration histories are append-only by contract; codegen output is
# regenerated. Patterns are framework-family generic (Prisma uses
# `prisma/migrations/`, Alembic uses `alembic/versions/`, Rails uses
# `db/migrate/`, etc. — all caught by the `*/(migrations?|migrate|versions)/`
# pattern). Override or extend via `EXTRA_EXCLUDE_PATH_RE` env var if a
# project uses a non-conventional path.
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"
git ls-files \
  | grep -vxFf "$CHANGED_FILES_LIST" \
  | grep -E "$SOURCE_EXT_RE" \
  | grep -vE "$EXCLUDE_PATH_RE" \
  > "$UNCHANGED_FILES_LIST"

CHANGED_COUNT=$(wc -l < "$CHANGED_FILES_LIST")
UNCHANGED_COUNT=$(wc -l < "$UNCHANGED_FILES_LIST")

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "=== Propagation Check ==="
  echo "Base: $BASE_REF"
  echo "No changed files in $BASE_REF...HEAD — nothing to check."
  exit 0
fi

# Common-keyword denylist for symbol renames. These appear in nearly every
# diff because they're the language's own keywords; reporting them as
# "renamed" would generate massive false positives. Languages covered:
# TS/JS, Python, Go, Java, Rust common minimum.
KEYWORD_DENYLIST_RE='^(const|let|var|function|class|type|interface|enum|export|import|return|if|else|elif|for|while|do|switch|case|break|continue|true|false|null|undefined|void|new|this|self|None|True|False|def|pass|raise|except|try|finally|with|as|from|in|is|not|and|or|public|private|protected|static|abstract|final|override|virtual|async|await|yield|throw|throws|catch|extends|implements|namespace|module|package|use|fn|impl|struct|trait|mod|pub|crate|let|match|where|loop|move|ref|self|super|str|bool|int|long|short|char|byte|float|double|string)$'

# --- Output ---
echo "=== Propagation Check ==="
echo "Base: $BASE_REF"
echo "Changed files: $CHANGED_COUNT  Unchanged files (search scope): $UNCHANGED_COUNT"
echo ""

# Helper: emit a finding row.
_emit_finding() {
  local severity="$1"
  local file_line="$2"
  local message="$3"
  printf '  [%s] %s — %s\n' "$severity" "$file_line" "$message"
}

# --- C1: Symbol rename candidates ---
# Identifiers present on `-` lines but not on `+` lines are candidate-removed.
# Anything that *also* appears in unchanged files is a candidate stale
# reference. False positives: comments / strings echoing the same word.
detect_symbol_renames() {
  echo "## C1 Symbol rename — identifiers removed from diff but still referenced elsewhere"
  echo ""

  local removed_idents added_idents candidate_idents
  removed_idents="$_CP_TMPDIR/c1_removed.txt"
  added_idents="$_CP_TMPDIR/c1_added.txt"
  candidate_idents="$_CP_TMPDIR/c1_candidates.txt"

  # First: count removals per identifier ONLY on lines that look like a
  # code definition or import position. Stripping prose / comment / string
  # context kills the dominant FP source (common words like "Production",
  # "Behavior", "Replaces" appearing in tests/configs/markdown that happen
  # to be edited). Code-position patterns covered:
  #   import { X } from 'y'
  #   export { X } / export function X / export class X / etc.
  #   function X(...) / class X / interface X / type X / enum X
  #   const X = / let X = / var X = / pub fn X / def X / func X
  local removal_counts
  removal_counts="$_CP_TMPDIR/c1_removal_counts.txt"
  git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
    | grep -E '^-[^-]' \
    | grep -E '^-[[:space:]]*(import|export|function|class|interface|type|enum|const|let|var|def|fn|func|public|private|pub)\b|\bimport[[:space:]]*\{|\{[[:space:]]*[A-Za-z_]' \
    | grep -oE "\\b[A-Za-z_][A-Za-z0-9_]{$((IDENT_MIN_LENGTH - 1)),}\\b" \
    | sort | uniq -c | awk -v min="$IDENT_MIN_REMOVALS" '$1 >= min { print $2 }' \
    > "$removed_idents"

  git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
    | grep -E '^\+[^+]|^\+\+\+' | grep -v '^+++' \
    | grep -oE "\\b[A-Za-z_][A-Za-z0-9_]{$((IDENT_MIN_LENGTH - 1)),}\\b" \
    | sort -u > "$added_idents"

  # removed-but-not-added AND not a language keyword
  sort -u "$removed_idents" \
    | comm -23 - "$added_idents" \
    | grep -vE "$KEYWORD_DENYLIST_RE" \
    > "$candidate_idents"

  if [ ! -s "$candidate_idents" ]; then
    echo "  (no rename candidates found)"
    echo ""
    return
  fi

  # Single bulk grep across all unchanged files for any candidate identifier.
  # Faster than per-symbol grep on large repos.
  local pattern hits_file
  pattern=$(paste -sd'|' "$candidate_idents")
  hits_file="$_CP_TMPDIR/c1_hits.txt"

  if command -v rg >/dev/null 2>&1; then
    # file:line:match — `-n` forces line numbers; `--no-heading` flattens
    # the per-file header rg uses for human display.
    xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
      rg -n --no-heading --color=never -wo "($pattern)" 2>/dev/null \
      | sort -u > "$hits_file"
  else
    xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
      grep -HnoE "\\b($pattern)\\b" 2>/dev/null \
      | sort -u > "$hits_file"
  fi

  local found=0
  while IFS= read -r ident; do
    [ -z "$ident" ] && continue
    # hits_file rows are 'file:line:match'. Filter to rows where match == ident.
    local matches
    matches=$(grep -E ":${ident}\$" "$hits_file" \
      | head -"$MAX_HITS_PER_CANDIDATE")
    if [ -n "$matches" ]; then
      # Severity: Minor. Identifier-rename detection without AST awareness
      # is inherently noisy — common words and shared library names
      # produce false positives that would crowd out higher-confidence
      # findings if marked Major.
      echo "$matches" | while IFS=: read -r f l _rest; do
        _emit_finding "Minor" "$f:$l" "candidate stale reference to '$ident' (removed in diff)"
      done
      found=1
    fi
  done < "$candidate_idents"

  [ "$found" -eq 0 ] && echo "  (no stale references found in unchanged files)"
  echo ""
}

# --- C2: Constant value change candidates ---
# `const NAME = OLD` → `const NAME = NEW` in changed files. Unchanged files
# with hardcoded OLD are candidates that should reference the constant.
# We scope to numeric literals only — string literals are covered by C3.
detect_constant_changes() {
  echo "## C2 Constant value change — hardcoded old value still present in unchanged files"
  echo ""

  local pairs_file
  pairs_file="$_CP_TMPDIR/c2_pairs.txt"

  # Walk the diff hunks; pair `-const NAME = N` with `+const NAME = M` when
  # the same NAME appears on both sides. Naive: rely on diff's hunk
  # alignment for one-removed / one-added pairs.
  git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
    | awk '
        /^-/ {
          if (match($0, /(const|let|var|final)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*([0-9]+)/, m)) {
            removed[m[2]] = m[3]
          } else if (match($0, /^-[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*([0-9]+)/, m)) {
            removed[m[1]] = m[2]
          }
        }
        /^\+/ {
          if (match($0, /(const|let|var|final)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*([0-9]+)/, m)) {
            added[m[2]] = m[3]
          } else if (match($0, /^\+[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*([0-9]+)/, m)) {
            added[m[1]] = m[2]
          }
        }
        END {
          for (n in removed) {
            if (n in added && removed[n] != added[n]) {
              print n "\t" removed[n] "\t" added[n]
            }
          }
        }
      ' > "$pairs_file"

  if [ ! -s "$pairs_file" ]; then
    echo "  (no constant value changes detected in diff)"
    echo ""
    return
  fi

  local found=0
  while IFS=$'\t' read -r name oldval newval; do
    [ -z "$name" ] && continue
    # Find unchanged files with the OLD value as a standalone token.
    local hits
    hits=$(xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
      grep -HnE "\\b${oldval}\\b" 2>/dev/null \
      | head -"$MAX_HITS_PER_CANDIDATE")
    if [ -n "$hits" ]; then
      echo "  Constant ${name}: ${oldval} → ${newval}"
      echo "$hits" | while IFS=: read -r f l rest; do
        _emit_finding "Minor" "$f:$l" "hardcoded ${oldval} may need update to ${newval} (constant ${name} changed)"
      done
      echo ""
      found=1
    fi
  done < "$pairs_file"

  [ "$found" -eq 0 ] && { echo "  (constant changes detected but no hardcoded occurrences in unchanged files)"; echo ""; }
}

# --- C3: String literal change candidates ---
# String literals removed in the diff and still present verbatim in
# unchanged files. Highest-confidence category: string literals rarely
# collide with unrelated content, so a hit is almost always meaningful.
detect_string_literal_changes() {
  echo "## C3 String literal change — removed strings still present in unchanged files"
  echo ""

  local strings_file
  strings_file="$_CP_TMPDIR/c3_strings.txt"

  # Extract removed strings: long enough to be meaningful, not in the added
  # set (so we're confident it was actually removed and not relocated).
  git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
    | grep -E '^-[^-]' \
    | grep -hoE "\"[^\"\\\\]{$STRING_MIN_LENGTH,200}\"|'[^'\\\\]{$STRING_MIN_LENGTH,200}'" \
    | sort -u > "$_CP_TMPDIR/c3_removed.txt"

  git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
    | grep -E '^\+[^+]' \
    | grep -hoE "\"[^\"\\\\]{$STRING_MIN_LENGTH,200}\"|'[^'\\\\]{$STRING_MIN_LENGTH,200}'" \
    | sort -u > "$_CP_TMPDIR/c3_added.txt"

  comm -23 "$_CP_TMPDIR/c3_removed.txt" "$_CP_TMPDIR/c3_added.txt" > "$strings_file"

  if [ ! -s "$strings_file" ]; then
    echo "  (no removed strings detected in diff)"
    echo ""
    return
  fi

  local found=0
  while IFS= read -r quoted; do
    [ -z "$quoted" ] && continue
    # Strip outer quotes for grep -F; re-add them when reporting context.
    local body="${quoted:1:${#quoted}-2}"
    [ -z "$body" ] && continue
    # Skip CSS utility-class clusters (Tailwind / similar). Multi-token
    # all-lowercase strings of the form "flex items-center gap-2" are
    # repeated by design across components and produce no R3 signal.
    case "$body" in
      *' '*)
        local _tw_re='^[a-z][a-z0-9. /:-]*$'
        if [[ "$body" =~ $_tw_re ]]; then
          continue
        fi
        ;;
    esac
    # Skip JSON / object-syntax fragments. Strings containing braces or
    # brackets are typically string-concatenation pieces in test fixtures
    # building serialized payloads — they correlate weakly with R3.
    if [[ "$body" =~ [][{}] ]]; then
      continue
    fi
    # Skip pure UUID test fixtures — repeated across many tests by design.
    local _uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    if [[ "$body" =~ $_uuid_re ]]; then
      continue
    fi
    local hits
    hits=$(xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
      grep -HnF -- "$body" 2>/dev/null \
      | head -"$MAX_HITS_PER_CANDIDATE")
    if [ -n "$hits" ]; then
      echo "  Removed string: $quoted"
      echo "$hits" | while IFS=: read -r f l rest; do
        _emit_finding "Major" "$f:$l" "still contains ${quoted} (removed elsewhere in diff)"
      done
      echo ""
      found=1
    fi
  done < "$strings_file"

  [ "$found" -eq 0 ] && { echo "  (removed strings detected but not present in unchanged files)"; echo ""; }
}

# --- C4: Function / method signature change candidates ---
# AST-driven. Two-phase:
#   Phase 1: per-file diff_signatures collects all changed signatures.
#   Phase 2a (shape changes): one ast_find_references_batch call resolves
#     true callers via TS LanguageService — name-collision FP eliminated.
#   Phase 2b (removed exports): text-grep, because findReferences cannot
#     resolve a base-only declaration (the symbol no longer exists at
#     head). Same heuristic as before; IDENT_MIN_LENGTH still applied.
# Silently skipped if the AST runtime (Node + typescript module) is not
# provisioned — the regex categories above still run.
detect_signature_changes() {
  echo "## C4 Signature change — function shape changed in diff, callers may be stale"
  echo ""

  if ! command -v ast_diff_signatures >/dev/null 2>&1; then
    echo "  (AST library not loaded — install.sh did not provision hooks/lib/)"
    echo ""
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  (jq not on PATH — required to parse AST diff output)"
    echo ""
    return
  fi

  local ts_changed_list="$_CP_TMPDIR/c4_changed_ts.txt"
  : > "$ts_changed_list"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    ast_lang_for_file "$f" >/dev/null 2>&1 || continue
    ast_available "$f" >/dev/null 2>&1 || continue
    echo "$f" >> "$ts_changed_list"
  done < "$CHANGED_FILES_LIST"

  if [ ! -s "$ts_changed_list" ]; then
    echo "  (no AST-supported source files in diff)"
    echo ""
    return
  fi

  # Collect every changed signature across every changed file into one
  # JSON array, annotating each entry with its declFile so the batch
  # find-references call can be a single Node invocation.
  local all_changes="$_CP_TMPDIR/c4_all_changes.json"
  echo "[]" > "$all_changes"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local base_tmp="$_CP_TMPDIR/c4_base_$(echo "$f" | tr '/' '_')"
    if ! git show "$BASE_REF:$f" > "$base_tmp" 2>/dev/null; then continue; fi
    local diff_json
    diff_json=$(ast_diff_signatures "$base_tmp" "$f" 2>/dev/null) || continue
    [ -z "$diff_json" ] && continue
    [ "$diff_json" = "[]" ] && continue
    jq --arg f "$f" --slurpfile prev "$all_changes" \
      'map(. + {declFile: $f}) + $prev[0]' \
      <(echo "$diff_json") > "$all_changes.tmp"
    mv "$all_changes.tmp" "$all_changes"
  done < "$ts_changed_list"

  local total_changes
  total_changes=$(jq 'length' "$all_changes")
  if [ "$total_changes" -eq 0 ]; then
    echo "  (no signature changes with surviving callers found)"
    echo ""
    return
  fi

  # Split into AST-resolvable (shape changes) and text-grep-only (removed).
  local shape_set="$_CP_TMPDIR/c4_shape.json"
  local removed_set="$_CP_TMPDIR/c4_removed.json"
  jq '[.[] | select(.changes | index("removed") | not)]' "$all_changes" > "$shape_set"
  jq '[.[] | select(.changes | index("removed"))]' "$all_changes" > "$removed_set"

  local found=0

  # ---- shape changes: AST refs ----
  local shape_n
  shape_n=$(jq 'length' "$shape_set")
  if [ "$shape_n" -gt 0 ] && command -v ast_find_references_batch >/dev/null 2>&1; then
    # Build the batch query: one entry per shape-change signature.
    local batch_input="$_CP_TMPDIR/c4_batch_input.json"
    jq '[.[] | {declFile, name, owner: (.owner // "")}]' "$shape_set" > "$batch_input"

    local refs_output="$_CP_TMPDIR/c4_refs_output.json"
    if ast_find_references_batch "$batch_input" > "$refs_output" 2>/dev/null && [ -s "$refs_output" ]; then
      # shape_set[i] and refs_output[i] correspond — runner preserves input order.
      local i=0
      while [ "$i" -lt "$shape_n" ]; do
        local name owner kind detail changes_csv sev
        name=$(jq -r ".[$i].name" "$shape_set")
        owner=$(jq -r ".[$i].owner // \"\"" "$shape_set")
        kind=$(jq -r ".[$i].kind" "$shape_set")
        detail=$(jq -r ".[$i].detail" "$shape_set")
        changes_csv=$(jq -r ".[$i].changes | join(\",\")" "$shape_set")
        sev=$(jq -r ".[$i].severity // \"Minor\"" "$shape_set")

        # Filter refs: drop import / type-ref kinds (those don't break on
        # signature change), keep only files that are in UNCHANGED_FILES_LIST
        # (callers in changed files were already revised by the same diff).
        local locs="$_CP_TMPDIR/c4_locs_${i}.txt"
        jq -r ".[$i].references[] | select(.kind == \"ref\") | \"\(.file):\(.line)\"" \
          "$refs_output" | sort -u > "$locs"

        local final_hits="$_CP_TMPDIR/c4_final_${i}.txt"
        : > "$final_hits"
        while IFS=: read -r hf hl; do
          [ -z "$hf" ] && continue
          if grep -Fxq "$hf" "$UNCHANGED_FILES_LIST"; then
            echo "${hf}:${hl}" >> "$final_hits"
          fi
        done < "$locs"

        i=$((i + 1))

        if [ -s "$final_hits" ]; then
          local label
          if [ -n "$owner" ]; then label="${owner}.${name}"; else label="${name}"; fi
          echo "  ${kind} ${label}: ${detail}  [changes: ${changes_csv}]"
          local hit_count=0
          while IFS=: read -r hf hl; do
            [ "$hit_count" -ge "$MAX_HITS_PER_CANDIDATE" ] && break
            _emit_finding "$sev" "${hf}:${hl}" "calls '$name' — signature changed (${detail})"
            hit_count=$((hit_count + 1))
          done < "$final_hits"
          echo ""
          found=1
        fi
      done
    fi
  fi

  # ---- removed exports: text-grep ----
  # The base-only declaration cannot be AST-resolved against the head
  # program. IDENT_MIN_LENGTH still applies to suppress single-letter
  # name collisions (text-grep FP surface).
  local rem_n
  rem_n=$(jq 'length' "$removed_set")
  if [ "$rem_n" -gt 0 ]; then
    local i=0
    while [ "$i" -lt "$rem_n" ]; do
      local name owner kind detail changes_csv sev
      name=$(jq -r ".[$i].name" "$removed_set")
      owner=$(jq -r ".[$i].owner // \"\"" "$removed_set")
      kind=$(jq -r ".[$i].kind" "$removed_set")
      detail=$(jq -r ".[$i].detail" "$removed_set")
      changes_csv=$(jq -r ".[$i].changes | join(\",\")" "$removed_set")
      sev=$(jq -r ".[$i].severity // \"Major\"" "$removed_set")
      i=$((i + 1))

      if [ "${#name}" -lt "$IDENT_MIN_LENGTH" ]; then
        continue
      fi

      local hits
      hits=$(xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
        grep -HnE "\\b${name}\\b" 2>/dev/null \
        | head -"$MAX_HITS_PER_CANDIDATE")

      if [ -n "$hits" ]; then
        local label
        if [ -n "$owner" ]; then label="${owner}.${name}"; else label="${name}"; fi
        echo "  ${kind} ${label}: ${detail}  [changes: ${changes_csv}]"
        echo "$hits" | while IFS=: read -r hf hl _rest; do
          _emit_finding "$sev" "$hf:$hl" "calls '$name' — signature changed (${detail})"
        done
        echo ""
        found=1
      fi
    done
  fi

  [ "$found" -eq 0 ] && { echo "  (no signature changes with surviving callers found)"; echo ""; }
}

# --- C5: Enum coverage gap ---
# AST-driven. For each TS/JS file in the diff, compare BASE/HEAD enum
# member sets; for each newly-added member, find unchanged files that
# reference the enum (qualified `EnumName.X`) but NOT the new member.
# These are switch / match exhaustiveness candidates the reviewer should
# extend. v1 scope: TypeScript `enum` declarations only — discriminated
# unions / `as const` arrays are deferred. Silently skipped when the AST
# runtime is unavailable.
detect_enum_coverage_gaps() {
  echo "## C5 Enum coverage — enum member added, callers may not handle new variant"
  echo ""

  if ! command -v ast_diff_enums >/dev/null 2>&1; then
    echo "  (AST library not loaded — install.sh did not provision hooks/lib/)"
    echo ""
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  (jq not on PATH — required to parse AST diff output)"
    echo ""
    return
  fi

  local ts_changed_list="$_CP_TMPDIR/c5_changed_ts.txt"
  : > "$ts_changed_list"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    ast_lang_for_file "$f" >/dev/null 2>&1 || continue
    ast_available "$f" >/dev/null 2>&1 || continue
    echo "$f" >> "$ts_changed_list"
  done < "$CHANGED_FILES_LIST"

  if [ ! -s "$ts_changed_list" ]; then
    echo "  (no AST-supported source files in diff)"
    echo ""
    return
  fi

  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue

    local base_tmp="$_CP_TMPDIR/c5_base_$(echo "$f" | tr '/' '_')"
    if ! git show "$BASE_REF:$f" > "$base_tmp" 2>/dev/null; then
      continue
    fi

    local diff_json
    diff_json=$(ast_diff_enums "$base_tmp" "$f" 2>/dev/null) || continue
    [ -z "$diff_json" ] && continue
    [ "$diff_json" = "[]" ] && continue

    local enum_count
    enum_count=$(echo "$diff_json" | jq 'length')
    [ "$enum_count" -eq 0 ] && continue

    local i=0
    while [ "$i" -lt "$enum_count" ]; do
      local enum_name added_count
      enum_name=$(echo "$diff_json" | jq -r ".[$i].name")
      added_count=$(echo "$diff_json" | jq ".[$i].added | length")
      i=$((i + 1))

      [ "$added_count" -eq 0 ] && continue

      # Cheaper than per-member: compute "files referencing this enum" once,
      # then per-member compute "files referencing the new member" and take
      # the set difference.
      local files_with_enum_refs="$_CP_TMPDIR/c5_refs_${enum_name}.txt"
      xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
        grep -lE "\\b${enum_name}\\.[A-Za-z_][A-Za-z0-9_]*" 2>/dev/null \
        | sort -u > "$files_with_enum_refs"
      [ ! -s "$files_with_enum_refs" ] && continue

      local j=0
      while [ "$j" -lt "$added_count" ]; do
        local new_member
        new_member=$(echo "$diff_json" | jq -r ".[$((i - 1))].added[$j]")
        j=$((j + 1))

        # Files that DO reference the new member already — they are
        # presumed handled. Subtract them from the candidate set.
        local files_with_new_member="$_CP_TMPDIR/c5_new_${enum_name}_${new_member}.txt"
        xargs -d '\n' -a "$files_with_enum_refs" \
          grep -lE "\\b${enum_name}\\.${new_member}\\b" 2>/dev/null \
          | sort -u > "$files_with_new_member"

        local missing="$_CP_TMPDIR/c5_miss_${enum_name}_${new_member}.txt"
        comm -23 "$files_with_enum_refs" "$files_with_new_member" > "$missing"

        [ ! -s "$missing" ] && continue

        echo "  Enum ${enum_name}: new member ${new_member} added"
        local hit_count=0
        while IFS= read -r hf; do
          [ -z "$hf" ] && continue
          [ "$hit_count" -ge "$MAX_HITS_PER_CANDIDATE" ] && break
          # Report the first qualified reference line as the navigation
          # target — that's where the reviewer will start adding cases.
          local example_line
          example_line=$(grep -nE "\\b${enum_name}\\." "$hf" | head -1 | cut -d: -f1)
          _emit_finding "Minor" "${hf}:${example_line:-1}" \
            "references ${enum_name} but not new member ${enum_name}.${new_member}"
          hit_count=$((hit_count + 1))
          found=1
        done < "$missing"
        echo ""
      done
    done
  done < "$ts_changed_list"

  [ "$found" -eq 0 ] && { echo "  (no enum coverage gaps detected)"; echo ""; }
}

detect_symbol_renames
detect_constant_changes
detect_string_literal_changes
detect_signature_changes
detect_enum_coverage_gaps

echo "=== End Propagation Check ==="
