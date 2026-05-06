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

@test "unknown op: exits non-zero" {
  run run_runner not-a-real-op
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown op"* ]]
}
