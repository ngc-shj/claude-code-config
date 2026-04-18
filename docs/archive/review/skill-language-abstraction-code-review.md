# Code Review: skill-language-abstraction
Date: 2026-04-18
Review rounds: 4 (Round 1 + Round 2 + Round 3 + Round 4 termination)

## Scope

In-place review of the working-tree changes to:
- `skills/multi-agent-review/SKILL.md`
- `skills/simplify/SKILL.md`
- `skills/test-gen/SKILL.md`

No plan or deviation log: this work was direct editing (not plan-driven). The diff applies two layers of change: (1) added new content from session learnings (R17-R22 in multi-agent-review; "Analysis Obligations" + "Defer is dead phrase" sections in simplify), then (2) abstracted away language/framework/repo-specific identifiers from those additions AND from pre-existing content.

Project context: `config-only`, test infrastructure `none`. Per project context obligation, automated-test/CI-related Major/Critical findings were downgraded to Minor only.

Branch state at review: `main` (skill rule "No Commits to main" applies — branching needed before commit).

## Round 1 Findings (15 actionable + 1 deferred)

### Functionality (6)
- F1 (Major): R20 Recurring Issue Check template label "Multi-line import preservation" narrowed the rule defined as "Multi-statement preservation in mechanical edits".
- F2 (Major): simplify Step 3 prompt referenced removed section name "CLI/separate-package drift" (current name: "Parallel-implementation drift check").
- F3 (Minor): simplify "Defer is dead phrase" had two thresholds (`<30-min` vs `15 minutes`).
- F4 (Minor): en-dash `R17–R22` vs ASCII `R1-R22` elsewhere — grep-searchability.
- F5 (Minor): `<file already in this diff>` used angle brackets while other placeholders use `[brackets]`.
- F6 (Minor pre-existing): R5 row used `findMany` (JS-ORM identifier) — left behind by abstraction pass.

### Security (4, all Minor — no Critical, no escalation)
- S1: R21 lacked security-specific re-verification clause for auth/crypto/input-validation/permission-grant changes.
- S2: R18 "Remove (or narrow) entries" wording could authorize blast-radius widening.
- S3: Pre-existing prompt-injection surface in skill prompts (`[Plan contents]` / `[Code contents]` / `[Deviation log contents]` / `[Local LLM output]` interpolation without delimiter fencing).
- S4: simplify "Defer is dead phrase" lacked the security carve-out that multi-agent-review's 30-minute rule has.

### Testing (7)
- T1 (Major): R19 row contained `__mocks__` (Jest-specific filesystem convention).
- T2 (Major): R20 had no concrete grep pattern.
- T3 (Major): R21 said "the relevant test suite" without definition; 50+-files step omitted tests from the re-run list.
- T4 (Minor): Storage-backend schema verification (Step 2-1 #6) lost concrete catalog pointer after abstraction.
- T5 (Minor, duplicate of F1): R20 template label.
- T6 (Minor): R21 output template said "Verified" while every other R-rule used "Checked".
- T7 (Minor): R19 Extended described two mock structural shapes but had no failure-mode signal.

## Round 2 Findings (13 new Minor — all resolved or accepted)

### Functionality (4)
- F7: R20 row introduced JS-flavored regex examples (`^import {$`, `^switch (.*) {$`) violating the abstraction policy that drove this refactor.
- F8: Three security carve-outs drifted in their surface list (R21 row, R21 Extended, simplify Defer).
- F9: R21 row omitted "AND complete impact analysis (R3 propagation check)" present in R21 Extended.
- F10: simplify Step 3 prompt wording diverged from the "Parallel-implementation drift check" heading.

### Security (5)
- S5 (initially Major in Round 2; demoted to Minor on alignment): R21 table row vs Extended divergence on impact analysis — duplicate of F9.
- S6: R18 "auditable" too weak; should specify "on the allowlist or behind a higher-privilege gate".
- S7: R20's new backticked regex content marginally widened the pre-existing S3 prompt-injection surface.
- S8: simplify "Security carve-out" impact-analysis phrasing drifted from multi-agent-review's "R3 propagation check".
- S9 (informational): R9/R14/R16 abstraction reduced reviewer greppability — accepted as inherent tradeoff.
- S10 (informational): Anti-Deferral example sanitization confirmed.

### Testing (6)
- T8: R20 examples are JS/brace-family-only — duplicate of F7 / S7.
- T9: R21 Extended #4 (security carve-out) disrupted 1-2-3 procedural flow.
- T10: R19 step #3 used "exercises" — sentence's own failure-mode named "asserting test".
- T11: Storage-backend four-engine list slightly dilutive.
- T12: R5 row omitted test-observability angle (mocked tests pass vacuously).
- T13 (duplicate of S5): R21 row vs Extended divergence.

## Round 3 Findings (6 new Minor)

### Functionality (3)
- F11: R21 Extended callout said "complete impact analysis (R3 propagation check — ...)" while R21 row and simplify Defer used "complete the R3 propagation check (...)" — minor surface drift.
- F12: R21 Extended callout missing blank line separator from list step 3 (Markdown render fold-in).
- F13: R5 row's mocked-test caveat reads as testing-only content placed in "all experts" — testing expert (T15) scoped it as appropriate cross-role.

### Security (3 — all Minor or informational)
- S11: simplify cross-skill reference hardcoded `skills/multi-agent-review/SKILL.md` — fragile pointer.
- S12 (informational): S9 acceptance reaffirmed.
- S13 (informational): R14 severity ladder explicit.

### Testing (3)
- T14: same as F12 — Markdown blank-line issue.
- T15 (informational): R5 placement appropriate cross-role (overrules F13).
- T16 (informational): R19 step 3 concrete enough.

## Round 4 (Termination Check)

All three perspectives reported "No findings". Loop terminates.

## Resolution Status

### F1 [Major] R20 template label narrowed the rule — RESOLVED (Round 1)
- Action: Updated Recurring Issue Check template entry from "Multi-line import preservation" to "Multi-statement preservation in mechanical edits".
- Modified: `skills/multi-agent-review/SKILL.md` (Recurring Issue Check output template, R20 line).

### F2 [Major] simplify Step 3 prompt referenced removed section name — RESOLVED (Round 1)
- Action: Updated the prompt text to "parallel-implementation drift across separate trees", later refined in Round 2 to "the parallel-implementation drift check" matching the section heading.
- Modified: `skills/simplify/SKILL.md:121`.

### F3 [Minor] simplify Defer threshold inconsistency — RESOLVED (Round 1)
- Action: Standardized both thresholds to "under 30 minutes".
- Modified: `skills/simplify/SKILL.md:148, 152`.

### F4 [Minor] en-dash `R17–R22` vs ASCII — RESOLVED (Round 1)
- Action: Replaced en-dash with ASCII hyphen in all occurrences.
- Modified: `skills/multi-agent-review/SKILL.md` (multiple locations).

### F5 [Minor] angle-bracket placeholder inconsistency — RESOLVED (Round 1)
- Action: Changed `<file already in this diff>` to `[file already in this diff]`.
- Modified: `skills/multi-agent-review/SKILL.md:892`.

### F6 [Minor pre-existing] R5 `findMany` JS-ORM identifier — RESOLVED (Round 1)
- Action: Generalized to "A read query (e.g., listing rows) followed by a separate write query (update/delete) without wrapping both in a DB transaction".
- Modified: `skills/multi-agent-review/SKILL.md:937`.
- Anti-Deferral note: although pre-existing, the file is in the diff (not just one line) per Pre-existing-in-changed-file rule, so fix was required.

### S1 [Minor] R21 lacked security carve-out — RESOLVED (Round 1)
- Action: Added security-specific re-verification clause to R21 table row AND added "Security carve-out" point #4 in R21 Extended obligations (later restructured in Round 2 as a parallel-obligation callout).
- Modified: `skills/multi-agent-review/SKILL.md` (R21 row + Extended).

### S2 [Minor] R18 "Remove (or narrow)" wording — RESOLVED (Round 1)
- Action: Tightened wording in BOTH R18 table row AND R18 Extended obligations to require: helper itself appears on the allowlist, AND all helper call sites are themselves on the allowlist/safelist or behind an equivalent higher-privilege gate. Round 2 strengthened "auditable" → "on the allowlist/safelist or behind an equivalent higher-privilege gate".
- Modified: `skills/multi-agent-review/SKILL.md` (R18 row + Extended).

### S3 [Minor pre-existing] Skill prompts lack delimiter fencing for content interpolation — DEFERRED (Out of scope)
- **Anti-Deferral check**: out of scope (different feature).
- **Justification**: rewriting the prompt-construction surface to add delimiter fences requires architectural redesign across all `[Plan contents]` / `[Code contents]` / `[Deviation log contents]` / `[Local LLM output]` interpolation sites in multiple skills, exceeding the 30-minute rule. The underlying issue is pre-existing in the skill family and predates this PR's changes.
- TODO marker: `TODO(skill-prompt-injection): add delimiter fences to all content interpolation in skill prompts (multi-agent-review, simplify, test-gen, explore, pr-create)`.
- **Orchestrator sign-off**: out-of-scope exception satisfied — issue tracked via grep-able TODO marker; pre-existing in unchanged surface (the prompt template construction pattern itself).

### S4 [Minor] simplify Defer lacked security carve-out — RESOLVED (Round 1)
- Action: Added "Security carve-out" paragraph after the Defer rule in simplify; later refined in Round 2/3 to use "the R3 propagation check" wording aligned with R21.
- Modified: `skills/simplify/SKILL.md:154`.

### T1 [Major] R19 row contained `__mocks__` — RESOLVED (Round 1)
- Action: Removed `__mocks__`, replaced with "in-test mock factories, manual mock files, test fixtures" + added vacuous-pass failure-mode warning.
- Modified: `skills/multi-agent-review/SKILL.md:951`.

### T2 [Major] R20 lacked concrete grep pattern — RESOLVED (Round 1, refined Round 2)
- Action: Added two concrete reviewer actions to R20 row. Round 2 replaced JS-flavored regex examples (`^import {$`, `^switch (.*) {$`) with language-neutral prose ("the project's block-opening token immediately followed by another block-opening token with no matching closer in between").
- Modified: `skills/multi-agent-review/SKILL.md:952`.

### T3 [Major] R21 "the relevant test suite" undefined — RESOLVED (Round 1)
- Action: R21 Extended now specifies "the project's full test command" with concrete clarification (package manifest test script / Makefile target / README command). Added "tests" to the 50+ re-run list.
- Modified: `skills/multi-agent-review/SKILL.md` (R21 Extended).

### T4 [Minor] Storage-backend lost concrete catalog pointer — RESOLVED (Round 1, refined Round 2)
- Action: Added inline examples (`information_schema`, `SHOW GRANTS`, `db.runCommand`, IAM-policy queries). Round 2 added "The list is illustrative, not exhaustive — for any other engine, consult its documentation for the equivalent introspection surface."
- Modified: `skills/multi-agent-review/SKILL.md:319`.

### T5 [Minor duplicate of F1] R20 template label — RESOLVED (Round 1)
- Action: Same fix as F1.

### T6 [Minor] R21 template "Verified" vs "Checked" — RESOLVED (Round 1)
- Action: Changed "Verified" to "Checked" in the R21 template line.
- Modified: `skills/multi-agent-review/SKILL.md` (Recurring Issue Check output template).

### T7 [Minor] R19 Extended lacked failure-mode signal — RESOLVED (Round 1, refined Round 2)
- Action: Added step #3 to R19 Extended Procedure: "Confirm at least one test asserts on the result of calling the new export through the mock — a mock declaration with no asserting test is the same vacuous-pass failure mode as omitting the export entirely." (Round 2 changed "exercises" to "asserts on the result of calling".)
- Modified: `skills/multi-agent-review/SKILL.md` (R19 Extended).

### F7 / T8 / S7 [Minor convergent] R20 JS-flavored regex examples — RESOLVED (Round 2)
- Action: Replaced `^import {$`, `^switch (.*) {$` with language-neutral prose.
- Modified: `skills/multi-agent-review/SKILL.md:952`.

### F8 / S8 [Minor convergent] Security carve-out wording drift — RESOLVED (Round 2, refined Round 3)
- Action: Aligned R21 row, R21 Extended, simplify Defer to all use "complete the R3 propagation check (trace all affected paths, confirm no propagation gap)" with the same surface list ("auth, crypto, input validation, permission grants, or other security-sensitive surfaces").
- Modified: `skills/multi-agent-review/SKILL.md` (R21 row + Extended), `skills/simplify/SKILL.md:154`.

### F9 / S5 / T13 [Minor convergent] R21 row omitted impact analysis — RESOLVED (Round 2)
- Action: Added "AND complete the R3 propagation check (trace all affected paths, confirm no propagation gap)" to R21 table row.
- Modified: `skills/multi-agent-review/SKILL.md:953`.

### F10 [Minor] simplify prompt wording vs heading — RESOLVED (Round 2)
- Action: Updated prompt to "the parallel-implementation drift check" matching the section heading.
- Modified: `skills/simplify/SKILL.md:121`.

### S6 [Minor] R18 "auditable" too weak — RESOLVED (Round 2)
- Action: Changed to "on the allowlist/safelist or behind an equivalent higher-privilege gate".
- Modified: `skills/multi-agent-review/SKILL.md` (R18 Extended).

### T9 [Minor] R21 Extended #4 disrupted numbered flow — RESOLVED (Round 2, refined Round 3)
- Action: Restructured from numbered step #4 to "**Security carve-out (parallel obligation, applies in addition to steps 1-3 above)**" callout. Round 3 added blank line for Markdown rendering.
- Modified: `skills/multi-agent-review/SKILL.md` (R21 Extended).

### T10 [Minor] R19 step #3 "exercises" — RESOLVED (Round 2)
- Action: Changed to "asserts on the result of calling".
- Modified: `skills/multi-agent-review/SKILL.md` (R19 Extended).

### T11 [Minor] Storage-backend list dilutive — RESOLVED (Round 2)
- Action: Added "The list is illustrative, not exhaustive — for any other engine, consult its documentation for the equivalent introspection surface."
- Modified: `skills/multi-agent-review/SKILL.md:319`.

### T12 [Minor] R5 row missing test-observability angle — RESOLVED (Round 2)
- Action: Added "Note: unit tests with mocked DB calls pass vacuously because the mock returns a stable result; only integration tests under concurrent load expose the race."
- Modified: `skills/multi-agent-review/SKILL.md:937`.

### F11 / F12 / T14 [Minor convergent] R21 Extended callout blank line + wording drift — RESOLVED (Round 3)
- Action: Added blank line before the callout; aligned wording to "complete the R3 propagation check (...)" across all three security-carve-out surfaces.
- Modified: `skills/multi-agent-review/SKILL.md` (R21 Extended).

### S11 [Minor] simplify cross-reference hardcoded file path — RESOLVED (Round 3)
- Action: Changed "in `skills/multi-agent-review/SKILL.md`" to "in the multi-agent-review skill".
- Modified: `skills/simplify/SKILL.md:154`.

### F13 [Minor] R5 mocked-test note placement — NO ACTION (Scope-owner ruling)
- **Anti-Deferral check**: out of scope (scope-owner ruling).
- **Justification**: testing expert (T15 in Round 3) — the scope owner for testing-related concerns — explicitly ruled placement appropriate cross-role: "observability concern applies cross-role; no action needed". Functionality expert F13 deferred to scope owner.
- **Orchestrator sign-off**: scope-owner ruling accepted; finding closed.

### S9 / S12 [Minor informational] Abstraction reduced reviewer greppability — ACCEPTED (Inherent tradeoff)
- **Anti-Deferral check**: acceptable risk.
- **Worst case**: a reviewer fails to grep for a now-abstract concept and misses an instance.
- **Likelihood**: medium (depends on reviewer's familiarity with the abstracted concept).
- **Cost to fix**: would re-introduce stack-specific identifiers (e.g., PostgreSQL terms), reverting the user's feedback that drove the entire abstraction effort. Net negative.
- **Orchestrator sign-off**: tradeoff is intentional and aligned with the user's stated policy (`feedback_no_lang_repo_specifics.md`).

### S10 / S13 / T15 / T16 [Informational] — NO ACTION
- Confirmations of intentional state; no remediation required.

## Recurring Issue Check (cross-round summary)

### Functionality expert
- R1-R8: N/A — no shared utility / constant / pattern / event / DB / cascade / E2E / UI changes
- R9 (Transaction boundary for fire-and-forget): Checked — no async dispatch in tx in this doc-only diff
- R10-R13: N/A
- R14-R16: N/A — no DB roles / migrations / privilege tests in this doc-only diff
- R17 (Helper adoption): N/A — diff is documentation, no shared helper introduced
- R18 (Allowlist sync): N/A — no privileged-op file changes
- R19 (Test mock alignment): N/A — no new exports in mocked modules
- R20 (Multi-statement preservation): N/A — edits were direct, not mechanical scripts
- R21 (Subagent completion vs verification): Checked — sub-agent outputs verified by re-reading file state at cited locations across rounds
- R22 (Perspective inversion): N/A — no helper introduced or used

### Security expert
- R1-R16: as above (N/A or Checked)
- R17-R22: as above
- RS1-RS3: N/A — no credential comparison / new routes / new request parameters in this diff

### Testing expert
- R1-R22: as above
- RT1-RT3: N/A — no test files modified, no test framework recommendation made

## Verification

- Lint / Test / Production build: N/A — config-only repo, no toolchain.
- E2E impact: N/A — no UI / route / selector changes.
- Pre-existing-in-changed-file rule: F6 (R5 `findMany`) caught and fixed per rule.

## Next Steps

1. Branch creation required before commit (skill rule "No Commits to main", currently on main with uncommitted changes).
2. Commit message suggestion: `refactor: abstract language/repo-specific identifiers from skill rules; add R17-R22`.
3. Reinstall via `bash install.sh` after commit so the running copy at `~/.claude/skills/` matches.
