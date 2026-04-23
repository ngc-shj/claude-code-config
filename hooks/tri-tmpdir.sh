#!/usr/bin/env bash
# tri-tmpdir.sh — per-run temp directory lifecycle for triangulate.
#
# Centralizes the mktemp / cleanup pattern used by the skill's Phase 1 Step 1-5,
# Phase 3 Step 3-2b, and Phase 3 Step 3-9. Keeps SKILL.md snippets short and
# gives one place to audit tmpdir handling (shellcheck, TMPDIR policy, etc.).
#
# Usage:
#   TRI_DIR=$(bash ~/.claude/hooks/tri-tmpdir.sh create)     # stdout=path; exit 1 on failure
#   bash ~/.claude/hooks/tri-tmpdir.sh cleanup "$TRI_DIR"     # no-op if path empty or non-marv
#
# Confidentiality: mktemp -d creates the directory with mode 0700 owned by the
# invoking user, so no umask change is needed — other local users cannot
# traverse into it regardless of interior file modes.

set -euo pipefail

cmd_create() {
  local dir
  if ! dir=$(mktemp -d "${TMPDIR:-/tmp}/tri-XXXXXX" 2>/dev/null); then
    echo "tri-tmpdir: mktemp -d failed under ${TMPDIR:-/tmp}" >&2
    exit 1
  fi
  printf '%s\n' "$dir"
}

# Refuse to cleanup paths that were not produced by cmd_create. Safety
# layers, in order:
#   1. Empty path → silent no-op (matches the previous [ -n ... ] && rm -rf
#      behavior that this helper replaces).
#   2. Path contains a `..` component → reject, even if the prefix matches.
#      Purely-lexical prefix checks are bypassable: `/tmp/tri-foo/../../etc`
#      matches the prefix but `rm -rf` would resolve the `..` and delete
#      `/etc`. Rejecting any path that contains `..` is the simplest
#      guarantee that the later prefix check is not subverted.
#   3. Symlinks → reject. `rm -rf` does not follow symlinks on the top-level
#      argument (it removes the symlink itself, not the target), but
#      rejecting upfront removes an ambiguity in the safety contract.
#   4. Path does not match the expected `${TMPDIR:-/tmp}/tri-` prefix →
#      reject. Final prefix check is meaningful only after (2) closes the
#      `..` bypass.
cmd_cleanup() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    return 0
  fi
  case "$dir" in
    *..*)
      echo "tri-tmpdir: refusing to cleanup path containing '..': $dir" >&2
      exit 1
      ;;
  esac
  if [ -L "$dir" ]; then
    echo "tri-tmpdir: refusing to cleanup symlink: $dir" >&2
    exit 1
  fi
  local expected_prefix="${TMPDIR:-/tmp}/tri-"
  if [ "${dir#"$expected_prefix"}" = "$dir" ]; then
    echo "tri-tmpdir: refusing to cleanup path outside ${expected_prefix}*: $dir" >&2
    exit 1
  fi
  # TOCTOU defense-in-depth: re-check symlink immediately before rm. On a
  # sticky /tmp, only the directory owner can unlink the target and swap in
  # a symlink — making this a self-attack on single-user hosts — but a
  # second check costs nothing and closes the window entirely.
  if [ -L "$dir" ]; then
    echo "tri-tmpdir: refusing to cleanup symlink (detected pre-rm): $dir" >&2
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
    echo "Usage: bash tri-tmpdir.sh <command> [args]" >&2
    echo "Commands:" >&2
    echo "  create              Create a per-run tri-* directory, print path to stdout" >&2
    echo "  cleanup <path>      Remove a tri-* directory (safety: rejects non-marv paths)" >&2
    exit 1
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run 'bash tri-tmpdir.sh help' for available commands." >&2
    exit 1
    ;;
esac
