# Plan Review: triangulate-r43-rt9-failsafe-lessons
Date: 2026-07-11
Review round: 1

## Changes from Previous Round
Initial review.

## Merged Findings

**Severity**: Major
**Problem**: Contract C9's member-set derivation itemizes R1-R42 occurrences across five files, then states "Total: R1-R42 ×20, RT1-RT8 ×2". Direct reproduction confirms the itemized list and live grep count sum to R1-R42 ×18 (RT1-RT8 ×2 is correct).
**Impact**: Undermines the mechanical consistency discipline this PR's own R42 rule preaches. Implementers trusting "×20" may search for phantom occurrences or silently accept the discrepancy, weakening the audit trail and the "recompute, don't trust the prompt" baseline.
**Recommended action**: Correct C9's total line to "R1-R42 ×18, RT1-RT8 ×2" as verified by direct reproduction.
**Evidence**: `grep -rn -oE 'R1-R42|RT1-RT8' skills/triangulate/ | grep -c 'R1-R42'` → 18; per-line reproduction matches itemized list exactly; plan.md:160.
**Perspectives**: Functionality, Testing

**Severity**: Major
**Problem**: R43's verbatim body enumerates boundary-surface widening shapes but omits three classes implied by source lessons: (1) Logging/audit reduction, (2) Timeout/interval extension, (3) Crypto-parameter weakening framed as compatibility fix. These share the exact "fix-round functionality complaint → security-relevant parameter loosened" mechanism R43 targets.
**Impact**: Reviewers pattern-matching R43 will correctly catch frame/broadcast cases but will miss audit-suppression, timeout-widening, or crypto-downgrade "fixes". Incomplete enumeration creates a false sense of coverage and a "not on the list, not R43" loophole.
**Recommended action**: Extend R43's enumeration to explicitly include audit/observability retention, security-relevant timeout/interval values, and crypto/KDF parameter floors/whitelists. Add cross-references to R31(g), R34/R35 Tier-2, interval-jitter obligation, and RS5.
**Evidence**: plan.md lines 29, 172, 220; common-rules.md 252-268, 308, 311, 331.
**Perspectives**: Security

**Severity**: Major
**Problem**: Step 3-5 protocol step 2 requires "explicit user approval recorded in Resolution Status" with no minimum quantification bar. This contrasts with the Anti-Deferral mandatory format (Worst/Likelihood/Cost-to-fix) and item 7 (requires quantification + approval).
**Impact**: Creates an easier path to permanently accept a security-boundary widening than to defer a fix. Orchestrators under time pressure may route through the weaker gate, especially for Critical cases where credentials/secrets are at risk.
**Recommended action**: Add to C6/protocol text that "explicit user approval" for reversing the fail-safe default must follow the same Worst/Likelihood/Cost-to-fix quantification mandated by the Anti-Deferral format.
**Evidence**: plan.md C6/item-7 verbatim; common-rules.md lines 169-186.
**Perspectives**: Security

**Severity**: Major
**Problem**: Item 7 defaults to same-branch fix for "R42-derived members". Firing R42 (especially trigger b) is a judgment call. Orchestrators incentivized to defer can simply not invoke R42, classify the finding as pure functionality, and route through weaker item 4. No forcing function exists before the fork.
**Impact**: Item 7 only adds obligation when the orchestrator already intends to do the right thing. The gaming path replicates the exact same-branch-avoidance failure mode this plan aims to fix.
**Recommended action**: Add a forcing rule: whenever a finding reports a missing/bypassed security control on one instance of a structurally recurring operation, the orchestrator MUST run the R42 structural derivation before deciding between item 4 and item 7. Gate on the structural test, not the self-reported label.
**Evidence**: plan.md item 7 verbatim; common-rules.md line 319 (R42 trigger b).
**Perspectives**: Security

**Severity**: Major
**Problem**: C8's locked schema requires `"file": string` (non-nullable), but Phase-1 finding format has no file/line field. Plan-review findings target plan prose, not source files.
**Impact**: Implementers must invent fillers or violate the locked schema; "malformed index → return-to-expert" becomes mechanically undecidable for Phase-1, undermining C8's mechanical decibility promise across templates.
**Recommended action**: Change `"file": string` to `"file": string|null`. State that Phase-1 findings without a concrete file target use `null` (or plan file path by convention).
**Evidence**: plan.md:152 (schema); phase-1-plan.md:118-125 (finding format).
**Perspectives**: Testing

**Severity**: Major
**Problem**: Anti-Deferral item 7 says "Contrast with item 4", but the current common-rules.md numbered list has item 4 = "Deferred findings must be tracked" (line 167). The intended "out of scope (different feature)" exception is the 4th bullet in a separate unnumbered fenced block (line 184). Items 6/7 append to the numbered list, causing misdirection.
**Impact**: Readers following "Contrast with item 4" land on an unrelated tracking rule, degrading self-containedness and risking misapplication of the carve-out logic.
**Recommended action**: Rename cross-reference to point at the correct anchor (e.g., "Contrast with the 'out of scope (different feature)' exception in the mandatory Skipped/Accepted format block"). Apply to C4 acceptance criteria and plan's C4 "Invariants" line.
**Evidence**: plan.md:122,191; common-rules.md:159-167 (item 4), 184 (format block).
**Perspectives**: Functionality

**Severity**: Minor
**Problem**: C8's signature asserts the findings-index bullet is inherited via "All obligations from Round 1 remain in effect", but the parenthetical only names "(Plan-specific obligations, severity criteria, etc.)" — not "Requirements". Round 2+ has its own Requirements list. Inheritance of the findings-index instruction is non-obvious.
**Impact**: Sub-agents rendering Round 2+ prompts literally may not surface the findings-index instruction.
**Recommended action**: Add the findings-index bullet explicitly to phase-1's Round 2+ Requirements list, or reword the inheritance parenthetical to name Requirements explicitly.
**Evidence**: phase-1-plan.md:176-184; plan.md C8 signature (151) and Considerations (284-286).
**Perspectives**: Functionality

**Severity**: Minor
**Problem**: Item 6 correctly exempts read-only queries from R31, but does not state that the query itself must avoid logging row-level contents of security-state tables, which could trigger logging rules instead of R31.
**Impact**: Low; read-only helpers might implicitly write audit entries leaking row content into logs.
**Recommended action**: Add optional wording: "the measurement query itself must not log row-level contents of security-state tables (count/aggregate only)."
**Evidence**: plan.md item 6 verbatim; common-rules.md line 308.
**Perspectives**: Security

**Severity**: Minor
**Problem**: Item 6's "provisional pending measurement" label doesn't cross-reference Anti-Deferral item 4 (tracking/TODO) or specify that open provisions block the Step 3-8 termination check.
**Impact**: Provisional dispositions could silently survive to commit, effectively acting as untracked deferrals.
**Recommended action**: Add clause: a `provisional pending measurement` disposition must satisfy Anti-Deferral item 4 (TODO marker, tracked) and must not be treated as closed by the termination check.
**Evidence**: plan.md item 6; common-rules.md line 166; phase-3-review.md Step 3-8.
**Perspectives**: Security

**Severity**: Minor
**Problem**: RT9's Critical/Major split lists "security control (origin/frame gate, authz check, sanitizer, crypto parameter)", but RT5's escalation list explicitly includes "rate-limit, RLS, idempotency". RT9 generalizes RT5 but omits these.
**Impact**: Twin-drift gaps in rate limiters or RLS/tenancy predicates would be under-classified as Major.
**Recommended action**: Add "rate limiter, RLS/tenancy predicate" to RT9's parenthetical list to match RT5's Critical-escalation scope.
**Evidence**: plan.md RT9 verbatim; common-rules.md line 342.
**Perspectives**: Security

**Severity**: Minor
**Problem**: C8 schema states `"escalate": boolean|null` with "null for non-security experts". It doesn't specify what Security experts put for non-Critical findings. Ambiguity exists between "not populated by design" vs "no escalation needed".
**Impact**: Mechanical merge pre-pass cannot distinguish between "no escalation needed" and "field not populated".
**Recommended action**: Clarify schema notes: Security entries use `escalate: false` for non-escalated Critical findings, `escalate: null` only for non-Critical findings or non-Security experts.
**Evidence**: plan.md C8 schema; phase-3-review.md lines 195-197.
**Perspectives**: Security

**Severity**: Minor
**Problem**: Testing strategy item 1 hedges with "-style check or visual re-read" for row formatting verification. A concrete mechanical command exists based on 6-field parity.
**Impact**: Low; reduces test determinism and leaves a soft check in a mechanical pipeline.
**Recommended action**: State definitively: `grep '^| R43 \|^| RT9 ' skills/triangulate/common-rules.md | awk -F'|' '{print NF}'` — expect `6` for each row. Drop "or visual re-read".
**Evidence**: `grep '^| R42 ' ... | awk -F'|' '{print NF}'` → 6; plan.md:263.
**Perspectives**: Testing

**Severity**: Minor
**Problem**: Testing strategy item 3 uses `grep -c` to count status lines. This counts matching lines, not occurrences. Correct only due to an unstated one-per-line template precondition.
**Impact**: Low; mechanical criterion becomes fragile if template condensation changes line structure.
**Recommended action**: Note the one-per-line dependency, or switch to `grep -o ... | wc -l`.
**Evidence**: synthetic single-line test yields 1, not 3; plan.md:265.
**Perspectives**: Testing

**Severity**: Minor
**Problem**: C7 adds the boundary-widening bullet only to the phase-3 Round 2+ template. The reasoning (Round 1 baseline = main/pre-branch) is implicit, not stated.
**Impact**: Low; implementers might incorrectly conclude R43 is unchecked in Round 1.
**Recommended action**: Add one sentence to C7 or the R43 verbatim body: Round 1's baseline for "previous state" is main/pre-branch; the Round 2+ bullet exists only for "compare to previous round, not just main" precision.
**Evidence**: plan.md:142-147, 217-221; grep output in phase-3-review.md.
**Perspectives**: Testing

**Severity**: Minor (informational)
**Problem**: Pre-existing RS6/RT8 template staleness is verified real but is correctly scoped by the plan's own declaration + Anti-Deferral changed-file rule.
**Impact**: None; confirmed correct as scoped.
**Recommended action**: No action required.
**Evidence**: common-rules.md:332,345; phase-2-coding.md:401; phase-1-plan.md:261-276; phase-3-review.md:307-322.
**Perspectives**: Functionality

## Recurring Issue Check

### Functionality expert
- R1: N/A — markdown-only skill edit
- R2: N/A — no source constants; skill prose only
- R3: Checked — C9's range-sweep is an R3-style propagation obligation; verified the plan's line-list is complete and accurate (F1 is a summary-count slip, not a missed site)
- R4: N/A — no event dispatch code
- R5: N/A
- R6: N/A
- R7: N/A
- R8: N/A
- R9: N/A
- R10: N/A
- R11: N/A
- R12: N/A — no enum-like registration; RS*/RT* templates checked (F4, correct scope)
- R13: N/A
- R14: N/A
- R15: N/A
- R16: N/A
- R17: N/A — no new shared helper
- R18: Checked — R43's "Distinct from R18" claim verified against R18's actual text — no issue
- R19: Checked — RT9's R19 distinction verified — no issue
- R20: N/A
- R21: N/A
- R22: N/A
- R23: N/A
- R24: N/A
- R25: N/A
- R26: N/A
- R27: N/A
- R28: N/A
- R29: Checked — no external specs cited; abstraction requirement honored throughout — no issue
- R30: Checked — no bare #<n>/@<name> tokens in verbatim bodies — no issue
- R31: Checked — item 6's R31-interaction claim consistent with R31's write-only categories — no issue
- R32: N/A
- R33: N/A
- R34: Checked — no adjacent bug beyond the RS6/RT8 staleness the plan scopes in — no issue
- R35: N/A — config-only, correctly declared
- R36: N/A
- R37: Checked — abstracted language per Forbidden-patterns list — no issue
- R38: Checked — R43's "Distinct from R38" claim accurate — no issue
- R39: N/A
- R40: N/A — C8 schema is flat/typed with return-to-expert fallback
- R41: Checked — SC1 explicitly defers mechanical wiring; declared, not silently unbacked — no issue
- R42: Checked — C9 applies the derivation to itself; independent re-run matches the line list exactly; summary total off by 2 (F1)

### Security expert
- R1: N/A — markdown-only plan, no shared-utility reimplementation surface
- R2: N/A — no hardcoded constants introduced
- R3: N/A — no pattern propagation surface (C9 sweep covers range-token propagation mechanically)
- R4: N/A — no event/mutation dispatch code
- R5: N/A — no DB transactions
- R6: N/A — no cascade deletes
- R7: N/A — no E2E selectors
- R8: N/A — no UI components
- R9: N/A — no async dispatch
- R10: N/A — no module imports
- R11: N/A — no display/subscription grouping
- R12: N/A — no enum/action group registration
- R13: N/A — no event delivery loop
- R14: N/A — no DB roles
- R15: N/A — no migrations
- R16: N/A — no DB privilege tests
- R17: N/A — no new shared helper
- R18: Checked — no issue. R43's "Distinct from" clause correctly separates itself from R18
- R19: N/A — no test mocks
- R20: N/A — no mechanical multi-line code insertion
- R21: N/A — no sub-agent code changes to verify
- R22: N/A — no shared-helper migration
- R23: N/A — no UI input handlers
- R24: N/A — no migrations
- R25: N/A — no persist/hydrate boundary
- R26: N/A — no UI controls
- R27: N/A — no user-facing numeric strings
- R28: N/A — no toggle/switch labels
- R29: N/A — no external spec citations in the new rule bodies
- R30: N/A — no autolink-adjacent handles
- R31: Checked — no issue. Read-only-exempt claim verified correct (see S4 for minor completeness note)
- R32: N/A — no runtime-shape boot artifact
- R33: N/A — no CI config change
- R34: Checked — no issue. Item 7 consistent with R34's security carve-out framing (S3 is about item 7's own gate, not R34 consistency)
- R35: Checked — no issue. No deployment-artifact files touched
- R36: N/A — no warning suppression
- R37: N/A — no user-facing translation strings
- R38: Checked — no issue. R43 distinctness verified against R38's actual text
- R39: Checked — no issue. Different mechanism; no cross-reference needed
- R40: N/A — no cross-boundary serialized payload (json index is orchestrator-internal; see S8 for its one ambiguity)
- R41: N/A — no capability declarations
- R42: Checked — no issue on R42's own text; item 7's use of R42-derivation as a gate has a gaming loophole (S3)
- R43: Checked — Major findings raised (S1: enumeration completeness gap; S2: approval-bar inconsistency)
- RS1: N/A — no timing-safe comparison code
- RS2: N/A — no new API routes
- RS3: N/A — no request parameter validation
- RS4: N/A — no personal-identifying data in the plan text (checked: no real emails/handles/hostnames found)
- RS5: Checked — flagged as a missing cross-reference in R43's "Distinct from" clause (S1, item 3)
- RS6: N/A — no escape-character sanitization code

### Testing expert
- R1: N/A
- R2: N/A
- R3: N/A
- R4: N/A
- R5: N/A
- R6: N/A
- R7: N/A
- R8: N/A
- R9: N/A
- R10: N/A
- R11: N/A
- R12: N/A
- R13: N/A
- R14: N/A
- R15: N/A
- R16: N/A
- R17: N/A
- R18: N/A
- R19: Checked — no issue (verified R19's text to confirm C2's cross-reference claim; R19 does not backstop RT9's gap)
- R20: N/A
- R21: N/A
- R22: N/A
- R23: N/A
- R24: N/A
- R25: N/A
- R26: N/A
- R27: N/A
- R28: N/A
- R29: N/A
- R30: N/A
- R31: N/A
- R32: N/A
- R33: N/A
- R34: N/A
- R35: N/A
- R36: N/A
- R37: N/A
- R38: N/A
- R39: N/A
- R40: N/A
- R41: N/A
- R42: Checked — Finding T1 (C9's member-set arithmetic internally inconsistent — the total, not the itemized list)
- RT1: N/A
- RT2: N/A
- RT3: N/A
- RT4: Checked — no issue (RT9's vacuous-family framing consistent with RT4)
- RT5: Checked — no issue (RT9/RT5 boundary non-redundant, T7)
- RT6: N/A
- RT7: Checked — no issue (RT9's "red-proven per RT7" cross-reference consistent)
- RT8: Checked — no issue (RT9's vacuous-family framing consistent with RT8)

## Quality Warnings
No findings flagged for quality gates. All merged findings contain specific file/line references, concrete recommended actions, and mechanical or textual evidence. No vague phrasing, unsupported claims, or untestable recommendations were detected.

## Resolution Status — Round 1

All Round-1 findings were accepted and reflected in the plan file before Round 2:

- F1/T1 (Major, convergent: functionality+testing) — C9 total corrected to "R1-R42 ×18, RT1-RT8 ×2".
- S1 (Major) — R43 enumeration extended with audit/observability emission-or-retention, security-relevant timeout/interval values, crypto/KDF floors & algorithm whitelists; "not a closed list" clause added; RS5 added to the Distinct-from clause.
- S2 (Major) — Step 3-5 protocol step 2 now requires the Anti-Deferral Worst case / Likelihood / Cost-to-fix quantification on the approval entry ("bare 'user approved' is invalid").
- S3 (Major) — item 7 now gates on R42's structural test, with derivation-before-classification forcing rule ("we didn't invoke R42" is not an exemption).
- F2 (Major) — item 7 and C4 cross-references renamed from "item 4" to the "out of scope (different feature)" exception of the Skipped/Accepted format block.
- T2 (Major) — C8 schema `file` is now `string|null` with Phase-1 null convention documented.
- S4 (Minor) — item 6 adds "count/aggregate only; must not select/echo/log row-level contents of security-state tables".
- S5 (Minor) — item 6 provisional disposition now requires an item-4 grep-able TODO marker and blocks the termination check's "No findings" stop.
- S6 (Minor) — RT9 severity parenthetical extended with rate limiter, RLS/tenancy predicate (matches RT5's escalation list).
- S8 (Adjacent → C8) — escalate null-vs-false semantics defined (false = assessed-not-escalated Critical; null = not applicable).
- T3 (Minor) — Testing strategy item 1 replaced with the definitive awk field-count command (expect 6).
- T4 (Minor) — Testing strategy item 3 rewritten as per-pattern per-file checks independent of line layout.
- T5 (Minor) — Round-1 baseline sentence added to R43 Reviewer action and C7 acceptance criteria.
- F3 (Minor) — C8 now adds the findings-index bullet explicitly to all four templates (no inheritance reliance).
- F4 (Minor, informational) — no action required; RS6/RT8 staleness bundling confirmed correctly scoped.

---

# Plan Review: triangulate-r43-rt9-failsafe-lessons
Date: 2026-07-11
Review round: 2

## Changes from Previous Round
All 15 Round-1 findings reflected in the plan (see Round-1 Resolution Status): R43 enumeration extended + Round-1 baseline, tradeoff-protocol approval quantification, item 7 structural-test gate, item 6 measurement hygiene + provisional tracking, C8 schema null semantics + four explicit template placements, C9 count correction, testing-strategy command rewrites, cross-reference renames.

## Functionality Findings
## Functionality Review R2 — all Round-1 fixes re-verified independently; 1 new Minor.

**F5 (Minor, new in round 2)** — Stale `(all 20)` parenthetical in the C9 Replacements bullet contradicts the corrected ×18 count two lines above and Testing-strategy item 2's baseline. The F1/T1 fix corrected two of three sibling occurrences. Acceptance criterion (zero-hits grep) is count-agnostic so no functional risk, but the internal contradiction is a defect in an otherwise exactly-verified contract block.
Fix: `(all 20)` → `(all 18)` on plan line 161.

Verified fixed (independently re-run): F1/T1 (grep → 18/2 exact), S1 (R43 row single line, 6 awk fields, RS5 in Distinct-from, not-a-closed-list clause), S2 (quantification required, bare approval invalid), S3 (derivation-before-classification unambiguous), F2 (remaining "item 4" references verified correct: C4's disambiguation + item 6's genuine item-4 tracking reference), T2 (file nullable, identical in schema and bullet), S4/S5 (verified against real termination-check text phase-1:321 / phase-3:424), S6, S8 (escalate semantics verbatim-match schema↔bullet), T3/T4 (commands definitive, correct baselines), T5 (verbatim-consistent in both locations), F3 (ALL FOUR templates explicit; phase-3 R2+ confirmed to lack inheritance sentence).
No forbidden-pattern token leakage (allFrames / passwd-sso / -lib.ts / ?raw / kdfType / pending-save / webNavigation appear only inside their Forbidden-patterns declarations).

## Recurring Issue Check (Functionality, R2)
- R1-R2: N/A
- R3: N/A — C9 derivation is R42-flavored, not R3
- R4-R28: N/A
- R29: N/A — no external-standard citations
- R30: N/A
- R31: N/A
- R32-R41: N/A
- R42: Checked — independently re-ran C9 member-set grep, 18/2 exact match to claimed line numbers; caught incomplete propagation of the count fix (F5)

## Security Findings
## Security Review R2 — verified all Round-1 fixes close their loopholes without new ones. No Critical.

**S9 (Minor, new in round 2)** — "Common Security logging obligations" is an unresolvable in-skill cross-reference.
Item 6 (C3) reads "(see Common Security logging obligations)" — zero hits in skills/triangulate/. The real content lives in ~/.claude/rules/common/security.md (a non-triangulate rules file expert sub-agents never receive). Operative constraint is already in-line, so this is citation hygiene (same family R29 polices).
Fix: make self-contained — drop the parenthetical or replace with "— never echo row-level values of security-state tables (sessions, tokens, credential/permission rows), consistent with standard secret-logging hygiene".

**S10 (Minor, new in round 2)** — RT9's "same scope as RT5's escalation list" is a paraphrase, not a verbatim match.
RT5's list: "auth, authz, rate-limit, signature verification, RLS, idempotency on a security-state mutation". RT9's: "origin/frame gate, authz check, sanitizer, crypto parameter, rate limiter, RLS/tenancy predicate — same scope as RT5's escalation list" (adds origin/frame gate + sanitizer, drops signature verification + idempotency). Not a threat-model error; a precision gap in a load-bearing cross-reference.
Fix: reword to "superset of RT5's escalation list" or align the wording.

Escalate: not applicable (no Critical).

## Recurring Issue Check (Security, R2)
- R1-R17: N/A
- R18: Checked — R43 Distinct-from R18 correct
- R19: Checked — RT9's R19 note consistent
- R20-R28: N/A
- R29: Checked — R31(g), RS5 cross-refs verbatim-consistent; RT5 cross-ref loose paraphrase (S10); "Common Security logging obligations" unresolvable in-skill (S9)
- R30: N/A
- R31: Checked — R43 audit clause matches R31 category (g), no drift
- R32-R41: N/A (R38 Checked — Distinct-from correct)
- R42: Checked — item 7's trigger-(b)/derivation references consistent with R42's actual text
- RS1-RS4: N/A
- RS5: Checked — Distinct-from RS5 logically sound (external-untrusted vs internal-deliberate)
- RS6: N/A
- RT5: Checked — generalization claim accurate; escalation-list wording paraphrase (S10)

## Testing Findings
## Testing Review R2 — all Round-1 fixes verified (commands re-run); 1 new Minor.

**T11 (Minor, new in round 2)**: Stale risk-note contradicts C8's fixed "no inheritance" rule.
plan.md:286 ("Risk: phase-1 Round 2+ template does not restate Requirements bullets") still says the findings-index bullet "is inherited there" for phase-1 Round 2+ — contradicting C8's signature/acceptance ("each template gets its own copy", "no inheritance reliance") and Edit-targets. Round-1-era leftover; could mislead the Phase-2 implementer into skipping the phase-1 Round 2+ bullet.
Fix: rewrite the paragraph as a non-issue note: inheritance is NOT relied upon; all four locations get explicit copies. Verify post-fix: `grep -c 'inherited there' plan.md` → 0.

Verification summary (all pass):
- T1: grep recount → 18, matches plan. T2: schema nullable + null semantics consistent across all three locations; mechanically decidable. T3: awk field-count command proxy-tested on R42/RT8 rows (NF=6). T4: six grep -cF checks correct (pre-edit 0 as expected). T5: baseline sentence in both locations.
- S1 side effect: R43 row still one physical line, 6 awk fields. F2: no stale renames. F3: four placements consistent everywhere except the stale line 286 (T11). S8/T2: schema/bullet/pre-pass mutually consistent.
- Anchor uniqueness re-verified for ALL "Before (verbatim)" strings + insertion anchors (footer, bracket line, R42 row, RT8 row, item 5, Handling [Adjacent] heading, phase-3 "Important rules", RS5/RT7 template lines, R42 template line): all exactly 1 hit.

## Recurring Issue Check (Testing, R2)
- R1-R41: N/A
- R42: Checked — C9 derivation correct incl. clause ③ indirect members
- RT1-RT4: N/A
- RT5: Checked — RT9 distinction correct
- RT6: N/A
- RT7: Checked — "red-proven per RT7" resolves with matching semantics
- RT8: N/A

## Adjacent Findings
None in Round 2.

## Quality Warnings
None — all four Round-2 findings carry file/line evidence and concrete fixes (manual merge; Ollama merge skipped for a 4-finding round, per orchestrator fallback rules).

## Resolution Status — Round 2

- F5 (Minor) — `(all 20)` → `(all 18)` applied. Verified: `grep -c 'all 20'` → 0.
- S9 (Minor) — item 6 parenthetical made self-contained ("sessions, tokens, credential/permission rows — standard secret-logging hygiene"). Verified: dangling reference gone.
- S10 (Minor) — RT9 severity cell reworded to "a superset of RT5's Critical-escalation list". Verified.
- T11 (Minor) — stale inheritance risk-note rewritten as "Non-issue: phase-1 Round 2+ template inheritance is not relied upon". Verified: `grep -c 'inherited there'` → 0.

---

# Plan Review: triangulate-r43-rt9-failsafe-lessons
Date: 2026-07-11
Review round: 3 (+ single-item round 4 verification)

## Changes from Previous Round
Round-2 fixes applied: F5 (all 20 → all 18), S9 (item 6 self-contained wording), S10 (RT9 superset rewording), T11 (Non-issue paragraph rewrite).

## Functionality Findings
## Functionality Review R3 — No findings.

Residual-occurrence sweep of all four fixed strings: zero hits, replacements present exactly once each. R42 recount: 18/2 consistent across all three citation sites. C9 block and Considerations section coherent end-to-end.

## Security Findings
## Security Review R3/R4 — S9 RESOLVED; S10 reopened as S11 (Minor), fixed and verified; no open findings.

**S11 (Minor, new in round 3, RESOLVED in round 4)**: "a superset of RT5's Critical-escalation list" was still factually wrong after the Round-2 rewording — RT9's list lacked "signature verification" and "idempotency on a security-state mutation". Fixed per option (b): both categories added to RT9's enumeration ("auth/authz check, origin/frame gate, sanitizer, crypto parameter, signature verification, rate limiter, RLS/tenancy predicate, idempotency guard on a security-state mutation"). Round-4 element-by-element verification: all six RT5 elements covered, three additions on top — the superset claim is now literally true. Additions only widen the Critical trigger (fail-safe direction). Escalate: false.
F5/T11: no security side effects (non-normative prose edits).

### Recurring Issue Check (Security, R3/R4)
- R29 (cross-reference accuracy): re-checked — S11 initially failed verbatim comparison, passes element-by-element after fix.
- All other rules: N/A — unchanged since Round 2.

## Testing Findings
## Testing Review R3 — No findings.

All four mechanical scope items verified: inherited-there 0; all-20 0 with three count sites consistent at 18; no stale siblings (the single "20" hit is the intentional historical narration); R43/RT9 rows still 6 awk fields; items 6/7 block intact.

## Adjacent Findings
None.

## Quality Warnings
None (manual merge — 1-finding round).

## Resolution Status — Round 3/4

- S11 (Minor) — RT9 severity-cell list extended with auth, signature verification, idempotency guard; superset claim now literally true. Verified by the originating security expert (element-by-element) and mechanically (RT9 row still parses as 6 awk fields).

## Convergence
Round 3: Functionality "No findings", Testing "No findings", Security S11 only → fixed → Round 4 single-item verification by the originating expert: "S11 RESOLVED", no S12. All experts at zero open findings. Phase 1 converged in 3 rounds (+1 single-item verification pass). Go/No-Go gate: C1-C9 all locked.
