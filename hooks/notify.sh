#!/bin/bash
# Notification hook: Play sound and show desktop notification (Linux)
# Uses paplay (PulseAudio) + notify-send (libnotify). All calls are best-effort;
# missing tools or unavailable audio do not propagate failures.

set -euo pipefail

INPUT=$(cat)

NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

# Resolve a sound file from the freedesktop sound theme, falling back through
# common locations. Empty result = play nothing.
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
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Claude Code" "$title" "$body" 2>/dev/null || true
}

case "$NOTIFICATION_TYPE" in
  permission_prompt)
    _play "$(_resolve_sound bell)"
    _notify "Claude Code" "Claude needs permission"
    ;;
  idle_prompt)
    _play "$(_resolve_sound message)"
    _notify "Claude Code" "Claude is waiting for input"
    ;;
esac
