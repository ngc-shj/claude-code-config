#!/bin/bash
# Detect vacuous denial-path tests: a test asserts a gate's reject status
# (403 / 429 / 503) but never asserts the guarded mutation did NOT run.
#
# RT8 (Vacuous denial-path test guard) — when a test exercises a gate's
# DENIAL path (authorization/step-up reject 403, rate-limit reject 429,
# fail-closed 503, permission-denied) and asserts only the HTTP status,
# the test is vacuously green: remove the gate and let the mutation
# proceed, and the test still passes because nothing checks the side
# effect. It is a false-green on exactly the security control the test
# advertises.
#
# Required pattern (illustrative — adapts to the project's assertion
# library):
#   expect(res.status).toBe(403)                 (denial status — existing)
#   expect(deleteMock).not.toHaveBeenCalled()    (the guard — the side-effect's absence)
#                                                  or .toHaveBeenCalledTimes(0)
#
# Detection
#   Per-test block (Jest/Vitest `it(...)` / `test(...)` for v1) inside
#   each changed test file:
#     1. Block asserts a denial status: `.toBe(403|429|503)` /
#        `.toEqual(403|429|503)` / `.toStrictEqual(403|429|503)`.
#     2. The FILE declares a mutation-verb spy: a `*Mock` / `*Spy`
#        identifier or a `.<verb>: vi.fn()` / `.<verb>(` shape whose verb
#        is a mutation verb (create/update/delete/deleteMany/upsert/
#        insert/save/remove/revoke/...). The spy is almost always set up
#        at module / `vi.mock` factory / `beforeEach` scope, so this is a
#        file-wide check — a truly vacuous block asserts the status and
#        never references the spy AT ALL, which is exactly why a
#        block-scoped spy check could never catch it. The file-wide spy
#        proves there IS a guarded write the denial block could assert on.
#     3. Block does NOT contain a negative call assertion:
#        `.not.toHaveBeenCalled(...)` / `.toHaveBeenCalledTimes(0)`.
#   When (1) AND (2 file-wide) AND NOT (3): emit, citing the denial-status
#   line(s) that fall on diff `+` lines (newly added / newly modified).
#
# Severity
#   - Major by default. Escalate to Critical (manual) when the gate is a
#     security control — authz/authn, rate-limit, step-up re-auth,
#     fail-closed. The hook cannot classify the gate's role, so it emits
#     Major and prints the escalation note (same posture as
#     check-suppression.sh).
#
# Companion to check-race-vacuous-guard.sh (RT4): RT4 = race cardinality
# needs both branches to occur; RT8 = a single non-race denial test must
# observe the mutation's absence.
#
# Out of scope (v1)
#   - Test frameworks beyond Jest / Vitest (`it` / `test` blocks).
#     Python pytest, Go t.Run, Ruby RSpec are not detected.
#   - Denial signalled by a thrown error / rejected promise rather than a
#     status code (e.g. `await expect(fn()).rejects.toThrow()`) — the
#     status-code shape is the canonical v1 surface.
#   - `describe(...)` blocks themselves (only `it`/`test` are candidate
#     blocks; nested `it` inside `describe` is detected).
#
# Block-boundary detection
#   `it(` / `test(` block starts on a line matching
#     \b(it|test)([.](only|skip|each|todo|concurrent))?[[:space:]]*\(
#   The block ends when the parens originally opened by `it(` close.
#   Paren counting strips strings and line comments first to avoid
#   miscounts.
#
# Usage: bash check-vacuous-denial.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   EXTRA_DENIAL_STATUS_RE — additional denial-status patterns (e.g. a
#                            project that signals fail-closed with 423)
#   EXTRA_MUTATION_VERB_RE — additional mutation-verb spy patterns
#                            (project-specific write helpers)
#   EXTRA_NEGATIVE_RE — additional negative-assertion patterns
#   EXTRA_EXCLUDE_PATH_RE — additional paths to drop from analysis
#   BLOCK_LINE_CAP (default 200) — max lines per test block
#
# Output: human-scannable findings, one row per denial-path violation.
# Exit 0 always.

set -u

_VD_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_VD_TMPDIR'" EXIT

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

# Denial-status assertion: equality to a reject status code. 403 (authz /
# step-up), 429 (rate limit), 503 (fail-closed) are the canonical gate
# rejects. 401 is intentionally excluded — an unauthenticated 401 rarely
# pairs with a guarded mutation worth asserting against, and including it
# inflates false positives on plain auth tests.
DENIAL_STATUS_RE='[.](toBe|toEqual|toStrictEqual)[(][[:space:]]*(403|429|503)[[:space:]]*[)]'
[ -n "${EXTRA_DENIAL_STATUS_RE:-}" ] && DENIAL_STATUS_RE="${DENIAL_STATUS_RE}|${EXTRA_DENIAL_STATUS_RE}"
DENIAL_STATUS_RE="${DENIAL_STATUS_RE//\\b/\\\\y}"
DENIAL_STATUS_RE="${DENIAL_STATUS_RE//\\./[.]}"
DENIAL_STATUS_RE="${DENIAL_STATUS_RE//\\(/[(]}"

# Mutation-verb spy: a spy/mock identifier or a `.verb(` call whose verb
# is a write. Two shapes:
#   (a) an identifier ending in Mock/Spy whose head is a mutation verb
#       (e.g. deleteMock, createManySpy, revokeSpy)
#   (b) a `.verb(` method call (e.g. .deleteMany(, .upsert(, .revoke()
# Either shape means there IS a guarded write the test could assert on.
# Mutation verbs, in BOTH cases so the verb can sit anywhere inside a
# camelCase spy identifier (`mockBridgeCodeCreate` — verb is a suffix —
# is the common real-world convention, not just `createMock`).
MUTATION_VERB='([Cc]reate|[Uu]pdate|[Dd]elete|[Uu]psert|[Ii]nsert|[Ss]ave|[Rr]emove|[Rr]evoke|[Dd]estroy|[Pp]urge|[Ww]ipe|[Gg]rant|[Dd]eactivate)'
# Four spy shapes (file-wide existence proof that there IS a guarded write):
#   (a) `.verb(` method call                e.g. `.deleteMany(`
#   (b) a mock/spy identifier CONTAINING a mutation verb anywhere —
#       `mock*` prefix or `*Mock`/`*Spy` suffix, verb at any position
#       e.g. `mockBridgeCodeCreate`, `deleteEntrySpy`, `createMock`
#   (c) `verb: vi.fn()` / `verb: jest.fn()` mock-factory property
# This regex is used ONLY in `grep -E` (file-wide pre-pass), never in awk,
# so it keeps grep-flavor `\b` word boundaries — do NOT apply the awk
# `\b`->`\y` rewrite the other patterns below use.
MUTATION_VERB_RE="[.]${MUTATION_VERB}[A-Za-z0-9]*[(]|\\bmock[A-Za-z0-9]*${MUTATION_VERB}[A-Za-z0-9]*\\b|\\b[A-Za-z0-9]*${MUTATION_VERB}[A-Za-z0-9]*(Mock|Spy)\\b|\\b${MUTATION_VERB}[A-Za-z0-9]*[[:space:]]*:[[:space:]]*(vi|jest)\\.fn"
[ -n "${EXTRA_MUTATION_VERB_RE:-}" ] && MUTATION_VERB_RE="${MUTATION_VERB_RE}|${EXTRA_MUTATION_VERB_RE}"

# Handler-verb discriminator (block-scoped, suppresses read-only denials).
# A denied GET/HEAD/OPTIONS never mutates, so a denial block that invokes
# ONLY a read-verb handler has nothing to assert absent — suppress it even
# though the file declares a write spy (the spy belongs to a sibling
# mutating handler tested elsewhere in the same file). When the block
# invokes a mutating handler (POST/PUT/PATCH/DELETE) — or no recognizable
# handler call at all — it stays a candidate.
READ_HANDLER_RE='\b(GET|HEAD|OPTIONS)[(]'
READ_HANDLER_RE="${READ_HANDLER_RE//\\b/\\\\y}"
READ_HANDLER_RE="${READ_HANDLER_RE//\\(/[(]}"
MUTATING_HANDLER_RE='\b(POST|PUT|PATCH|DELETE)[(]'
MUTATING_HANDLER_RE="${MUTATING_HANDLER_RE//\\b/\\\\y}"
MUTATING_HANDLER_RE="${MUTATING_HANDLER_RE//\\(/[(]}"

# Negative call assertion (the guard we want present): the mutation spy
# was asserted NOT to have run.
NEGATIVE_RE='[.]not[.]toHaveBeenCalled[(]|[.]toHaveBeenCalledTimes[(][[:space:]]*0[[:space:]]*[)]|[.]not[.]toHaveBeenCalledWith[(]'
[ -n "${EXTRA_NEGATIVE_RE:-}" ] && NEGATIVE_RE="${NEGATIVE_RE}|${EXTRA_NEGATIVE_RE}"
NEGATIVE_RE="${NEGATIVE_RE//\\b/\\\\y}"
NEGATIVE_RE="${NEGATIVE_RE//\\./[.]}"
NEGATIVE_RE="${NEGATIVE_RE//\\(/[(]}"

# Test-file scope.
TEST_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs)$'
TEST_PATH_RE='(__tests__|test|tests|spec|specs)/|[.](test|spec)[.][a-z]+$|_test[.][a-z]+$|_spec[.][a-z]+$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

CHANGED_TEST_FILES="$_VD_TMPDIR/changed_tests.txt"
git diff --name-only "$BASE_REF...HEAD" 2>/dev/null \
  | grep -E "$TEST_EXT_RE" \
  | grep -E "$TEST_PATH_RE" \
  | grep -vE "$EXCLUDE_PATH_RE" \
  > "$CHANGED_TEST_FILES"

CHANGED_COUNT=$(wc -l < "$CHANGED_TEST_FILES")

echo "=== Vacuous Denial-Path Check (RT8) ==="
echo "Base: $BASE_REF"
echo "Test files in diff: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "  (no test files in diff; nothing to check)"
  echo "=== End Vacuous Denial-Path Check ==="
  exit 0
fi

NEW_LINES_DIR="$_VD_TMPDIR/added"
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

  # File-wide check for a mutation spy (trigger 2). Spies are declared at
  # module / vi.mock-factory / beforeEach scope, so this must be file-wide,
  # not block-scoped — a vacuous denial block never references the spy.
  # Strip line comments first so a commented-out spy does not count.
  if sed 's://.*$::' "$f" | grep -Eq "$MUTATION_VERB_RE"; then
    file_has_mut=1
  else
    file_has_mut=0
  fi

  flagged=$(awk -v file="$f" \
                -v denial_re="$DENIAL_STATUS_RE" \
                -v neg_re="$NEGATIVE_RE" \
                -v read_re="$READ_HANDLER_RE" \
                -v mut_handler_re="$MUTATING_HANDLER_RE" \
                -v file_has_mut="$file_has_mut" \
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

    function process_block(    n, lines, i, line_s, has_neg, has_read, has_mut_handler, denial_lines, nden, k) {
      has_neg = 0; has_read = 0; has_mut_handler = 0; nden = 0
      n = split(block_body, lines, "\n")
      for (i = 1; i <= n; i++) {
        line_s = strip(lines[i])
        if (!has_neg && line_s ~ neg_re) has_neg = 1
        if (!has_read && line_s ~ read_re) has_read = 1
        if (!has_mut_handler && line_s ~ mut_handler_re) has_mut_handler = 1
        if (line_s ~ denial_re) denial_lines[++nden] = block_start + i - 1
      }
      # Suppress read-only denial blocks: a denied GET/HEAD/OPTIONS cannot
      # mutate, so there is nothing to assert absent.
      if (has_read && !has_mut_handler) return
      if (nden > 0 && file_has_mut == 1 && !has_neg) {
        for (k = 1; k <= nden; k++) {
          ln = denial_lines[k]
          if (ln in added) {
            printf "  [Major] %s:%d — denial-path block at %s:%d asserts reject status; the file declares a mutation spy but this block has no `.not.toHaveBeenCalled()` / `.toHaveBeenCalledTimes(0)`; assert the guarded write did NOT run (RT8; escalate to Critical if the gate is authz/authn/rate-limit/step-up/fail-closed)\n", \
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
        if (match(stripped, /\<(it|test)([.](only|skip|each|todo|concurrent))?[[:space:]]*\(/)) {
          in_block = 1
          block_start = lineno
          block_body = raw
          block_lines = 1
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
    n=$(printf '%s\n' "$flagged" | grep -c '^  \[Major\]' || true)
    findings_total=$((findings_total + n))
  fi
done < "$CHANGED_TEST_FILES"

if [ "$findings_total" -eq 0 ]; then
  echo "  (no vacuous denial-path blocks found)"
fi
echo ""
echo "Total findings: $findings_total"
echo ""
echo "=== End Vacuous Denial-Path Check ==="
