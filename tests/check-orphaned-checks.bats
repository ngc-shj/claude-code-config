#!/usr/bin/env bats
# Tests for check-orphaned-checks.sh (RT7 shape b).
#
# Diff-driven: fires only on check-like scripts added/modified on the
# branch. Classifies each candidate by where its basename is referenced:
# no caller -> Major; only in prose/docs -> Minor; on a gate surface
# (CI / Makefile / package.json / another *.sh) -> OK (silent).

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/check-orphaned-checks.sh"

setup() {
  WORK="$(mktemp -d)"
  (cd "$WORK" && git init -q && git config user.email t@t && git config user.name t)
}

teardown() {
  rm -rf "$WORK"
}

init_with() {
  for f in "$@"; do
    mkdir -p "$WORK/$(dirname "$f")"
    : > "$WORK/$f"
  done
  (cd "$WORK" && git add -A && git commit -qm initial)
}

@test "RT7b: new check script with no caller fires Major" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/check-thing.sh"
  (cd "$WORK" && git add -A && git commit -qm "add check")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"scripts/check-thing.sh"* ]]
  [[ "$output" == *"no caller"* ]]
}

@test "RT7b: check script referenced only in docs fires Minor" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/verify-policy.sh"
  mkdir -p "$WORK/docs"
  cat > "$WORK/docs/notes.md" <<'EOF'
Run scripts/verify-policy.sh manually when curious.
EOF
  (cd "$WORK" && git add -A && git commit -qm "add check + docs mention")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Minor]"* ]]
  [[ "$output" == *"verify-policy.sh"* ]]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT7b: check script wired into a CI yaml is silent (OK)" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/check-thing.sh"
  mkdir -p "$WORK/.github/workflows"
  cat > "$WORK/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - run: bash scripts/check-thing.sh
EOF
  (cd "$WORK" && git add -A && git commit -qm "add check + wire CI")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"every candidate is referenced from a gate surface"* ]]
  [[ "$output" != *"[Major]"* ]]
  [[ "$output" != *"[Minor]"* ]]
}

@test "RT7b: check wired transitively through an aggregate *.sh is silent" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/check-thing.sh"
  cat > "$WORK/scripts/pre-pr.sh" <<'EOF'
#!/bin/bash
bash scripts/check-thing.sh
EOF
  (cd "$WORK" && git add -A && git commit -qm "add check + aggregate caller")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # Positive marker: prove the script WAS a candidate and WAS judged wired,
  # not merely that no verdict fired (which also holds on the ignored path).
  [[ "$output" == *"added/modified: 1"* ]]
  [[ "$output" == *"every candidate is referenced from a gate surface"* ]]
  [[ "$output" != *"[Major]"* ]]
  [[ "$output" != *"[Minor]"* ]]
}

@test "RT7b: non-check script added is ignored" {
  init_with README.md
  mkdir -p "$WORK/src"
  : > "$WORK/src/helper.ts"
  (cd "$WORK" && git add -A && git commit -qm "add non-check")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no check-like scripts added or modified"* ]]
}

@test "RT7b: a longer-named sibling does not mask a shorter candidate (boundary match)" {
  # check.sh is orphaned; only mycheck.sh (a superstring) is mentioned on a
  # gate surface. A bare substring match would falsely treat check.sh as wired.
  init_with README.md
  mkdir -p "$WORK/scripts" "$WORK/.github/workflows"
  : > "$WORK/scripts/check.sh"
  : > "$WORK/scripts/mycheck.sh"
  cat > "$WORK/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - run: bash scripts/mycheck.sh
EOF
  (cd "$WORK" && git add -A && git commit -qm "orphan check.sh + wired mycheck.sh")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"scripts/check.sh"* ]]
}

@test "RT7b: a MODIFIED (not added) orphaned check fires Major" {
  # diff-filter AM must cover M, not just A.
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/check-thing.sh"
  (cd "$WORK" && git add -A && git commit -qm initial)
  echo "# extra line" >> "$WORK/scripts/check-thing.sh"
  (cd "$WORK" && git add -A && git commit -qm "modify check")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"scripts/check-thing.sh"* ]]
}

@test "RT7b: two candidates in one diff are both classified" {
  init_with README.md
  mkdir -p "$WORK/scripts" "$WORK/.github/workflows"
  : > "$WORK/scripts/check-orphan.sh"
  : > "$WORK/scripts/check-wired.sh"
  cat > "$WORK/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - run: bash scripts/check-wired.sh
EOF
  (cd "$WORK" && git add -A && git commit -qm "two candidates")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added/modified: 2"* ]]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"scripts/check-orphan.sh"* ]]
  [[ "$output" != *"check-wired.sh — no caller"* ]]
}

@test "RT7b: EXTRA_CHECK_NAME_RE detects a name the default regex ignores" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/policy-foo.sh"
  (cd "$WORK" && git add -A && git commit -qm "add policy script")
  # Default name regex does not include 'policy' -> ignored.
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [[ "$output" == *"no check-like scripts added or modified"* ]]
  # With the override it becomes a candidate and fires Major (no caller).
  run bash -c "cd '$WORK' && EXTRA_CHECK_NAME_RE=policy bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"scripts/policy-foo.sh"* ]]
}

@test "RT7b: a malformed EXTRA regex fails loud instead of silently disabling" {
  init_with README.md
  mkdir -p "$WORK/scripts"
  : > "$WORK/scripts/check-thing.sh"
  (cd "$WORK" && git add -A && git commit -qm "add check")
  run bash -c "cd '$WORK' && EXTRA_CHECK_NAME_RE='(' bash '$HOOK' HEAD~1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid regex"* ]]
}
