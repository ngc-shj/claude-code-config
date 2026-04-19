# Coding Deviation Log: expand-ollama-delegation
Created: 2026-04-19

## Deviations from Plan

### D1: README overview-section pr-create update (not in Implementation Checklist)
- **Plan description**: Implementation step 5 specified appending 6 new example pipelines to the `ollama-utils.sh` code block. It did NOT mention updating the `### pr-create` overview paragraph elsewhere in README.md (around line 234-238).
- **Actual implementation**: Batch D appended the examples as planned. During cross-cutting verification step 7.10 (stale-Sonnet-reference sweep), the `### pr-create` skill overview was found to still describe "Sonnet sub-agent composes PR body" — stale after the Batch B pr-create/SKILL.md change. Updated that paragraph to match the new local-LLM-only reality.
- **Reason**: R3 propagation consequence — changing pr-create's implementation made the pre-existing overview paragraph stale. Pre-existing-in-changed-file rule applies (README.md is in this branch's diff via Batch D).
- **Impact scope**: `README.md` pr-create overview paragraph only. No behavior change; documentation alignment.

## No other deviations

All 4 batches (A hook additions, B pr-create SKILL.md, C multi-agent-review SKILL.md, D README examples) implemented as specified in the Implementation Checklist. All 10 cross-cutting verification checks pass:

| # | Check | Expected | Actual |
|---|---|---|---|
| 7.1 | dispatcher cases | 13 | 13 ✓ |
| 7.2 | 6 distinct cmd names in help | 6 | 6 ✓ |
| 7.3 | Sonnet in pr-create/SKILL.md | 0 | 0 ✓ |
| 7.4 | old Sonnet-sub-agent deviation-log text | 0 | 0 ✓ |
| 7.5 | `~/\.claude/hooks/ollama-utils\.sh <new-cmd>` in skills | ≥6 | 8 ✓ |
| 7.6 | `OLLAMA-INPUT-SEPARATOR` across repo | ≥10 | 12 ✓ |
| 7.7 | new cmds in README | ≥6 | 6 ✓ |
| 7.8 | settings.json allow rule intact | present | present ✓ |
| 7.9 | wildcard coverage | no permission prompt | no prompt observed during smoke test ✓ |
| 7.10 | stale Sonnet sweep | all remaining refs intentional | all remaining intentional (test-gen, Step 2-2 impl, explore, simplify, README-Ollama-architecture) ✓ |

Token-measurement (informational, not pass/fail): deferred to first post-deployment `/pr-create` invocation — record tool-usage `total_tokens` and compare against an historic PR #24 or #25 baseline. No gating.
