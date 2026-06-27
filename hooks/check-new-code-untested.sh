#!/bin/bash
# Detect newly-added public/exported production symbols in the diff that
# arrive without any corresponding test file change in the same diff
# (RT6 — Newly added production exports without test diff).
#
# Review-history rationale (5/1-5/31 sample): repeated pattern where new
# logic shipped without a test, the omission was noticed later, and the
# fix was a follow-up /test-gen run. The cheaper catch is to surface the
# omission inside the same PR so test authoring is part of the producing
# commit instead of a later cleanup round.
#
# Detection (per language, applied to diff `+` lines in non-test source
# files):
#   - TS/JS: `export (async )?function NAME`,
#            `export (default )?(abstract )?class NAME`,
#            `export (default )?(async )?(const|let) NAME`,
#            `export default (async )?function`
#            (re-exports `export { ... } from` and `export * from`
#            excluded — they ship no new logic)
#   - Python: top-level `def NAME(` / `class NAME(`
#            (private `_name` skipped per PEP 8 convention)
#   - Go:    `func (recv) NAME(` / `func NAME(` where NAME is capitalized
#   - Swift: `public`/`open` `func`/`var`/`let`/`class`/`struct`/`enum`/
#            `actor`/`protocol NAME` (only externally-visible decls;
#            `internal` default / `private` / `fileprivate` are skipped).
#            Swift test files: `*Tests.swift` / `*Test.swift` and files
#            under `Tests/` (XCTest / Swift Testing). Generated Swift
#            (`*.generated.swift` / `*.gen.swift`) is excluded.
#            (Go's export convention), `type NAME (struct|interface)`
#   - Rust:  `pub (async )?fn NAME`, `pub (struct|trait|enum) NAME`
#
# For each non-test source file with one or more new exports:
#   - If any test file appears anywhere in the same diff, treat the test
#     concern as "addressed in this PR" (loose mode, v1) and list the
#     new exports as informational only.
#   - If no test file appears in the diff, emit a Major finding listing
#     every new export the diff added. Disposition options: (a) add tests
#     in the same PR, (b) run /test-gen and include the result, or (c)
#     record an Anti-Deferral entry in the deviation log.
#
# Test-file recognition (file path matches any of):
#   - Suffix:   .test.<ext> / .spec.<ext> / _test.<ext> / _spec.<ext>
#   - Path:     under tests/ / test/ / __tests__/ / spec/ / specs/
#   - Python:   test_<name>.py / <name>_test.py
#
# Skip conditions:
#   - Project has no test files at all (`test infrastructure: none`):
#     exit 0 with an informational message.
#   - File is excluded by path (migrations, vendor, generated, types/, .d.ts).
#   - File is a re-export-only barrel: lines matching `export { } from` or
#     `export * from` are not counted as new exports.
#   - TypeScript type-only exports (`export type`, `export interface`) are
#     excluded — they carry no runtime behavior to test.
#
# v1 limitations:
#   - Test-presence is checked diff-wide, not per-symbol. A PR that touches
#     one test for unrelated logic still satisfies the loose check. Strict
#     per-symbol mapping is v2.
#   - Multi-line declarations split across `+` lines may be missed.
#   - Java / Kotlin / C# / Ruby / PHP detection is not implemented in v1.
#   - The `.d.ts` and `types/` heuristics exclude type-shaped paths but
#     can miss type-only files named elsewhere.
#   - Directory-name match wins: a production file placed under a directory
#     named `test/` / `tests/` / `spec/` / `__tests__/` is classified as test
#     infrastructure and its exports are NOT scanned. Use
#     `EXTRA_EXCLUDE_PATH_RE` to opt specific production paths out of the
#     test-directory match if your repo uses one of these names for app code.
#   - Diff parsing assumes git's default `a/` / `b/` source/dest prefix on
#     hunk headers. Repos with `git config diff.noprefix true` or non-default
#     `diff.srcPrefix` / `diff.dstPrefix` will silently produce zero findings
#     (every file fails the `+++ b/<path>` regex and `is_source` stays 0).
#     Matches the precedent in other hooks/check-*.sh files.
#
# Severity: Major. The user can downgrade to Minor or skip via Anti-Deferral
# when the change is judged trivially correct without a test (e.g., a
# one-line accessor, a config constant export).
#
# Env knobs:
#   EXTRA_EXCLUDE_PATH_RE        — additional exclude paths
#   EXTRA_TEST_FILE_RE           — additional patterns recognized as test files
#   EXTRA_PRODUCTION_EXPORT_RE   — additional patterns recognized as new exports
#                                  (applied to diff `+` line content; project-
#                                  specific framework exports like
#                                  `app.controller.ts` decorators, etc.)
#
# Caveat for all three EXTRA_* knobs: the values are passed to awk via
# `-v name=value`, and awk's POSIX `-v` rewrites backslash escape sequences
# (`\n`, `\t`, `\\`) before assignment. A pattern containing literal
# backslashes (e.g. `\b` word boundary, `\d` digit shorthand) needs to be
# double-escaped in the shell to survive both shell quoting AND awk's
# pre-processing. Test the env var by running the hook against a known-match
# fixture before relying on it in CI / Phase 2 pre-step.
#
# Usage: bash check-new-code-untested.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref...HEAD.

set -u

_CNT_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CNT_TMPDIR'" EXIT

BASE_REF="${1:-main}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
# Empty stdout from a 0-exit `git rev-parse --show-toplevel` is extremely
# unusual but possible under bind-mount edge cases or wrapper shims;
# `cd ""` would silently no-op and the subsequent git diff would run
# against the caller's cwd instead of the verified repo root.
[ -n "$TRUSTED_ROOT" ] || { echo "Error: empty git toplevel" >&2; exit 1; }
cd "$TRUSTED_ROOT" || exit 1

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|swift)$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|\.d\.ts$|\.generated\.|_generated\.|\.gen\.|(^|/)types?/'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

TEST_FILE_RE='(^|/)([Tt]ests?|__tests__|[Ss]pecs?)/|(\.test|\.spec|_test|_spec)\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs)$|(^|/)test_[^/]+\.py$|[A-Za-z0-9_]+Tests?\.swift$'
[ -n "${EXTRA_TEST_FILE_RE:-}" ] && TEST_FILE_RE="${TEST_FILE_RE}|${EXTRA_TEST_FILE_RE}"

echo "=== New-Code-Untested Check (RT6) ==="
echo "Base: $BASE_REF"

# Skip when project has no test infrastructure at all.
TEST_FILE_COUNT=$(git ls-files | grep -cE "$TEST_FILE_RE" || true)
if [ "$TEST_FILE_COUNT" -eq 0 ]; then
  echo ""
  echo "  (no test files exist in repo — project has no test infrastructure; skipping)"
  echo ""
  echo "=== End New-Code-Untested Check ==="
  exit 0
fi

CHANGED_FILES_LIST="$_CNT_TMPDIR/changed.txt"
git diff --name-only "$BASE_REF...HEAD" > "$CHANGED_FILES_LIST"
CHANGED_COUNT=$(wc -l < "$CHANGED_FILES_LIST")
echo "Changed files: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "  (no changed files)"
  echo "=== End New-Code-Untested Check ==="
  exit 0
fi

# Count only Added/Modified test files; drop renames and deletions so a
# "strip the tests, ship new code" PR cannot satisfy the loose-mode check
# by either deleting tests outright OR by repurposing an unrelated source
# file via rename-into-tests-dir. `--diff-filter=AM` picks A (added) and
# M (modified) entries. Git represents rename-with-content-edit as a
# single `R<similarity>` entry (NOT A+D+M), so the AM filter drops every
# rename regardless of whether content also changed — this intentionally
# prevents the rename-bypass attack class. D (deleted) entries are also
# dropped for the same coverage-stripping reason. Net effect: only newly
# created or in-place-edited test files satisfy the check.
TEST_DIFF_LIST="$_CNT_TMPDIR/test-diff.txt"
git diff --name-only --diff-filter=AM "$BASE_REF...HEAD" > "$TEST_DIFF_LIST"
TEST_DIFF_COUNT=$(grep -cE "$TEST_FILE_RE" "$TEST_DIFF_LIST" || true)

RAW="$_CNT_TMPDIR/raw.tsv"
git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
  | awk -v src_re="${SOURCE_EXT_RE//\\/\\\\}" \
        -v exclude_re="${EXCLUDE_PATH_RE//\\/\\\\}" \
        -v test_re="${TEST_FILE_RE//\\/\\\\}" \
        -v extra_re="${EXTRA_PRODUCTION_EXPORT_RE:-}" '
      BEGIN { lineno = 1; is_source = 0 }
      /^\+\+\+ b\// {
        sub(/^\+\+\+ b\//, "")
        file = $0
        is_source = (file ~ src_re && file !~ exclude_re && file !~ test_re)
        next
      }
      /^\+\+\+ \/dev\/null/ { is_source = 0; next }
      /^@@/ {
        if (match($0, /\+[0-9]+/)) {
          lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
        }
        next
      }
      /^\+/ {
        if ($0 ~ /^\+\+\+/) next
        if (is_source) {
          content = substr($0, 2)
          # Exclude re-exports and type-only exports (no runtime to test).
          if (content ~ /^[[:space:]]*export[[:space:]]+\*[[:space:]]+from/) { lineno++; next }
          if (content ~ /^[[:space:]]*export[[:space:]]+\{[^}]*\}[[:space:]]+from/) { lineno++; next }
          if (content ~ /^[[:space:]]*export[[:space:]]+(type|interface)[[:space:]]/) { lineno++; next }
          kind = ""
          if (content ~ /^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+[A-Za-z_]/) kind = "ts-fn"
          else if (content ~ /^[[:space:]]*export[[:space:]]+default[[:space:]]+(async[[:space:]]+)?function/) kind = "ts-default-fn"
          else if (content ~ /^[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]+[A-Za-z_]/) kind = "ts-class"
          else if (content ~ /^[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(const|let)[[:space:]]+[A-Za-z_]/) kind = "ts-const"
          # Python `def` / `class` patterns are file-extension-guarded so
          # bare `class Foo` in a TS file (un-exported, no `export` prefix)
          # is not misclassified as a Python class. py-class also filters
          # to capital-first-letter at this stage (PEP 8 PascalCase
          # convention); the PEP 8 underscore-skip for `def` is applied
          # downstream in the bash name-extraction loop. Lowercase `class`
          # (legal but unusual) and `_Private` classes are dropped here.
          else if (file ~ /\.py$/ && content ~ /^def[[:space:]]+[a-zA-Z_]/) kind = "py-def"
          else if (file ~ /\.py$/ && content ~ /^class[[:space:]]+[A-Z]/) kind = "py-class"
          else if (file ~ /\.go$/ && content ~ /^func[[:space:]]+(\([^)]+\)[[:space:]]+)?[A-Z]/) kind = "go-func"
          else if (file ~ /\.go$/ && content ~ /^type[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]+(struct|interface)/) kind = "go-type"
          else if (file ~ /\.rs$/ && content ~ /^[[:space:]]*pub[[:space:]]+(async[[:space:]]+)?fn[[:space:]]+/) kind = "rs-fn"
          else if (file ~ /\.rs$/ && content ~ /^[[:space:]]*pub[[:space:]]+(struct|trait|enum)[[:space:]]+/) kind = "rs-ty"
          # Swift: `public`/`open` declarations. Function/type/member API
          # surface. `private`/`fileprivate`/`internal` (the default) are
          # not externally visible, so only `public`/`open` count.
          else if (file ~ /\.swift$/ && content ~ /^[[:space:]]*(public|open)[[:space:]]+((static|final|class|convenience|override|mutating|@[A-Za-z]+[[:space:]]+)[[:space:]]*)*(func|var|let)[[:space:]]+/) kind = "swift-fn"
          else if (file ~ /\.swift$/ && content ~ /^[[:space:]]*(public|open)[[:space:]]+((final|@[A-Za-z]+[[:space:]]+)[[:space:]]*)*(class|struct|enum|actor|protocol)[[:space:]]+/) kind = "swift-ty"
          else if (extra_re != "" && content ~ extra_re) kind = "extra"
          if (kind != "") {
            gsub(/\t/, " ", content)
            print file "\t" lineno "\t" kind "\t" content
          }
        }
        lineno++
      }
    ' > "$RAW"

if [ ! -s "$RAW" ]; then
  echo "  (no new production exports detected)"
  echo ""
  echo "=== End New-Code-Untested Check ==="
  exit 0
fi

# Extract symbol names from the raw lines.
EXPORTS="$_CNT_TMPDIR/exports.tsv"
> "$EXPORTS"
while IFS=$'\t' read -r file lineno kind content; do
  name=""
  case "$kind" in
    ts-fn)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p')
      ;;
    ts-default-fn)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*export[[:space:]]+default[[:space:]]+(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p')
      [ -z "$name" ] && name="default"
      ;;
    ts-class)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p')
      ;;
    ts-const)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(const|let)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4/p')
      ;;
    py-def)
      name=$(printf '%s\n' "$content" | sed -nE 's/^def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/p')
      # PEP 8: leading underscore = private; skip
      [ "${name:0:1}" = "_" ] && continue
      ;;
    py-class)
      name=$(printf '%s\n' "$content" | sed -nE 's/^class[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\1/p')
      ;;
    go-func)
      name=$(printf '%s\n' "$content" | sed -nE 's/^func[[:space:]]+(\([^)]+\)[[:space:]]+)?([A-Z][A-Za-z0-9_]*).*/\2/p')
      ;;
    go-type)
      name=$(printf '%s\n' "$content" | sed -nE 's/^type[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\1/p')
      ;;
    rs-fn)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*pub[[:space:]]+(async[[:space:]]+)?fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p')
      ;;
    rs-ty)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*pub[[:space:]]+(struct|trait|enum)[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\2/p')
      ;;
    swift-fn)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*(public|open)[[:space:]]+.*(func|var|let)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p')
      ;;
    swift-ty)
      name=$(printf '%s\n' "$content" | sed -nE 's/^[[:space:]]*(public|open)[[:space:]]+.*(class|struct|enum|actor|protocol)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p')
      ;;
    extra)
      name="match"
      ;;
  esac
  [ -z "$name" ] && name="?"
  printf '%s\t%s\t%s\t%s\n' "$file" "$lineno" "$kind" "$name" >> "$EXPORTS"
done < "$RAW"

if [ ! -s "$EXPORTS" ]; then
  echo "  (no new production exports detected)"
  echo ""
  echo "=== End New-Code-Untested Check ==="
  exit 0
fi

TOTAL=$(wc -l < "$EXPORTS")

if [ "$TEST_DIFF_COUNT" -gt 0 ]; then
  echo "## New exports added (test file diff present — $TEST_DIFF_COUNT test file(s) modified, $TOTAL new export(s))"
  echo ""
  echo "  Tests touched in same diff — verify per-symbol coverage manually:"
  echo ""
  sort -t $'\t' -k1,1 -k2,2n "$EXPORTS" | while IFS=$'\t' read -r file lineno kind name; do
    printf '  %s:%s — new %s `%s`\n' "$file" "$lineno" "$kind" "$name"
  done
  echo ""
  echo "=== End New-Code-Untested Check ==="
  exit 0
fi

echo "## New production exports without test diff (RT6)"
echo ""
echo "  No test file was modified in this diff. $TOTAL new public/exported"
echo "  symbol(s) ship without any test diff in the same PR:"
echo ""

sort -t $'\t' -k1,1 -k2,2n "$EXPORTS" | while IFS=$'\t' read -r file lineno kind name; do
  printf '  [Major] %s:%s — new %s `%s` without test diff\n' "$file" "$lineno" "$kind" "$name"
done

echo ""
echo "  Disposition options:"
echo "    (a) Add tests in this PR (preferred)."
echo "    (b) Run /test-gen on the new symbol(s) and include the generated tests."
echo "    (c) Record an Anti-Deferral entry in the deviation log with"
echo "        Worst-case / Likelihood / Cost-to-fix lines (see"
echo "        common-rules.md 'Anti-Deferral Rules')."
echo ""
echo "=== End New-Code-Untested Check ==="
