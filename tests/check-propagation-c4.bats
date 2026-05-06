#!/usr/bin/env bats
# Tests for check-propagation.sh C4 — AST-driven signature change detection
# with caller-side text-grep. C1-C3 (regex categories) have no dedicated
# bats coverage yet; this file is scoped to the new C4 path.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/check-propagation.sh"

setup() {
  if ! command -v node >/dev/null 2>&1; then
    skip "node not on PATH"
  fi
  if [ ! -d "$REPO_ROOT/hooks/lib/node_modules/typescript" ]; then
    skip "typescript module not provisioned"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not on PATH"
  fi
  WORK="$(mktemp -d)"
  (cd "$WORK" && git init -q && git config user.email t@t && git config user.name t)
}

teardown() {
  rm -rf "$WORK"
}

# Helper: stage a base commit with $1 (repo.ts contents) and $2 (caller.ts
# contents), then mutate repo.ts to $3 and commit. Leaves the work tree at
# HEAD with a one-commit diff against HEAD~1.
seed_repo() {
  printf '%s\n' "$1" > "$WORK/repo.ts"
  printf '%s\n' "$2" > "$WORK/caller.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
  printf '%s\n' "$3" > "$WORK/repo.ts"
  (cd "$WORK" && git add -A && git commit -qm mutate)
}

@test "C4: param-count change with surviving caller is flagged Minor" {
  seed_repo \
    'export class Repo { findById(id: string): unknown { return null; } }' \
    'import { Repo } from "./repo"; const r = new Repo(); r.findById("abc");' \
    'export class Repo { findById(id: string, opts?: object): unknown { return null; } }'
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## C4 Signature change"* ]]
  [[ "$output" == *"params 1 → 2"* ]]
  [[ "$output" == *"[Minor]"* ]]
  [[ "$output" == *"caller.ts"* ]]
}

@test "C4: removed function with surviving caller is flagged Major" {
  seed_repo \
    'export function gone(x: number): void {}' \
    'import { gone } from "./repo"; gone(1);' \
    'export function stillHere(): void {}'
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"* ]]
  [[ "$output" == *"[Major]"* ]]
}

@test "C4: param-shape (type) change is flagged" {
  # Function name must be >= IDENT_MIN_LENGTH (4) to be flagged. Single
  # letters are deliberately filtered (test below covers that).
  seed_repo \
    'export function compute(a: number): void {}' \
    'import { compute } from "./repo"; compute(123);' \
    'export function compute(a: string): void {}'
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"param-shape"* ]]
  [[ "$output" == *"number"* ]]
  [[ "$output" == *"string"* ]]
}

@test "C4: identical signature → no false positive on same name in caller" {
  # repo.ts has an unrelated change (added export) — f's signature unchanged.
  # The caller calling f() should NOT be flagged.
  seed_repo \
    'export function f(a: number): void {}' \
    'import { f } from "./repo"; f(1);' \
    'export function f(a: number): void {} export const VERSION = 2;'
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # C4 should report no signature changes with surviving callers.
  [[ "$output" == *"(no signature changes with surviving callers found)"* ]]
}

@test "C4: short identifier names are skipped (collide too widely)" {
  # Single-letter / 2-char names match every variable in the codebase. The
  # hook's IDENT_MIN_LENGTH default (4) suppresses these.
  seed_repo \
    'export function f(a: number): void {}' \
    'import { f } from "./repo"; const a = 1; f(a);' \
    'export function f(a: number, b: number): void {}'
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # 'f' is below IDENT_MIN_LENGTH so even though its arity changed, no
  # caller flagging happens (would be too noisy).
  [[ "$output" != *"calls 'f'"* ]]
}

@test "C4: non-TS files in diff don't break the hook" {
  printf '# README\n' > "$WORK/README.md"
  printf 'export function findById(id: string): void {}\n' > "$WORK/repo.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
  printf '# README updated\n' > "$WORK/README.md"
  (cd "$WORK" && git add -A && git commit -qm "docs only")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## C4 Signature change"* ]]
  [[ "$output" == *"(no AST-supported source files in diff)"* ]]
}

@test "C4 graceful skip: no AST runtime → C1-C3 still run" {
  # Simulate runtime-missing by overriding PATH to hide node.
  printf 'export function gone(x: number): void {}\n' > "$WORK/repo.ts"
  printf 'import { gone } from "./repo"; gone(1);\n' > "$WORK/caller.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
  printf 'export function stillHere(): void {}\n' > "$WORK/repo.ts"
  (cd "$WORK" && git add -A && git commit -qm "remove gone")

  # Stub PATH excludes node — but keep coreutils, git, grep, awk, sed.
  # find /usr/bin /bin /usr/local/bin for what we need; node is NOT there in
  # this environment because it's installed via linuxbrew. So we just
  # restrict PATH to /usr/bin:/bin.
  run bash -c "cd '$WORK' && PATH=/usr/bin:/bin bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # C1-C3 must still run.
  [[ "$output" == *"## C1 Symbol rename"* ]]
  [[ "$output" == *"## C2 Constant value change"* ]]
  [[ "$output" == *"## C3 String literal change"* ]]
  # C4 should be present but degraded (no AST output expected).
  [[ "$output" == *"## C4 Signature change"* ]]
}
