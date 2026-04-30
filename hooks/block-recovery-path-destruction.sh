#!/bin/bash
# PreToolUse hook: block recovery-path destruction
# Implements R31 category (h) — recovery-path destruction — at the
# harness level. Deleting a backup, snapshot, recovery point, or
# shortening a PITR window eliminates the rollback path before any
# subsequent destructive op runs. Critical severity per R31. The
# operation an attacker would specifically run to make a follow-up
# data-destroying action irreversible.
#
# Coverage (non-exhaustive — extend per project context via PRs):
#   AWS:
#     aws backup delete-recovery-point | delete-backup-plan |
#                 delete-backup-vault | delete-backup-selection
#     aws ec2 delete-snapshot
#     aws rds delete-db-snapshot | delete-db-cluster-snapshot
#     aws rds modify-db-instance | modify-db-cluster
#                                 (with --backup-retention-period —
#                                  flagged regardless of value, since
#                                  shortening from 35 to 7 still erodes
#                                  the recovery window)
#   GCP:
#     gcloud compute snapshots delete
#     gcloud sql backups delete
#     gcloud sql instances patch ... --backup-start-time / --no-backup
#   Azure:
#     az snapshot delete
#     az backup {vault,item,policy} delete
#   Kubernetes:
#     kubectl delete volumesnapshot(s)
#     kubectl delete pv (persistent volumes — they often back
#                        snapshot data; deleting frees the storage)
#
# Intentionally NOT blocked:
#   - `terraform destroy` — heavily used in dev/CI for ephemeral
#     environments. Hook is repo-context-blind so blocking here would
#     produce constant false positives. R31 reviewer-text obligation
#     remains the primary control for production-state destroys.
#   - `kubectl delete pvc` — overlap with R31 (a) data-volume
#     destruction; defer to that category's future hook expansion.
#
# Best-effort tripwire — bypasses exist (base64-decoded eval, alternate
# shells, direct cloud-provider API calls bypassing the CLI). Override
# locally via ~/.claude/settings.local.json.

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

# Substring match against the full command line; catches `bash -c`
# wrappers. Each provider gets its own alternation branch.
DENY_REGEX='(aws[[:space:]]+backup[[:space:]]+(delete-recovery-point|delete-backup-plan|delete-backup-vault|delete-backup-selection)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+ec2[[:space:]]+delete-snapshot\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+rds[[:space:]]+(delete-db-snapshot|delete-db-cluster-snapshot)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+rds[[:space:]]+(modify-db-instance|modify-db-cluster)[[:space:]].*--backup-retention-period\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+compute[[:space:]]+snapshots[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+sql[[:space:]]+backups[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+patch[[:space:]].*(--no-backup|--backup-start-time)\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+snapshot[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+backup[[:space:]]+(vault|item|policy)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(kubectl[[:space:]]+delete[[:space:]]+(volumesnapshot|volumesnapshots|pv|persistentvolume|persistentvolumes)\b)'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='Recovery-path destruction blocked (R31 category h). Deleting a backup, snapshot, recovery point, or shortening a PITR/backup-retention window eliminates the rollback path. This is the operation that makes a subsequent destructive action irreversible — exactly what an attacker (or a panicking remediator) would run before destroying the live data. Before proceeding: (1) verify the backup is genuinely orphaned and document the retention-policy rationale (compliance windows often require minimum retention); (2) for retention shortening, prefer creating a new policy with the desired window, then migrating, then deleting the old — never directly modify the existing window without coordination; (3) for kubectl pv / volumesnapshot deletion, check that no PVC still claims the volume and that the snapshot has a successor in the chain. Note: `terraform destroy` is intentionally NOT blocked by this hook (too noisy in dev/CI); reviewer obligation R31 remains the primary control for production-state destroys. To override this hook locally, edit ~/.claude/settings.local.json.'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
