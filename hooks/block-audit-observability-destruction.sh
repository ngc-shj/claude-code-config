#!/bin/bash
# PreToolUse hook: block audit log / observability destruction
# Implements R31 category (g) — audit/observability destruction — at the
# harness level. Anti-forensic verbs (deleting log groups, alert rules,
# dashboards, paging policies) are the operations an attacker — or a
# panicking remediator — would specifically run to hide evidence of a
# prior compromise. Critical severity per R31.
#
# Coverage (non-exhaustive — extend per project context via PRs):
#   AWS:
#     aws logs delete-log-group
#     aws logs delete-log-stream
#     aws logs put-retention-policy   (changing retention, often shortening)
#     aws cloudwatch delete-alarms
#     aws cloudwatch delete-dashboards
#   GCP:
#     gcloud logging logs delete
#     gcloud logging buckets delete
#     gcloud logging sinks delete
#     gcloud monitoring alert-policies delete
#     gcloud monitoring dashboards delete
#     gcloud monitoring notification-channels delete
#   Azure:
#     az monitor diagnostic-settings delete
#     az monitor action-group delete
#     az monitor metrics alert delete
#   Kubernetes (prometheus-operator CRDs):
#     kubectl delete prometheusrule(s)
#     kubectl delete servicemonitor(s)
#     kubectl delete podmonitor(s)
#     kubectl delete alertmanagerconfig(s)
#
# Best-effort tripwire — bypasses exist (base64-decoded eval, alternate
# shells, direct API calls bypassing the CLI). Primary enforcement
# remains reviewer obligation R31. Override locally via
# ~/.claude/settings.local.json.

set -euo pipefail

INPUT=$(cat)

# Single jq call: emit tool_name + Unit Separator (U+001F) + command.
# US survives jq -rj as a real 0x1F byte (unlike @tsv, which escapes
# embedded TABs as literal "\t") and is virtually never present in
# real shell commands, so the field-split is unambiguous.
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

# Substring match against full command line; catches `bash -c '...'`
# wrappers. Each provider gets its own alternation branch for clarity.
# All verb tokens use `\b` to avoid matching unrelated subcommand prefixes.
DENY_REGEX='(aws[[:space:]]+logs[[:space:]]+(delete-log-group|delete-log-stream|put-retention-policy)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+cloudwatch[[:space:]]+(delete-alarms|delete-dashboards)\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+logging[[:space:]]+(logs|buckets|sinks)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+monitoring[[:space:]]+(alert-policies|dashboards|notification-channels)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+monitor[[:space:]]+(diagnostic-settings|action-group|metrics[[:space:]]+alert)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(kubectl[[:space:]]+delete[[:space:]]+(prometheusrule|prometheusrules|servicemonitor|servicemonitors|podmonitor|podmonitors|alertmanagerconfig|alertmanagerconfigs)\b)'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='Audit/observability destruction blocked (R31 category g — anti-forensic). Deleting log groups, alert rules, dashboards, monitoring CRDs, or paging policies erases the evidence and detection capability needed to recover from an incident — and is exactly what an attacker (or a panicking remediator) would run to hide a prior compromise. Before proceeding: (1) confirm with the team that the resource is genuinely orphaned and document the deletion reason in writing; (2) for retention shortening, prefer creating a NEW policy with the desired retention, then migrating writers, before deleting the old one; (3) for alert rule cleanup during refactors, disable the rule first (via update, not delete) so the change is reversible. To override this hook locally, edit ~/.claude/settings.local.json (NOT overwritten by install.sh).'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
