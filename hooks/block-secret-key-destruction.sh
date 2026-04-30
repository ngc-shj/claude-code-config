#!/bin/bash
# PreToolUse hook: block secret/key material destruction
# Implements R31 category (e) — secret/key material destruction — at
# the harness level. Permanently destroying a KMS customer master key,
# secret, certificate, or signing material is unrecoverable and often
# unrecoverable AT ALL (no soft-delete window past the configured
# pending-deletion period). Critical severity per R31.
#
# Coverage (non-exhaustive — extend per project context via PRs):
#   AWS KMS:
#     aws kms schedule-key-deletion
#     aws kms disable-key
#     aws kms delete-alias
#   AWS Secrets Manager / SSM Parameter Store:
#     aws secretsmanager delete-secret
#     aws ssm delete-parameter | delete-parameters
#   AWS IAM credentials:
#     aws iam delete-access-key
#     aws iam delete-server-certificate
#     aws iam delete-signing-certificate
#     aws iam deactivate-mfa-device | delete-virtual-mfa-device
#   AWS Certificate Manager:
#     aws acm delete-certificate
#   GCP KMS:
#     gcloud kms keys versions destroy
#     gcloud kms keys versions disable
#   GCP Secret Manager:
#     gcloud secrets delete
#     gcloud secrets versions destroy
#   GCP IAM service accounts:
#     gcloud iam service-accounts keys delete
#   Azure Key Vault:
#     az keyvault {key,secret,certificate} delete
#     az keyvault {key,secret,certificate} purge   (BYPASSES soft-delete)
#   HashiCorp Vault:
#     vault kv delete | vault kv metadata delete
#     vault delete (general path)
#   GPG:
#     gpg --delete-secret-keys
#     gpg --delete-secret-and-public-key
#     gpg -K   (note: -K is list-secret-keys; the destructive short form
#              is --delete-secret-keys, no short alias by default)
#   Kubernetes:
#     kubectl delete secret
#
# Intentionally NOT blocked:
#   - `rm` against arbitrary key files — too broad; would catch dev/test
#     fixtures. Existing settings.json `Bash(rm *)` ask rule covers
#     direct invocations.
#   - `kubectl delete configmap` — configmaps mostly hold non-sensitive
#     config; treating them as secrets would create false positives.
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

# Substring match against the full command line; catches `bash -c`
# wrappers. Each provider gets its own alternation branch.
DENY_REGEX='(aws[[:space:]]+kms[[:space:]]+(schedule-key-deletion|disable-key|delete-alias)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+secretsmanager[[:space:]]+delete-secret\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+ssm[[:space:]]+(delete-parameter|delete-parameters)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+iam[[:space:]]+(delete-access-key|delete-server-certificate|delete-signing-certificate|deactivate-mfa-device|delete-virtual-mfa-device)\b)'
DENY_REGEX="$DENY_REGEX"'|(aws[[:space:]]+acm[[:space:]]+delete-certificate\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+kms[[:space:]]+keys[[:space:]]+versions[[:space:]]+(destroy|disable)\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+secrets[[:space:]]+(delete|versions[[:space:]]+destroy)\b)'
DENY_REGEX="$DENY_REGEX"'|(gcloud[[:space:]]+iam[[:space:]]+service-accounts[[:space:]]+keys[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(az[[:space:]]+keyvault[[:space:]]+(key|secret|certificate)[[:space:]]+(delete|purge)\b)'
DENY_REGEX="$DENY_REGEX"'|(vault[[:space:]]+kv[[:space:]]+(delete|metadata[[:space:]]+delete)\b)'
DENY_REGEX="$DENY_REGEX"'|(vault[[:space:]]+delete\b)'
DENY_REGEX="$DENY_REGEX"'|(gpg[[:space:]].*--delete-(secret-keys|secret-and-public-key)\b)'
DENY_REGEX="$DENY_REGEX"'|(kubectl[[:space:]]+delete[[:space:]]+secret(s)?\b)'

if echo "$COMMAND" | grep -qE "$DENY_REGEX"; then
  REASON='Secret/key material destruction blocked (R31 category e). Permanently destroying KMS keys, secrets, certificates, signing material, or access credentials is unrecoverable — once the pending-deletion window closes (or `purge` runs), there is no recovery. Before proceeding: (1) confirm rotation is complete and the new credential is active across ALL consumers (services, CI, peer accounts) — destroying a key while a single consumer still uses it locks them out; (2) for KMS keys, prefer scheduling deletion with the maximum window (30 days for AWS, 24 hours minimum for GCP) so a misconfiguration can be caught before destruction; (3) for keyvault `purge`, never run without the vault soft-delete window having elapsed AND a backup of the material existing somewhere recoverable; (4) for `gpg --delete-secret-keys`, ensure the corresponding public key is no longer used to encrypt active material; (5) for `kubectl delete secret`, check no Pod still mounts it and that any ServiceAccount tokens have been replaced. To override this hook locally, edit ~/.claude/settings.local.json.'
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
  exit 0
fi

echo '{"decision": "approve"}'
