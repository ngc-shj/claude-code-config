#!/usr/bin/env bats
# Tests for hooks/check-pre-pr.sh — verifies that `git push` and
# `gh pr create` are gated on the project's scripts/pre-pr.sh, while
# non-push commands and projects without the script are no-op.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/check-pre-pr.sh"

setup() {
  TMPREPO=$(mktemp -d)
  (cd "$TMPREPO" && git init -q && git config user.email t@t && git config user.name t)
  ORIG_PWD=$PWD
  cd "$TMPREPO"
  # Unset so the hook falls back to git rev-parse from $TMPREPO instead
  # of using whatever CLAUDE_PROJECT_DIR the test runner inherited.
  unset CLAUDE_PROJECT_DIR
  # Keep git's upward repo discovery inside the tmp tree (matters once
  # .git is deleted mid-test, e.g. T16 — an outer repo must never leak in).
  export GIT_CEILING_DIRECTORIES="$(dirname "$TMPREPO")"
}

teardown() {
  cd "$ORIG_PWD"
  # The run-count fixture lives OUTSIDE $TMPREPO (a counter inside the repo
  # would mutate the fingerprint and defeat cache-hit tests) — remove it too.
  rm -f "$TMPREPO/../run-count-$(basename "$TMPREPO")"
  rm -rf "$TMPREPO"
}

run_hook() {
  local tool_name="$1"
  local command="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg c "$command" \
    '{tool_name:$n, tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# run_direct: stdin closed (</dev/null) so a mode-dispatch regression that
# falls through to hook mode's `INPUT=$(cat)` fails red immediately instead
# of hanging the suite.
run_direct() {
  bash "$SCRIPT" run </dev/null
}

write_script() {
  mkdir -p scripts
  printf '%s\n' "$@" > scripts/pre-pr.sh
  chmod +x scripts/pre-pr.sh
}

# commit_baseline: cache tests need a committed HEAD (the plain setup()
# leaves an unborn HEAD, which deliberately fails fingerprinting).
commit_baseline() {
  git add -A
  git commit -q -m baseline
}

# ============================================================
# APPROVE — no-op cases
# ============================================================

@test "approve: non-Bash tool" {
  run run_hook Read ""
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: Bash with non-push command" {
  run run_hook Bash "ls -la"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git push but no scripts/pre-pr.sh in repo" {
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gh pr create but no scripts/pre-pr.sh in repo" {
  run run_hook Bash "gh pr create --title foo --body bar"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git fetch (not a push verb)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git fetch origin"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: git pushd (substring false-positive avoidance)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "pushd /tmp"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: 'git pushd' (verb extending 'push' must not match)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git pushd /some/repo"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: malformed JSON on stdin fails open" {
  run bash -c "printf 'garbage not json' | bash '$SCRIPT'"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$status" -eq 0 ]
}

@test "approve: chmod -x scripts/pre-pr.sh is treated as absent (hook gates on -x)" {
  write_script '#!/bin/bash' 'exit 1'
  chmod -x scripts/pre-pr.sh
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: outside any git repo, no CLAUDE_PROJECT_DIR" {
  cd /
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# APPROVE — pre-pr.sh passes
# ============================================================

@test "approve: git push and pre-pr.sh exits 0" {
  write_script '#!/bin/bash' 'echo ok' 'exit 0'
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: gh pr create and pre-pr.sh exits 0" {
  write_script '#!/bin/bash' 'exit 0'
  run run_hook Bash "gh pr create --draft"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# BLOCK — pre-pr.sh fails
# ============================================================

@test "block: git push and pre-pr.sh exits non-zero" {
  write_script '#!/bin/bash' 'echo FAIL' 'exit 1'
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"pre-pr.sh"* ]]
}

@test "block: gh pr create and pre-pr.sh exits non-zero" {
  write_script '#!/bin/bash' 'exit 2'
  run run_hook Bash "gh pr create --title foo"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: git push --force-with-lease still gated by pre-pr.sh" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push --force-with-lease origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: rtk-rewritten git push still gated" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "rtk git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block reason contains pre-pr.sh stdout" {
  write_script '#!/bin/bash' 'echo SENTINEL_OUTPUT' 'exit 1'
  run run_hook Bash "git push"
  [[ "$output" == *"SENTINEL_OUTPUT"* ]]
}

# ============================================================
# BLOCK — shell-separator coverage (F1 fix)
# ============================================================

@test "block: 'git push;echo done' (semicolon separator)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push;echo done"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: 'git push|tee log' (pipe separator)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push|tee log"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: '(git push)' (subshell wrap)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "(git push)"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: 'git push&&echo done' (logical-and)" {
  write_script '#!/bin/bash' 'exit 1'
  run run_hook Bash "git push&&echo done"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "block: symlinked scripts/pre-pr.sh still gated" {
  mkdir -p scripts target
  cat > target/real-pre-pr.sh <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x target/real-pre-pr.sh
  ln -s "$(pwd)/target/real-pre-pr.sh" scripts/pre-pr.sh
  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# BLOCK — truncation branch (T1)
# ============================================================

@test "block: large pre-pr.sh output is tail-truncated and notes basename" {
  write_script '#!/bin/bash' \
    'python3 -c "import sys; sys.stdout.write(\"X\" * 5000); sys.stdout.write(\"\\nTAIL_SENTINEL\\n\")"' \
    'exit 1'
  run run_hook Bash "git push"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"truncated to last 4000 bytes"* ]]
  [[ "$output" == *"TAIL_SENTINEL"* ]]
  # Truncation note uses basename only — should not contain a leading slash
  # near the "preserved" word, only $TMPDIR/<basename>.
  [[ "$output" == *'preserved in $TMPDIR/pre-pr-gate.'* ]]
}

# ============================================================
# ESCAPE HATCH
# ============================================================

@test "approve: SKIP_PRE_PR_GATE=1 bypasses a failing script" {
  write_script '#!/bin/bash' 'exit 1'
  input=$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')
  run env SKIP_PRE_PR_GATE=1 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$input"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "SKIP_PRE_PR_GATE=1 emits stderr breadcrumb" {
  write_script '#!/bin/bash' 'exit 1'
  input=$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push"}}')
  # `run` merges stderr by default in bats 1.5+; the breadcrumb should appear.
  run env SKIP_PRE_PR_GATE=1 bash -c 'bash "$1" 2>&1' _ "$SCRIPT" <<<"$input"
  [[ "$output" == *"SKIP_PRE_PR_GATE=1"* ]]
  [[ "$output" == *"bypassing"* ]]
}

# ============================================================
# SKILL-DOC CONTRACT (T5)
# Ensures the /triangulate phase docs continue to reference
# scripts/pre-pr.sh literally — if the docs drift to a different name
# (e.g. `npm run pre-pr`), the hook's hardcoded path would silently
# diverge from the doc contract.
# ============================================================

@test "skill docs reference scripts/pre-pr.sh literally" {
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  grep -q 'scripts/pre-pr.sh' "$repo_root/skills/triangulate/phases/phase-2-coding.md"
  grep -q 'scripts/pre-pr.sh' "$repo_root/skills/triangulate/phases/phase-3-review.md"
}

# T17: phase docs must call the cache-aware wrapper, and must never spell
# a raw invocation of scripts/pre-pr.sh (which would bypass the cache and
# re-introduce the triple run this plan eliminates).
@test "skill docs invoke check-pre-pr.sh run, not a raw scripts/pre-pr.sh invocation" {
  local repo_root phase2 phase3
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  phase2="$repo_root/skills/triangulate/phases/phase-2-coding.md"
  phase3="$repo_root/skills/triangulate/phases/phase-3-review.md"

  grep -q 'check-pre-pr.sh run' "$phase2"
  grep -q 'check-pre-pr.sh run' "$phase3"

  ! grep -qE 'bash [^ ]*scripts/pre-pr\.sh' "$phase2"
  ! grep -qE 'bash [^ ]*scripts/pre-pr\.sh' "$phase3"
}

# ============================================================
# PASS-CACHE MATRIX (C6, plan: docs/archive/review/pre-pr-gate-cache-plan.md)
# T8c (foreign-owned cache file) is intentionally absent — not mechanically
# testable in unprivileged bats (would require root to chown a file to
# another user); documented in the plan as covered-by-code-review instead.
# ============================================================

# run-count fixture lives OUTSIDE the repo tree so it never becomes an
# untracked file that would itself change the fingerprint (which would
# defeat every cache-hit assertion). Only T11 deliberately counts inside.
write_counting_script() {
  local counter="$1"
  shift
  write_script '#!/bin/bash' "echo run >> '$counter'" "$@"
}

@test "T1: pass, identical tree, push again -> cache hit (run-count stays 1, breadcrumb)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  run bash -c 'bash "$1" 2>&1' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [[ "$output" == *'"decision": "approve"'* ]]
  [[ "$output" == *"already passed for identical source state"* ]]

  [ "$(wc -l <"$counter")" -eq 1 ]
}

@test "T2: pass, modify tracked file, push -> cache miss (run-count 2)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  printf 'changed\n' >> scripts/pre-pr.sh
  chmod +x scripts/pre-pr.sh

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T3: pass, add untracked file, push -> cache miss (run-count 2)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  printf 'untracked\n' > untracked-file.txt

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T3b: dash-prefixed untracked filename is hashed as content, not parsed as a sha256sum option" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline
  printf 'v1\n' > ./--help

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$(wc -l <"$counter")" -eq 1 ]

  # Content change in the dash-named file MUST invalidate the cache. An
  # implementation without the ./-prefix lets sha256sum eat `--help` as an
  # option, the file drops out of the fingerprint, and this stays a hit.
  printf 'v2\n' > ./--help

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T3c: untracked file literally named '-' is hashed as content, not read as stdin" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline
  printf 'v1\n' > ./-

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$(wc -l <"$counter")" -eq 1 ]

  # GNU sha256sum treats a bare '-' operand as stdin even after '--'; the
  # ./-prefix makes it a real file. Without it, content changes to ./- are
  # fingerprint-invisible and this second push would stay a stale hit.
  printf 'v2 totally different content\n' > ./-

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T4: pass, commit, push -> cache miss (HEAD changed, run-count 2)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  printf 'more\n' > another-file.txt
  git add another-file.txt
  git commit -q -m "second commit"

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T5: pass, backdate cache stamp beyond TTL -> cache miss (run-count 2)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file old_stamp new_stamp fp
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  fp="$(awk '{print $1}' "$cache_file")"
  new_stamp=$(( $(date +%s) - 7200 ))
  printf '%s %s\n' "$fp" "$new_stamp" > "$cache_file"

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T6: PRE_PR_CACHE_TTL=0 -> two passing pushes both run, no cache file ever created" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  local cache_file
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"

  run env PRE_PR_CACHE_TTL=0 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ ! -e "$cache_file" ]

  run env PRE_PR_CACHE_TTL=0 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ ! -e "$cache_file" ]

  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T7: failing script, same tree, push again -> block twice, run-count 2 (failures uncached)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 1'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision":"block"'* ]]

  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T8a: malformed cache file content -> cache miss, no crash (run-count increments)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  printf 'not-a-valid-cache-line\n' > "$cache_file"

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T8b: symlinked cache file -> cache miss, no crash (run-count increments)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file real_target
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  real_target="$TMPREPO/../symlink-target-$$"
  cp "$cache_file" "$real_target"
  rm -f "$cache_file"
  ln -s "$real_target" "$cache_file"

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T9: run mode, failing script -> wrapper exit == script exit (R44)" {
  write_script '#!/bin/bash' 'exit 42'
  commit_baseline

  run run_direct
  [ "$status" -eq 42 ]
}

@test "T10: run mode pass, then hook-mode push -> push approves, run-count stays 1 (cross-pattern dedup)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_direct
  [ "$status" -eq 0 ]

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  [ "$(wc -l <"$counter")" -eq 1 ]
}

@test "T11: self-mutating passing script -> not recorded, second push runs again" {
  # This is the one fixture allowed to write INSIDE the repo tree: the
  # mutation itself (touching a tracked file) is the point of the test.
  write_script '#!/bin/bash' 'echo mutated >> mutation-marker.txt' 'git add -A' 'exit 0'
  printf 'seed\n' > mutation-marker.txt
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  # No cache recorded after the first (mutating) run means the second push
  # re-executed the script rather than skipping — observe via a second
  # counter-based script would double-count; instead assert the mutation
  # marker grew by exactly 2 lines (seed + one append per run).
  [ "$(wc -l <mutation-marker.txt)" -eq 3 ]
}

@test "T12: future-dated cache stamp -> cache miss (run-count increments)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file fp future_stamp
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  fp="$(awk '{print $1}' "$cache_file")"
  future_stamp=$(( $(date +%s) + 3600 ))
  printf '%s %s\n' "$fp" "$future_stamp" > "$cache_file"

  run run_hook Bash "git push origin main"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T13: run mode, no scripts/pre-pr.sh -> exit 0, note printed" {
  printf 'seed\n' > seed.txt
  commit_baseline

  run run_direct
  [ "$status" -eq 0 ]
  [[ "$output" == *"no scripts/pre-pr.sh"* ]]
}

@test "T14: run mode, unknown arg -> exit 2, usage on stderr" {
  printf 'seed\n' > seed.txt
  commit_baseline

  run bash -c 'bash "$1" bogus-arg 2>&1' _ "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: check-pre-pr.sh [run]"* ]]
}

@test "T14b: run mode with extra arg -> exit 2, usage on stderr (C4: run takes no other args)" {
  write_script '#!/bin/bash' 'exit 0'
  commit_baseline

  run bash -c 'bash "$1" run extra-arg 2>&1 </dev/null' _ "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: check-pre-pr.sh [run]"* ]]
}

@test "T15: run mode outside any git repo, no CLAUDE_PROJECT_DIR -> exit 2, stderr note" {
  local outside
  outside=$(mktemp -d)

  run bash -c 'cd "$1" && unset CLAUDE_PROJECT_DIR && bash "$2" run </dev/null 2>&1' _ "$outside" "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not resolve repo root — gate not run"* ]]

  rm -rf "$outside"
}

@test "T16: run mode, passing script deletes .git during run -> wrapper exit 0, passthrough present" {
  write_script '#!/bin/bash' 'echo PASSTHROUGH_SENTINEL' 'rm -rf .git' 'exit 0'
  commit_baseline

  run run_direct
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASSTHROUGH_SENTINEL"* ]]
}

@test "T18: PRE_PR_CACHE_TTL=999999999, stamp aged past the 86400 cap -> cache miss (cap enforced)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file fp stamp
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  fp="$(awk '{print $1}' "$cache_file")"
  stamp=$(( $(date +%s) - 90000 ))
  printf '%s %s\n' "$fp" "$stamp" > "$cache_file"

  run env PRE_PR_CACHE_TTL=999999999 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [ "$(wc -l <"$counter")" -eq 2 ]
}

@test "T18b: PRE_PR_CACHE_TTL=999999999, stamp aged within the cap -> cache hit (run-count stays 1)" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file fp stamp
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  fp="$(awk '{print $1}' "$cache_file")"
  stamp=$(( $(date +%s) - 50000 ))
  printf '%s %s\n' "$fp" "$stamp" > "$cache_file"

  run env PRE_PR_CACHE_TTL=999999999 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [ "$(wc -l <"$counter")" -eq 1 ]
}

@test "T19: PRE_PR_CACHE_TTL=abc with fresh matching cache -> no crash, skip occurs, fallback note" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  run env PRE_PR_CACHE_TTL=abc bash -c 'bash "$1" 2>&1' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [[ "$output" == *'"decision": "approve"'* ]]
  [[ "$output" == *"is not a non-negative integer; using default 3600"* ]]
  [ "$(wc -l <"$counter")" -eq 1 ]
}

@test "T19b: PRE_PR_CACHE_TTL=08 (leading-zero base-10 trap), stamp aged 100s -> no crash, cache miss" {
  local counter="$TMPREPO/../run-count-$(basename "$TMPREPO")"
  write_counting_script "$counter" 'exit 0'
  commit_baseline

  run run_hook Bash "git push origin main"
  [[ "$output" == *'"decision": "approve"'* ]]

  local cache_file fp stamp
  cache_file="$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass"
  fp="$(awk '{print $1}' "$cache_file")"
  stamp=$(( $(date +%s) - 100 ))
  printf '%s %s\n' "$fp" "$stamp" > "$cache_file"

  run env PRE_PR_CACHE_TTL=08 bash -c 'bash "$1"' _ "$SCRIPT" <<<"$(jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin main"}}')"
  [ "$(wc -l <"$counter")" -eq 2 ]
}
