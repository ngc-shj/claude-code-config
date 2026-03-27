#!/usr/bin/env bats
# Tests for hooks/resolve-ollama-host.sh
# Mocks curl to avoid real network calls.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/resolve-ollama-host.sh"

# ---------------------------------------------------------------------------
# Helper: mock curl that succeeds for specified hosts, logs all calls
# Usage: setup_curl_mock <host_substring_to_succeed...>
# ---------------------------------------------------------------------------
setup_curl_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
LOG_FILE="${CURL_LOG_FILE:-/dev/null}"
for arg in "$@"; do
  case "$arg" in
    http://*)
      echo "$arg" >> "$LOG_FILE"
      ;;
  esac
done
SUCCEED_HOSTS_STR="${CURL_SUCCEED_HOSTS:-}"
for arg in "$@"; do
  case "$arg" in
    http://*)
      for h in $SUCCEED_HOSTS_STR; do
        if [[ "$arg" == *"$h"* ]]; then
          printf '000'
          exit 0
        fi
      done
      ;;
  esac
done
# No match — fail
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# Mock curl that always fails (simulates all hosts unreachable)
setup_curl_fail_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
LOG_FILE="${CURL_LOG_FILE:-/dev/null}"
for arg in "$@"; do
  case "$arg" in
    http://*)
      echo "$arg" >> "$LOG_FILE"
      ;;
  esac
done
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# Cross-platform: set file mtime to N seconds ago
set_mtime_ago() {
  local file="$1" seconds_ago="$2"
  local target_ts
  target_ts=$(( $(date +%s) - seconds_ago ))
  # GNU touch -d, fallback to python3
  if touch -d "@$target_ts" "$file" 2>/dev/null; then
    return
  fi
  python3 -c "import os; os.utime('$file', ($target_ts, $target_ts))" 2>/dev/null || true
}

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  # Isolate cache to test tmpdir
  export _OLLAMA_HOST_CACHE="$BATS_TEST_TMPDIR/.ollama-host-cache"
  # Log curl calls
  export CURL_LOG_FILE="$BATS_TEST_TMPDIR/curl-calls.log"
  # Clear OLLAMA_HOST so auto-detection runs
  unset OLLAMA_HOST
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# ===========================================================================
# OLLAMA_HOST env var takes precedence
# ===========================================================================

@test "env var: OLLAMA_HOST set returns it directly without probing" {
  export OLLAMA_HOST="http://custom:9999"
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://custom:9999" ]
}

@test "env var: OLLAMA_HOST set does not create cache file" {
  export OLLAMA_HOST="http://custom:9999"
  source "$SCRIPT"
  [ ! -f "$_OLLAMA_HOST_CACHE" ]
}

# ===========================================================================
# Cache behavior
# ===========================================================================

@test "cache: fresh cache returns cached value without probing" {
  echo "http://cached-host:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://cached-host:11434" ]
  [ ! -s "$CURL_LOG_FILE" ]
}

@test "cache: stale cache triggers re-probe" {
  echo "http://stale-host:11434" > "$_OLLAMA_HOST_CACHE"
  set_mtime_ago "$_OLLAMA_HOST_CACHE" 600
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://gx10-a9c0:11434" ]
  [ -s "$CURL_LOG_FILE" ]
}

@test "cache: symlink cache is ignored" {
  echo "http://symlink-target:11434" > "$BATS_TEST_TMPDIR/real-cache"
  ln -s "$BATS_TEST_TMPDIR/real-cache" "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://gx10-a9c0:11434" ]
}

# ===========================================================================
# Probe order
# ===========================================================================

@test "probe: tries hosts in correct order (gx10-a9c0 -> gx10-a9c0.local -> localhost)" {
  setup_curl_fail_mock
  source "$SCRIPT"
  run cat "$CURL_LOG_FILE"
  [ "${lines[0]}" = "http://gx10-a9c0:11434/api/version" ]
  [ "${lines[1]}" = "http://gx10-a9c0.local:11434/api/version" ]
  [ "${lines[2]}" = "http://localhost:11434/api/version" ]
}

@test "probe: stops at first reachable host" {
  export CURL_SUCCEED_HOSTS="gx10-a9c0.local"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://gx10-a9c0.local:11434" ]
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 2 ]
}

@test "probe: returns first host when it is reachable" {
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://gx10-a9c0:11434" ]
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 1 ]
}

# ===========================================================================
# Fallback
# ===========================================================================

@test "fallback: all hosts unreachable returns gx10-a9c0" {
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://gx10-a9c0:11434" ]
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 3 ]
}

# ===========================================================================
# Export
# ===========================================================================

@test "export: OLLAMA_HOST is exported after sourcing" {
  # Do NOT pre-export — let the script resolve and export
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  # Verify export flag is set
  run bash -c 'echo "$OLLAMA_HOST"'
  [ "$output" = "http://gx10-a9c0:11434" ]
}

# ===========================================================================
# Idempotent sourcing
# ===========================================================================

@test "idempotent: sourcing twice does not re-probe" {
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  first="$OLLAMA_HOST"
  source "$SCRIPT"
  second="$OLLAMA_HOST"
  [ "$first" = "$second" ]
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 1 ]
}

# ===========================================================================
# Atomic cache write
# ===========================================================================

@test "cache write: creates cache file on successful probe" {
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ -f "$_OLLAMA_HOST_CACHE" ]
  cached=$(cat "$_OLLAMA_HOST_CACHE")
  [ "$cached" = "http://localhost:11434" ]
}

@test "cache write: does not create cache on fallback" {
  setup_curl_fail_mock
  source "$SCRIPT"
  [ ! -f "$_OLLAMA_HOST_CACHE" ]
}
