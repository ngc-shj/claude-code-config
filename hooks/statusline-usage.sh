#!/usr/bin/env bash
# Status line that also records the plan's rate-limit percentages.
#
# Why this exists: `/usage` floors its percentages to integers, which cannot
# resolve a batch smaller than a few percent of the weekly allowance. The
# status line payload carries the same figures with decimals, and it is the
# only place they surface locally — the server computes them and Claude Code
# does not persist them anywhere else.
#
# WHAT A DIFFERENCE BETWEEN TWO READINGS MEANS. The log measures ACCOUNT-WIDE
# usage, not this batch's, so `after - before` is:
#   - an UPPER BOUND on the batch, when both readings sit in the same window
#     (identical `resets_at`) and the closing one is fresh — anything else you
#     or another device did lands in the same figure;
#   - INVALID, not merely loose, when a window rolled over between them, when
#     either reading is stale, or when a field is missing. A rollover can make
#     the difference negative or spuriously small, so it is not conservative in
#     any direction.
# Matching the model, effort and agent shape is NOT needed for the subtraction
# itself; it is what licenses extrapolating the result to a different batch.
#
# EACH WINDOW IS JUDGED ALONE. The five-hour and seven-day figures roll over on
# different schedules and either may be absent from a payload, so a reading is
# accepted or rejected per window. A window that is missing, that went
# backwards, or whose reset moved backwards is written as `null` rather than
# carried forward from the previous line — carrying it forward would invent an
# observation that was never made. A consumer subtracting one window skips the
# lines where it is null.
#
# WHAT IS LOGGED, and nothing else: a timestamp, the two percentages and their
# reset boundaries. The payload also carries the session id, the transcript
# path and the working directory; none are written. tests/ pins that.
#
# Usage: configured as `statusLine.command` in settings.json. Claude Code runs
# it on each render and passes the session JSON on stdin.
set -u

LOG="${CLAUDE_USAGE_LOG:-$HOME/.claude/usage-log.jsonl}"
LOCK="$LOG.lock"
STATE="$LOG.state"      # last ACCEPTED value per window; see append_record
warn=""

payload="$(cat)"

# No jq: still render something rather than leaving the status line blank.
if ! command -v jq >/dev/null 2>&1; then
  printf 'claude'
  exit 0
fi

# A lock directory rather than flock: `mkdir` is atomic on POSIX and present
# everywhere, while flock is absent on macOS — and calling flock only `if`
# available silently reverts to an unsynchronised read-then-write on exactly
# the platform that lacks it.
#
# A held lock is reclaimed ONLY when its owner is provably gone (`kill -0`).
# Age is never evidence of death — a suspended laptop or a stalled write can
# exceed any threshold with the writer alive — and an unreadable owner file is
# not evidence either: there is a sub-millisecond window between `mkdir`
# succeeding and the owner being written, and an age-based fallback treated a
# lock in that window as ancient and stole it. That race only appeared under
# load, which is what a concurrency test running late in a full suite provides.
# So an unreadable owner means WAIT, and exhausting the retries means fail
# closed. A lock whose creator died inside that window is never reclaimed
# automatically; the status line says `usage-log!` until it is removed by hand.
lock_acquire() {
  local i=0 lock_pid
  while [ "$i" -lt 25 ]; do
    i=$((i + 1))
    if mkdir "$LOCK" 2>/dev/null; then
      printf '%s\n' "$$" 2>/dev/null > "$LOCK/owner" || :
      return 0
    fi
    lock_pid=""
    read -r lock_pid _ 2>/dev/null < "$LOCK/owner" || :
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      rm -rf "$LOCK" 2>/dev/null                       # owner is provably gone
    fi
    sleep 0.02
  done
  return 1                                             # fail CLOSED
}
lock_release() { rm -rf "$LOCK" 2>/dev/null; }

# $1 record JSON, $2 comparison key, $3 "monotonic" to judge windows for staleness.
# Echoes the record actually written (windows may be nulled), or nothing.
append_record() {
  local record="$1" key="$2" mode="${3:-}" last merged newstate
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 1
  lock_acquire || return 1
  trap 'lock_release' EXIT

  # Before any early return. umask governs creation only, so a log that
  # predates this guard keeps its old mode forever — and an unchanged or stale
  # reading, the common cases, both leave without reaching the append.
  if [ -e "$LOG" ] && ! chmod 600 "$LOG" 2>/dev/null; then
    lock_release; trap - EXIT; return 1
  fi

  last="$(tail -n 1 "$LOG" 2>/dev/null)"

  if [ "$mode" = monotonic ]; then
    # The comparison baseline is a STATE FILE holding the last accepted value
    # per window, not a slice of the log. Scanning the last N lines made the
    # "reject a value that went backwards" guarantee depend on N: advance one
    # window past the lookback and a stale reading of the OTHER window was
    # accepted as new. The state file has no such horizon and is O(1).
    #
    # If it is absent — first run, or a log that predates it — it is rebuilt
    # from the whole log once, so an existing history is not silently forgotten.
    if [ ! -s "$STATE" ] && [ -s "$LOG" ]; then
      jq -sc '{ five_hour: ([.[] | .five_hour | select(type=="object")] | last),
                seven_day: ([.[] | .seven_day | select(type=="object")] | last) }' \
         "$LOG" > "$STATE" 2>/dev/null || :
      chmod 600 "$STATE" 2>/dev/null
    fi
    # --slurpfile fails outright on a missing file, and that failure is
    # indistinguishable from a real merge error, so make sure one exists.
    if [ ! -s "$STATE" ]; then
      printf '{}\n' > "$STATE" 2>/dev/null && chmod 600 "$STATE" 2>/dev/null
    fi

    # One jq for the merge: it reads the state, judges each window against it,
    # and emits the record then the new state. A window is valid only when BOTH
    # used_percentage and resets_at are present — the header calls a missing
    # field invalid, and recording a percentage with a null boundary would make
    # the next comparison meaningless.
    if ! merged="$(printf '%s\n' "$record" \
        | jq -c --slurpfile s "$STATE" '
            . as $b
            | (($s[0] // {}) ) as $a
            | (["five_hour","seven_day"] | map(. as $w | {key: $w, value:
                ( ($a[$w] // null) as $x | ($b[$w] // null) as $y
                  | if   ($y|type) != "object" or $y.used_percentage == null
                         or $y.resets_at == null then {v: null, new: false}
                    elif ($x|type) != "object" then {v: $y, new: true}
                    elif $y.resets_at < $x.resets_at then {v: null, new: false}
                    elif $y.resets_at == $x.resets_at
                         and $y.used_percentage < $x.used_percentage then {v: null, new: false}
                    else {v: $y, new: ($y != $x)} end )})
               | from_entries) as $j
            | if ($j.five_hour.new or $j.seven_day.new | not) then empty else
                ({at: $b.at, five_hour: $j.five_hour.v, seven_day: $j.seven_day.v}),
                ({five_hour: ($j.five_hour.v // $a.five_hour),
                  seven_day: ($j.seven_day.v // $a.seven_day)})
              end' 2>/dev/null)"; then
      lock_release; trap - EXIT; return 1          # the merge itself failed
    fi
    [ -z "$merged" ] && { lock_release; trap - EXIT; return 0; }   # nothing new
    record="${merged%%$'\n'*}"
    newstate="${merged#*$'\n'}"
  fi

  if [ "${last#*,}" = "${record#*,}" ]; then
    lock_release; trap - EXIT; return 0                # unchanged
  fi

  printf '%s\n' "$record" >> "$LOG" || { lock_release; trap - EXIT; return 1; }
  chmod 600 "$LOG" 2>/dev/null
  if [ "$mode" = monotonic ]; then
    printf '%s\n' "$newstate" > "$STATE" 2>/dev/null && chmod 600 "$STATE" 2>/dev/null
  fi
  lock_release; trap - EXIT
  return 0
}

# TWO jq invocations on the hot path: this one, which turns the payload into the
# display fields and a candidate record, and the merge in append_record, which
# judges that candidate against the state file. An earlier comment claimed one,
# which was true only before the per-window merge existed. Both are needed:
# nothing can be judged before the lock is held, and the payload cannot be
# parsed twice for free.
# It emits two lines: the display fields as TSV, then the candidate as JSON. `at` is deliberately the FIRST field,
# because the change comparison drops it with `${record#*,}` — a timestamp
# contains no comma, so what remains is exactly the part that must match.
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
     five_hour: (if (.rate_limits.five_hour.used_percentage == null
                      or .rate_limits.five_hour.resets_at == null) then null else
                 { used_percentage: .rate_limits.five_hour.used_percentage,
                   resets_at:       .rate_limits.five_hour.resets_at } end),
     seven_day: (if (.rate_limits.seven_day.used_percentage == null
                      or .rate_limits.seven_day.resets_at == null) then null else
                 { used_percentage: .rate_limits.seven_day.used_percentage,
                   resets_at:       .rate_limits.seven_day.resets_at } end) } | tojson)
' 2>/dev/null)"

IFS=$'\t' read -r model dir five seven state <<< "${out%%$'\n'*}"
record="${out#*$'\n'}"

line="${model:-claude}"
[ -n "${dir:-}" ] && [ "$dir" != "-" ] && line="${line} $(basename "$dir")"

case "${state:-none}" in
  ok)
    line="${line} | 5h ${five}% 7d ${seven}%"
    umask 077
    append_record "$record" "${record#*,}" monotonic || warn=" usage-log!"
    ;;
  shape:*)
    # rate_limits present but not under the documented path. Record the key
    # NAMES so the schema can be corrected, never the values.
    keys="${state#shape:}"
    umask 077
    append_record "$(printf '{"at":"%s","unexpected_rate_limit_keys":"%s"}' "$now" "$keys")" \
                  "\"unexpected_rate_limit_keys\":\"$keys\"}" || warn=" usage-log!"
    ;;
esac

printf '%s%s' "$line" "$warn"
