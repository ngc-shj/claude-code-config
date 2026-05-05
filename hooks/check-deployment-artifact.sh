#!/bin/bash
# Detect deployment artifacts in a diff and warn when no manual-test plan
# accompanies them.
#
# R35 (Production-deployed component merged without manual test plan)
# fired 105 times across passwd-sso's review history and 59 times in
# claude-code-config — the next-largest gap after R3. R35's "mechanical
# fire trigger" already enumerates the deployment-artifact list (Dockerfile,
# K8s manifests, Helm, Terraform, Ansible, systemd, IAM, TLS material,
# IdP metadata, mesh policy CRDs, webhook signing-key config).
# Manual enforcement is unreliable when reviewers under time pressure miss
# the artifact match. This hook automates the gate.
#
# Usage: bash check-deployment-artifact.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Exit code:
#   0 — no deployment artifact OR manual-test.md found in diff
#   0 — deployment artifact present, manual-test.md missing (advisory only,
#       prints warning to stdout). The hook is a review aid, not a gate;
#       use the output to decide whether to add the missing artifact.

set -u

BASE_REF="${1:-main}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

# --- Deployment-artifact patterns ---
# These mirror the closed list in R35's "Mechanical fire trigger" clause.
# Anything matching here in the diff fires the rule. New deployment shapes
# (e.g., a new orchestrator) require an extension here AND an extension
# of R35's matrix entry — kept in lockstep deliberately.
DEPLOY_PATTERNS=(
  # Container build / orchestration
  '(^|/)Dockerfile(\.|$)'
  '(^|/)\.dockerignore$'
  '(^|/)docker-compose[^/]*\.ya?ml$'
  '(^|/)compose\.ya?ml$'
  # Kubernetes
  '(^|/)k8s/'
  '(^|/)kubernetes/'
  '(^|/)manifests/'
  '\.deployment\.ya?ml$'
  '\.service\.ya?ml$'
  '\.ingress\.ya?ml$'
  '\.statefulset\.ya?ml$'
  '\.daemonset\.ya?ml$'
  '\.cronjob\.ya?ml$'
  '\.configmap\.ya?ml$'
  '\.secret\.ya?ml$'
  '(^|/)kustomization\.ya?ml$'
  # Helm
  '(^|/)Chart\.ya?ml$'
  '(^|/)charts/'
  '(^|/)values[^/]*\.ya?ml$'
  '(^|/)templates/.*\.ya?ml$'
  # Terraform / Pulumi
  '\.tf$'
  '\.tfvars$'
  '(^|/)Pulumi\.ya?ml$'
  # CloudFormation / CDK
  '(^|/)cloudformation[^/]*\.(ya?ml|json)$'
  '(^|/)cdk\.json$'
  # Ansible / cloud-init
  '(^|/)playbook[^/]*\.ya?ml$'
  '(^|/)ansible/'
  '(^|/)cloud-init\.ya?ml$'
  '(^|/)user-data\.ya?ml$'
  # systemd
  '\.service$'
  '\.timer$'
  '\.socket$'
  # Identity / TLS / mesh policy
  '(^|/)\.well-known/'
  '\.idp\.ya?ml$'
  '\.idp\.xml$'
  'saml-metadata\.xml$'
  '(^|/)oauth-config\.'
  '(^|/)oidc-config\.'
  '(^|/)iam/'
  '\.istio\.ya?ml$'
  '(^|/)policies/.*\.ya?ml$'
  '(^|/)mesh-policy/'
  '(^|/)webhook[s]?-config\.'
  # CI/CD pipeline definitions that govern release
  '(^|/)\.github/workflows/.*\.ya?ml$'
  '(^|/)\.gitlab-ci\.ya?ml$'
  '(^|/)\.circleci/'
  '(^|/)Jenkinsfile$'
  '(^|/)bitbucket-pipelines\.ya?ml$'
)

# Tier-2 (Critical) keyword set — when ANY changed file's path contains
# one of these, escalate severity. R35 Tier-2 covers auth flows, auth
# changes, crypto-material, session lifecycle, federation, key custody,
# zero-trust / service-mesh policy, webhook signing-key rotation. The
# closed-list invariant in R35 says this list MUST grow in lockstep with
# R35's Tier-2 definition.
TIER2_KEYWORD_RE='(^|/)(auth|oauth|oidc|saml|sso|mfa|webauthn|otp|totp|jwt|crypto|cipher|encrypt|decrypt|key-rotation|kms|tls|ssl|cert|certificate|session|federation|idp|webhook|signing|signer)([/_.-]|$)'

# Build the deployment-artifact regex once, OR-joined.
DEPLOY_RE=$(printf '%s|' "${DEPLOY_PATTERNS[@]}" | sed 's/|$//')

# --- Collect changed-file lists ---
all_changed=$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null)
if [ -z "$all_changed" ]; then
  echo "=== Deployment-Artifact Check ==="
  echo "Base: $BASE_REF"
  echo "No changed files in $BASE_REF...HEAD — nothing to check."
  exit 0
fi

deployment_hits=$(echo "$all_changed" | grep -E "$DEPLOY_RE" || true)
manual_test_added=$(git diff --name-only --diff-filter=A "$BASE_REF...HEAD" 2>/dev/null \
  | grep -E '/[^/]+-manual-test\.md$' || true)

# Tier classification: if ANY changed file path contains a Tier-2 keyword,
# the gate is Tier-2 (Critical). Otherwise Tier-1 (Major).
tier='Tier-1 (Major)'
if echo "$all_changed" | grep -qE "$TIER2_KEYWORD_RE"; then
  tier='Tier-2 (Critical)'
fi

# --- Output ---
echo "=== Deployment-Artifact Check ==="
echo "Base: $BASE_REF"
echo "Changed files: $(echo "$all_changed" | wc -l)"
echo ""

if [ -z "$deployment_hits" ]; then
  echo "No deployment artifacts detected in diff. R35 manual-test.md gate does NOT fire."
  exit 0
fi

echo "## Deployment artifacts present (R35 gate fires)"
echo ""
echo "Tier: $tier"
echo ""
echo "Changed deployment-artifact files:"
echo "$deployment_hits" | sed 's/^/  - /'
echo ""

if [ -n "$manual_test_added" ]; then
  echo "## Manual test plan present in diff — gate satisfied"
  echo ""
  echo "$manual_test_added" | sed 's/^/  ✓ /'
  echo ""
  echo "Verify the artifact contains the required sections per R35:"
  echo "  - Pre-conditions / Steps / Expected result / Rollback"
  if [ "$tier" = "Tier-2 (Critical)" ]; then
    echo "  - Adversarial scenarios (Tier-2 only): cross-tenant access,"
    echo "    token replay, redirect-URI/state manipulation, scope elevation,"
    echo "    session fixation as applicable"
  fi
  exit 0
fi

# Gate fires and no manual-test.md in diff.
echo "## ⚠ Manual test plan MISSING from diff"
echo ""
echo "R35 ${tier} requires a corresponding manual-test plan when the"
echo "diff touches the deployment-artifact list above."
echo ""
echo "Required artifact: ./docs/archive/review/[plan-name]-manual-test.md"
echo "Required sections: Pre-conditions / Steps / Expected result / Rollback"
if [ "$tier" = "Tier-2 (Critical)" ]; then
  echo "Tier-2 additionally requires: Adversarial scenarios (cross-tenant"
  echo "  access, token replay, redirect-URI/state manipulation, scope"
  echo "  elevation, session fixation as applicable)"
fi
echo ""
echo "If a manual-test.md already exists for this plan and was added in"
echo "an earlier commit (not this diff), this warning can be dismissed."
echo "Otherwise, add the artifact before merge."
