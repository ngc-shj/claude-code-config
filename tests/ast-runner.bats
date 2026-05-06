#!/usr/bin/env bats
# Tests for hooks/lib/ast-runner.js — TypeScript Compiler API based
# signature extraction and diffing. Skipped automatically if Node or the
# typescript module are not provisioned (CI environments without npm
# install pre-step).

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RUNNER="$REPO_ROOT/hooks/lib/ast-runner.js"
NODE_MODULES="$REPO_ROOT/hooks/lib/node_modules"

setup() {
  if ! command -v node >/dev/null 2>&1; then
    skip "node not on PATH"
  fi
  if [ ! -d "$NODE_MODULES/typescript" ]; then
    skip "typescript module not installed (run: npm install --prefix $REPO_ROOT/hooks/lib)"
  fi
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

run_runner() {
  NODE_PATH="$NODE_MODULES" node "$RUNNER" "$@"
}

@test "extract-signatures: top-level function with typed params and return" {
  cat > "$WORK/a.ts" <<'EOF'
export function foo(a: number, b: string): boolean {
  return a > 0;
}
EOF
  run run_runner extract-signatures "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"foo"'* ]]
  [[ "$output" == *'"kind":"function"'* ]]
  [[ "$output" == *'"returnType":"boolean"'* ]]
}

@test "extract-signatures: class methods carry owner = class name" {
  cat > "$WORK/a.ts" <<'EOF'
export class Repo {
  findById(id: string): unknown { return null; }
}
EOF
  run run_runner extract-signatures "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"owner":"Repo"'* ]]
  [[ "$output" == *'"kind":"method"'* ]]
}

@test "extract-signatures: arrow function via export const" {
  cat > "$WORK/a.ts" <<'EOF'
export const handler = (req: { id: string }): Promise<void> => Promise.resolve();
EOF
  run run_runner extract-signatures "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"handler"'* ]]
  [[ "$output" == *'"kind":"arrow"'* ]]
}

@test "extract-signatures: optional and rest params are tagged" {
  cat > "$WORK/a.ts" <<'EOF'
function f(a: number, b?: string, ...rest: any[]): void {}
EOF
  run run_runner extract-signatures "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"optional":true'* ]]
  [[ "$output" == *'"rest":true'* ]]
}

@test "diff-signatures: param-count change is reported" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: number, b: string): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"param-count"'* ]]
  [[ "$output" == *'"name":"f"'* ]]
}

@test "diff-signatures: param-shape change (type) is reported" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: string): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"param-shape"'* ]]
  [[ "$output" == *"number"* ]]
  [[ "$output" == *"string"* ]]
}

@test "diff-signatures: return-type change is reported" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(): number { return 0; }
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(): string { return ""; }
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"return-type"'* ]]
}

@test "diff-signatures: removed function is reported" {
  cat > "$WORK/base.ts" <<'EOF'
export function gone(x: number): void {}
export function kept(): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function kept(): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed"'* ]]
  [[ "$output" == *'"name":"gone"'* ]]
  [[ "$output" != *'"name":"kept"'* ]]
}

@test "diff-signatures: identical signatures produce empty array" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number, b: string): boolean { return true; }
EOF
  cp "$WORK/base.ts" "$WORK/head.ts"
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "diff-signatures: methods are matched by class.method key" {
  cat > "$WORK/base.ts" <<'EOF'
export class Repo {
  findById(id: string): void {}
}
export class Cache {
  findById(id: number): void {}
}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export class Repo {
  findById(id: string, opts: object): void {}
}
export class Cache {
  findById(id: number): void {}
}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  # Only Repo.findById changed; Cache.findById should not be reported.
  [[ "$output" == *'"owner":"Repo"'* ]]
  [[ "$output" != *'"owner":"Cache"'* ]]
}

@test "diff-signatures: severity Major on required-param addition" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: number, b: string): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"severity":"Major"'* ]]
}

@test "diff-signatures: severity Minor on optional-param addition" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: number, b?: string): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"severity":"Minor"'* ]]
}

@test "diff-signatures: severity Minor on default-valued param addition" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: number, b: string = ""): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"severity":"Minor"'* ]]
}

@test "diff-signatures: severity Major on removed function" {
  cat > "$WORK/base.ts" <<'EOF'
export function gone(x: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"severity":"Major"'* ]]
}

@test "diff-signatures: severity Minor on param-shape (type) change" {
  cat > "$WORK/base.ts" <<'EOF'
export function f(a: number): void {}
EOF
  cat > "$WORK/head.ts" <<'EOF'
export function f(a: string): void {}
EOF
  run run_runner diff-signatures "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"severity":"Minor"'* ]]
}

@test "extract-enums: numeric enum (auto-numbered) member values are null" {
  cat > "$WORK/a.ts" <<'EOF'
export enum Role { ADMIN, USER, GUEST }
EOF
  run run_runner extract-enums "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Role"'* ]]
  [[ "$output" == *'"name":"ADMIN"'* ]]
  [[ "$output" == *'"value":null'* ]]
}

@test "extract-enums: string enum members carry quoted value text" {
  cat > "$WORK/a.ts" <<'EOF'
export enum Status { ACTIVE = "active", INACTIVE = "inactive" }
EOF
  run run_runner extract-enums "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"ACTIVE"'* ]]
  [[ "$output" == *'\"active\"'* ]]
}

@test "extract-enums: file with no enums returns empty array" {
  cat > "$WORK/a.ts" <<'EOF'
export function f() {}
export class C {}
EOF
  run run_runner extract-enums "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "diff-enums: added members reported per enum" {
  cat > "$WORK/base.ts" <<'EOF'
export enum Status { ACTIVE = "a", INACTIVE = "i" }
EOF
  cat > "$WORK/head.ts" <<'EOF'
export enum Status { ACTIVE = "a", INACTIVE = "i", ARCHIVED = "x" }
EOF
  run run_runner diff-enums "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Status"'* ]]
  [[ "$output" == *'"added":["ARCHIVED"]'* ]]
  [[ "$output" == *'"removed":[]'* ]]
}

@test "diff-enums: removed members reported per enum" {
  cat > "$WORK/base.ts" <<'EOF'
export enum Status { ACTIVE, INACTIVE, DEPRECATED }
EOF
  cat > "$WORK/head.ts" <<'EOF'
export enum Status { ACTIVE, INACTIVE }
EOF
  run run_runner diff-enums "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed":["DEPRECATED"]'* ]]
}

@test "diff-enums: brand-new enum at head is not reported" {
  # Brand-new enums have no callers to retrofit — they're noise for R12.
  cat > "$WORK/base.ts" <<'EOF'
export enum Old { A, B }
EOF
  cat > "$WORK/head.ts" <<'EOF'
export enum Old { A, B }
export enum FreshNew { X, Y }
EOF
  run run_runner diff-enums "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"name":"FreshNew"'* ]]
}

@test "diff-enums: identical enums produce empty array" {
  cat > "$WORK/base.ts" <<'EOF'
export enum Status { A = "a", B = "b" }
EOF
  cp "$WORK/base.ts" "$WORK/head.ts"
  run run_runner diff-enums "$WORK/base.ts" "$WORK/head.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "extract-all: returns combined struct in one parse" {
  cat > "$WORK/a.ts" <<'EOF'
export enum Status { A, B }
export function f(x: number): void {}
EOF
  run run_runner extract-all "$WORK/a.ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"signatures"'* ]]
  [[ "$output" == *'"enums"'* ]]
  [[ "$output" == *'"name":"Status"'* ]]
  [[ "$output" == *'"name":"f"'* ]]
}

@test "find-references-batch: resolves call site for top-level function" {
  # find-references requires a project (cwd-rooted synthetic Program when
  # no tsconfig.json is present), so cd into the work dir for the call.
  cat > "$WORK/repo.ts" <<'EOF'
export function helper(x: number): string { return String(x); }
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { helper } from "./repo";
const x = helper(1);
EOF
  cat > "$WORK/queries.json" <<'EOF'
[{"declFile": "repo.ts", "name": "helper"}]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"helper"'* ]]
  [[ "$output" == *'"file":"caller.ts"'* ]]
  [[ "$output" == *'"kind":"ref"'* ]]
  [[ "$output" == *'"kind":"import"'* ]]
}

@test "find-references-batch: kind classifies import vs ref vs type-ref" {
  cat > "$WORK/repo.ts" <<'EOF'
export function helper(x: number): string { return String(x); }
export type HelperFn = typeof helper;
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { helper, type HelperFn } from "./repo";
const fn: HelperFn = helper;
const x = helper(1);
EOF
  cat > "$WORK/queries.json" <<'EOF'
[{"declFile": "repo.ts", "name": "helper"}]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"import"'* ]]
  [[ "$output" == *'"kind":"type-ref"'* ]]
  [[ "$output" == *'"kind":"ref"'* ]]
}

@test "find-references-batch: method on class is resolved by owner" {
  # Two classes can have a method with the same name; owner disambiguates.
  cat > "$WORK/repo.ts" <<'EOF'
export class Repo {
  findById(id: string): void {}
}
export class Cache {
  findById(id: number): void {}
}
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { Repo, Cache } from "./repo";
const r = new Repo();
const c = new Cache();
r.findById("a");
c.findById(1);
EOF
  cat > "$WORK/queries.json" <<'EOF'
[{"declFile": "repo.ts", "name": "findById", "owner": "Repo"}]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  # Result must include the Repo.findById call site and exclude
  # Cache.findById's. We assert on the line numbers: r.findById is at
  # line 4 of caller.ts, c.findById is at line 5.
  [[ "$output" == *'"line":4'* ]]
  [[ "$output" != *'"line":5'* ]]
}

@test "find-references-batch: arrow-function exported via const is resolved" {
  cat > "$WORK/repo.ts" <<'EOF'
export const handler = (x: number): string => String(x);
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { handler } from "./repo";
const y = handler(1);
EOF
  cat > "$WORK/queries.json" <<'EOF'
[{"declFile": "repo.ts", "name": "handler"}]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"file":"caller.ts"'* ]]
  [[ "$output" == *'"kind":"ref"'* ]]
}

@test "find-references-batch: unknown name returns empty references" {
  cat > "$WORK/repo.ts" <<'EOF'
export function helper(x: number): string { return String(x); }
EOF
  cat > "$WORK/queries.json" <<'EOF'
[{"declFile": "repo.ts", "name": "doesNotExist"}]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"references":[]'* ]]
}

@test "find-references-batch: preserves input order in output" {
  cat > "$WORK/repo.ts" <<'EOF'
export function alpha(x: number): void {}
export function beta(x: number): void {}
export function gamma(x: number): void {}
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { alpha, beta, gamma } from "./repo";
gamma(3); alpha(1); beta(2);
EOF
  # Deliberately reverse-order the queries; output must keep the
  # caller's order, not be re-shuffled by tsconfig grouping.
  cat > "$WORK/queries.json" <<'EOF'
[
  {"declFile": "repo.ts", "name": "gamma"},
  {"declFile": "repo.ts", "name": "alpha"},
  {"declFile": "repo.ts", "name": "beta"}
]
EOF
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  # Verify the output[].name list matches input order: gamma, alpha, beta.
  local names
  names=$(echo "$output" | python3 -c "import sys,json; print(','.join(e['name'] for e in json.load(sys.stdin)))")
  [ "$names" = "gamma,alpha,beta" ]
}

@test "find-references-batch: empty input yields empty output" {
  echo "[]" > "$WORK/queries.json"
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "find-references-batch: malformed input rejected" {
  echo '{"not": "an array"}' > "$WORK/queries.json"
  run bash -c "cd '$WORK' && NODE_PATH='$NODE_MODULES' node '$RUNNER' find-references-batch queries.json"
  [ "$status" -ne 0 ]
}

@test "unknown op: exits non-zero" {
  run run_runner not-a-real-op
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown op"* ]]
}
