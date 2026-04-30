#!/usr/bin/env bats
# Tests for hooks/block-authz-state-destruction.sh — R31 (f) verbs
# that delete roles / role bindings / IAM policies / group memberships
# / service accounts are denied across major providers + Kubernetes.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-authz-state-destruction.sh"

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY — AWS IAM
# ============================================================

@test "deny: aws iam delete-role" {
  run run_hook Bash "aws iam delete-role --role-name MyRole"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-role-policy (inline)" {
  run run_hook Bash "aws iam delete-role-policy --role-name R --policy-name P"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam detach-role-policy (managed)" {
  run run_hook Bash "aws iam detach-role-policy --role-name R --policy-arn arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-policy" {
  run run_hook Bash "aws iam delete-policy --policy-arn arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-policy-version" {
  run run_hook Bash "aws iam delete-policy-version --policy-arn arn:... --version-id v1"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-group" {
  run run_hook Bash "aws iam delete-group --group-name developers"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam remove-user-from-group" {
  run run_hook Bash "aws iam remove-user-from-group --user-name alice --group-name developers"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-user" {
  run run_hook Bash "aws iam delete-user --user-name alice"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam delete-instance-profile" {
  run run_hook Bash "aws iam delete-instance-profile --instance-profile-name p"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws iam remove-role-from-instance-profile" {
  run run_hook Bash "aws iam remove-role-from-instance-profile --instance-profile-name p --role-name r"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — GCP IAM
# ============================================================

@test "deny: gcloud iam roles delete" {
  run run_hook Bash "gcloud iam roles delete my-role --project=p"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud iam service-accounts delete" {
  run run_hook Bash "gcloud iam service-accounts delete sa@p.iam.gserviceaccount.com"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud projects remove-iam-policy-binding" {
  run run_hook Bash "gcloud projects remove-iam-policy-binding p --member=user:a@x.com --role=roles/editor"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud projects set-iam-policy (replaces ENTIRE policy)" {
  run run_hook Bash "gcloud projects set-iam-policy p policy.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud organizations remove-iam-policy-binding" {
  run run_hook Bash "gcloud organizations remove-iam-policy-binding 12345 --member=user:a@x.com --role=r"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud resource-manager folders remove-iam-policy-binding" {
  run run_hook Bash "gcloud resource-manager folders remove-iam-policy-binding 67890 --member=user:a@x.com --role=r"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Azure RBAC / AAD
# ============================================================

@test "deny: az role assignment delete" {
  run run_hook Bash "az role assignment delete --assignee a@x.com --role Contributor"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az role definition delete" {
  run run_hook Bash "az role definition delete --name 'My Custom Role'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az ad group delete" {
  run run_hook Bash "az ad group delete --group developers"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az ad group member remove" {
  run run_hook Bash "az ad group member remove --group developers --member-id ABC"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az ad sp delete (service principal)" {
  run run_hook Bash "az ad sp delete --id 12345-abc"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Kubernetes RBAC
# ============================================================

@test "deny: kubectl delete role" {
  run run_hook Bash "kubectl delete role app-reader -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete rolebinding" {
  run run_hook Bash "kubectl delete rolebinding app-reader-binding -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete clusterrole" {
  run run_hook Bash "kubectl delete clusterrole my-clusterrole"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete clusterrolebinding" {
  run run_hook Bash "kubectl delete clusterrolebinding my-binding"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete serviceaccount" {
  run run_hook Bash "kubectl delete serviceaccount app-sa -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete serviceaccounts (plural)" {
  run run_hook Bash "kubectl delete serviceaccounts --all -n staging"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — bash -c wrapper + reason content
# ============================================================

@test "deny: bash -c 'aws iam delete-role ...' (wrapper)" {
  run run_hook Bash "bash -c 'aws iam delete-role --role-name R'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason mentions rotate-not-revoke + settings.local.json" {
  run run_hook Bash "aws iam delete-role --role-name R"
  [[ "$output" == *"rotate"* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "deny block reason mentions set-iam-policy replacement risk" {
  run run_hook Bash "gcloud projects set-iam-policy p policy.json"
  [[ "$output" == *"REPLACES"* ]]
}

# ============================================================
# APPROVE — read-only / list / describe / create operations
# ============================================================

@test "approve: aws iam list-roles" {
  run run_hook Bash "aws iam list-roles"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam get-role" {
  run run_hook Bash "aws iam get-role --role-name R"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam create-role" {
  run run_hook Bash "aws iam create-role --role-name R --assume-role-policy-document file://trust.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam attach-role-policy (granting, not removing)" {
  run run_hook Bash "aws iam attach-role-policy --role-name R --policy-arn arn:..."
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam add-user-to-group (granting)" {
  run run_hook Bash "aws iam add-user-to-group --user-name alice --group-name dev"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud iam roles list" {
  run run_hook Bash "gcloud iam roles list --project=p"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud projects add-iam-policy-binding (surgical add)" {
  run run_hook Bash "gcloud projects add-iam-policy-binding p --member=user:a@x.com --role=roles/viewer"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud projects get-iam-policy" {
  run run_hook Bash "gcloud projects get-iam-policy p"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az role assignment list" {
  run run_hook Bash "az role assignment list --assignee a@x.com"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az role assignment create" {
  run run_hook Bash "az role assignment create --assignee a@x.com --role Reader --resource-group rg"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az ad group list" {
  run run_hook Bash "az ad group list"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az ad group member add (granting membership)" {
  run run_hook Bash "az ad group member add --group developers --member-id ABC"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl get role" {
  run run_hook Bash "kubectl get role -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl describe rolebinding" {
  run run_hook Bash "kubectl describe rolebinding app-reader -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl create rolebinding" {
  run run_hook Bash "kubectl create rolebinding app-reader-bind --role=app-reader --user=alice -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl create serviceaccount" {
  run run_hook Bash "kubectl create serviceaccount app-sa -n default"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — unrelated commands that look superficially similar
# ============================================================

@test "approve: kubectl delete pod (not an authz resource)" {
  run run_hook Bash "kubectl delete pod my-pod"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl delete namespace (not authz; dangerous but different category)" {
  run run_hook Bash "kubectl delete namespace test"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws iam create-policy (creating, not deleting)" {
  run run_hook Bash "aws iam create-policy --policy-name P --policy-document file://p.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud iam service-accounts create" {
  run run_hook Bash "gcloud iam service-accounts create sa --display-name='Service Account'"
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
