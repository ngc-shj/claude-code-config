#!/bin/bash
# verify-references: Check file:line references in sub-agent output.
# Usage: echo "$output" | bash ~/.claude/hooks/verify-references.sh [--root <dir>]
#
# Reads text on stdin, extracts path:line and path:line-line references,
# and reports which ones exist and which are stale. Zero Claude tokens.
#
# Output format (to stdout):
#   === Reference Verification ===
#   OK           path/to/file.ts:42
#   MISSING      path/to/gone.ts:10
#   OUT-OF-RANGE path/to/file.ts:9999 (file has 150 lines)
#   OUT-OF-ROOT  ../outside.txt:1
#   --- Summary: total=4, ok=1, issues=3 ---
#
# Security model:
#   stdin is UNTRUSTED (originates from sub-agent / LLM output, potentially
#   shaped by prompt-injection or hallucination). Path components are
#   canonicalized via realpath and must resolve inside ROOT — absolute paths
#   outside ROOT, `..`-traversal, and symlink escape are all rejected as
#   OUT-OF-ROOT. Without this containment the helper becomes an
#   existence/size oracle for any user-readable file.
#
# Exit 0 always (non-blocking helper).

set -euo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--root <dir>]  (reads stdin)" >&2
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Canonicalize ROOT once. Missing ROOT is a configuration error, not a
# recoverable condition for a single ref — fail closed.
ROOT_ABS=$(realpath -e -- "$ROOT" 2>/dev/null) || {
  echo "Error: ROOT '$ROOT' does not exist or is not accessible" >&2
  exit 1
}

INPUT=$(cat)
if [ -z "$INPUT" ]; then
  echo "=== Reference Verification ==="
  echo "--- Summary: total=0, ok=0, issues=0 ---"
  exit 0
fi

# Extract path:line refs.
#   Path may optionally begin with '/' (absolute). Line is a single number or
#   range (e.g., 42-51); only the start line is verified.
# Grep returns a stream of raw matches; we dedupe and sort afterward.
REFS=$(printf '%s' "$INPUT" \
  | grep -oE '(/?[A-Za-z0-9_.][A-Za-z0-9_./\-]*[A-Za-z0-9_]):[0-9]+(-[0-9]+)?' \
  | sort -u)

if [ -z "$REFS" ]; then
  echo "=== Reference Verification ==="
  echo "--- Summary: total=0, ok=0, issues=0 ---"
  exit 0
fi

TOTAL=0
OK_COUNT=0
ISSUE_COUNT=0
OUTPUT=""

while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  path="${ref%%:*}"
  linespec="${ref##*:}"
  start_line="${linespec%%-*}"

  # Skip refs whose path looks non-filesystem (e.g., 'http', 'localhost', bare words).
  # Heuristic: require a '/' (absolute or nested) OR a recognized file extension.
  if [[ "$path" != */* ]] && [[ ! "$path" =~ \.(ts|tsx|js|jsx|py|go|rs|sh|bash|md|json|yml|yaml|toml|rb|java|kt|c|h|cpp|hpp|cs|php|sql|bats)$ ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Resolve candidate path: absolute stays absolute; relative joins ROOT_ABS.
  # realpath -m resolves even when the final component does not exist, so we
  # can still classify MISSING while enforcing containment.
  if [[ "$path" = /* ]]; then
    candidate="$path"
  else
    candidate="$ROOT_ABS/$path"
  fi

  full_abs=$(realpath -m -- "$candidate" 2>/dev/null) || full_abs=""
  if [ -z "$full_abs" ]; then
    OUTPUT="${OUTPUT}MISSING      ${ref}
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  # Containment: canonical path must sit under ROOT_ABS. Catches directory
  # traversal (../), absolute-path escapes, and symlink redirection in a
  # single check.
  case "$full_abs/" in
    "$ROOT_ABS/"*) : ;;
    *)
      OUTPUT="${OUTPUT}OUT-OF-ROOT  ${ref}
"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
      continue
      ;;
  esac

  if [ ! -f "$full_abs" ]; then
    OUTPUT="${OUTPUT}MISSING      ${ref}
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  file_lines=$(wc -l < "$full_abs" 2>/dev/null | tr -d ' ')
  file_lines="${file_lines:-0}"

  if [ "$start_line" -gt "$file_lines" ]; then
    OUTPUT="${OUTPUT}OUT-OF-RANGE ${ref} (file has ${file_lines} lines)
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  else
    OUTPUT="${OUTPUT}OK           ${ref}
"
    OK_COUNT=$((OK_COUNT + 1))
  fi
done <<< "$REFS"

echo "=== Reference Verification ==="
printf '%s' "$OUTPUT"
echo "--- Summary: total=${TOTAL}, ok=${OK_COUNT}, issues=${ISSUE_COUNT} ---"
