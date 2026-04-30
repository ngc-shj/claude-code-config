#!/bin/bash
# PreToolUse hook: block volume-destroying docker commands
# Triggered after a dev DB data-loss incident; permission-rule glob is too
# brittle for `bash -c` / quoted wrappers, so we inspect the full command
# string here. Best-effort tripwire — bypasses exist (base64-decoded eval,
# alternate shells, Docker socket directly via curl). Primary enforcement
# remains settings.json `permissions.deny` plus reviewer obligation (R31).

set -euo pipefail

INPUT=$(cat)

# Single jq call: emit tool_name + Unit Separator (U+001F) + command.
# US is chosen because (a) it survives jq -rj raw output as a real 0x1F
# byte, unlike @tsv which escapes embedded TABs as the literal "\\t",
# and (b) U+001F is virtually never present in real shell commands, so
# the field-split is unambiguous.
PARSED=$(echo "$INPUT" | jq -rj '(.tool_name // ""), "\u001f", (.tool_input.command // "")')
TOOL_NAME="${PARSED%%$'\x1f'*}"
COMMAND="${PARSED#*$'\x1f'}"

if [ "$TOOL_NAME" != "Bash" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

if [ -z "$COMMAND" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Patterns that destroy docker volumes. Substring match against the full
# command string catches `bash -c '...'`, pipelines, and many wrappers too.
# Structure of the bundled-short-flag matcher:
#   `(.*[[:space:]])(-v\b|-[a-zA-Z]*v[a-zA-Z]*\b|--volumes\b)`
# The `.*[[:space:]]` requires whitespace immediately before the flag token.
# This is what disambiguates `-v` / `-tv` (single-dash short flag clusters)
# from the second `-` of a long flag like `--remove-orphans` — the second
# `-` is not preceded by whitespace, so the bundled-short alternative
# never anchors on it. Without this anchor the regex `-[a-zA-Z]*v[a-zA-Z]*\b`
# would false-positive on `-remov` inside `--remove-orphans`.
#   - `(docker[[:space:]]+compose|docker-compose)` covers tab/multi-space.
#   - `-v\b` matches bare `-v`. `-[a-zA-Z]*v[a-zA-Z]*\b` matches bundled
#     clusters like `-tv` / `-vt` / `-tvf`. `--volumes\b` matches the long form.
DENY_REGEX='((docker[[:space:]]+compose|docker-compose)[[:space:]]+(down|rm)(.*[[:space:]])(-v\b|-[a-zA-Z]*v[a-zA-Z]*\b|--volumes\b))|(docker[[:space:]]+volume[[:space:]]+(rm|prune)\b)|(docker[[:space:]]+system[[:space:]]+prune(.*[[:space:]])(-v\b|-[a-zA-Z]*v[a-zA-Z]*\b|--volumes\b))'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='Destructive docker-volume operation blocked. This rule exists because a previous session caused dev DB data loss via `docker compose down -v`. To override (in priority order): (1) edit ~/.claude/settings.local.json to remove or reorder this hook (settings.local.json is NOT overwritten by install.sh and survives reinstall); (2) for one-shot use, swap the destructive op for a targeted alternative (e.g., `docker compose rm -f -s <service>` keeps the volume; `docker volume rm <named-volume>` requires explicit naming); (3) edit settings.json in the repo and re-run install.sh. Do NOT comment out the entry directly in ~/.claude/settings.json — install.sh will silently re-enable the block on next install.'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
