#!/bin/bash
# Detect static-analysis warning suppressions added without a written
# justification.
#
# R36 (Static-analysis warning suppression as substitute for fix) calls
# out the case where reviewers paper over a lint / type-check / SAST
# warning by silencing it instead of fixing the underlying code. The
# rule's allowed escape valve is "suppression IS acceptable when
# accompanied by a written justification placed adjacent to the
# suppression comment, naming the specific upstream issue, version, or
# incompatibility". Bare suppression with no justification is the
# violation; a justified suppression is fine.
#
# Detection
#   For each `+` line in the diff (source files only):
#     1. Match a suppression marker:
#         - JS/TS:   `eslint-disable[-next-line]`, `@ts-ignore`,
#                    `@ts-expect-error`, `@ts-nocheck`
#         - Python:  `# type: ignore`, `# noqa`, `# pylint:`
#         - Java:    `@SuppressWarnings`
#         - Go:      `//nolint`
#         - Rust:    `#[allow(...)]`
#     2. Check whether the SAME line carries a justification keyword:
#         - URL (`https?://`)
#         - Issue reference (`#<number>` or `(github\.com|gitlab|jira)`)
#         - Version pin (`fixed in v?[0-9]`, `until v?[0-9]`)
#         - Reasoning verb (`because`, `due to`, `false positive`, `FP`,
#           `upstream`, `intentional`)
#     3. If no justification on the same line, emit a Major finding.
#
# Severity: Major. R36 also calls out a Critical escalation when the
# suppressed warning is in a security category (SAST injection, path
# traversal, SSRF, timing, hardcoded-secret, deserialization, weak
# cipher) — the hook surfaces all matches as Major and lets the
# reviewer pick the few that warrant Critical based on the rule
# being silenced.
#
# Out of scope
#   - Multi-line suppression where the justification is on the line
#     ABOVE / BELOW (rare; check ±1 line would be a v2 enhancement).
#   - Inline-disable comments wrapping a code block where the wrapping
#     comment carries the justification but the disable line does not.
#
# Usage: bash check-suppression.sh [base-ref]

set -u

_CSP_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CSP_TMPDIR'" EXIT

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

# Suppression markers (one big alternation). Each is anchored loosely
# enough to match wrapped-in-comment forms (`// eslint-disable-next-line`
# inside a JSDoc block, `# type: ignore[arg-type]` etc.).
SUPPRESS_RE='(eslint-disable(-next-line)?|@ts-(ignore|expect-error|nocheck)|# *type: *ignore|# *noqa|# *pylint:|@SuppressWarnings|//[[:space:]]*nolint|#\[allow\()'

# Justification heuristics — at least one must be present on the same
# line for the suppression to be considered acceptable.
JUST_RE='(https?://|github\.com|gitlab\.com|jira|#[0-9]+|fixed in|until v|because|due to|false positive|\bFP\b|upstream|intentional|workaround|TODO\([A-Za-z]+\)|see )'

SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|kts|scala|cs|fs|vb|swift|m|mm|c|h|hpp|hxx|cpp|cc|cxx|php|pl|pm|ex|exs|erl|hrl|elm|clj|cljs|cljc|edn|lua|sh|bash|zsh|fish|graphql|gql)$'
EXCLUDE_PATH_RE='^(prisma/migrations/|migrations/|db/migrations/|vendor/|node_modules/|.+\.generated\.|.+_generated\.|.+\.gen\.)'

ADDED="$_CSP_TMPDIR/added.tsv"
git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
  | awk -v src_re="${SOURCE_EXT_RE//\\/\\\\}" -v exclude_re="${EXCLUDE_PATH_RE//\\/\\\\}" '
      /^\+\+\+ b\// {
        sub(/^\+\+\+ b\//, "")
        file = $0
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
      /^\+/ {
        if ($0 ~ /^\+\+\+/) next
        if (in_source) {
          content = substr($0, 2)
          if (content != "") print file "\t" lineno "\t" content
        }
        lineno++
      }
    ' > "$ADDED"

CHANGED_COUNT=$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null | wc -l)

echo "=== Suppression-Without-Justification Check (R36) ==="
echo "Base: $BASE_REF"
echo "Changed files: $CHANGED_COUNT"
echo ""

if [ ! -s "$ADDED" ]; then
  echo "  (no source-file diff lines to inspect)"
  exit 0
fi

hits_emitted=0
echo "## Bare suppressions (no justification on the same line)"
echo ""

while IFS=$'\t' read -r file lineno content; do
  if ! [[ "$content" =~ $SUPPRESS_RE ]]; then
    continue
  fi
  marker="${BASH_REMATCH[0]}"
  if [[ "$content" =~ $JUST_RE ]]; then
    continue
  fi
  printf '  [Major] %s:%s — `%s` without justification (add URL / issue ref / version pin / "false positive" / "upstream" rationale on the same line)\n' \
    "$file" "$lineno" "$marker"
  hits_emitted=$((hits_emitted + 1))
done < "$ADDED"

[ "$hits_emitted" -eq 0 ] && echo "  (no candidates found)"
echo ""
echo "=== End Suppression Check ==="
