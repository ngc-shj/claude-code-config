#!/bin/bash
# PreToolUse hook: block VCS history rewrites against pushed branches
# Implements R31 category (d) — VCS history rewrites — at the harness
# level. Defense-in-depth on top of existing settings.json
# `permissions.deny` rules (which catch direct invocations but miss
# `bash -c '...'` wrappers and similar).
#
# Best-effort tripwire — bypasses exist (base64-decoded eval, alternate
# shells, direct .git/ manipulation). Primary enforcement remains
# permissions.deny + reviewer obligation R31.
#
# Intentionally NOT blocked:
#   - `git push --force-with-lease` and `--force-if-includes` — these
#     are the SAFER alternatives that this hook actively recommends in
#     its override message. They only force-push when the remote state
#     is what the local clone expected, so they cannot silently overwrite
#     work pushed by another contributor in the meantime.
#   - `git reset --hard` — frequent in legitimate local workflow (squash,
#     fixup, rebase recovery). The existing settings.json
#     `Bash(git reset --hard*)` deny rule covers direct invocations, and
#     a destructive `reset` is recoverable from reflog within 90 days.
#     Including it here would produce too many false positives.

set -euo pipefail

INPUT=$(cat)

# Single jq call: emit tool_name + Unit Separator (U+001F) + command.
# US survives jq -rj as a real 0x1F byte (unlike @tsv, which escapes
# embedded TABs as literal "\t") and is virtually never present in
# real shell commands, so the field-split is unambiguous.
PARSED=$(echo "$INPUT" | jq -rj '(.tool_name // ""), "\u001f", (.tool_input.command // "")')
TOOL_NAME="${PARSED%%$'\x1f'*}"
COMMAND="${PARSED#*$'\x1f'}"

if [ "$TOOL_NAME" != "Bash" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

if [ -z "$COMMAND" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Patterns that rewrite VCS history. Substring match against the full
# command catches `bash -c '...'` wrappers too.
#
# Notes on each branch:
#   - `git push.*--force([^-a-zA-Z]|$)` — long form `--force` followed by
#     a non-flag-name char (whitespace / EOL / equals), so `--force-with-lease`
#     and `--force-if-includes` are NOT matched (next char is `-`, which is
#     in the negated set).
#   - `git push(.*[[:space:]])(-f\b|-[a-zA-Z]*f[a-zA-Z]*\b)` — single-dash
#     short flag containing `f`, anchored to whitespace before the dash so
#     the second `-` of a long flag (e.g., `--force-with-lease`) does not
#     false-positive match `-force` as a bundled short cluster. Matches
#     bare `-f` and bundled forms like `-fu` (force + set-upstream).
#   - `git filter-branch\b` — porcelain history-rewrite tool.
#   - `git filter-repo\b` — modern replacement (separate package, but the
#     verb token is identical from the hook's perspective).
DENY_REGEX='(git[[:space:]]+push[[:space:]].*--force([^-a-zA-Z]|$))|(git[[:space:]]+push(.*[[:space:]])(-f\b|-[a-zA-Z]*f[a-zA-Z]*\b))|(git[[:space:]]+filter-branch\b)|(git[[:space:]]+filter-repo\b)'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='VCS history-rewrite operation blocked (R31 category d). Force-pushes and filter-* commands can overwrite or erase commits that other contributors have based work on. Recommended alternatives: (1) `git push --force-with-lease` — only force-pushes when the remote is what your local clone expected, preventing silent overwrites of teammates'"'"' commits; (2) `git push --force-if-includes` — even stricter, requires your local commit history to include the remote tip; (3) for `filter-branch`/`filter-repo` rewriting shared history, coordinate with the team and document the rewrite reason in the PR. To override this hook locally, edit ~/.claude/settings.local.json (NOT overwritten by install.sh).'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
