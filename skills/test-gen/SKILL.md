---
name: test-gen
description: "Generate tests for specified code or changed code. Detects test framework automatically, generates test outlines via local LLM, then implements and verifies tests via Sonnet sub-agent. Use this skill when: asked to generate or add tests; asked to improve test coverage; asked to write tests for specific files or functions."
---

# Test Generation Skill

Generates tests for specified or changed code using a multi-stage pipeline: local LLM for analysis, Sonnet for implementation.

---

## Step 1: Scope and Framework Detection

Determine what to test:

| User instruction | Scope |
|-----------------|-------|
| Specific file(s) or function(s) | Those targets only |
| "Test the changes" / no target | Changed files on current branch |
| "Increase coverage" | Files with low or no test coverage |

Auto-detect the test framework from project files:

```bash
# Check for test framework indicators
ls package.json pyproject.toml pytest.ini Cargo.toml go.mod 2>/dev/null
```

Identify the project's test conventions:
- Test file naming pattern (e.g., `*.test.ts`, `*_test.go`, `test_*.py`)
- Test directory structure (e.g., `__tests__/`, `tests/`, co-located)
- Existing test examples to follow as patterns

Discover existing test infrastructure (mandatory):
```bash
# Scan for shared test helpers, fixtures, and mock utilities
bash ~/.claude/hooks/scan-shared-utils.sh
```
Search the test directories for:
- Shared test helpers/setup functions (e.g., `test-utils`, `test-helpers`, `factories`, `fixtures`)
- Common mock patterns already in use (e.g., `mockServer`, `createMock*`, `fake*`)
- Shared setup/teardown hooks (e.g., `beforeAll` in a shared file)
- Record what exists so the sub-agent reuses them instead of creating new ones

## Step 2: Test Outline Generation (Local LLM, Zero Claude Tokens)

Classify files and generate test case outlines using local LLM:

```bash
# Classify target files
echo "[file paths, one per line]" | bash ~/.claude/hooks/llm-commands.sh classify-changes

# Generate detailed review focusing on testability
bash ~/.claude/hooks/pre-review.sh code
```

The pre-review output will highlight:
- Functions without test coverage
- Edge cases and error paths
- Input validation boundaries

If Ollama is unavailable, proceed to Step 3 without outlines.

## Step 3: Sonnet Test Implementation (Sub-agent Loop)

Launch a Sonnet sub-agent to generate and verify tests:

```
You are a test engineer.

Test framework: [detected framework]
Test conventions: [naming pattern, directory structure]
Existing test examples: [sample test file contents for pattern reference]

Shared test infrastructure (MUST reuse — do NOT recreate):
[List of existing test helpers, mock utilities, fixtures from Step 1]

Local LLM analysis (for reference):
[Local LLM output, or "None"]

Source files to test:
[Source file contents]

Task:
1. Generate test files following the project's existing conventions
2. Reuse existing shared test helpers and mock utilities — do NOT create new helpers when equivalent ones already exist
3. Cover these categories:
   - Happy path: normal expected behavior
   - Edge cases: boundary values, empty inputs, null/undefined
   - Error paths: invalid inputs, failure scenarios
   - Integration: key interactions between components (if applicable)
4. Run the tests to verify they pass
5. If tests fail, fix them (max 3 fix iterations)
6. If tests still fail after 3 iterations, report:
   - Which tests failed and why
   - Root cause analysis (test issue vs source code issue)
   - Whether the source code needs fixing (escalate to orchestrator)
7. Check that test assertions are meaningful (not just "doesn't throw")
8. Verify test independence (no shared mutable state between tests)
9. Verify mock-reality consistency:
   - Mock return values must match actual API response shapes (read the real type/interface)
   - Mock/spy resets must be in setup/teardown hooks, not inside test bodies
   - Async functions under test must be awaited before assertions
   - Per-test state must use per-test hooks (beforeEach), not once-before-all (beforeAll)
10. When generating tests: NEVER modify production code to make it easier to test. If the production code uses a safe API variant (e.g., parameterized queries, tagged templates, structured builders), adapt the test mock to match that safe API — do not switch production code to an unsafe escape hatch for testability.
11. **Denial-path tests must assert the side-effect's absence (RT8)** — framework-agnostic: when a generated test exercises a gate's *denial* path — an authorization/permission reject (403), rate-limit reject (429), fail-closed (503), or any "request is blocked" case — it MUST assert BOTH the status/outcome AND that the guarded operation did NOT run. A denial test that asserts only the status is vacuously green: if the gate is removed and the mutation proceeds, the test still passes. Never generate a status-only denial test when a mutation spy/double is in scope. (Illustrative spelling — adapt to the project's framework: Jest/Vitest `expect(deleteMock).not.toHaveBeenCalled()` / `toHaveBeenCalledTimes(0)`; pytest `delete_mock.assert_not_called()`; Go `require.Equal(t, 0, deleteCalls)`.)
12. **Race/concurrency tests must assert both branches occurred (RT4)** — framework-agnostic: when a generated test asserts a cardinality outcome under concurrency ("exactly one winner", "no double-success", a zero-collision count), it MUST also assert that the contested window actually opened — both the success and the failure/contention branch each occurred at least once. A bare zero-cardinality assertion passes vacuously if a setup error short-circuits every iteration. Additionally, the chosen observable must be causally downstream of the contested property: if a purely SERIAL re-run of the same calls would also satisfy every assertion (e.g. the function returns success unconditionally), the test proves only that the code was called — pick an observable only the contested interleaving can produce (exactly one row inserted, loser-saw-conflict) and sanity-check it by the serialized-rerun thought experiment before emitting the test. (Illustrative spelling — Jest/Vitest `expect(collisions).toBe(0)` PLUS `expect(successes).toBeGreaterThan(0)` AND `expect(failures).toBeGreaterThan(0)`; adapt the matcher to the project's framework.)
13. **Tolerant-parser tests need a mixed valid+malformed fixture (R40 tolerant-consumer sub-clause)** — framework-agnostic: when the code under test is a best-effort/tolerant parser or filter over a collection (line-oriented file, record stream, "skip unknown shapes" reader), generate a fixture that mixes valid records WITH at least one malformed member, and assert the valid records still come through. An all-valid fixture cannot distinguish per-element fault isolation from a whole-collection catch-all that voids the entire batch on one bad element — the silent-total-data-loss shape passes every clean-input test.
14. **Fixtures must have cardinality ≥2 on every dimension the code iterates (RT7 empty-oracle sub-clause)** — framework-agnostic: when the code under test loops over a dimension (multiple keys per manifest, multiple matches per call site, multiple files per scan, multiple windows per item), generate at least one fixture where that dimension holds TWO members reaching the same consumer. A suite whose cross-product is empty in practice — every run iterating a collection of size 1 — cannot observe cross-contamination, per-iteration state leakage, or ordering defects, yet reports full coverage of the loop. Where the target is a DETECTOR (a check that emits findings only on violations), also generate at least one positive fixture: a suite over clean inputs alone makes the detector's output set empty by design, so every assertion about its output holds vacuously and an unconditional-success stub passes. Enumerate the dimensions the implementation iterates before emitting fixtures, and cover each with a ≥2 case.
15. **Register every acquired fixture for teardown at acquisition, not after the assertions (RT11)** — framework-agnostic: whenever a generated test acquires state that can survive it — a file or directory, a record carrying a globally unique key, an entry in a shared registry, a line in an append-only sink — the release MUST be registered at the moment of acquisition and run by the framework's teardown construct, never as trailing statements after the assertions. Assertions throw, and the abort-on-failure semantics of every runner then skip exactly the cleanup the failing run needed: the leak surfaces in the NEXT run as a uniqueness violation or an existence assertion satisfied by the previous run's residue, a failure that does not name its cause. Two further obligations: register identifiers returned by *production* code, not only ones the test constructed; and when a test needs a fixture OUTSIDE the subject root (the "outside the guarded tree" case a containment guard must be given), nest the subject one level inside the per-test sandbox so that fixture still lands inside the tree teardown reclaims — never walk a parent segment out of the sandbox into shared system temp under a predictable name. Direct every mutable sink the subject touches to a per-test location explicitly rather than assuming the scratch-directory pattern covers it, and assert the sink's exact resulting state rather than the presence of a matching entry, which another test's residue also satisfies. (Illustrative spelling — adapt to the project's framework: Jest/Vitest `afterEach` registration inside the acquiring helper; pytest a `yield` fixture or `request.addfinalizer` called immediately after creation; Go `t.Cleanup(...)` on the line after acquisition; bats `$BATS_TEST_TMPDIR` with the subject nested one level in.)
16. **A "this test would catch X" claim needs a mutation that discriminates (RT7 shape (g))** — framework-agnostic: when test-gen reports that a generated test pins a specific behaviour, that claim is a red-proof claim and must be executed, not argued. The mutation counts only if it is applied SINGLY (two changes at once show only that *some* assertion fired), produces a NON-ZERO delta on the real subject (a mutation that changes no output proves nothing; removing one alternative from a detector's deny list can only ever remove findings), reds for a reason the observed failure output NAMES (a red arriving from a neighbouring assertion, a diagnostic string, or a second failure the mutation also caused is a different test going red), is not satisfiable by the implementation the assertion exists to exclude (for a single-source or derivation claim, CHANGE the value rather than deleting it — deletion reds under the hardcoded implementation too), and TERMINATES (a mutation that removes a loop bound, a wait, or a depth limit wedges the suite instead of reddening it; bound the proving test with a timeout). Where the generated test covers a guard spanning N parallel arms or spellings, N mutations are required — one discharges exactly the arm it mutated. **Procedure, because obligation 10 forbids LEAVING production code edited** (a mutation you provably revert is not a production edit; an unreverted one is): **bind the subject before reading the colour.** A mutant the runner never loads produces a green that means nothing (R50) — and suites commonly derive the subject path from the test file's own location with no override, in which case an out-of-repo scratch copy is never executed. So: (i) if the runner offers a path override (env var, injectable module, config), mutate a scratch copy and point the runner at it; (ii) otherwise copy the whole tree to scratch and run there, or mutate in place having FIRST committed or stashed, or backed the file up by copy to restore by copying back. **Any scratch destination is created with `mktemp -d` (mode 0700) or the session scratchpad — never a predictable path under shared system temp**, the same discipline obligation 15 states for fixtures: a whole-tree copy carries `.env`, `.git/config` remotes and credential-helper settings, `.npmrc`/`.netrc`, and local certificates out from under the repo's own protections, so the copy is as sensitive as the original. Either way, prove the mutant is what ran — observe the mutation's OWN delta in the output (the changed value appearing in the failure message), or, when the mutation produces no visible delta, add a diagnostic marker; a marker added purely to establish subject identity does not count against the applied-SINGLY criterion, which is about the number of behavioural changes under test. Note the framework: `bats` does not print `$output` on failure by default, so a marker there needs `--print-output-on-failure` or an explicit `echo "$output" >&3`; the default report shows only the assertion text and its line. Do NOT mutate in place and restore with a whole-file working-tree revert (`git checkout -- <file>` / `git restore <file>`) while the tree holds uncommitted work: the revert's blast radius exceeds the mutation and discards the uncommitted change under test along with it (R21's destructive-verification carve-out, control 3 — observed repeatedly). To prove nothing leaked, capture `git status --porcelain` BEFORE mutating and diff it against the same command after — "the tree is clean" is not the predicate, because in this procedure the tree legitimately holds the uncommitted work under test; "the tree is byte-identical to the pre-mutation snapshot" is. Derive the mutant from the shipped file rather than retyping it — a hand-written copy proves only that the copy behaves. Bound the proving run with a timeout, per the termination criterion above. Report the mutation and the failure line you observed; never report a red-proof you reasoned about.
17. **A guard gets BOTH fixtures, both adjacent to the IMPLEMENTED boundary, and its axes covered in combination (RT10)** — framework-agnostic. (a) *Pairing*: never emit a guard suite that exercises only rejected inputs. Every deny fixture ships with an allow fixture that is legitimate and must still pass. This is a generation obligation on every framework — the `check-deny-only-guard.sh` hook in Step 4 covers only Jest/Vitest, bats, and hook-decision-JSON grammars, so on pytest / Go / RSpec nothing but this obligation enforces it. (b) *Adjacency, both sides*: derive both fixtures from the decision variable the code actually compares, not from the requirement's wording. The allow fixture is the nearest input that must still pass; the deny fixture is the nearest input that must still be refused — the one differing from a permitted input only in the property under test. A deny fixture written from the requirement ("an unrelated case must not match") typically lands far from the implemented boundary, where a too-loose implementation refuses it as well, so the test is green on the defective code, and obligation 16's proof does not catch it because force-truing the whole predicate reddens the distant case too. To check adjacency, enumerate the ONE-STEP loosenings the implementation admits — read them off the code, do not imagine them (exact→prefix→substring, normalised comparison→raw, dropping one conjunct, removing a canonicalisation step, widening the compared container by one level) — and require at least one of them to make the deny fixture PASS. Run that loosening as a real mutation under obligation 16, not on paper; "loosen to the weakest reading" is unfalsifiable without the one-step bound, since always-allow admits every fixture and a hair's loosening admits almost none. **The allow fixture gets the mirror test, or "adjacency is symmetric" is a claim enforced on one side only**: enumerate the one-step TIGHTENINGS the implementation admits (substring→prefix→exact, raw→normalised, adding a conjunct, adding a canonicalisation step, narrowing the compared container by one level) and require at least one of them to make the allow fixture FAIL. An allow fixture that survives every one-step tightening is distant from the boundary, and without this the allow side keeps exactly the paper judgment the deny side just lost. (c) *Axis combinations*: where the input has independent axes, enumerate them and choose fixtures from the cross-product's boundary cells rather than testing each axis alone — the escapes that reach review are compound. State which cells are deliberately unclaimed, so an uncovered cell is not read as a covered one.
18. **A parallel-implementation drift guard must be closed over the whole scope it claims (RT9)** — framework-agnostic: when the test being generated is a sync/parity test over a production artifact and its test-importable twin (a vendored copy, a generated artifact vs its source, a raw-loaded script plus its typed twin), a containment assertion — one file's text CONTAINS a needle taken from the other — is closed only INSIDE the needle. It catches substitution and deletion there and is blind to everything outside, so widening the needle from a construct's body to the full delimited construct plus its attributes (matcher flags/modifiers, visibility, decorators) closes in-construct drift only. It does not close the shape this obligation exists for: a SECOND declaration elsewhere in the twin that overrides or supplements the pinned one. **Draw the region before choosing a form, and draw it over FILES, not one file.** The pinned region is the set of files the loader actually loads that can define the construct — derive it from the manifest / loader config / script tags / deployment bundle, which is step (1) of RT9's reviewer action — not from "the twin file". Where that set has more than one member, the guard is over the set: a second declaration in a SIBLING script the same manifest loads defeats every single-file form. Then emit one of — the full construct plus attributes, with everything outside the region declared unclaimed in the test as in 17(c); a checksum over a region drawn to include every site that can override the pinned one; or whole-file equality, which applies ONLY where the twin is a verbatim copy (vendored, generated), since a typed or shimmed twin differs by construction and can never satisfy it — in the typed-twin case, RT9's own archetype, the choice is between the first two. Then red-prove per obligation 16 with the append placed OUTSIDE the pinned region: an append inside the pinned construct reddens under any containment assertion and proves nothing about the property claimed.

Output: generated test files with pass/fail status.
```

If sub-agents are unavailable, implement tests directly.

## Step 4: Coverage Review

Review generated tests for completeness:
- Identify missing edge cases or error paths
- Check that test assertions are meaningful (not just "doesn't throw")
- Verify test independence (no shared mutable state between tests)
- Verify the sub-agent reused existing test helpers (not reimplemented)
- Audit mock-reality alignment with the local LLM before spot-checking manually:

  ```bash
  { cat [generated-test-file]
    echo '=== OLLAMA-INPUT-SEPARATOR ==='
    cat [source-or-type-definition-file]
  } | bash ~/.claude/hooks/llm-commands.sh verify-mock-shapes
  ```

  The output is a set of `[Severity] test-path:line — Problem — Fix` blocks (or `No findings`). Treat Critical/Major findings as mandatory fixes before reporting completion; Minor findings are informational. Remaining unflagged mocks still warrant a manual spot-check against the actual type definitions — the audit is a filter, not a substitute.

- Run the vacuous-test detectors on the generated tests (closes the generate→verify loop — test-gen is the skill that *produces* the tests these hooks later catch in review). Pass the **same base ref the skill used to scope the run** (the merge-base / feature-branch point), not the default — the hooks default to `main...HEAD`, so a no-arg call silently sees an empty diff when test-gen ran on specific files while on `main` with no feature branch:

  ```bash
  # BASE_REF = the ref test-gen scoped against (e.g. the merge-base with main).
  # When test-gen ran on specific files with no branch, stage the new test
  # files and pass a ref that includes them, else these hooks no-op.
  # RT8 — denial-path test asserts status but not the mutation's absence
  bash ~/.claude/hooks/check-vacuous-denial.sh "$BASE_REF"
  # RT4 — race/cardinality test with no both-branches-occurred guard
  bash ~/.claude/hooks/check-race-vacuous-guard.sh "$BASE_REF"
  # RT10 — guard suite with no allow-shaped assertion anywhere in the file
  bash ~/.claude/hooks/check-deny-only-guard.sh "$BASE_REF"
  ```

  Any finding here is a vacuous test the generator just wrote — fix it before reporting completion (add the missing negative / lower-bound assertion), do not defer to a later review round. **Scope caveat**: the RT8 and RT4 hooks are **Jest/Vitest TS/JS only** (v1); the RT10 hook also covers bats. Its hook-decision-JSON tokens are scored in the bats-flavored branch ONLY, so a Jest/Vitest test asserting on decision JSON is not covered by either grammar — two file flavors, not three grammars. All three are no-ops for pytest / Go / RSpec — for those, the RT8/RT4/RT10 obligations are a manual review of the generated denial/race/guard tests, not a mechanical gate. On a framework a given hook does not cover, a clean run from that hook means "not checked", not "passed". The caveat also has an *obligation* axis: among the numbered obligations 11-18, only 11 (RT8), 12 (RT4) and 17(a) (the RT10 pairing) have a hook at all — obligation 9's mock-shape audit has its own LLM-invoked check earlier in this step, which is why this sentence is scoped to 11-18 rather than stated universally. Obligations 13 (R40 tolerant-consumer), 14 (RT7 empty-oracle), 15 (RT11), 16 (RT7 shape (g)), 17(b)-(c) (boundary adjacency, axis combinations) and 18 (RT9 drift-guard scope) have no mechanical detector on any framework and are manual review in every case — three clean hooks do not discharge the block. Obligation 17 is the sharpest instance of that gap: the RT10 hook decides only whether an allow-shaped assertion exists *somewhere in the file*, never whether either fixture sits near the implemented boundary, so a green RT10 run says nothing about 17(b).

If gaps are found, delegate additional test generation to Sonnet.

Before reporting completion, check migrations and run ALL three verification steps, plus three cross-skill checks adapted from the triangulate skill (lessons from prior runs that surfaced regressions test-gen alone did not catch):

```bash
# Check for pending migrations
bash ~/.claude/hooks/check-migrations.sh

# Run ALL three project-defined checks:
# 1. Lint
[lint command]

# 2. Tests
[test command]

# 3. Production build
[build command]

# 4. Production-code-untouched grep (test-gen specific contract).
# test-gen is supposed to ADD tests, not modify production code. If the diff
# touches files outside the test surface, the sub-agent likely violated the
# "do not modify production code to make it easier to test" rule (Step 3
# obligation #10). Adapt the path globs for the project's test naming conventions.
PROD_DIFF=$(git diff main...HEAD --name-only \
  | grep -vE '(^|/)(__tests__|tests|test|spec|specs)/|\.test\.|\.spec\.|_test\.|test_' || true)
if [ -n "$PROD_DIFF" ]; then
  echo "Production-code modifications detected outside test files:"
  echo "$PROD_DIFF"
  echo "Test-gen must not modify production code. Review and either (a) revert"
  echo "the production changes, OR (b) document why the change is mandatory and"
  echo "escalate to the user — generated tests should adapt to existing API,"
  echo "not the other way around."
fi

# 5. CI gate parity. The local lint/test/build set may be a subset of what CI
# runs. Extract every lint/check/verify command from the project's CI
# configuration and run each locally before declaring the skill complete.
# Surfacing a CI-only failure here costs one iteration; surfacing it after
# push costs one push round plus triage time.
while read -r cmd; do
  [ -z "$cmd" ] && continue
  echo "Running CI gate locally: $cmd"
  eval "$cmd" || { echo "CI gate failed locally: $cmd"; exit 1; }
done < <(bash ~/.claude/hooks/extract-ci-checks.sh)
# Environment-parity caveat: a local pass runs in the LOCAL environment, which
# carries generated artifacts (ORM/RPC codegen, build output) that a "static"/
# "no-generate" CI job omits. If a generated test file (or a helper it imports)
# lands in the input set of a generate-skipping job, the local pass is blind to
# the CI-only missing-artifact failure. Displace the generated artifact
# (`mv <codegen-out>{,.bak}`), re-run the gate, restore. See triangulate phase-2
# Step 2-1 item 7 environment-parity sub-check.

# 6. User feedback memory cross-check (same mechanism as triangulate Phase 2).
# Per-project feedback memories at ~/.claude/projects/<slug>/memory/feedback_*.md
# capture rules the user has previously corrected the orchestrator on; reapplying
# the corrected mistake in generated tests wastes review attention re-litigating
# a settled call. Sub-agents in Step 3 cannot see these memories — the orchestrator
# must enumerate them and cross-check the generated test files before commit.
PROJ_SLUG=$(pwd | sed 's|/|-|g')
MEM_DIR="$HOME/.claude/projects/$PROJ_SLUG/memory"
if [ -d "$MEM_DIR" ]; then
  for f in "$MEM_DIR"/feedback_*.md; do
    [ -f "$f" ] || continue
    echo "=== $(basename "$f") ==="
    cat "$f"
    echo
  done
fi
# For each feedback rule with a grep-able pattern, run
# `git diff main...HEAD | grep -nE '<pattern>'`. Direct hits MUST be fixed in
# this skill's session; do not defer to a later review. Non-grep-able rules are
# manual review obligations.
```

All must pass. Fix any failures before proceeding.

**IMPORTANT**: Tests and build alone are insufficient. Lint catches unused imports, style violations, and other issues that neither tests nor builds detect. The production build catches issues that only surface during full compilation/bundling — module resolution failures, type errors in non-test code, and bundler/packager-specific failures — that test runs do not exercise. All three must pass.

**IMPORTANT**: Fix ALL errors found by lint/test/build — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes." We are building the whole project, not just a diff.

Final report:
```
=== Test Generation Complete ===
Test files created: [list]
Test cases: [total]
  Happy path: [n]
  Edge cases: [n]
  Error paths: [n]
Tests passing: [n/total]
Lint: [pass/fail]
Build: [pass/fail]
Production-code untouched: [confirmed / N file(s) outside test surface — see findings]
CI gate parity: [N gates extracted, all pass locally / N extracted, M failed and resolved / no CI config detected]
Memory cross-check: [N feedback rules enumerated, no regressions / N enumerated, M direct hits resolved / no memory dir]
Coverage: [if measurable]
```
