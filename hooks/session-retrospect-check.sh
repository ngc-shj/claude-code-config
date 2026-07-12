#!/bin/bash
# SessionStart hook — surfaces a once-per-day prompt when retrospective
# mining is due for one or more configured sources.
#
# This hook is a pure pipe over hooks/retro-state.sh: it reads no files
# directly and never compares dates itself (the once-per-day suppression
# and the interval math both live in retro-state.sh, under its RETRO_NOW
# clock seam). Any internal error degrades to silent exit 0 — a broken
# SessionStart hook must never block a session from starting.
#
# stdin:  Claude Code SessionStart JSON
#         {session_id, transcript_path, cwd, hook_event_name, source}
# stdout: either nothing, or exactly one line —
#         {"hookSpecificOutput":{"hookEventName":"SessionStart",
#          "additionalContext":"…"}}
#
# Env: RETRO_CONFIG, RETRO_STATE (passed through to retro-state.sh)
#
# Forbidden in this file: network fetches, LLM calls, filesystem scans —
# session-start latency budget; this hook talks to retro-state.sh only.

set -u

HOOK_DIR="$(dirname "${BASH_SOURCE[0]}")"
RETRO_STATE_CLI="$HOOK_DIR/retro-state.sh"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$RETRO_STATE_CLI" ] || exit 0

INPUT="$(cat)"
SOURCE="$(jq -r '.source // empty' <<<"$INPUT" 2>/dev/null)" || exit 0

CONFIG="$(bash "$RETRO_STATE_CLI" config --json 2>/dev/null)" || exit 0
[ -n "$CONFIG" ] || exit 0
jq -e . >/dev/null 2>&1 <<<"$CONFIG" || exit 0

PROMPT_SOURCES="$(jq -c '.prompt_sources // ["startup"]' <<<"$CONFIG" 2>/dev/null)" || exit 0
jq -e --arg s "$SOURCE" 'index($s) != null' >/dev/null 2>&1 <<<"$PROMPT_SOURCES" || exit 0

DUE_JSON="$(bash "$RETRO_STATE_CLI" due --json --prompt-guard 2>/dev/null)" || exit 0
[ -n "$DUE_JSON" ] || exit 0
jq -e . >/dev/null 2>&1 <<<"$DUE_JSON" || exit 0

# Redundant depth: only names from the closed source set may ever reach
# the emitted context, even if retro-state.sh's own filtering is bypassed.
DUE_SOURCES="$(jq -c '[.[] | select(. == "artifacts" or . == "github" or . == "transcripts" or . == "scout")]' <<<"$DUE_JSON" 2>/dev/null)" || exit 0
[ -n "$DUE_SOURCES" ] || exit 0
jq -e 'length > 0' >/dev/null 2>&1 <<<"$DUE_SOURCES" || exit 0

bash "$RETRO_STATE_CLI" mark-prompted >/dev/null 2>&1

SOURCE_LIST="$(jq -r 'join(", ")' <<<"$DUE_SOURCES" 2>/dev/null)" || exit 0
[ -n "$SOURCE_LIST" ] || exit 0

MESSAGE="Retrospective mining is due for: ${SOURCE_LIST}. Ask the user whether to run the retrospect skill now to mine lessons from these sources. If the user declines, offer to snooze a source with: bash ~/.claude/hooks/retro-state.sh snooze <source>"

jq -n --arg ctx "$MESSAGE" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' \
  2>/dev/null || exit 0

exit 0
