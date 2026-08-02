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
| `common-rules.digest.md` | Any phase — compact routing index for recurring rules (R1-R57, RS*, RT*); read before selecting rules |
| `common-rules.md` | Targeted lookup only — full rule rows, extended obligations, severity tables, and shared orchestration obligations |

**Loading protocol** — Read `common-rules.digest.md` first. Match its pattern names against the diff and task, then use anchored `rg` queries to extract only the triggered rows from `common-rules.md`; also extract a selected rule's Extended obligations section when its row points there. For a named non-recurring Common Rules section, extract that heading and its bounded section. Read the full `common-rules.md` only when targeted extraction is inconclusive, and record the reason. Do not paraphrase rule details from memory.

**Truncation protocol** — a partial read of a phase file is silent unless you check for it:

1. Read phase files and `common-rules.digest.md` with the `Read` tool, whole-file. Do not `cat`/`head` them through Bash — Bash output passes through an output-compressing proxy that can render a 500-line file as its first line plus a `[N more lines]` marker.
2. Every phase file's last line is `## END-OF-PHASE-<N>`, and `common-rules.digest.md`'s last line is `## END-OF-DIGEST`. If the last line you received is not that terminator, the read was partial — re-read before acting on it.
3. Before reporting a phase complete, reconcile the steps you executed against the `step_ids:` declared in that phase's front matter. An unexecuted ID means the phase is not complete. The step named in `core:` has no substitute — inline work by the orchestrator does not discharge it.

<!-- Machine-parsed by hooks/check-rule-sync.sh (check 8) BY SHAPE: backticked
     key tokens, and a backticked stem followed by "(phase files)" / "(the
     digest)". Reword the sentence and the stems stop extracting. -->
Manifest keys: `step_ids:`, `core:`. Terminator stems: `END-OF-PHASE` (phase files), `END-OF-DIGEST` (the digest).

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

Each phase file ends with a summary, a pointer to the next phase, and its `## END-OF-PHASE-N` terminator as the final line. Follow the pointer when the current phase reports complete.
