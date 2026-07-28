#!/bin/bash
# Detect guard test files that exercise only the deny side.
#
# RT10 (Guard tested only on its deny side) — a test file whose assertions
# are entirely deny-shaped pins the guard's strictness and nothing else.
# A later tightening, including an accidental one, stays invisible, and the
# guard's dominant failure mode goes unmeasured: over-blocking. An
# over-blocking guard gets disabled, granted an escape hatch, or routed
# around, and the protection leaves with it.
#
# Detection (file-level, not block-level — RT10's claim is about a guard's
# test *suite*, so the analysis unit is the file):
#   Fire Major when a changed test file has
#     (1) >=1 deny-shaped line whose number is in the diff '+' set, AND
#     (2) zero allow-shaped lines file-wide, across all three grammars.
#
# Three grammars, polarity-scored. Scoring the token without the operator
# that surrounds it is the mistake this hook exists to catch in others:
#   Jest/Vitest  deny  .toBe|toEqual|toStrictEqual(403|429|503), rejects.,
#                      .toThrow(
#                allow any other line carrying expect( AND a matcher
#   bats status  deny  [ "$status" -ne 0 ], [ "$status" -eq <non-zero> ]
#                allow [ "$status" -eq 0 ]
#   hook decision deny "decision":"block"      allow "decision":"approve"
#                 (either spacing; `!=` flips the polarity of both)
#
# The Jest/Vitest allow side is deliberately GENERAL rather than an
# enumeration of success spellings. Measured over 1022 real test files: an
# enumerated status-shaped allow vocabulary fires on 130 of them; the
# general form fires on 1, and that one is a genuine deny-only suite. RT10
# claims "its tests exercise ONLY rejected inputs", so a file whose
# assertions are overwhelmingly non-deny must not fire.
#
# The allow line must carry a MATCHER, not merely `expect(`. Prettier wraps
# a long assertion so the opener sits alone:
#     await expect(
#       provider.send({ ... }),
#     ).rejects.toThrow("...")
# Counting the bare opener as allow lets every multi-line deny assertion
# cancel itself, and the fire condition can never be met. Measured: with the
# matcher requirement the corpus still yields exactly 1 fire, and the
# Prettier-wrapped form of that file still fires.
#
# `assert_success` / `assert_failure` are deliberately absent: measured zero
# occurrences in this repo, and bats-assert is not a dependency here. An
# alternative nobody can red-prove is worse than none.
#
# Control class: DETECTION ONLY. Findings inform a review round; nothing is
# blocked. Exit is 0 whether or not findings are emitted; non-zero only for
# setup errors. Known limits, none of which this hook closes:
#   - "boundary-adjacent" (RT10 clause 1) and axis-combination coverage
#     (clause 2) are not mechanically checkable at all.
#   - File-level granularity: a file holding one covered guard and one
#     deny-only guard stays silent.
#   - Grammars beyond the three above (pytest, Go, RSpec) are not detected.
#   - Allow-shaped lines are NOT diff-scoped, so deleting a file's only
#     allow assertion produces no fire — the canonical RT10 regression.
#   - A `//` inside a string literal is over-stripped by comment removal,
#     which can delete an allow match (measured: 1 file in 1022, 0 induced
#     fires); the JS lexer is not consulted.
#   - This hook cannot usefully classify its own test file: a detection-only
#     script's suite asserts `[ "$status" -eq 0 ]`, so it scores allow>0.
#
# Untrusted input: filenames come from `git diff` over a repository under
# review. Two consequences, both handled below and neither optional:
#   - Every filename operand is passed as "./$f". An unguarded `-rf.bats`
#     is parsed by sed as `-r` plus `-f .bats`, so sed reads its script from
#     the repository under review and GNU sed's `e` command executes it.
#     The sibling check-vacuous-denial.sh survives this only because its
#     expression `s://.*$::` contains `/` and cannot be a filename — an
#     accident of delimiter choice, not a control, and one that does not
#     transfer to a `#`-comment expression.
#   - The changed-file set is read NUL-framed (`--name-status -z`), so a path
#     containing a newline, quote, backslash or tab is carried through as
#     itself. `--name-only` would C-quote such a path, and a consumer that
#     assumes a raw path then skips the file silently — a deny-only suite in
#     a file named `auth<newline>.bats` would never be reported.
#
# Failed commands are never read as "nothing found". The base ref is peeled
# to a commit (a tree-ish passes plain `--verify` and makes every later diff
# exit 128), and both the file-list diff and each per-file diff have their
# own exit status checked. Reporting a clean run from a command that did not
# run is the fail-open shape this hook exists to name in other people's code.
#
# Usage: bash check-deny-only-guard.sh [base-ref]
#   base-ref defaults to 'main'. The comparison is merge-base(base-ref, HEAD)
#   against the WORKING TREE — so commits landing on the base branch after
#   the branch point are not misreported as this branch's changes, and staged
#   or unstaged test files are analyzed. A commit-only diff would make the
#   hook a no-op in the phase-2 pre-step and in test-gen's post-generation
#   block, which both run before anything is committed.
#
# Renames are followed (`--diff-filter=AMR`, new path analyzed): moving a
# paired suite while dropping its allow assertions is the cheapest way to
# turn it deny-only, and an `AM`-only filter drops it from the set entirely.
#
# Env knobs (appended to the built-in vocabularies):
#   EXTRA_DENY_ASSERTION_RE, EXTRA_ALLOW_ASSERTION_RE, EXTRA_EXCLUDE_PATH_RE
# These are consumed by awk via ENVIRON, never via `awk -v`: -v performs
# escape processing on the value first, so `\[ *"\$status"…` silently
# becomes a bracket expression matching any one of those characters. A
# widened allow pattern makes the fire condition unreachable and the hook
# reports "Total findings: 0" forever. Validation probes the value in the
# engine that consumes it, for the same reason.
#
# Output: human-scannable findings, one row per file. Exit 0 always;
# exit 1 on setup error (not a git repo, invalid base-ref, malformed EXTRA_*).

set -u

_DOG_TMPDIR=$(mktemp -d)
# The handler quotes at trap-execution time, not at registration time. A
# string-expanded `trap "rm -rf '$dir'" EXIT` embeds the directory's bytes
# as shell code, so a $TMPDIR containing a single quote runs a command at
# exit. The path is attacker-influenced wherever TMPDIR is.
_dog_cleanup() { rm -rf -- "$_DOG_TMPDIR"; }
trap _dog_cleanup EXIT

BASE_REF="${1:-main}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT" || exit 1

# The base-ref check is an argument-injection boundary, not only an RT7
# shape (c) concern, and it must precede the first `git diff`: an
# option-shaped argument reaching `git diff` is an arbitrary-file-write
# primitive (`git diff "--output=/tmp/x...HEAD"` exits 0 and creates that
# file). The EXIT STATUS is the gate — several option shapes exit 1 while
# still writing to stdout, so a `[ -n "$(...)" ]` form would not hold.
# --end-of-options closes the class structurally rather than by convention.
#
# It also peels to a commit. `--verify` alone accepts any object, so a tree-ish such
# as `HEAD^{tree}` passes and every later `git diff` then exits 128 — which,
# unchecked, reads as "no findings" and exit 0. Rejecting non-commits here
# is the first of two guards; the second is checking each diff's status.
if ! git rev-parse --quiet --verify --end-of-options "$BASE_REF^{commit}" >/dev/null 2>&1; then
  echo "Error: '$BASE_REF' is not a valid commit-ish" >&2
  exit 1
fi

# The comparison point is the merge base, so commits landing on the base
# branch after the branch point are not misreported as this branch's
# changes. Diffing the merge base against the WORKING TREE rather than
# against HEAD is deliberate: staged and unstaged test files must be
# analyzed too. The phase-2 pre-step and the test-gen post-generation block
# both run before anything is committed, and a commit-only diff would make
# the hook a no-op at exactly the moment it is asked to run.
MERGE_BASE=$(git merge-base "$BASE_REF" HEAD 2>/dev/null) || MERGE_BASE=""
if [ -z "$MERGE_BASE" ]; then
  echo "Error: no merge base between '$BASE_REF' and HEAD" >&2
  exit 1
fi

# --- vocabularies -----------------------------------------------------------
#
# Leading word boundary for awk: `\y` is a gawk extension and `\b` is a
# backspace in POSIX ERE, so neither works in the BSD awk that ships with
# macOS. Spell the boundary out (same convention as check-vacuous-denial.sh).
AWK_WORD_START='(^|[^A-Za-z0-9_])'

JS_DENY='[.](toBe|toEqual|toStrictEqual)[(][[:space:]]*(403|429|503)[[:space:]]*[)]|rejects[.]|[.]toThrow[(]'
# An allow line must carry a matcher, not merely an `expect(` opener.
JS_MATCHER='[)][.][A-Za-z]|[.]to[A-Z]|[.]resolves[.]|[.]rejects[.]|[.]not[.]'
JS_EXPECT='expect[(]'
# `.not.` inverts a deny token into an assertion that the thing does NOT
# reject. `.resolves.` is NOT a negation — it is promise unwrapping, and
# `expect(getStatus()).resolves.toBe(403)` is a deny assertion. Measured: 97
# `.resolves.` uses in the reference corpus, none carrying a deny token, so
# treating it as a negation would have been latent rather than visible.
JS_NEGATE='[.]not[.]'

BATS_DENY='\[[[:space:]]*"\$status"[[:space:]]*-ne[[:space:]]*0[[:space:]]*\]|\[[[:space:]]*"\$status"[[:space:]]*-eq[[:space:]]*[1-9][0-9]*[[:space:]]*\]'
BATS_ALLOW='\[[[:space:]]*"\$status"[[:space:]]*-eq[[:space:]]*0[[:space:]]*\]'

DECISION_BLOCK='"decision"[[:space:]]*:[[:space:]]*"block"'
DECISION_APPROVE='"decision"[[:space:]]*:[[:space:]]*"approve"'
# `!=` flips BOTH decision tokens: `!= *"decision": "approve"*` asserts the
# input was not approved (a deny assertion), and `!= *"decision":"block"*`
# asserts it was not blocked (an allow assertion).
DECISION_NEGATE='!='

TEST_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs)$'
TEST_PATH_RE='(__tests__|test|tests|spec|specs)/|[.](test|spec)[.][a-z]+$|_test[.][a-z]+$|_spec[.][a-z]+$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

# --- EXTRA_* validation, in the engine that consumes the value --------------
#
# A `grep -E` probe is not sufficient: it accepts values that awk rejects
# (`\[unterminated` is grep-valid and awk-fatal) and cannot see values whose
# meaning awk changes. Probing through ENVIRON — the same channel the scan
# uses — is what makes the check and the use agree.
_validate_extra() {
  local name="$1" value="$2"
  [ -n "$value" ] || return 0
  export _DOG_PROBE="$value"
  if ! awk 'BEGIN { if ("" ~ ENVIRON["_DOG_PROBE"]) exit 0; exit 0 }' </dev/null >/dev/null 2>&1; then
    echo "Error: $name is not a valid regular expression for awk: $value" >&2
    unset _DOG_PROBE
    return 1
  fi
  unset _DOG_PROBE
  return 0
}

_validate_extra EXTRA_DENY_ASSERTION_RE "${EXTRA_DENY_ASSERTION_RE:-}" || exit 1
_validate_extra EXTRA_ALLOW_ASSERTION_RE "${EXTRA_ALLOW_ASSERTION_RE:-}" || exit 1
_validate_extra EXTRA_EXCLUDE_PATH_RE "${EXTRA_EXCLUDE_PATH_RE:-}" || exit 1

# --- changed-file set -------------------------------------------------------
#
# --diff-filter=AM keeps deleted and renamed paths — which no longer exist —
# out of the read loop, matching every sibling detector.
RAW="$_DOG_TMPDIR/raw.z"
# Unpiped, so the status tested is git's own (R44). A failed diff must never
# reach the "no findings" path: reporting a clean run from a command that
# did not run is the fail-open direction this whole hook exists to name.
# `R` is in the filter because a rename is how an existing paired suite is
# most cheaply turned into a deny-only one — dropping the allow assertions
# in the same commit that moves the file. With `AM` only, git's rename
# detection removed the file from the set entirely.
if ! git diff --name-status -z --diff-filter=AMR "$MERGE_BASE" > "$RAW" 2>/dev/null; then
  echo "Error: 'git diff' against $MERGE_BASE failed; refusing to report a clean run" >&2
  exit 1
fi

# NUL-framed end to end. `--name-status -z` emits raw paths rather than the
# C-quoted form `--name-only` produces, so a filename containing a newline,
# quote, backslash or tab is carried through correctly instead of having to
# be refused. Rename and copy records carry two paths; the second is the one
# that exists now and the one to analyze.
KEPT="$_DOG_TMPDIR/kept.z"
: > "$KEPT"
while IFS= read -r -d '' status_field; do
  IFS= read -r -d '' path1 || break
  case "$status_field" in
    R*|C*) IFS= read -r -d '' path2 || break; candidate="$path2" ;;
    *)     candidate="$path1" ;;
  esac
  case "$candidate" in
    *.bats) ;;
    *) printf '%s' "$candidate" | grep -qE "$TEST_EXT_RE" || continue ;;
  esac
  printf '%s' "$candidate" | grep -qE "$EXCLUDE_PATH_RE" && continue
  printf '%s\0' "$candidate" >> "$KEPT"
done < "$RAW"

# Untracked files never appear in any `git diff`, and a freshly generated
# test file is untracked until someone stages it. test-gen's contract is to
# run this hook immediately after generation, so an untracked-only view of
# the world would make it a no-op exactly there. --exclude-standard honours
# .gitignore, so build output and vendored trees stay out.
UNTRACKED="$_DOG_TMPDIR/untracked.z"
if ! git ls-files --others --exclude-standard -z > "$UNTRACKED" 2>/dev/null; then
  echo "Error: 'git ls-files --others' failed; refusing to report a clean run" >&2
  exit 1
fi
while IFS= read -r -d '' candidate; do
  case "$candidate" in
    *.bats) ;;
    *) printf '%s' "$candidate" | grep -qE "$TEST_EXT_RE" || continue ;;
  esac
  printf '%s' "$candidate" | grep -qE "$EXCLUDE_PATH_RE" && continue
  printf '%s\0' "$candidate" >> "$KEPT"
done < "$UNTRACKED"

kept_count=$(tr -cd '\0' < "$KEPT" | wc -c | tr -d ' ')
echo "=== Deny-Only Guard Check (RT10) ==="
echo "Base: $BASE_REF (merge base $MERGE_BASE, compared against the working tree)"
echo "Test files in diff: $kept_count"
echo ""

findings=0

while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  # `./` guards option position at every operand. `--` is not a candidate:
  # gawk treats it as a filename after the program text, and it has no
  # bearing on awk's operand var-assignment parsing (`FS=x.bats`) either.
  [ -f "./$f" ] || continue
  # The guard normalizes how the operand is parsed, not what it resolves to.
  # A tracked symlink can point outside the repository under review.
  [ -L "./$f" ] && continue

  case "$f" in
    *.bats) flavor=bats ;;
    *)
      printf '%s\n' "$f" | grep -qE "$TEST_PATH_RE" || continue
      flavor=js
      ;;
  esac

  added="$_DOG_TMPDIR/added.txt"
  rawdiff="$_DOG_TMPDIR/file.diff"
  if git ls-files --error-unmatch -- "./$f" >/dev/null 2>&1; then
    tracked=1
  else
    # Untracked: the whole file is new, so every line counts as added.
    tracked=0
    awk '{ print NR }' "./$f" > "$added"
  fi
  if [ "$tracked" -eq 1 ] && ! git diff "$MERGE_BASE" --unified=0 -- "./$f" > "$rawdiff" 2>/dev/null; then
    echo "  [Major] $f — 'git diff' failed for this file, so its added-line set is unknown; not analyzed. A failed diff is not evidence of no findings."
    findings=$((findings + 1))
    continue
  fi
  if [ "$tracked" -eq 1 ]; then
    awk '
        /^@@/ { if (match($0, /\+[0-9]+/)) lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
        /^\+\+\+/ { next }
        /^\+/ { print lineno; lineno++ }
      ' "$rawdiff" > "$added"
  fi

  export _DOG_JS_DENY="$JS_DENY" _DOG_JS_MATCHER="$JS_MATCHER" \
         _DOG_JS_EXPECT="$JS_EXPECT" _DOG_JS_NEGATE="$JS_NEGATE" \
         _DOG_BATS_DENY="$BATS_DENY" _DOG_BATS_ALLOW="$BATS_ALLOW" \
         _DOG_DEC_BLOCK="$DECISION_BLOCK" _DOG_DEC_APPROVE="$DECISION_APPROVE" \
         _DOG_DEC_NEGATE="$DECISION_NEGATE" \
         _DOG_EXTRA_DENY="${EXTRA_DENY_ASSERTION_RE:-}" \
         _DOG_EXTRA_ALLOW="${EXTRA_ALLOW_ASSERTION_RE:-}"

  result=$(awk -v flavor="$flavor" -v added_file="$added" -v wstart="$AWK_WORD_START" '
    BEGIN {
      while ((getline ln < added_file) > 0) added[ln + 0] = 1
      close(added_file)
      js_deny    = ENVIRON["_DOG_JS_DENY"];    js_matcher = ENVIRON["_DOG_JS_MATCHER"]
      js_expect  = ENVIRON["_DOG_JS_EXPECT"];  js_negate  = ENVIRON["_DOG_JS_NEGATE"]
      bats_deny  = ENVIRON["_DOG_BATS_DENY"];  bats_allow = ENVIRON["_DOG_BATS_ALLOW"]
      dec_block  = ENVIRON["_DOG_DEC_BLOCK"];  dec_appr   = ENVIRON["_DOG_DEC_APPROVE"]
      dec_neg    = ENVIRON["_DOG_DEC_NEGATE"]
      x_deny     = ENVIRON["_DOG_EXTRA_DENY"]; x_allow    = ENVIRON["_DOG_EXTRA_ALLOW"]
      deny = 0; allow = 0; first_deny = 0
    }
    {
      line = $0
      # Comment stripping. A `//` inside a string literal is over-stripped;
      # the JS lexer is not consulted and that limit is declared, not hidden.
      if (flavor == "js") sub(/\/\/.*$/, "", line)
      else                sub(/#.*$/, "", line)
      if (line ~ /^[ \t]*$/) next

      is_deny = 0; is_allow = 0

      if (flavor == "js") {
        if (line ~ js_deny) {
          if (line ~ js_negate) is_allow = 1
          else                  is_deny = 1
        } else if (line ~ js_expect && line ~ js_matcher) {
          is_allow = 1
        }
      } else {
        if (line ~ bats_deny)  is_deny = 1
        if (line ~ bats_allow) is_allow = 1
        if (line ~ dec_block)  { if (line ~ dec_neg) is_allow = 1; else is_deny = 1 }
        if (line ~ dec_appr)   { if (line ~ dec_neg) is_deny = 1;  else is_allow = 1 }
      }

      if (x_deny  != "" && line ~ x_deny)  is_deny = 1
      if (x_allow != "" && line ~ x_allow) is_allow = 1

      # An allow reading always wins over a deny reading on the same line:
      # the file-level question is whether ANY allow-shaped assertion exists.
      if (is_allow) { allow++; next }
      if (is_deny) {
        deny++
        if (NR in added && first_deny == 0) first_deny = NR
      }
    }
    END { printf "%d %d %d\n", deny, allow, first_deny }
  ' "./$f")

  set -- $result
  d="$1"; a="$2"; ln="$3"

  if [ "$d" -gt 0 ] && [ "$a" -eq 0 ] && [ "$ln" -gt 0 ]; then
    echo "  [Major] $f:$ln — $d deny-shaped assertion(s), 0 allow-shaped assertions in the file; the guard's over-block direction is untested. Add the boundary-adjacent allow case: the nearest legitimate input that must still pass (RT10; escalate to Critical when a false deny would block an operational recovery, deployment, or incident-response path)."
    findings=$((findings + 1))
  fi
done < "$KEPT"

if [ "$findings" -eq 0 ]; then
  echo "  (no deny-only guard files found)"
fi
echo ""
echo "Total findings: $findings"
echo ""
echo "=== End Deny-Only Guard Check ==="
