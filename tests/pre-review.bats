#!/usr/bin/env bats
# Tests for hooks/pre-review.sh — focus on PLAN_FILE path containment (S3).
# curl is mocked so the containment check is exercised without touching Ollama.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/pre-review.sh"

# Mock curl that exits non-zero so the script falls through to its
# "Ollama unavailable" graceful-exit path. Our assertions target the
# stderr warning emitted BEFORE the curl call.
setup_curl_fail_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  export OLLAMA_HOST="http://mock-ollama:11434"
  setup_curl_fail_mock
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

@test "PLAN_FILE=/etc/passwd (outside repo): rejected with warning, falls back to stdin" {
  run bash -c "PLAN_FILE=/etc/passwd echo '' | PLAN_FILE=/etc/passwd bash '$SCRIPT' plan"
  # Non-blocking helper: exit 0 even when Ollama is mocked to fail.
  [ "$status" -eq 0 ]
  [[ "$output" == *"outside TRUSTED_ROOT"* ]]
  [[ "$output" == *"/etc/passwd"* ]]
  # Must NOT include any content from /etc/passwd.
  [[ "$output" != *"root:x:0"* ]]
}

@test "PLAN_FILE=~/.bashrc (HOME, outside repo): rejected" {
  run bash -c "PLAN_FILE='$HOME/.bashrc' echo '' | PLAN_FILE='$HOME/.bashrc' bash '$SCRIPT' plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"outside TRUSTED_ROOT"* ]]
}

@test "PLAN_FILE=traversal (../../etc/hostname): rejected after canonicalization" {
  run bash -c "cd '$BATS_TEST_TMPDIR' && echo '' | PLAN_FILE='../../etc/hostname' bash '$SCRIPT' plan"
  [ "$status" -eq 0 ]
  # Either the existence check fails or the containment check catches it.
  # Critical invariant: no /etc/hostname content in output.
  [[ "$output" != *"$(cat /etc/hostname 2>/dev/null)"* || -z "$(cat /etc/hostname 2>/dev/null)" ]]
}

@test "PLAN_FILE unset: falls back to stdin normally (backwards compat)" {
  # Feed a small plan via stdin. Script will attempt Ollama call (mocked to fail)
  # and exit gracefully — we just confirm no containment warning fires.
  run bash -c "echo 'Plan: do stuff' | bash '$SCRIPT' plan"
  [ "$status" -eq 0 ]
  [[ "$output" != *"outside TRUSTED_ROOT"* ]]
}

@test "PLAN_FILE inside repo: accepted (backwards compat)" {
  # Use the repo's own CLAUDE.md as a benign in-repo path.
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  run bash -c "echo '' | PLAN_FILE='$REPO_ROOT/CLAUDE.md' bash '$SCRIPT' plan"
  [ "$status" -eq 0 ]
  [[ "$output" != *"outside TRUSTED_ROOT"* ]]
  [[ "$output" != *"could not be resolved"* ]]
}
