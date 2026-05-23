#!/bin/bash
# Stop hook: Notify when Claude finishes a response (Linux)
# Uses paplay (PulseAudio) + notify-send (libnotify). All calls are best-effort.

set -euo pipefail

INPUT=$(cat)

STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty')

_resolve_sound() {
  local name="$1"
  local candidates=(
    "/usr/share/sounds/freedesktop/stereo/${name}.oga"
    "/usr/share/sounds/freedesktop/stereo/${name}.ogg"
    "/usr/share/sounds/sound-icons/${name}.wav"
  )
  for c in "${candidates[@]}"; do
    [ -f "$c" ] && { echo "$c"; return; }
  done
}

_play() {
  local sound="$1"
  [ -z "$sound" ] && return
  if command -v paplay >/dev/null 2>&1; then
    paplay "$sound" 2>/dev/null &
  elif command -v aplay >/dev/null 2>&1; then
    aplay -q "$sound" 2>/dev/null &
  fi
}

_notify() {
  local title="$1"
  local body="$2"
  local urgency="${3:-normal}"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Claude Code" -u "$urgency" "$title" "$body" 2>/dev/null || true
}

case "$STOP_REASON" in
  end_turn)
    _play "$(_resolve_sound complete)"
    _notify "Claude Code" "Task complete"
    ;;
  max_tokens)
    _play "$(_resolve_sound dialog-warning)"
    _notify "Claude Code" "Stopped: max tokens reached (response may be incomplete)" critical
    ;;
esac
