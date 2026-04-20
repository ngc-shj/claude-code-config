---
name: multi-agent-review
description: "A skill that reviews plan files or codebases from three expert perspectives: functionality, security, and testing. Launches three sub-agents and repeats the review-and-fix loop until all issues are resolved. Always use this skill when: asked to review plans, code, or branches; asked to evaluate from functionality/security/testing perspectives; asked for PR or pre-implementation review; asked to implement or develop from a plan."
---

# Multi-Agent Review Skill

A skill that covers the entire development workflow from plan creation to coding to code review.
Three expert agents (functionality, security, testing) repeat review and fix cycles at each phase until all issues are resolved.

The skill is split across several files for context efficiency. Load only the files required for the current phase.

---

## Supplemental Files

| File | Load when |
|------|-----------|
| `phases/phase-1-plan.md` | Plan creation / plan review is the active phase |
| `phases/phase-2-coding.md` | Implementation is the active phase |
| `phases/phase-3-review.md` | Code review is the active phase |
| `common-rules.md` | Any phase — contains severity classification, sub-agent launch patterns, codebase awareness obligations, anti-deferral rules, and the recurring issue check reference (R1-R30, RS*, RT*) |

**Loading protocol** — when a phase file references a rule identifier (R1-R30, RSN, RTN), a "Common Rules" section, or an obligation defined elsewhere, Read `common-rules.md` before acting on that reference. Do not paraphrase from memory.

---

## Entry Point Decision

Determine the starting phase from the user's instructions:

| User instruction | Starting phase | First action |
|-----------------|----------------|--------------|
| "Implement", "Develop", etc. — starting from scratch | Phase 1 (Plan creation) | Read `phases/phase-1-plan.md` |
| An existing plan file path is specified | Phase 1 (From review) | Read `phases/phase-1-plan.md` |
| "Review the code", "Review the branch" | Phase 3 (Code review) | Read `phases/phase-3-review.md` |

## Phase Transitions

- Phase 1 → Phase 2: after plan review completes, Read `phases/phase-2-coding.md`
- Phase 2 → Phase 3: after coding completes, Read `phases/phase-3-review.md`
- Phase 3 standalone: when invoked for branch review only, skip Phase 1 and 2

Each phase file ends with a summary and a pointer to the next phase. Follow the pointer when the current phase reports complete.
