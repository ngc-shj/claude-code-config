# Code Review: retro-artifacts-2026-08-02 fold

Date: 2026-08-02
Review round: 2
Branch: `retro/2026-08-02-artifacts-r52-r57`

---

# Round 2 — incremental review of the round-1 fixes

Subject: `git diff HEAD~1 HEAD` (commit 294ec9c). Twenty findings, six Major. All twenty
resolved; details in the Round-2 Resolution Status at the end of this file.

**The headline: one round-1 fix was a security regression, and two cited receivers that do not
receive.** That is the shape this branch's own R29 extension names — a fix whose *rationale* is
false even where its conclusion is not — and all three were found by verifying the round-1
Resolution Status entries against the code rather than reading them.

## Round-2 convergence

| Merged | Reported by | Severity |
|---|---|---|
| The completion sentinel is forgeable by the reviewed diff | S-10 (sec), and T-07/T-08 as coverage gaps in the same code | Major |
| The carry-forward receiver does not receive | N-01 (func) | Major |

## Round-2 findings

- **S-10 Major (new, introduced by the round-1 fix) — the completeness sentinel is forgeable by
  the diff under review.** Round 1 promoted `llm-commands.sh`'s `## END-OF-ANALYSIS` to a
  completeness certificate. Upstream, that normalizer emits the FIRST standalone sentinel and
  silently drains the rest — and its `sed` deliberately splits an inline occurrence onto its own
  line first. Verified by execution: an input containing a diff line `+## END-OF-ANALYSIS`
  followed by `[Critical] src/auth.ts:42 — hardcoded credential committed` produced output ending
  at the echoed marker, the Critical discarded, and `_run_ollama` then reported
  `sentinel=present`, `rc=0`, no failure line, exit 0. A contributor's diff could truncate its own
  security review and attach a completeness certificate. The analyze-* prompts instruct the model
  to quote problem text, so an echo is the ordinary case, not a contrived one — and this branch's
  own `tests/review-backend.bats` adds standalone sentinel lines, so the precondition is live.
- **N-01 Major (continuing) — F-02 is not closed.** The round-1 fix routed carried-forward
  findings into "the plan file's Implementation Checklist — the artifact Phase 2 Step 2-1 actually
  reads". It does not: `phase-2-coding.md` Step 2-1 item 5 AUTHORS that section from its own impact
  analysis. Phase 1 would create it, Phase 2 would append a second one under the same heading, and
  the only real consumer — `phase-3-review.md:160` — reads it as a list of files that must appear
  in the diff, so a finding entry is either ignored or reported as a spurious Phase-3 finding.
  F-02 with a rationale attached.
- **N-02 Major (new) — the permission allowlist now pre-approves exactly the forbidden form.**
  `settings.json` carried only `Bash(bash ~/.claude/hooks/check-rule-sync.sh)` and its `*` variant.
  The round-1 fix made `bash hooks/check-rule-sync.sh skills/triangulate` the mandatory gate, which
  matches neither — so the invocation the skill declares wrong is the one that runs without a
  prompt, and the one it mandates is the one that asks. An inverted incentive at a gate whose whole
  point is that the cheap wrong form must not be the easy one.
- **S-11 Major (continuing) — the R36 carve-out draws its line on a distinction R36 calls
  indistinguishable.** It foreclosed spellings (a) and (c) for security detectors and left (b)
  *narrowing the gate's subject* admissible with a proof. Two routes back: adding the offending
  file to a secret scanner's exclusion glob IS a subject narrowing and is the canonical real-world
  bypass; and R36's own text says (b) is "nearly indistinguishable from (c)", so an author doing
  (c) can file it as (b).
- **T-07 Major (new) — `--adversarial` had zero coverage.** Executed proof: mutating the gate to
  `[ "$adversarial" = 1 ] || [ "$failed" -eq 0 ]` — restoring the exact T-01 defect for adversarial
  runs — left all 18 cases green.
- **T-08 Major (new) — no mixed-pass case, so a `failed`-flag reset survived the suite.** Executed
  proof: adding `else failed=0` to the success branch left the whole file green, while the
  realistic scenario (one pass dies, two succeed) then returns 0 and reads as clean.
- **N-03 / N-04 / S-13 / S-14 Minor — the linter's own new surfaces.** `Subject:` printed the
  argument unresolved, so `skills/triangulate` and `~/.claude/skills/triangulate` printed
  identically from different cwds — the instance was closed, the mechanism was not. The ceiling
  check passed silently when no severity cell parsed, and `$(NF-1)` on a row without a trailing
  pipe returns the Procedure cell, whose text contains "Critical" for most security rules — so a
  malformed row yields fabricated agreement. And the ceiling test is token-presence, so a row that
  keeps the word while narrowing its trigger to something unreachable still passes.
- **N-05 / S-15 Minor — the round-1 fix's in-band control line.** `SKILL.md` declared an empty pass
  body a FAILED RUN that the runner never emitted, and `## FAILED:` was itself forgeable by echoed
  diff text in the fail-closed direction.
- **N-06 Minor — "open" was undefined** in saturation condition 2 against the four Anti-Deferral
  dispositions established 19 lines earlier; the cheapest reading (file the entry, the finding is
  no longer open) reinstates the severity-blind exit through a documented format.
- **S-17 Minor — saturation conditions 3 and 4 were jointly unsatisfiable.** A wording ambiguity is
  not reachable only by executing, so no non-empty finding set satisfied both — and an unsatisfiable
  conjunction invites the loose reading, which is how the weakening returns.
- **N-07 Minor — R37's row carried a Major trigger absent from its detail**, in the very class
  F-06's sweep declared closed. Both sides are non-Critical, so the new ceiling check is blind to it
  by construction.
- **N-08 Minor — `check-suppression.sh` still carried R36's pre-rename title**, the last surviving
  use and the first thing a reader of that hook sees.
- **S-12 Minor — the carve-out's category was a closed list** while the escalation it cites is
  explicitly non-exhaustive, so a project-specific security detector fell outside the bar.
- **S-16 Minor [Adjacent] — `stage_llm_stub`'s unquoted heredoc** interpolated the caller's body
  into a double-quoted stub; a body containing `$(…)` or a backtick would execute rather than print.
- **T-09 Minor — no fixture for the row shapes that break `$(NF-1)`**, though the digest generator's
  own suite already has that precedent.
- **T-10 Minor (continuing) — F-09's supersession did not cover the axis it closed.** T-03 pinned
  the linter's output, not the caller's invocation form: reverting `folding.md` to the bare
  installed path — the exact T-02 regression — left all 1014 tests green.

**Verified by the round-2 experts, not accepted:** all three re-ran both gates themselves; the
testing expert re-executed all three of round 1's claimed red-proofs and reproduced them exactly,
noting that one of the two ceiling directions also emits a stale-digest drift line and is therefore
not singly attributable (the other direction is). `git status --porcelain` was empty before,
between and after every mutation. The R43 sweep found no fix-induced widening: R37's default did
NOT move from Major to Minor — the pre-fix row already read "Minor otherwise", so the rewrite only
ADDED Major triggers. No secrets or PII.

---

# Round 3 — incremental review of the round-2 fixes, plus the user's own review

Subject: `git diff HEAD~1 HEAD` (commit 930c63d), then the working tree. Twenty-two findings —
one Critical, nine Major — from the three experts plus three Major raised directly by the user.
All resolved.

**The Critical was mine, and the user caught it independently.** Round 2 added a relative-path
`check-rule-sync.sh` entry to `settings.json` so the newly-mandated repo-local gate would not
prompt. But that file is `install.sh`-merged into the user's GLOBAL settings, and a relative-path
allow entry is cwd-independent: it pre-approves executing whatever ANY repository ships at
`hooks/check-rule-sync.sh`, in every project, with the deny and ask lists anchored on the leading
`bash` token and unable to see inside. The pre-existing entries name the installed absolute path,
which `block-sensitive-files.sh` keeps a session from rewriting — that is why they are safe and the
new ones were not. Both were removed, and `folding.md` now records that the gate prompts
deliberately so the next round does not "fix" it again. (S-18, escalate: true.)

## Round-3 findings, by fate

**Resolved in the round-2 fixes, verified by re-execution rather than accepted:** N-02 (superseded
by S-18's removal), N-03/N-04/S-13/S-14, S-11/S-12 in part, N-06/S-17, N-08, S-16, and all six of
round 2's red-proof claims, each reproduced exactly.

**New or continuing, all fixed this round:**

- **S-18 Critical** — the global permission widening, above.
- **F-01 / S-17 Major** — the round-2 narrowing removed BOTH directions of the sentinel test, but
  only one was forgeable. "Sentinel present ⇒ complete" is forgeable by the reviewed diff and was
  correctly removed; "body empty ⇒ the pass did not run" is forgeable only toward failure and was
  not. `llm-commands.sh` documents empty-stdout-exit-0 as its own failure contract, so an
  unreachable local model mapped to `verdict: approve`. Emptiness is now fail-closed, with the
  asymmetry stated: a diff can add output, never remove it.
- **User-reported Major — the empty check read the RAW capture.** The first version of that fix
  tested the capture before the sentinel strip, so a pass whose entire output was the framing line
  counted as non-empty — and the test written alongside it asserted that as correct, pinning the
  defect. Emptiness is now judged on the stripped body; the test is inverted and gained an
  allow-side twin.
- **User-reported Major — the ceiling check was bypassable with an escaped pipe.** `Critical \|
  Major` is ONE Markdown cell containing "Critical", but the split on a bare `|` read the trailing
  "Major", so a detail file could keep its escalation while the compact row dropped it. Escaped
  pipes are protected before splitting, with a deny-side test.
- **User-reported Major — a bash 4 construct in a bash 3.2 script.** The case-folding expansion the
  ceiling check used is bash 4+, in a script that twice declares support for the bash 3.2 shipped
  on macOS; the mandatory gate would have died there with `bad substitution`. Lowercasing moved
  into `awk`'s `tolower()`, and a sweep confirms no other bash-4 construct in either changed hook.
- **F-02 Major** — `phase-2-coding.md` cited a Phase-3 enforcer that does not exist. Dispositions
  now land in the deviation log, which Phase 3's expert prompts already read.
- **S-19 Major** — the R36 carve-out still enumerated a CLOSED spelling list, leaving channel
  suppression and severity-threshold raising open. The admissibility test is now stated on the
  OUTCOME, with the four named letters as instances rather than the definition.
- **T-11 Major** — the sentinel test did not discriminate: its oracle was `status -ne 0`, which the
  stub's non-zero exit satisfied unconditionally, so deleting the sentinel from the fixture left it
  green. Rewritten to exit 0 and assert on content. R55's degenerate-oracle shape, inside a test
  written to enforce it.
- **T-12 Major** — the fold-gate test's negative half was inoperative for `folding.md`: bash exempts
  a `!`-inverted command from `set -e` unless it is the test's LAST statement, so inside a
  two-iteration loop it guarded only the second file — the wrong one. Rewritten as
  `if …; then false; fi`. **Derived as a class (R42):** a sweep of all 17 negated assertions in
  `tests/` found 8 dead; the other 7 were converted too, and one was red-proven live afterwards.
- **T-13 Major** — the absolute-path resolution's success path was unpinned; replacing it with a
  bare existence check left all 1019 tests green. A case now passes a relative argument from the
  parent directory and asserts the printed subject is absolute.
- **T-14 / T-15 / T-16 / F-03 / F-04 / F-05 / F-06 / S-20 / S-21 / S-22 / S-23 Minor** — a
  deny-side twin for the pipe-in-cell case (whose comment claimed a red-proof that did not hold); a
  case pinning that each failing pass reports its OWN exit code; a case for a pass emitting no bytes;
  the 10-round-cap exit now carries findings forward on the same terms as saturation; R37's detail
  severity CELL aligned, not only its prose; Step 5 now names a stderr redirection the caller can
  actually use and states that the merged-stream case makes the notice advisory; phase-3's seed
  sentinel declared a fail-toward-work tripwire so it no longer contradicts the agent-review skill;
  R36's two colliding `(a)-(d)` enumerations disambiguated; `cd -P --` with stdout silenced against
  `CDPATH` and option-shaped arguments; and Phase 2 now checks each carried-forward entry's
  provenance against this run's review artifact, since the plan file is committed and a contributor
  could pre-seed one.

## Round-3 gates

`bash hooks/check-rule-sync.sh skills/triangulate` → exit 0, `R1-R57`, `Subject:` absolute.
`bats tests/` → exit 0, **1025 passed / 0 failed / 30 files** (1019 before this round).
Every fix red-proven by an executed mutation, bounded by `timeout` and restored by a `trap`;
`git status --porcelain` clean between and after each.

---

# Round 1

## Changes from Previous Round

Initial review. Subject is the retrospect fold: six new rule rows R52–R57, extensions to
R42/R36/R29/R34, a plan-review saturation exit criterion in phase-1, cross-ports into
agent-review / test-gen / simplify, a fix to retrospect's own fold-gate invocation, and the
retrospective audit document. No production code, no hooks, no tests in the reviewed diff.

There is no plan file or deviation log for this branch — `retrospect` produces an audit
document instead, and `docs/archive/audit/retro-artifacts-lessons-2026-08-02.md` was given to
the experts as the branch's record of intent.

## Perspective convergence

Per "Perspective Convergence as a Severity Signal", four findings were reported independently
by two or three experts and are fixed first within their tier:

| Merged | Reported by | Severity |
|---|---|---|
| Phase-1 saturation exit is unsafe (severity-blind, Anti-Deferral-blind, no receiver, self-adjudicated) | F-01 + F-02 (func), S-01 (sec), T-04 (test) | Major, `convergent: functionality+security+testing` |
| agent-review's completion check cites evidence no backend emits | F-03 (func), T-01 (test) | Major, `convergent: functionality+testing` |
| R36's markerless-weakening sub-clause is unreachable through its own trigger | F-05 (func), S-03 (sec) | Major, `convergent: functionality+security` |
| R36's compact row and digest drop the Critical security escalation | F-06 (func), S-04 (sec) | Major, `convergent: functionality+security` |

## Functionality Findings

- **F-01 Major — the saturation criterion contradicts itself and can exit with an open
  Critical/Major.** `phase-1-plan.md:355` requires that *every* remaining finding be reachable
  only by executing the implementation; `:360` then says to carry unresolved prose-level
  findings forward. Under the permissive reading the exit is severity-blind and overrides
  `:313` ("Critical/Major finding: Must be reflected in the plan file"). Criterion 1 excludes
  "a wrong citation" and "a pattern that denies conformant code" from design findings, but R29
  escalates a citation to Critical when it drives a security decision, and a predicate denying
  conformant code is the R47/R48 class. The exit is also asymmetric with the 10-round cap,
  which mandates consulting the user. "Carried forward" is none of the four Anti-Deferral
  labels, so no cost-justification is required — the deferral channel the R34 extension in this
  same diff exists to catch.
- **F-02 Major — "carry forward as Phase 2 inputs" has no receiving mechanism.**
  `phase-2-coding.md:13` reads only the plan file; nothing ingests the plan-review artifact.
  A finding deliberately not reflected in the plan file reaches no Phase 2 reader (R41 shape).
- **F-03 Major — agent-review's completion check cites a closing marker no backend emits.**
  `agent-review/SKILL.md:139` names "an output missing the backend's own closing marker" as
  failure evidence, but `review-backend.sh:74` strips `## END-OF-ANALYSIS` unconditionally, and
  the codex/claude paths never emit a terminator. The non-zero-exit half is also unavailable
  for ollama: the pass pipeline ends in `|| true`, so `_run_ollama` returns 0 regardless.
- **F-04 Major — the R29 extension is unreachable through the documented selection path.**
  The digest pattern name is still "**External spec** citation accuracy", and both phase-file
  triggers (`phase-1-plan.md:158`, `phase-3-review.md:203`) enumerate external standards only.
  A diff whose citations are intra-repo matches none of them, so the folded extension is dead
  text (R3 against the rule set's own trigger surface).
- **F-05 Major — R36's markerless sub-clause is excluded by R36's own "Fires when".**
  `common-rules.md:325` fires on "a diff **adds or broadens warning suppression**"; the
  sub-clause's defining property is the absence of any such marker. The detail file's Detection
  sentence still says to grep the suppression markers.
- **F-06 Major — R36's compact row and digest drop the Critical escalation the detail states.**
  Row and digest read `Major`; `rule-details/R36.md` reads
  `Major (Critical when the suppressed warning is in a security category)`.
  `check-rule-sync.sh` compares only ID and pattern, never the severity cell.
- **F-07 Minor — R52 omits R48 from "Distinct from" while duplicating its enumeration.**
- **F-08 Minor — the audit's `Novel folded = 6` note enumerates seven items,** and §11's
  mechanical-detectability disposition is consequently unrecorded.
- **F-09 Minor [Adjacent] — nothing pins the argument-bearing invocation** in
  `folding.md`/`pipeline.md`; a future edit can silently reintroduce the bare form.

## Security Findings

- **S-01 Major — the saturation exit closes Phase 1 with unresolved findings at any severity**,
  bypassing the severity gate at `:313`, the Anti-Deferral record at `:337`, and the user
  consultation the other non-clean exit requires. No external attacker; the pressure is
  endogenous — the criterion's own framing is "the second exit, and the one that fires in
  practice", and the classification is the reviewer's own and unreviewed. Impact: a plan
  carrying a false security rationale or a security-driving hallucinated citation is committed
  and implemented.
- **S-02 Major — the R36 sub-clause makes an audit-trail entry the *sufficient* remedy for the
  two spellings that are evasion of a security control.** Base R36 is prohibitive (four
  root-cause categories); the sub-clause places itself outside that frame and supplies "record
  which response was chosen" as its remedy. Spellings (d) and (b) get hard obligations;
  (a) rewording the matched text and (c) softening the pattern get only "record" plus a
  preference. Those two are the canonical bypasses of a secret detector, a forbidden-API gate,
  and a SAST rule — an author whose secret scanner fires can split the literal or alias the
  import, file a deviation entry, and be conformant.
- **S-03 Major — the markerless obligation has no trigger path.** The digest pattern name, the
  compact row's "Fires when", and R36's own Detection clause all key on suppression markers,
  while the sub-clause's premise is that these responses leave none. R42 clause ①a: the
  suppression marker is the *symptom*; "a firing gate went green with no behaviour change" is
  the primitive.
- **S-04 Major (pre-existing, in a changed file) — R36's Critical escalation is absent from the
  digest and the compact row**, so a routed review caps a suppressed SAST or secret-detector hit
  at Major. Because the Security expert appends `escalate` only to Critical findings, a
  deliberately disabled security control never enters the escalation path.

**Verified clean.** (A) Prompt-injection / instruction laundering: a grep over every added line
for network verbs, URLs, shell execution, permission widening, gate-disabling imperatives, and
`settings.json` / `~/.claude` writes returned two hits, both the word "allowlist" used
descriptively. No imperative from the mined corpus survived into the shipped text. (B)
Confidentiality: the sibling corpus is referenced only by opaque thread name and provenance ID;
no secret, credential, token, email, IP, hostname, username, or home path is introduced. RS4
clean. The fold-gate fix creates no skip path (a wrong `$PWD` exits 2, not 0). The R34
extension moves strictly toward harder deferral; agent-review Steps 5/6 move strictly toward
more verification of untrusted external claims; every new row's "Do" clause adds an obligation.

## Testing Findings

- **T-01 Major — agent-review's completion gate cites evidence its own default backend
  destroys.** Executed rather than argued: a stubbed `llm-commands.sh` printing partial output
  and exiting 7 produced `PIPELINE-SURVIVED exit=0`. On the exact failure the clause was written
  for, the gate has nothing to fail on — the RT7 shape embedded in the guard against it.
  Testable: `tests/review-backend.bats` already stubs backends on `PATH`.
- **T-02 Major — the fold-gate fix pins the gate's subject but not its instrument.** Both files
  still invoke `~/.claude/hooks/check-rule-sync.sh`. The same staleness argument applies to the
  script: a fold that changes the linter runs the pre-fold linter against post-fold rules and
  reports green. R50 clause (iii) on the instrument axis.
- **T-03 Major — the "read the printed maximum rule ID" gate cannot fail for an `Extends`-only
  fold.** This fold records 4 `Extends` folded and 13 deferred. When no new ID is added the
  stale-subject and repo-subject runs print a byte-identical range, so the prescribed
  verification is green either way. Root cause: the linter's success line never names the
  subject it checked. Testable and precedented — `tests/check-rule-sync.bats:178,832` already
  assert on the printed output.
- **T-04 Major — the saturation exit is self-adjudicated, has no round floor, and demotes a
  control-semantics defect to prose.** No "not before round N" guard, so a Round-1 result of
  citation/example findings exits plan review after a single pass. "A pattern that denies
  conformant code" is the R47/R48 class, not document hygiene. And `:360` pre-announces the
  verdict — "(the expected answer is none)" — which is a prompt, not a test.
- **T-05 Minor — R53 clause (d)'s red-proof oracle does not discriminate.** An "unreachable
  value" for a coverage floor is frequently also schema-invalid, so the observed red is a config
  rejection whose message also names the key, satisfying the stated oracle while proving nothing
  about key matching. R55's own degenerate-oracle rule, two rows above, not applied to R53's
  proof.
- **T-06 Minor — test-gen obligation 17 states no disposition for the blocked test.** Obligation
  10 forbids editing production code, so the skill cannot resolve the R55 defect; 17 does not say
  what the emitted suite should contain meanwhile, and silent omission is the likely default.

**Gate evidence re-run, not quoted:** `bats tests/` unpiped and redirected, own exit status read
— EXIT=0, 1005 `ok`, 0 `not ok`, 30 files. `check-rule-sync.sh "$PWD/skills/triangulate"` —
EXIT=0, `R1-R57`. The audit's own defect claim reproduces: the bare form exits 0 printing
`R1-R51`.

## Adjacent Findings

- F-09 (functionality → testing): no test pins the fixed invocation form. Superseded by T-03's
  stronger mechanical fix — have the linter name its subject, and assert that.

## Recurring Issue Check

Preserved from each expert's output. Rules that fired: R3 (F-04, F-05, S-03), R16 (T-02), R33
(F-06), R34 (S-01), R36 (F-05, F-06, S-02, S-03, S-04), R41 (F-02, F-03), R44 (T-01), R47
(F-05), R48 (F-07), R49 (S-03, T-01), R50 (T-02, T-03), R53 (T-05), R55 (T-03, T-05), RT4 (T-04
at the process level), RT7 (T-01, T-03, T-04, T-05). Checked and clean: R1, R2, R12, R18, R20,
R21, R25, R29 (every citation in the new text individually resolved), R30, R40, R42, R43, R45,
R52–R57, RS1–RS6, RT1–RT3, RT5, RT6, RT8–RT11. N/A for the remainder — the diff is skill, rule,
and audit text with no runtime code, schema, migration, transaction, UI, enum, async state
machine, serialization, threshold, cursor, sentinel, or progress marker.

All three experts recorded `Seed Finding Disposition` sections. The functionality and security
seeds were empty (the caution branch was applied — no safety inferred from the empty seed). Of
the five testing seeds, two were rejected as out-of-diff or non-reproducing, and three were
adopted after independent verification (T-03, T-05, T-06); one seed's cited line numbers were
obligation numbers, which the expert caught.

## Environment Verification Report

N/A — no environment constraints were declared (this branch has no Phase 1 plan; `retrospect`
produces an audit document instead). Both gates are runnable locally and were executed by two
experts independently of the orchestrator.

## Resolution Status

All 15 findings resolved in the round-1 fix commit. Gates after the round:
`check-rule-sync.sh skills/triangulate` → exit 0, `R1-R57`, `Subject: skills/triangulate`;
`bats tests/` → exit 0, **1014 passed / 0 failed / 30 files collected** (1005 before this round;
the nine new cases are named below).

### F-01 / S-01 / T-04 Major — saturation exit unsafe (convergent: functionality+security+testing)
- Action: rewrote the criterion. It now requires FOUR conditions, not two: at least two completed
  rounds; no open Critical or Major finding in any category, design or prose; no design-level
  finding; and every remainder reachable only by executing the implementation. Removed "a pattern
  that denies conformant code" from the prose exclusion and pointed it at R47/R48; added the
  instruction to classify by the rule that fires rather than by which artifact the text sits in.
  Deleted the leading oracle "(the expected answer is none)". The design/prose label is now filed
  per finding by the expert who raised it and merged — not re-labelled — by the orchestrator, with
  orchestrator disagreement routed into round n+1. Added the user-facing surface of the call that
  the 10-round cap already carries.
- Modified file: `skills/triangulate/phases/phase-1-plan.md`

### F-02 Major — carry-forward has no Phase 2 receiver
- Action: each carried-forward finding must now be written into the plan file's Implementation
  Checklist — the artifact Phase 2 Step 2-1 actually reads — with its finding ID and an
  Anti-Deferral entry in the mandatory format. Stated explicitly that "carried forward" is not a
  fifth disposition escaping that format, closing the unlabeled deferral channel S-01 identified.
- Modified file: `skills/triangulate/phases/phase-1-plan.md`

### F-03 / T-01 Major — agent-review completion evidence (convergent: functionality+testing)
- Action: fixed at both layers rather than only rewording the claim. `_run_ollama` now captures
  each pass's own status (never the pipe tail's — R44), checks for `llm-commands.sh`'s
  `## END-OF-ANALYSIS` sentinel BEFORE stripping it, emits
  `## FAILED: <pass> exit=<n> sentinel=<present|missing>`, and returns non-zero when any pass
  failed or was truncated. The `|| true` that previously swallowed the status is gone; the one that
  remains guards only the sentinel-strip pipe (a body that is only the sentinel filters to nothing
  and `grep` exits 1, which `pipefail` would turn into an abort) and cannot mask a pass failure,
  because that status is captured before the pipe. `SKILL.md` Step 5 now enumerates signals that
  exist — the runner's exit status, the `## FAILED:` line, an empty section under a declared pass
  heading, and, for codex/claude, transcript size plus process exit with an explicit note that no
  terminator is available there.
- Modified files: `skills/agent-review/review-backend.sh`, `skills/agent-review/SKILL.md`,
  `tests/review-backend.bats` (+4 cases)
- Red-proof (RT7 shape (g)): reverting `_run_ollama` to the pre-fix pipeline reds
  *"a truncated pass (no sentinel) reds and names itself"* and *"a pass that exits non-zero reds
  even when the sentinel arrived"*, each on its own `[ "$status" -ne 0 ]` assertion, while both
  allow-side cases stay green. Run bounded by `timeout` with a restoring `trap` — the first
  attempt at this proof hung and left the file mutated, which is RT7 shape (g)(v) and RT11 applied
  to the proof's own subject.

### F-04 Major — R29 extension unreachable
- Action: renamed the rule to "Citation and rationale accuracy (external spec or intra-repo)" so
  the digest pattern name — the index the loading protocol matches against — reaches the intra-repo
  case; regenerated the digest; extended both phase-file triggers (`phase-1-plan.md` R29 bullet,
  `phase-3-review.md` sub-agent citation check) with computed constants, `file:line` and symbol
  references, tool-behaviour claims, and the rationale attached to an invariant; updated the
  Recurring Issue Check template line to match.
- Modified files: `skills/triangulate/common-rules.md`, `phases/phase-1-plan.md`,
  `phases/phase-3-review.md`, `common-rules.digest.md`

### F-05 / S-03 Major — R36 markerless obligation unreachable (convergent: functionality+security)
- Action: renamed R36 to "Suppression, or any markerless weakening, as substitute for fix" and
  broadened the compact row's "Fires when" to cover a firing gate going green with no behaviour
  change (source reworded, pattern softened, subject narrowed, stderr discarded, expectation
  regenerated). Updated the detail file's heading and row pattern to match — `check-rule-sync.sh`
  compares all three — and extended its Detection sentence with a second sweep that does not rely
  on a marker: a gate definition changed in the same diff as the source it scans, a `2>/dev/null`
  added to a load-bearing command, a regenerated expectation/snapshot/baseline. Regenerated the
  digest and updated the template line.
- Modified files: `skills/triangulate/common-rules.md`, `rule-details/R36.md`,
  `common-rules.digest.md`

### F-06 / S-04 Major — R36 severity ceiling dropped (convergent: functionality+security)
- Action: restored `Major (Critical when the suppressed or out-edited warning is in a security
  category)` on the compact row and regenerated the digest. Then derived the class rather than
  fixing the reported instance (R42): a sweep of every `rule-details/` severity cell against its
  compact row found two more real divergences — RS4, whose detail read bare `Major` while the row
  carried a Critical ceiling, and R37, whose row and detail gave different answers for a jargon
  string in a security-relevant flow that does not block comprehension. Both corrected (RS4's
  detail gained the escalation with the rotate-a-pushed-secret reasoning; R37's row was aligned to
  the detail's triggers). Added a **severity-ceiling** check to `check-rule-sync.sh`'s detail-file
  loop: the row and the detail must agree on whether the rule can reach Critical, compared
  case-insensitively in both directions. Deliberately a ceiling test and not a text-equality test —
  equality would fire on eight of the ten pairs, all of them legitimate summary wording.
- Modified files: `skills/triangulate/common-rules.md`, `rule-details/R36.md`,
  `rule-details/RS4.md`, `hooks/check-rule-sync.sh`, `tests/check-rule-sync.bats` (+3 cases)
- Red-proof: dropping the Critical from R36's row on a staged copy →
  `DRIFT: rule-details/R36.md severity ceiling disagrees … (table Critical=0, detail Critical=1)`,
  exit 1. Dropping it from RS4's detail instead →
  `(table Critical=1, detail Critical=0)`, exit 1. Two mutations, applied singly, opposite
  directions, each naming the rule. The paired allow case (differently-worded severities, same
  ceiling) is green, so the check is not deny-only (RT10).

### S-02 Major — R36 sub-clause weakened the remedy for security-detector evasion
- Action: added a security-category carve-out to `rule-details/R36.md`. For a detector in the
  security category the rule already enumerates, spellings (a) rewording the matched text and
  (c) softening the pattern are not admissible resolutions at any price — the base four categories
  are the only ones available, and the deviation entry documents which was applied rather than
  substituting for one. Spellings (b) and (d) keep their own hard obligations everywhere.
- Modified file: `skills/triangulate/rule-details/R36.md`

### T-02 Major — fold gate ran the stale installed instrument
- Action: both invocations are now fully repo-local (`bash hooks/check-rule-sync.sh
  skills/triangulate`), and the prose states the staleness argument for the SCRIPT as well as its
  subject — a fold that changes the linter itself would otherwise run the pre-fold linter against
  post-fold rules and pass because the new check does not exist in the copy being executed.
- Modified files: `skills/retrospect/folding.md`, `skills/retrospect/pipeline.md`

### T-03 Major — printed-max-ID gate vacuous for an Extends-only fold
- Action: `check-rule-sync.sh` now prints `Subject: <resolved dir>` on both the OK and the failure
  path, and `folding.md`/`pipeline.md` require reading that line rather than the ID range — which
  discriminates regardless of disposition type, where the range does not (an `Extends`-only fold
  adds no ID, so both trees print the same range). The ID-range check is kept as a cheaper
  secondary signal for folds that do add one. Three bats cases: the live-repo pass now asserts its
  subject, a fixture pass asserts the subject is the one passed and not a fixed path, and a drift
  case asserts the failure path names it too.
- Modified files: `hooks/check-rule-sync.sh`, `tests/check-rule-sync.bats`,
  `skills/retrospect/folding.md`, `skills/retrospect/pipeline.md`

### F-07 Minor — R52 Distinct-from
- Action: R48's strict-direction sub-clause is now R52's first "Distinct from" entry, with the
  discriminator stated (R48: the survivor is stricter than what the primary path produces, fixed by
  pinning "never stricter"; R52: a latent defect in the survivor's helper chain, which pinning does
  not fix) and the note that a collapse fires both. Replaced the duplicated value enumeration with a
  pointer to R48's list.
- Modified file: `skills/triangulate/common-rules.md`

### F-08 Minor — audit count wording
- Action: the `Novel folded` note now reads "R52–R57 (§1–§6)" only, with a following paragraph
  stating that the saturation criterion is folded but sits outside the 93-row table and why.
  §15 gained its mechanical-detectability entry, plus a note that one member of the extension group
  turned out to be mechanically detectable and was implemented rather than deferred.
- Modified file: `docs/archive/audit/retro-artifacts-lessons-2026-08-02.md`

### T-05 Minor — R53 clause (d) oracle
- Action: the proving value must be legal for the tool but outside the subject's achievable range,
  and the observed failure must name the subject **and its measured value** — which a config
  rejection cannot produce. Cited as R55's degenerate-oracle obligation applied to R53's own proof.
- Modified file: `skills/triangulate/common-rules.md`

### T-06 Minor — test-gen obligation 17 disposition
- Action: stated the disposition. Assert on an out-of-band signal where the code exposes one;
  otherwise emit no assertion on that path and record the omission beside the R55 finding, so the
  suite makes no coverage claim it cannot discriminate. Silent emission and silent omission are both
  named as wrong.
- Modified file: `skills/test-gen/SKILL.md`

### F-09 Minor [Adjacent] — no test pins the invocation form
- Action: superseded by T-03. The linter now names its subject and three bats cases assert it, which
  pins the property mechanically instead of pinning the prose that describes it — the stronger of
  the two remedies, and the one that survives a rewording of the documentation.


---

## Round-2 Resolution Status

All 20 resolved. Gates: `bash hooks/check-rule-sync.sh skills/triangulate` → exit 0, `R1-R57`,
`Subject: <absolute repo path>/skills/triangulate`; `bats tests/` → exit 0, **1019 passed /
0 failed / 30 files** (1014 before this round).

### S-10 / S-15 / N-05 / S-16 / T-07 / T-08 — the backend change, narrowed to out-of-band signals
- Action: removed the forgery surface rather than defending it. `_run_ollama` no longer reads the
  `## END-OF-ANALYSIS` sentinel as evidence (it is stripped as framing, as before the fold) and no
  longer emits `## FAILED:` into the review stream. What remains is the part that is not forgeable:
  each pass's own process status is captured before the strip, a failing pass names itself on
  **stderr**, and the run exits non-zero. `SKILL.md` Step 5 now keys on exit status and transcript
  judgement only, and DECLARES the residual per R49 — a backend that stops early and still exits 0
  is not detectable here, and no in-band marker can close that gap, because stdout carries model
  text about a contributor's diff. The structural mitigation (partition the subject) is named as the
  remedy instead of a signal.
- Modified files: `skills/agent-review/review-backend.sh`, `skills/agent-review/SKILL.md`,
  `tests/review-backend.bats`
- Tests: `stage_llm_stub` now passes the body through the ENVIRONMENT rather than interpolating it
  into a generated script (S-16), and supports per-pass overrides so mixed-pass behaviour is
  expressible. Six ollama cases: complete pass, sentinel-only body, all-passes-fail, ONE failing
  pass among three (T-08), `--adversarial` single pass (T-07), and a diff echoing the sentinel
  (S-10) which must not gain a clean verdict.
- Red-proof, executed and bounded with a restoring trap: `else failed=0` reds ONLY the mixed-pass
  case; exempting `--adversarial` from the gate reds ONLY the adversarial case; swallowing the pass
  status reds all four deny-side cases while both allow-side cases stay green.

### N-01 Major — carry-forward receiver
- Action: the round-1 claim was wrong and is replaced, not reworded. Carried-forward findings now go
  under a distinct `## Carried-Forward Plan Findings` heading, and `phase-2-coding.md` Step 2-1
  gained an explicit obligation to read that section and disposition every entry before writing
  code. Stated why it must NOT ride in `## Implementation Checklist`: Step 2-1 item 5 authors that
  section, and Phase 3 reads it as a file list.
- Modified files: `skills/triangulate/phases/phase-1-plan.md`, `phases/phase-2-coding.md`

### N-02 Major — permission allowlist
- Action: added `Bash(bash hooks/check-rule-sync.sh)` and `Bash(bash hooks/check-rule-sync.sh *)`
  to `settings.json`, so the mandated repo-local form is the one that runs without a prompt.
- Modified file: `settings.json`

### S-11 / S-12 Major+Minor — the R36 carve-out
- Action: extended the carve-out to spelling (b) **when the subject narrowed away is the one that
  produced the finding** — excluding the offending file from a scanner's glob is the canonical
  bypass, and drawing the line on whether the firing subject survives is enforceable where drawing
  it between (b) and (c) is not, since R36 itself calls those indistinguishable in a diff. Restated
  the security category as the non-exhaustive one the escalation clause already defines, with the
  test being what the detector protects rather than whether it appears in the list.
- Modified file: `skills/triangulate/rule-details/R36.md`

### N-03 / N-04 / S-13 / S-14 / T-09 — the linter's own surfaces
- Action: `SKILL_DIR` is resolved to an absolute path (exit 2 naming the subject if it does not
  exist), so `Subject:` identifies a tree rather than echoing an argument. The ceiling extraction
  now requires the row to end in `|` and both cells to parse non-empty, refusing rather than
  fabricating agreement from the Procedure cell. The token-presence limit is declared in place
  (R49): a row that keeps the word "Critical" while narrowing its trigger still passes, and that
  narrowing is R36 spelling (c) applied to this gate — human review.
- Modified files: `hooks/check-rule-sync.sh`, `tests/check-rule-sync.bats` (+2 cases: a
  trailing-pipe-less row must red; a literal pipe in a non-severity cell must stay green)
- Red-proof: dropping the row-shape guard, and separately dropping the non-empty assertion, each
  reds exactly the trailing-pipe case; dropping the absolute-path resolution reds exactly the
  nonexistent-subject case. No collateral reds.

### T-10 Minor — the caller's invocation form is now pinned
- Action: a bats case asserts both `folding.md` and `pipeline.md` contain
  `bash hooks/check-rule-sync.sh skills/triangulate` and neither presents a bare installed-copy
  invocation. Precedent: `tests/check-pre-pr.bats` "skill docs reference scripts/pre-pr.sh
  literally". F-09 is now closed on its own axis rather than by supersession.
- Modified file: `tests/check-rule-sync.bats`
- Red-proof: reverting `folding.md` to the bare form reds exactly that case.

### N-06 / S-17 Minor — the saturation criterion's remaining ambiguities
- Action: defined *open* — a Critical or Major finding carrying any Anti-Deferral disposition is
  still open, because filing a cost-justification tracks a finding rather than resolving one.
  Rewrote conditions 3 and 4 as a partition rather than a conjunction: every remaining Minor is
  either prose-only or executable-only, which is satisfiable, where requiring both of every finding
  was not.
- Modified file: `skills/triangulate/phases/phase-1-plan.md`

### N-07 / N-08 Minor — the two remaining drifts
- Action: R37's detail gained the comprehension/safe-recovery trigger its compact row leads with,
  closing the divergence the ceiling check is blind to by construction. `check-suppression.sh`'s
  header carries R36's new title and now states that the hook covers only the marker-bearing half,
  so a clean run from it is not an R36 pass.
- Modified files: `skills/triangulate/rule-details/R37.md`, `hooks/check-suppression.sh`
