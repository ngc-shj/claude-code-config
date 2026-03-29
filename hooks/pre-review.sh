#!/bin/bash
# Pre-review: Quick code review pre-screening using local LLM
# Usage: bash ~/.claude/hooks/pre-review.sh [plan|code]
# - plan: Review a plan file (reads from stdin or $PLAN_FILE)
# - code: Review code changes (reads git diff from current branch)

set -euo pipefail

# shellcheck source=resolve-ollama-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/resolve-ollama-host.sh"
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
    # Prepend shared utility inventory if scanner is available
    SCANNER="$(dirname "${BASH_SOURCE[0]}")/scan-shared-utils.sh"
    if [ -x "$SCANNER" ]; then
      PLAN_UTILS=$(bash "$SCANNER" 2>/dev/null | head -200 || true)
      if [ -n "$PLAN_UTILS" ]; then
        CONTENT="=== SHARED UTILITIES INVENTORY (existing project code) ===
${PLAN_UTILS}

=== PLAN TO REVIEW ===
${CONTENT}"
      fi
    fi
    SYSTEM="You are a senior engineer. Review the following plan for obvious issues.

The input may contain a shared utilities inventory followed by the plan. Use the inventory to check whether the plan reuses existing code.

Focus on:
1. Missing requirements, unclear scope, security red flags, untestable designs
2. Whether the plan accounts for reusing existing shared utilities listed in the inventory instead of building new ones
3. Whether the plan covers ALL locations that need changes (not just the primary file)

Known recurring issues to check:
- R1: Does the plan propose creating logic that may already exist as a shared utility?
- R2: Does the plan hardcode constants that should be imported from a shared module?
- R3: If a pattern is changed, does the plan list ALL files using that pattern?
- R4: If mutations are added, does the plan include event/notification dispatch for all sites?

Be concise. Classify each finding as [Critical], [Major], or [Minor]. Critical: blocks release, data loss, security vulnerability. Major: significant functional issue, shared utility missed. Minor: style, naming. List only clear problems. If no issues found, reply with exactly: No issues found."
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

    # Collect shared utility inventory FIRST (needed for budget calculation)
    SHARED_UTILS=""
    SHARED_UTILS_LEN=0
    SCANNER="$(dirname "${BASH_SOURCE[0]}")/scan-shared-utils.sh"
    if [ -x "$SCANNER" ]; then
      FULL_SCAN=$(bash "$SCANNER" 2>/dev/null || true)
      SCAN_LINES=$(echo "$FULL_SCAN" | wc -l)
      if [ "$SCAN_LINES" -gt 200 ]; then
        SHARED_UTILS=$(echo "$FULL_SCAN" | head -200)
        SHARED_UTILS="${SHARED_UTILS}
# WARNING: inventory truncated at 200 lines — later sections may be missing"
      else
        SHARED_UTILS="$FULL_SCAN"
      fi
      SHARED_UTILS_LEN=${#SHARED_UTILS}
    fi

    # Collect full file contents for context, with budget control
    FILE_CONTEXT=""
    FILE_CONTEXT_LEN=0
    DIFF_LEN=${#DIFF}
    # Budget for file context = total budget - diff - shared utils inventory - margin
    FILE_BUDGET=$(( MAX_INPUT_CHARS - DIFF_LEN - SHARED_UTILS_LEN - 2000 ))
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

    if [ -n "$SHARED_UTILS" ]; then
      CONTENT="=== SHARED UTILITIES INVENTORY ===
${SHARED_UTILS}

${CONTENT}"
    fi

    SYSTEM="You are a code reviewer. Review the following code changes for obvious issues.

The input contains: (1) optionally, a shared utilities inventory, (2) full file contents (or headers if truncated), (3) the diff. Use these to verify imports, function definitions, and variable usage before flagging issues.

Focus on:
1. Bugs, security vulnerabilities (OWASP Top 10, injection, auth bypass), missing error handling
2. Code that reimplements logic already available in shared utilities (check the inventory if provided)
3. Constants or values hardcoded instead of imported from shared modules
4. Pattern changes applied in one location but missed in others

Known recurring issues to check:
- R1: New code reimplements existing shared utility (flag as Major)
- R2: Literal values that should be shared constants
- R3: Pattern changed in one file but not in other files using the same pattern
- RS1: Credential/token comparison using === instead of timingSafeEqual (flag as Critical)

Be concise. Classify each finding as [Critical], [Major], or [Minor]. Critical: data loss, security vulnerability, crash. Major: incorrect logic, missing error handling, shared utility reimplementation. Minor: naming, style.
IMPORTANT: Only flag issues you can confirm from the provided context. If a file was truncated, do NOT assume symbols are missing. List only clear problems with file name and line number. If no issues found, reply with exactly: No issues found."
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
