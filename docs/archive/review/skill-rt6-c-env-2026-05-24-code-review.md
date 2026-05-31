# Code Review: skill-rt6-c-env-2026-05-24

Date: 2026-05-24
Review round: 1
Scope: ad-hoc improvement to the triangulate skill itself (no formal Phase 1 plan).
Diff: 7 files (5 modified + 2 new) totalling 614 review-input lines.

## Changes from Previous Round
Initial review. Seed generation skipped (uncommitted-on-main scenario; full
diff passed directly to sub-agents).

## Functionality Findings
0 Critical, 0 Major, 5 Minor + 2 Adjacent. Full output: `/tmp/tri-zh6XZ4/func-findings.txt`.
- F-01 Minor: Python class/def asymmetry — addressed via inline awk comment.
- F-02 Minor: `lineno` not initialized — addressed via awk `BEGIN { lineno = 1; is_source = 0 }`.
- F-03 Minor: `+++ b/` git prefix assumption — addressed via docblock caveat.
- F-04 Minor: `/test/` directory heuristic — addressed via docblock caveat.
- F-05 Minor: cosmetic peer-hook header spelling — out-of-scope (separate cleanup PR).

## Security Findings
0 Critical, 0 Major, 2 Minor + 2 Adjacent. Full output: `/tmp/tri-zh6XZ4/sec-findings.txt`.
- S-01 Minor: empty `TRUSTED_ROOT` — addressed via `[ -n "$TRUSTED_ROOT" ]` guard + `cd ... || exit 1`.
- S-02 Minor: awk `-v` POSIX escape caveat — addressed via docblock caveat.
- [Adjacent] hook counted DELETED test files in `TEST_DIFF_COUNT` — addressed via `--diff-filter=AM`.

## Testing Findings
0 Critical, **4 Major**, 3 Minor + 2 Adjacent. Full output: `/tmp/tri-zh6XZ4/test-findings.txt`.
- T-01 Major: loose-mode escape hatch not pinned by test — addressed by new test "loose mode — touching unrelated test file satisfies the check".
- T-02 Major: multi-line declaration false-negative not pinned — addressed by new test "multi-line export declaration is a v1 known false-negative" (uses `export\nfunction ...` shape).
- T-03 Major: `EXTRA_*` env knobs untested — addressed by 3 new tests, one per knob.
- T-04 Major: Go test 6 `git reset --hard HEAD~1` dance — addressed by removing the reset; the `pkg/main_test.go` existence from `init_with` is sufficient.
- T-05 Minor: substring-JSON brittleness across 7 block-*.bats files — addressed via top-of-file comment in `block-sensitive-files.bats` documenting the asymmetric whitespace contract.
- T-06 Minor: no test for `CHANGED_COUNT=0` branch — addressed by new test "base-ref equals HEAD produces no-changed-files exit".
- T-07 Minor: no test for invalid base-ref — addressed by new test "invalid base-ref exits 1".

## Adjacent Findings
- Hook misclassified TS un-exported `class Foo` as `py-class` (regex had no file-extension guard). **Newly discovered during T-14 implementation**; fixed by adding `file ~ /\.py$/` guard to both `py-def` and `py-class` branches.

## Quality Warnings
None.

## Recurring Issue Check
### Functionality expert
R1-R37: all clean or N/A. Full enumeration in `/tmp/tri-zh6XZ4/func-findings.txt`.

### Security expert
R1-R37 + RS1-RS4: all clean or N/A. Full enumeration in `/tmp/tri-zh6XZ4/sec-findings.txt`.

### Testing expert
R1-R37 + RT1-RT6: all clean or N/A. RT6 satisfied recursively (new hook
is new production code; new bats file is its corresponding test diff).
Full enumeration in `/tmp/tri-zh6XZ4/test-findings.txt`.

## Resolution Status

### T-01 Major Loose-mode escape-hatch behavior undocumented in test
- Action: Added bats test "loose mode — touching unrelated test file satisfies the check" that touches `tests/unrelated.test.ts` with a comment while `src/feature.ts` adds `brandNewFn`; asserts informational-only output.
- Modified file: tests/check-new-code-untested.bats (new test block)

### T-02 Major Multi-line declaration false-negative untested
- Action: Added bats test pinning `export\nfunction splitExportFn(...)` shape as v1 false-negative; comment in test notes the v2-fix update path.
- Modified file: tests/check-new-code-untested.bats (new test block)

### T-03 Major EXTRA_* env knobs untested
- Action: Added 3 bats tests, one per knob (EXTRA_TEST_FILE_RE, EXTRA_EXCLUDE_PATH_RE, EXTRA_PRODUCTION_EXPORT_RE), each exercising both the without-knob and with-knob paths.
- Modified file: tests/check-new-code-untested.bats (new test blocks)

### T-04 Major Test 6 (Go) committed-then-reset pattern brittle
- Action: Refactored to use the standard `init_with` two-commit pattern. The `pkg/main_test.go` existence from `init_with` satisfies the "test infra exists" check without requiring any further touch; no `git reset` needed.
- Modified file: tests/check-new-code-untested.bats:116-138

### T-05 Minor Loose-substring JSON assertion brittleness
- Action: Added a top-of-file comment to `tests/block-sensitive-files.bats` documenting the asymmetric whitespace contract shared by all 7 block-*.sh hooks and warning future refactors. The jq-helper version is the cleaner path but scoped out (7-file refactor).
- Modified file: tests/block-sensitive-files.bats:5-19

### T-06 Minor base-ref equals HEAD branch untested
- Action: Added bats test "base-ref equals HEAD produces no-changed-files exit".
- Modified file: tests/check-new-code-untested.bats (new test block)

### T-07 Minor Invalid base-ref path untested
- Action: Added bats test "invalid base-ref exits 1" asserting exit 1 + stderr error.
- Modified file: tests/check-new-code-untested.bats (new test block)

### F-01 Minor Python class/def asymmetry undocumented
- Action: Added inline awk-script comment explaining the file-ext guard and PEP 8 PascalCase convention.
- Modified file: hooks/check-new-code-untested.sh (awk classifier section)

### F-02 Minor lineno uninitialized
- Action: Added `BEGIN { lineno = 1; is_source = 0 }` to the awk pipeline.
- Modified file: hooks/check-new-code-untested.sh (awk script start)

### F-03 Minor Diff-prefix assumption
- Action: Added docblock caveat naming the `diff.noprefix` / `diff.srcPrefix` / `diff.dstPrefix` config risk.
- Modified file: hooks/check-new-code-untested.sh (v1 limitations section)

### F-04 Minor `/test/` directory heuristic surprises
- Action: Added docblock caveat noting directory-name match wins and pointing to `EXTRA_EXCLUDE_PATH_RE` as the escape hatch.
- Modified file: hooks/check-new-code-untested.sh (v1 limitations section)

### S-01 Minor TRUSTED_ROOT empty stdout handling
- Action: Added `[ -n "$TRUSTED_ROOT" ]` guard + `cd "$TRUSTED_ROOT" || exit 1`.
- Modified file: hooks/check-new-code-untested.sh:81-90

### S-02 Minor awk `-v` POSIX escape behavior undocumented
- Action: Added docblock caveat under the Env knobs section.
- Modified file: hooks/check-new-code-untested.sh (env knobs section)

### [Adjacent-Sec] Hook counted DELETED test files in TEST_DIFF_COUNT
- Action: Switched the test-file count source from `CHANGED_FILES_LIST` to a `git diff --name-only --diff-filter=AM` list. Pure-deletion test diffs no longer satisfy the loose check.
- Modified file: hooks/check-new-code-untested.sh:129-135

### [Adjacent-newly-discovered] py-class regex misclassified TS un-exported classes
- Action: Added `file ~ /\.py$/` extension guard to BOTH `py-def` and `py-class` branches. Surfaced during implementation of T-14 (EXTRA_PRODUCTION_EXPORT_RE test) where `class FooController {}` in a TS file was being detected.
- Modified file: hooks/check-new-code-untested.sh (awk classifier section)

## Verification

- `bats tests/check-new-code-untested.bats`: 17/17 pass (was 9 → +8 new tests)
- `bats tests/block-sensitive-files.bats`: 20/20 pass (no regression from top-of-file comment)
- `bats tests/`: 446/446 pass total

---

# Round 2

Date: 2026-05-24
All 3 expert agents verified Round 1 fixes as resolved-clean. Findings:
- Functionality: 0 Critical, 0 Major, 2 Minor + 2 Adjacent
- Security: 0 Critical, 0 Major, 0 Minor direct + 2 Adjacent
- Testing: 0 Critical, 0 Major, 0 new — `No new findings`

All Round 2 findings inside Round 1 fix scope, inline-minor severity, no
security-boundary touch — eligible for **Tightening-only skip** per
phase-3-review.md Step 3-8.

## Tightening-only skip — Round 2
Findings applied directly (no Round 3 review):
- [F-06-R2 + Adjacent-Sec-R2-a] [Minor] `--diff-filter=AM` comment understates the rename-bypass-prevention semantics — applied: tightened the inline comment at `hooks/check-new-code-untested.sh:147-156` to make the rename-bypass attack class explicit (R-with-edit collapsed into single R entry → dropped intentionally).

Findings recorded but not modified (low-priority, accepted as-is):
- [F-07-R2] [Minor] `BEGIN { lineno = 1 }` produces plausible-but-wrong line on missing `@@` hunk header — defense-in-depth only, git diff output never omits `@@` headers in practice. Accepted.
- [Adjacent-Sec-R2-b] [Minor] Malformed `EXTRA_*` regex silent-tolerated on gawk — already covered by the existing awk `-v` escape caveat docblock at `hooks/check-new-code-untested.sh:80-86`. No new code change.

Justification: every Round 2 finding is scoped within Round 1 fix range,
inline minor severity, and touches no security boundary (the two Adjacent
Security findings are docblock-prose tightening only).

## Round 2 Verification

- `bats tests/`: 446/446 pass after Round 2 comment update (no behavior change, only prose).
