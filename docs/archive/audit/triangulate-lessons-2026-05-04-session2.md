# Lessons Learned: triangulate skill (session 2 — Phase 1+2+3 full pass)

Date: 2026-05-04 (filed same day as session-1; this is a separate run by a
different operator and surfaces partly-overlapping but mostly new findings)
Source run: one continuous ~12h session that took a feature through Phase 1
plan review (2 rounds, 37 + 15 findings), Phase 2 implementation (4 Sonnet
sub-agent batches), Phase 3 code review (2 rounds, 9 + 4 findings + R34
escalation), manual test execution (M1-M3), and 3 push rounds of CI repair
ending in a green PR #442.

This document captures the operator's retrospective verbatim under "Findings"
and the disposition (which earlier PR addresses it / what new work remains)
under "Disposition".

---

## What worked

- **3-expert parallel review** caught items a single expert would have missed:
  - Functionality F1: matrix actor incorrectly inferred from route file name
  - Security S10: PR #433/S1 invariant (REQUESTED→STALE) matrix gap
  - Testing T1: vitest swc passes but `tsc --noEmit` fails on missing types
- **R1-R36 + RS*/RT* checklist** added value in both plan and code review.
  Particularly R12 (enum coverage) and R31 (destructive-op safety).
- **Anti-Deferral Rule** fired correctly via Round 2 Security expert on R34
  (pre-existing-in-changed-file is in-scope, not deferrable).
- **Locked Contracts (C1-C8) + Go/No-Go Gate** at the plan tail (introduced
  on user direction during the session) was the practical mechanism that
  stopped the pseudo-code iteration spiral.

## Findings

### A. Pseudo-code in Phase 1 inflates plan size

Each plan-review round added pseudo-code to the plan; by Round 3 it had grown
to 400+ lines and pseudo-code blocks contradicted each other ("require tx" vs.
"accept TxOrPrisma"). Operator pivoted on user direction — "contracts → types →
implementation" — and Round 4 became unnecessary.

**Status**: PR-A (#48) addressed the contract-first default. Two refinements
remain that the operator validated empirically in this session:
- **Number contracts (C1, C2, ..., C8)** so they can be referenced by ID in
  reviews and findings.
- **Add an explicit Go/No-Go Gate** at the plan tail listing each contract by
  ID with a binary "verified locked" status. The plan does not transition to
  Phase 2 until every contract reads "locked".

### B. CI gate enumeration was incomplete

Phase 1 / Phase 2 Step 2-1 impact analysis missed CI gates that fired only
after push. Specifically `check-bypass-rls.mjs` (new file using
`withBypassRls`) and `verify-allowlist-rename-only.mjs` (allowlist edits must
be rename-only). Each surfaced as a CI failure that triggered an additional
push round.

**Proposed fix**: Phase 2 Step 2-1 must enumerate every CI gate that the
diff's changed-file pattern could trigger. Concrete check (illustrative —
adapt path for the project's CI directory layout):

```bash
find .github/workflows/ scripts/checks/ -type f \
  -exec grep -l "<changed-file-pattern>" {} \;
```

Each hit is a CI gate that runs against this PR; review it before
implementation, not after the first push fails.

### C. Mandatory checks diverged from CI

The skill's Phase 2-4 verification block ran `vitest run` + `next build` only,
because those are what CLAUDE.md flags as required. CI ran additional guards
(`check:bypass-rls`, `verify-allowlist-rename-only`, `check:team-auth-rls`,
others) that the local pre-push pass did not exercise.

**Proposed fix**: ship a helper that extracts every lint/check command from
the project's CI configuration and runs them as part of Phase 2-4. Skeleton
(illustrative — adapt to project's CI tool):

```bash
# Extract from GitHub Actions
yq '.jobs.*.steps[].run' .github/workflows/*.yml | grep -E 'lint|check|verify' | sort -u
```

Run each extracted command. Do not declare Phase 2 complete until every CI
gate the PR will hit has been exercised locally.

### D. Manual-test document inflated to 319 lines

The first manual-test draft attempted to enumerate every route flow and every
adversarial scenario. User direction: "only what genuinely needs human hands".
Final filtered version was 3 items (HTTP-layer race, E2E UI flow, DB invariant
SQL).

**Proposed fix**: Phase 3 manual-test.md generation must apply two filters
before writing content:
1. **Automation deduplication**: any invariant already verified by an
   automated test (unit / integration / E2E) is excluded from manual-test.md.
2. **True-need filter**: only items requiring at least one of {browser auth,
   UI crypto rendering, multi-process race that test infra cannot reproduce}
   stay in manual-test.md.

### E. Phase 3 stop condition was implicit

Round 2 produced new findings classified as "tightening only" (refinement
within the prior round's fix). The operator skipped Round 3 on judgment, but
the skill's only documented stop is the 10-round cap.

**Proposed fix**: codify the tightening-only skip rule in Step 3-8:
- Skip is permitted when **every** Round-n new finding falls within the prior
  round's fix scope AND is classified as inline minor (typo / comment /
  formatting / variable rename).
- Skip is **forbidden** when any Round-n finding touches a security boundary
  (auth, authz, crypto, session, input validation, audit logging) — those
  always trigger Round n+1.

### F. Integration test assumed worker-process availability in CI

The operator wrote an integration test that polled `audit_logs` directly,
assuming the outbox-drainer worker was running. CI runs the test process
without the worker, so the test timed out forever.

**Proposed fix**: Phase 2 Step 2-1 "Storage-backend schema verification" must
add an async-I/O observation rule: when a write is mediated by a queue,
outbox, stream, or other async pipeline, the test must observe the
**upstream intermediate state** (the queue/outbox table itself), not the
drained terminal state — unless the project's CI explicitly runs the drainer
process in test mode.

### G. Pseudo-code snippets were type-incomplete

Plan pseudo-code wrote `Omit<Prisma.X.UpdateInput, "status">` for an
`updateMany` call. The actual ORM contract for `updateMany` requires
`UncheckedUpdateManyInput` (relation-form vs. unchecked-form distinction).
Phase 2 sub-agent fixed during implementation; logged as deviation §1.

**Proposed fix**: Phase 1 Functionality expert obligation must include a
spot-check for ORM-specific type-shape mismatches. The instruction stays
language-agnostic per the project's "no language/framework/repo-specific
identifiers" feedback memory — the rule names the failure mode (different
input types per write operation), illustrative examples are flagged as such,
and the actual ORM is left to project context.

## Disposition

| # | Status | Vehicle |
|---|--------|---------|
| A | Partially addressed by PR-A #48 (contract-first default). Refinement: numbered contracts (C1-C8) + Go/No-Go gate. | PR-D |
| B | New. CI gate enumeration in Phase 2 Step 2-1. | PR-E |
| C | New. CI-step extraction helper + Phase 2-4 invocation. | PR-E |
| D | New. Two-filter rule for manual-test.md generation. | PR-F |
| E | New. Tightening-only skip rule in Step 3-8. | PR-F |
| F | New. Async-I/O upstream-observation rule in Step 2-1. | PR-E |
| G | New. ORM type-shape spot-check obligation in Step 1-4 (lang-agnostic phrasing). | PR-D |

Sequencing: PR-D / PR-E / PR-F edit different files (phase-1 / phase-2 /
phase-3 respectively), so they can land in parallel without conflict.
