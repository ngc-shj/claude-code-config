#!/usr/bin/env bats
# Tests for check-new-code-untested.sh (RT6).
#
# v1 detects new public/exported symbols added in diff `+` lines of
# non-test source files (TS/JS, Python, Go, Rust) and flags Major when
# no test file appears anywhere in the diff. Loose mode: any test file
# touched diff-wide satisfies the check.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/check-new-code-untested.sh"

setup() {
  WORK="$(mktemp -d)"
  (cd "$WORK" && git init -q && git config user.email t@t && git config user.name t)
}

teardown() {
  rm -rf "$WORK"
}

# Helper: stage initial commit with $1 as initial files (associative
# string: relative path then content separated by NULs is overkill;
# tests pass paths directly).
init_with() {
  for f in "$@"; do
    mkdir -p "$WORK/$(dirname "$f")"
    : > "$WORK/$f"
  done
  (cd "$WORK" && git add -A && git commit -qm initial)
}

@test "RT6: new TS export with no test diff fires Major" {
  init_with src/foo.ts tests/init.test.ts
  cat > "$WORK/src/foo.ts" <<'EOF'
export function newFn(x: number): number {
  return x * 2;
}
EOF
  (cd "$WORK" && git add -A && git commit -qm "add export")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"New production exports without test diff (RT6)"* ]]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"newFn"* ]]
  [[ "$output" == *"src/foo.ts"* ]]
}

@test "RT6: new TS export WITH test diff is informational only" {
  init_with src/foo.ts tests/foo.test.ts
  cat > "$WORK/src/foo.ts" <<'EOF'
export function newFn(x: number): number {
  return x * 2;
}
EOF
  cat > "$WORK/tests/foo.test.ts" <<'EOF'
import { newFn } from "../src/foo";
describe("newFn", () => { it("doubles", () => { expect(newFn(2)).toBe(4); }); });
EOF
  (cd "$WORK" && git add -A && git commit -qm "add export + test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test file diff present"* ]]
  [[ "$output" != *"[Major]"* ]]
  [[ "$output" == *"newFn"* ]]
}

@test "RT6: re-exports and type-only exports are not counted" {
  init_with src/index.ts tests/init.test.ts
  cat > "$WORK/src/index.ts" <<'EOF'
export * from "./foo";
export { something } from "./bar";
export type MyAlias = string;
export interface MyInterface { id: string; }
EOF
  (cd "$WORK" && git add -A && git commit -qm "barrel + types")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no new production exports detected)"* ]]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT6: project with no test infrastructure is a no-op" {
  : > "$WORK/foo.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
  echo "export function newFn() { return 1; }" > "$WORK/foo.ts"
  (cd "$WORK" && git add -A && git commit -qm "add export")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no test files exist in repo"* ]]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT6: Python top-level def fires; underscore-private skipped" {
  init_with svc.py tests/test_init.py
  cat > "$WORK/svc.py" <<'EOF'
def public_fn(x):
    return x * 2

def _private_fn():
    pass

class PublicClass:
    pass
EOF
  (cd "$WORK" && git add -A && git commit -qm "add python exports")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"public_fn"* ]]
  [[ "$output" == *"PublicClass"* ]]
  [[ "$output" != *"_private_fn"* ]]
  [[ "$output" == *"[Major]"* ]]
}

@test "RT6: Go capitalized symbols fire; lowercase (unexported) skipped" {
  # `init_with` leaves both pkg/main.go and pkg/main_test.go empty.
  # We only modify the production file in the second commit so the diff
  # contains exactly one new file and zero added/modified test files,
  # exercising the "no test diff → Major" path cleanly.
  init_with pkg/main.go pkg/main_test.go
  cat > "$WORK/pkg/main.go" <<'EOF'
package pkg

func PublicFunc(x int) int { return x * 2 }
func privateFunc() int { return 1 }

type PublicStruct struct{ Name string }
type privateStruct struct{}
EOF
  (cd "$WORK" && git add -A && git commit -qm "add go exports only")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PublicFunc"* ]]
  [[ "$output" == *"PublicStruct"* ]]
  [[ "$output" != *"privateFunc"* ]]
  [[ "$output" != *"privateStruct"* ]]
  [[ "$output" == *"[Major]"* ]]
}

@test "RT6: Rust pub fn/struct/enum fire; private fn skipped" {
  init_with lib.rs tests/integration.rs
  cat > "$WORK/lib.rs" <<'EOF'
pub fn public_rust_fn(x: i32) -> i32 { x * 2 }
fn private_rust_fn() {}
pub struct PublicStruct;
pub enum PublicEnum { A, B }
EOF
  (cd "$WORK" && git add -A && git commit -qm "add rust exports")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"public_rust_fn"* ]]
  [[ "$output" == *"PublicStruct"* ]]
  [[ "$output" == *"PublicEnum"* ]]
  [[ "$output" != *"private_rust_fn"* ]]
}

@test "RT6: test files in the changed source are not scanned for exports" {
  init_with src/foo.ts tests/foo.test.ts
  # Add an export inside the TEST file — should NOT be flagged.
  cat > "$WORK/tests/foo.test.ts" <<'EOF'
export function helper(): number { return 1; }
describe("noop", () => { it("passes", () => {}); });
EOF
  (cd "$WORK" && git add -A && git commit -qm "test-only change")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no new production exports detected)"* ]]
}

@test "RT6: excluded paths (vendor, generated, types/) are ignored" {
  mkdir -p "$WORK/vendor" "$WORK/src/types" "$WORK/tests"
  : > "$WORK/vendor/lib.ts"
  : > "$WORK/src/types/api.ts"
  : > "$WORK/src/foo.generated.ts"
  : > "$WORK/tests/init.test.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
  echo "export function vendorFn() { return 1; }" > "$WORK/vendor/lib.ts"
  echo "export function typeFn() { return 1; }" > "$WORK/src/types/api.ts"
  echo "export function generatedFn() { return 1; }" > "$WORK/src/foo.generated.ts"
  (cd "$WORK" && git add -A && git commit -qm "exclude-path additions")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no new production exports detected)"* ]]
  [[ "$output" != *"[Major]"* ]]
}

# RT6: loose-mode contract pin (v1 design).
# Touching ANY test file diff-wide satisfies the check, even one whose
# content has no relationship to the new export. This pins the v1 quirk
# so a future v2 refactor toward per-symbol mapping must explicitly
# update this test rather than silently changing the contract.
@test "RT6: loose mode — touching unrelated test file satisfies the check" {
  init_with src/feature.ts tests/unrelated.test.ts
  # Add a new export to production code AND make an unrelated change to
  # a test file that has nothing to do with the new export.
  echo "export function brandNewFn(): number { return 42; }" > "$WORK/src/feature.ts"
  echo "// completely unrelated comment" > "$WORK/tests/unrelated.test.ts"
  (cd "$WORK" && git add -A && git commit -qm "new export + unrelated test edit")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test file diff present"* ]]
  [[ "$output" == *"verify per-symbol coverage manually"* ]]
  [[ "$output" != *"[Major]"* ]]
  [[ "$output" == *"brandNewFn"* ]]
}

# RT6: multi-line declaration is a documented v1 false-negative.
# v1 limitation: the awk parser inspects one `+` line at a time. When the
# `export` keyword is on a line of its own (split from the declarator on
# the next line), neither line independently matches: line 1 is just
# `export` and fails the `[[:space:]]+(function|class|const|let|...)`
# continuation; line 2 starts with `function` (no `export` prefix) and
# fails every pattern. Pins this behavior so a v2 detector that handles
# multi-line correctly must explicitly update / remove this test, making
# the behavioral change visible in the same diff.
@test "RT6: multi-line export declaration is a v1 known false-negative" {
  init_with src/multi.ts tests/init.test.ts
  # Case: `export` on its own line, then `function ...` on the next.
  cat > "$WORK/src/multi.ts" <<'EOF'
export
function splitExportFn(arg: number): number {
  return arg * 2;
}
EOF
  (cd "$WORK" && git add -A && git commit -qm "multi-line export")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # When v2 adds proper multi-line handling, change to: [[ "$output" == *"splitExportFn"* ]]
  [[ "$output" == *"(no new production exports detected)"* ]]
  [[ "$output" != *"splitExportFn"* ]]
}

# RT6: EXTRA_TEST_FILE_RE knob extends test-file recognition.
# Needs a `tests/` keeper file in the repo so the "no test infrastructure"
# skip path (which checks `git ls-files | grep TEST_FILE_RE`) does NOT fire.
# Without the keeper, the hook would skip entirely before reaching the
# loose-mode decision the knob is supposed to affect.
@test "RT6: EXTRA_TEST_FILE_RE extends test-file recognition" {
  init_with src/foo.ts e2e_specs/foo.ts tests/keeper.test.ts
  echo "export function newOne(): number { return 1; }" > "$WORK/src/foo.ts"
  echo "// e2e spec touched" > "$WORK/e2e_specs/foo.ts"
  (cd "$WORK" && git add -A && git commit -qm "add export + e2e_specs change")

  # Default: e2e_specs/ not recognized as test → only diff'd test path
  # would be tests/keeper.test.ts but it was not touched → TEST_DIFF_COUNT=0
  # → Major fires.
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]

  # With EXTRA_TEST_FILE_RE: e2e_specs/ now recognized → e2e_specs/foo.ts
  # in the diff counts as a test file → informational only.
  run bash -c "cd '$WORK' && EXTRA_TEST_FILE_RE='(^|/)e2e_specs/' bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test file diff present"* ]]
  [[ "$output" != *"[Major]"* ]]
}

# RT6: EXTRA_EXCLUDE_PATH_RE knob excludes additional production paths.
@test "RT6: EXTRA_EXCLUDE_PATH_RE excludes additional production paths" {
  init_with src/foo.ts experimental/lab.ts tests/init.test.ts
  echo "export function labFn(): number { return 1; }" > "$WORK/experimental/lab.ts"
  (cd "$WORK" && git add -A && git commit -qm "add experimental export")

  # Default: experimental/ is a production path → Major fires.
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"labFn"* ]]
  [[ "$output" == *"[Major]"* ]]

  # With EXTRA_EXCLUDE_PATH_RE: experimental/ is excluded → no detection.
  run bash -c "cd '$WORK' && EXTRA_EXCLUDE_PATH_RE='(^|/)experimental/' bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no new production exports detected)"* ]]
  [[ "$output" != *"[Major]"* ]]
}

# RT6: EXTRA_PRODUCTION_EXPORT_RE knob adds custom export-pattern recognition.
@test "RT6: EXTRA_PRODUCTION_EXPORT_RE recognizes project-specific export patterns" {
  init_with src/controller.ts tests/init.test.ts
  # A decorator-style declaration that doesn't match any built-in pattern.
  cat > "$WORK/src/controller.ts" <<'EOF'
@Controller('/api/foo')
class FooController {}
EOF
  (cd "$WORK" && git add -A && git commit -qm "add decorator-style export")

  # Default: no built-in pattern matches → no detection.
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no new production exports detected)"* ]]

  # With EXTRA_PRODUCTION_EXPORT_RE: decorator pattern detected → Major fires.
  run bash -c "cd '$WORK' && EXTRA_PRODUCTION_EXPORT_RE='^@Controller[(]' bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"extra"* ]]
}

# RT6: no-changed-files branch fires when base-ref equals HEAD.
@test "RT6: base-ref equals HEAD produces no-changed-files exit" {
  init_with src/foo.ts tests/init.test.ts
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changed files"* ]]
  [[ "$output" != *"[Major]"* ]]
}

# RT6: invalid base-ref exits 1 with a stderr error.
@test "RT6: invalid base-ref exits 1" {
  init_with src/foo.ts tests/init.test.ts
  run bash -c "cd '$WORK' && bash '$HOOK' nonexistent-ref 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a valid git ref"* ]]
}

# RT6: deleted-only test files do not satisfy the loose-mode check.
# (Adjacent finding from Security review: `git diff --name-only` counts
# pure-D entries which would let a "strip the tests, ship new code" PR
# silently satisfy the check. `--diff-filter=AM` is the fix.)
# Needs a `tests/keeper.test.ts` so the "no test infrastructure" skip
# does not fire after the deletion of the targeted test file.
@test "RT6: pure-deletion of test files does not satisfy the loose check" {
  init_with src/foo.ts tests/old.test.ts tests/keeper.test.ts
  echo "// old test seed" > "$WORK/tests/old.test.ts"
  (cd "$WORK" && git add -A && git commit -qm "seed old test")
  # Now: add a new export AND delete the targeted test file. keeper remains
  # so the repo still has test infrastructure.
  echo "export function shipNoTest(): number { return 1; }" > "$WORK/src/foo.ts"
  rm "$WORK/tests/old.test.ts"
  (cd "$WORK" && git add -A && git commit -qm "add export + delete old test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  # The deleted test file MUST NOT count toward TEST_DIFF_COUNT.
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"shipNoTest"* ]]
}
