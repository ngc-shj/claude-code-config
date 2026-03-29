---
name: multi-agent-review
description: "A skill that reviews plan files or codebases from three expert perspectives: functionality, security, and testing. Launches three sub-agents and repeats the review-and-fix loop until all issues are resolved. Always use this skill when: asked to review plans, code, or branches; asked to evaluate from functionality/security/testing perspectives; asked for PR or pre-implementation review; asked to implement or develop from a plan."
---

# Multi-Agent Review Skill

A skill that covers the entire development workflow from plan creation to coding to code review.
Three expert agents (functionality, security, testing) repeat review and fix cycles at each phase until all issues are resolved.

---

## Entry Point Decision

Determine the starting phase from the user's instructions:

| User instruction | Starting phase |
|-----------------|----------------|
| "Implement", "Develop", etc. — starting from scratch | Phase 1 (Plan creation) |
| An existing plan file path is specified | Phase 1 (From review) |
| "Review the code", "Review the branch" | Phase 3 (Code review) |

---

## Phase 1: Plan Creation, Review & Commit

### Step 1-1: Determine Plan Name and Branch Name

Generate name candidates using local LLM (zero Claude tokens):

```bash
# Generate plan name slug from task description
PLAN_SLUG=$(echo "[one-line task summary]" | bash ~/.claude/hooks/ollama-utils.sh generate-slug)
```

If Ollama is unavailable or the result is unsatisfactory, generate the slug yourself as fallback.

Determine the branch prefix (`feature/`, `fix/`, `refactor/`, `docs/`) from the task type, then confirm with the user:

```
Plan name: [plan-name]
Branch name: [prefix]/[plan-name]
Save to: ./docs/archive/review/[plan-name]-plan.md
```

Naming guidelines:
- **Plan name**: Short descriptive slug in kebab-case (e.g., `add-user-auth`, `fix-login-bug`)
- **Branch name**: Prefix + slug in kebab-case (e.g., `feature/add-user-auth`, `fix/login-bug`, `refactor/extract-utils`)

### Step 1-2: Create the Plan

Use Claude Code's built-in plan creation feature to create a plan and save it to `./docs/archive/review/[plan-name]-plan.md`.

Ensure the following sections are included for review expert agents to evaluate. Add missing sections as needed:

- **Objective**: What to achieve
- **Requirements**: Functional and non-functional requirements
- **Technical approach**: Technologies, architecture, and design decisions
- **Implementation steps**: Concrete implementation steps (numbered)
- **Testing strategy**: How to test
- **Considerations & constraints**: Known risks, constraints, and out-of-scope items
- **User operation scenarios**: Concrete usage scenarios with specific sites/forms/workflows to surface edge cases (e.g., form structure variations, input field conflicts, fallback paths)

### Step 1-3: Local LLM Pre-screening (Optional)

Before launching Claude sub-agents, run a quick pre-screening pass using local LLM to catch obvious issues and reduce API cost.
The script reads the plan file directly and calls Ollama via curl — no Claude tokens consumed.

```bash
PLAN_FILE=./docs/archive/review/[plan-name]-plan.md bash ~/.claude/hooks/pre-review.sh plan
```

If the output contains issues, fix them in the plan before proceeding to expert review.
If Ollama is unavailable, the script outputs a warning and exits gracefully — proceed to Step 1-4.

Save the local LLM output for reference in Step 1-4 (to avoid duplicate findings).

### Step 1-4: Plan Review by Three Expert Agents (Claude Sub-agents)

Launch three sub-agents in parallel with the following roles (fall back to sequential inline execution if unavailable).

| Agent | Role | Evaluation perspective | Out of scope |
|-------|------|----------------------|-------------|
| Functionality expert | Senior Software Engineer | Requirements coverage, architecture, feasibility, edge cases, error handling | Security vulnerabilities, test design/coverage |
| Security expert | Security Engineer | Threat model, auth/authz, data protection, OWASP Top 10, injection, auth bypass, business logic vulnerabilities (OWASP A04) | Functional correctness (non-security), test strategy |
| Testing expert | QA Engineer | Test strategy, coverage, testability, CI/CD integration, test quality | Implementation correctness, security analysis |

**[Adjacent] tag obligation**: When an expert encounters an issue outside their scope but with potential impact, they MUST flag it using the format: `[Adjacent] Severity: Problem — this may overlap with [other expert]'s scope`. This is mandatory, not optional.

Instruction template for each sub-agent:

**Round 1 (full review):**
```
You are a [role name].
Evaluate the following plan from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Plan contents:
[Plan file contents]

Local LLM pre-screening results (already addressed — do not re-report these):
[Local LLM output, or "None" if skipped]

Requirements:
- Only raise specific and actionable findings within your scope
- If you encounter an issue outside your scope but with potential impact, flag it as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria (see below)
- For each finding, specify "Severity", "Problem", "Impact", and "Recommended action"
- Do not duplicate issues already caught by local LLM pre-screening
- If there are no findings, explicitly state "No findings"

Plan-specific obligations:
- Account for all downstream invariants of schema changes. When adding a new enum value, constant, or type, search for tests that enumerate all values of that type and check what invariants they enforce. Common patterns to check:
  - i18n key coverage tests (every enum value needs a translation key)
  - Exhaustive switch/if-else statements
  - Group membership arrays (audit action groups, permission groups)
  - OpenAPI spec generation
- The plan MUST list all files that need updating, not just the direct schema/constant files
- Verify the plan accounts for existing shared utilities (see "Codebase Awareness Obligations" in Common Rules)

Severity criteria for [role name]:
  [Populate with the full table for this expert from "Severity Classification Reference" in Common Rules. Do NOT use a reference — copy the actual table here.]

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true — e.g., multi-step auth flow, complex trust boundary, chained vulnerabilities]
```

**Round 2+ (incremental review):**
```
You are a [role name].
Review the changes made since the last round from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Changes since last round:
[Diff or description of changes]

Previous findings and their resolution:
[Previous findings with status: resolved/new/continuing]

Requirements:
- Verify that previous fixes are correct and complete
- Check if fixes introduced regression or new issues in surrounding context
- Report any previously overlooked issues within your scope
- Flag out-of-scope issues with potential impact as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria
- If there are no findings, explicitly state "No findings"

All obligations from Round 1 remain in effect (Plan-specific obligations, severity criteria, etc.).

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true]
```

### Step 1-5: Save Review Results and Deduplicate

First, save each agent's raw output to temporary files, then use local LLM for deduplication (zero Claude tokens):

```bash
# Concatenate all agent outputs and merge via Ollama
# Save each agent's output to files, then merge
cat /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
```

If Ollama is unavailable, deduplicate manually as fallback:
- Merge findings that describe the same underlying issue from different perspectives
- Keep the most comprehensive description and note all perspectives that flagged it

Save to `./docs/archive/review/[plan-name]-review.md` (create `./docs/archive/review/` if it doesn't exist).

```markdown
# Plan Review: [plan-name]
Date: [ISO 8601 format]
Review round: [nth]

## Changes from Previous Round
[For first round: "Initial review", for subsequent rounds: describe changes]

## Functionality Findings
[Functionality expert output — deduplicated]

## Security Findings
[Security expert output — deduplicated]

## Testing Findings
[Testing expert output — deduplicated]

## Adjacent Findings
[Adjacent-tagged findings from all experts — preserved for routing]

## Quality Warnings
[Findings flagged by merge-findings quality gate: VAGUE, NO-EVIDENCE, UNTESTED-CLAIM]
```

### Step 1-6: Validity Assessment and Plan Update

**Quality gate check (mandatory)**: Before assessing findings, check the `## Quality Warnings` section of the merged output. For each flagged finding (`[VAGUE]`, `[NO-EVIDENCE]`, `[UNTESTED-CLAIM]`), return it to the originating expert with the specific flag and request revision. Do not proceed with those findings until the expert provides a revised version with the required evidence or specificity.

The main agent scrutinizes each finding:
- **Critical/Major finding**: Must be reflected in the plan file
- **Minor finding**: Reflect if straightforward, otherwise record reason and skip, explain to user
- **Unnecessary finding**: Record reason and skip, explain to user

Return to Step 1-4 until all agents return "No findings", or the maximum of **10 rounds** is reached.

If the loop limit is reached with unresolved findings:
```
=== Review Loop Limit Reached (10 rounds) ===
Remaining findings: [list with severity]
Decision needed: Continue manually or accept current state?
```
Consult the user before proceeding.

### Step 1-7: Branch Creation and Commit

Once plan review is complete, create a branch and commit.

```bash
# Create new branch from main
git checkout main
git checkout -b [branch-name]

# Commit
git add ./docs/archive/review/[plan-name]-plan.md
git add ./docs/archive/review/[plan-name]-review.md

git commit -m "plan: [plan-name] - plan creation and review complete"
```

Report to user:
```
=== Phase 1 Complete ===
Plan: ./docs/archive/review/[plan-name]-plan.md
Branch: [branch-name]
Review rounds: [n]
Next step: Proceeding to Phase 2 (Coding)
```

---

## Phase 2: Coding

### Step 2-1: Review the Plan and Analyze Impact (Mandatory)

Read `./docs/archive/review/[plan-name]-plan.md` and understand the implementation steps.

Before writing any code, perform the following impact analysis:

1. **Enumerate all code paths**: grep for the target identifiers (e.g., function names, API endpoint paths, message types, and file name patterns) to identify every location that will need changes
2. **Check for duplicate implementations**: Verify there are no parallel implementations of the same feature (e.g., `.js` and `.ts` versions, direct and message-based paths, primary and fallback paths)
3. **Read related type definitions and constants**: Confirm actual enum values, type shapes, and constant definitions before using them in implementation
4. **Inventory reusable code**: Run the shared utility scanner, then supplement with manual search:
   ```bash
   INVENTORY=$(mktemp /tmp/shared-utils-inventory.XXXXXX)
   bash ~/.claude/hooks/scan-shared-utils.sh > "$INVENTORY"
   ```
   Review the output and add any additional findings:
   - Shared helper functions (e.g., rate limiters, encoders/decoders, URL builders)
   - Shared constants and validation schemas (e.g., constants modules, validation config)
   - Existing patterns for event dispatch, error handling, and DB transactions
   - Record each as: `[file:line] [function/constant name] — [what it does]`
5. **Append checklist to plan**: Record the results as a checklist in `./docs/archive/review/[plan-name]-plan.md` under a new "## Implementation Checklist" section, listing:
   - Every file and location that must be modified
   - Every shared utility that must be reused (from step 4)
   - Every pattern that must be followed consistently across all sites

This step prevents: using wrong constant values, missing fallback code paths, leaving stale duplicate implementations untouched, and reimplementing logic that already exists in shared modules.

### Step 2-2: Implementation (Delegate to Sonnet Sub-agents)

Split the plan's "Implementation steps" into independent batches and delegate to Sonnet sub-agents:

1. **Task splitting**: Group implementation steps into batches that can be executed independently
2. **Sonnet delegation**: Launch Sonnet sub-agent(s) for each batch with:
   - The full plan for context
   - The specific steps to implement
   - Any outputs from previous batches (for dependencies)
   - **The shared utility inventory from Step 2-1** (list of existing helpers, constants, and patterns that MUST be reused — sub-agents are prohibited from reimplementing these)
3. **Review**: After each batch completes, verify the output before proceeding to the next batch. Specifically check:
   - Did the sub-agent reuse existing shared utilities, or did it create new ones?
   - Did the sub-agent follow existing patterns, or did it invent a parallel approach?
   - If new helper functions were created, are they genuinely new, or do they duplicate existing code?

If sub-agents are unavailable, implement directly as fallback.

Recording rules during implementation:
- Sections implemented as planned: No recording needed
- **Sections that deviate from the plan**: Append to the deviation log with reasons (see Step 2-3)

### Step 2-3: Deviation Log Management

After implementation, delegate deviation log creation to a Sonnet sub-agent:
- Provide the plan and `git diff main...HEAD` to Sonnet
- Sonnet compares the diff against the plan and generates the deviation log
- Review Sonnet's output for accuracy

If sub-agents are unavailable, record deviations directly.

Save to `./docs/archive/review/[plan-name]-deviation.md`.

```markdown
# Coding Deviation Log: [plan-name]
Created: [ISO 8601 format]

## Deviations from Plan

### [Deviation ID]: [Deviation summary]
- **Plan description**: [Original plan]
- **Actual implementation**: [What was actually done]
- **Reason**: [Why it was changed]
- **Impact scope**: [Areas affected by this change]

---
```

If there are no deviations, create the file with "No deviations".

### Step 2-4: Implementation Completion Check

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

**IMPORTANT**: Fix ALL errors found by lint/test/build — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes." We are building the whole project, not just a diff.

Report to user when implementation is done:
```
=== Phase 2 Complete ===
Files implemented: [n]
Lint: [pass/fail]
Tests: [pass/fail]
Build: [pass/fail]
Deviations from plan: [yes/no] (log: ./docs/archive/review/[plan-name]-deviation.md)
Next step: Proceeding to Phase 3 (Code Review)
```

---

## Phase 3: Code Review, Fix & Commit

### Step 3-1: Gather Review Input

Read the following three items:
1. Finalized plan: `./docs/archive/review/[plan-name]-plan.md`
2. Deviation log: `./docs/archive/review/[plan-name]-deviation.md`
3. All code on the current branch

```bash
git branch --show-current   # Confirm branch name
git diff main...HEAD --stat # Understand changed files
```

### Step 3-2: Local LLM Pre-screening (Optional)

Before launching Claude sub-agents, run a quick pre-screening pass using local LLM.

The script reads `git diff main...HEAD` directly and calls Ollama via curl — no Claude tokens consumed.

```bash
bash ~/.claude/hooks/pre-review.sh code
```

If the output contains issues, fix them before proceeding to expert review.
If Ollama is unavailable, the script outputs a warning and exits gracefully — proceed to Step 3-3.

Save the local LLM output for reference in Step 3-3 (to avoid duplicate findings).

### Step 3-3: Code Review by Three Expert Agents (Claude Sub-agents)

Launch the same three roles in parallel as the plan review.

| Agent | Role | Evaluation perspective | Out of scope |
|-------|------|----------------------|-------------|
| Functionality expert | Senior Software Engineer | Requirements coverage, architecture, feasibility, edge cases, error handling | Security vulnerabilities, test design/coverage |
| Security expert | Security Engineer | Threat model, auth/authz, data protection, OWASP Top 10, injection, auth bypass, business logic vulnerabilities (OWASP A04) | Functional correctness (non-security), test strategy |
| Testing expert | QA Engineer | Test strategy, coverage, testability, CI/CD integration, test quality | Implementation correctness, security analysis |

**[Adjacent] tag obligation**: When an expert encounters an issue outside their scope but with potential impact, they MUST flag it using the format: `[Adjacent] Severity: Problem — this may overlap with [other expert]'s scope`. This is mandatory, not optional.

**Round 1 (full review):**
```
You are a [role name].
Review the code on the current branch from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Finalized plan:
[Plan contents]

Deviation log:
[Deviation log contents]

Target code:
[Code contents]

Local LLM pre-screening results (already addressed — do not re-report these):
[Local LLM output, or "None" if skipped]

Requirements:
- Only specific and actionable findings within your scope (vague findings are prohibited)
- If you encounter an issue outside your scope but with potential impact, flag it as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria (see below)
- For each finding, specify file name, line number, severity, problem, and recommended fix
- Consider the deviation log when reviewing
- Do not duplicate issues already caught by local LLM pre-screening
- Cross-check the plan's "Implementation Checklist" section against the git diff. Report any file listed in the checklist that does not appear in the diff as a finding
- If there are no findings, explicitly state "No findings"

Codebase awareness (mandatory — see "Codebase Awareness Obligations" in Common Rules):
- Before writing any finding or recommendation, search the codebase for existing shared utilities, helpers, and patterns related to the changed code
- If new code reimplements logic that already exists in a shared module, flag it as a finding
- Include the evidence (grep results, file paths) in your findings

Cross-cutting verification (mandatory for all experts):
- For each changed pattern (e.g., URL matching logic, message payload structure, form input handling), grep the codebase to verify the same pattern is not used elsewhere without the equivalent change
- Report any missed locations as findings with the pattern name and file locations
- For security-relevant pattern changes (input validation, auth checks, sanitization), treat missed locations as at least Major severity findings

Write-read consistency verification (mandatory for all experts):
- When a feature writes data in one endpoint and reads it in another (e.g., audit logs, notifications, sync), note: "Unit tests with mocked write and read cannot verify data format consistency. The written value must be valid for the read query's type constraints."
- Specifically check:
  - Values written to DB columns must be valid for any query (filter, lookup) that reads them
  - Enum values written must exist in both the DB schema and the ORM/client's generated types
  - String IDs written must match the expected format (UUID, CUID, etc.) of any ID-based lookup query
  - Values passed to DB queries must be validated/sanitized at the input boundary (e.g., request schema) before reaching the query layer

Sub-agent test validation (mandatory for all experts):
- After implementation sub-agents generate tests, spot-check complex test cases for these red flags:
  - Mock/spy reset calls placed inside a test body instead of setup/teardown hooks — this invalidates the test's own setup
  - Test assertions that don't reference values from the mock setup — the test may pass vacuously
  - Mock return values whose shape doesn't match the actual API response format (e.g., returning an array when the real API returns an object with status fields)
  - Async test functions that do not await the target call — assertions may execute before the async operation completes, always passing
  - Per-test state initialized in a once-before-all hook instead of a per-test hook — causes test-order dependency and intermittent failures

Severity criteria for [role name]:
  [Populate with the full table for this expert from "Severity Classification Reference" in Common Rules. Do NOT use a reference — copy the actual table here.]

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true — e.g., multi-step auth flow, complex trust boundary, chained vulnerabilities]
```

**Round 2+ (incremental review):**
```
You are a [role name].
Review the fixes made since the last round from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Changes since last round (diff):
[git diff of fixes]

Previous findings and their resolution:
[Previous findings with status: resolved/new/continuing]

Context files (files affected by the changes):
[Relevant surrounding code]

Requirements:
- Verify that previous fixes are correct and complete
- Check if fixes introduced regression or new issues in surrounding context
- Report any previously overlooked issues within your scope
- Flag out-of-scope issues with potential impact as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria
- For each finding, specify file name, line number, severity, problem, and recommended fix
- Indicate status from previous round (resolved, new, continuing)
- If there are no findings, explicitly state "No findings"

Cross-cutting verification (mandatory for all experts):
- For each changed pattern, grep the codebase to verify no other locations use the same pattern without the equivalent change
- Report any missed locations as findings

Write-read consistency verification (mandatory for all experts):
- Same rules as Round 1 apply to any newly written or modified code in this round

Sub-agent test validation (mandatory for all experts):
- Same red flags as Round 1 apply to any tests generated or modified in this round

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true]
```

### Step 3-4: Save Review Results and Deduplicate

First, save each agent's raw output to temporary files, then use local LLM for deduplication (zero Claude tokens):

```bash
# Save each agent's output to files, then merge
cat /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
```

If Ollama is unavailable, consolidate and deduplicate manually (merge same underlying issue flagged by multiple agents).

Save to `./docs/archive/review/[plan-name]-code-review.md` (overwrite).

```markdown
# Code Review: [plan-name]
Date: [ISO 8601 format]
Review round: [nth]

## Changes from Previous Round
[For first round: "Initial review", for subsequent rounds: classify as resolved/new/continuing]

## Functionality Findings
[Functionality expert output — deduplicated]

## Security Findings
[Security expert output — deduplicated]

## Testing Findings
[Testing expert output — deduplicated]

## Adjacent Findings
[Adjacent-tagged findings from all experts — preserved for routing]

## Quality Warnings
[Findings flagged by merge-findings quality gate: VAGUE, NO-EVIDENCE, UNTESTED-CLAIM]

## Resolution Status
[Updated after fixes]
```

### Step 3-5: Fix the Code

**Quality gate check (mandatory)**: Before fixing findings, check the `## Quality Warnings` section. For each flagged finding (`[VAGUE]`, `[NO-EVIDENCE]`, `[UNTESTED-CLAIM]`), return it to the originating expert with the specific flag and request revision. Do not fix findings that lack evidence or specificity — send them back first.

The main agent scrutinizes findings and fixes based on severity:
- **Critical**: Must fix immediately
- **Major**: Must fix
- **Minor**: Fix if straightforward, otherwise consult the user

Important rules:
- **No deferring**: "Address later" is not an option for Critical/Major
- For findings that are difficult to fix, consult the user before deciding
- Always run migration check, lint, tests, AND production build after fixes
- **Fix ALL errors** — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes."
- **Test-verified behavior conflict check**: Before accepting any finding that reverses a configuration or behavior confirmed during implementation/testing (Phase 2), verify: (1) the finding cites a specific spec or concrete attack vector, not a general heuristic, (2) the finding explains why the tested scenario is invalid. If neither is met, reject the finding and note the test evidence. After applying any fix that changes security boundaries (CSP, CORS, auth, rate limiting), re-run the relevant E2E flow in production-equivalent mode.

### Step 3-6: Test, Build, and Commit

```bash
# Check for pending migrations
bash ~/.claude/hooks/check-migrations.sh

# Run lint to catch unused imports, style violations, etc.
[lint command]

# Run tests (use project-appropriate command)
[test command]

# Run production build to catch SSR/bundling/type errors not covered by tests
[build command]

# Commit only if ALL three pass
git add -A
git commit -m "review([n]): [summary of fixes]"
```

**IMPORTANT**: Tests and build alone are insufficient. Lint catches unused imports, style violations, and other issues that neither tests nor builds detect. The production build catches SSR-only module resolution failures, TypeScript errors in non-test code, and bundler issues. All three must pass before committing.

### Step 3-7: Update Resolution Status

Append to the "Resolution Status" section of `./docs/archive/review/[plan-name]-code-review.md`:

```markdown
## Resolution Status
### [Finding number] [Severity] [Problem summary]
- Action: [Fix performed]
- Modified file: [filename:line number]
```

### Step 3-8: Termination Check

End the loop when all agents return "No findings", or the maximum of **10 rounds** is reached.

If the loop limit is reached with unresolved findings:
```
=== Review Loop Limit Reached (10 rounds) ===
Remaining findings: [list with severity]
Decision needed: Continue manually or accept current state?
```
Consult the user before proceeding.

If findings remain and under the limit, return to Step 3-3.

### Step 3-9: Final Commit

```bash
git add ./docs/archive/review/[plan-name]-code-review.md
git add ./docs/archive/review/[plan-name]-deviation.md
git commit -m "review: code review complete - all findings resolved"
```

Final report:
```
=== All Phases Complete ===
Plan name: [plan-name]
Branch: [branch-name]
Plan review rounds: [n]
Code review rounds: [n]
Artifacts:
  - ./docs/archive/review/[plan-name]-plan.md (finalized plan)
  - ./docs/archive/review/[plan-name]-review.md (plan review log)
  - ./docs/archive/review/[plan-name]-deviation.md (deviation log)
  - ./docs/archive/review/[plan-name]-code-review.md (code review log)
```

---

## Common Rules

### Loop Progress Report

Report at the start of each review loop:
```
=== [Phase name] Review Loop [round n/10] ===
Previous findings: Critical [x] / Major [y] / Minor [z]
Resolved: [n] / New: [n] / Continuing: [n]
```

### Ensure docs/archive/review Directory

Create `./docs/archive/review/` before starting review if it doesn't exist:
```bash
mkdir -p ./docs/archive/review
```

### When Sub-agents Are Unavailable

Process the three perspectives sequentially inline.
Explain to the user that evaluation objectivity may be reduced.

### No Commits to main

All commits must be made on the `[branch-name]` branch.
If accidentally on main, create a new branch before continuing work.

### Sub-agent Model Selection

| Expert | Default model | Escalation |
|--------|--------------|------------|
| Functionality expert | Sonnet | — |
| Security expert | Sonnet | Opus (when `escalate: true` is flagged) |
| Testing expert | Sonnet | — |

**Escalation mechanism** (Security expert only):
1. **Detection**: After Security expert (Sonnet) returns findings, check each Critical finding for `escalate: true` flag. As a safety net, the orchestrator should also independently assess whether any Critical finding warrants escalation, even if `escalate: false` is reported
2. **Re-run**: If any `escalate: true` is present, re-launch Security expert with `model: "opus"`, passing the same input (Round 1: full plan/code; Round 2+: current round's diff and previous findings) plus the Sonnet findings as additional context
3. **Merge**: Opus findings are merged with Sonnet findings (not replaced). Findings are considered "overlapping" when they share the same root cause (same file, same vulnerability type). Opus takes precedence for overlapping Critical findings; Sonnet's non-overlapping Major/Minor findings are preserved

### Handling [Adjacent] Findings

Processing rules for `[Adjacent]`-tagged findings:
1. **During deduplication** (Step 1-5 / Step 3-4): `[Adjacent]` findings are preserved and NOT merged with the originating expert's findings
2. **During fix assessment** (Step 1-6 / Step 3-5): The main orchestrator routes each `[Adjacent]` finding to the appropriate expert's scope for evaluation
3. **If the appropriate expert already reported the same issue**: merge and keep the more comprehensive description
4. **If the appropriate expert did not report it**: treat it as a new finding from that expert's perspective
5. **If the routing target is unclear or unavailable**: the main orchestrator evaluates the finding directly

### Codebase Awareness Obligations

Every expert agent MUST perform codebase-wide investigation before writing findings. Reviewing only the changed files is insufficient — you must understand how the changes fit into the whole system.

**Before-review investigation (mandatory for all experts):**

1. **Discover shared utilities**: Search (`grep -r`, `Glob`) for existing helper functions, shared modules, and utility files related to the feature under review. Common locations: `lib/`, `utils/`, `shared/`, `common/`, `helpers/`.
2. **Find parallel implementations**: Search for similar logic elsewhere in the codebase. If the new code reimplements something that already exists, flag it as a finding (Major severity minimum).
3. **Trace the full pattern**: When the change touches a pattern (e.g., event dispatch, rate limiting, validation), search for ALL other places that use the same pattern. List them explicitly.
4. **Check constant/enum consumers**: When constants, enums, or types are added or changed, search for all consumers (switch statements, if-else chains, array membership checks, i18n keys, test assertions).

**Evidence requirement**: Every finding that references existing code must include the file path and line number where the evidence was found. Findings without evidence are rejected.

**Anti-pattern: "Missing the forest"**
The following are language-agnostic examples of costly misses from past reviews:
- Rate limiter reimplemented 3 times in separate files when a shared helper already existed
- Encoding/decoding function copied locally instead of importing from the existing shared module
- Event/notification dispatch added in 2 of 6 mutation sites, missed the other 4 (required 3 review rounds)
- Validation constants hardcoded in UI, API schema, AND test mocks instead of imported from a shared constants module
- URL construction helper duplicated in 4 files instead of calling the centralized one

### Finding Quality Standards

**Prohibited finding types:**

1. **Vague recommendations**: "Consider adding tests" or "Error handling could be improved" — must specify WHICH function, WHAT test case, and HOW to handle the error
2. **Untested testability claims**: Before recommending "add a test for X", verify that X is actually testable in the project's test infrastructure (e.g., Auth.js internal provider config is NOT unit-testable)
3. **Architecture misunderstandings**: Before flagging crypto, auth, or complex domain logic, read the surrounding code to understand the design intent. False alarms on crypto (e.g., flagging HKDF-derived hashes as "password hashes") waste review rounds
4. **Cargo-cult security findings**: Flagging standard library usage as "insecure" without a concrete attack vector. Every security finding must describe: attacker, attack vector, preconditions, and impact
5. **Heuristic-only security restrictions**: Recommending removal of a configuration (e.g., CSP directive, CORS origin, allowed redirect URI) based on "generally this shouldn't be in production" without verifying the actual use case. Security findings that restrict functionality MUST cite the relevant specification (RFC, OWASP, vendor docs) and explain why the specific use case does not apply. Example of a prohibited finding: "Remove localhost from CSP form-action in production" — without checking whether OAuth native app flow (RFC 8252) requires it

**Required finding format (code review):**
```
[Finding ID] [Severity]: [Problem title]
- File: [path:line]
- Evidence: [grep output, code snippet, or specific observation]
- Problem: [Concrete description — what is wrong and why]
- Impact: [What breaks, what data is at risk, what users experience]
- Fix: [Specific code change or approach — not "consider improving"]
```

Findings that omit Evidence or provide a vague Fix are returned to the expert for revision.

### Anti-Deferral Rules

**"Out of scope" and "pre-existing" are not free passes.**

1. **Pre-existing issues in changed files**: If a file is already being modified and contains a pre-existing bug, it MUST be flagged (severity based on impact, not on who introduced it). The CLAUDE.md rule "Fix ALL errors" applies.
2. **Out-of-scope finding obligations**: When marking a finding as "out of scope", the expert MUST:
   - State which expert's scope it belongs to (use [Adjacent] tag)
   - Provide enough detail for the other expert to evaluate it
   - Never use "out of scope" to avoid investigating a finding
3. **"Acceptable risk" requires quantification**: Do not accept risks with hand-waving like "acceptable for personal tool" or "low probability." State: what is the worst case, what is the likelihood, and what is the cost to fix. If cost-to-fix is low, fix it.
4. **Deferred findings must be tracked**: Any finding deferred to a future PR must be recorded in the review log with a clear reason and an explicit "TODO" marker that can be grepped.

### Expert Agent Obligations

**Do not override test-verified behavior with general heuristics**
When a finding recommends changing a configuration or behavior that was previously tested and confirmed working (e.g., during implementation or E2E testing), the burden of proof is on the finding. The expert MUST:
- Cite a specific specification (RFC, OWASP rule, language spec) — not "generally you shouldn't do X"
- Explain why the tested scenario does not apply, with a concrete counter-example
- If unable to provide spec-level evidence, downgrade to an informational note, not a finding

Real example: A security expert recommended removing `http://localhost:*` from CSP `form-action` in production, citing "localhost is not used in production." This broke OAuth native app flow (RFC 8252 §7.3 requires localhost redirect for desktop apps). The tested E2E flow had already confirmed localhost was needed, but the orchestrator accepted the finding without re-verification.

**Do not fabricate technical justifications**
When comparing design options, each technical argument must be independently valid. If the true differentiator is implementation cost, state that explicitly — never present cost preference as an architectural constraint. Experts must challenge any argument that conflates "harder to implement" with "technically incompatible."

**Do not blindly follow existing patterns**
When implementation follows an existing codebase pattern, each expert MUST explicitly evaluate: "Is the existing pattern correct, or is it a latent bug we are propagating?" In particular:

- If a field stores UUIDs, writing non-UUID values (e.g., sentinel strings like `"bulk"`) must be flagged regardless of existing code
- If a value is stored by one endpoint and read by another, verify the value is valid for both the write schema and the read query

**Verify type definitions before proposing value changes**
Before changing any value in a function call or object literal, read the type/schema definition of the target field. Common mistakes:

- Optional vs nullable: optional fields may not accept explicit null (e.g., `undefined` ≠ `null` in languages that distinguish them)
- Schema validators may reject values that the language's type system accepts (e.g., a UUID-format validator rejects arbitrary strings even if the static type is `string`)

This applies to both the Plan phase (pseudocode) and the Code Review phase (actual code).

### Known Recurring Issue Checklist

These issues have been found repeatedly in past reviews. Every expert MUST explicitly check for these patterns and report their findings (even if "not applicable" — this confirms the check was performed).

**All experts must check:**

| # | Pattern | What to grep/check | Severity if missed |
|---|---------|--------------------|--------------------|
| R1 | Shared utility reimplementation | `grep -r` for existing helpers (rate limiters, validators, encoders, formatters) before accepting new implementations | Major |
| R2 | Constants hardcoded in multiple places | Search for literal values that should be shared constants (validation limits, enum values, config defaults) | Major |
| R3 | Incomplete pattern propagation | When a pattern is changed in one file, search for ALL other files using the same pattern | Critical if security-relevant, Major otherwise |
| R4 | Event/notification dispatch gaps | When mutations are added, verify ALL similar mutation sites dispatch the corresponding event | Major |
| R5 | Missing transaction wrapping | findMany + update/delete in separate calls without DB transaction | Major |
| R6 | Cascade delete orphans | DB cascade deletes that don't clean up external storage (blob store, file system, cache) | Major |

**Security expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RS1 | Timing-safe comparison | Any credential/token/hash comparison using `===` or `!==` instead of `timingSafeEqual` | Critical |
| RS2 | Rate limiter on new routes | Every new API endpoint must have rate limiting (check if shared rate limiter exists) | Major |
| RS3 | Input validation at boundaries | New request parameters must be validated/sanitized at the schema level, not deep in business logic | Major |

**Testing expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RT1 | Mock-reality divergence | Mock return values must match actual API response shapes | Critical |
| RT2 | Testability verification | Before recommending "add test for X", confirm X is testable with the project's test infrastructure | — (reject finding if untestable) |
| RT3 | Shared constant in tests | Test assertions using hardcoded values that should import from shared constants | Major |

Each expert must include a "Recurring Issue Check" section in their output:
```
## Recurring Issue Check
- R1 (Shared utility reimplementation): [Checked — no issue / Finding F-XX]
- R2 (Constants hardcoded): [Checked — no issue / Finding F-XX]
- R3 (Pattern propagation): [Checked — no issue / Finding F-XX]
- R4 (Event dispatch gaps): [N/A — no mutations / Finding F-XX]
- R5 (Missing transactions): [N/A — no multi-step DB ops / Finding F-XX]
- R6 (Cascade delete orphans): [N/A — no deletes / Finding F-XX]
- [Expert-specific checks as applicable]
```

### Severity Classification Reference

Each expert uses their own severity criteria. When populating `[Expert-specific severity definitions]` in prompt templates, use the definitions below.

**Functionality expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | Requirements not met, data corruption, infinite loop/deadlock | Must fix immediately |
| Major | Logic error, unhandled edge case, architecture violation | Must fix |
| Minor | Naming, code structure, readability | Fix if straightforward, otherwise user decides |

**Security expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | RCE, auth bypass, SQLi/XSS, sensitive data exposure | Must fix immediately |
| Major | Insufficient access control, crypto misuse, SSRF | Must fix |
| Minor | Missing headers, excessive logging | Fix if straightforward, otherwise user decides |
| Conditional | Deprecated algorithms — Minor by default; escalate to Critical if used for authentication credentials, password hashing, or data integrity verification | Depends on context |

**Testing expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | No tests for critical path, false-positive tests (always pass) | Must fix immediately |
| Major | Insufficient coverage, flaky tests, mock inconsistency | Must fix |
| Minor | Test naming, assertion order, test redundancy | Fix if straightforward, otherwise user decides |
