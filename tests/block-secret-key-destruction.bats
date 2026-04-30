#!/usr/bin/env bats
# Tests for hooks/block-secret-key-destruction.sh — R31 (e) verbs that
# destroy KMS keys, secrets, certificates, signing material, or access
# credentials are denied across major providers + Vault + GPG + k8s.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-secret-key-destruction.sh"

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY — AWS KMS / Secrets Manager / SSM / IAM / ACM
# ============================================================

@test "deny: aws kms schedule-key-deletion" {
  run run_hook Bash "aws kms schedule-key-deletion --key-id 12345-abc --pending-window-in-days 30"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws kms disable-key" {
  run run_hook Bash "aws kms disable-key --key-id 12345-abc"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws kms delete-alias" {
  run run_hook Bash "aws kms delete-alias --alias-name alias/my-key"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws secretsmanager delete-secret" {
  run run_hook Bash "aws secretsmanager delete-secret --secret-id prod/db/password"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws ssm delete-parameter" {
  run run_hook Bash "aws ssm delete-parameter --name /prod/api-key"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws ssm delete-parameters" {
  run run_hook Bash "aws ssm delete-parameters --names /prod/k1 /prod/k2"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-access-key" {
  run run_hook Bash "aws iam delete-access-key --user-name alice --access-key-id AKIAxxx"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-server-certificate" {
  run run_hook Bash "aws iam delete-server-certificate --server-certificate-name my-cert"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam deactivate-mfa-device" {
  run run_hook Bash "aws iam deactivate-mfa-device --user-name alice --serial-number arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-virtual-mfa-device" {
  run run_hook Bash "aws iam delete-virtual-mfa-device --serial-number arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws acm delete-certificate" {
  run run_hook Bash "aws acm delete-certificate --certificate-arn arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — GCP KMS / Secret Manager / IAM
# ============================================================

@test "deny: gcloud kms keys versions destroy" {
  run run_hook Bash "gcloud kms keys versions destroy 1 --key=my-key --location=us"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud kms keys versions disable" {
  run run_hook Bash "gcloud kms keys versions disable 1 --key=my-key"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud secrets delete" {
  run run_hook Bash "gcloud secrets delete my-secret"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud secrets versions destroy" {
  run run_hook Bash "gcloud secrets versions destroy 1 --secret=my-secret"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud iam service-accounts keys delete" {
  run run_hook Bash "gcloud iam service-accounts keys delete KEY_ID --iam-account=sa@p.iam.gserviceaccount.com"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Azure Key Vault (incl. purge that bypasses soft-delete)
# ============================================================

@test "deny: az keyvault key delete" {
  run run_hook Bash "az keyvault key delete --vault-name v --name k"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az keyvault secret delete" {
  run run_hook Bash "az keyvault secret delete --vault-name v --name s"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az keyvault certificate delete" {
  run run_hook Bash "az keyvault certificate delete --vault-name v --name c"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az keyvault key purge (BYPASSES soft-delete)" {
  run run_hook Bash "az keyvault key purge --vault-name v --name k"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az keyvault secret purge" {
  run run_hook Bash "az keyvault secret purge --vault-name v --name s"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — HashiCorp Vault
# ============================================================

@test "deny: vault kv delete" {
  run run_hook Bash "vault kv delete secret/my-app/db"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: vault kv metadata delete (deletes all versions on KV v2)" {
  run run_hook Bash "vault kv metadata delete secret/my-app/db"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: vault delete (general path)" {
  run run_hook Bash "vault delete pki/issuer/default"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — GPG
# ============================================================

@test "deny: gpg --delete-secret-keys" {
  run run_hook Bash "gpg --delete-secret-keys 0xABCDEF"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gpg --delete-secret-and-public-key" {
  run run_hook Bash "gpg --delete-secret-and-public-key 0xABCDEF"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Kubernetes
# ============================================================

@test "deny: kubectl delete secret" {
  run run_hook Bash "kubectl delete secret my-tls -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete secrets (plural)" {
  run run_hook Bash "kubectl delete secrets --all -n stage"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — bash -c wrapper + reason content
# ============================================================

@test "deny: bash -c 'aws kms schedule-key-deletion ...' (wrapper)" {
  run run_hook Bash "bash -c 'aws kms schedule-key-deletion --key-id k'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason mentions rotation completeness + settings.local.json" {
  run run_hook Bash "aws secretsmanager delete-secret --secret-id s"
  [[ "$output" == *"rotation"* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

# ============================================================
# APPROVE — read-only / list / describe / create operations
# ============================================================

@test "approve: aws kms describe-key" {
  run run_hook Bash "aws kms describe-key --key-id 12345"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws kms list-keys" {
  run run_hook Bash "aws kms list-keys"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws kms create-key" {
  run run_hook Bash "aws kms create-key --description 'new key'"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws kms enable-key (re-enabling, not destructive)" {
  run run_hook Bash "aws kms enable-key --key-id 12345"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws kms cancel-key-deletion (REVERSING destruction)" {
  run run_hook Bash "aws kms cancel-key-deletion --key-id 12345"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws secretsmanager get-secret-value" {
  run run_hook Bash "aws secretsmanager get-secret-value --secret-id prod/db"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws secretsmanager describe-secret" {
  run run_hook Bash "aws secretsmanager describe-secret --secret-id prod/db"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws secretsmanager restore-secret (REVERSING destruction)" {
  run run_hook Bash "aws secretsmanager restore-secret --secret-id prod/db"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam list-access-keys" {
  run run_hook Bash "aws iam list-access-keys --user-name alice"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam create-access-key" {
  run run_hook Bash "aws iam create-access-key --user-name alice"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud secrets list" {
  run run_hook Bash "gcloud secrets list"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud secrets create" {
  run run_hook Bash "gcloud secrets create my-secret --data-file=./secret.txt"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az keyvault list" {
  run run_hook Bash "az keyvault list --resource-group rg"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az keyvault key show" {
  run run_hook Bash "az keyvault key show --vault-name v --name k"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az keyvault key create" {
  run run_hook Bash "az keyvault key create --vault-name v --name k --kty RSA"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: vault kv list" {
  run run_hook Bash "vault kv list secret/"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: vault kv get" {
  run run_hook Bash "vault kv get secret/my-app/db"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: vault kv put (writing, not destroying)" {
  run run_hook Bash "vault kv put secret/my-app/db password=xxx"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gpg --list-secret-keys (list only)" {
  run run_hook Bash "gpg --list-secret-keys"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gpg -K (short for --list-secret-keys)" {
  run run_hook Bash "gpg -K"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gpg --import (importing, not destroying)" {
  run run_hook Bash "gpg --import key.asc"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl get secret" {
  run run_hook Bash "kubectl get secret -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl describe secret" {
  run run_hook Bash "kubectl describe secret my-tls -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl create secret" {
  run run_hook Bash "kubectl create secret generic my-secret --from-literal=k=v"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — unrelated commands
# ============================================================

@test "approve: kubectl delete pod (not a secret)" {
  run run_hook Bash "kubectl delete pod my-pod"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws s3 delete-bucket (not a secret store)" {
  run run_hook Bash "aws s3api delete-bucket --bucket b"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: rm /tmp/some-key.pem (rm intentionally not in this hook)" {
  run run_hook Bash "rm /tmp/scratch-key.pem"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: regular shell commands" {
  run run_hook Bash "ls -la"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: non-Bash tool" {
  run run_hook Edit "/tmp/foo.txt"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: empty command" {
  run run_hook Bash ""
  [[ "$output" == *'"decision": "approve"'* ]]
}
