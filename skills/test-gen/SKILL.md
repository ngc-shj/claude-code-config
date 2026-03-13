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

Local LLM analysis (for reference):
[Local LLM output, or "None"]

Source files to test:
[Source file contents]

Task:
1. Generate test files following the project's existing conventions
2. Cover these categories:
   - Happy path: normal expected behavior
   - Edge cases: boundary values, empty inputs, null/undefined
   - Error paths: invalid inputs, failure scenarios
   - Integration: key interactions between components (if applicable)
3. Run the tests to verify they pass
4. If tests fail, fix them (max 3 fix iterations)
5. Report any tests that cannot be made to pass

Output: generated test files with pass/fail status.
```

If sub-agents are unavailable, implement tests directly.

## Step 4: Coverage Review

Review generated tests for completeness:
- Identify missing edge cases or error paths
- Check that test assertions are meaningful (not just "doesn't throw")
- Verify test independence (no shared mutable state between tests)

If gaps are found, delegate additional test generation to Sonnet.

Final report:
```
=== Test Generation Complete ===
Test files created: [list]
Test cases: [total]
  Happy path: [n]
  Edge cases: [n]
  Error paths: [n]
Tests passing: [n/total]
Coverage: [if measurable]
```
