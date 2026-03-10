#!/bin/bash
# Pre-review: Quick code review pre-screening using local LLM
# Usage: bash ~/.claude/hooks/pre-review.sh [plan|code]
# - plan: Review a plan file (reads from stdin or $PLAN_FILE)
# - code: Review code changes (reads git diff from current branch)

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://gx10-a9c0:11434}"
MODEL="${REVIEW_MODEL:-gpt-oss:120b}"
TIMEOUT="${REVIEW_TIMEOUT:-600}"
MODE="${1:-code}"

# Token budget: reserve space for output, use rest for input
# ~3 chars per token as rough estimate; let Ollama manage num_ctx
MAX_INPUT_TOKENS=128000
NUM_PREDICT=8192
MAX_INPUT_CHARS=$(( MAX_INPUT_TOKENS * 3 ))

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
    # Use -U10 for expanded context (default is 3 lines)
    DIFF=$(git diff -U10 main...HEAD 2>/dev/null)
    if [ -z "$DIFF" ]; then
      DIFF=$(git diff -U10 HEAD 2>/dev/null)
    fi
    if [ -z "$DIFF" ]; then
      DIFF=$(git diff -U10 2>/dev/null)
    fi
    if [ -z "$DIFF" ]; then
      echo "No code changes to review."
      exit 0
    fi

    # Collect full file contents for context, with budget control
    FILE_CONTEXT=""
    FILE_CONTEXT_LEN=0
    DIFF_LEN=${#DIFF}
    # Budget for file context = total budget - diff size - margin for system prompt
    FILE_BUDGET=$(( MAX_INPUT_CHARS - DIFF_LEN - 2000 ))
    if [ "$FILE_BUDGET" -lt 0 ]; then
      FILE_BUDGET=0
    fi

    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if [ -f "$f" ] && [ "$FILE_CONTEXT_LEN" -lt "$FILE_BUDGET" ]; then
        FILE_CONTENT=$(cat "$f" 2>/dev/null)
        FILE_CONTENT_LEN=${#FILE_CONTENT}
        if [ $(( FILE_CONTEXT_LEN + FILE_CONTENT_LEN )) -le "$FILE_BUDGET" ]; then
          # Full file fits in budget
          FILE_CONTEXT="${FILE_CONTEXT}
--- Full file: ${f} ---
${FILE_CONTENT}
"
          FILE_CONTEXT_LEN=$(( FILE_CONTEXT_LEN + FILE_CONTENT_LEN ))
        else
          # Fallback to header only
          HEADER=$(head -40 "$f" 2>/dev/null)
          if [ -n "$HEADER" ]; then
            FILE_CONTEXT="${FILE_CONTEXT}
--- File header: ${f} (first 40 lines, truncated due to budget) ---
${HEADER}
"
            FILE_CONTEXT_LEN=$(( FILE_CONTEXT_LEN + ${#HEADER} ))
          fi
        fi
      fi
    done < <(echo "$DIFF" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||')

    CONTENT="=== FILE CONTEXT ===
${FILE_CONTEXT}
=== DIFF (with 10 lines of surrounding context) ===
${DIFF}"

    SYSTEM="You are a code reviewer. Review the following code changes for obvious issues. The input contains full file contents (or headers if truncated) followed by the diff. Use the file contents to verify imports, function definitions, and variable usage before flagging issues. Focus on: bugs, security vulnerabilities (OWASP Top 10, injection, auth bypass), missing error handling, naming issues. Be concise. Classify each finding as [Critical], [Major], or [Minor]. Critical: data loss, security vulnerability, crash. Major: incorrect logic, missing error handling. Minor: naming, style. IMPORTANT: Only flag issues you can confirm from the provided context. If a file was truncated, do NOT assume symbols are missing. List only clear problems with file name and line number. If no issues found, reply with exactly: No issues found."
    ;;
  *)
    echo "Usage: $0 [plan|code]"
    exit 1
    ;;
esac

# Build request JSON via temp files to avoid ARG_MAX limits
TMPDIR_REQ=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REQ"' EXIT
printf '%s' "$SYSTEM" > "$TMPDIR_REQ/system"
printf '%s' "$CONTENT" > "$TMPDIR_REQ/prompt"

# Call Ollama API
jq -n \
    --arg model "$MODEL" \
    --rawfile system "$TMPDIR_REQ/system" \
    --rawfile prompt "$TMPDIR_REQ/prompt" \
    --argjson num_predict "$NUM_PREDICT" \
    '{model: $model, system: $system, prompt: $prompt, stream: false,
      options: {num_predict: $num_predict}}' \
  > "$TMPDIR_REQ/request.json"

HTTP_CODE=$(curl -s --max-time "$TIMEOUT" -w '%{http_code}' \
  -o "$TMPDIR_REQ/response.json" \
  "$OLLAMA_HOST/api/generate" \
  -d @"$TMPDIR_REQ/request.json" 2>/dev/null) || true

if [ "$HTTP_CODE" = "000" ] || [ ! -s "$TMPDIR_REQ/response.json" ]; then
  echo "Warning: Ollama unavailable at $OLLAMA_HOST. Skipping pre-review."
  exit 0
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "Warning: Ollama returned HTTP $HTTP_CODE. Skipping pre-review."
  head -5 "$TMPDIR_REQ/response.json" >&2
  exit 0
fi

# Extract response; some models (thinking models) put output in .thinking
RESPONSE=$(jq -r '
  if (.response // "") != "" then .response
  elif (.thinking // "") != "" then .thinking
  else empty
  end' "$TMPDIR_REQ/response.json")

if [ -z "$RESPONSE" ]; then
  echo "Warning: Ollama returned empty response. Skipping pre-review."
  exit 0
fi

echo "$RESPONSE"
