#!/bin/bash
# State CLI for the retrospect skill — the single owner of the retrospect
# state file and the single trusted read path for the retrospect config.
#
# State:  ~/.claude/state/retrospect.json   (override: RETRO_STATE)
# Config: ~/.claude/retrospect.config.json  (override: RETRO_CONFIG)
# Clock:  RETRO_NOW (epoch seconds) overrides `date +%s` — every time
#         comparison in this CLI (due, snooze expiry, prompt guard) derives
#         from it, so tests pin absolute timestamps deterministically.
#
# Subcommands:
#   seed [--high-water <source>=<value>]...
#       Create state (all sources last_run=now) iff absent. --high-water is
#       applied EVEN when state exists (state-loss recovery; touches only
#       high_water, never last_run). Values are shape-validated by the same
#       chokepoint as mark-run. artifacts/github scalars expand to an object
#       over the currently configured repos; transcripts stays scalar;
#       scout=... is rejected (exit 2) — hash cursors cannot be seeded.
#   due [--json] [--prompt-guard]
#       Enabled sources with now - last_run >= interval_days*86400 and not
#       snoozed. A missing state entry — or a missing/untrusted state FILE —
#       means due. --prompt-guard emits nothing when last_prompted == today.
#   mark-prompted
#   mark-run <source> [--high-water-file <path>]
#       last_run=now (creates the entry if missing); the file's JSON value
#       replaces high_water after jq syntax + per-source shape validation.
#   snooze <source> [days]        (default: config snooze_days, else 3)
#   show [--json]
#   config [--json]
#       Emit the config iff it is a regular, non-symlink, user-owned file;
#       unknown source keys are dropped with a stderr note (closed set).
#
# Exit codes: 0 ok / 1 validation failure (state untouched) / 2 usage error.
#
# Trust boundary: state and config are honored only as regular, non-symlink,
# user-owned files (same invariant as _llm_trusted_file in llm-utils.sh —
# the predicate is 3 lines and re-stated here to avoid sourcing the LLM
# discovery side effects). Corrupt state JSON is quarantined alongside the
# state file and reseeded; writes are atomic (mktemp + mv, never through a
# symlink).

set -u

CONFIG="${RETRO_CONFIG:-$HOME/.claude/retrospect.config.json}"
STATE="${RETRO_STATE:-$HOME/.claude/state/retrospect.json}"
KNOWN_SOURCES='["artifacts","github","transcripts","scout"]'

usage() {
  cat >&2 <<'EOF'
Usage: retro-state.sh <subcommand>
  seed [--high-water <source>=<value>]...   create state; apply/repair cursors
  due [--json] [--prompt-guard]             list due sources
  mark-prompted                             record today's prompt
  mark-run <source> [--high-water-file <p>] record a run (+validated cursor)
  snooze <source> [days]                    suppress a source temporarily
  show [--json]                             print state
  config [--json]                           print trusted, filtered config
Sources: artifacts | github | transcripts | scout
Env: RETRO_CONFIG, RETRO_STATE, RETRO_NOW (epoch seconds; test clock seam)
EOF
}

_now() { printf '%s' "${RETRO_NOW:-$(date +%s)}"; }
_now_iso() { jq -nr --argjson n "$(_now)" '$n | todate'; }
_today() { jq -nr --argjson n "$(_now)" '$n | todate | .[0:10]'; }

_trusted_file() {
  [ -f "$1" ] && ! [ -L "$1" ] && [ -O "$1" ]
}

_known_source() {
  case "$1" in
    artifacts|github|transcripts|scout) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit the trusted, closed-set-filtered config document; empty when the
# config is absent or fails the trust gate.
_config_json() {
  _trusted_file "$CONFIG" || return 0
  local raw dropped
  raw=$(jq -c . "$CONFIG" 2>/dev/null) || {
    echo "retro-state: config is not valid JSON: $CONFIG" >&2
    return 0
  }
  dropped=$(jq -r --argjson known "$KNOWN_SOURCES" \
    '(.sources // {}) | keys[] | select(. as $k | $known | index($k) | not)' <<<"$raw")
  if [ -n "$dropped" ]; then
    echo "retro-state: ignoring unknown source key(s): $(printf '%s' "$dropped" | tr '\n' ' ')" >&2
  fi
  jq -c --argjson known "$KNOWN_SOURCES" \
    '.sources = ((.sources // {}) | with_entries(select(.key as $k | $known | index($k))))' \
    <<<"$raw"
}

_fresh_state() {
  jq -nc --arg now "$(_now_iso)" --argjson known "$KNOWN_SOURCES" \
    '{version: 1, last_prompted: null,
      sources: ($known | map({key: ., value: {last_run: $now, high_water: null, snoozed_until: null}}) | from_entries)}'
}

# Atomic write; never through a symlink.
_write_state() {
  local doc="$1" dir tmp
  dir=$(dirname "$STATE")
  mkdir -p -m 0700 "$dir" 2>/dev/null || true
  if [ -L "$STATE" ]; then
    echo "retro-state: refusing to write through symlinked state file: $STATE" >&2
    return 1
  fi
  tmp=$(mktemp "$dir/.retrospect.XXXXXX") || return 1
  printf '%s\n' "$doc" > "$tmp"
  chmod 0600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$STATE"
}

# Emit the state document. An absent or untrusted state file emits nothing
# (readers treat that as "no state"). Corrupt JSON is quarantined and
# reseeded, then the fresh document is emitted.
_state_json() {
  [ -e "$STATE" ] || return 0
  if ! _trusted_file "$STATE"; then
    echo "retro-state: state file failed the trust gate (symlink/non-regular/foreign-owned); treating as absent" >&2
    return 0
  fi
  if ! jq -e . "$STATE" >/dev/null 2>&1; then
    local quarantine="${STATE}.corrupt.$(_now)"
    mv "$STATE" "$quarantine" 2>/dev/null || true
    echo "retro-state: corrupt state quarantined to $quarantine; reseeding" >&2
    _write_state "$(_fresh_state)" || return 0
  fi
  cat "$STATE" 2>/dev/null
}

_is_iso() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?$ ]]
}

_norm_iso() {
  if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf '%sT00:00:00Z' "$1"
  else
    printf '%s' "$1"
  fi
}

# Shape-validate a high_water JSON value for a source — the single
# chokepoint for EVERY high_water writer (mark-run and seed).
#   artifacts:   object; keys string-equal to configured repos; ISO values
#   github:      object; keys owner/repo; ISO values
#   transcripts: ISO string
#   scout:       object; keys among configured urls; sha256 values
_validate_hw() {
  local source="$1" hw="$2" cfg="$3" key val
  case "$source" in
    transcripts)
      jq -e 'type == "string"' <<<"$hw" >/dev/null 2>&1 || return 1
      _is_iso "$(jq -r . <<<"$hw")" || return 1
      ;;
    artifacts|github|scout)
      jq -e 'type == "object"' <<<"$hw" >/dev/null 2>&1 || return 1
      while IFS= read -r key; do
        case "$source" in
          artifacts)
            jq -e --arg k "$key" '.sources.artifacts.repos // [] | index($k)' \
              <<<"$cfg" >/dev/null 2>&1 || return 1
            ;;
          github)
            [[ "$key" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
            ;;
          scout)
            jq -e --arg k "$key" '.sources.scout.urls // [] | index($k)' \
              <<<"$cfg" >/dev/null 2>&1 || return 1
            ;;
        esac
      done < <(jq -r 'keys[]' <<<"$hw")
      while IFS= read -r val; do
        case "$source" in
          scout) [[ "$val" =~ ^[0-9a-f]{64}$ ]] || return 1 ;;
          *) _is_iso "$val" || return 1 ;;
        esac
      done < <(jq -r '.[]' <<<"$hw")
      ;;
    *) return 1 ;;
  esac
  return 0
}

cmd_seed() {
  local cfg state pairs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --high-water)
        [ $# -ge 2 ] || { echo "retro-state: --high-water needs <source>=<value>" >&2; return 2; }
        pairs+=("$2"); shift 2 ;;
      *) echo "retro-state: unknown seed argument: $1" >&2; return 2 ;;
    esac
  done

  cfg=$(_config_json)
  state=$(_state_json)
  if [ -z "$state" ]; then
    state=$(_fresh_state)
  elif [ ${#pairs[@]} -eq 0 ]; then
    # Existing state, nothing to apply — idempotent no-op.
    return 0
  fi

  local pair source value hw
  for pair in ${pairs[@]+"${pairs[@]}"}; do
    source="${pair%%=*}"
    value="${pair#*=}"
    if ! _known_source "$source"; then
      echo "retro-state: unknown source: $source" >&2; return 2
    fi
    if [ "$source" = "scout" ]; then
      echo "retro-state: scout high-water cannot be seeded (url->sha256 map has no scalar form); omit it — the next run re-fetches all URLs" >&2
      return 2
    fi
    if ! _is_iso "$value"; then
      echo "retro-state: invalid high-water value for $source: $value (need ISO-8601)" >&2
      return 1
    fi
    value=$(_norm_iso "$value")
    case "$source" in
      transcripts)
        hw=$(jq -nc --arg v "$value" '$v')
        ;;
      artifacts|github)
        hw=$(jq -c --arg v "$value" '.sources.'"$source"'.repos // [] | map({key: ., value: $v}) | from_entries' <<<"${cfg:-null}")
        ;;
    esac
    if ! _validate_hw "$source" "$hw" "${cfg:-null}"; then
      echo "retro-state: high-water for $source failed shape validation; state untouched" >&2
      return 1
    fi
    state=$(jq -c --arg s "$source" --argjson hw "$hw" \
      '.sources[$s] = ((.sources[$s] // {last_run: null, high_water: null, snoozed_until: null}) | .high_water = $hw)' \
      <<<"$state")
  done

  _write_state "$state"
}

cmd_due() {
  local as_json=0 guard=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --prompt-guard) guard=1; shift ;;
      *) echo "retro-state: unknown due argument: $1" >&2; return 2 ;;
    esac
  done

  local cfg state now
  cfg=$(_config_json)
  if [ -z "$cfg" ]; then
    [ "$as_json" -eq 1 ] && echo '[]'
    return 0
  fi
  state=$(_state_json)
  [ -n "$state" ] || state='null'
  now=$(_now)

  if [ "$guard" -eq 1 ]; then
    local lp
    lp=$(jq -r '.last_prompted // ""' <<<"$state" 2>/dev/null)
    if [ "$lp" = "$(_today)" ]; then
      [ "$as_json" -eq 1 ] && echo '[]'
      return 0
    fi
  fi

  local due
  # Each source's date arithmetic is wrapped in try/catch so one malformed
  # timestamp (a hand-edited last_run / snoozed_until that is valid JSON but
  # not ISO-8601) cannot abort the whole array comprehension and silently
  # report nothing-due for EVERY source. A source with an unparseable cursor
  # is treated as due (fail toward more mining, never toward silently skipping).
  due=$(jq -c --argjson now "$now" --argjson state "$state" '
    [ (.sources | to_entries[])
      | select(.value.enabled == true)
      | .key as $k
      | ((.value.interval_days // 7) * 86400) as $ivl
      | (($state.sources? // {})[$k] // null) as $e
      | if $e == null or ($e.last_run // null) == null then $k
        # A malformed snoozed_until must be treated as EXPIRED (catch -> $now,
        # which is not > $now), never as far-future — otherwise one bad value
        # would suppress the source forever. A malformed last_run is treated as
        # past the interval (catch -> $ivl), i.e. due. Both fail toward mining.
        elif (($e.snoozed_until // null) != null)
             and ((try ($e.snoozed_until | fromdateiso8601) catch $now) > $now) then empty
        elif ((try ($now - ($e.last_run | fromdateiso8601)) catch $ivl) >= $ivl) then $k
        else empty
        end ]' <<<"$cfg") || due='[]'

  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$due"
  else
    jq -r '.[]' <<<"$due"
  fi
}

cmd_mark_prompted() {
  local state
  state=$(_state_json)
  [ -n "$state" ] || state=$(_fresh_state)
  state=$(jq -c --arg t "$(_today)" '.last_prompted = $t' <<<"$state")
  _write_state "$state"
}

cmd_mark_run() {
  local source="${1:-}" hw_file=""
  [ -n "$source" ] || { echo "retro-state: mark-run needs a source" >&2; return 2; }
  _known_source "$source" || { echo "retro-state: unknown source: $source" >&2; return 2; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --high-water-file)
        [ $# -ge 2 ] || { echo "retro-state: --high-water-file needs a path" >&2; return 2; }
        hw_file="$2"; shift 2 ;;
      *) echo "retro-state: unknown mark-run argument: $1" >&2; return 2 ;;
    esac
  done

  local cfg state hw=""
  cfg=$(_config_json)
  if [ -n "$hw_file" ]; then
    hw=$(jq -c . "$hw_file" 2>/dev/null) || {
      echo "retro-state: high-water file is not valid JSON: $hw_file; state untouched" >&2
      return 1
    }
    if ! _validate_hw "$source" "$hw" "${cfg:-null}"; then
      echo "retro-state: high-water for $source failed shape validation; state untouched" >&2
      return 1
    fi
  fi

  state=$(_state_json)
  [ -n "$state" ] || state=$(_fresh_state)
  state=$(jq -c --arg s "$source" --arg now "$(_now_iso)" \
    '.sources[$s] = ((.sources[$s] // {high_water: null, snoozed_until: null}) | .last_run = $now)' \
    <<<"$state")
  if [ -n "$hw" ]; then
    state=$(jq -c --arg s "$source" --argjson hw "$hw" '.sources[$s].high_water = $hw' <<<"$state")
  fi
  _write_state "$state"
}

cmd_snooze() {
  local source="${1:-}" days="${2:-}"
  [ -n "$source" ] || { echo "retro-state: snooze needs a source" >&2; return 2; }
  _known_source "$source" || { echo "retro-state: unknown source: $source" >&2; return 2; }
  if [ -z "$days" ]; then
    days=$(_config_json | jq -r '.snooze_days // 3' 2>/dev/null)
    [ -n "$days" ] || days=3
  fi
  case "$days" in
    ''|*[!0-9]*) echo "retro-state: snooze days must be a positive integer" >&2; return 2 ;;
  esac

  local state until
  state=$(_state_json)
  [ -n "$state" ] || state=$(_fresh_state)
  until=$(jq -nr --argjson n "$(_now)" --argjson d "$days" '($n + $d * 86400) | todate')
  state=$(jq -c --arg s "$source" --arg u "$until" \
    '.sources[$s] = ((.sources[$s] // {last_run: null, high_water: null}) | .snoozed_until = $u)' \
    <<<"$state")
  _write_state "$state"
}

cmd_show() {
  local as_json=0
  [ "${1:-}" = "--json" ] && as_json=1
  local state
  state=$(_state_json)
  if [ -z "$state" ]; then
    [ "$as_json" -eq 0 ] && echo "retro-state: no state file at $STATE (run: retro-state.sh seed)" >&2
    return 0
  fi
  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$state"
  else
    jq . <<<"$state"
  fi
}

cmd_config() {
  local cfg
  cfg=$(_config_json)
  [ -n "$cfg" ] || return 0
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$cfg"
  else
    jq . <<<"$cfg"
  fi
}

command -v jq >/dev/null 2>&1 || {
  echo "retro-state: jq is required" >&2
  exit 0
}

case "${1:-}" in
  seed)          shift; cmd_seed "$@" ;;
  due)           shift; cmd_due "$@" ;;
  mark-prompted) shift; cmd_mark_prompted "$@" ;;
  mark-run)      shift; cmd_mark_run "$@" ;;
  snooze)        shift; cmd_snooze "$@" ;;
  show)          shift; cmd_show "$@" ;;
  config)        shift; cmd_config "$@" ;;
  *)             usage; exit 2 ;;
esac
