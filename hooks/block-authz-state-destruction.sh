#!/bin/bash
# PreToolUse hook: block authorization-state destruction
# Implements R31 category (f) — authorization-state destruction — at
# the harness level. Removing roles, role bindings, IAM policies,
# group memberships, or service accounts can lock out legitimate
# operators (immediate denial-of-service) and break runtime auth
# (services that depend on the role/binding fail to authenticate).
# Critical severity per R31.
#
# Coverage (non-exhaustive — extend per project context via PRs):
#   AWS IAM:
#     aws iam delete-role | delete-role-policy | detach-role-policy
#     aws iam delete-policy | delete-policy-version
#     aws iam delete-group | remove-user-from-group
#     aws iam delete-user-policy | detach-user-policy
#     aws iam delete-user
#     aws iam delete-instance-profile |
#         remove-role-from-instance-profile
#   GCP IAM:
#     gcloud iam roles delete
#     gcloud iam service-accounts delete
#     gcloud projects remove-iam-policy-binding
#     gcloud projects set-iam-policy   (REPLACES entire policy — risky)
#     gcloud organizations remove-iam-policy-binding
#     gcloud resource-manager folders remove-iam-policy-binding
#   Azure RBAC / AAD:
#     az role assignment delete
#     az role definition delete
#     az ad group delete | az ad group member remove
#     az ad sp delete   (service principal delete)
#   Kubernetes RBAC:
#     kubectl delete {role, rolebinding, clusterrole,
#                     clusterrolebinding, serviceaccount} + plurals
#
# Best-effort tripwire — bypasses exist (base64-decoded eval, alternate
# shells, direct cloud-provider API calls). Override locally via
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

DENY_REGEX='(aws[[:space:]]+iam[[:space:]]+(delete-role|delete-role-policy|detach-role-policy|delete-policy|delete-policy-version|delete-group|remove-user-from-group|delete-user-policy|detach-user-policy|delete-user|delete-instance-profile|remove-role-from-instance-profile)\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+iam[[:space:]]+(roles|service-accounts)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+(projects|organizations|resource-manager[[:space:]]+folders)[[:space:]]+(remove-iam-policy-binding|set-iam-policy)\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+role[[:space:]]+(assignment|definition)[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+ad[[:space:]]+(group[[:space:]]+(delete|member[[:space:]]+remove)|sp[[:space:]]+delete)\b)'
DENY_REGEX="$DENY_REGEX"'|(kubectl[[:space:]]+delete[[:space:]]+(role|roles|rolebinding|rolebindings|clusterrole|clusterroles|clusterrolebinding|clusterrolebindings|serviceaccount|serviceaccounts)\b)'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='Authorization-state destruction blocked (R31 category f). Removing a role, role binding, IAM policy attachment, group membership, or service account can immediately lock out legitimate operators and break runtime auth for services that depend on the binding. The over-privilege-revocation direction is Critical because it produces denial-of-service that surfaces only when the affected actor next tries to authenticate. Before proceeding: (1) identify ALL principals (users, services, CI runners, peer accounts) that depend on this binding — the binding may grant access transitively; (2) verify a replacement is in place AND active before removing the existing one (rotate, do not revoke); (3) for `gcloud projects set-iam-policy`, prefer `add-iam-policy-binding` / `remove-iam-policy-binding` for surgical changes — `set-iam-policy` REPLACES the entire policy and silently drops anything not in the new copy; (4) for `kubectl delete clusterrolebinding system:*` or similar built-in bindings, do NOT proceed without an offline confirmation — these often gate kube-controller-manager itself and removing one can render the cluster unrecoverable. To override this hook locally, edit ~/.claude/settings.local.json.'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
