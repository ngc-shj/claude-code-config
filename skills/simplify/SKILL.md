---
name: simplify
description: "Review changed code for reuse, quality, and efficiency, then fix any issues found. Use this skill when: asked to simplify or clean up code; asked to find duplication or refactoring opportunities; asked to improve code quality of recent changes."
---

# Simplify Skill

Reviews changed or specified code for simplification opportunities: duplication, complexity hotspots, and efficiency improvements.

---

## Step 1: Determine Scope

Determine what to analyze based on user instructions:

| User instruction | Scope |
|-----------------|-------|
| No specific target | Current branch diff vs main |
| Specific file(s) mentioned | Those files only |
| "Whole codebase" / "everything" | Full project scan |

```bash
git diff main...HEAD --stat  # Understand what changed
```

## Step 2: Local LLM Pre-analysis (Zero Claude Tokens)

First, inventory existing shared utilities to inform reuse proposals:

```bash
bash ~/.claude/hooks/scan-shared-utils.sh
```

Then run pre-screening to identify complexity hotspots and duplication:

```bash
bash ~/.claude/hooks/pre-review.sh code
```

The local LLM will analyze changes focusing on:
- Complexity hotspots (long functions, deep nesting)
- Repeated code patterns
- Unused imports or dead code
- Simplification opportunities

If Ollama is unavailable, proceed to Step 3 without pre-analysis.

Save the output for reference in Step 3.

## Step 3: Sonnet Deep Analysis (Sub-agent)

Launch a Sonnet sub-agent to explore the codebase and generate concrete proposals:

```
You are a senior engineer specializing in code simplification.

Local LLM pre-analysis (for reference — do not re-report):
[Local LLM output, or "None"]

Shared utility inventory (existing reusable code — check before proposing new abstractions):
[scan-shared-utils.sh output, or "None"]

Changed files:
[File list from git diff --stat]

Task:
1. Read each changed file and its surrounding context
2. Search the codebase for similar patterns or existing utilities that could be reused — cross-reference the shared utility inventory above
3. Identify concrete simplification opportunities:
   - Duplicate logic that can be extracted into a shared function
   - Complex conditionals that can be simplified
   - Code that reimplements existing utility functions
   - Overly verbose patterns that have simpler alternatives
4. For each opportunity, provide:
   - File and line number
   - Category: duplication / complexity / reuse / verbosity
   - Before: current code snippet
   - After: proposed simplified code
   - Estimated impact: LOC reduction, readability improvement
   - Evidence: for reuse proposals, include the path and line of the existing utility being recommended

Output format: numbered list of proposals with before/after code blocks.
Proposals that recommend reuse without specifying the existing utility's location will be rejected.
If no simplification opportunities found, state "No simplification opportunities found."
```

If sub-agents are unavailable, perform the analysis directly.

## Step 4: Review and Apply

Present Sonnet's proposals to the user as a numbered list.

For each proposal, the user can:
- **Accept**: Apply the change (delegate mechanical refactoring to Sonnet if available)
- **Skip**: Leave the code as-is
- **Modify**: Adjust the proposal before applying

After applying accepted changes, check migrations and run ALL three verification steps:

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

**IMPORTANT**: Tests and build alone are insufficient. Lint catches unused imports, style violations, and other issues that neither tests nor builds detect. The production build catches SSR-only module resolution failures, TypeScript errors in non-test code, and bundler issues. All three must pass.

**IMPORTANT**: Fix ALL errors found by lint/test/build — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes." We are building the whole project, not just a diff.

**Manual verification (mandatory when refactoring affects runtime behavior)**:
When the refactoring changes **any** of the following, lint/test/build alone are insufficient — mocked tests may pass even when runtime behavior is broken (e.g., mock shape not updated to match the new API, or permissions insufficient for the new query pattern):
- API call patterns (e.g., single-record fetch → batch fetch, sync → async)
- Database queries (e.g., adding JOIN, changing WHERE conditions, switching query methods)
- Event dispatch (e.g., adding or removing event emission, changing payload shape)
- Worker/background job logic (e.g., changing job payload, queue routing, retry behavior)

In such cases:
1. Start the dev server (and workers/background processes if applicable)
2. Exercise the affected code path at least once through the running application
3. Verify no runtime errors in server logs

Do not commit until manual verification passes or the user explicitly waives it. If the user waives manual verification, record the waiver reason in the commit message or deviation log.

Report:
```
=== Simplify Complete ===
Proposals: [total]
Accepted: [n]
Skipped: [n]
Lint: [pass/fail]
Tests: [pass/fail]
Build: [pass/fail]
```
