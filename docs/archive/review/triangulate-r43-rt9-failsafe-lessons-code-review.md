# Code Review: triangulate-r43-rt9-failsafe-lessons
Date: 2026-07-11
Review round: 1 (inline fallback)

## Review-mode note (objectivity disclosure)

All three Step 2-5 mini sub-agents and the Phase 3 expert sub-agents were unavailable (session limit). Per Common Rules "When Sub-agents Are Unavailable", the three perspectives were processed sequentially INLINE by the orchestrator — evaluation objectivity is reduced relative to independent sub-agents. Independent inputs that did run: local-LLM code pre-screening (`pre-review.sh code` → "No issues found") and the full mechanical verification battery below. A follow-up independent 3-agent review round after the session-limit reset is recommended before merge if additional assurance is desired.

## Changes from Previous Round
Initial review of the implementation diff (2 commits: plan artifacts; C1-C9 skill edits).

## Verification battery (all pass)

- Contract conformance: 11/11 verbatim bodies byte-identical between the locked plan and the implemented skill text (R43 row, RT9 row, items 6/7, footer, R43 template line, Round 2+ bullet, Perspective Convergence subsection, Step 3-5 protocol, findings-index bullet — 4 copies identical, merge pre-pass — 2 copies identical).
- Range sweep: zero `R1-R42` / `RT1-RT8` stragglers in skills/triangulate/; all 18 bumped sites read correctly in context.
- Template registration: RS6/RT8/RT9 status lines present exactly once in each phase file; R43 present in rule table AND Recurring Issue Check template; bracket line reads RS1-RS6 / RT1-RT9.
- Table integrity: R43 and RT9 rows parse as exactly 6 awk pipe-fields.
- Forbidden patterns: clean (allFrames / passwd-sso / -lib.ts / ?raw / webNavigation / kdfType / pending-save absent from skill diff).
- Autolink/personal-data grep on added lines: clean (R30/RS4).
- Full bats suite: 548/548. Deployment parity: `diff -q` clean ×5 files. Local-LLM pre-screen: No issues found.

## Functionality Findings
No findings. (Inline pass: replace_all contexts verified line-by-line; duplicated blocks byte-identical; no cross-file inconsistency.)

## Security Findings
No findings. (Inline pass: implemented text matches the security-hardened plan verbatim — the plan's own 3-round review covered enumeration completeness, approval-bar quantification, derivation-before-classification, and citation accuracy. No mangling introduced at implementation.)

## Testing Findings
No findings. (Inline pass: all plan Testing-strategy commands re-run and pass; acceptance criteria red-capable — the range-sweep grep and the six template greps fail on the pre-edit tree.)

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check
### All perspectives (inline; compact — full per-rule status recorded in the plan-review file for Rounds 1-3)
- R1-R28: N/A — markdown-only skill edit; no code surfaces
- R29: Checked — internal cross-references in new text verified during plan Rounds 2-3 (R31(g), RS5, RT5 superset element-by-element, item-4 tracking reference); implementation is verbatim, so verification carries over
- R30: Checked — no autolink-prone tokens on added lines
- R31: N/A — no destructive operations (read-only greps + install.sh copy)
- R32-R41: N/A
- R42: Checked — C9 member-set (18/2) re-derived post-implementation: zero residual
- R43: N/A — first round; no prior-round fixes to widen (baseline = main)
- RS1-RS6: N/A except RS4 — Checked, no personal data in artifacts
- RT1-RT8: N/A except RT7 — Checked: acceptance checks demonstrated red-capable (fail on pre-edit tree)
- RT9: N/A — no parallel implementation (single-source markdown, install.sh copies)

## Resolution Status

### PRE1 Minor: 4 pre-existing rule rows (R30, RS3, RS6, RT6) contain unescaped `|` inside backticked code spans (awk NF!=6) — Accepted
- **Anti-Deferral check**: acceptable risk (pre-existing in changed file — flagged, not silently skipped)
- **Justification**:
  - Worst case: GitHub's rendered view splits those 4 rows' cells oddly; the primary consumer (Claude reading raw markdown at runtime) is unaffected, and escaping to `\|` would corrupt the literal regexes those rules instruct copying.
  - Likelihood: low impact — rendering-only; rows have shipped through many PRs in this state.
  - Cost to fix: touching 4 dense regex-bearing rows risks changing rule semantics for a cosmetic gain; > 30 min with verification, and the fix direction (escape vs HTML entity vs restructure) needs its own design decision.
- **Tracking**: TODO(triangulate-r43-rt9-failsafe-lessons): decide pipe-escaping policy for regex-bearing rule rows (R30, RS3, RS6, RT6).
- **Orchestrator sign-off**: acceptable-risk exception satisfied with the three values above.

## Termination
Round 1: No findings from any perspective (inline). Tightening-only skip not needed. Loop ends.

---

# Code Review: triangulate-r43-rt9-failsafe-lessons
Date: 2026-07-11
Review round: 2 (external adversarial security review)

## Changes from Previous Round
External security review of the branch raised one Critical finding against the Round-1 state; no other findings; `git diff --check` clean.

## Security Findings

### SX1 Critical: recipient-side verification treated as a confidentiality boundary for privileged payloads — FIXED
- File: skills/triangulate/phases/phase-3-review.md (Step 3-5 protocol step 1); docs/archive/review/triangulate-r43-rt9-failsafe-lessons-plan.md (C6 verbatim, C6 acceptance, Scenario 1, L2 narrative)
- Problem: the protocol's illustrative both-satisfying moves listed "enforce the gate at the consumer side" generically. For confidential payloads this is not a confidentiality boundary: the recipient controls the verification code, and the secret has already crossed the boundary on delivery. An orchestrator could approve exactly the R43-Critical widening as a "both-satisfying design".
- Root cause: over-generalization of the source session's special case, where the receiving code was the platform-injected TRUSTED code of the producer itself (isolated-world content script) — a trusted-endpoint condition the generic example silently dropped.
- Fix applied: (1) replaced the first move with producer-side recipient authentication before delivery; (2) added an explicit anti-example clause — "For confidential payloads, verification AFTER delivery is NOT a both-satisfying design ... a design whose only gate runs on the recipient is the R43 widening itself"; recipient-side checks demoted to defense-in-depth admissible only for producer-owned trusted endpoints with non-exposing transport; (3) Scenario 1 and the L2 narrative updated to producer-side verification; (4) C6 acceptance criteria updated.
- Verification: plan-vs-implementation conformance diff MATCH; zero residual "consumer-side" tokens in skill files; install parity ×5 OK.
- R43 Round-2+ self-check on this fix: the change NARROWS guidance (removes a widening-sanctioning example) — no boundary predicate widened versus Round 1.

## Resolution Status — Round 2
- SX1 (Critical) — Fixed as above. Contract C6 was amended post-lock (material change to its acceptance criteria); per Go/No-Go rules it flipped to pending and is re-locked with this round's verification.

## Termination
Round 2: single Critical from external review, fixed and verified; external reviewer reported no other findings. Loop ends pending any further external re-review.
