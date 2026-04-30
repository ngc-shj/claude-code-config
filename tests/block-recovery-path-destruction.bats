#!/usr/bin/env bats
# Tests for hooks/block-recovery-path-destruction.sh — R31 (h) backup /
# snapshot / recovery-point destruction is denied across the major
# providers + Kubernetes; read/list/create operations and unrelated
# CLIs (incl. `terraform destroy`) are approved.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-recovery-path-destruction.sh"

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY — AWS Backup / EC2 / RDS
# ============================================================

@test "deny: aws backup delete-recovery-point" {
  run run_hook Bash "aws backup delete-recovery-point --backup-vault-name v --recovery-point-arn arn:..."
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws backup delete-backup-plan" {
  run run_hook Bash "aws backup delete-backup-plan --backup-plan-id p"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws backup delete-backup-vault" {
  run run_hook Bash "aws backup delete-backup-vault --backup-vault-name v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws backup delete-backup-selection" {
  run run_hook Bash "aws backup delete-backup-selection --backup-plan-id p --selection-id s"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws ec2 delete-snapshot" {
  run run_hook Bash "aws ec2 delete-snapshot --snapshot-id snap-12345"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws rds delete-db-snapshot" {
  run run_hook Bash "aws rds delete-db-snapshot --db-snapshot-identifier mydb-snap"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws rds delete-db-cluster-snapshot" {
  run run_hook Bash "aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier c-snap"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws rds modify-db-instance --backup-retention-period 0" {
  run run_hook Bash "aws rds modify-db-instance --db-instance-identifier mydb --backup-retention-period 0"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws rds modify-db-instance --backup-retention-period 1 (window narrowing)" {
  run run_hook Bash "aws rds modify-db-instance --db-instance-identifier mydb --backup-retention-period 1"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws rds modify-db-cluster --backup-retention-period 7" {
  run run_hook Bash "aws rds modify-db-cluster --db-cluster-identifier c --backup-retention-period 7"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — GCP
# ============================================================

@test "deny: gcloud compute snapshots delete" {
  run run_hook Bash "gcloud compute snapshots delete snap-1 --quiet"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud sql backups delete" {
  run run_hook Bash "gcloud sql backups delete 12345 --instance=my-instance"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud sql instances patch --no-backup" {
  run run_hook Bash "gcloud sql instances patch my-instance --no-backup"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud sql instances patch --backup-start-time" {
  run run_hook Bash "gcloud sql instances patch my-instance --backup-start-time=23:00"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Azure
# ============================================================

@test "deny: az snapshot delete" {
  run run_hook Bash "az snapshot delete --name snap1 --resource-group rg"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az backup vault delete" {
  run run_hook Bash "az backup vault delete --name v --resource-group rg"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az backup item delete" {
  run run_hook Bash "az backup item delete --vault-name v --resource-group rg --container-name c --name i"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az backup policy delete" {
  run run_hook Bash "az backup policy delete --name policy1 --vault-name v --resource-group rg"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Kubernetes
# ============================================================

@test "deny: kubectl delete volumesnapshot" {
  run run_hook Bash "kubectl delete volumesnapshot snap1 -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete volumesnapshots (plural)" {
  run run_hook Bash "kubectl delete volumesnapshots --all -n default"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete pv" {
  run run_hook Bash "kubectl delete pv my-pv"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete persistentvolume (long form)" {
  run run_hook Bash "kubectl delete persistentvolume my-pv"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — bash -c wrapper
# ============================================================

@test "deny: bash -c 'aws ec2 delete-snapshot ...' (wrapper)" {
  run run_hook Bash "bash -c 'aws ec2 delete-snapshot --snapshot-id snap-1'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason mentions retention coordination + settings.local.json" {
  run run_hook Bash "aws backup delete-recovery-point --recovery-point-arn arn:..."
  [[ "$output" == *"compliance"* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

# ============================================================
# APPROVE — read-only / list / describe operations
# ============================================================

@test "approve: aws backup list-recovery-points-by-backup-vault" {
  run run_hook Bash "aws backup list-recovery-points-by-backup-vault --backup-vault-name v"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws ec2 describe-snapshots" {
  run run_hook Bash "aws ec2 describe-snapshots --owner-ids self"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws ec2 create-snapshot (creating, not destroying)" {
  run run_hook Bash "aws ec2 create-snapshot --volume-id vol-1"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws rds describe-db-snapshots" {
  run run_hook Bash "aws rds describe-db-snapshots"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws rds modify-db-instance (no retention flag)" {
  run run_hook Bash "aws rds modify-db-instance --db-instance-identifier mydb --allocated-storage 100"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud compute snapshots list" {
  run run_hook Bash "gcloud compute snapshots list"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gcloud sql backups list" {
  run run_hook Bash "gcloud sql backups list --instance=my-instance"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az snapshot list" {
  run run_hook Bash "az snapshot list --resource-group rg"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: az backup vault list" {
  run run_hook Bash "az backup vault list --resource-group rg"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl get pv" {
  run run_hook Bash "kubectl get pv"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl describe volumesnapshot" {
  run run_hook Bash "kubectl describe volumesnapshot snap1"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — terraform destroy is intentionally NOT blocked
# ============================================================

@test "approve: terraform destroy (intentionally not blocked — too noisy in dev/CI)" {
  run run_hook Bash "terraform destroy -auto-approve"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: terraform destroy -target=resource.x (targeted)" {
  run run_hook Bash "terraform destroy -target=aws_instance.dev"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — unrelated commands that look superficially similar
# ============================================================

@test "approve: kubectl delete pod (not a recovery resource)" {
  run run_hook Bash "kubectl delete pod my-pod"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: kubectl delete pvc (intentionally deferred to docker hook scope)" {
  run run_hook Bash "kubectl delete pvc my-pvc"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: aws s3 delete-object (not a backup)" {
  run run_hook Bash "aws s3api delete-object --bucket b --key k"
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
