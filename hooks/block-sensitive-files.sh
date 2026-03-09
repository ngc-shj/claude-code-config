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

echo '{"decision": "approve"}'
