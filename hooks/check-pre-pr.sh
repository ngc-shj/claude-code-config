#!/bin/bash
# PreToolUse hook: gate `git push` / `gh pr create` on the project's
# pre-PR script.
#
# Rationale: the /triangulate skill runs lint / test / build explicitly,
# but a project's `scripts/pre-pr.sh` often bundles repo-specific gates
# beyond that (forbidden-pattern greps, count checks, license-header
# validation, etc.). When the skill skips this script, CI-only failures
# leak through to push round and cost an iteration.
#
# Behavior:
#   - Fires only on Bash commands matching `git push` or `gh pr create`.
#   - Locates the project root via $CLAUDE_PROJECT_DIR (set by the harness),
#     falling back to `git rev-parse --show-toplevel` only when the env
#     var is unset. Falling back to git-cwd alone is a fail-open hole
#     when the user has `cd`'d into a non-repo directory before push.
#   - When `<repo>/scripts/pre-pr.sh` exists and is executable, runs
#     `bash scripts/pre-pr.sh` from the repo root.
#   - Pass: approve.
#   - Fail: block with the captured output (tail-limited) in the reason.
#   - No script present: approve (no-op for projects without the convention).
#
# Escape hatches:
#   - Set `SKIP_PRE_PR_GATE=1` in the env to bypass for a single session.
#     A stderr breadcrumb fires on every bypass so the operator notices an
#     accidentally-persistent export (e.g., in ~/.bashrc).
#   - Disable globally by removing the hook entry from settings.json.
#
# Intentionally NOT gated:
#   - `git push --force` / `-f` family — already denied earlier by
#     block-vcs-history-rewrite.sh + permissions.deny.
#   - `git push --force-with-lease` / `--force-if-includes` — these still
#     push and DO trigger this gate (the safer-alternative semantics do
#     not exempt them from pre-PR validation).
#
# Timeout: registered at 1800s in settings.json. The hook itself has no
# internal timeout — pre-pr.sh aggregate scripts routinely run for minutes
# (full lint + test + build + repo-specific gates). 1800s is sized for
# the worst-case full run on a slow machine; a hung script (interactive
# prompt slipped past </dev/null, network stall) will still wait the full
# budget. If your project's pre-pr.sh is short, this is overhead-free.
#
# Secrets warning: combined stdout+stderr of pre-pr.sh is captured into
# the block reason that appears in the Claude Code conversation
# transcript. Authors of scripts/pre-pr.sh MUST avoid `set -x`, `env`
# dumps, and echoing secret-bearing tokens on failure paths — the
# transcript may be shared via /bug reports or session exports.

set -euo pipefail

INPUT=$(cat)

# Fail-open on malformed JSON: a hook that crashes (non-zero exit, no
# stdout) would otherwise block all Bash tool calls with a generic
# harness error. Approving on parse failure trades correctness for
# availability — the hook is a safety net, not the primary gate.
if ! PARSED=$(echo "$INPUT" | jq -rj '(.tool_name // ""), "", (.tool_input.command // "")' 2>/dev/null); then
  echo '{"decision": "approve"}'
  exit 0
fi
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

if [ "${SKIP_PRE_PR_GATE:-0}" = "1" ]; then
  printf 'check-pre-pr: SKIP_PRE_PR_GATE=1 — bypassing scripts/pre-pr.sh gate\n' >&2
  echo '{"decision": "approve"}'
  exit 0
fi

# Detect push / PR-create verbs. Substring match against the full command
# catches `bash -c '...'` wrappers and `rtk git push ...` rewrites too.
# Boundaries use [^a-zA-Z0-9_-] (NOT just whitespace) so common shell
# separators like `;`, `|`, `&`, `(`, `)`, `<`, `>` are recognized as
# verb-edge — `git push;echo done` and `(git push)` are caught.
# Trailing-word-char exclusion preserves the `git pushd` false-positive
# avoidance (next char `d` is a word char, no match).
PUSH_REGEX='(^|[^a-zA-Z0-9_-])git[[:space:]]+push($|[^a-zA-Z0-9_-])|(^|[^a-zA-Z0-9_-])gh[[:space:]]+pr[[:space:]]+create($|[^a-zA-Z0-9_-])'

if ! echo "$COMMAND" | grep -qE "$PUSH_REGEX"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Prefer $CLAUDE_PROJECT_DIR (set by the harness to the session's project
# root) over git-cwd discovery. The git-rev-parse fallback alone would
# fail open when the user has `cd`'d into a non-repo directory before
# push — exactly the scenario where the gate matters most.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
if [ -z "$REPO_ROOT" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

SCRIPT="$REPO_ROOT/scripts/pre-pr.sh"
# `-x` (exists AND executable) matches the contract documented in the
# /triangulate skill phase docs. Projects shipping pre-pr.sh without an
# exec bit must `chmod +x` it; this is a one-time fix and avoids the
# "looks present but silently skipped" ambiguity of `-r`.
if [ ! -x "$SCRIPT" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Run the script with stdin closed to prevent interactive prompts from
# hanging the hook. Capture combined stdout+stderr for the block reason.
OUTPUT_FILE=$(mktemp -t pre-pr-gate.XXXXXX)
trap 'rm -f "$OUTPUT_FILE"' EXIT

if (cd "$REPO_ROOT" && bash "$SCRIPT" </dev/null) >"$OUTPUT_FILE" 2>&1; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Tail-limit the captured output so the block reason stays readable.
TAIL_BYTES=4000
SIZE=$(wc -c <"$OUTPUT_FILE")
if [ "$SIZE" -gt "$TAIL_BYTES" ]; then
  # Use basename only in the user-visible note so the transcript does
  # not leak $TMPDIR layout (e.g., /var/folders/.../<username>/...).
  TRUNC_NOTE="(output truncated to last $TAIL_BYTES bytes; full log preserved in \$TMPDIR/$(basename "$OUTPUT_FILE"))"
  TAIL=$(tail -c "$TAIL_BYTES" "$OUTPUT_FILE")
  # Preserve the temp file for inspection on failure.
  trap - EXIT
else
  TRUNC_NOTE=""
  TAIL=$(cat "$OUTPUT_FILE")
fi

REASON=$(printf 'scripts/pre-pr.sh failed (exit non-zero) — push/PR blocked.\nFix the failures below and retry. To bypass for one session: export SKIP_PRE_PR_GATE=1\n%s\n--- pre-pr.sh output ---\n%s' "$TRUNC_NOTE" "$TAIL")
printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
exit 0
