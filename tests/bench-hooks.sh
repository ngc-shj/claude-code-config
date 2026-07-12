#!/bin/bash
# Benchmark the PreToolUse Bash hook chain.
# Measures per-hook latency and cumulative chain latency for an approve
# case (the most common path — nothing matches).
#
# Usage:
#   bash tests/bench-hooks.sh [iterations]    # default: 100
#
# Output: Markdown table to stdout. Exits 0.
#
# Methodology:
#   - For each block-*.sh hook in hooks/, run N iterations with a benign
#     approve-path JSON input ({"tool_name":"Bash","tool_input":{
#     "command":"echo hello"}}) and record wall time per invocation
#     using `date +%s%N` (nanosecond resolution).
#   - "Approve path" is the right thing to measure because: (a) it is
#     the dominant path in normal workflow, (b) the deny path is faster
#     anyway (regex matches early and exits), so approve is the worst
#     case, (c) it isolates the always-paid cost of jq parsing + grep
#     evaluation.
#   - Report: min, median, p95, max, avg in milliseconds per hook, plus
#     cumulative chain estimate (sum of avgs).
#
# Caveats:
#   - Wall time on a developer machine has high variance; run on a
#     quiescent system. Re-run before drawing conclusions.
#   - Each iteration spawns a new bash process — process startup cost
#     dominates. The numbers here over-estimate hook-only cost relative
#     to a long-running daemon, but they correctly reflect what Claude
#     Code actually pays per Bash tool call.
#   - Hooks are timed in isolation (one invocation each). Real chain
#     execution invokes them sequentially per tool call, so cumulative
#     ≈ sum of avgs (modulo small per-process startup overhead that
#     cancels out across hooks).

set -euo pipefail

ITERATIONS="${1:-100}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_DIR/hooks"

# Benign approve case. Substring chosen to NOT match any deny regex.
APPROVE_INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'

# Confirm jq is present (every hook depends on it).
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

# Runs $hook $ITERATIONS times, prints "min median p95 max avg" in ms.
# The stdin fixture defaults to APPROVE_INPUT but may be overridden via
# the second argument (used by the session-retrospect-check.sh section,
# which needs its own SessionStart JSON instead of a PreToolUse fixture).
benchmark_hook() {
  local hook="$1"
  local stdin_fixture="${2:-$APPROVE_INPUT}"
  local i samples=()

  for ((i = 0; i < ITERATIONS; i++)); do
    local start_ns end_ns
    start_ns=$(date +%s%N)
    printf '%s' "$stdin_fixture" | bash "$hook" > /dev/null
    end_ns=$(date +%s%N)
    samples+=( $(( (end_ns - start_ns) / 1000000 )) )  # ns -> ms
  done

  # Sort, pick percentiles. POSIX sort with -n.
  local sorted
  sorted=$(printf '%s\n' "${samples[@]}" | sort -n)
  local count=${#samples[@]}
  local min median p95 max sum=0 avg

  min=$(printf '%s\n' "$sorted" | head -1)
  max=$(printf '%s\n' "$sorted" | tail -1)
  median=$(printf '%s\n' "$sorted" | awk -v c="$count" 'NR == int((c+1)/2) {print; exit}')
  p95=$(printf '%s\n' "$sorted" | awk -v c="$count" 'NR == int(c*0.95) {print; exit}')
  for s in "${samples[@]}"; do sum=$((sum + s)); done
  avg=$((sum / count))

  printf '%s %s %s %s %s\n' "$min" "$median" "$p95" "$max" "$avg"
}

# Header.
printf '# Hook chain latency benchmark\n\n'
printf 'Date: %s\n' "$(date -Iseconds)"
printf 'Iterations per hook: %s\n' "$ITERATIONS"
printf 'Input: approve-path JSON (`echo hello`)\n\n'
printf '| Hook | Matcher | min | median | p95 | max | avg |\n'
printf '| --- | --- | ---:| ---:| ---:| ---:| ---:|\n'

# Determine matcher membership from settings.json so the chain sums
# group hooks by the matcher they actually run on.
SETTINGS="$REPO_DIR/settings.json"

bash_chain_avg=0
bash_chain_count=0
edit_chain_avg=0
edit_chain_count=0

for hook in "$HOOKS_DIR"/block-*.sh; do
  [ -f "$hook" ] || continue
  hook_name=$(basename "$hook" .sh)
  read -r min median p95 max avg <<<"$(benchmark_hook "$hook")"

  # Find which matcher entry references this hook script.
  matcher=$(jq -r --arg n "$hook_name.sh" '
    .hooks.PreToolUse[]
    | select(.hooks[]?.command | tostring | contains($n))
    | .matcher
  ' "$SETTINGS" 2>/dev/null | head -1)
  [ -z "$matcher" ] && matcher="(unregistered)"

  printf '| %s | %s | %s ms | %s ms | %s ms | %s ms | %s ms |\n' \
    "$hook_name" "$matcher" "$min" "$median" "$p95" "$max" "$avg"

  case "$matcher" in
    "Bash")
      bash_chain_avg=$((bash_chain_avg + avg))
      bash_chain_count=$((bash_chain_count + 1))
      ;;
    "Edit|Write|MultiEdit")
      edit_chain_avg=$((edit_chain_avg + avg))
      edit_chain_count=$((edit_chain_count + 1))
      ;;
  esac
done

printf '\n## session-retrospect-check.sh (SessionStart)\n\n'
printf 'A dedicated section: this hook fires on SessionStart, not PreToolUse, so it\n'
printf 'needs its own stdin JSON plus RETRO_CONFIG/RETRO_STATE fixtures instead of the\n'
printf 'block-*.sh PreToolUse fixture above. The fixture models the "due" path (the\n'
printf 'more expensive branch: config parsed, due computed, mark-prompted written,\n'
printf 'additionalContext built).\n\n'

RETRO_BENCH_DIR="$(mktemp -d)"
trap 'rm -rf "$RETRO_BENCH_DIR"' EXIT

RETRO_BENCH_CONFIG="$RETRO_BENCH_DIR/config.json"
RETRO_BENCH_STATE="$RETRO_BENCH_DIR/state.json"
jq -nc '{
  version: 1,
  prompt_sources: ["startup"],
  snooze_days: 3,
  sources: {
    artifacts:   {enabled: true,  interval_days: 0,  repos: ["~/sib"], glob: "*.md"},
    github:      {enabled: false, interval_days: 7,  repos: []},
    transcripts: {enabled: false, interval_days: 14, root: "~/.claude/projects"},
    scout:       {enabled: false, interval_days: 30, urls: []}
  }
}' > "$RETRO_BENCH_CONFIG"

SESSION_START_INPUT='{"session_id":"bench","transcript_path":"/tmp/bench.jsonl","cwd":"/tmp","hook_event_name":"SessionStart","source":"startup"}'

retro_hook="$HOOKS_DIR/session-retrospect-check.sh"
if [ -f "$retro_hook" ]; then
  # Reset state each iteration so the hook keeps taking the due path
  # rather than degrading to the (cheaper) same-day-silent path after
  # the first mark-prompted.
  export RETRO_CONFIG="$RETRO_BENCH_CONFIG"
  export RETRO_STATE="$RETRO_BENCH_STATE"
  retro_samples=()
  for ((i = 0; i < ITERATIONS; i++)); do
    rm -f "$RETRO_BENCH_STATE"
    start_ns=$(date +%s%N)
    printf '%s' "$SESSION_START_INPUT" | bash "$retro_hook" > /dev/null
    end_ns=$(date +%s%N)
    retro_samples+=( $(( (end_ns - start_ns) / 1000000 )) )
  done
  unset RETRO_CONFIG RETRO_STATE

  retro_sorted=$(printf '%s\n' "${retro_samples[@]}" | sort -n)
  retro_count=${#retro_samples[@]}
  retro_min=$(printf '%s\n' "$retro_sorted" | head -1)
  retro_max=$(printf '%s\n' "$retro_sorted" | tail -1)
  retro_median=$(printf '%s\n' "$retro_sorted" | awk -v c="$retro_count" 'NR == int((c+1)/2) {print; exit}')
  retro_p95=$(printf '%s\n' "$retro_sorted" | awk -v c="$retro_count" 'NR == int(c*0.95) {print; exit}')
  retro_sum=0
  for s in "${retro_samples[@]}"; do retro_sum=$((retro_sum + s)); done
  retro_avg=$((retro_sum / retro_count))

  printf '| Hook | Matcher | min | median | p95 | max | avg |\n'
  printf '| --- | --- | ---:| ---:| ---:| ---:| ---:|\n'
  printf '| session-retrospect-check | SessionStart | %s ms | %s ms | %s ms | %s ms | %s ms |\n' \
    "$retro_min" "$retro_median" "$retro_p95" "$retro_max" "$retro_avg"
else
  printf '(hooks/session-retrospect-check.sh not found — skipping)\n'
fi

rm -rf "$RETRO_BENCH_DIR"
trap - EXIT

printf '\n## Per-matcher chain estimates\n\n'
printf '| Matcher | Hooks counted | Cumulative avg |\n'
printf '| --- | ---:| ---:|\n'
printf '| Bash (block-* hooks only) | %d | **%d ms** |\n' \
  "$bash_chain_count" "$bash_chain_avg"
printf '| Edit \\| Write \\| MultiEdit | %d | **%d ms** |\n' \
  "$edit_chain_count" "$edit_chain_avg"

printf '\nNotes:\n'
printf -- '- The Bash matcher also runs `commit-msg-check.sh`, which is excluded from this benchmark because (a) it short-circuits on non-`git commit` commands and (b) on a real `git commit` it calls Ollama, dominating wall time. The numbers above are the always-paid block-* tripwire cost.\n'
printf -- '- Per-iteration cost is dominated by `bash` process startup + a single `jq` invocation. The hooks emit `tool_name` and `tool_input.command` in one jq call separated by U+001F (Unit Separator) and split via bash parameter expansion — earlier 2-jq-call versions paid roughly twice this; an even earlier `@tsv` attempt was reverted because TAB inside command values collided with the TSV field separator.\n'
printf -- '- Numbers are wall time on a developer machine. Re-run on a quiescent system before drawing conclusions about per-call cost.\n'
