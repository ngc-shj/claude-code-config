#!/usr/bin/env bats
# Tests for hooks/block-destructive-docker.sh — verify deny patterns and
# benign-command approval. Triggered by a dev DB data-loss incident from
# `docker compose down -v`; this fixture is the regression check.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-destructive-docker.sh"

# Helper: build minimal PreToolUse JSON and pipe to the hook. Returns the
# hook's stdout (JSON decision).
run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# DENY cases — destructive docker volume operations
# ============================================================

@test "deny: docker compose down -v" {
  run run_hook Bash "docker compose down -v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose down --volumes" {
  run run_hook Bash "docker compose down --volumes"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose down --volumes=true (attached value)" {
  run run_hook Bash "docker compose down --volumes=true"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker-compose down -v (hyphen variant)" {
  run run_hook Bash "docker-compose down -v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose down -tv (combined short flags)" {
  run run_hook Bash "docker compose down -tv"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose down -vt 30 (combined, v first)" {
  run run_hook Bash "docker compose down -vt 30"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose down -t 30 -v (flag before -v)" {
  run run_hook Bash "docker compose down -t 30 -v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: bash -c 'docker compose down -v' (wrapper)" {
  run run_hook Bash "bash -c 'docker compose down -v'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker\\tcompose down -v (tab whitespace)" {
  run run_hook Bash $'docker\tcompose down -v'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker  compose  down  -v (multi-space)" {
  run run_hook Bash "docker  compose  down  -v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose rm -v" {
  run run_hook Bash "docker compose rm -v"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker compose rm --volumes -f" {
  run run_hook Bash "docker compose rm --volumes -f"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker volume rm <name>" {
  run run_hook Bash "docker volume rm passwd-sso_postgres_data"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker volume rm -f <name>" {
  run run_hook Bash "docker volume rm -f myvol"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker volume prune -f" {
  run run_hook Bash "docker volume prune -f"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker system prune --volumes -f" {
  run run_hook Bash "docker system prune --volumes -f"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: docker system prune -a --volumes" {
  run run_hook Bash "docker system prune -a --volumes"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny block reason mentions override path settings.local.json" {
  run run_hook Bash "docker volume rm xyz"
  [[ "$output" == *"settings.local.json"* ]]
}

# ============================================================
# APPROVE cases — benign / non-destructive commands
# ============================================================

@test "approve: docker compose down (no volume flag)" {
  run run_hook Bash "docker compose down"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker compose down -t 30 (timeout flag, no -v)" {
  run run_hook Bash "docker compose down -t 30"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker compose down --remove-orphans" {
  run run_hook Bash "docker compose down --remove-orphans"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker compose stop" {
  run run_hook Bash "docker compose stop"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker rm <container> (not a volume rm)" {
  run run_hook Bash "docker rm my-container"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker run --rm myimage (--rm flag is not 'rm' subcommand)" {
  run run_hook Bash "docker run --rm myimage"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker volume ls" {
  run run_hook Bash "docker volume ls"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker volume inspect <name>" {
  run run_hook Bash "docker volume inspect myvol"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker compose ps" {
  run run_hook Bash "docker compose ps"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker system prune (no volume flag)" {
  run run_hook Bash "docker system prune"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: docker system prune -f (force, no volume)" {
  run run_hook Bash "docker system prune -f"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git commit (Bash but unrelated to docker)" {
  run run_hook Bash "git commit -m 'msg'"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: non-Bash tool (Edit)" {
  run run_hook Edit "/tmp/foo.txt"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: empty command" {
  run run_hook Bash ""
  [[ "$output" == *'"decision": "approve"'* ]]
}
