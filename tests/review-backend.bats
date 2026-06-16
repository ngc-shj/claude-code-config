#!/usr/bin/env bats
# Tests for skills/agent-review/review-backend.sh
# Stubs git / codex / claude so no real backend, repo, or network is touched.

bats_require_minimum_version 1.5.0

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$ROOT/skills/agent-review/review-backend.sh"
SCHEMA="$ROOT/skills/agent-review/schemas/review-output.schema.json"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_DIR"
  CAPTURE="$BATS_TEST_TMPDIR/capture"
  : > "$CAPTURE"
  export CAPTURE PATH="$STUB_DIR:$PATH"
}

# A stub that appends "<name> <args>" and its stdin to $CAPTURE, then emits $2.
make_stub() {
  local name="$1" stdout="${2:-}"
  cat > "$STUB_DIR/$name" <<EOF
#!/bin/bash
{ printf '%s ARGS: %s\n' "$name" "\$*"; printf '%s STDIN: ' "$name"; cat; printf '\n'; } >> "$CAPTURE"
printf '%s\n' "$stdout"
exit 0
EOF
  chmod +x "$STUB_DIR/$name"
}

# ---------------------------------------------------------------------------
# Argument parsing (codex backend computes its own diff, so no git stub needed)
# ---------------------------------------------------------------------------

@test "run codex: maps base:<branch> to 'codex review --base <branch>'" {
  make_stub codex
  run bash "$SCRIPT" run codex base:main
  [ "$status" -eq 0 ]
  grep -q "codex ARGS: review --base main" "$CAPTURE"
}

@test "run codex: maps commit:<sha> to 'codex review --commit <sha>'" {
  make_stub codex
  run bash "$SCRIPT" run codex commit:abc123
  [ "$status" -eq 0 ]
  grep -q "codex ARGS: review --commit abc123" "$CAPTURE"
}

@test "run codex: --adversarial injects an approach-challenging prompt plus focus" {
  make_stub codex
  run bash "$SCRIPT" run codex uncommitted "auth path" --adversarial
  [ "$status" -eq 0 ]
  grep -q "Adversarial review" "$CAPTURE"
  grep -q "auth path" "$CAPTURE"
}

@test "run codex: flag order is irrelevant (--adversarial before focus)" {
  make_stub codex
  run bash "$SCRIPT" run codex uncommitted --adversarial "auth path"
  [ "$status" -eq 0 ]
  grep -q "Adversarial review" "$CAPTURE"
  grep -q "auth path" "$CAPTURE"
}

@test "run: missing backend exits 1 with a clear message" {
  run bash "$SCRIPT" run
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing backend"* ]]
}

@test "run: unknown backend exits 1" {
  run bash "$SCRIPT" run frobnicate uncommitted
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown or missing backend"* ]]
}

@test "run codex backend-only (scope omitted) does not leak backend name as focus" {
  make_stub codex
  run bash "$SCRIPT" run codex
  [ "$status" -eq 0 ]
  # scope defaults to uncommitted; no stray 'codex' should appear as a prompt arg
  grep -q "codex ARGS: review --uncommitted" "$CAPTURE"
  ! grep -qE "review --uncommitted .*codex" "$CAPTURE"
}

# ---------------------------------------------------------------------------
# Ref validation (flag-injection / typo guard)
# ---------------------------------------------------------------------------

@test "run codex: flag-shaped base ref is rejected" {
  make_stub codex
  run bash "$SCRIPT" run codex "base:--evil"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid base ref"* ]]
}

# ---------------------------------------------------------------------------
# scope -> git command mapping (claude path; stub git + claude)
# ---------------------------------------------------------------------------

@test "run claude base:<branch>: builds 'git diff ... <branch>...HEAD' and forwards the diff read-only" {
  make_stub git "FAKEDIFF"
  make_stub claude
  run bash "$SCRIPT" run claude base:main "focus text"
  [ "$status" -eq 0 ]
  grep -q "git ARGS: diff -U10 main...HEAD" "$CAPTURE"
  # claude must receive the diff and be invoked read-only (no tools)
  grep -q "claude ARGS: -p --tools" "$CAPTURE"
  grep -q "FAKEDIFF" "$CAPTURE"
  grep -q "Focus on: focus text" "$CAPTURE"
}

@test "run claude: empty diff reports 'No changes' and exits 0 without calling claude" {
  make_stub git ""
  make_stub claude
  run bash "$SCRIPT" run claude uncommitted
  [ "$status" -eq 0 ]
  [[ "$output" == *"No changes in scope"* ]]
  ! grep -q "claude ARGS:" "$CAPTURE"
}

# ---------------------------------------------------------------------------
# detect ordering (ollama forced unavailable via empty hooks dir)
# ---------------------------------------------------------------------------

@test "detect: lists codex before claude (CLI backend preference order)" {
  make_stub codex
  make_stub claude
  CLAUDE_HOOKS_DIR="$BATS_TEST_TMPDIR/no-hooks" run bash "$SCRIPT" detect
  [ "$status" -eq 0 ]
  # ollama excluded (no llm-commands.sh under hooks dir); codex precedes claude
  codex_line=$(printf '%s\n' "$output" | grep -n '^codex$'  | cut -d: -f1)
  claude_line=$(printf '%s\n' "$output" | grep -n '^claude$' | cut -d: -f1)
  [ -n "$codex_line" ] && [ -n "$claude_line" ] && [ "$codex_line" -lt "$claude_line" ]
}

# ---------------------------------------------------------------------------
# Output schema is valid and has the canonical shape SKILL.md normalizes into
# ---------------------------------------------------------------------------

@test "review-output schema is valid JSON" {
  run jq empty "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "review-output schema requires the canonical top-level fields" {
  required=$(jq -r '.required | sort | join(",")' "$SCHEMA")
  [ "$required" = "backend,findings,next_steps,summary,verdict" ]
}

@test "a conforming review object validates against the schema's basic structure" {
  obj='{"backend":"ollama","verdict":"needs-attention","summary":"x","findings":[{"severity":"Major","title":"t","file":"a.sh","recommendation":"r"}],"next_steps":[]}'
  run bash -c "printf '%s' '$obj' | jq -e '
    .backend and .verdict and .summary and (.findings|type==\"array\") and (.next_steps|type==\"array\")
    and (.findings[0] | .severity and .title and .file and .recommendation)'"
  [ "$status" -eq 0 ]
}
