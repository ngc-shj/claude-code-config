#!/usr/bin/env bats
# Tests for check-propagation.sh C5 — AST-driven enum coverage gap.
# Mirrors check-propagation-c4.bats structure: temp git repo + diff-driven
# integration tests. Skipped automatically when AST runtime is missing.

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

@test "C5: added enum member with caller-side gap is flagged Minor" {
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { ACTIVE = "a", INACTIVE = "i" }
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { Status } from "./status";
export function describe(s: Status): string {
  switch (s) {
    case Status.ACTIVE: return "on";
    case Status.INACTIVE: return "off";
  }
  return "?";
}
EOF
  (cd "$WORK" && git add -A && git commit -qm initial)
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { ACTIVE = "a", INACTIVE = "i", ARCHIVED = "x" }
EOF
  (cd "$WORK" && git add -A && git commit -qm "add ARCHIVED")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## C5 Enum coverage"* ]]
  [[ "$output" == *"Status: new member ARCHIVED added"* ]]
  [[ "$output" == *"caller.ts"* ]]
  [[ "$output" == *"[Minor]"* ]]
  [[ "$output" == *"Status.ARCHIVED"* ]]
}

@test "C5: file already referencing the new member is NOT flagged" {
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { ACTIVE = "a" }
EOF
  cat > "$WORK/handled.ts" <<'EOF'
import { Status } from "./status";
const labels: Record<string, string> = {};
labels[Status.ACTIVE] = "on";
labels[Status.PENDING] = "wait";
EOF
  (cd "$WORK" && git add -A && git commit -qm initial)
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { ACTIVE = "a", PENDING = "p" }
EOF
  (cd "$WORK" && git add -A && git commit -qm "add PENDING")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # handled.ts ALREADY references Status.PENDING — must not be flagged.
  [[ "$output" != *"handled.ts"*"Status.PENDING"* ]]
  [[ "$output" == *"(no enum coverage gaps detected)"* ]]
}

@test "C5: enum member removal does not trigger (only additions)" {
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { A = "a", B = "b", C = "c" }
EOF
  cat > "$WORK/caller.ts" <<'EOF'
import { Status } from "./status";
console.log(Status.A);
EOF
  (cd "$WORK" && git add -A && git commit -qm initial)
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { A = "a", B = "b" }
EOF
  (cd "$WORK" && git add -A && git commit -qm "remove C")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # Removal is out of C5 scope (it's a different rule — stale caller of
  # a removed value is a separate coverage gap; v1 only handles additions).
  [[ "$output" == *"(no enum coverage gaps detected)"* ]]
}

@test "C5: brand-new enum (no base) is not flagged" {
  cat > "$WORK/status.ts" <<'EOF'
export const VERSION = 1;
EOF
  cat > "$WORK/another.ts" <<'EOF'
export const X = 1;
EOF
  (cd "$WORK" && git add -A && git commit -qm initial)
  cat > "$WORK/status.ts" <<'EOF'
export const VERSION = 1;
export enum Status { A = "a", B = "b" }
EOF
  (cd "$WORK" && git add -A && git commit -qm "introduce Status enum")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # New enum has no pre-existing callers, so coverage gap is undefined.
  [[ "$output" == *"(no enum coverage gaps detected)"* ]]
}

@test "C5: file referencing enum but no qualified-form member ref is not flagged" {
  # `Status` appearing only in import/type position (no `Status.X` form)
  # is not a coverage candidate — the file isn't switching over members.
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { A = "a" }
EOF
  cat > "$WORK/typeOnly.ts" <<'EOF'
import type { Status } from "./status";
export type Wrapper = { kind: Status };
EOF
  (cd "$WORK" && git add -A && git commit -qm initial)
  cat > "$WORK/status.ts" <<'EOF'
export enum Status { A = "a", B = "b" }
EOF
  (cd "$WORK" && git add -A && git commit -qm "add B")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no enum coverage gaps detected)"* ]]
}

@test "C5: graceful skip when no AST-supported files in diff" {
  printf '# README\n' > "$WORK/README.md"
  (cd "$WORK" && git add -A && git commit -qm initial)
  printf '# README updated\n' > "$WORK/README.md"
  (cd "$WORK" && git add -A && git commit -qm "docs only")

  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## C5 Enum coverage"* ]]
  [[ "$output" == *"(no AST-supported source files in diff)"* ]]
}
