#!/bin/bash
# Notification hook: Play sound and show desktop notification
# Works on macOS; Linux users should replace with notify-send

set -euo pipefail

INPUT=$(cat)

NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

case "$NOTIFICATION_TYPE" in
  permission_prompt)
    afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
    osascript -e 'display notification "Claude needs permission" with title "Claude Code"' 2>/dev/null || true
    ;;
  idle_prompt)
    afplay /System/Library/Sounds/Tink.aiff 2>/dev/null &
    osascript -e 'display notification "Claude is waiting for input" with title "Claude Code"' 2>/dev/null || true
    ;;
esac
