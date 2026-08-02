# Code Review: retro-artifacts-2026-08-02 fold

Date: 2026-08-02
Review round: 1
Branch: `retro/2026-08-02-artifacts-r52-r57`

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

