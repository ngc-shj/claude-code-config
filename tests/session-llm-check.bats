#!/usr/bin/env bats
# Tests for hooks/session-llm-check.sh
#
# The hook exists because of a failure that produced no failure: the host list
# was repointed at a server that did not serve the configured model, and every
# LLM-backed hook went on "succeeding" by returning empty. So the cases that
# matter are the two silences — a healthy pool and an unconfigured machine must
# say nothing, or the warning becomes noise nobody reads — and the one voice.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO/hooks/session-llm-check.sh"

# Mock curl: /v1/models answers for hosts named in CPP_SUCCEED_HOSTS, serving
# CPP_MODELS_JSON. Mirrors tests/openai-backend.bats so both describe the same
# server surface.
setup_curl_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
URL=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in http://*|https://*) URL="${args[i]}" ;; esac
done
MODELS="${CPP_MODELS_JSON:-}"
[ -z "$MODELS" ] && MODELS='{"data":[{"id":"served/model:Q4"}]}'
case "$URL" in
  */v1/models)
    for h in ${CPP_SUCCEED_HOSTS:-}; do
      if [[ "$URL" == *"$h"* ]]; then printf '%s' "$MODELS"; exit 0; fi
    done
    exit 28 ;;
esac
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
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/xdg" TMPDIR="$BATS_TEST_TMPDIR"
  mkdir -p "$XDG_RUNTIME_DIR"
  export OLLAMA_HOST="http://dummy-ollama:11434"
  export LLM_BACKEND=openai
  unset OPENAI_HOST OPENAI_HOSTS LLM_TRUSTED_HOSTS
  unset OPENAI_MODEL OPENAI_MODEL_THINK OPENAI_MODEL_NOTHINK OPENAI_MODEL_SMALL OPENAI_MODEL_LARGE
  setup_curl_mock
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

@test "silent when no LLM host is configured at all" {
  unset OLLAMA_HOST LLM_BACKEND
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when the configured model is served by a reachable host" {
  export OPENAI_HOSTS="good:8080" LLM_TRUSTED_HOSTS="good:8080"
  export OPENAI_MODEL="served/model:Q4"
  export CPP_SUCCEED_HOSTS="good:8080"
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The exact failure this hook was written for: hosts repointed, model left
# behind. Both slots resolve to a model id nothing in the pool serves.
@test "warns when the pool serves no host for the configured model" {
  export OPENAI_HOSTS="good:8080" LLM_TRUSTED_HOSTS="good:8080"
  export OPENAI_MODEL="absent/model:Q4"
  export CPP_SUCCEED_HOSTS="good:8080"
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "SessionStart" ]
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"llm:nothink -> absent/model:Q4"* ]]
  [[ "$ctx" == *"llm:think -> absent/model:Q4"* ]]
  # The point of the warning is that the failure is silent, so say so.
  [[ "$ctx" == *"skipped silently"* ]]
}

@test "warns when the whole pool is unreachable" {
  export OPENAI_HOSTS="down:8080" LLM_TRUSTED_HOSTS="down:8080"
  export OPENAI_MODEL="served/model:Q4"
  export CPP_SUCCEED_HOSTS=""
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Local LLM misconfigured"* ]]
}

# A split configuration is the case where naming only one slot would mislead.
@test "names only the slot that cannot be served" {
  export OPENAI_HOSTS="good:8080" LLM_TRUSTED_HOSTS="good:8080"
  export OPENAI_MODEL_NOTHINK="served/model:Q4"
  export OPENAI_MODEL_THINK="absent/model:Q4"
  export CPP_SUCCEED_HOSTS="good:8080"
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"llm:think -> absent/model:Q4"* ]]
  [[ "$ctx" != *"llm:nothink"* ]]
}

@test "emits valid JSON on one line" {
  export OPENAI_HOSTS="good:8080" LLM_TRUSTED_HOSTS="good:8080"
  export OPENAI_MODEL="absent/model:Q4"
  export CPP_SUCCEED_HOSTS="good:8080"
  run bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  jq -e . >/dev/null <<<"$output"
}

# A SessionStart hook that fails must not take the session with it.
@test "exits 0 when jq is unavailable" {
  export OPENAI_HOSTS="good:8080" OPENAI_MODEL="absent/model:Q4"
  printf '#!/bin/bash\nexit 127\n' > "$BATS_TEST_TMPDIR/jq"
  chmod +x "$BATS_TEST_TMPDIR/jq"
  run env PATH="$BATS_TEST_TMPDIR:$PATH" bash "$SCRIPT" <<<'{"source":"startup"}'
  [ "$status" -eq 0 ]
}

@test "exits 0 on malformed stdin" {
  export OPENAI_HOSTS="good:8080" LLM_TRUSTED_HOSTS="good:8080"
  export OPENAI_MODEL="served/model:Q4" CPP_SUCCEED_HOSTS="good:8080"
  run bash "$SCRIPT" <<<'not json at all'
  [ "$status" -eq 0 ]
}
