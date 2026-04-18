# Code Review: add-r23-r28-runtime-obligations
Date: 2026-04-18
Review rounds: 3 (Round 1 findings → Round 2 findings on fixes → Round 3 termination)
Branch: refactor/add-r23-r28-and-runtime-obligations

## Scope

In-place review of working-tree changes to `skills/multi-agent-review/SKILL.md` in response to user feedback adding:
- R23-R28 to the Known Recurring Issue Checklist
- Enhancements to R3 (flagged-instance enumeration) and R19 (exact-shape assertion)
- New Expert Agent Obligation: "Check runtime environment constraints against security-relevant minimum values"
- Additions to Step 2-4 (Implementation Completion Check) and Step 3-3 (cross-cutting verification)

No plan / deviation log (direct editing in response to feedback). Project context: `config-only`, test infrastructure `none` — per project-context obligation, all test/CI-framework recommendations were downgraded to Minor.

The user's original feedback contained many language/framework-specific identifiers (React/Tailwind/Chrome MV3/Prisma/Jest/Vitest/Japanese grammar examples). These were abstracted before insertion per the established policy in memory `feedback_no_lang_repo_specifics.md`.

## Round 1 (15 findings: 2 Major, 13 Minor)

### Functionality (4 Minor)
- F1: R19 template stub label missed "Exact-shape assertion obligation"
- F2: R3 template stub missed "Flagged-instance enumeration obligation"
- F3: Step 3-3 omitted R26 bullet alongside R23/R28
- F4: runtime-constraint "typically single-digit minutes" was a hedge, not a procedural trigger

### Security (2 Major + 3 Minor, no Critical)
- S1 (Minor): runtime-constraint treated fail-open and fail-closed symmetrically
- S2 (Major, convergent with T2): R24 missed authz-bypass window for tenancy/identity fields
- S3 (Major, convergent with T1): R25 missed security-sensitive field class callout
- S6 (Minor): R23 lacked security angle for security-relevant numeric inputs
- S7 (Minor): R27 severity undersold drift for security-governing constants

### Testing (2 Major + 7 Minor)
- T1 (Major, convergent with S3): R25 missed round-trip test obligation
- T2 (Major, convergent with S2): R24 missed intermediate-state test obligation
- T3 (Minor): R19 "equal/deep-equal" abstraction not mechanically identifiable
- T4 (Minor): R27 over-flagged version/year/HTTP-code literals
- T5 (Minor): R28 didn't state it's primarily a human-review item
- T6 (Minor): R26 lacked Check-column procedure
- T7 (Minor): R21 vs runtime-constraints interaction undefined
- T8 (Minor): "Flag Major even if within spec" read as general precedent
- T9 (Minor): Step 2-4 prose blocks lacked MANUAL CHECK prefix

## Round 2 (new findings on fixes: 3 Major, 6 Minor)

### Functionality (2 Minor)
- F5: R19 Extended section not updated to reflect the new exact-shape obligation
- F6: mid-band decision tier's "empirical test" ambiguous on fake timers

### Security (3 Major + 2 Minor)
- S8 (Major): dormancy "window" is a distribution with a tail — 3× threshold can still miss under tail conditions
- S9 (Major, convergent with T12): R24 "realistic load" doesn't require concurrent writers crossing the migration boundary
- S10 (Minor, convergent with T11): R25 "simulate restart" could mean same-process reinstantiation
- S11 (Major): R27 escalation list too narrow — missed consent, retention, audit thresholds, MFA-grace, lockout, key-rotation
- S12 (Minor accepted): MANUAL CHECK comments have no CI enforcement (inherent in config-only context)

### Testing (5 Minor)
- T10 (Minor accepted): R19 spelling list non-exhaustive ("common spellings" framing acceptable)
- T11 (Minor, convergent with S10): R25 "simulate restart" underspecified
- T12 (Minor, convergent with S9): R24 "realistic load" not grep-able
- T13 (Minor): MANUAL CHECK prefix lacked visual separator from regular bash block
- T14 (Minor): R24/R25 MANUAL CHECK wording diverged from table-row wording

## Round 3 (Termination)

All three perspectives reported "No findings". Loop terminates.

## Resolution Status

### F1-F4 [Minor] — RESOLVED (Round 1)
- F1: template stub now reads "R19 (Test mock alignment + Exact-shape assertion obligation)"
- F2: template stub now reads "R3 (Pattern propagation + Flagged-instance enumeration)"
- F3: Step 3-3 now includes "Disabled-state visible cue check (R26)" bullet alongside R23/R28
- F4: replaced hedge with explicit decision procedure (≤1× dormancy → Major; 1-3× → Minor + empirical test; ≥3× → no finding)

### S1-S7 [Minor to Major] — RESOLVED (Round 1)
- S1: added "Fail-open is the materially worse direction" paragraph
- S2 (convergent with T2): R24 row now has **Security angle** naming tenant_id/role/owner_id class + **Testing obligation**
- S3 (convergent with T1): R25 row now has **Security angle** (tokens/revocation/encryption material/consent/audit) + **Testing obligation** (round-trip)
- S6: R23 row now has **Security angle** for security-relevant numeric inputs
- S7: R27 row now has severity escalation clause + Severity column changed to "Minor (Major when constant governs a security policy boundary)"

### T1-T9 [Minor to Major] — RESOLVED (Round 1)
- T1 (via S3): round-trip test obligation added to R25
- T2 (via S2): intermediate-state test obligation added to R24
- T3: R19 wording now lists "common spellings across frameworks" with 5+ illustrative examples
- T4: R27 now excludes "year literals, HTTP status codes, version numbers"
- T5: R28 now states "this is primarily a human-review check"
- T6: R26 now has "grep for controls with disabled/readonly attributes and verify each one has a paired disabled-state style rule"
- T7: runtime-constraints obligation now has "Interaction with R21" paragraph
- T8: "Flag Major even if within spec" now scoped: "applies specifically to security-relevant interval minimums against runtime jitter; it is not a general license to override spec compliance elsewhere"
- T9: Step 2-4 comments now use `# MANUAL CHECK —` prefix

### F5-F6 [Minor] — RESOLVED (Round 2)
- F5: R19 Extended section now has "Exact-shape assertion obligation (companion to the above)" paragraph with the full framework-spelling list
- F6: mid-band tier now reads "against the actual runtime (real wall-clock, NOT fake timers / simulated time)"

### S8-S11 [Major/Minor] — RESOLVED (Round 2)
- S8: added "dormancy window is a distribution with a tail" caveat + use p99 or worst observed + fallback when tail is unbounded
- S9 (convergent with T12): R24 now reads "CONCURRENT writers including at least one caller that has NOT yet been updated to use the new field"
- S10 (convergent with T11): R25 now reads "crosses a TRUE process / worker / container boundary (new process, cold worker, restarted container) — NOT a same-process in-memory reinstantiation"
- S11: R27 escalation now covers "ANY security or privacy policy boundary" with 11 example categories

### T13-T14 [Minor] — RESOLVED (Round 2)
- T13: added `##### MANUAL CHECKS (not runnable commands — review obligations) #####` header and `##### END MANUAL CHECKS #####` footer
- T14: MANUAL CHECK wording aligned with table-row wording

### S12 [Minor] — ACCEPTED (Round 2)
- **Anti-Deferral check**: acceptable risk.
- **Worst case**: a manual-check comment in a bash block is easy to overlook because it's not runnable.
- **Likelihood**: medium — reviewers running `pre-pr` without reading the block miss it.
- **Cost to fix**: adding CI enforcement for manual checks requires a linter/pre-commit hook implementation, exceeding the 30-minute rule AND outside the scope of this rule-definition PR (this is a documentation change, not a CI-infrastructure PR). Mitigated by R13-style clear section markers (added) and by the skill's overall "read every step" obligation.
- **Orchestrator sign-off**: acceptance satisfied; mitigated by MANUAL CHECK section markers added in T13 resolution.

### T10 [Minor] — ACCEPTED (Round 2)
- **Anti-Deferral check**: acceptable risk.
- **Worst case**: a reviewer using a framework whose equality primitive is not on the list fails to grep for it.
- **Likelihood**: low — the phrase "common spellings across frameworks" explicitly marks the list as non-exhaustive, and the R19 Extended section was expanded with `assertEquals`, `assert_eq!` etc. covering most common stacks.
- **Cost to fix**: enumerating every framework's equality primitive is unmaintainable and re-leaks stack specifics. Current "common spellings" framing is the intended tradeoff.
- **Orchestrator sign-off**: acceptance satisfied; framing is by design.

## Recurring Issue Check (cross-round summary)

### Functionality expert
- R1-R8: N/A — no shared utility / constant / pattern / event / DB / cascade / E2E / UI changes in the diff itself
- R9-R16: N/A — no async dispatch / circular imports / group/subscription / audit actions / re-entrant dispatch / DB role grants / migrations / CI-role tests in this doc-only diff
- R17 (Helper adoption): N/A — no shared helper introduced
- R18 (Allowlist sync): N/A — no privileged-op file changes
- R19 (Test mock alignment + Exact-shape): N/A — no mocks in diff
- R20 (Multi-statement preservation): N/A — edits were direct, not mechanical
- R21 (Subagent verification): Checked — sub-agent outputs verified by re-reading cited line ranges across rounds
- R22 (Perspective inversion): N/A — no helper introduced
- R23-R28 (new rules): N/A — these rules check for UI inputs / migrations / persist / disabled-state / strings / toggles, none in this doc diff

### Security expert
- R1-R28: as above
- RS1-RS3: N/A — no credential comparison / new routes / new request parameters

### Testing expert
- R1-R28: as above
- RT1-RT3: N/A — no test files modified

## Verification

- Abstraction sanity check: grep against the 20-term blocklist (Prisma/Tailwind/chrome.*/MV3/Vitest/Jest/__mocks__/toEqual/Math.min/parseInt/onChange/.tsx/.jsx/React./Auth.js/HKDF/BYPASSRLS/SUPERUSER/disabled:opacity/<Switch>/<Toggle>/messages/**/npx eslint) returned zero hits.
- R1-R22 → R1-R28 reference propagation: all 7+ occurrences updated.
- Lint / Test / Production build: N/A — config-only repo, no toolchain.
- E2E impact: N/A — no UI/route/selector changes.
- Pre-existing-in-changed-file rule: no pre-existing issues surfaced in this round.

## Next Steps

1. Commit on branch `refactor/add-r23-r28-and-runtime-obligations`.
2. Reinstall via `bash install.sh` after commit so the running copy matches.
3. Push + PR targeting main.
