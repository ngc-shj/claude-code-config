#!/usr/bin/env bash
# Status line that also records the plan's rate-limit percentages.
#
# Why this exists: `/usage` prints a percentage and forgets it. Nothing local
# keeps a timestamped history, so the cost of a batch cannot be recovered once
# it is over. This log is that history — ordered, per window, monotonically
# filtered — and two of its lines can be subtracted.
#
# IT WAS ALSO BUILT FOR SUB-PERCENT RESOLUTION, AND THAT PREMISE HAS NOT HELD.
# `/usage` floors to integers while the payload appeared to carry decimals, but
# across the first 27 logged readings every value was a whole percent, and the
# two that looked otherwise — 14.000000000000002 and 28.000000000000004 — are
# `0.14 * 100` and `0.28 * 100` to the bit. The server quantizes to 1% and
# scales; the trailing digits are float noise, not precision. So read the
# resolution as 1% of the window until a reading arrives that is not a whole
# percent. This hook rounds nothing, which is what leaves that falsifiable:
# such a reading would be logged exactly as it came. tests/ pins it.
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

# $1 record JSON, $2 "monotonic" to judge each window against the baseline.
#
# The baseline for that judgement is a STATE file holding the last accepted
# value per window. A slice of the log will not do: scanning the last N lines
# made "reject a value that went backwards" depend on N, since advancing one
# window past the lookback let a stale reading of the OTHER window through.
#
# Two files mean a consistency problem, and the state is therefore
# SELF-VALIDATING: its FIRST line is the log line that was current when it was
# written, and its second is the baseline. Two plain lines rather than one JSON
# object so that reading and writing it costs no jq — the hot path stays at two
# invocations, the payload parse and the merge. If that does not match the log's actual last line — because a state
# write failed, or the log was edited — the state is rebuilt from the log
# before anything is judged against it. A failed state write is reported AND
# repairs itself on the next render, rather than silently biasing every
# comparison that follows.
append_record() {
  local record="$1" mode="${2:-}" last merged newstate state_tail baseline

  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 1
  lock_acquire || return 1
  trap 'lock_release' EXIT
  _fail() { lock_release; trap - EXIT; return 1; }
  _done() { lock_release; trap - EXIT; return 0; }

  # Before any early return: umask governs creation only, so a file predating
  # this guard keeps its old mode forever — and the unchanged and stale paths,
  # the common ones, both leave before the append. The state carries the same
  # figures as the log and gets the same treatment.
  [ -e "$LOG" ]   && { chmod 600 "$LOG"   2>/dev/null || { _fail; return 1; }; }
  [ -e "$STATE" ] && { chmod 600 "$STATE" 2>/dev/null || { _fail; return 1; }; }

  last="$(tail -n 1 "$LOG" 2>/dev/null)"

  if [ "$mode" = monotonic ]; then
    # Rebuild whenever the state is missing or does not answer for the log as
    # it stands now. A rebuild that FAILS over a non-empty log is fatal: there
    # is a history and we cannot read it, so continuing with no baseline would
    # accept anything. Only an empty log yields an empty baseline.
    state_tail=""; baseline=""
    # -s first: `wc -l < missing` reports the open() failure to the terminal
    # before 2>/dev/null is in effect, because bash applies redirections in order.
    if [ -s "$STATE" ] && [ "$(wc -l 2>/dev/null < "$STATE")" -eq 2 ]; then
      state_tail="$(head -n 1 "$STATE" 2>/dev/null)"
      baseline="$(tail -n 1 "$STATE" 2>/dev/null)"
    fi
    if [ -z "$baseline" ] || [ "$state_tail" != "$last" ]; then
      if [ -s "$LOG" ]; then
        baseline="$(jq -sc '
             { five_hour: ([.[] | .five_hour | select(type=="object")] | last),
               seven_day: ([.[] | .seven_day | select(type=="object")] | last) }' \
             "$LOG" 2>/dev/null)" || { _fail; return 1; }
        [ -z "$baseline" ] && { _fail; return 1; }
      else
        baseline='{}'
      fi
      printf '%s\n%s\n' "$last" "$baseline" > "$STATE.tmp" 2>/dev/null || { _fail; return 1; }
      mv -f "$STATE.tmp" "$STATE" 2>/dev/null || { _fail; return 1; }
      chmod 600 "$STATE" 2>/dev/null
    fi

    # One jq for the merge: it reads the state, judges each window against it,
    # and emits the record then the new state. A window is valid only when BOTH
    # used_percentage and resets_at are present — the header calls a missing
    # field invalid, and a percentage recorded against a null boundary makes
    # every later comparison against it meaningless.
    if ! merged="$(printf '%s\n' "$record" \
        | jq -c --argjson a "$baseline" '
            . as $b
            | (["five_hour","seven_day"] | map(. as $w | {key: $w, value:
                ( ($a[$w] // null) as $x | ($b[$w] // null) as $y
                  | if   ($y|type) != "object" or $y.used_percentage == null
                         or $y.resets_at == null then {v: null, new: false}
                    elif ($x|type) != "object" then {v: $y, new: true}
                    # The status-line payload rounds some reset instants while
                    # /api/oauth/usage returns fractional ISO timestamps. The
                    # same boundary has been observed one second apart. Since
                    # real window boundaries are hours apart, canonicalise a
                    # +/-1s difference to the accepted boundary before the
                    # monotonic comparison.
                    elif (($y.resets_at - $x.resets_at) | fabs) <= 1 then
                      ($y + {resets_at: $x.resets_at}) as $z
                      | if $z.used_percentage < $x.used_percentage
                        then {v: null, new: false}
                        else {v: $z, new: ($z != $x)} end
                    elif $y.resets_at < $x.resets_at then {v: null, new: false}
                    else {v: $y, new: ($y != $x)} end )})
               | from_entries) as $j
            | if ($j.five_hour.new or $j.seven_day.new | not) then empty else
                ({at: $b.at, five_hour: $j.five_hour.v, seven_day: $j.seven_day.v}),
                ({five_hour: ($j.five_hour.v // $a.five_hour),
                  seven_day: ($j.seven_day.v // $a.seven_day)})
              end' 2>/dev/null)"; then
      _fail; return 1
    fi
    [ -z "$merged" ] && { _done; return 0; }          # nothing new
    record="${merged%%$'\n'*}"
    newstate="${merged#*$'\n'}"
  fi

  [ "${last#*,}" = "${record#*,}" ] && { _done; return 0; }

  printf '%s\n' "$record" >> "$LOG" || { _fail; return 1; }
  chmod 600 "$LOG" 2>/dev/null

  if [ "$mode" = monotonic ]; then
    # Atomic, and fatal if it fails: the log has moved and a state left behind
    # would judge the next reading against a value that is no longer the
    # latest. The self-validation above repairs it on the next render, and the
    # status line says so now.
    printf '%s\n%s\n' "$record" "$newstate" > "$STATE.tmp" 2>/dev/null || { _fail; return 1; }
    mv -f "$STATE.tmp" "$STATE" 2>/dev/null || { _fail; return 1; }
    chmod 600 "$STATE" 2>/dev/null
  fi

  _done
  return 0
}

# TWO jq invocations on the hot path, and only two: this one, which turns the
# payload into the display fields and a candidate record, and the merge in
# append_record, which judges that candidate against the baseline. Reading and
# writing the state costs none, which is why it is two plain lines rather than
# a JSON object. A rebuild adds a third, and happens once per inconsistency.
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
    append_record "$record" monotonic || warn=" usage-log!"
    ;;
  shape:*)
    # rate_limits present but not under the documented path. Record the key
    # NAMES so the schema can be corrected, never the values.
    keys="${state#shape:}"
    umask 077
    append_record "$(printf '{"at":"%s","unexpected_rate_limit_keys":"%s"}' "$now" "$keys")" \
      || warn=" usage-log!"
    ;;
esac

printf '%s%s' "$line" "$warn"
