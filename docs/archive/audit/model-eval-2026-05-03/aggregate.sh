#!/bin/bash
# Aggregate bench.sh results into a markdown summary.
#
# Produces summary.md with:
#   1. Latency table   (seconds per sample × hook × model)
#   2. Token table     (output token count + tokens/sec)
#   3. Format check    (analyze-functionality: did the model emit ## END-OF-ANALYSIS?)
#   4. Output preview  (first 5 lines of each cell's response)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
DIR="$REPO_ROOT/docs/archive/audit/model-eval-2026-05-03"
RESULTS="$DIR/results"
OUT="$DIR/summary.md"

SAMPLES=(small medium large)
MODELS=("gpt-oss:20b" "gpt-oss:120b" "qwen3.6:35b-a3b")
HOOKS=(commit-msg-check summarize-diff analyze-functionality)

model_safe() { echo "${1//[:.\/]/-}"; }

cell_meta() {
  local sample="$1" hook="$2" model="$3"
  local f="$RESULTS/$sample/${hook}_$(model_safe "$model").meta"
  [ -s "$f" ] && cat "$f" || echo '{}'
}

cell_out() {
  local sample="$1" hook="$2" model="$3"
  local f="$RESULTS/$sample/${hook}_$(model_safe "$model").out"
  [ -s "$f" ] && cat "$f" || echo ""
}

{
  echo "# Model evaluation — $(date +%Y-%m-%d)"
  echo
  echo "Bench runner: \`bench.sh\` · Aggregator: \`aggregate.sh\` · Ollama version: $(curl -s --max-time 3 "${OLLAMA_HOST:-http://gx10-a9c0:11434}/api/version" 2>/dev/null | jq -r '.version // "?"')"
  echo
  echo "Sample commits:"
  for s in "${SAMPLES[@]}"; do
    diff_lines=$(wc -l < "$DIR/samples/$s.diff" 2>/dev/null || echo 0)
    subj=$(head -1 "$DIR/samples/$s.subject" 2>/dev/null || echo "?")
    echo "- **$s**: \`$subj\` ($diff_lines diff lines)"
  done
  echo

  # --- 1. Latency ---
  echo "## 1. Wall-clock latency (seconds)"
  echo
  for hook in "${HOOKS[@]}"; do
    echo "### $hook"
    echo
    printf '| sample |'; for m in "${MODELS[@]}"; do printf ' %s |' "$m"; done; echo
    printf '|---|'; for _ in "${MODELS[@]}"; do printf '%s' '---:|'; done; echo
    for sample in "${SAMPLES[@]}"; do
      printf '| %s |' "$sample"
      for model in "${MODELS[@]}"; do
        v=$(cell_meta "$sample" "$hook" "$model" | jq -r '.elapsed_s // "—"')
        printf ' %s |' "$v"
      done
      echo
    done
    echo
  done

  # --- 2. Output tokens & throughput ---
  echo "## 2. Output tokens / throughput (eval_count, tokens/sec)"
  echo
  for hook in "${HOOKS[@]}"; do
    echo "### $hook"
    echo
    printf '| sample |'; for m in "${MODELS[@]}"; do printf ' %s |' "$m"; done; echo
    printf '|---|'; for _ in "${MODELS[@]}"; do printf '%s' '---:|'; done; echo
    for sample in "${SAMPLES[@]}"; do
      printf '| %s |' "$sample"
      for model in "${MODELS[@]}"; do
        meta=$(cell_meta "$sample" "$hook" "$model")
        ec=$(echo "$meta" | jq -r '.eval_count // 0')
        ed=$(echo "$meta" | jq -r '.eval_duration_ms // 0')
        if [ "$ec" -gt 0 ] && [ "$ed" -gt 0 ]; then
          tps=$(awk -v c="$ec" -v d="$ed" 'BEGIN{printf "%.1f", c*1000/d}')
          printf ' %s tok / %s tok·s⁻¹ |' "$ec" "$tps"
        else
          printf ' — |'
        fi
      done
      echo
    done
    echo
  done

  # --- 3. Format adherence (analyze-functionality only) ---
  echo "## 3. Format adherence — analyze-functionality"
  echo
  echo "Did the model emit \`## END-OF-ANALYSIS\` as the final non-empty line?"
  echo
  printf '| sample |'; for m in "${MODELS[@]}"; do printf ' %s |' "$m"; done; echo
  printf '|---|'; for _ in "${MODELS[@]}"; do printf '%s' '---:|'; done; echo
  for sample in "${SAMPLES[@]}"; do
    printf '| %s |' "$sample"
    for model in "${MODELS[@]}"; do
      out=$(cell_out "$sample" "analyze-functionality" "$model")
      if [ -z "$out" ]; then
        printf ' — |'
      else
        last=$(echo "$out" | awk 'NF{l=$0} END{print l}')
        if echo "$last" | grep -q '^## END-OF-ANALYSIS$'; then
          printf ' ✅ |'
        else
          printf ' ❌ |'
        fi
      fi
    done
    echo
  done
  echo

  # --- 4. Output previews ---
  echo "## 4. Output previews"
  echo
  for sample in "${SAMPLES[@]}"; do
    for hook in "${HOOKS[@]}"; do
      echo "### $sample × $hook"
      echo
      for model in "${MODELS[@]}"; do
        echo "**$model**"
        echo
        out=$(cell_out "$sample" "$hook" "$model")
        if [ -z "$out" ]; then
          echo "_(empty / error)_"
        else
          echo '```'
          echo "$out" | head -8
          [ "$(echo "$out" | wc -l)" -gt 8 ] && echo "..."
          echo '```'
        fi
        echo
      done
    done
  done
} > "$OUT"

echo "Wrote $OUT" >&2
