#!/bin/bash
# Detect race-style tests that assert cardinality without guarding both
# outcome branches actually occurred — vacuous-pass risk.
#
# RT4 (Race-test vacuous-pass guard) — when a test asserts "no double
# success" via a cardinality check (`expect(bothSucceeded).toBe(0)`)
# but does NOT also assert that both success and failure branches each
# occurred at least once, a setup misconfiguration that short-circuits
# every iteration (RLS denies all rows, lock never contended, contested
# resource never exists) leaves the cardinality assertion vacuously
# satisfied — the race-condition bug ships green.
#
# Required pattern (illustrative — adapts to the project's assertion
# library):
#   expect(successes + failures).toBe(N)         (cardinality)
#   expect(successes).toBeGreaterThan(0)         (race window opened)
#   expect(failures).toBeGreaterThan(0)          (contention occurred)
#
# Detection
#   Per-test block (Jest/Vitest `it(...)` / `test(...)` for v1) inside
#   each changed test file:
#     1. Block contains a concurrency primitive
#        (`Promise.all` / `allSettled` / `race` / `any`).
#     2. Block contains a cardinality assertion of the "zero collisions"
#        form: `.toBe(0)` / `.toEqual(0)` / `.toStrictEqual(0)`.
#     3. Block does NOT contain a lower-bound guard:
#        `.toBeGreaterThan(<N>)` / `.toBeGreaterThanOrEqual(<N>)`,
#        `.not.toBe(0)` / `.not.toEqual(0)`, `.toBeTruthy()`.
#   When (1) AND (2) AND NOT (3): emit Critical, citing the cardinality
#   line(s) that fall on diff `+` lines (newly added / newly modified).
#
# Severity
#   - Critical. A green test that does not distinguish "race correctly
#     serialized" from "race never happened" is materially worse than
#     no test — the reviewer trusts the green and ships the bug.
#
# Out of scope (v1)
#   - Test frameworks beyond Jest / Vitest (`it` / `test` blocks).
#     Python `pytest`, Go `t.Run`, Ruby RSpec are not detected.
#   - Cardinality values other than 0 (e.g. `expect(winners).toBe(1)`).
#     The "exactly N winners" pattern is RT4-relevant but precision drops
#     when allowing arbitrary integers; v1 covers the canonical zero-
#     collision shape.
#   - `describe(...)` blocks themselves (only `it`/`test` are tracked
#     as candidate blocks; nested `it` inside `describe` is detected).
#
# Block-boundary detection
#   `it(` / `test(` block starts on a line matching
#     \b(it|test)([.](only|skip|each|todo|concurrent))?[[:space:]]*\(
#   The block ends when the parens originally opened by `it(` close.
#   Paren counting strips strings and line comments first to avoid
#   miscounts. Brace nesting inside the arrow callback does not affect
#   the paren-based termination.
#
# Usage: bash check-race-vacuous-guard.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   EXTRA_CONCURRENCY_RE — additional concurrency primitive patterns
#                          (project-specific helpers, e.g. `runConcurrent[(]`)
#   EXTRA_CARDINALITY_RE — additional cardinality assertion patterns
#                          (project-specific custom matchers)
#   EXTRA_GUARD_RE — additional lower-bound guard patterns
#   EXTRA_EXCLUDE_PATH_RE — additional paths to drop from analysis
#   BLOCK_LINE_CAP (default 200) — max lines per test block
#
# Output: human-scannable findings, one row per cardinality violation.
# Exit 0 always.

set -u

_RTG_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_RTG_TMPDIR'" EXIT

BASE_REF="${1:-main}"
BLOCK_LINE_CAP="${BLOCK_LINE_CAP:-200}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

# Concurrency primitive patterns (v1: JS/TS focus). When a test block
# contains any of these, treat as race-style.
CONCURRENCY_RE='Promise[.](all|allSettled|race|any)\b|\bPromise[.]all\b'
[ -n "${EXTRA_CONCURRENCY_RE:-}" ] && CONCURRENCY_RE="${CONCURRENCY_RE}|${EXTRA_CONCURRENCY_RE}"
CONCURRENCY_RE="${CONCURRENCY_RE//\\b/\\\\y}"
CONCURRENCY_RE="${CONCURRENCY_RE//\\./[.]}"
CONCURRENCY_RE="${CONCURRENCY_RE//\\(/[(]}"

# Cardinality assertion: equality to zero (the canonical "no collisions"
# / "no double-success" / "no duplicate" pattern). Other integer values
# are RT4-relevant in principle but admit too many FPs at the line level.
CARDINALITY_RE='[.](toBe|toEqual|toStrictEqual)[(][[:space:]]*0[[:space:]]*[)]'
[ -n "${EXTRA_CARDINALITY_RE:-}" ] && CARDINALITY_RE="${CARDINALITY_RE}|${EXTRA_CARDINALITY_RE}"
CARDINALITY_RE="${CARDINALITY_RE//\\b/\\\\y}"
CARDINALITY_RE="${CARDINALITY_RE//\\./[.]}"
CARDINALITY_RE="${CARDINALITY_RE//\\(/[(]}"

# Lower-bound guard patterns. Either:
#   - `.toBeGreaterThan(N)` / `.toBeGreaterThanOrEqual(N)` for any N
#   - `.not.toBe(0)` / `.not.toEqual(0)` (negation of zero)
#   - `.toBeTruthy()` (weaker but accepted)
GUARD_RE='[.](toBeGreaterThan|toBeGreaterThanOrEqual)[(][[:space:]]*[0-9]+|[.]not[.](toBe|toEqual|toStrictEqual)[(][[:space:]]*0[[:space:]]*[)]|[.]toBeTruthy[(][[:space:]]*[)]'
[ -n "${EXTRA_GUARD_RE:-}" ] && GUARD_RE="${GUARD_RE}|${EXTRA_GUARD_RE}"
GUARD_RE="${GUARD_RE//\\b/\\\\y}"
GUARD_RE="${GUARD_RE//\\./[.]}"
GUARD_RE="${GUARD_RE//\\(/[(]}"

# Test-file scope. Only test paths are inventoried; we want to find
# exactly the kind of files this rule applies to.
TEST_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs)$'
TEST_PATH_RE='(__tests__|test|tests|spec|specs)/|[.](test|spec)[.][a-z]+$|_test[.][a-z]+$|_spec[.][a-z]+$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

CHANGED_TEST_FILES="$_RTG_TMPDIR/changed_tests.txt"
git diff --name-only "$BASE_REF...HEAD" 2>/dev/null \
  | grep -E "$TEST_EXT_RE" \
  | grep -E "$TEST_PATH_RE" \
  | grep -vE "$EXCLUDE_PATH_RE" \
  > "$CHANGED_TEST_FILES"

CHANGED_COUNT=$(wc -l < "$CHANGED_TEST_FILES")

echo "=== Race-Test Vacuous-Guard Check (RT4) ==="
echo "Base: $BASE_REF"
echo "Test files in diff: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "  (no test files in diff; nothing to check)"
  echo "=== End Race-Test Vacuous-Guard Check ==="
  exit 0
fi

# Per-file added-line set: cardinality assertions outside diff `+` are
# advisory at best; we report only those genuinely added/modified.
NEW_LINES_DIR="$_RTG_TMPDIR/added"
mkdir -p "$NEW_LINES_DIR"

_safe_fname() { echo "$1" | tr '/' '_' | tr -c 'A-Za-z0-9_.-' '_'; }

findings_total=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ ! -f "$f" ] && continue

  enc=$(_safe_fname "$f")
  added_file="$NEW_LINES_DIR/$enc.added"
  git diff "$BASE_REF...HEAD" --unified=0 -- "$f" 2>/dev/null \
    | awk '
        /^@@/ {
          if (match($0, /\+[0-9]+/)) {
            lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
          }
          next
        }
        /^\+\+\+/ { next }
        /^\+/ { print lineno; lineno++ }
      ' > "$added_file"

  # Per-file awk: track `it(`/`test(` blocks via paren balance, classify
  # each block (race + cardinality + guard), emit findings.
  flagged=$(awk -v file="$f" \
                -v conc_re="$CONCURRENCY_RE" \
                -v card_re="$CARDINALITY_RE" \
                -v guard_re="$GUARD_RE" \
                -v block_cap="$BLOCK_LINE_CAP" \
                -v added_file="$added_file" '
    BEGIN {
      while ((getline ln < added_file) > 0) added[ln+0] = 1
      close(added_file)
      in_block = 0
      block_paren = 0
    }

    function strip(s,    out) {
      out = s
      sub(/\/\/.*$/, "", out)
      gsub(/"[^"\\]*(\\.[^"\\]*)*"/, "\"\"", out)
      gsub(/'\''[^'\''\\]*(\\.[^'\''\\]*)*'\''/, "''", out)
      gsub(/`[^`]*`/, "``", out)
      return out
    }

    # Count parens in s starting at position pos. Returns net (+open, -close).
    function paren_delta(s, pos,    i, c, n_open, n_close, len) {
      n_open = 0; n_close = 0
      len = length(s)
      for (i = pos; i <= len; i++) {
        c = substr(s, i, 1)
        if (c == "(") n_open++
        else if (c == ")") n_close++
      }
      return n_open - n_close
    }

    function process_block(    n, lines, i, line, line_s, has_conc, card_lines, has_guard, ncard, k) {
      has_conc = 0; has_guard = 0; ncard = 0
      n = split(block_body, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        # Strip comments and string literals before scanning so
        # `// Promise.all not used` does not trigger concurrency match
        # and a string like "expect.toBe(0)" in a description does not
        # trigger cardinality match.
        line_s = strip(line)
        if (!has_conc && line_s ~ conc_re) has_conc = 1
        if (!has_guard && line_s ~ guard_re) has_guard = 1
        if (line_s ~ card_re) {
          # Track which absolute line number this corresponds to.
          card_lines[++ncard] = block_start + i - 1
        }
      }
      if (has_conc && ncard > 0 && !has_guard) {
        for (k = 1; k <= ncard; k++) {
          ln = card_lines[k]
          if (ln in added) {
            printf "  [Critical] %s:%d — race-style block at %s:%d asserts zero-cardinality without lower-bound guard; verify both branches occurred (RT4)\n", \
                   file, ln, file, block_start
          }
        }
      }
    }

    {
      raw = $0
      lineno = NR
      stripped = strip(raw)

      if (!in_block) {
        # Detect `it(` or `test(` block start at this line.
        if (match(stripped, /\<(it|test)([.](only|skip|each|todo|concurrent))?[[:space:]]*\(/)) {
          in_block = 1
          block_start = lineno
          block_body = raw
          block_lines = 1
          # Count parens from the matched `(` onwards.
          block_paren = paren_delta(stripped, RSTART)
          if (block_paren <= 0) {
            process_block()
            in_block = 0
          }
          next
        }
      } else {
        block_body = block_body "\n" raw
        block_lines++
        block_paren += paren_delta(stripped, 1)
        if (block_paren <= 0 || block_lines > block_cap) {
          process_block()
          in_block = 0
        }
      }
    }

    END {
      if (in_block) process_block()
    }
  ' "$f")

  if [ -n "$flagged" ]; then
    echo "$flagged"
    n=$(printf '%s\n' "$flagged" | grep -c '^  \[Critical\]' || true)
    findings_total=$((findings_total + n))
  fi
done < "$CHANGED_TEST_FILES"

if [ "$findings_total" -eq 0 ]; then
  echo "  (no race-style blocks with missing guards found)"
fi
echo ""
echo "Total findings: $findings_total"
echo ""
echo "=== End Race-Test Vacuous-Guard Check ==="
