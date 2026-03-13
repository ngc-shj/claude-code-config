#!/usr/bin/env bats
# Tests for hooks/ollama-utils.sh
# Mocks curl to avoid real Ollama calls.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/ollama-utils.sh"

# ---------------------------------------------------------------------------
# Helper: write a mock curl into PATH
# Usage: setup_curl_mock <http_code> <json_body>
# The mock writes <json_body> to the file given by -o <file>, then exits 0.
# ---------------------------------------------------------------------------
setup_curl_mock() {
  local http_code="$1"
  local json_body="$2"

  cat > "$BATS_TEST_TMPDIR/curl" <<EOF
#!/bin/bash
# Mock curl: parse -o <outfile> from args and write json_body there
outfile=""
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    outfile="\${args[i+1]}"
  fi
done

if [ -n "\$outfile" ]; then
  printf '%s' '$json_body' > "\$outfile"
fi

# The script reads the exit status code from the -w '%{http_code}' output.
# curl prints http_code to stdout when -w is used.
printf '%s' "$http_code"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# Mock curl that exits non-zero (simulates connection failure / timeout)
setup_curl_fail_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
# Simulate curl failure (e.g., timeout): print 000 and exit non-zero
# The script uses `|| true` so the exit code doesn't matter;
# what matters is that http_code becomes "000".
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

setup() {
  # Give each test its own tmp dir
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  # Use a predictable fake host so tests never hit real Ollama
  export OLLAMA_HOST="http://mock-ollama:11434"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# ===========================================================================
# Happy path: each subcommand returns the mocked .response value
# ===========================================================================

@test "generate-slug: returns slug from .response field" {
  setup_curl_mock "200" '{"response":"add-user-auth","thinking":""}'
  result=$(echo "Add user authentication" | bash "$SCRIPT" generate-slug)
  [ "$result" = "add-user-auth" ]
}

@test "summarize-diff: returns summary from .response field" {
  setup_curl_mock "200" '{"response":"- Changed auth logic\n- Added tests","thinking":""}'
  result=$(printf 'diff --git a/auth.sh\n+added line' | bash "$SCRIPT" summarize-diff)
  [ -n "$result" ]
}

@test "merge-findings: returns merged output from .response field" {
  setup_curl_mock "200" '{"response":"Critical: SQL injection risk","thinking":""}'
  result=$(echo "Finding 1: SQL injection" | bash "$SCRIPT" merge-findings)
  [ "$result" = "Critical: SQL injection risk" ]
}

@test "classify-changes: returns category from .response field" {
  setup_curl_mock "200" '{"response":"feature","thinking":""}'
  result=$(printf 'src/new-feature.sh\nsrc/helper.sh' | bash "$SCRIPT" classify-changes)
  [ "$result" = "feature" ]
}

# ===========================================================================
# Response parsing: .thinking fallback and empty response
# ===========================================================================

@test "response parsing: falls back to .thinking when .response is empty" {
  setup_curl_mock "200" '{"response":"","thinking":"thinking-fallback-text"}'
  result=$(echo "some input" | bash "$SCRIPT" generate-slug)
  [ "$result" = "thinking-fallback-text" ]
}

@test "response parsing: returns nothing when both .response and .thinking are empty" {
  setup_curl_mock "200" '{"response":"","thinking":""}'
  result=$(echo "some input" | bash "$SCRIPT" generate-slug)
  [ -z "$result" ]
}

@test "response parsing: prefers .response over .thinking when both are present" {
  setup_curl_mock "200" '{"response":"preferred","thinking":"fallback"}'
  result=$(echo "some input" | bash "$SCRIPT" generate-slug)
  [ "$result" = "preferred" ]
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "empty stdin: produces no output and exits 0" {
  # No curl mock needed since empty content short-circuits before curl call
  result=$(echo -n "" | bash "$SCRIPT" generate-slug)
  [ -z "$result" ]
}

@test "custom OLLAMA_HOST is used (visible in warning)" {
  # Use a failing mock so the host appears in the warning message
  setup_curl_fail_mock
  export OLLAMA_HOST="http://custom-host:9999"
  stderr_output=$(echo "test input" | bash "$SCRIPT" generate-slug 2>&1 >/dev/null)
  [[ "$stderr_output" == *"custom-host:9999"* ]]
}

# ===========================================================================
# Error paths: missing/unknown command
# ===========================================================================

@test "no command arg: exits with code 1 and prints usage to stderr" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help command: exits with code 1 and prints usage to stderr" {
  run bash "$SCRIPT" help
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown command: exits with code 1 and prints error to stderr" {
  run bash "$SCRIPT" no-such-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

# ===========================================================================
# Error paths: curl failure / unavailable Ollama
# ===========================================================================

@test "curl returns 000 (timeout/connection refused): warns and produces no stdout" {
  setup_curl_fail_mock
  stdout=$(echo "test input" | bash "$SCRIPT" generate-slug 2>/dev/null)
  [ -z "$stdout" ]
}

@test "curl returns 000: warning is printed to stderr" {
  setup_curl_fail_mock
  stderr_output=$(echo "test input" | bash "$SCRIPT" generate-slug 2>&1 >/dev/null)
  [[ "$stderr_output" == *"Warning: Ollama unavailable"* ]]
}

@test "HTTP 500: warns on stderr and produces no stdout" {
  setup_curl_mock "500" '{"error":"internal server error"}'
  stdout=$(echo "test input" | bash "$SCRIPT" generate-slug 2>/dev/null)
  [ -z "$stdout" ]
}

@test "HTTP 500: warning contains HTTP code" {
  setup_curl_mock "500" '{"error":"internal server error"}'
  stderr_output=$(echo "test input" | bash "$SCRIPT" generate-slug 2>&1 >/dev/null)
  [[ "$stderr_output" == *"Warning: Ollama returned HTTP 500"* ]]
}

@test "HTTP 404: warns on stderr and produces no stdout" {
  setup_curl_mock "404" '{"error":"not found"}'
  stdout=$(echo "test input" | bash "$SCRIPT" generate-slug 2>/dev/null)
  [ -z "$stdout" ]
}

# ===========================================================================
# Error paths: invalid / unexpected JSON
# ===========================================================================

@test "invalid JSON response: produces no stdout (jq parse error causes non-zero exit)" {
  setup_curl_mock "200" 'not-valid-json'
  # jq parse error causes the script to exit non-zero due to set -euo pipefail.
  # We only verify that stdout is empty (no partial output leaked); stderr may
  # contain the jq error message, so redirect it away before capturing stdout.
  run --separate-stderr bash "$SCRIPT" generate-slug <<< "test input"
  [ -z "$output" ]
}

@test "JSON missing response and thinking fields: produces no stdout" {
  setup_curl_mock "200" '{"model":"gpt-oss:20b","done":true}'
  stdout=$(echo "test input" | bash "$SCRIPT" generate-slug 2>/dev/null)
  [ -z "$stdout" ]
}
