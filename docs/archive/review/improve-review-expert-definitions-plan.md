# Plan: Improve Review Expert Definitions

## Objective

Enhance the multi-agent-review skill's three expert agents by:
1. Adding explicit scope boundaries to reduce finding duplication
2. Defining expert-specific severity classifications for more precise evaluation
3. Specifying model routing for each expert sub-agent

## Requirements

### Functional Requirements
- Each expert's prompt template must include "out-of-scope" directives to prevent overlap
- Severity definitions must be tailored per expert role (Functionality, Security, Testing)
- The same expert-specific severity definitions must be used in both Phase 1 and Phase 3 templates
- Model selection must be specified per expert in the skill definition
- Changes must apply to both Phase 1 (plan review) and Phase 3 (code review) templates

### Non-functional Requirements
- Backward compatible — existing workflow and phase structure unchanged
- No increase in the number of sub-agents (keep 3)
- Token efficiency should improve (fewer duplicate findings = fewer review rounds)

## Technical Approach

### 1. Scope Boundaries (Section: Expert Role Table + Prompt Templates)

Add an "Out of scope" column to the expert role table and embed scope directives in prompt templates:

| Expert | In scope | Out of scope |
|--------|----------|-------------|
| Functionality | Logic correctness, requirements coverage, architecture, edge cases, error handling | Security vulnerabilities, test design/coverage |
| Security | Threat model, auth/authz, data protection, OWASP Top 10, injection, crypto, **business logic vulnerabilities (OWASP A04)** | Functional correctness (non-security), test strategy |
| Testing | Test strategy, coverage, testability, CI/CD, test quality | Implementation correctness, security analysis |

**[Adjacent] tag obligation**: When an expert encounters an issue outside their scope but with potential impact, they MUST flag it using the format: `[Adjacent] Severity: Problem — this may overlap with [other expert]'s scope`. This is mandatory, not optional.

### 2. Expert-specific Severity Definitions (Section: Prompt Templates + Common Rules)

Replace the shared severity table with per-expert definitions. These definitions are identical in Phase 1 and Phase 3.

**Functionality:**
- Critical: Requirements not met, data corruption, infinite loop/deadlock
- Major: Logic error, unhandled edge case, architecture violation
- Minor: Naming, code structure, readability

**Security:**
- Critical: RCE, auth bypass, SQLi/XSS, sensitive data exposure
- Major: Insufficient access control, crypto misuse, SSRF
- Minor: Missing headers, excessive logging
- Conditional: Deprecated algorithms — Minor by default; escalate to Critical if used for authentication credentials, password hashing, or data integrity verification

**Testing:**
- Critical: No tests for critical path, false-positive tests (always pass)
- Major: Insufficient coverage, flaky tests, mock inconsistency
- Minor: Test naming, assertion order, test redundancy

### 3. Model Routing (New Section in Common Rules)

Add a "Sub-agent Model Selection" section:

| Expert | Default model | Escalation |
|--------|--------------|------------|
| Functionality | Sonnet | — |
| Security | Sonnet | Opus (for complex auth flow analysis) |
| Testing | Sonnet | — |

Escalation mechanism:
1. **Detection**: Security expert's output format must include an `escalate: true/false` field with an `escalate_reason` **per Critical finding** (not per expert). Format: each Critical finding block ends with `escalate: true/false` and `escalate_reason: [reason]`. The main orchestrator checks these flags — no natural-language pattern matching required.
2. **Re-run**: If `escalate: true` is present, re-launch the Security expert with `model: "opus"` parameter, passing the same input plus the Sonnet findings as additional context.
3. **Merge**: Opus findings are merged with Sonnet findings (not replaced). Opus takes precedence for any overlapping Critical findings; Sonnet's non-overlapping Major/Minor findings are preserved.

### 4. Handling [Adjacent] Findings (New Section in Common Rules)

Define processing rules for `[Adjacent]`-tagged findings:
1. During deduplication (Step 1-5 / Step 3-4): `[Adjacent]` findings are preserved and NOT merged with the originating expert's findings
2. During fix assessment (Step 1-6 / Step 3-5): The main orchestrator routes each `[Adjacent]` finding to the appropriate expert's scope for evaluation
3. If the appropriate expert already reported the same issue: merge and keep the more comprehensive description
4. If the appropriate expert did not report it: treat it as a new finding from that expert's perspective

## Implementation Steps

1. Update the expert role table in Step 1-4 and Step 3-3 to add "Out of scope" column and [Adjacent] tag obligation
2. Add scope boundary directives to Round 1 and Round 2+ prompt templates in Step 1-4
3. Add scope boundary directives to Round 1 and Round 2+ prompt templates in Step 3-3
4. Replace shared severity definition in prompt templates with expert-specific definitions (identical in Phase 1 and Phase 3)
5. Add `escalate: true/false` field to Security expert's output format in prompt templates
6. Add "Sub-agent Model Selection" section to Common Rules
7. Add "Handling [Adjacent] Findings" section to Common Rules
8. Update the "Severity Classification Reference" table in Common Rules to reference expert-specific definitions
9. Apply identical changes to both `~/.claude/skills/multi-agent-review/SKILL.md` and `skills/multi-agent-review/SKILL.md` (project copy)
10. Verify file sync: `diff ~/.claude/skills/multi-agent-review/SKILL.md skills/multi-agent-review/SKILL.md`

## Testing Strategy

- Manual review: Read through updated SKILL.md to verify consistency across Phase 1 and Phase 3 templates
- File sync check: Run `diff` between the two SKILL.md copies to confirm they are identical
- Markdown validation: Verify all added tables render correctly, all prompt template code blocks are properly closed, and nested list structure is intact
- Dry run: Invoke the skill on a small test case to verify:
  - Scope boundary directives appear in sub-agent prompts
  - Expert-specific severity definitions are used (not shared definitions)
  - `escalate` field appears in Security expert output format
  - `[Adjacent]` tag format is documented in the prompt

## Considerations & Constraints

- **Scope**: Only modifying SKILL.md — no changes to hooks, settings, or other skills
- **Risk**: Over-constraining scope boundaries may cause blind spots; mitigated by mandatory `[Adjacent]` tagging with defined processing rules in the orchestrator
- **Out of scope**: Adding new expert agents, changing the phase structure, modifying the review loop logic
