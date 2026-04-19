#!/usr/bin/env bash
# marv-tmpdir.sh — per-run temp directory lifecycle for multi-agent-review.
#
# Centralizes the mktemp / cleanup pattern used by the skill's Phase 1 Step 1-5,
# Phase 3 Step 3-2b, and Phase 3 Step 3-9. Keeps SKILL.md snippets short and
# gives one place to audit tmpdir handling (shellcheck, TMPDIR policy, etc.).
#
# Usage:
#   MARV_DIR=$(bash ~/.claude/hooks/marv-tmpdir.sh create)     # stdout=path; exit 1 on failure
#   bash ~/.claude/hooks/marv-tmpdir.sh cleanup "$MARV_DIR"     # no-op if path empty or non-marv
#
# Confidentiality: mktemp -d creates the directory with mode 0700 owned by the
# invoking user, so no umask change is needed — other local users cannot
# traverse into it regardless of interior file modes.

set -euo pipefail

cmd_create() {
  local dir
  if ! dir=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX" 2>/dev/null); then
    echo "marv-tmpdir: mktemp -d failed under ${TMPDIR:-/tmp}" >&2
    exit 1
  fi
  printf '%s\n' "$dir"
}

# Refuse to cleanup paths that were not produced by cmd_create. The safety
# check compares the argument against the expected marv-* prefix under
# TMPDIR (or /tmp) — catches an accidentally-corrupted $MARV_DIR value
# before `rm -rf` runs.
cmd_cleanup() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    # Silent no-op on empty — matches the [ -n "${MARV_DIR:-}" ] && rm -rf
    # pattern that this helper replaces.
    return 0
  fi
  local expected_prefix="${TMPDIR:-/tmp}/marv-"
  if [ "${dir#"$expected_prefix"}" = "$dir" ]; then
    echo "marv-tmpdir: refusing to cleanup path outside ${expected_prefix}*: $dir" >&2
    exit 1
  fi
  rm -rf "$dir"
}

case "${1:-}" in
  create)
    shift
    cmd_create "$@"
    ;;
  cleanup)
    shift
    cmd_cleanup "$@"
    ;;
  help|"")
    echo "Usage: bash marv-tmpdir.sh <command> [args]" >&2
    echo "Commands:" >&2
    echo "  create              Create a per-run marv-* directory, print path to stdout" >&2
    echo "  cleanup <path>      Remove a marv-* directory (safety: rejects non-marv paths)" >&2
    exit 1
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run 'bash marv-tmpdir.sh help' for available commands." >&2
    exit 1
    ;;
esac
