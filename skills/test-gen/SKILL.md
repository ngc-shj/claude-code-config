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
- Spot-check mock return values against actual type definitions

If gaps are found, delegate additional test generation to Sonnet.

Before reporting completion, check migrations and run ALL three verification steps:

```bash
# Check for pending migrations
bash ~/.claude/hooks/check-migrations.sh

# Run ALL three checks:
# 1. Lint
[lint command]

# 2. Tests
[test command]

# 3. Production build
[build command]
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
Coverage: [if measurable]
```
