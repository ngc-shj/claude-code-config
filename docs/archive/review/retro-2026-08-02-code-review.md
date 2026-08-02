# Code Review: retro/2026-08-02-control-scope-and-fixture-adjacency
Date: 2026-08-02
Review round: 1

## Changes from Previous Round

Initial review. Branch is the output of the `retrospect` skill's artifacts-source run:
seven rule extensions (R25, R29, R38, R42, RS3, RT9, RT10), two Pass-3 cross-ports into
`test-gen` and `explore`, one Pass-2 correction inside `test-gen`, a gate-command fix in
`folding.md`, and the retrospective document. No executable code changed.

Local LLM pre-screening (`pre-review.sh code`) and the Step 3-2b expert seeds were both
skipped: the configured backend was unreachable, so all three experts ran full-diff
review. The Security expert's first run died on an API error mid-response and was
relaunched with an explicit context budget for `common-rules.md` (single table rows there
run to tens of thousands of characters); the relaunched run completed.

## Functionality Findings

- **F1 (Major)** `skills/retrospect/pipeline.md:160` — Step 5 restated the gate with the
  same argument-less `check-rule-sync.sh` invocation that `folding.md` was fixed for. The
  fix had been applied to the reported site, not the set (R42 trigger (b)), so a retro run
  reading pipeline.md first reproduces the exact R50 failure the document claims closed.
- **F2 (Major)** `common-rules.md` Recurring Issue Check template — R25/R29/R38 kept
  pre-extension pattern names and `N/A` escape hatches scoped to the old triggers. A
  reviewer holding a TOFU-pin diff answers `N/A — no async state machine` and never reaches
  R38's new clause, defeating the stated purpose of widening it. `check-rule-sync.sh`
  cannot see this: it compares rule IDs, not the parenthetical names or the N/A wording.
- **F3 (Major)** `phases/phase-1-plan.md:158` — lesson 7's defect occurred at plan stage,
  but the phase-1 R29 trigger was still gated entirely on external standards, leaving the
  review moment where the mined defect actually happened unchanged.
- **F4 (Major)** `common-rules.md:327` — R38's new clause cited `(R31)` for a product-facing
  confirmation affordance. R31 is scoped to the reviewing agent's own tool calls
  ("reviewer-agent guidance executed by the orchestrator's own discipline before each tool
  call"), so the pointer sends a reader to the wrong rule.
- **F5 (Minor)** R38's Extended obligations title and procedure were not widened with the row.
- **F6 (Minor)** `phase-2-coding.md:343` — the R25 manual check covered only the presence
  axis that the new sub-clause explicitly calls insufficient.
- **F7 (Minor)** RT10's hook-limitation text still framed boundary adjacency as an
  allow-side-only property, disagreeing with the updated `test-gen` sentence.
- **F8 (Minor, Adjacent)** `settings.json` has no allow entry for the newly prescribed
  repo-relative invocation, so the gate prompts each round.

## Security Findings

- **S-01 (Minor)** `common-rules.md:327` — R38's persisted-state exit, applied to its own
  leading example (a trust-on-first-use pin), describes an in-band user-initiated reset
  that re-establishes on next contact. An on-path attacker triggers the mismatch, the user
  clears it while still on the hostile path, and the pin re-pins the attacker's material.
  The clause satisfied every other stated condition while prescribing the downgrade.
- **S-02 (Minor)** `common-rules.md:350` — RS3's new clause closed its consequence set at
  "type-specific sanitizers no-op", omitting the case where the off-type value reaches an
  *interpreter* (query operator, credential comparison, deep merge) and is assigned that
  interpreter's meaning. RS3's flat `Major` then rates an authentication bypass as Major.
- **S-03 (Minor)** `docs/archive/audit/retro-artifacts-lessons-2026-08-02.md:60` — the RS4
  sign-off stated "eight spans" where the committed file scrubs to 11 across 10 lines, with
  no reproducing command. This is a direct violation of the R29 obligation added in the same
  commit.

RS4 verification returned clean: no personal-identifying data, credentials, secret-shaped
strings, absolute user paths, emails, IPs, URLs, or external repository/product names on
any added line. All 11 scrubber redactions were judged individually and every one is a
false positive of the `[A-Za-z0-9+_=-]{20,}` pass matching hyphenated English compounds.
Prompt-injection residue: no imperative-mood text from the untrusted corpus is reproduced
in the committed document; the claim was checked rather than accepted.

## Testing Findings

- **T-01 (Major)** `test-gen/SKILL.md:112` and the RT10 row — "loosen the predicate on paper
  to the weakest reading a reader might implement" is unbounded and therefore unfalsifiable
  in both directions (always-allow admits every fixture; a hair's loosening admits almost
  none), and `on paper` contradicts obligation 16's "executed, not argued".
- **T-02 (Major)** `test-gen/SKILL.md:112` — no numbered generation obligation required the
  RT10 allow/deny pairing or axis-combination coverage. Obligation 17 presupposed both
  fixtures exist. On pytest / Go / RSpec, where the hook does not run, nothing asked the
  generator for an allow fixture at all.
- **T-03 (Major)** `test-gen/SKILL.md:113` and the RT9 row — the prescribed red-proof did
  not constrain where the append lands. An append inside the pinned construct reddens under
  any containment assertion, so the proof succeeds while the drift shape RT9 exists for (a
  second declaration elsewhere in the twin) stays green.
- **T-04 (Major)** `test-gen/SKILL.md:111` — `git status --porcelain` cannot prove "the tree
  is untouched" in the very case the same sentence describes, since the procedure runs while
  the tree legitimately holds the uncommitted work under test.
- **T-05 (Major)** `test-gen/SKILL.md:111` — the now-primary out-of-repo scratch-copy
  procedure had no subject-binding step. Every bats file in this repo derives the subject
  from the test file's own location with no override, so a mutated out-of-repo copy is never
  executed and the run reports a green whose subject is the wrong file (R50).
- **T-06 (Minor)** the scope caveat's obligation-axis enumeration overstated the manual-only
  set (obligation 9 has an LLM-invoked audit) and omitted the RT10 hook's third grammar.
- **T-07 (Minor, informational)** the corrected gate command in `folding.md` had no
  regression guard.

## Adjacent Findings

F8 (settings.json permission scope) — routed to Security. Resolved without widening the
allow list; see Resolution Status.

## Quality Warnings

None. `merge-findings` was not run (local LLM unreachable); deduplication was performed
manually against the three experts' json indices. No finding was flagged VAGUE,
NO-EVIDENCE, or UNTESTED-CLAIM — every finding carried a file:line and reproducing
evidence, and the three that asserted repository facts (T-05's subject-binding claim, T-06's
obligation-9 hook claim, S-03's redaction count) were independently re-verified by the
orchestrator before being actioned.

## Recurring Issue Check

Each expert returned a full R1-R51 / RS1-RS6 / RT1-RT11 pass routed via
`common-rules.digest.md` (terminator `## END-OF-DIGEST` confirmed present by all three).
Rules that fired, with the finding that carries them:

### Functionality expert
- R3 (Incomplete pattern propagation): F1, F3, F6 — folding stopped at the compact row
- R12 (Enum/action group coverage gap): F2 — the template is this repo's label map
- R18 (Config allowlist synchronization): F8
- R20, R21, R22, R30, R34, R41, R43, R44, R50: Checked
- R25: F6 · R29: F3, F4 · R31: F4 · R38: F4, F5 · R42: F1 · R49: F1 · RT10: F7
- All other R/RS/RT rows: N/A (prose-only diff, no runtime, schema, or UI)

### Security expert
- R3, R18, R20, R21, R31, R34, R41, R43, R44, R50: Checked
- R29: S-03 · R38: S-01 · RS3: S-02
- RS4: Checked — full grep log recorded, clean
- RS5: Checked — asymmetry with R38's new clause noted under S-01
- All other rows: N/A

### Testing expert
- R3, R18, R21, R29, R41, R44: Checked
- R42: T-02, T-06 · R47: T-03 · R49: T-03 · R50: T-05
- RT7: T-01, T-03 · RT9: T-03 · RT10: T-01, T-02
- RT2: Checked — every recommended fix is a prose revision; only T-07 warranted a test
- All other rows: N/A

## Environment Verification Report

N/A — no environment constraints were declared in Phase 1 (this branch entered at Phase 3;
there is no Phase 1 plan). Gates actually executed, each unpiped and read for its own exit
status (R44), with counts quoted rather than a bare zero (R50 clause ii):

- `bash hooks/check-rule-sync.sh skills/triangulate` → exit 0,
  `OK: R1-R51 / RS1-RS6 / RT1-RT11 consistent across all sync points`. The skill-directory
  argument is load-bearing and was verified so: the same hook invoked bare returns exit 0
  against the installed tree while the repo digest is stale.
- `bats tests/` → 1006 tests collected from 30 files, 1003 ok, 3 not ok, exit 1.
  The 3 failures are byte-identical on a clean `main` checkout (verified by stashing this
  branch and re-running the two affected files) and are macOS/BSD portability bugs in test
  code, not defects in any hook. Enumerate them with
  `bats tests/ 2>&1 | grep '^not ok'`; identify them per file with
  `bats tests/check-deny-only-guard.bats 2>&1 | grep '^not ok'` and the same for
  `tests/retro-prescreen.bats`:
  `tests/check-deny-only-guard.bats:339` uses GNU-only `head -n -4` (the failing assertion
  is at `:342`); `tests/retro-prescreen.bats` file-ordinals **23 and 24** — global
  `not ok 802` / `803`, source lines `:457` and `:482`, failing at the `.candidates[].path`
  comparison on `:475` and `:512` — compare a hook-emitted realpath (`/private/var/...`)
  against an unresolved fixture path (`/var/...`). The user elected to fix these in a
  separate PR. This branch adds no new failure.
- The new test `retrospect: the rule-sync gate is prescribed with an explicit skill
  directory` appears in the run as `ok 623`.

## Resolution Status

### F1 Major — argument-less gate survived in pipeline.md
- Action: rewrote Step 5's gate to `bash hooks/check-rule-sync.sh skills/triangulate` and
  stated why the argument is load-bearing. Added a bats regression guard so a revert reds.
- Modified file: `skills/retrospect/pipeline.md:160`, `tests/install.bats:326`

### F2 Major — Recurring Issue Check template unreachable for the widened rules
- Action: widened all three template lines — R25 gains the access-scope axis in its Checked
  branch, R29's N/A now requires "no codebase-derived numbers", R38's N/A now requires "no
  persisted fail-closed state" and names the four member kinds.
- Modified file: `skills/triangulate/common-rules.md:627,631,640` (post-change line numbers;
  the Extended-obligations Part 3 insertion moved the template block down by nine lines)

### F3 Major — phase-1 R29 trigger gated on external standards only
- Action: added a `Derived-claim check (R29)` bullet requiring the reproducing command
  beside any quantitative claim used as justification, re-run when a later round restates it.
- Modified file: `skills/triangulate/phases/phase-1-plan.md:158`

### F4 Major — R38 cited R31 for a product-facing confirmation affordance
- Action: dropped the `(R31)` pointer, stated the requirement directly, and recorded that
  the catalog has no rule governing product-side confirmation UX today.
- Modified file: `skills/triangulate/common-rules.md:327`

### F5 Minor — R38 Extended obligations not widened with the row
- Action: retitled the section and added Part 3 (persisted fail-closed wedge), six steps
  covering enumeration, the missing clearing path, the explicit exit, re-establish-not-
  disable, the out-of-band requirement for anti-impersonation pins, and the legitimate-
  rotation question.
- Modified file: `skills/triangulate/common-rules.md:534`

### F6 Minor — phase-2 R25 check covered only the presence axis
- Action: appended the process/lifecycle enumeration and the shared-availability-window
  requirement, and noted that a round-trip test in the owning process passes on the defect.
- Modified file: `skills/triangulate/phases/phase-2-coding.md:343`

### F7 Minor — RT10 hook-limitation text framed adjacency as allow-side-only
- Action: changed "the paired allow fixture" to "EITHER fixture" in the RT10 row, and added
  the symmetric re-check to the phase-2 pre-step description.
- Modified file: `skills/triangulate/common-rules.md:368`, `phases/phase-2-coding.md:419`

### F8 Minor — no allow-list entry for the prescribed invocation
- Action: **deliberately not fixed by widening `settings.json`.** A
  `Bash(bash hooks/check-rule-sync.sh *)` entry is cwd-relative and would auto-approve
  executing whatever `hooks/check-rule-sync.sh` exists in any repository the session opens —
  a wider grant than a once-per-round gate is worth (R43 direction). Recorded the decision
  and the reasoning in folding.md, including that the installed form accepts the same
  argument and is already allow-listed but runs the installed linter against repo content.
  Worst case: one approval prompt per retro round. Likelihood: every round. Cost to fix
  properly: an anchored per-repo permission mechanism that does not exist today.
- Modified file: `skills/retrospect/folding.md:120`

### S-01 Minor — R38's persisted-state exit prescribed the TOFU downgrade path
- Action: added the out-of-band requirement for anti-impersonation pins — not reachable
  from inside the failing ceremony, never a dismissable step in the protected flow,
  re-established material verified through an independent channel — with the reason stated
  (the mismatch prompt is the attacker's most likely arrival point) and the RS5 interaction
  named. Mirrored as step 5 of the new Extended obligations Part 3.
- Modified file: `skills/triangulate/common-rules.md:327,534`

### S-02 Minor — RS3 omitted the interpreter-sink consequence class
- Action: named the second consequence class explicitly, required BOTH be enumerated,
  routed the reviewer action through R42 sink-set derivation, and raised the severity cell
  to `Major; Critical when an unvalidated off-type value can reach a query operator, a
  credential comparison, or an object-merge/assign sink`. Digest regenerated.
- Modified file: `skills/triangulate/common-rules.md:350`

### S-03 Minor — RS4 sign-off carried an unreproducible count
- Action: re-derived the figure (11 spans across 10 lines, 7 distinct strings), corrected
  the sentence, listed the distinct strings, and shipped the reproducing command — which is
  what R29's new clause requires of exactly this kind of claim.
- Modified file: `docs/archive/audit/retro-artifacts-lessons-2026-08-02.md:60`

### T-01 Major — obligation 17's adjacency check was unfalsifiable and contradicted 16
- Action: replaced "loosen on paper to the weakest reading" with an enumeration of ONE-STEP
  loosenings read off the code (exact→prefix→substring, normalised→raw, dropping a conjunct,
  removing canonicalisation, widening the compared container by one level), flipped the pass
  condition to the discriminating direction (at least one must make the deny fixture PASS),
  and required it be run as a real mutation under obligation 16. Stated that a wholesale
  force-true does not discharge it. Applied to both the RT10 row and the test-gen obligation.
- Modified file: `skills/triangulate/common-rules.md:368`, `skills/test-gen/SKILL.md:112`

### T-02 Major — pairing and axis combinations were never a generation obligation
- Action: restructured obligation 17 into (a) pairing — never emit a deny-only guard suite,
  stated as a generation obligation on every framework with the hook's three-grammar limit
  named; (b) adjacency on both sides; (c) axis combinations with unclaimed cells declared.
- Modified file: `skills/test-gen/SKILL.md:112`

### T-03 Major — obligation 18's red-proof was non-discriminating
- Action: relocated the defect statement from "containment in general" to "the needle is
  narrower than the scope of the invariant claimed", spelled out that widening to the full
  construct closes in-construct drift only, required one of three closed forms (full
  construct with the outside declared unclaimed / checksum over a region drawn to include
  every override site / whole-file equality), and required the red-proof append to land
  OUTSIDE the pinned region. Applied to both the RT9 row and the test-gen obligation.
- Modified file: `skills/triangulate/common-rules.md:367`, `skills/test-gen/SKILL.md:113`

### T-04 Major — the restore proof asserted a predicate that is false by construction
- Action: replaced "prove the tree is untouched" with a before/after comparison against a
  pre-mutation `git status --porcelain` snapshot, and stated why "the tree is clean" is the
  wrong predicate here.
- Modified file: `skills/test-gen/SKILL.md:111`

### T-05 Major — the scratch-copy procedure had no subject binding
- Action: added an explicit bind-the-subject step before reading the colour: use a runner
  path override where one exists, else copy the whole tree to scratch or mutate in place
  having first committed or stashed; and prove the mutant is what ran via a marker only it
  can emit. Named the failure as R50.
- Modified file: `skills/test-gen/SKILL.md:111`

### T-06 Minor — scope caveat overstated the manual-only set
- Action: scoped the claim to the numbered obligations 11-18, named obligation 9's
  LLM-invoked audit as the reason for that scoping, corrected the RT10 hook's grammar count
  to three, and re-pointed the sub-clause references to 17(a)/17(b)-(c).
- Modified file: `skills/test-gen/SKILL.md:152`

### T-07 Minor — no regression guard on the corrected gate command
- Action: added `tests/install.bats` test asserting both retrospect files prescribe the
  gate with its skill-directory argument and that no bare `bash … check-rule-sync.sh`
  invocation survives. Reworded folding.md's counter-example so it no longer spells a
  runnable bare invocation, which is what makes the invariant mechanically checkable.
  **Red-proved per RT7 shape (g), one mutant per assertion, each attributed**: removing the
  argument from pipeline.md reds the positive assertion at `install.bats:337`; appending a
  bare invocation to folding.md while leaving the correct one intact reds the negative
  assertion at `install.bats:345`. The first mutation attempt did not actually apply — the
  suite stayed green — and was caught by verifying the mutant was present before reading the
  result rather than after.
- Modified file: `tests/install.bats:326`, `skills/retrospect/folding.md:114`

## Anti-Deferral

One finding is recorded as accepted rather than fixed: **F8**, with the Worst case /
Likelihood / Cost-to-fix quantification stated in its Resolution Status entry above.

Two items outside this branch's scope are recorded rather than deferred silently:
- The three pre-existing macOS/BSD bats failures, identical on `main`, which the user
  elected to fix in a separate PR.
- The scrubber's `[A-Za-z0-9+_=-]{20,}` false-positive rate, whose fix trades away UUID
  redaction and therefore needs its own change with a red fixture. Reasoning recorded in
  the retrospective document.
