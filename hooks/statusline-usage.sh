#!/usr/bin/env bash
# Status line that also records the plan's rate-limit percentages.
#
# Why this exists: `/usage` floors its percentages to integers, which cannot
# resolve a batch smaller than a few percent of the weekly allowance. The
# status line payload carries the same figures with decimals, and it is the
# only place they surface locally — the server computes them and Claude Code
# does not persist them anywhere else.
#
# WHAT A DIFFERENCE BETWEEN TWO READINGS MEANS, and does not. The log measures
# ACCOUNT-WIDE usage, not this batch's. `after - before` is that batch's cost
# only under a controlled run:
#   - `resets_at` is identical in both readings (otherwise a window rolled over
#     and the difference is meaningless — this is why it is recorded)
#   - no other Claude Code session, claude.ai, Desktop or device was used in
#     between
#   - the same model, effort and agent shape throughout
#   - the closing reading reflects the batch's last API response
# Outside those conditions it is an upper bound on the batch, not its cost.
#
# WHAT IS LOGGED, and nothing else: a timestamp, the two percentages and their
# reset boundaries. The payload also carries the session id, the transcript
# path and the working directory; none are written. tests/ pins that.
#
# Usage: configured as `statusLine.command` in settings.json. Claude Code runs
# it on each render and passes the session JSON on stdin.
set -u

LOG="${CLAUDE_USAGE_LOG:-$HOME/.claude/usage-log.jsonl}"
warn=""

payload="$(cat)"

# No jq: still render something rather than leaving the status line blank.
if ! command -v jq >/dev/null 2>&1; then
  printf 'claude'
  exit 0
fi

# ONE jq invocation per render. It emits two lines: the display fields as TSV,
# then the log record as JSON. Splitting these into separate jq calls cost
# ~21ms per render for no benefit.
#
# `at` is deliberately the FIRST field of the record, because the change
# comparison below drops it with `${record#*,}` — a timestamp contains no
# comma, so that yields exactly the part that must be identical for a reading
# to count as unchanged.
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
out="$(printf '%s' "$payload" | jq -r --arg t "$now" '
  ([ (.model.display_name // .model.id // "?"),
     (.workspace.current_dir // .cwd // "-"),
     (.rate_limits.five_hour.used_percentage // "-" | tostring),
     (.rate_limits.seven_day.used_percentage // "-" | tostring),
     (if (.rate_limits.five_hour.used_percentage // .rate_limits.seven_day.used_percentage) then "ok"
      elif .rate_limits then "shape:" + (.rate_limits | keys | join(",")) else "none" end)
   ] | @tsv),
  ({ at: $t,
     five_hour: { used_percentage: .rate_limits.five_hour.used_percentage,
                  resets_at:       .rate_limits.five_hour.resets_at },
     seven_day: { used_percentage: .rate_limits.seven_day.used_percentage,
                  resets_at:       .rate_limits.seven_day.resets_at } } | tojson)
' 2>/dev/null)"

IFS=$'\t' read -r model dir five seven state <<< "${out%%$'\n'*}"
record="${out#*$'\n'}"

line="${model:-claude}"
[ -n "${dir:-}" ] && [ "$dir" != "-" ] && line="${line} $(basename "$dir")"

case "${state:-none}" in
  ok)
    line="${line} | 5h ${five}% 7d ${seven}%"
    key="${record#*,}"
    # Compare and append under a lock on the log itself. Without it, two
    # sessions rendering at once both read the same tail and both append: a
    # 100-way parallel run produced six lines where one was correct. The lock
    # also stops an older reading from landing after a newer one.
    if ! ( umask 077
           mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 1
           exec 9>>"$LOG" 2>/dev/null || exit 1
           command -v flock >/dev/null 2>&1 && flock 9 2>/dev/null
           last="$(tail -n 1 "$LOG" 2>/dev/null)"
           [ "${last#*,}" = "$key" ] && exit 0
           printf '%s\n' "$record" >&9 || exit 1 ); then
      warn=" usage-log!"
    fi
    ;;
  shape:*)
    # rate_limits present but not under the documented path. Record the key
    # NAMES so the schema can be corrected, never the values.
    keys="${state#shape:}"
    if ! ( umask 077
           mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 1
           exec 9>>"$LOG" 2>/dev/null || exit 1
           command -v flock >/dev/null 2>&1 && flock 9 2>/dev/null
           last="$(tail -n 1 "$LOG" 2>/dev/null)"
           case "$last" in *"\"unexpected_rate_limit_keys\":\"$keys\""*) exit 0 ;; esac
           printf '{"at":"%s","unexpected_rate_limit_keys":"%s"}\n' "$now" "$keys" >&9 || exit 1 ); then
      warn=" usage-log!"
    fi
    ;;
esac

printf '%s%s' "$line" "$warn"
