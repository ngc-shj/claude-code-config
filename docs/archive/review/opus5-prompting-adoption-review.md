# Plan Review: opus5-prompting-adoption

Date: 2026-07-26
Review rounds: 2 (see Round 2 section at the end)

## Changes from Previous Round

Initial review.

## Pre-screening (local LLM, gpt-oss:120b via pre-review.sh)

Two Minor findings, both accepted and fixed before expert review:

- **Scope clarification** — R42 listed root `CLAUDE.md` as an always-loaded member
  but the plan edited only `global/CLAUDE.md`; whether the root file needs a
  parallel update was unstated. Fixed: root `CLAUDE.md` is now explicitly a
  **sweep member but not an edit target**, because duplicating global content there
  double-loads it in this repo's own sessions (`tests/install.bats:222`, commit #106).
- **C3 resolution mechanism** — the placeholder-fill path was undefined. Fixed by
  first *verifying* no shell path exists (`settings.json` has no `"model"` key; no
  `ANTHROPIC_MODEL`-style env var is exported) and then pinning the honest
  mechanism: the orchestrating model fills it from session context, writing `不明`
  when it cannot.

## Functionality Findings

Four Minor findings. The expert independently re-verified every repo claim the plan
made — all `tests/install.bats` line numbers (222/233/243/253/268), `SKILL.md:131`,
`global/CLAUDE.md` section order, `install.sh:79` delivery, and the R42 five-member
set — and found them accurate, plus confirmed no sixth always-loaded member exists.

- **F-01 (Minor, R41)** — C3's resolution mechanism had no checkable acceptance
  path: a declared capability with no backing verification. **Accepted** — C3 now
  pins a literal placeholder token `{{context_window}}`, so the *shape* is
  grep-assertable even though the *fill* is not.
- **F-02 (Minor)** — C4's grep target for C2 was underspecified ("delegation
  criteria" is not a literal string), unlike C1's clean heading anchor.
  **Accepted** — C2 now pins the literal substring `your own work` as C4's anchor.
- **F-03 (Minor)** — NFR1's before/after check had no recorded baseline.
  **Accepted** — 365 words measured and recorded.
- **F-04 (Minor, informational)** — SC1's skill list not independently verified as
  exhaustive. **Acknowledged, no change**: SC1's list is illustrative and not
  load-bearing, since `skills/**` is a non-member of the always-loaded set
  regardless of which skills appear in the list.

Notably the expert also **refuted** one of the plan's own stated risks: the plan
flagged `install.bats:268` as needing a re-read in case it keys off a line count or
section list. It does not — it only checks for absence of `@RTK.md`,
`gpt-oss:120b`, `telemetry` and presence of two pointers. No conflict exists.

## Security Findings

One Major, two Minor. No Critical, so no escalation.

- **F-01 (Major)** — C2's R21 safeguard was a *wording-presence* check, not a
  semantic one. A sentence can contain "your own" and still nudge toward trusting a
  subagent's report, and the plan itself conceded the forbidden-pattern regex is
  "not grep-decidable alone". Since `global/CLAUDE.md` loads every session, a
  slightly-wrong wording is a standing, silent downgrade of R21 (Critical,
  silent-regression-risk) across every project using this config.
  **Accepted** — C2's acceptance criteria now require a mandatory side-by-side read
  of the final sentence against R21's actual row before the edit is accepted, and
  spell out the distinction: forbidden is *spawning an extra agent to re-check
  finished work*, never *reading a delegate's output critically*.
- **F-02 (Minor)** — the NFR3 five-file sweep is asserted by the plan but not shown
  executed in it. **Accepted as a Phase 2 obligation**; the expert independently
  swept `rules/common/testing.md` and `coding-style.md` and found them clean.
- **F-03 (Minor, [Adjacent])** — C3's fail-safe direction is correct (suppress/mark
  unknown rather than guess); reliability of the model's self-fill is a
  functionality concern, not security. Routed to functionality, which raised the
  same point as its F-01.

Verified clean by the security expert: **RS4** (no PII/secrets in the plan file;
it is untracked and safe to commit), gate liveness (nothing touches `hooks/*.sh`,
`settings.json` wiring, or `install.sh` copy logic, so none of the #106
silently-dead-gate mechanisms are implicated), prompt-injection surface (no
untrusted content enters the always-loaded channel), and the Anti-Deferral entries
(VC1/SC1–SC4 each carry a real cost justification and owner; SC1's carve-out is
"correctly drawn and does not reopen the #106 class").

## Testing Findings

Four Major, two Minor, two verified-no-finding. This expert produced the round's
highest-value results by checking facts rather than reasoning about the plan.

- **F-01 (Major, RT7)** — the mutation-proof named the safety property ("scratch
  copy") but no target path or command, leaving two implementers free to satisfy it
  non-equivalently, one of them by editing the tracked file. **Accepted** —
  C4 now carries a concrete command block that mutates only the `$STAGING` copy
  `setup()` already makes.
- **F-02 (Major)** — no residue check after the mutation proof, unlike this repo's
  own R21 precedent that a "restored" claim is never accepted as proof.
  **Accepted** — `git diff --stat global/CLAUDE.md` is now an acceptance criterion.
- **F-03 (Minor, RT8)** — the `[ "$status" -eq 0 ]` guard was only implied by
  "follows the shape of `install.bats:243`". **Accepted** — now an explicit content
  obligation, since a skimming implementer could copy the grep without it.
- **F-05 (Major, RT8)** — C3's bare negative grep passes vacuously if the file is
  renamed or deleted. **Confirmed by execution**: `! grep -q PATTERN missing-file`
  exits 0, so `!`-inversion reports PASS. **Accepted** — C3 now uses a paired
  `[ -f ]` + positive + negative triple.
- **F-06 (Major)** — C3 had *no* natural bats home, because `install.bats`
  `setup()` explicitly skips staging `skills/` while `install.sh:225-235` does
  install them in production. The plan had deferred this to Phase 2 as an open
  condition despite it being checkable immediately. **Confirmed by reading
  `tests/install.bats:32`.** **Accepted** — resolved now as `SC5` (source-only
  grep, deliberately), with the C1/C2 asymmetry justified rather than left as a
  Phase-2 accident.
- **F-08 (Minor)** — the green-before baseline had no command and no go/no-go rule
  for an already-red suite. **Accepted** — baseline measured (790 passing, 0
  failing), commands and the halt-and-file-separately rule recorded.
- **F-04, F-07 (verified, no finding)** — the installed-copy-vs-source choice for
  C4 matches all nine existing delivery tests and is correctly reasoned; VC1's
  Anti-Deferral precedent citation is accurate, and the cheaper proxy a reviewer
  would suggest (forbidden-pattern grep) is already in the plan. F-07 did ask
  whether those patterns are bats-asserted or reviewer-checked — now stated
  explicitly as reviewer-checked, with the reason.

## Adjacent Findings

- Security F-03 → functionality (C3 self-fill reliability). Converged with
  functionality F-01; both resolved by the pinned `{{context_window}}` token.

## Quality Warnings

None. No finding was flagged VAGUE / NO-EVIDENCE / UNTESTED-CLAIM; the two
highest-severity testing findings (F-05, F-06) arrived with reproduction steps and
were independently re-confirmed by the orchestrator before acceptance.

## Perspective convergence

C3's placeholder mechanism was flagged by all three experts from different angles
(functionality R41 / security fail-safe direction / testing vacuous-grep). Per the
convergence severity signal, the merged item was treated as the round's second
priority after security F-01 and received the most substantial rewrite.

## Recurring Issue Check

### Functionality expert

- R1–R20: N/A — no application code; prompt-text and skill-doc edits only
- R21: Checked — no issue; plan correctly distinguishes orchestrator-verifies-delegate (preserved) from delegate-verifies-orchestrator (C2 clause c)
- R22–R33: N/A — no runtime/hook logic touched
- R34: Checked — no issue; VC1 and SC3 both model Anti-Deferral correctly
- R35–R40: N/A
- R41: Finding F-01 — C3 declared capability without checkable backing path
- R42: Checked — member set independently recomputed, matches the plan's five members, no sixth found
- R43–R46: N/A

### Security expert

- R1–R17: N/A
- R18: Checked — no allowlist/safelist file touched
- R19, R20: N/A
- R21: Finding F-01 (Major) — wording-presence check is not a semantic guarantee
- R22–R33: N/A
- R34: Checked — no issue; each deferral carries cost justification and owner
- R35–R41: N/A
- R42: Checked — derivation logic correct; F-02 covers execution completeness
- R43–R46: N/A
- RS1: N/A — no credential comparison
- RS2: N/A — no new route
- RS3: N/A — no new HTTP boundary
- RS4: Checked — no PII/secrets in the plan file
- RS5: N/A — no externally-sourced crypto parameter
- RS6: N/A — no string-escaping code

### Testing expert

- R1–R20: N/A — no application code
- R21: Checked — no subagent-authored code accepted without re-run in this plan
- R22–R31: N/A
- R32: N/A — no long-running runtime artifact
- R33: N/A
- R34: Checked — VC1 and SC3 model Anti-Deferral correctly
- R35–R41: N/A
- R42: Checked — five-member derivation independently verified
- R43: N/A
- R44: Checked — none of C1–C4's acceptance commands pipe a gate's exit status through a filter
- R45, R46: N/A
- RT1–RT6: N/A
- RT7: Findings F-01, F-02 — mutation procedure under-specified, residue check missing
- RT8: Findings F-03 (C4, minor gap in explicitness), F-05 (C3, real vacuous-pass gap)
- RT9: N/A

## Round 1 disposition summary

| Finding | Severity | Disposition |
| --- | --- | --- |
| Sec F-01 | Major | Fixed — semantic R21 side-by-side read now required |
| Test F-01 | Major | Fixed — concrete mutation command block added |
| Test F-02 | Major | Fixed — residue check added to acceptance criteria |
| Test F-05 | Major | Fixed — paired positive+negative+existence assertions |
| Test F-06 | Major | Fixed — resolved as SC5, no longer a Phase-2 contingency |
| Func F-01 | Minor | Fixed — `{{context_window}}` token pinned |
| Func F-02 | Minor | Fixed — `your own work` pinned as C4's anchor |
| Func F-03 | Minor | Fixed — 365-word baseline recorded |
| Test F-03 | Minor | Fixed — status guard made an explicit obligation |
| Test F-08 | Minor | Fixed — baseline measured, go/no-go rule stated |
| Sec F-02 | Minor | Accepted as Phase 2 obligation (expert pre-swept two files clean) |
| Func F-04 | Minor | No change — SC1 list is illustrative, not load-bearing |
| Sec F-03 | Minor | Merged into Func F-01 |

---

# Round 2 (incremental)

Date: 2026-07-26

## Changes from Previous Round

All ten accepted Round 1 findings were applied to the plan (see the Round 1
disposition table). Round 2 reviewed those fixes for correctness, regression, and
newly-introduced gaps.

## Functionality Findings (Round 2)

- **F-03R2 (Major) — real arithmetic error in the orchestrator's own text.**
  The new baseline subsection read "365 + C1 (≤60) + C2 (≤45) = ≤470 words, within
  the ~120-word net-addition budget" — conflating the post-change *total* with the
  *net addition* NFR1 actually bounds. 470 is not within 120 by any reading.
  **Confirmed and fixed**: net addition = ≤105 words within ~120; the ≤470 total is
  recorded for the `wc -w` diff but is explicitly not what NFR1 bounds.
- **F-05R2 (Minor) — SC5's rationale overclaimed.** I had written that staging
  `skills/` "would slow every test in the file". `setup()` already stages
  individual files selectively (`global/RTK.md`, `global/model-routing.md`), so one
  more `cp` is not a whole-tree cost. **Fixed**: the honest reason is *precedent*
  (no existing test stages skill-internal files; doing so couples `install.bats` to
  paths inside `skills/`), not speed. SC5's decision stands on corrected grounds.
- **F-01 verified closed** — the `{{context_window}}` pin makes the shape
  assertable. Expert noted this relocates rather than eliminates the R41 gap and
  asked for an explicit label; **added**: fill-correctness is now stated as
  `VC1`-class `blocked-deferred`.
- **F-02 verified closed and stable** — expert grepped the repo and confirmed the
  anchor string had zero pre-existing occurrences, so no collision risk.
- **F-04** — pushback considered and declined by the expert itself; SC1's list is
  illustrative, not load-bearing. No change.

## Security Findings (Round 2)

- **F-01 (Major, carried over, escalated) — accepted.** The expert argued
  adversarially that Round 1's mitigation was still weak: C2's anchor was a 3-word
  fragment (`your own work`) plus an unenforceable "read it and judge" step, while
  the plan elsewhere *demoted* forbidden-pattern regexes precisely because
  unenforceable checks are weak. Applying the weaker treatment to the one clause
  that gates R21 (Critical) was inconsistent in stakes. **Accepted in full** — the
  anchor is now a full locked sentence, `Delegate a whole slice of work, not the
  checking of work already done.`, grepped verbatim by C4. The sentence never uses
  the word "verify" and states the positive shape, so it cannot be read as "don't
  verify". Residual semantic risk recorded as `SC6` rather than left implicit.
- **F-04 (Minor) — accepted.** The mutation procedure named two run mechanisms
  without pinning one. **Fixed**: exactly one is now permitted (scratch repo tree),
  with the alternatives explicitly disallowed.
- **F-05 (Minor, [Adjacent]) — accepted as a separate issue.** `install.bats`'s
  blanket `skills/` skip means `skills/security-scan/SKILL.md` delivery is also
  untested — the #106 silently-dead-delivery class, never extended to skills.
  Pre-existing, not caused by this plan. **Recorded as `SC7`** with a named owner
  (separate future issue, staging only `security-scan/` to preserve SC5's rationale)
  rather than silently skipped, per R34.
- Verified clean again: RS4 on both the plan and this review file (all
  credential-pattern hits were false positives on "token" as in token-count and on
  the `{{context_window}}` placeholder); and the C4 mutation procedure cannot reach
  the tracked or installed config — the expert read `block-sensitive-files.sh` in
  full and confirmed the `git diff --stat` residue check is the correct backstop.

## Testing Findings (Round 2)

This expert reviewed a **stale snapshot** — the plan changed mid-review, and its
report quotes text that had already been replaced. It was re-sent the current state,
but its verdict still reasons about the older wording. Findings triaged on merit:

- **F-R2-01 (Major) — REFUTED by execution, not accepted.** The expert argued the
  scratch-tree mechanism is a dead end because `REPO_DIR="$(cd "$(dirname
  "$BATS_TEST_FILENAME")/.." && pwd)"` is a bare assignment that ignores an
  exported `REPO_DIR`. That premise is true and the conclusion does not follow: the
  procedure never uses an env override. Copying `tests/install.bats` *into* the
  scratch tree makes `$BATS_TEST_FILENAME` resolve there, so `REPO_DIR` recomputes
  to the scratch root by itself. **Proven twice** by running the existing
  `Rules Layer` test against a mutated scratch tree — it went red naming its own
  grep, with `git diff` clean and no tracked file edited. The objection is recorded
  in the plan anyway, because it is the natural first reading of line 7.
- **F-R2-03 (Major) — CONFIRMED and fixed.** My SC5 wording claimed C3's delivery
  was "already covered by the generic skill-install loop". Verified false:
  `grep -rn 'skill' tests/install.bats` returns two comments and nothing else, and
  no test in the suite asserts anything reaches `~/.claude/skills/`. **Fixed** —
  the claim is replaced with the accurate statement that the loop is production
  code with zero test coverage, which C3 neither regresses nor gets credit for.
- **F-R2-05 (Minor) — accepted.** C2's mandatory manual R21 read was discoverable
  only from C2's contract text, so the Testing-strategy table could be misread as
  "C4 covers it". **Fixed**: the table row now states the manual obligation.
- **F-R2-02 (Minor) — accepted.** `grep -v` strips a line, not a section, so C1's
  run leaves an orphaned paragraph; harmless here since both anchors are
  single-line and single-occurrence, but a bad template to generalize. **Noted in
  the plan** as a caveat against over-generalizing the technique.
- **F-R2-04 (verified, no finding)** — the 791 after-state was independently
  confirmed by a static `@test` count of exactly 790 across `tests/*.bats`, matching
  my measured run, plus a check that the suite contains no dynamic test generation
  that could make static and runtime counts diverge. Two independent methods agreeing
  is stronger than either alone.

## Adjacent Findings (Round 2)

- Security F-05 → testing (coverage prioritization). Routed and resolved as `SC7`.

## Quality Warnings (Round 2)

- Testing expert's report was produced against a superseded revision of the plan
  and self-described mid-report uncertainty about which text it was quoting. Not a
  VAGUE/NO-EVIDENCE flag — its two Major findings were specific and checkable, and
  checking them is exactly what separated the refuted one from the confirmed one.

## Round 2 disposition summary

| Finding | Severity | Disposition |
| --- | --- | --- |
| Sec F-01 | Major | Fixed — full locked sentence replaces the 3-word fragment; SC6 records residual risk |
| Test F-R2-03 | Major | Fixed — false coverage claim removed after verification |
| Func F-03R2 | Major | Fixed — NFR1 arithmetic corrected |
| Test F-R2-01 | Major | **Refuted** — mechanism proven by execution twice; objection recorded in-plan |
| Sec F-04 | Minor | Fixed — one mutation mechanism pinned |
| Sec F-05 | Minor | Accepted as SC7 (separate future issue) |
| Func F-05R2 | Minor | Fixed — SC5 rationale corrected to precedent, not speed |
| Test F-R2-05 | Minor | Fixed — table row states the manual R21 obligation |
| Test F-R2-02 | Minor | Fixed — caveat added against generalizing the strip technique |
| Func F-01 | — | Verified closed; VC1-class label added |
| Func F-02 | — | Verified closed; anchor uniqueness confirmed |
| Test F-R2-04 | — | Verified, no finding (790 static count matches measured run) |
