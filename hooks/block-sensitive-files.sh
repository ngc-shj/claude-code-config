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

# Block patterns
case "$BASENAME" in
  .env|.env.local|.env.production|.env.staging)
    echo '{"decision": "block", "reason": "Blocked: editing environment file '"$BASENAME"' which may contain secrets"}'
    exit 0
    ;;
  .env.*)
    # Allow .env.example (template without secrets)
    if [ "$BASENAME" = ".env.example" ]; then
      echo '{"decision": "approve"}'
      exit 0
    fi
    echo '{"decision": "block", "reason": "Blocked: editing environment file '"$BASENAME"' which may contain secrets"}'
    exit 0
    ;;
  credentials.json|secrets.yaml|secrets.yml|*.pem|*.key|id_rsa|id_ed25519)
    echo '{"decision": "block", "reason": "Blocked: editing credential/key file '"$BASENAME"'"}'
    exit 0
    ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|bun.lock)
    echo '{"decision": "block", "reason": "Blocked: lock files should only be modified by package managers, not edited directly"}'
    exit 0
    ;;
esac

# Block .git internals
case "$FILE_PATH" in
  */.git/*|.git/*)
    echo '{"decision": "block", "reason": "Blocked: editing git internals is dangerous"}'
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
case "$FILE_PATH" in
  "$HOME/.claude/hooks/"*.sh|"$HOME/.claude/settings.json"|"$HOME/.claude/CLAUDE.md")
    echo '{"decision": "block", "reason": "Blocked: editing harness config under ~/.claude/ directly. The repo claude-code-config is the source of truth — edit there and run `bash ./install.sh`. To override a hook locally, use ~/.claude/settings.local.json (which is NOT blocked)."}'
    exit 0
    ;;
  "~/.claude/hooks/"*.sh|"~/.claude/settings.json"|"~/.claude/CLAUDE.md")
    echo '{"decision": "block", "reason": "Blocked: editing harness config under ~/.claude/ directly. Edit the repo claude-code-config and run `bash ./install.sh`. Use ~/.claude/settings.local.json for local overrides."}'
    exit 0
    ;;
esac

echo '{"decision": "approve"}'
