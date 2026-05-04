#!/bin/bash
# Extract lint/check/verify commands from GitHub Actions workflow files
# Output: one shell command per line on stdout, suitable for piping to a runner
# Non-blocking: exits 0 with empty stdout when no workflows are present
# Usage: bash ~/.claude/hooks/extract-ci-checks.sh
#
# Scope:
# - Reads .github/workflows/*.yml and *.yaml
# - Extracts `run: <single-line>` entries whose text matches a lint/check
#   keyword (lint, check, verify, typecheck, tsc, eslint, prettier, stylelint)
# - Deduplicates with sort -u
#
# Limitations:
# - Multi-line `run: |` and `run: >` blocks are NOT extracted; a warning is
#   emitted to stderr listing the affected files so the orchestrator can
#   review them manually.
# - GitHub Actions only. Adapt or replace for GitLab CI / CircleCI / Jenkins.
# - Cannot resolve reusable-workflow `uses:` references; if a project's gates
#   live in a called workflow, the call site shows up as `uses:` with no
#   `run:` to extract. Run the called workflow's extractor separately.

set -uo pipefail

WORKFLOW_DIR=".github/workflows"
VERIFY_PATTERN='\b(lint|check|verify|typecheck|tsc|eslint|prettier|stylelint)\b'

if [ ! -d "$WORKFLOW_DIR" ]; then
  echo "extract-ci-checks: no $WORKFLOW_DIR directory; nothing to extract" >&2
  exit 0
fi

multiline_files=()

for f in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$f" ] || continue

  # Detect multi-line run: blocks (run: | or run: >). Record the file for the
  # warning summary; do not attempt to parse the block contents.
  if grep -qE '^[[:space:]]*run:[[:space:]]*[|>]' "$f"; then
    multiline_files+=("$f")
  fi

  # Single-line `run: <cmd>`. Strip the leading `run:` and surrounding quotes.
  # Filter to lines matching the verification keyword set.
  grep -hE '^[[:space:]]*run:[[:space:]]+[^|>]' "$f" \
    | sed -E 's/^[[:space:]]*run:[[:space:]]+//' \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'$/\1/" \
    | grep -E "$VERIFY_PATTERN" || true
done | sort -u

if [ "${#multiline_files[@]}" -gt 0 ]; then
  {
    echo "extract-ci-checks: workflow files with multi-line run: blocks (review manually):"
    for f in "${multiline_files[@]}"; do echo "  $f"; done
  } >&2
fi

exit 0
