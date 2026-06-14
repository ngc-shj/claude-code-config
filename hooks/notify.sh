#!/bin/bash
# Notification hook: play a sound and show a desktop notification.
# Cross-platform: macOS (afplay + osascript) and Linux (paplay/aplay + notify-send).
# All calls are best-effort — missing tools or unavailable audio never fail the hook.

set -euo pipefail

INPUT=$(cat)

NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

IS_MACOS=false
[ "$(uname)" = "Darwin" ] && IS_MACOS=true

# Resolve a Linux sound file from the freedesktop theme, trying common
# extensions/locations. Empty result = play nothing. Always succeeds (a
# non-zero return here would abort the hook under `set -e` when no file
# matches — e.g. a headless host with no sound theme installed).
_resolve_linux_sound() {
  local name="$1" c
  for c in \
    "/usr/share/sounds/freedesktop/stereo/${name}.oga" \
    "/usr/share/sounds/freedesktop/stereo/${name}.ogg" \
    "/usr/share/sounds/sound-icons/${name}.wav"; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 0
}

# _play <macos-aiff-path> <linux-freedesktop-name>
_play() {
  if $IS_MACOS; then
    afplay "$1" 2>/dev/null &
    return
  fi
  local sound; sound="$(_resolve_linux_sound "$2")"
  [ -z "$sound" ] && return
  if command -v paplay >/dev/null 2>&1; then
    paplay "$sound" 2>/dev/null &
  elif command -v aplay >/dev/null 2>&1; then
    aplay -q "$sound" 2>/dev/null &
  fi
}

# _notify <title> <body>
# Callers MUST pass static string literals. Do not interpolate hook input
# ($INPUT-derived data) without escaping — the macOS osascript path builds an
# AppleScript string by interpolation and an unescaped quote would be an
# injection sink.
_notify() {
  if $IS_MACOS; then
    osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
    return
  fi
  command -v notify-send >/dev/null 2>&1 || return 0
  # Backgrounded: notify-send makes a synchronous D-Bus call that blocks until
  # the notification is dismissed when no daemon services it, which would hang
  # the hook (and the harness).
  notify-send -a "$1" "$1" "$2" 2>/dev/null &
}

case "$NOTIFICATION_TYPE" in
  permission_prompt)
    _play /System/Library/Sounds/Ping.aiff bell
    _notify "Claude Code" "Claude needs permission"
    ;;
  idle_prompt)
    _play /System/Library/Sounds/Tink.aiff message
    _notify "Claude Code" "Claude is waiting for input"
    ;;
esac
