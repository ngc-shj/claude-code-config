#!/bin/bash
# Shared Ollama utility commands for skills and hooks
# Usage: bash ~/.claude/hooks/ollama-utils.sh <command> [options]
# Input via stdin, output to stdout. Ollama failure → warning to stderr, empty stdout, exit 0.

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://gx10-a9c0:11434}"

# Script-level temp directory for all requests
TMPDIR_UTILS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_UTILS"' EXIT

# Common request function: sends prompt to Ollama, prints response
# Args: $1=model $2=system_prompt $3=timeout $4=num_predict
_ollama_request() {
  local model="$1" system="$2" timeout="$3" num_predict="${4:-16384}"
  local content
  content=$(cat)

  if [ -z "$content" ]; then
    return
  fi

  local tmpdir="$TMPDIR_UTILS"

  printf '%s' "$system" > "$tmpdir/system"
  printf '%s' "$content" > "$tmpdir/prompt"

  jq -n \
    --arg model "$model" \
    --rawfile system "$tmpdir/system" \
    --rawfile prompt "$tmpdir/prompt" \
    --argjson num_predict "$num_predict" \
    '{model: $model, system: $system, prompt: $prompt, stream: false,
      options: {num_predict: $num_predict}}' \
    > "$tmpdir/request.json"

  local http_code
  http_code=$(curl -s --max-time "$timeout" -w '%{http_code}' \
    -o "$tmpdir/response.json" \
    "$OLLAMA_HOST/api/generate" \
    -d @"$tmpdir/request.json" 2>/dev/null) || true

  if [ "$http_code" = "000" ] || [ ! -s "$tmpdir/response.json" ]; then
    echo "Warning: Ollama unavailable at $OLLAMA_HOST" >&2
    return
  fi

  if [ "$http_code" != "200" ]; then
    echo "Warning: Ollama returned HTTP $http_code" >&2
    head -3 "$tmpdir/response.json" >&2
    return
  fi

  # Support thinking models: prefer .response, fall back to .thinking
  local response
  response=$(jq -r '.response // empty' "$tmpdir/response.json")

  if [ -z "$response" ]; then
    response=$(jq -r '.thinking // empty' "$tmpdir/response.json")
  fi

  if [ -n "$response" ]; then
    printf '%s' "$response"
  fi
}

# --- Subcommands ---

cmd_generate_slug() {
  _ollama_request "gpt-oss:20b" \
    "Convert the input to a short kebab-case slug (2-5 words, lowercase, hyphens only). Output ONLY the slug, nothing else. Examples: 'Add user authentication' → 'add-user-auth', 'Fix login page bug' → 'fix-login-bug'" \
    60
}

cmd_summarize_diff() {
  _ollama_request "gpt-oss:120b" \
    "Summarize the following git diff in 3-5 concise bullet points. Focus on: what changed, why it matters, and any risks. Output only the bullet points." \
    600
}

cmd_merge_findings() {
  _ollama_request "gpt-oss:120b" \
    "You receive review findings from multiple expert agents. Deduplicate and merge them:
- Merge findings that describe the same underlying issue (keep the most comprehensive description)
- Note which perspectives flagged each finding
- Sort by severity: Critical → Major → Minor
- Preserve the format: Severity, Problem, Impact, Recommended action
- If all inputs say 'No findings', output exactly: No findings" \
    600
}

cmd_classify_changes() {
  _ollama_request "gpt-oss:20b" \
    "Classify the following list of changed file paths into exactly ONE category. Output ONLY the category word, nothing else.
Categories: feature, fix, refactor, docs, test, chore.
If mixed, choose the dominant category." \
    60
}

# --- Dispatcher ---

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
  generate-slug)    cmd_generate_slug ;;
  summarize-diff)   cmd_summarize_diff ;;
  merge-findings)   cmd_merge_findings ;;
  classify-changes) cmd_classify_changes ;;
  help|"")
    echo "Usage: bash ollama-utils.sh <command>" >&2
    echo "Commands: generate-slug, summarize-diff, merge-findings, classify-changes" >&2
    exit 1
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    echo "Run 'bash ollama-utils.sh help' for available commands." >&2
    exit 1
    ;;
esac
