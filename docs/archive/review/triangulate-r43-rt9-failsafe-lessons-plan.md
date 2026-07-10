# Plan: Fold security-audit remediation session lessons into triangulate (R43, RT9, fail-safe precedence, measurement & convergence rules)

## Project context

- **Type**: `config-only` (this repo tracks `~/.claude/` configuration: settings.json, hooks, skills, rules)
- **Test infrastructure**: `unit tests only` — `tests/` holds shell-based hook tests; no CI/CD pipeline runs in this repo. Skill markdown is validated by review and runtime usage.
- **Deployment model**: this repo is the source of truth; `install.sh` copies files into `~/.claude/`. Skill files live at `skills/triangulate/` (copied, not symlinked).
- **Out-of-scope test recommendations**: per phase-1-plan.md project-context guidance, experts MUST NOT raise Major/Critical findings recommending automated tests, CI/CD, or test framework setup for skill markdown changes.
- **Verification environment constraints**: none blocking — all acceptance checks are local greps, markdown table integrity checks, and `install.sh` + `diff -q` parity. Every contract's verification path is `verifiable-local`.

## Objective

A security-audit remediation session (E2E-encrypted password manager monorepo; 10 audit findings fixed across 3 Phase-3 rounds + dedicated verification) surfaced two classes of skill gap that required manual user intervention, plus five smaller improvements. Encode all seven so the next security-remediation run converges without the user having to say "セキュリティ対応ブランチなのだから本質的対応が大前提" by hand:

1. **L1 (gap, user-corrected)**: a Round-2 fix restored a wide broadcast surface (re-delivering decrypted credentials to all subframes) to answer a functionality expert's coverage-regression finding — the fix itself re-opened the vulnerability. Nothing in the skill made the next round diff boundary predicates against the *previous round's* narrowed state, and nothing said security wins the tradeoff by default. → **R43** + Round-2+ template check + Step 3-5 protocol.
2. **L2 (gap, user-corrected)**: the functionality expert offered a two-option menu (restore the wide surface / defer a permission change to another PR) and no step forced searching for the third design that satisfies both sides (consumer-side self-origin gate). → **Step 3-5 cross-perspective tradeoff protocol** (both-satisfying search first; fail-safe precedence).
3. **L3 (judgment was ad-hoc)**: an uncovered same-class member found in an out-of-audit-scope feature (pending-save flow) triggered a per-member "this branch or separate PR?" question to the user. → **Anti-Deferral item: same-branch default for security-class members**.
4. **L4 (near-miss, caught manually)**: production plain-script + typed test-twin parallel implementation — a gate added to the twin only would have shipped a vulnerable production artifact under a green suite; a raw-content sync test prevented it. → **RT9**.
5. **L5 (resolved only by user-driven measurement)**: a residual-data finding (pre-fix rows) was headed for a desk-argument accept until a read-only count query settled it (0 rows). → **Anti-Deferral item: read-only measurement before disposition**.
6. **L6 (orchestrator load)**: 3 rounds × 3 experts of prose findings made cross-round tracking manual and error-prone. → **machine-readable findings index block** in expert templates + mechanical merge pre-pass.
7. **L7 (worked, not yet codified)**: two independent perspectives converging on the same line/fix reliably predicted Major+ severity. → **Perspective Convergence severity-floor rule**.

Plus one pre-existing staleness in files this PR touches (Anti-Deferral: in scope): the Recurring Issue Check file templates in phase-1 (lines 261-276) and phase-3 (lines 307-322) list only RS1-RS5 / RT1-RT7 — RS6 and RT8 are missing.

## Requirements

### Functional

1. **R43 (NEW)** — Fix-induced security-boundary widening (fail-safe precedence). New row in the "All experts must check" table, after R42. Severity: Major; **Critical when the widened surface delivers credentials, session/key material, decrypted secrets, or privileged operations to the added recipients**. Self-contained row (no Extended-obligations section). Verbatim body below.
2. **RT9 (NEW)** — Parallel-implementation twin drift. New row in the "Testing expert must additionally check" table, after RT8. Severity: **Critical when the drifting logic is a security control; Major otherwise**. Self-contained row. Verbatim body below.
3. **Anti-Deferral Rules: two new numbered items** (6 and 7) in common-rules.md — residual-data read-only measurement; security-class member same-branch default. Verbatim bodies below.
4. **Perspective Convergence as a Severity Signal** — new `###` subsection in common-rules.md, placed immediately after "Handling [Adjacent] Findings". Verbatim body below.
5. **Cross-perspective tradeoff protocol (fail-safe precedence)** — new block inside phase-3 Step 3-5, after the "Important rules" list. Verbatim body below.
6. **Round 2+ boundary-widening check** — new requirement bullet in the phase-3 Step 3-3 Round 2+ template. Verbatim body below.
7. **Machine-readable findings index** — new requirement bullet in expert instruction templates (phase-1 Step 1-4 Round 1 & Round 2+; phase-3 Step 3-3 Round 1 & Round 2+) + a "Mechanical merge pre-pass" paragraph in phase-1 Step 1-5 and phase-3 Step 3-4. Verbatim bodies below.
8. **Range/template consistency sweep** — all rule-range references bumped and the stale RS/RT template lists fixed. Member-set derived by grep (see C9).

### Non-functional

- **No language/framework/repo-specific identifiers** (per `feedback_no_lang_repo_specifics`): the source session's tokens (`allFrames`, extension message names, `.js`/`-lib.ts` pairing, product names) MUST NOT appear as normative text. Concrete mechanisms are described abstractly (broadcast/delivery surface, origin/frame gate, production artifact vs test-importable twin) with examples marked illustrative.
- **Rule-ID stability**: R1-R42, RS1-RS6, RT1-RT8 IDs unchanged. R43 and RT9 append; no renumbering.
- **Table integrity**: new rows keep the 4-column layout of their tables.
- **Edit the repo source only** (per `feedback_edit_repo_source_not_installed`); `install.sh` deploys.

## Technical approach

Markdown-only change across 5 files in `skills/triangulate/`. No hook/script changes in this PR (mechanical detection for R43/RT9 is deferred — see Scope contract SC2).

### Edit targets

1. **`skills/triangulate/common-rules.md`**:
   - Insert R43 row after R42 row (C1).
   - Insert RT9 row after RT8 row (C2).
   - Update footer line ("See "Extended obligations" below…"): add R43 to the self-contained list (C1).
   - Append Anti-Deferral items 6 and 7 after item 5 (C3, C4).
   - Insert "Perspective Convergence as a Severity Signal" subsection after "Handling [Adjacent] Findings" (C5).
   - Recurring Issue Check template: add R43 line after R42 line; bracket line `RS1-RS6` stays, `RT1-RT8` → `RT1-RT9` (C9).
   - Line 105 `R1-R42` → `R1-R43` (C9).
2. **`skills/triangulate/phases/phase-3-review.md`**:
   - Step 3-5: insert the tradeoff protocol block after the "Important rules" list (C6).
   - Step 3-3 Round 2+ template: add the R43 boundary-widening bullet to Requirements (C7).
   - Step 3-3 Round 1 & Round 2+ templates: add the findings-index bullet (C8).
   - Step 3-4: add the "Mechanical merge pre-pass" paragraph (C8).
   - Recurring Issue Check file template: add `RS6`, `RT8`, `RT9` lines; `(R1-R42)` → `(R1-R43)` ×3 (C9).
   - Lines 80, 90, 114, 127: `R1-R42` → `R1-R43` (C9).
3. **`skills/triangulate/phases/phase-1-plan.md`**:
   - Step 1-4 Round 1 & Round 2+ templates: add the findings-index bullet (C8).
   - Step 1-5: add the "Mechanical merge pre-pass" paragraph (C8).
   - Recurring Issue Check file template: add `RS6`, `RT8`, `RT9` lines; `(R1-R42)` → `(R1-R43)` ×3; line 225 `R1-R42` → `R1-R43` (C9).
4. **`skills/triangulate/phases/phase-2-coding.md`**:
   - Line 353 `R1-R42` → `R1-R43`; lines 400-402 scope list: `R1-R42` → `R1-R43` (×3 experts), `RT1-RT8` → `RT1-RT9` (C9).
5. **`skills/triangulate/SKILL.md`**:
   - Lines 22, 24 `R1-R42` → `R1-R43` (C9).

### Diff scope summary

| File | LOC delta (estimate) |
|---|---|
| `skills/triangulate/common-rules.md` | +~40 / -~3 |
| `skills/triangulate/phases/phase-3-review.md` | +~35 / -~10 |
| `skills/triangulate/phases/phase-1-plan.md` | +~12 / -~5 |
| `skills/triangulate/phases/phase-2-coding.md` | ±4 lines (range updates) |
| `skills/triangulate/SKILL.md` | ±2 lines (range updates) |

### Deployment

After editing, run `./install.sh`, then verify `diff -q` parity for all 5 files against `~/.claude/skills/triangulate/`.

## Contracts

### C1 — R43 rule row (+ footer self-contained list)

- **Signature**: one new markdown table row in the "All experts must check" table, 4 columns, inserted immediately after the R42 row. Footer sentence gains ", and R43" in its self-contained list.
- **Invariants** (app-enforced — the "runtime" is reviewer behavior): (a) R42 remains the last-but-one row; no existing row text changes; (b) the row is self-referentially complete (a reviewer can act on the table row alone); (c) severity column carries the Major/Critical split.
- **Forbidden patterns**:
  - `pattern: allFrames — reason: source-session-specific API token; must be abstracted to "delivery/broadcast surface"`
  - `pattern: passwd-sso — reason: source project name must not appear in skill text`
- **Acceptance criteria**: `grep -c '^| R43 '` on common-rules.md returns 1; the row has exactly 4 `|`-delimited cells; footer line lists R43 as self-contained; R43 references phase-3 Step 3-5 protocol and distinguishes itself from R18 and R38.
- **Consumer-flow walkthrough**: Consumer 1 — expert sub-agents (phase-1/2/3 prompts) read the row's {Pattern, What to check, Severity} to run the check; all three fields present in the verbatim body. Consumer 2 — the Recurring Issue Check template (common-rules.md ~line 608) needs a matching `- R43 (...)` status line; provided by C9. Consumer 3 — phase-3 Round 2+ template bullet (C7) cites "per R43"; the row exists before the bullet references it (single PR, atomic).

### C2 — RT9 rule row

- **Signature**: one new markdown table row in the "Testing expert must additionally check" table, 4 columns, after RT8.
- **Invariants**: RT1-RT8 rows unchanged; 4-column layout preserved.
- **Forbidden patterns**:
  - `pattern: -lib\.ts — reason: source-session file-pairing convention; abstract to "test-importable twin"`
  - `pattern: \?raw — reason: bundler-specific import syntax; mark illustrative if mentioned, prefer "raw-content import"`
- **Acceptance criteria**: `grep -c '^| RT9 '` returns 1; row cross-references RT5 (file-level generalization), RT7 (red-proven sync guard), and R19 (why all-test-tree enumeration does not backstop); severity cell carries the Critical/Major split.
- **Consumer-flow walkthrough**: Consumer 1 — testing-expert sub-agent prompts consume the row directly. Consumer 2 — Recurring Issue Check file templates in phase-1/phase-3 need an `- RT9: [status]` line; provided by C9. Consumer 3 — phase-2 Step 2-5 scope list (`Testing expert: R1-R43 + RT1-RT9`) must include RT9; provided by C9.

### C3 — Anti-Deferral item 6 (residual-data read-only measurement)

- **Signature**: new numbered item `6.` appended to the Anti-Deferral Rules numbered list in common-rules.md (currently 1-5).
- **Invariants**: items 1-5 unchanged; the mandatory Skipped/Accepted format block below the list is unchanged (the new item feeds its "acceptable risk" branch with measured values).
- **Forbidden patterns**: `pattern: kdfType — reason: source-session schema field; abstract to "legacy-format rows"`
- **Acceptance criteria**: item requires (a) read-only measurement before accept/migrate/defer disposition, (b) command + observed count recorded in Resolution Status, (c) explicit statement that version/timing speculation is not evidence, (d) R31 interaction (read-only exempt; cleanup writes still gated), (e) unreachable-environment escape hatch (provisional disposition).
- **Consumer-flow walkthrough**: Consumer — orchestrator during Step 1-6 / 3-5 disposition; reads the item as a precondition checklist for the Anti-Deferral entry format it already uses. No new fields consumed elsewhere.

### C4 — Anti-Deferral item 7 (security-class member same-branch default)

- **Signature**: new numbered item `7.` after item 6.
- **Invariants**: contrast with the "out of scope (different feature)" exception (the 4th exception bullet of the mandatory Skipped/Accepted format block — NOT numbered list item 4, which is "Deferred findings must be tracked") stays coherent — item 7 explicitly carves security-class members OUT of that exception's "cite the plan/issue and defer" path. All cross-references in the verbatim body name the exception by its label, never by a bare "item 4".
- **Forbidden patterns**: `pattern: pending-save — reason: source-session feature name; describe as "a feature outside the original audit scope"`
- **Acceptance criteria**: item states (a) same-branch fix is the DEFAULT for security-class members regardless of original ticket scope, with the trigger defined by R42's structural test (a control that ought to hold universally + this finding is one instance), NOT by the self-reported "was R42 invoked" label — and the derivation MUST run BEFORE the same-branch-vs-separate-PR classification is made, (b) deferral requires full acceptable-risk quantification AND recorded user approval, (c) pure-functionality/UX discoveries remain material for the "out of scope (different feature)" exception of the Skipped/Accepted format block, (d) cross-reference to Essence-Shift Detection (class discovery = essence shift; re-scope once, don't ask per member).
- **Consumer-flow walkthrough**: Consumer 1 — orchestrator disposition step (as C3). Consumer 2 — Essence-Shift Detection section already instructs re-scoping; item 7 cites it by name, no text change needed there (verified: section exists at common-rules.md line 47).

### C5 — Perspective Convergence subsection

- **Signature**: new `### Perspective Convergence as a Severity Signal` subsection in common-rules.md, immediately after `### Handling [Adjacent] Findings`.
- **Invariants**: dedup steps (1-5/3-4) keep their existing text; the subsection layers a floor rule on top, it does not redefine merging.
- **Acceptance criteria**: subsection states (a) ≥2 independent perspectives on same location + same root cause ⇒ severity floor Major, take max never average, (b) merged finding records which perspectives converged, (c) convergent findings are fixed first in the round, (d) explicit non-inference: absence of convergence is NOT evidence of low severity.
- **Consumer-flow walkthrough**: Consumer 1 — orchestrator during dedup/merge (Step 1-5/3-4) applies the floor when writing the merged file; the C8 mechanical pre-pass names this subsection as where convergence is stamped. Consumer 2 — fix-ordering in Step 3-5 reads "fixed first".

### C6 — Step 3-5 cross-perspective tradeoff protocol

- **Signature**: new bold-titled block `**Cross-perspective tradeoff protocol (fail-safe precedence)**` with a 3-step numbered procedure, inserted in phase-3 Step 3-5 after the "Important rules" bullet list.
- **Invariants**: existing Step 3-5 rules (No deferring, Fix ALL errors, Test-verified behavior conflict check) unchanged; the protocol composes with the Test-verified-behavior check (that check governs reverting tested behavior; this protocol governs conflicting *findings*).
- **Forbidden patterns**: `pattern: webNavigation — reason: source-session permission name; describe as "a new platform permission"`
- **Acceptance criteria**: protocol contains (1) both-satisfying design search FIRST with ≥3 illustrative moves (consumer-side gate, scoped delivery to the specific member, split privileged payload from broadcast signal) and requires recording searched alternatives in Resolution Status, (2) security-wins-by-default when no both-satisfying design found, with widening acceptance requiring isolated R43 security re-review + explicit user approval, (3) the absolute statement that a functionality-regression report against a security fix is a trigger for step 1, never authorization to weaken — strengthened on security-remediation branches.
- **Consumer-flow walkthrough**: Consumer 1 — orchestrator at fix time (Step 3-5). Consumer 2 — R43's row (C1) routes "when found → Step 3-5 protocol"; the protocol must exist at that path (same PR, atomic). Consumer 3 — Resolution Status entries gain a "searched alternatives" line; format is free-form within the existing entry, no template change required.

### C7 — Round 2+ boundary-widening check bullet

- **Signature**: one requirement bullet added to phase-3 Step 3-3 Round 2+ template's Requirements list.
- **Invariants**: Round 2+ template retains all existing bullets; the new bullet applies to ALL experts (the widening is often introduced by a functionality-driven fix and must be caught by any perspective).
- **Acceptance criteria**: bullet instructs comparing boundary predicates against the PREVIOUS ROUND's state (not only main), names revert-of-tightening as in scope, and cites R43. Round-1 coverage note: no Round-1 bullet is needed — R43's self-contained table row (C1) obligates the check in every round, and its Reviewer-action text defines the Round-1 baseline as the pre-fix state (branch point / main); the Round 2+ bullet exists only to add the "previous round, not just main" precision that becomes meaningful from Round 2.
- **Consumer-flow walkthrough**: Consumer — expert sub-agents receiving the Round 2+ prompt. The bullet references only inputs the template already provides (the round diff and previous findings).

### C8 — Machine-readable findings index + mechanical merge pre-pass

- **Signature**: (a) one requirement bullet appended to the Requirements list of ALL FOUR templates explicitly (phase-1 Step 1-4 Round 1 AND Round 2+; phase-3 Step 3-3 Round 1 AND Round 2+) — phase-1's Round 2+ "All obligations from Round 1 remain in effect (Plan-specific obligations, severity criteria, etc.)" sentence names only two blocks, not the Requirements list, so relying on inheritance is an ambiguous parse; each template gets its own copy of the bullet; (b) one paragraph in phase-1 Step 1-5 and phase-3 Step 3-4 before the Ollama merge call.
- **Index schema (locked)**: fenced ```json block, array of objects: `{"id": "F1", "severity": "Critical"|"Major"|"Minor", "title": string, "file": string|null, "line": number|null, "adjacent": boolean, "escalate": boolean|null}`. Empty array `[]` when "No findings". `file` is null for findings with no concrete source-file target (typical for Phase-1 plan-prose findings; a plan-section anchor may go in `title` instead). `escalate` semantics: `false` = Security-expert Critical finding assessed and NOT escalated; `true` = escalation requested; `null` = field not applicable (non-Critical finding, or non-Security expert) — null never means "not assessed" on a Security-expert Critical entry. Prose findings remain authoritative; the index is a tracking aid.
- **Invariants**: Recurring Issue Check verbatim-preservation rule unchanged; Ollama merge-findings call remains; missing/malformed index → return-to-expert (same contract as missing Recurring Issue Check).
- **Acceptance criteria**: all four template locations carry their own copy of the bullet (no inheritance reliance); Step 1-5/3-4 paragraphs describe join keys (file, line proximity, title similarity), convergence stamping (cites C5 subsection), cross-round ID carry, and Ollama-unavailable fallback role; the schema's `file` and `escalate` null semantics are stated in the bullet itself.
- **Consumer-flow walkthrough**: Consumer 1 — orchestrator merge step reads `{id, severity, file, line}` to join across experts and rounds, `{adjacent}` to route per Handling [Adjacent] Findings, `{escalate}` to trigger the Opus re-run. All fields present in the locked schema. Consumer 2 — convergence detection (C5) reads `{file, line, title}` pairs across experts. Consumer 3 — Loop Progress Report reads per-severity counts; derivable from `{severity}`.

### C9 — Range/template consistency sweep

- **Signature**: mechanical text replacements + template line insertions across all 5 files.
- **Member-set derivation (R42 clause ①)**: defining primitive = the literal range tokens. `grep -rn -oE 'R1-R42|RT1-RT8' skills/triangulate/` run on 2026-07-11 returned exactly: SKILL.md:22, SKILL.md:24; common-rules.md:105, common-rules.md:609(RT); phase-1-plan.md:225, 256, 260, 269; phase-2-coding.md:353, 400, 401, 402(+RT at 402); phase-3-review.md:80, 90, 114, 127, 302, 306, 315. Total: R1-R42 ×18, RT1-RT8 ×2 (Round-1 review recomputed and confirmed: 18, not the initially miscounted 20). Plus structurally-indirect members (clause ③ — enumerated lists rather than range tokens): phase-1-plan.md lines 261-265 (RS list missing RS6) and 270-276 (RT list missing RT8), phase-3-review.md lines 307-311 (RS list missing RS6) and 316-322 (RT list missing RT7's successors RT8), and common-rules.md Recurring Issue Check template (needs R43 line after the R42 line at ~608).
- **Replacements**: `R1-R42` → `R1-R43` (all 18); `RT1-RT8` → `RT1-RT9` (both); phase-1 & phase-3 file templates gain `- RS6: [status]`, `- RT8: [status]`, `- RT9: [status]` lines; common-rules template gains the R43 status line; `RS1-RS6` unchanged.
- **Acceptance criteria**: after edits, `grep -rn -E 'R1-R42|RT1-RT8' skills/triangulate/` returns zero hits; `grep -rn 'RS6: \[status\]'` hits phase-1 and phase-3 once each; same for `RT9: \[status\]`; `grep -c 'R43 (' skills/triangulate/common-rules.md` ≥ 2 (table row + template line).
- **Consumer-flow walkthrough**: Consumers are the experts copying the templates; a template listing RT9 requires the RT9 row to exist (C2, same PR).

## Verbatim rule bodies

Phase 2 pastes these verbatim. Markdown table rows are single-line; keep `|` cell boundaries intact.

### Verbatim — R43 row (insert after R42 row in "All experts must check")

```
| R43 | Fix-induced security-boundary widening (fail-safe precedence) | Fires when a diff — most often a review-round fix responding to a functionality/coverage finding — WIDENS a security-boundary surface relative to the state before the fix: delivery/broadcast scope (which frames, windows, processes, or recipients receive a privileged payload), origin/frame/tenant gating predicates, allowlist/safelist entries, permission/entitlement/scope declarations, input-acceptance predicates, audit/observability emission or retention (suppressing or downgrading an audit write, narrowing what gets logged, shortening retention to answer a noise/performance complaint — same family as R31 category (g)), security-relevant timeout/interval values (session TTL, lockout duration, rate-limit window, re-auth/MFA grace — widened to answer a UX complaint; the runtime-constraints obligation above covers values too SMALL, R43 covers the fix-round widening direction), crypto/KDF parameter floors and algorithm whitelists (an internal floor lowered or a deprecated algorithm re-admitted as a "compatibility fix"), or a revert of an earlier round's tightening in any of these classes — the enumeration is illustrative of the mechanism, not a closed list: any predicate whose narrowing WAS the security fix is in scope when a later fix re-widens it. The canonical failure shape: a security fix narrows a delivery surface; a functionality reviewer correctly reports a coverage regression ("legitimate consumer X no longer receives Y"); the responder restores the wide delivery — re-opening the vulnerability the narrowing fixed (illustrative: re-broadcasting decrypted credentials to every embedded frame to restore one legitimate embedded consumer's autofill). The functionality report is CORRECT as a report — the error is treating "restore the old width" as its fix. **Reviewer action**: for each fix in the round, diff every boundary predicate it touches against the PREVIOUS round's state (not only against main; on Round 1, where no previous round exists, the baseline is the pre-fix state — the branch point / main) and ask "did any gate get wider to buy back functionality?" — widening disguised as a regression fix does not announce itself. When found: the widening change MUST be re-reviewed in isolation from the security perspective before commit, and the default disposition is fail-safe — keep the narrow boundary and route to the cross-perspective tradeoff protocol (phase-3 Step 3-5) to search for a design satisfying both sides. Accepting the widening requires explicit security sign-off recorded in Resolution Status plus the full Anti-Deferral quantification (Worst case / Likelihood / Cost-to-fix). **Distinct from**: R18 (allowlist bidirectional sync on privileged-op moves — R43 covers ANY boundary predicate and specifically the fix-round revert dynamic), R38 (fail-open by late async write — R43 is fail-open by deliberate edit), RS5 (RS5 bounds externally-supplied parameters at the input boundary — R43 fires when an INTERNAL floor/whitelist is loosened mid-review), and the Step 3-5 test-verified-behavior check (that check defends tested behavior against heuristic findings; R43 defends a security tightening against a coverage-regression finding). | Major (Critical when the widened surface delivers credentials, session/key material, decrypted secrets, or privileged operations to the added recipients) |
```

### Verbatim — footer line update (common-rules.md line 321)

Before (verbatim): `See "Extended obligations" below for full procedures on R17-R22, R31-R35, R38, R40, and R42. R23-R30, R36, R37, R39, and R41 are self-contained in the table row above.`

After (verbatim): `See "Extended obligations" below for full procedures on R17-R22, R31-R35, R38, R40, and R42. R23-R30, R36, R37, R39, R41, and R43 are self-contained in the table row above.`

### Verbatim — RT9 row (insert after RT8 row in "Testing expert must additionally check")

```
| RT9 | Parallel-implementation twin drift (production artifact vs test-importable twin) | When the production artifact and the file the tests import are SEPARATE files maintained in parallel — a plain-script production file plus a typed twin for unit tests (common in build-less runtimes that load raw scripts: extension content scripts, userscripts, embedded interpreters), a vendored/transpiled copy, an implementation plus a hand-maintained stub, a generated artifact vs its source — the entire test suite exercises the twin, so a change (especially a security gate) applied to the twin but not to the production file ships a vulnerable production artifact under a fully green suite. This is the file-level generalization of RT5 (test call-path must include the production primitive): the call path is right, the FILE is wrong — and it is vacuous in the RT4/RT8 sense: every test passes while the property under test is absent from production. **Reviewer action**: (1) detect twin pairs — check what the runtime actually loads (manifest, loader config, script tags, deployment bundle) versus what the tests import; same-basename pairs and documented twins are the common shapes; (2) when the diff changes one side of a pair, require the equivalent change on the other side in the same diff; (3) require a drift guard pinning security-relevant logic to BOTH files — preferred: single-source-of-truth build (twin generated from one source, drift impossible); acceptable: a sync test that reads both files as raw text/AST and asserts the guarded logic exists in each (raw-content import or file read, checksum over the relevant region, AST query — illustrative, adapt to the project's tooling), red-proven per RT7; (4) note that R19's all-test-tree enumeration does NOT backstop this gap — every test tree imports the twin, so no amount of test-tree coverage observes the production file. | Critical when the drifting logic is a security control (auth/authz check, origin/frame gate, sanitizer, crypto parameter, signature verification, rate limiter, RLS/tenancy predicate, idempotency guard on a security-state mutation — a superset of RT5's Critical-escalation list); Major otherwise |
```

### Verbatim — Anti-Deferral items 6 and 7 (append after item 5 in common-rules.md)

```
6. **Residual-data findings require read-only measurement before disposition**: when a finding concerns pre-existing stored data (rows written before a fix landed, legacy-format records, stale cache/index entries, orphaned rows), the accept/migrate/defer decision MUST be grounded in a read-only measurement against the target environment — a count/enumeration query executed BEFORE disposition, with the command and the observed count recorded in the Resolution Status entry. Count/aggregate only: the measurement query must not select, echo, or log row-level contents of security-state tables (sessions, tokens, credential/permission rows) — standard secret-logging hygiene; the evidence needed is a number, not the data. "Should be zero because <version/timing reasoning>" is speculation, not evidence — the one-minute query is always cheaper than the desk debate it replaces, and pre-release assumptions about data states have been wrong before. Read-only measurement does not trigger R31; any subsequent cleanup/migration WRITE remains fully subject to R31's confirmation contract. When the target environment is unreachable from the review context, record that explicitly and mark the disposition `provisional pending measurement` — a provisional accept is not a closed finding: it must additionally carry a grep-able TODO marker per item 4 (Deferred findings must be tracked), and a round with an open provisional disposition does NOT satisfy the termination check's "all experts return No findings" stop condition.
7. **Uncovered members of a security-boundary class default to same-branch fix**: when review discovers that a finding is an uncovered member of a security-boundary class (a member the control was declared to cover — the same credential-release path, the same guard-bypass shape), fixing it in the CURRENT branch is the default even when the member lives in a feature outside the original ticket/audit scope. A security-remediation branch that merges with a known same-class hole open has not remediated the class — the audit scope was the seed, not the set (R42 trigger (b)). **Trigger is the structural test, not the label**: whenever a finding reports a missing/bypassed security control on one instance of an operation that structurally recurs elsewhere (the R42 trigger-(b) shape), the orchestrator MUST run the R42 member-set derivation BEFORE deciding same-branch vs separate-PR — the classification decision cannot precede the derivation, and "we didn't invoke R42 on this one" is not an exemption. Deferring such a member to a follow-up PR requires the full acceptable-risk quantification (worst case / likelihood / cost) AND explicit user approval recorded in the entry; "different feature" alone is NOT sufficient grounds, and the 30-minute rule's security carve-out (impact analysis before applying) still applies to the fix itself. Contrast: pure-functionality/UX improvements discovered en route remain separate-PR material under the "out of scope (different feature)" exception of the mandatory Skipped/Accepted format block below — the same-branch default applies only to members of the security class being remediated. Discovering such a member is an essence shift — apply "Essence-Shift Detection and Re-Scoping" (declare once, re-scope the plan, proceed) instead of asking the user per member.
```

### Verbatim — Perspective Convergence subsection (insert after "Handling [Adjacent] Findings" in common-rules.md)

```
### Perspective Convergence as a Severity Signal

When two or more experts independently converge on the same location and the same root cause — e.g., the functionality expert reports "regression: legitimate consumers of X broke" and the security expert reports "vulnerability: X trusts the wrong input", both pointing at the same site and implying the same fix — treat the convergence itself as corroborating evidence:

1. **Severity floor**: a finding independently reported by ≥2 perspectives is at least Major, regardless of the individual reports' severities. Take the maximum of the reported severities — never average, and never let deduplication (Step 1-5 / Step 3-4) silently downgrade a finding by merging a higher-severity report into a lower-severity description.
2. **Record the convergence**: the merged finding notes which perspectives converged (e.g., `convergent: functionality+security`) so fix assessment can weight it.
3. **Fix priority**: convergent findings are fixed first within their severity tier — independent derivations agreeing is exactly the signal triangulation exists to produce, and such findings are the least likely to be false positives.
4. **No inverse inference**: convergence raises the floor; its absence proves nothing. A finding reported by a single perspective keeps its assessed severity and its priority — most Critical findings are single-perspective by nature (deep domain checks the other experts are scoped out of).
```

### Verbatim — Step 3-5 tradeoff protocol (insert in phase-3 after the "Important rules" list)

```
**Cross-perspective tradeoff protocol (fail-safe precedence)**: when a fix that satisfies one expert's finding would violate another expert's requirement — the canonical case: restoring functionality coverage requires widening a security boundary (R43) — do NOT pick between the options the findings offer:

1. **Search for a both-satisfying design first.** The options enumerated inside a finding are proposals, not the design space. Before accepting any tradeoff, spend an explicit search step on a design that preserves the security invariant AND restores the function. Typical moves (illustrative): enforce the gate at the consumer side instead of the producer (each recipient independently verifies its own origin/identity/context before acting on the payload); scope the delivery to the specific legitimate member instead of re-opening the broad surface; split the privileged payload from the broadcast signal (broadcast only a notification, let the legitimate consumer pull the payload through a gated channel). Record the alternatives searched in the Resolution Status entry even when the first one succeeds — the search step is evidence the tradeoff was not accepted by default.
2. **If no both-satisfying design is found, security wins by default.** Keep the narrower boundary, accept the functionality regression, and record it as a known limitation with a full Anti-Deferral entry. Reversing this default — accepting the boundary widening — requires an isolated security re-review of the widening change (R43) AND explicit user approval recorded in Resolution Status, and the approval entry MUST carry the same Worst case / Likelihood / Cost-to-fix quantification the Anti-Deferral mandatory format requires — a bare "user approved" line is invalid, exactly as it is for a Skipped/Accepted finding. (Accepting a widening permanently must never be cheaper to record than deferring a fix.)
3. **A functionality-regression report against a security fix is never, by itself, authorization to weaken the fix.** It is the trigger for step 1. On a security-remediation branch this is absolute: the branch's purpose fixes the priority order, and "restore the previous behavior" is presumed to re-open the vulnerability until shown otherwise.
```

### Verbatim — Round 2+ boundary-widening bullet (add to phase-3 Step 3-3 Round 2+ Requirements)

```
- **Fix-induced boundary-widening check (R43, all experts)**: for each fix in this round's diff, compare every security-boundary predicate it touches (delivery/broadcast scope, origin/frame/tenant gate, allowlist entry, permission/entitlement scope, input-acceptance predicate) against the PREVIOUS round's state — not only against main — and flag any widening, including reverts of an earlier round's tightening made to restore functionality. Evaluate per R43: widening that delivers credentials/secrets/privileged operations to added recipients is Critical.
```

### Verbatim — findings-index bullet (add to expert-template Requirements: phase-1 Step 1-4 Round 1 AND Round 2+; phase-3 Step 3-3 Round 1 AND Round 2+ — each template gets its own copy)

```
- After your findings and the Recurring Issue Check, append a machine-readable index of your findings as a fenced json code block: a JSON array with one element per finding — {"id": "F1", "severity": "Critical"|"Major"|"Minor", "title": "<short title>", "file": <"path" or null>, "line": <number or null>, "adjacent": <true|false>, "escalate": <true|false|null>} — or [] when you report "No findings". `file` is null when the finding has no concrete source-file target (typical for plan-prose findings). `escalate`: false = Critical finding assessed and not escalated (Security expert), true = escalation requested, null = not applicable (non-Critical finding, or non-Security expert). The prose finding remains authoritative; the index is a merge/tracking aid and must list exactly the findings your prose reports (no extras, no omissions).
```

### Verbatim — mechanical merge pre-pass paragraph (add to phase-1 Step 1-5 and phase-3 Step 3-4, before the Ollama merge invocation)

```
**Mechanical merge pre-pass (before the Ollama call)**: parse each expert's fenced json findings index and join entries across experts on (same file, line within ±5, similar title/root cause). Use the join to (a) seed deduplication, (b) detect perspective convergence and stamp the merged finding's severity floor per "Perspective Convergence as a Severity Signal" (Common Rules), and (c) carry finding IDs and statuses across rounds without re-parsing prose. The Ollama merge-findings call remains the prose merger; when Ollama is unavailable, this json join IS the fallback dedup skeleton. A missing or malformed index (or one that disagrees with the expert's prose findings) is returned to the expert for revision — same contract as a missing Recurring Issue Check section.
```

### Verbatim — Recurring Issue Check template additions

common-rules.md template (after the R42 line):
```
- R43 (Fix-induced security-boundary widening): [N/A — no boundary predicate touched by this round's fixes / Checked — no widening vs previous round / Finding F-XX]
```
common-rules.md bracket line — Before: `- [Expert-specific checks as applicable: Security adds RS1-RS6; Testing adds RT1-RT8]` / After: `- [Expert-specific checks as applicable: Security adds RS1-RS6; Testing adds RT1-RT9]`

phase-1-plan.md and phase-3-review.md file templates: after `- RS5: [status]` insert `- RS6: [status]`; after `- RT7: [status]` insert `- RT8: [status]` and `- RT9: [status]`; every `- ... (R1-R42)` becomes `- ... (R1-R43)`.

## Go/No-Go Gate

| ID  | Subject                                                        | Status |
|-----|----------------------------------------------------------------|--------|
| C1  | R43 rule row + footer self-contained list                      | locked |
| C2  | RT9 rule row                                                   | locked |
| C3  | Anti-Deferral item 6 — residual-data measurement               | locked |
| C4  | Anti-Deferral item 7 — security-class member same-branch       | locked |
| C5  | Perspective Convergence subsection                             | locked |
| C6  | Step 3-5 cross-perspective tradeoff protocol                   | locked |
| C7  | Round 2+ boundary-widening check bullet                        | locked |
| C8  | Findings index + mechanical merge pre-pass                     | locked |
| C9  | Range/template consistency sweep (incl. stale RS6/RT8 lines)   | locked |

Locked 2026-07-11 after plan-review convergence (3 rounds + 1 single-item verification; all experts at zero open findings).

## Testing strategy

Config-only repo; validation is review-driven plus mechanical greps:

1. **Table integrity**: `grep '^| R43 \|^| RT9 ' skills/triangulate/common-rules.md | awk -F'|' '{print NF}'` → exactly `6` for each of the two rows (a well-formed 4-content-cell markdown row splits into 6 `|`-fields; verified against existing R42/RT8 rows). Sibling rows unchanged.
2. **Range sweep**: `grep -rn -E 'R1-R42|RT1-RT8' skills/triangulate/` → zero hits post-edit (pre-edit baseline: R1-R42 ×18, RT1-RT8 ×2).
3. **Template completeness**: for each pattern `RS6: [status]`, `RT8: [status]`, `RT9: [status]` run a separate fixed-string count per file — `grep -cF '<pattern>' skills/triangulate/phases/phase-1-plan.md` and same for phase-3-review.md — each of the six (3 patterns × 2 files) returns exactly 1. Per-pattern counting is independent of line layout (`grep -c` counts lines, so a combined alternation would under-report if two patterns ever shared a line).
4. **Cross-reference existence**: R43 row's "phase-3 Step 3-5" target exists (`grep -c 'Cross-perspective tradeoff protocol' phases/phase-3-review.md` = 1); C8 bullet's schema fields match the pre-pass paragraph's join keys.
5. **Deployment parity**: `./install.sh` then `diff -q` on all 5 files vs `~/.claude/skills/triangulate/`.
6. **Semantic**: three-expert plan review (this Phase 1) + three-expert code review (Phase 3).

## Considerations & constraints

### Risk: R43 false positives on legitimate widening

Some widenings are the intended feature (a new legitimate consumer added by design, with its own gate). Mitigation in the R43 body: the rule requires isolated security re-review and routes to the Step 3-5 protocol — a deliberately-designed, gated widening passes that review with sign-off recorded; R43 blocks only *unreviewed* widening-as-regression-fix.

### Risk: fail-safe precedence misread as "functionality findings lose"

The protocol's step 1 makes the both-satisfying search mandatory BEFORE any precedence applies, and R43 explicitly states the functionality report is correct as a report. C5's no-inverse-inference clause protects single-perspective functionality findings.

### Risk: findings-index adds friction / drifts from prose

Mitigated: index is declared a non-authoritative tracking aid; mismatch handling reuses the existing return-for-revision contract; schema is minimal (7 fields).

### Non-issue: phase-1 Round 2+ template inheritance is not relied upon

Although phase-1's Round 2+ template has an "All obligations from Round 1 remain in effect" sentence, C8 does NOT rely on it — the sentence's parenthetical names only two blocks (Plan-specific obligations, severity criteria), not the Requirements list, which is an ambiguous parse. All four template locations, including phase-1 Round 2+, receive their own explicit copy of the findings-index bullet.

### Scope contract

- **SC1**: Extending `llm-commands.sh merge-findings` (or a new hook) to consume the json index mechanically — deferred; owned by a follow-up (`TODO(triangulate-r43-rt9-failsafe-lessons): teach merge-findings to consume the json findings index`). This PR only defines the index and the orchestrator-side manual join.
- **SC2**: Mechanical detection hooks for R43 (boundary-predicate diff between rounds) and RT9 (twin-pair detection) — deferred to the Phase-3 AST-infra track (see `project_phase3_ast_infra` memory); both rows mark detection as human-review for now.
- **SC3**: Cross-porting L1/L2/L4 lessons into `simplify` / `test-gen` skills — separate PR, consistent with the #91-#95 series pattern.

## User operation scenarios

**Scenario 1 (L1/L2)**: Round 2 of a security-remediation review. The functionality expert reports "embedded-frame autofill broke after the delivery surface was narrowed in Round 1" and proposes restoring the broad delivery. The orchestrator hits the Step 3-5 protocol: searches for a both-satisfying design, lands on consumer-side origin verification, implements it, and records the searched alternatives. The Round 3 experts run the R43 Round-2+ check and confirm no boundary predicate widened versus Round 2.

**Scenario 2 (L3)**: During the same review, R42 derivation surfaces an uncovered same-class member in a feature outside the audit's 10 findings. Anti-Deferral item 7 makes the same-branch fix the default; the orchestrator declares the essence shift, re-scopes, and fixes it without a per-member user question.

**Scenario 3 (L4)**: A diff adds an origin gate to the typed twin used by unit tests but not to the plain-script production file the runtime loads. The testing expert's RT9 check compares what the manifest loads against what the tests import, flags Critical, and requires the same-diff production edit plus a red-proven sync test.

**Scenario 4 (L5)**: A reviewer finds legacy-format rows that predate a fix. Instead of a desk debate, Anti-Deferral item 6 requires a read-only count against the target environment; the entry records `SELECT count(*) ... → 0` and the accept disposition closes with evidence.

**Scenario 5 (L6/L7)**: Three experts return findings; two point at the same line. The orchestrator's mechanical pre-pass joins the json indices, stamps `convergent: functionality+security`, raises the floor to Major, and fixes it first in the round.
