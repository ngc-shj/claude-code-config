#!/bin/bash
# Pre-review: Quick code review pre-screening using local LLM
# Usage: bash ~/.claude/hooks/pre-review.sh [plan|code]
# - plan: Review a plan file (reads from stdin or $PLAN_FILE)
# - code: Review code changes (reads git diff from current branch)

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://gx10-a9c0:11434}"
MODEL="${REVIEW_MODEL:-gpt-oss:120b}"
TIMEOUT="${REVIEW_TIMEOUT:-300}"
MODE="${1:-code}"

case "$MODE" in
  plan)
    if [ -n "${PLAN_FILE:-}" ] && [ -f "$PLAN_FILE" ]; then
      CONTENT=$(cat "$PLAN_FILE")
    else
      CONTENT=$(cat)
    fi
    SYSTEM="You are a senior engineer. Review the following plan for obvious issues. Focus on: missing requirements, unclear scope, security red flags, untestable designs. Be concise. Classify each finding as [Critical], [Major], or [Minor]. Critical: blocks release, data loss, security vulnerability. Major: significant functional issue. Minor: style, naming. List only clear problems. If no issues found, reply with exactly: No issues found."
    ;;
  code)
    CONTENT=$(git diff main...HEAD 2>/dev/null)
    if [ -z "$CONTENT" ]; then
      CONTENT=$(git diff HEAD 2>/dev/null)
    fi
    if [ -z "$CONTENT" ]; then
      CONTENT=$(git diff 2>/dev/null)
    fi
    if [ -z "$CONTENT" ]; then
      echo "No code changes to review."
      exit 0
    fi
    SYSTEM="You are a code reviewer. Review the following code changes for obvious issues. Focus on: bugs, security vulnerabilities (OWASP Top 10, injection, auth bypass), missing error handling, naming issues. Be concise. Classify each finding as [Critical], [Major], or [Minor]. Critical: data loss, security vulnerability, crash. Major: incorrect logic, missing error handling. Minor: naming, style. List only clear problems with file name and line number. If no issues found, reply with exactly: No issues found."
    ;;
  *)
    echo "Usage: $0 [plan|code]"
    exit 1
    ;;
esac

# Call Ollama API
RESPONSE=$(curl -sf --max-time "$TIMEOUT" "$OLLAMA_HOST/api/generate" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM" \
    --arg prompt "$CONTENT" \
    '{model: $model, system: $system, prompt: $prompt, stream: false}')" \
  2>/dev/null | jq -r '.response // empty')

if [ -z "$RESPONSE" ]; then
  echo "Warning: Ollama unavailable at $OLLAMA_HOST. Skipping pre-review."
  exit 0
fi

echo "$RESPONSE"
