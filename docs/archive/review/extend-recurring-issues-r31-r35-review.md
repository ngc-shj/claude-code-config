# Plan Review: extend-recurring-issues-r31-r35
Date: 2026-04-29
Review rounds: 3 (Round 1, Round 2, Round 3 — final scope-back applied after Round 3)

## Summary of rounds

| Round | Findings | Resolution |
|-------|----------|------------|
| Round 1 | 17 raw → 12 merged (M1-M12). 6 Major, 5 Minor, 1 informational. | Applied to plan. Plan grew from 1 file edit to 4 file edits + R31 runtime prong proposal. |
| Round 2 | 18 (F7-F11, S8-S12, T12-T19). 2 Critical, 8 Major, 8 Minor. | Applied to plan. Plan grew further: PreToolUse hook script + settings.json entry + positive/negative fixtures + Tier-2 expansions. |
| Round 3 | 21 (F12-F19, S13-S19, T20-T26). 6 Critical, 12 Major, 3 Minor. Many were artifacts of misunderstood Claude Code hook protocol. | Triggered scope re-evaluation. |

After Round 3, scope was cut back to the original intent: lessons-learned text additions to `common-rules.md` + `R1-R30` literal propagation. The runtime hook + fixtures + declared-grep machinery were deferred.

## Round 1 findings (consolidated)

| ID | Severity | Title | Status (after scope-back) |
|----|----------|-------|---------------------------|
| M1 | Major | Stale "R1-R30" range references — edit-locations table incomplete | APPLIED — plan adds edits 5-8 covering 12 occurrences across 4 files |
| M2 | Major | R31 destructive-ops coverage, detection & ownership gaps | PARTIALLY APPLIED — coverage (8 categories from S1/S6) is in plan; detection runtime prong DEFERRED to follow-up |
| M3 | Major | R32 boot-test boundary with R21 + security drift + ready signal | APPLIED — R32 body says "companion to R21", security note included, PR-author-declared ready signal documented |
| M4 | Major | R33 procedure + security gate severity + syntactic diversity | APPLIED — R33 promoted to Extended obligations, semantic-equivalence detection, security-control Critical escalation |
| M5 | Major | R34 line limit + security carve-out + detection mechanism | APPLIED — R34 body includes Anti-Deferral cross-reference + closed list for security carve-out + reviewer-driven sibling detection. Line cap dropped to ~10 lines. |
| M6 | Major | R35 tier split + section list + false-positive guard + phase-3 cross-ref | APPLIED — Tier-1/Tier-2 split, mechanical fire trigger artifact list, min sections, self-contained artifact path |
| M7 | Minor | R29 N/A confirmed | informational, no action |
| M8 | Minor | Visual-scan step not reproducible | APPLIED — replaced with grep-based structural checks |
| M9 | Minor | Step 3 grep-count one-directional | APPLIED — paired R-token diff |
| M10 | Minor | Step 4 token threshold arbitrary | APPLIED — tracked metric (20% growth) with explicit baseline (commit `d44c0e1`, 410 lines / 52139 bytes) |
| M11 | Minor | R35 false-positive guard not mechanical | APPLIED — covered by M6 mechanical fire-trigger list |
| M12 | Minor | Merged review file undefined | APPLIED — path is `./docs/archive/review/[plan-name]-review.md` (this file) |

## Round 2 findings (consolidated)

| ID | Severity | Title | Status (after scope-back) |
|----|----------|-------|---------------------------|
| F7 | Minor | Off-by-one (11 vs 12 occurrences) | APPLIED — corrected to 12 |
| F8 | Major | R31 runtime prong has no implementation mechanism | DEFERRED — runtime hook moved to follow-up plan |
| F9 | Minor | phase-2-coding.md sync — non-issue per stated assumption | confirmed N/A |
| F10 | Minor | R32-R21 boundary one-sided | APPLIED — edit 3c appends `(see also R32)` to R21 row |
| F11 | Minor | R34 self-fulfilling reasoning in dogfood | RESOLVED — scope-back removes the dogfood claim, R34 stays simple reviewer-judgment |
| S8 | Critical | R31 runtime self-check has no implementation owner | DEFERRED — same as F8 |
| S9 | Critical | R31 missing supply-chain & monitoring categories | APPLIED — category (i) "supply-chain & artifact-integrity destruction" added; category (g) expanded |
| S10 | Major | R34 "any security-sensitive surface" open-ended | APPLIED — closed list |
| S11 | Major | R35 Tier-2 omits IdP/KMS/mesh/webhook | APPLIED — Tier-2 expanded |
| S12 | Minor | R31 fixture coverage 7/8 | DEFERRED — fixtures deferred with the runtime hook |
| T12 | Major | R31 fixture coverage gap vs 9 categories | DEFERRED with the fixtures |
| T13 | Major | Structural grep scope ambiguity | APPLIED — testing strategy uses scoped grep `^\| R[0-9]+ ` to filter rule rows only |
| T14 | Major | Paired R-token diff false matches | APPLIED — sed-scoped extraction |
| T15 | Major | R32 30s fallback unmeasurable | APPLIED — fallback dropped, missing-ready-signal IS the finding |
| T16 | Major | R34 same-class judgment-based | DEFERRED — declared-grep machinery is a process change, R34 stays as reviewer enumeration like R3 |
| T17 | Major | R35 artifact list incomplete | APPLIED — expanded to k8s/Helm/Terraform/Pulumi/Ansible/cloud-init/systemd/CloudFormation/IdP/KMS/mesh/webhook |
| T18 | Minor | No negative fixture for R31 | DEFERRED with fixtures |
| T19 | Minor | Tracked-metric baseline timestamp | APPLIED — baseline at commit `d44c0e1`, 2026-04-29 |

## Round 3 findings (post-mortem)

Round 3 surfaced 21 new findings, most of which were artifacts of the runtime-hook scope creep:

| ID | Severity | Title | Status (after scope-back) |
|----|----------|-------|---------------------------|
| F12 | Critical | R31 hook script interface contradicts Claude Code's actual hook protocol | DEFERRED — runtime hook removed from this plan |
| F13 | Critical | settings.json hook entry path wrong (`$CLAUDE_PROJECT_DIR/..`) | DEFERRED with the hook |
| F14 | Major | Bash matcher already occupied — merge strategy unspecified | DEFERRED with the hook |
| F15 | Major | Hook destructive-verb pattern list unspecified | DEFERRED with the hook |
| F16 | Major | Error-path handling unspecified | DEFERRED with the hook |
| F17 | Major | Split-into-two-PRs trigger ambiguous | DROPPED — scope-back removes size pressure |
| F18 | Minor | R31 categories (e)/(f) overlap precedence rule | DROPPED — categories are reviewer-facing enumeration; overlap is acceptable |
| F19 | Minor | Hook script needs settings.json permissions.allow entry | DEFERRED with the hook |
| S13 | Critical | Bash-only matcher misses indirect execution paths | DEFERRED with the hook |
| S14 | Major | Hook script tampering perimeter undefined | DEFERRED with the hook |
| S15 | Critical | Script-injection / unsafe parsing of `CLAUDE_TOOL_INPUT` | DEFERRED with the hook |
| S16 | Major | Pattern-bypass / obfuscation not acknowledged | DEFERRED with the hook |
| S17 | Major | Supply-chain category (i) detects damage post-facto | NOTED — for the reviewer-text version, R31 (i) is a Phase 3 reviewer pre-merge static check (lockfile diff inspection); pre-install runtime detection is part of the deferred hook plan |
| S18 | Major | R34 closed list / R35 Tier-2 alignment | APPLIED — R34 closed list now includes the same surfaces as R35 Tier-2 |
| S19 | Minor | Hook path fragile/traversal-y | DEFERRED with the hook |
| T20 | Major | sed range overshoots into RS/RT tables | APPLIED — testing strategy uses `^\| R[0-9]+ ` filter to exclude RS/RT rows directly |
| T21 | Critical | Hook smoke test invokes echo, hook match semantics unspecified | DEFERRED with the hook |
| T22 | Critical | Positive-fixture asserts 9 Critical but reality is 6+3 | DEFERRED with fixtures |
| T23 | Major | Negative fixture purpose mismatched | DEFERRED with fixtures |
| T24 | Major | R34 declared-grep no fallback gate | DEFERRED with declared-grep machinery |
| T25 | Major | Split-PR no testing strategy adaptation | DROPPED with split-PR mechanism |
| T26 | Minor | Fixture content judgment-bound | DEFERRED with fixtures |

## Scope-back rationale

Of the 51 findings across 3 rounds, only 18 are about lessons-learned text content (the originally requested change). The remaining 33 are about runtime-hook infrastructure, fixtures, declared-grep process changes, and split-PR mechanisms — all of which are scope creep introduced during Round 1's expansion of the testing-expert finding T1 ("R31 grep judgment-based").

Round 3's Critical findings on hook protocol (F12, F13, S15) confirmed that this scope creep was not just over-engineered but also implementation-incorrect: the orchestrator was drafting a hook against an imagined protocol rather than the real one. Continuing to iterate on a wrong-mental-model artifact would compound errors.

The scope-back keeps every Round 1-3 finding that improves the lessons-learned text and defers everything that builds runtime infrastructure. R31 in particular returns to its original framing: a reviewer-agent obligation, structurally identical to R1-R30, not a runtime gate.

## Adjacent findings

- F6 [Adjacent] (Functionality → Security): R31 expert routing — RESOLVED via shared "All experts must check" framing.
- T11 [Adjacent] (Testing → Functionality): merged review file path — RESOLVED via convention.

## Recurring Issue Check (consolidated, Phase 1 review of plan)

Across 3 rounds, every expert reported R1-R30 + RS1-RS3 + RT1-RT3 statuses. Most are N/A for a documentation-change plan. Notable:

- R3 (Pattern propagation): Round 1 M1 fired — the plan initially missed `R1-R30` literal propagation across 4 files. Resolved by edits 5-8.
- R20 (Mechanical edit preservation): Round 1 noted that markdown insertions use `Edit` with explicit anchors, which is safe.
- R29 (External spec citation accuracy): N/A — no external spec citations in the plan.
- R30 (Markdown autolink footguns): Checked — no bare `#<n>`/`@<name>`/SHA-shaped tokens in plan or this review.
- RT2 (Testability verification): Round 1 T1 / Round 3 T21-T22 fired — most resolved via scope-back; deferred items moved to follow-up.

## Final state

After scope-back, the plan is a bounded documentation change:
- 4 skill files edited
- ~70 new lines in `common-rules.md`
- 12 `R1-R30` → `R1-R35` literal replacements
- Sync to `~/.claude/skills/triangulate/`

Within file-size budget (492-line / 62567-byte 20% threshold).
