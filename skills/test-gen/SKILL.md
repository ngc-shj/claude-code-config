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
echo "[file paths, one per line]" | bash ~/.claude/hooks/ollama-utils.sh classify-changes

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
3. Run the tests to verify they pass
4. If tests fail, fix them (max 3 fix iterations)
5. If tests still fail after 3 iterations, report:
   - Which tests failed and why
   - Root cause analysis (test issue vs source code issue)
   - Whether the source code needs fixing (escalate to orchestrator)
6. Check that test assertions are meaningful (not just "doesn't throw")
7. Verify test independence (no shared mutable state between tests)
8. Verify mock-reality consistency:
   - Mock return values must match actual API response shapes (read the real type/interface)
   - Mock/spy resets must be in setup/teardown hooks, not inside test bodies
   - Async functions under test must be awaited before assertions
   - Per-test state must use per-test hooks (beforeEach), not once-before-all (beforeAll)
9. When generating tests: NEVER modify production code to make it easier to test. If the production code uses a safe API variant (e.g., parameterized queries, tagged templates, structured builders), adapt the test mock to match that safe API — do not switch production code to an unsafe escape hatch for testability.

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
  } | bash ~/.claude/hooks/ollama-utils.sh verify-mock-shapes
  ```

  The output is a set of `[Severity] test-path:line — Problem — Fix` blocks (or `No findings`). Treat Critical/Major findings as mandatory fixes before reporting completion; Minor findings are informational. Remaining unflagged mocks still warrant a manual spot-check against the actual type definitions — the audit is a filter, not a substitute.

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
# obligation #9). Adapt the path globs for the project's test naming conventions.
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
