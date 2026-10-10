#!/usr/bin/env bats
# Tests for hooks/block-audit-observability-destruction.sh — R31 (g)
# anti-forensic verbs are denied across the major providers + k8s, while
# read-only / list / describe operations and unrelated CLIs pass through with no decision.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-audit-observability-destruction.sh"

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY — AWS CloudWatch Logs / Metrics
# ============================================================

@test "deny: aws logs delete-log-group" {
  run run_hook Bash "aws logs delete-log-group --log-group-name /var/log/app"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws logs delete-log-stream" {
  run run_hook Bash "aws logs delete-log-stream --log-group-name g --log-stream-name s"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws logs put-retention-policy (retention shortening)" {
  run run_hook Bash "aws logs put-retention-policy --log-group-name /app --retention-in-days 1"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws cloudwatch delete-alarms" {
  run run_hook Bash "aws cloudwatch delete-alarms --alarm-names HighCPU"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: aws cloudwatch delete-dashboards" {
  run run_hook Bash "aws cloudwatch delete-dashboards --dashboard-names ProdOverview"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — GCP logging / monitoring
# ============================================================

@test "deny: gcloud logging logs delete" {
  run run_hook Bash "gcloud logging logs delete syslog --quiet"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud logging buckets delete" {
  run run_hook Bash "gcloud logging buckets delete _Default --location=global"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud logging sinks delete" {
  run run_hook Bash "gcloud logging sinks delete my-sink"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud monitoring alert-policies delete" {
  run run_hook Bash "gcloud monitoring alert-policies delete projects/p/alertPolicies/123"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud monitoring dashboards delete" {
  run run_hook Bash "gcloud monitoring dashboards delete projects/p/dashboards/abc"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: gcloud monitoring notification-channels delete" {
  run run_hook Bash "gcloud monitoring notification-channels delete projects/p/notificationChannels/xyz"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Azure monitoring
# ============================================================

@test "deny: az monitor diagnostic-settings delete" {
  run run_hook Bash "az monitor diagnostic-settings delete --name d1 --resource r"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az monitor action-group delete" {
  run run_hook Bash "az monitor action-group delete --name OnCall --resource-group rg"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: az monitor metrics alert delete" {
  run run_hook Bash "az monitor metrics alert delete --name HighCPU --resource-group rg"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — Kubernetes (prometheus-operator CRDs)
# ============================================================

@test "deny: kubectl delete prometheusrule" {
  run run_hook Bash "kubectl delete prometheusrule app-alerts -n monitoring"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete prometheusrules (plural)" {
  run run_hook Bash "kubectl delete prometheusrules --all -n monitoring"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete servicemonitor" {
  run run_hook Bash "kubectl delete servicemonitor app -n monitoring"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete podmonitor" {
  run run_hook Bash "kubectl delete podmonitor app -n monitoring"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: kubectl delete alertmanagerconfig" {
  run run_hook Bash "kubectl delete alertmanagerconfig pagerduty -n monitoring"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# DENY — bash -c wrapper
# ============================================================

@test "deny: bash -c 'aws logs delete-log-group ...' (wrapper)" {
  run run_hook Bash "bash -c 'aws logs delete-log-group --log-group-name g'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason recommends update-not-delete and explicit confirmation" {
  run run_hook Bash "kubectl delete prometheusrule x -n monitoring"
  [[ "$output" == *"anti-forensic"* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

# ============================================================
# PASS — read-only / list / describe operations
# ============================================================

@test "pass: aws logs describe-log-groups" {
  run run_hook Bash "aws logs describe-log-groups"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: aws logs filter-log-events" {
  run run_hook Bash "aws logs filter-log-events --log-group-name g"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: aws cloudwatch describe-alarms" {
  run run_hook Bash "aws cloudwatch describe-alarms"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: aws cloudwatch get-dashboard" {
  run run_hook Bash "aws cloudwatch get-dashboard --dashboard-name ProdOverview"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: aws logs create-log-group (creating, not destroying)" {
  run run_hook Bash "aws logs create-log-group --log-group-name /app/new"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: gcloud logging logs list" {
  run run_hook Bash "gcloud logging logs list"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: gcloud monitoring dashboards list" {
  run run_hook Bash "gcloud monitoring dashboards list"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: gcloud monitoring alert-policies create" {
  run run_hook Bash "gcloud monitoring alert-policies create --policy-from-file policy.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: kubectl get prometheusrule" {
  run run_hook Bash "kubectl get prometheusrule -A"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: kubectl describe servicemonitor" {
  run run_hook Bash "kubectl describe servicemonitor app -n monitoring"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

# ============================================================
# PASS — unrelated commands that look superficially similar
# ============================================================

@test "pass: kubectl delete pod (not a monitoring CRD)" {
  run run_hook Bash "kubectl delete pod my-pod"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: aws s3 delete-bucket (not logs/cloudwatch)" {
  run run_hook Bash "aws s3 delete-bucket --bucket old-bucket"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: az group delete (not monitor)" {
  run run_hook Bash "az group delete --name rg-test"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: gcloud compute instances delete (not logging/monitoring)" {
  run run_hook Bash "gcloud compute instances delete vm-test"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: regular shell commands" {
  run run_hook Bash "ls -la /var/log"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: non-Bash tool" {
  run run_hook Edit "/tmp/foo.txt"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

@test "pass: empty command" {
  run run_hook Bash ""
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision"'* ]]
}

# A pass must print nothing. Claude Code honours `{"decision": "approve"}` as an
# approval that skips the permission check for the call, so an approve here
# would auto-approve every call this hook inspects and lets through.
@test "regression: a call it lets through produces no decision" {
  run --separate-stderr run_hook Bash "aws logs describe-log-groups"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
