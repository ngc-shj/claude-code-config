---
name: triangulate
description: "Triangulate plans and code from three expert viewpoints — functionality, security, and testing — across three phases (plan, implementation, review). Each iteration sharpens the position of remaining issues until all are resolved. Always use this skill when: asked to review plans, code, or branches; asked to evaluate from functionality/security/testing perspectives; asked for PR or pre-implementation review; asked to implement or develop from a plan."
---

# Triangulate Skill

A skill that covers the entire development workflow from plan creation to coding to code review.
Three expert agents (functionality, security, testing) triangulate issues at each phase, repeating review and fix cycles until all findings are resolved.

The skill is split across several files for context efficiency. Load only the files required for the current phase.

---

## Supplemental Files

| File | Load when |
|------|-----------|
| `phases/phase-1-plan.md` | Plan creation / plan review is the active phase |
| `phases/phase-2-coding.md` | Implementation is the active phase |
| `phases/phase-3-review.md` | Code review is the active phase |
| `common-rules.digest.md` | Any phase — compact routing index for recurring rules (R1-R44, RS*, RT*); read before selecting rules |
| `common-rules.md` | Targeted lookup only — full rule rows, extended obligations, severity tables, and shared orchestration obligations |

**Loading protocol** — Read `common-rules.digest.md` first. Match its pattern names against the diff and task, then use anchored `rg` queries to extract only the triggered rows from `common-rules.md`; also extract a selected rule's Extended obligations section when its row points there. For a named non-recurring Common Rules section, extract that heading and its bounded section. Read the full `common-rules.md` only when targeted extraction is inconclusive, and record the reason. Do not paraphrase rule details from memory.

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
