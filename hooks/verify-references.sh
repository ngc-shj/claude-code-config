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
#   --- Summary: total=3, ok=1, issues=2 ---
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

INPUT=$(cat)
if [ -z "$INPUT" ]; then
  echo "=== Reference Verification ==="
  echo "--- Summary: total=0, ok=0, issues=0 ---"
  exit 0
fi

# Extract path:line refs.
#   Path must contain at least one '/' OR end in a recognizable file extension.
#   Line is a single number or a range (e.g., 42-51); only the start line is verified.
# Grep returns a stream of raw matches; we dedupe and sort afterward.
REFS=$(printf '%s' "$INPUT" \
  | grep -oE '([A-Za-z0-9_.][A-Za-z0-9_./\-]*[A-Za-z0-9_]):[0-9]+(-[0-9]+)?' \
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
  # Heuristic: require a '/' OR a recognized file extension.
  if [[ "$path" != */* ]] && [[ ! "$path" =~ \.(ts|tsx|js|jsx|py|go|rs|sh|bash|md|json|yml|yaml|toml|rb|java|kt|c|h|cpp|hpp|cs|php|sql|bats)$ ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))
  full="$ROOT/$path"

  if [ ! -f "$full" ]; then
    OUTPUT="${OUTPUT}MISSING      ${ref}
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  file_lines=$(wc -l < "$full" 2>/dev/null | tr -d ' ')
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
