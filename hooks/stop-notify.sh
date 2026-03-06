#!/bin/bash
# Stop hook: Notify when Claude finishes a response
# Useful when running long tasks and multitasking

set -euo pipefail

INPUT=$(cat)

STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty')

case "$STOP_REASON" in
  end_turn)
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    osascript -e 'display notification "Task complete" with title "Claude Code"' 2>/dev/null || true
    ;;
  max_tokens)
    afplay /System/Library/Sounds/Sosumi.aiff 2>/dev/null &
    osascript -e 'display notification "Stopped: max tokens reached" with title "Claude Code" subtitle "Response may be incomplete"' 2>/dev/null || true
    ;;
esac
