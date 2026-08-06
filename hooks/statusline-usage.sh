#!/usr/bin/env bash
# Status line that also records the plan's rate-limit percentages.
#
# Why this exists: `/usage` floors its percentages to integers, which cannot
# resolve a batch smaller than a few percent of the weekly allowance. The
# status line payload carries the same figures with decimals, and it is the
# only place they surface locally — the server computes them and Claude Code
# does not persist them anywhere else. Logging them here turns "how much did
# that batch of agents cost" into a subtraction instead of a guess.
#
# Usage: configured as `statusLine.command` in settings.json. Claude Code runs
# it on each render and passes the session JSON on stdin.
#
# WHAT IS LOGGED, and nothing else: a timestamp and the two percentages. The
# payload also carries the session id, the transcript path and the working
# directory; none of those are written. tests/statusline-usage.bats pins that.
set -u

LOG="${CLAUDE_USAGE_LOG:-$HOME/.claude/usage-log.jsonl}"

payload="$(cat)"

# No jq: still render something rather than leaving the status line blank.
if ! command -v jq >/dev/null 2>&1; then
  printf 'claude'
  exit 0
fi

model="$(printf '%s' "$payload" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null)"
dir="$(printf '%s' "$payload" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)"

# Field names follow the documented status line schema. They are read
# defensively because a payload from an older or newer CLI may not carry
# rate_limits at all, and a status line that errors is worse than one that is
# merely incomplete.
five="$(printf '%s' "$payload" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)"
seven="$(printf '%s' "$payload" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)"

line="${model}"
[ -n "$dir" ] && line="${line} $(basename "$dir")"

if [ -n "$five" ] || [ -n "$seven" ]; then
  line="${line} | 5h ${five:-?}% 7d ${seven:-?}%"

  # Append only when a figure changes. A status line renders many times per
  # turn; logging every render would bury the transitions that carry the
  # information, and the file is meant to be read by eye as well as by script.
  last=""
  [ -f "$LOG" ] && last="$(tail -n 1 "$LOG" 2>/dev/null | jq -r '"\(.five_hour)|\(.seven_day)"' 2>/dev/null)"
  if [ "${five:-null}|${seven:-null}" != "$last" ]; then
    mkdir -p "$(dirname "$LOG")" 2>/dev/null
    jq -cn --argjson f "${five:-null}" --argjson s "${seven:-null}" \
       --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{at:$t, five_hour:$f, seven_day:$s}' >> "$LOG" 2>/dev/null
  fi
elif [ -n "$(printf '%s' "$payload" | jq -r '.rate_limits // empty' 2>/dev/null)" ]; then
  # rate_limits exists but not under the expected path: record the key names
  # so the schema can be corrected, without writing any of the values.
  keys="$(printf '%s' "$payload" | jq -c '.rate_limits | keys' 2>/dev/null)"
  marker="$(tail -n 1 "$LOG" 2>/dev/null | jq -r '.unexpected_rate_limit_keys // empty' 2>/dev/null)"
  if [ "$keys" != "$marker" ]; then
    mkdir -p "$(dirname "$LOG")" 2>/dev/null
    jq -cn --argjson k "$keys" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{at:$t, unexpected_rate_limit_keys:$k}' >> "$LOG" 2>/dev/null
  fi
fi

printf '%s' "$line"
