#!/bin/bash
# PreToolUse hook: Block Edit/Write to sensitive files
# Prevents accidental modification of secrets, lock files, and git internals

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

if [ -z "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

# Emit a block decision with the reason JSON-encoded by jq. Direct shell
# interpolation of `$BASENAME` into the reason string is unsafe: a crafted
# tool_input.file_path containing `"` characters produces malformed JSON,
# and a fail-open harness would then bypass this hook entirely. Mirrors the
# pattern used by the other block-*.sh hooks in this directory.
emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$reason" | jq -Rs .)"
}

# Block patterns
case "$BASENAME" in
  .env|.env.local|.env.production|.env.staging)
    emit_block "Blocked: editing environment file ${BASENAME} which may contain secrets"
    exit 0
    ;;
  .env.*)
    # Allow .env.example (template without secrets)
    if [ "$BASENAME" = ".env.example" ]; then
      echo '{"decision": "approve"}'
      exit 0
    fi
    emit_block "Blocked: editing environment file ${BASENAME} which may contain secrets"
    exit 0
    ;;
  credentials.json|secrets.yaml|secrets.yml|*.pem|*.key|id_rsa|id_ed25519)
    emit_block "Blocked: editing credential/key file ${BASENAME}"
    exit 0
    ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|bun.lock)
    emit_block "Blocked: lock files should only be modified by package managers, not edited directly"
    exit 0
    ;;
esac

# Block .git internals
case "$FILE_PATH" in
  */.git/*|.git/*)
    emit_block "Blocked: editing git internals is dangerous"
    exit 0
    ;;
esac

# Block Claude Code harness configuration that is repo-managed. A session
# that edits its own hook script can no-op a tripwire (e.g.,
# block-destructive-docker.sh) and then issue the destructive operation
# the hook was meant to catch. The repo at ~/ghq/github.com/ngc-shj/
# claude-code-config/ is the source of truth — edits belong there, then
# `bash ./install.sh` syncs into ~/.claude/.
#
# Intentionally NOT blocked: ~/.claude/settings.local.json — that is the
# documented override path (it is NOT overwritten by install.sh) and is
# the only sanctioned way to disable a hook locally without modifying
# the repo. See block-destructive-docker.sh's reason message for the
# canonical override workflow.
#
# Normalize $HOME once, for every arm below: a trailing slash in $HOME
# (e.g. HOME=/home/user/) would otherwise turn "$HOME/.claude/..." into
# "…//.claude/…", which never matches the single-slash path the tool
# reports, so the guard silently fails open. ${HOME:?} turns an unset
# $HOME into a stated precondition instead of a mid-case crash under
# `set -euo pipefail`.
CLAUDE_HOME="${HOME:?}"; CLAUDE_HOME="${CLAUDE_HOME%/}/.claude"
# One copy, used by both the expanded and the literal-tilde arm. The two
# harness-config arms below carry deliberately different wording, but an
# identical message duplicated across arms drifts silently — and only the arm a
# fixture happens to exercise would catch it.
SKILLS_BLOCK_REASON="Blocked: editing an installed skill under ~/.claude/skills/ directly. If this skill is repo-managed, edit it in the claude-code-config repo and run \`bash ./install.sh\`. If it has no repo source (install.sh only removes and re-copies the skills it manages, so an unmanaged skill survives every install untouched), add it to the repo's skills/ directory, or exempt it via ~/.claude/settings.local.json."
case "$FILE_PATH" in
  "$CLAUDE_HOME/hooks/"*.sh|"$CLAUDE_HOME/settings.json"|"$CLAUDE_HOME/CLAUDE.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly. The repo claude-code-config is the source of truth — edit there and run \`bash ./install.sh\`. To override a hook locally, use ~/.claude/settings.local.json (which is NOT blocked)."
    exit 0
    ;;
  "$CLAUDE_HOME/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
  "~/.claude/hooks/"*.sh|"~/.claude/settings.json"|"~/.claude/CLAUDE.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly. Edit the repo claude-code-config and run \`bash ./install.sh\`. Use ~/.claude/settings.local.json for local overrides."
    exit 0
    ;;
  "~/.claude/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
esac

echo '{"decision": "approve"}'
