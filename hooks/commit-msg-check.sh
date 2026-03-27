#!/bin/bash
# PreToolUse hook: Validate commit messages using local LLM
# Checks git commit commands for message quality before execution

set -euo pipefail

# shellcheck source=resolve-ollama-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/resolve-ollama-host.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^git commit'; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Extract commit message (compatible with macOS grep)
COMMIT_MSG=$(echo "$COMMAND" | sed -n 's/.*-m "\([^"]*\)".*/\1/p; s/.*-m '"'"'\([^'"'"']*\)'"'"'.*/\1/p' | head -1)

if [ -z "$COMMIT_MSG" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Check with local LLM via Ollama API
REVIEW=$(curl -sf --max-time 10 "$OLLAMA_HOST/api/generate" \
  -d "$(jq -n \
    --arg model "gpt-oss:20b" \
    --arg prompt "Review this git commit message. Reply with ONLY 'OK' if it follows best practices (concise, English, explains why not what, uses conventional prefix like feat/fix/refactor/docs/test/chore). Reply with a one-line suggestion if it needs improvement.\n\nCommit message: $COMMIT_MSG" \
    '{model: $model, prompt: $prompt, stream: false}')" \
  2>/dev/null | jq -r '.response // empty' | head -1)

if [ -z "$REVIEW" ]; then
  # Ollama unavailable, approve silently
  echo '{"decision": "approve"}'
  exit 0
fi

if echo "$REVIEW" | grep -qi '^OK'; then
  echo '{"decision": "approve"}'
else
  echo "{\"decision\": \"approve\", \"reason\": \"Commit message suggestion from local LLM: $REVIEW\"}"
fi
