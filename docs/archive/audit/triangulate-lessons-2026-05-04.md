# Lessons Learned: triangulate skill (issue #435 run)

Date: 2026-05-04
Source run: production triangulate execution against issue #435 (3-round plan review,
Phase 2 implementation, Phase 3 review with 13 findings).

This document captures concrete failure modes observed during the run and proposes
skill-level fixes. Filed under `docs/archive/audit/` as a retrospective artifact;
the actionable items are tracked through staged PRs against `skills/triangulate/`
and `skills/triangulate/common-rules.md`.

---

## 1. Pseudo-code-driven plan loop (central failure)

**Symptom.** Three rounds of plan review where each round surfaced a new bug
introduced by the previous round's pseudo-code rewrite — an untreatable pattern.
Round 3 only converged after the user pivoted to "contract → type → implementation".

**Root cause.** The current Phase 1 plan template incentivises authors to write
pseudo-code under "Implementation steps". Pseudo-code inflates the review surface
area and invites round-trip rewrites of code that does not yet exist.

**Fix.** Phase 1 default should be **contract-first**: function signatures,
invariants, forbidden patterns, and acceptance criteria — no pseudo-code body.
Pseudo-code is opt-in only when an algorithm is genuinely novel.

---

## 2. R35 Tier-2 manual test missed in Phase 2

**Symptom.** PR was marked ready before the user noticed the missing manual-test
artifact. R35 is documented in `common-rules.md` Extended obligations, but no
mechanical check in Phase 2-4 detects when its trigger conditions apply.

**Fix.** Add a mechanical R35 gate to Phase 2-4:
- Run `git diff --name-only main...HEAD` and intersect with the
  deployment-artifact list and auth-flow paths declared by the project.
- If the intersection is non-empty, presence of `manual-test.md` becomes a
  Phase 2 completion gate.

---

## 3. User-specific recurring memory not consulted during Phase 2

**Symptom.** A standing memory (`3+ enumerated string literals → const-object`)
was not applied during Phase 2 — string literals like `"replay"` were inlined.
Caught only on user review.

**Fix.** Add a "user feedback memory cross-check" step to Phase 2:
```
ls ~/.claude/projects/<slug>/memory/feedback_*.md
```
Enumerate each feedback file and grep its rule text against the staged diff
before declaring Phase 2 complete.

---

## 4. Contract 1 violation slipped through Phase 2

**Symptom.** The plan declared "nested `$transaction` on raw client is forbidden"
as a contract, but Phase 2 reused an existing pattern
(`withBypassRls(p, async () => p.$transaction(...))`) and shipped it. Phase 3
flagged it as Critical S1.

**Root cause.** No mechanical check that staged code conforms to plan-declared
forbidden patterns. "Existing code does this" was treated as implicit permission.

**Fix.** Add contract conformance grep to Phase 2-4. For each forbidden-pattern
contract in the plan:
```
git diff main...HEAD | grep -nE '<forbidden-pattern>'
```
must return empty. Existing-code precedent does not exempt new code from
contract violation.

---

## 5. Race-test vacuous-pass guard missing from R checklist

**Symptom.** The race test had a cardinality assertion (`bothSucceeded === 0`)
but no assertion that the race window actually opened
(`expect(successes).toBeGreaterThan(0)`). With a misconfigured RLS context,
all iterations would have returned `not_found` and the test would still pass.
Caught in Phase 3 by T4 (testing reviewer).

**Fix.** Add **RT4** to `common-rules.md`: race-style tests with cardinality
assertions must additionally assert that **both branches of the contested
outcome occurred at least once** during the test run. A test that asserts "no
double-success" without asserting "at least one success happened" is vacuously
satisfiable.

---

## 6. Phase 3 surfaced 13 findings → Phase 2 lacked self-R-check

**Symptom.** Phase 3 reviewers produced 13 findings on first pass. Phase 2
mandatory checks are mechanical (lint/test/build) and do not exercise R1-R36
self-review. Phase 3 reviewers ended up doing the first R-check pass instead of
incremental verification.

**Fix.** Add a self-R-check step to Phase 2-4: invoke the same three Phase 3
sub-agents with a focused mini-prompt (R-checks only, no broad review) before
declaring Phase 2 complete. Phase 3 then operates as incremental verification
on remaining issues, not first-pass discovery.

---

## 7. Long-conversation careless mistakes

**Symptom.** After context exceeded ~150K tokens, low-level errors spiked:
- Table name singular/plural confusion (`team_password_entry_history` vs.
  `team_password_entries_history`) → 144 false test failures.
- Wrong prefix (`mcp_at_` instead of correct prefix).
- `.id` access on a string-typed `winner.accessToken.id`.

**Fix.** Add a **mid-conversation checkpoint obligation** to `common-rules.md`:
once context exceeds ~100K tokens, before the next action, write a single-page
summary of state (decisions, open issues, current diff scope) and continue from
that summary (`/compact`-style). The summary forces re-grounding before
context-decay errors compound.

---

## 8. No detection mechanism for cross-test pollution cascade

**Symptom.** An early `helpers.ts` extension bug left dirty state in a shared
test tenant. 144 unrelated tests failed as collateral damage. Manual `TRUNCATE`
was required for recovery.

**Fix.** Extend Phase 2-4 "Real-environment test obligation": after an
integration-test failure, **before re-running**, verify DB clean state — assert
the affected tenant's primary tables are empty, or run the project's reset
command. A re-run on dirty state masks the original failure with cascading
unrelated failures.

---

## 9. Ollama merge-findings call had no timeout

**Symptom.** The Ollama call hung once for several minutes before completing
(detected by parallel notification). The skill has no timeout or fallback path.

**Fix.** In `phase-1-5` and `phase-3-4` (the Ollama merge steps), specify a
60-second timeout and a documented manual-fallback procedure. Ollama is a soft
dependency; the skill must remain executable when it is unavailable.

---

## Disposition

These items are scheduled as three staged PRs (option B from the user
disposition):

- **PR-A — Skill structural changes** (items 1, 2, 4, 6, 8, 9):
  contract-first Phase 1 template, mechanical R35 / contract / self-R-check
  gates, DB clean-state verification, Ollama timeout.
- **PR-B — New common-rules** (items 5, 7):
  RT4 (race-test cardinality guard) and mid-conversation checkpoint obligation.
- **PR-C — Memory-aware Phase 2** (item 3):
  feedback-memory cross-check step.

Sequencing rationale: PR-A is structural and rewrites Phase template scaffolding;
landing it first keeps subsequent diffs reviewable. PR-B adds standalone rules
with no template dependency. PR-C touches only Phase 2 and stacks cleanly on PR-A.
