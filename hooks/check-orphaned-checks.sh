#!/bin/bash
# Detect authored check/gate scripts that are never wired into the
# project's authoritative enforcement gate (CI / pre-push / pre-commit).
#
# RT7 shape (b) — "authored-but-ungated detector". The passwd-sso
# supply-chain audit repeatedly found policy/security check scripts
# (`check-actions-sha-pinned.sh`, ~15 pre-pr guards) that existed but
# had zero callers in CI, so they reported PASS to humans purely by
# never executing. A check that cannot run is worse than no check —
# the project history shows the gate "exists" while it is inert.
#
# This is diff-driven: it fires only on check-like scripts that the
# current branch ADDED or MODIFIED, then asks "is this script invoked
# by the gate the project treats as authoritative?" If a PR authors a
# new guard, this nudges the author to wire it before merge.
#
# Detection
#   candidate scripts = files in `git diff --name-only base...HEAD`
#     whose basename matches the check-name regex (check|verify|guard|
#     gate|audit|validate|assert|scan|lint|enforce — extend via
#     EXTRA_CHECK_NAME_RE) and whose extension is a runnable script
#     (.sh/.bash/.mjs/.cjs/.js/.ts/.py/.rb — extend via EXTRA_CHECK_EXT_RE).
#   For each candidate, search every OTHER tracked file for its basename:
#     - 0 references anywhere          -> Major  (orphaned: no caller at all)
#     - referenced only in docs/text   -> Minor  (not wired to a gate surface)
#     - referenced in a gate surface   -> OK     (silent)
#   "Gate surface" = CI config, Makefile/Justfile/Taskfile, package.json,
#   pre-commit / husky config, or any other *.sh script (covers a check
#   invoked transitively through an aggregate like scripts/pre-pr.sh).
#   Extend gate-surface matching via EXTRA_GATE_NAME_RE.
#
# Severity: Major when the script has no caller at all; Minor when it is
# only mentioned in prose. Both are RT7(b) advisories — the reviewer
# confirms the script is meant to gate and wires it (or deletes it).
# Shapes (a) restriction-without-revert-test and (c) structurally-blind
# gate remain human-review.
#
# Usage: bash check-orphaned-checks.sh [base-ref]

set -u

_COC_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_COC_TMPDIR'" EXIT

BASE_REF="${1:-main}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

CHECK_NAME_RE='check|verify|guard|gate|audit|validate|assert|scan|lint|enforce'
[ -n "${EXTRA_CHECK_NAME_RE:-}" ] && CHECK_NAME_RE="$CHECK_NAME_RE|$EXTRA_CHECK_NAME_RE"

CHECK_EXT_RE='\.(sh|bash|mjs|cjs|js|ts|py|rb)$'
[ -n "${EXTRA_CHECK_EXT_RE:-}" ] && CHECK_EXT_RE="${CHECK_EXT_RE%\$}|$EXTRA_CHECK_EXT_RE"

# Gate surfaces — filename patterns whose presence means "wired to enforce".
# Scoped deliberately: CI config (not arbitrary YAML), build-runner manifests,
# pre-commit/husky, and aggregate runner scripts by basename (pre-pr / pre-push
# / pre-commit) so a check invoked transitively through such an aggregate still
# counts as wired — WITHOUT treating every stray *.sh / *.yaml as a gate (that
# masks a check referenced only by another dead script, or by an unrelated
# data YAML).
GATE_NAME_RE='(^|/)\.github/workflows/[^/]*\.ya?ml$|(^|/)\.gitlab-ci\.ya?ml$|(^|/)\.circleci/|(^|/)azure-pipelines[^/]*\.ya?ml$|(^|/)Makefile$|(^|/)Justfile$|(^|/)Taskfile\.ya?ml$|(^|/)package\.json$|(^|/)\.pre-commit-config\.ya?ml$|(^|/)\.husky/|(^|/)(pre-pr|pre-push|pre-commit|prepush|precommit|prepr)[^/]*\.(sh|bash)$'
[ -n "${EXTRA_GATE_NAME_RE:-}" ] && GATE_NAME_RE="$GATE_NAME_RE|$EXTRA_GATE_NAME_RE"

# Fail loud on a malformed regex (typically a bad EXTRA_* override) instead of
# silently degrading to zero candidates — a silent self-disable is the exact
# RT7 shape-(c) fail-open smell this hook warns about.
for _re in "$CHECK_NAME_RE" "$CHECK_EXT_RE" "$GATE_NAME_RE"; do
  printf '' | grep -E "$_re" >/dev/null 2>&1
  if [ "$?" -gt 1 ]; then
    echo "Error: invalid regex (check EXTRA_CHECK_NAME_RE / EXTRA_CHECK_EXT_RE / EXTRA_GATE_NAME_RE): $_re" >&2
    exit 1
  fi
done

CANDIDATES="$_COC_TMPDIR/candidates"
git diff --name-only --diff-filter=AM "$BASE_REF...HEAD" 2>/dev/null \
  | grep -iE "$CHECK_EXT_RE" \
  | while IFS= read -r f; do
      base=$(basename "$f")
      echo "$base" | grep -qiE "$CHECK_NAME_RE" && echo "$f"
    done > "$CANDIDATES"

CAND_COUNT=$(wc -l < "$CANDIDATES")

echo "=== Orphaned Check-Script Detection (RT7 shape b) ==="
echo "Base: $BASE_REF"
echo "Candidate check scripts added/modified: $CAND_COUNT"
echo ""

if [ "$CAND_COUNT" -eq 0 ]; then
  echo "  (no check-like scripts added or modified in this diff)"
  echo ""
  echo "=== End Orphaned Check-Script Detection ==="
  exit 0
fi

# All tracked files, for reference lookup.
ALL_FILES="$_COC_TMPDIR/all"
git ls-files > "$ALL_FILES"

hits_emitted=0
echo "## Authored-but-possibly-ungated check scripts"
echo ""

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")

  # Find every tracked file (other than the script itself) that mentions
  # the script's basename — its callers. Match on a filename boundary, NOT
  # a bare substring: a bare `grep -F check.sh` also matches `mycheck.sh`,
  # so a longer-named sibling would mask a shorter orphaned candidate. Escape
  # ERE metacharacters in the basename, then require a non-filename char (or
  # line edge) on both sides. `-e` / `--` keep a leading-dash basename/path
  # from being parsed as options.
  esc=$(printf '%s' "$base" | sed 's/[][(){}.^$*+?|\\]/\\&/g')
  refs="$_COC_TMPDIR/refs"
  git grep -lE -e "(^|[^A-Za-z0-9_.-])${esc}([^A-Za-z0-9_.-]|\$)" 2>/dev/null \
    | grep -vxF -- "$f" > "$refs" || true

  ref_count=$(wc -l < "$refs")

  if [ "$ref_count" -eq 0 ]; then
    printf '  [Major] %s — no caller found anywhere in the repo. An authored check that nothing invokes reports PASS by never running (RT7b). Wire it into CI / pre-push, or delete it.\n' "$f"
    hits_emitted=$((hits_emitted + 1))
    continue
  fi

  # Does any caller live on a gate surface?
  gate_hit=$(grep -iE "$GATE_NAME_RE" "$refs" | head -1 || true)
  if [ -z "$gate_hit" ]; then
    callers=$(tr '\n' ' ' < "$refs")
    printf '  [Minor] %s — referenced only in non-gate files (%s). Confirm it actually runs in the authoritative gate (CI / pre-push), not just documentation (RT7b).\n' \
      "$f" "${callers% }"
    hits_emitted=$((hits_emitted + 1))
  fi
done < "$CANDIDATES"

[ "$hits_emitted" -eq 0 ] && echo "  (every candidate is referenced from a gate surface)"
echo ""
echo "Note: a reference on a gate surface (CI config under .github/.gitlab-ci/"
echo ".circleci, Makefile/Justfile/Taskfile, package.json, pre-commit/husky, or"
echo "an aggregate pre-pr / pre-push / pre-commit script) is treated as wired,"
echo "including transitive invocation through such an aggregate. A reference"
echo "from an arbitrary script or data file is reported as Minor, not silent."
echo "RT7 shapes (a) restriction-without-revert-test and (c) structurally-blind"
echo "gate are human-review — this hook covers shape (b) only."
echo ""
echo "=== End Orphaned Check-Script Detection ==="
