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

# Symlink containment guards (defends against attacker-controlled symlinks
# pointing outside the project tree). Two layers:
#  1. If WORKFLOW_DIR itself is a symlink, refuse — a symlinked directory
#     could resolve to anywhere on disk (e.g., /etc/, $HOME) and cause the
#     extractor to read sensitive files. Subsequent Phase 2-4 `eval` would
#     then execute attacker-supplied commands.
#  2. For each matched file, refuse if it is a symlink. Same reasoning at
#     file granularity. Workflow files in real projects are regular files
#     committed to the repo; rejecting symlinks does not affect legitimate
#     usage.
# We additionally resolve $WORKFLOW_DIR to its absolute path and require that
# every processed file's resolved path stays under it. This catches the case
# where a workflow file is itself a regular file but contains an `include:`
# reference (we do not currently follow includes, but the guard is cheap and
# future-proof).
if [ -L "$WORKFLOW_DIR" ]; then
  echo "extract-ci-checks: $WORKFLOW_DIR is a symlink — refusing to traverse" >&2
  exit 1
fi

# Resolve WORKFLOW_DIR to absolute, with trailing slash for prefix comparison.
# realpath with -e fails (non-zero exit) if the path does not exist; -d falls
# back to dirname resolution. Both are POSIX-portable enough for Linux/macOS.
WORKFLOW_DIR_ABS=$(cd "$WORKFLOW_DIR" 2>/dev/null && pwd -P) || {
  echo "extract-ci-checks: could not resolve $WORKFLOW_DIR to an absolute path" >&2
  exit 1
}
WORKFLOW_DIR_ABS="${WORKFLOW_DIR_ABS%/}/"

# Buffer extracted commands to a temp file. We cannot pipe `done | sort -u`
# because that puts the for loop in a subshell and discards the
# `multiline_files` array updates the loop performs. Bash subshell semantics
# silently dropped the multi-line warning in an earlier version of this
# script — the temp file pattern is intentional, not lazy.
output_tmp=$(mktemp -t extract-ci-checks.XXXXXX)
trap 'rm -f "$output_tmp"' EXIT

multiline_files=()

for f in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$f" ] || continue

  # Layer 2: reject symlinked files. -L returns true even if the target is
  # a regular file — that is exactly the case we are blocking.
  if [ -L "$f" ]; then
    echo "extract-ci-checks: $f is a symlink — skipping" >&2
    continue
  fi

  # Containment check: resolved path must stay under WORKFLOW_DIR_ABS.
  # Belt-and-suspenders alongside the -L check; catches edge cases like
  # bind mounts or any future code that accepts user-supplied paths.
  f_abs=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P)/$(basename "$f")
  case "$f_abs" in
    "$WORKFLOW_DIR_ABS"*) ;;
    *)
      echo "extract-ci-checks: $f resolves outside $WORKFLOW_DIR — skipping" >&2
      continue
      ;;
  esac

  # Detect multi-line run: blocks (run: | or run: >). Match both YAML forms:
  #   - run: |          (list-item form)
  #     run: |          (mapping form)
  # Record the file for the warning summary; do not attempt to parse contents.
  if grep -qE '^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*[|>]' "$f"; then
    multiline_files+=("$f")
  fi

  # Single-line `run: <cmd>`. Match both list-item (`- run: cmd`) and mapping
  # (`run: cmd`) forms. Strip the leading marker + `run:` + surrounding
  # quotes, then filter to lines matching the verification keyword set.
  grep -hE '^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]+[^|>]' "$f" \
    | sed -E 's/^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]+//' \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'$/\1/" \
    | grep -E "$VERIFY_PATTERN" >> "$output_tmp" || true
done

sort -u "$output_tmp"

if [ "${#multiline_files[@]}" -gt 0 ]; then
  {
    echo "extract-ci-checks: workflow files with multi-line run: blocks (review manually):"
    for f in "${multiline_files[@]}"; do echo "  $f"; done
  } >&2
fi

exit 0
