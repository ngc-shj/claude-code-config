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

### Step 1-1: Determine Plan Name

If no plan name is specified, auto-generate a short English slug (kebab-case) from the task content and confirm with the user.
If specified, use that name.

```
Plan name: [plan-name]
Save to: ~/.claude/plans/[plan-name].md
```

### Step 1-2: Create the Plan

Use Claude Code's built-in plan creation feature to create a plan and save it to `~/.claude/plans/[plan-name].md`.

Ensure the following sections are included for review expert agents to evaluate. Add missing sections as needed:

- **Objective**: What to achieve
- **Requirements**: Functional and non-functional requirements
- **Technical approach**: Technologies, architecture, and design decisions
- **Implementation steps**: Concrete implementation steps (numbered)
- **Testing strategy**: How to test
- **Considerations & constraints**: Known risks, constraints, and out-of-scope items

### Step 1-3: Local LLM Pre-screening (Optional)

Before launching Claude sub-agents, run a quick pre-screening pass using local LLM to catch obvious issues and reduce API cost.
The script reads the plan file directly and calls Ollama via curl — no Claude tokens consumed.

```bash
PLAN_FILE=~/.claude/plans/[plan-name].md bash ~/.claude/hooks/pre-review.sh plan
```

If the output contains issues, fix them in the plan before proceeding to expert review.
If Ollama is unavailable, the script outputs a warning and exits gracefully — proceed to Step 1-4.

Save the local LLM output for reference in Step 1-4 (to avoid duplicate findings).

### Step 1-4: Plan Review by Three Expert Agents (Claude Sub-agents)

Launch three sub-agents in parallel with the following roles (fall back to sequential inline execution if unavailable).

| Agent | Role | Evaluation perspective |
|-------|------|----------------------|
| Functionality expert | Senior Software Engineer | Requirements coverage, architecture, feasibility, edge cases |
| Security expert | Security Engineer | Threat model, authentication/authorization, data protection, OWASP Top 10, injection, auth bypass |
| Testing expert | QA Engineer | Test strategy, coverage, testability, CI/CD integration |

Instruction template for each sub-agent:

**Round 1 (full review):**
```
You are a [role name].
Evaluate the following plan from a [perspective] perspective.

Plan contents:
[Plan file contents]

Local LLM pre-screening results (already addressed — do not re-report these):
[Local LLM output, or "None" if skipped]

Requirements:
- Only raise specific and actionable findings
- Classify each finding by severity: Critical / Major / Minor
  - Critical: Blocks release, causes data loss, security vulnerability
  - Major: Significant functional issue, performance problem
  - Minor: Style, naming, minor improvement suggestion
- For each finding, specify "Severity", "Problem", "Impact", and "Recommended action"
- Do not duplicate issues already caught by local LLM pre-screening
- If there are no findings, explicitly state "No findings"
```

**Round 2+ (incremental review):**
```
You are a [role name].
Review the changes made since the last round from a [perspective] perspective.

Changes since last round:
[Diff or description of changes]

Previous findings and their resolution:
[Previous findings with status: resolved/continuing]

Requirements:
- Verify that previous fixes are correct and complete
- Check if fixes introduced regression or new issues in surrounding context
- Report any previously overlooked issues
- Classify each finding by severity: Critical / Major / Minor
- If there are no findings, explicitly state "No findings"
```

### Step 1-5: Save Review Results and Deduplicate

Consolidate the three agents' evaluations. Before saving, deduplicate findings:
- Merge findings that describe the same underlying issue from different perspectives
- Keep the most comprehensive description and note all perspectives that flagged it

Save to `./docs/review/[plan-name]-review.md` (create `./docs/review/` if it doesn't exist).

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
```

### Step 1-6: Validity Assessment and Plan Update

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
git checkout -b [plan-name]

# Copy finalized plan to docs/review
cp ~/.claude/plans/[plan-name].md ./docs/review/[plan-name]-plan.md

# Commit
git add ./docs/review/[plan-name]-plan.md
git add ./docs/review/[plan-name]-review.md

git commit -m "plan: [plan-name] - plan creation and review complete"
```

Report to user:
```
=== Phase 1 Complete ===
Plan: ~/.claude/plans/[plan-name].md (original)
      ./docs/review/[plan-name]-plan.md (repository copy)
Branch: [plan-name]
Review rounds: [n]
Next step: Proceeding to Phase 2 (Coding)
```

---

## Phase 2: Coding

### Step 2-1: Review the Plan

Read `~/.claude/plans/[plan-name].md` and understand the implementation steps.

### Step 2-2: Implementation

Code according to the plan's "Implementation steps".

Recording rules during implementation:
- Sections implemented as planned: No recording needed
- **Sections that deviate from the plan**: Append to the deviation log with reasons (see Step 2-3)

### Step 2-3: Deviation Log Management

Record deviations from the plan in `./docs/review/[plan-name]-deviation.md`.

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

Report to user when implementation is done:
```
=== Phase 2 Complete ===
Files implemented: [n]
Deviations from plan: [yes/no] (log: ./docs/review/[plan-name]-deviation.md)
Next step: Proceeding to Phase 3 (Code Review)
```

---

## Phase 3: Code Review, Fix & Commit

### Step 3-1: Gather Review Input

Read the following three items:
1. Finalized plan: `~/.claude/plans/[plan-name].md`
2. Deviation log: `./docs/review/[plan-name]-deviation.md`
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

**Round 1 (full review):**
```
You are a [role name].
Review the code on the current branch from a [perspective] perspective.

Finalized plan:
[Plan contents]

Deviation log:
[Deviation log contents]

Target code:
[Code contents]

Local LLM pre-screening results (already addressed — do not re-report these):
[Local LLM output, or "None" if skipped]

Requirements:
- Only specific and actionable findings (vague findings are prohibited)
- Classify each finding by severity: Critical / Major / Minor
  - Critical: Bugs causing data loss/corruption, security vulnerabilities, crashes
  - Major: Incorrect logic, missing error handling, performance issues
  - Minor: Naming, style, minor improvements
- For each finding, specify file name, line number, severity, problem, and recommended fix
- Consider the deviation log when reviewing
- Do not duplicate issues already caught by local LLM pre-screening
- If there are no findings, explicitly state "No findings"
```

**Round 2+ (incremental review):**
```
You are a [role name].
Review the fixes made since the last round from a [perspective] perspective.

Changes since last round (diff):
[git diff of fixes]

Previous findings and their resolution:
[Previous findings with status: resolved/new/continuing]

Context files (files affected by the changes):
[Relevant surrounding code]

Requirements:
- Verify that previous fixes are correct and complete
- Check if fixes introduced regression or new issues in surrounding context
- Report any previously overlooked issues
- Classify each finding by severity: Critical / Major / Minor
- For each finding, specify file name, line number, severity, problem, and recommended fix
- Indicate status from previous round (resolved, new, continuing)
- If there are no findings, explicitly state "No findings"
```

### Step 3-4: Save Review Results and Deduplicate

Consolidate and deduplicate findings (merge same underlying issue flagged by multiple agents).

Save to `./docs/review/[plan-name]-code-review.md` (overwrite).

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

## Resolution Status
[Updated after fixes]
```

### Step 3-5: Fix the Code

The main agent scrutinizes findings and fixes based on severity:
- **Critical**: Must fix immediately
- **Major**: Must fix
- **Minor**: Fix if straightforward, otherwise consult the user

Important rules:
- **No deferring**: "Address later" is not an option for Critical/Major
- For findings that are difficult to fix, consult the user before deciding
- Always run tests after fixes

### Step 3-6: Test and Commit

```bash
# Run tests (use project-appropriate command)
[test command]

# Commit if tests pass
git add -A
git commit -m "review([n]): [summary of fixes]"
```

### Step 3-7: Update Resolution Status

Append to the "Resolution Status" section of `./docs/review/[plan-name]-code-review.md`:

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
git add ./docs/review/[plan-name]-code-review.md
git add ./docs/review/[plan-name]-deviation.md
git commit -m "review: code review complete - all findings resolved"
```

Final report:
```
=== All Phases Complete ===
Plan name: [plan-name]
Branch: [plan-name]
Plan review rounds: [n]
Code review rounds: [n]
Artifacts:
  - ./docs/review/[plan-name]-plan.md (finalized plan)
  - ./docs/review/[plan-name]-review.md (plan review log)
  - ./docs/review/[plan-name]-deviation.md (deviation log)
  - ./docs/review/[plan-name]-code-review.md (code review log)
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

### Ensure docs/review Directory

Create `./docs/review/` before starting review if it doesn't exist:
```bash
mkdir -p ./docs/review
```

### When Sub-agents Are Unavailable

Process the three perspectives sequentially inline.
Explain to the user that evaluation objectivity may be reduced.

### No Commits to main

All commits must be made on the `[plan-name]` branch.
If accidentally on main, create a new branch before continuing work.

### Severity Classification Reference

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | Data loss, security vulnerability, crash, blocks release | Must fix immediately |
| Major | Incorrect logic, missing error handling, performance issue | Must fix |
| Minor | Naming, style, minor improvement | Fix if straightforward, otherwise user decides |
