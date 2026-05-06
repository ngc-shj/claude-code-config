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
# AST-driven. For each TS/JS file in the diff, extract signatures at BASE
# and HEAD; flag functions whose param count, param shape, or return type
# changed. For each changed signature, text-grep callers in unchanged
# files. Silently skipped if the AST runtime (Node + typescript module) is
# not provisioned — the regex categories above still run.
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

  # Filter changed files to those a plugin can handle. ast_lang_for_file
  # echoes the lang key on stdout; we discard it and just check the exit
  # status. ast_available additionally checks runtime provisioning.
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

  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue

    # Reconstruct BASE-version of the file via `git show`. If the file
    # didn't exist at BASE (newly added), there's nothing to diff against
    # and signature changes don't apply (no callers existed yet).
    local base_tmp="$_CP_TMPDIR/c4_base_$(echo "$f" | tr '/' '_')"
    if ! git show "$BASE_REF:$f" > "$base_tmp" 2>/dev/null; then
      continue
    fi

    # Run AST diff. Failures (parse errors, runtime crashes) are non-fatal
    # — they just skip this file silently.
    local diff_json
    diff_json=$(ast_diff_signatures "$base_tmp" "$f" 2>/dev/null) || continue
    [ -z "$diff_json" ] && continue
    [ "$diff_json" = "[]" ] && continue

    # For each changed signature, extract (name, owner, kind, detail) and
    # search unchanged files for callers. Caller match is text-grep on the
    # method/function name as a word — same FP surface as C1 (cross-file
    # call-graph would be the next investment).
    local changed_count
    changed_count=$(echo "$diff_json" | jq 'length')
    [ "$changed_count" -eq 0 ] && continue

    local i=0
    while [ "$i" -lt "$changed_count" ]; do
      local name owner kind detail changes_csv
      name=$(echo "$diff_json" | jq -r ".[$i].name")
      owner=$(echo "$diff_json" | jq -r ".[$i].owner // \"\"")
      kind=$(echo "$diff_json" | jq -r ".[$i].kind")
      detail=$(echo "$diff_json" | jq -r ".[$i].detail")
      changes_csv=$(echo "$diff_json" | jq -r ".[$i].changes | join(\",\")")
      i=$((i + 1))

      # Skip very common short names. Single-letter or 2-3 char identifiers
      # collide with everything in callers. Same threshold as C1's
      # IDENT_MIN_LENGTH.
      if [ "${#name}" -lt "$IDENT_MIN_LENGTH" ]; then
        continue
      fi

      # Search callers in unchanged files. Word-boundary match on the
      # name. For methods, we don't qualify by owner — the receiver is
      # rarely visible textually at the call site (e.g. `repo.findById(...)`
      # — `findById` alone is the searchable token). Owner is included
      # in the human-readable label.
      local label
      if [ -n "$owner" ]; then
        label="${owner}.${name}"
      else
        label="$name"
      fi

      local hits
      hits=$(xargs -d '\n' -a "$UNCHANGED_FILES_LIST" \
        grep -HnE "\\b${name}\\b" 2>/dev/null \
        | head -"$MAX_HITS_PER_CANDIDATE")

      if [ -n "$hits" ]; then
        echo "  ${kind} ${label}: ${detail}  [changes: ${changes_csv}]"
        # Severity: Minor for shape changes (callers may be silently broken
        # by type widening or new optional params; reviewer judgment needed).
        # Major for `removed` — a removed export with surviving callers is
        # a hard breakage.
        local sev="Minor"
        case ",$changes_csv," in
          *,removed,*) sev="Major" ;;
        esac
        echo "$hits" | while IFS=: read -r hf hl _rest; do
          _emit_finding "$sev" "$hf:$hl" "calls '$name' — signature changed (${detail})"
        done
        echo ""
        found=1
      fi
    done
  done < "$ts_changed_list"

  [ "$found" -eq 0 ] && { echo "  (no signature changes with surviving callers found)"; echo ""; }
}

detect_symbol_renames
detect_constant_changes
detect_string_literal_changes
detect_signature_changes

echo "=== End Propagation Check ==="
