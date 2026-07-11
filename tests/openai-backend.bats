#!/usr/bin/env bats
# Tests for hooks/openai-backend.sh (the OpenAI-compatible provider) and the OpenAI
# arm of the hooks/llm-utils.sh dispatcher.
#
# Sourced via hooks/llm-utils.sh so the shared helpers + dispatcher are loaded.
# OLLAMA_HOST is pinned to a dummy so sourcing does not trigger real Ollama
# discovery; LLM_BACKEND=openai forces the dispatcher down the OpenAI arm.
# curl is mocked to speak the OpenAI surface (/v1/models, /v1/chat/completions).

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/llm-utils.sh"

# Mock curl: GET /v1/models succeeds (exit 0 + models JSON on stdout) for any
# host whose URL contains a substring in CPP_SUCCEED_HOSTS, else fails (exit 28).
# POST /v1/chat/completions writes CPP_CHAT_JSON to the -o file and prints
# CPP_CHAT_CODE as the http_code. Everything else fails.
setup_curl_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
LOG="${CURL_LOG_FILE:-/dev/null}"
URL=""; OUTFILE=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    http://*|https://*) URL="${args[i]}"; echo "${args[i]}" >> "$LOG" ;;
    -o) OUTFILE="${args[i+1]}" ;;
  esac
done
# Defaults set as plain single-quoted literals (NOT inside ${:-...}) — nested
# JSON braces would otherwise terminate the parameter expansion early.
MODELS="${CPP_MODELS_JSON:-}"
[ -z "$MODELS" ] && MODELS='{"data":[{"id":"unsloth/gpt-oss-20b-GGUF:F16"}]}'
CHAT="${CPP_CHAT_JSON:-}"
[ -z "$CHAT" ] && CHAT='{"choices":[{"message":{"content":"OK"}}]}'
case "$URL" in
  */v1/models)
    for h in ${CPP_SUCCEED_HOSTS:-}; do
      if [[ "$URL" == *"$h"* ]]; then
        printf '%s' "$MODELS"
        exit 0
      fi
    done
    exit 28
    ;;
  */v1/chat/completions)
    code="${CPP_CHAT_CODE:-200}"
    if [ "$code" != "000" ] && [ -n "$OUTFILE" ]; then
      printf '%s' "$CHAT" > "$OUTFILE"
    fi
    printf '%s' "$code"
    exit 0
    ;;
esac
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  export _OPENAI_HOST_CACHE="$BATS_TEST_TMPDIR/.openai-cache"
  export _OLLAMA_HOST_CACHE="$BATS_TEST_TMPDIR/.ollama-cache"
  export CURL_LOG_FILE="$BATS_TEST_TMPDIR/curl-calls.log"
  # Pin Ollama so sourcing llm-utils.sh does not run real Ollama discovery.
  export OLLAMA_HOST="http://dummy-ollama:11434"
  unset LLM_BACKEND OPENAI_HOST OPENAI_HOSTS LLM_TRUSTED_HOSTS LLM_OPENAI_PORTS
  unset OPENAI_MODEL_SMALL OPENAI_MODEL_LARGE OPENAI_MODEL_DS4_FLASH OPENAI_MODEL_DS4_PRO
  setup_curl_mock
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# openai_model_for — logical -> real model mapping
# ---------------------------------------------------------------------------

@test "model map: gpt-oss:20b -> default small model" {
  result=$(source "$SCRIPT" && openai_model_for "gpt-oss:20b")
  [ "$result" = "unsloth/gpt-oss-20b-GGUF:F16" ]
}

@test "model map: gpt-oss:120b -> default large (Qwen) model" {
  result=$(source "$SCRIPT" && openai_model_for "gpt-oss:120b")
  [ "$result" = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL" ]
}

@test "model map: env override is honored" {
  export OPENAI_MODEL_SMALL="foo/bar:Q8"
  result=$(source "$SCRIPT" && openai_model_for "gpt-oss:20b")
  [ "$result" = "foo/bar:Q8" ]
}

@test "model map: unknown logical name passes through unchanged" {
  result=$(source "$SCRIPT" && openai_model_for "some-model:7b")
  [ "$result" = "some-model:7b" ]
}

# ---------------------------------------------------------------------------
# llm_model_for — backend-aware wrapper
# ---------------------------------------------------------------------------

@test "llm_model_for: ollama backend is identity" {
  result=$(source "$SCRIPT" && llm_model_for "gpt-oss:120b" ollama)
  [ "$result" = "gpt-oss:120b" ]
}

@test "llm_model_for: openai backend delegates to the mapping" {
  result=$(source "$SCRIPT" && llm_model_for "gpt-oss:120b" openai)
  [ "$result" = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL" ]
}

# ---------------------------------------------------------------------------
# llm_select_backend
# ---------------------------------------------------------------------------

@test "select: LLM_BACKEND=ollama pins ollama (no probe)" {
  export LLM_BACKEND=ollama
  result=$(source "$SCRIPT" && llm_select_backend)
  [ "$result" = "ollama" ]
}

@test "select: LLM_BACKEND=openai pins openai" {
  export LLM_BACKEND=openai
  result=$(source "$SCRIPT" && llm_select_backend)
  [ "$result" = "openai" ]
}

@test "select: invalid LLM_BACKEND falls through to auto (openai reachable)" {
  export LLM_BACKEND=bogus
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && llm_select_backend)
  [ "$result" = "openai" ]
}

@test "select: auto picks ollama when llama.cpp is unreachable" {
  export CPP_SUCCEED_HOSTS=""   # nothing answers /v1/models
  result=$(source "$SCRIPT" && llm_select_backend)
  [ "$result" = "ollama" ]
}

# ---------------------------------------------------------------------------
# openai_host_for_model — discovery + filtering
# ---------------------------------------------------------------------------

@test "host: reachable host serving the model is returned" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$result" = "http://localhost:8080" ]
}

@test "host: unreachable -> empty (caller skips gracefully)" {
  export CPP_SUCCEED_HOSTS=""
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ -z "$result" ]
}

@test "host: server lacking the requested model id is filtered out" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  export CPP_MODELS_JSON='{"data":[{"id":"other/model:Q4"}]}'
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ -z "$result" ]
}

@test "host: single discovered record (no trailing newline) is not dropped by while-read" {
  # Regression: _openai_records must emit a trailing newline so a lone record
  # is read; otherwise the host is silently dropped and llama.cpp looks down.
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ -n "$result" ]
}

# ---------------------------------------------------------------------------
# Pinned host bypasses the shared cache
# ---------------------------------------------------------------------------

@test "pin: OPENAI_HOST probes directly and ignores a stale cache" {
  # Seed a stale cache pointing at a host that does NOT serve the model.
  printf 'http://stale:8080\tother/model:Q4\n' > "$_OPENAI_HOST_CACHE"
  export OPENAI_HOST="http://localhost:8080"
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$result" = "http://localhost:8080" ]
  # Cache must NOT be rewritten when a host is pinned.
  grep -q '^http://stale:8080' "$_OPENAI_HOST_CACHE"
}

# ---------------------------------------------------------------------------
# _openai_request — request/response + graceful degradation
# ---------------------------------------------------------------------------

@test "request: HTTP 200 returns message content" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && printf 'hi' | _openai_request "unsloth/gpt-oss-20b-GGUF:F16" "" 30 32)
  [ "$result" = "OK" ]
}

@test "request: falls back to reasoning_content when content is empty" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  export CPP_CHAT_JSON='{"choices":[{"message":{"content":"","reasoning_content":"thinking"}}]}'
  result=$(source "$SCRIPT" && printf 'hi' | _openai_request "unsloth/gpt-oss-20b-GGUF:F16" "" 30 32)
  [ "$result" = "thinking" ]
}

@test "request: empty stdin produces no output and exits 0" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  run bash -c "source '$SCRIPT' && printf '' | _openai_request 'unsloth/gpt-oss-20b-GGUF:F16' '' 30 32"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "request: HTTP 500 warns on stderr, no stdout" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  export CPP_CHAT_CODE="500"
  run bash -c "source '$SCRIPT' && printf 'hi' | _openai_request 'unsloth/gpt-oss-20b-GGUF:F16' '' 30 32 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "request: HTTP 500 does not leak the response body" {
  export CPP_SUCCEED_HOSTS="localhost:8080"
  export CPP_CHAT_CODE="500"
  export CPP_CHAT_JSON='{"secret":"LEAKED-CODE"}'
  run bash -c "source '$SCRIPT' && printf 'hi' | _openai_request 'unsloth/gpt-oss-20b-GGUF:F16' '' 30 32 2>&1"
  [ "$status" -eq 0 ]
  ! grep -q "LEAKED-CODE" <<< "$output"
}

@test "request: no reachable host -> empty stdout, exit 0" {
  export CPP_SUCCEED_HOSTS=""
  run bash -c "source '$SCRIPT' && printf 'hi' | _openai_request 'unsloth/gpt-oss-20b-GGUF:F16' '' 30 32 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# llm_request — end-to-end through the OpenAI dispatch arm
# ---------------------------------------------------------------------------

@test "dispatch: llm_request routes a logical model through the openai arm" {
  export LLM_BACKEND=openai
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && printf 'hi' | llm_request "gpt-oss:20b" "" 30 32)
  [ "$result" = "OK" ]
  # The chat endpoint must have been hit (proves the openai arm, not ollama).
  grep -q '/v1/chat/completions' "$CURL_LOG_FILE"
}

@test "dispatch: num_predict of 0 is coerced to the default (no max_tokens:0)" {
  export LLM_BACKEND=openai
  export CPP_SUCCEED_HOSTS="localhost:8080"
  result=$(source "$SCRIPT" && printf 'hi' | llm_request "gpt-oss:20b" "" 30 0)
  [ "$result" = "OK" ]
}

# ===========================================================================
# Trust boundary: cache lives in a user-private state dir (S2)
# ===========================================================================

@test "state dir: default openai cache path is under XDG_RUNTIME_DIR, not /tmp" {
  unset _OPENAI_HOST_CACHE
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  mkdir -p "$XDG_RUNTIME_DIR"
  export CPP_SUCCEED_HOSTS="localhost:8080"
  setup_curl_mock
  source "$SCRIPT"
  openai_available
  [ -f "$XDG_RUNTIME_DIR/claude-llm-hooks/openai-host-cache" ]
}

# ===========================================================================
# LLM_TRUSTED_HOSTS (backend-agnostic trusted host list)
# ===========================================================================

@test "trusted hosts: bare LLM_TRUSTED_HOSTS entry joins the pool on port 8080" {
  export LLM_TRUSTED_HOSTS="trusted-1"
  export CPP_SUCCEED_HOSTS="trusted-1"
  result=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$result" = "http://trusted-1:8080" ]
}

@test "trusted hosts: localhost:8080 remains a candidate alongside LLM_TRUSTED_HOSTS" {
  export LLM_TRUSTED_HOSTS="trusted-1"
  export CPP_SUCCEED_HOSTS="trusted-1 localhost"
  source "$SCRIPT"
  openai_available
  grep -q '^http://trusted-1:8080' "$_OPENAI_HOST_CACHE"
  grep -q '^http://localhost:8080' "$_OPENAI_HOST_CACHE"
}

@test "trusted hosts: OPENAI_HOSTS is exclusive and overrides LLM_TRUSTED_HOSTS" {
  export OPENAI_HOSTS="only-a"
  export LLM_TRUSTED_HOSTS="trusted-1"
  export CPP_SUCCEED_HOSTS="only-a trusted-1"
  source "$SCRIPT"
  result=$(openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$result" = "http://only-a:8080" ]
  # The generic trusted host must never even be probed
  run grep -c 'trusted-1' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: openai cache is invalidated when LLM_TRUSTED_HOSTS changes" {
  export CPP_SUCCEED_HOSTS="trusted-1 localhost"
  first=$(export LLM_TRUSTED_HOSTS="trusted-1"; source "$SCRIPT" \
    && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  # Round-robins across trusted-1 and localhost -> both appear
  [[ "$first" == *"http://trusted-1:8080"* ]]
  # Trusted list revoked: the still-fresh cache must not serve trusted-1
  second=$(source "$SCRIPT" && openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$second" = "http://localhost:8080" ]
}

@test "trusted hosts: glob-metachar entry is treated literally, not CWD-expanded" {
  cd "$BATS_TEST_TMPDIR"
  : > decoy-file-a; : > decoy-file-b
  export LLM_TRUSTED_HOSTS="trusted-1 *"
  export CPP_SUCCEED_HOSTS="trusted-1"
  source "$SCRIPT"
  result=$(openai_host_for_model "unsloth/gpt-oss-20b-GGUF:F16")
  [ "$result" = "http://trusted-1:8080" ]
  run grep -c 'decoy-file' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

# ===========================================================================
# Multi-port probing (llama.cpp :8080 + vLLM :8000) and ds4 logical models
# ===========================================================================

@test "multi-port: a bare trusted host is probed on both 8080 and 8000" {
  export LLM_TRUSTED_HOSTS="dual-host"
  # Both ports answer /v1/models -> both URLs join the pool
  export CPP_SUCCEED_HOSTS="dual-host:8080 dual-host:8000"
  source "$SCRIPT"
  openai_available
  grep -q '^http://dual-host:8080' "$_OPENAI_HOST_CACHE"
  grep -q '^http://dual-host:8000' "$_OPENAI_HOST_CACHE"
}

@test "multi-port: only the reachable port joins when one is down" {
  export LLM_TRUSTED_HOSTS="vllm-only"
  # Only :8000 answers (vLLM), serving ds4; :8080 is down
  export CPP_SUCCEED_HOSTS="vllm-only:8000"
  export CPP_MODELS_JSON='{"data":[{"id":"deepseek-v4-flash"}]}'
  source "$SCRIPT"
  result=$(openai_host_for_model deepseek-v4-flash)
  [ "$result" = "http://vllm-only:8000" ]
  # :8080 was probed (log proves the attempt) but failed, so only :8000 pools
  grep -q 'vllm-only:8080/v1/models' "$CURL_LOG_FILE"
  grep -q '^http://vllm-only:8000' "$_OPENAI_HOST_CACHE"
  ! grep -q '^http://vllm-only:8080' "$_OPENAI_HOST_CACHE"
}

@test "multi-port: LLM_OPENAI_PORTS overrides the probed port set" {
  export LLM_TRUSTED_HOSTS="custom"
  export LLM_OPENAI_PORTS="9000"
  export CPP_SUCCEED_HOSTS="custom:9000 custom:8080 custom:8000"
  source "$SCRIPT"
  openai_available
  grep -q '^http://custom:9000' "$_OPENAI_HOST_CACHE"
  # default ports must NOT have been probed
  run grep -cE 'custom:(8080|8000)' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: cache is invalidated when LLM_OPENAI_PORTS changes" {
  export LLM_TRUSTED_HOSTS="host-x"
  export CPP_SUCCEED_HOSTS="host-x:8080 host-x:8000"
  first=$(export LLM_OPENAI_PORTS="8080"; source "$SCRIPT" \
    && openai_host_for_model unsloth/gpt-oss-20b-GGUF:F16)
  [ "$first" = "http://host-x:8080" ]
  # Change the port set: the still-fresh cache (written for :8080) must not be
  # reused; re-probe finds :8000 instead
  export CPP_SUCCEED_HOSTS="host-x:8000"
  second=$(export LLM_OPENAI_PORTS="8000"; source "$SCRIPT" \
    && openai_host_for_model unsloth/gpt-oss-20b-GGUF:F16)
  [ "$second" = "http://host-x:8000" ]
}

@test "model map: ds4:flash -> deepseek-v4-flash" {
  result=$(source "$SCRIPT" && openai_model_for "ds4:flash")
  [ "$result" = "deepseek-v4-flash" ]
}

@test "model map: ds4:pro -> deepseek-v4-pro" {
  result=$(source "$SCRIPT" && openai_model_for "ds4:pro")
  [ "$result" = "deepseek-v4-pro" ]
}

@test "model map: ds4 env override is honored" {
  export OPENAI_MODEL_DS4_PRO="deepseek-v4-pro-fp8"
  result=$(source "$SCRIPT" && openai_model_for "ds4:pro")
  [ "$result" = "deepseek-v4-pro-fp8" ]
}

@test "model routing: ds4 request routes to the vLLM host that has it" {
  export LLM_TRUSTED_HOSTS="vllm-box"
  export CPP_SUCCEED_HOSTS="vllm-box:8000"
  export CPP_MODELS_JSON='{"data":[{"id":"deepseek-v4-flash"},{"id":"deepseek-v4-pro"}]}'
  source "$SCRIPT"
  result=$(openai_host_for_model "$(openai_model_for ds4:pro)")
  [ "$result" = "http://vllm-box:8000" ]
}

@test "multi-port: glob-metachar in LLM_OPENAI_PORTS is treated literally" {
  cd "$BATS_TEST_TMPDIR"
  : > decoy-port-file
  export LLM_TRUSTED_HOSTS="host-g"
  export LLM_OPENAI_PORTS="8080 *"
  export CPP_SUCCEED_HOSTS="host-g:8080"
  source "$SCRIPT"
  openai_available
  grep -q '^http://host-g:8080' "$_OPENAI_HOST_CACHE"
  # The '*' must not have expanded into decoy-port-file as a probed "port"
  run grep -c 'decoy-port-file' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: default localhost is probed on 8080 only, never other ports" {
  # No LLM_TRUSTED_HOSTS: the implicit loopback default must not widen to :8000
  # even though 8000 is in the default LLM_OPENAI_PORTS set.
  export CPP_SUCCEED_HOSTS="localhost:8080 localhost:8000"
  source "$SCRIPT"
  openai_available
  grep -q '^http://localhost:8080' "$_OPENAI_HOST_CACHE"
  ! grep -q '^http://localhost:8000' "$_OPENAI_HOST_CACHE"
  # :8000 must never even be probed for the implicit localhost default
  run grep -c 'localhost:8000' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: localhost vLLM on 8000 requires explicit opt-in" {
  # Naming localhost in LLM_TRUSTED_HOSTS opts into multi-port probing for it.
  export LLM_TRUSTED_HOSTS="localhost"
  export CPP_SUCCEED_HOSTS="localhost:8000"
  export CPP_MODELS_JSON='{"data":[{"id":"deepseek-v4-flash"}]}'
  source "$SCRIPT"
  result=$(openai_host_for_model deepseek-v4-flash)
  [ "$result" = "http://localhost:8000" ]
}
