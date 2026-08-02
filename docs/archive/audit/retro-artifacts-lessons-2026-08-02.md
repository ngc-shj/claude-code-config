---
sources: [artifacts]
cursors:
  # Per-repo MINIMUM, per pipeline.md Step 4 — a scalar cannot reconstruct
  # the per-repo map, and only the minimum is safe in the recovery direction.
  artifacts: 2026-07-14T16:44:06Z
---

# Retrospective: artifacts source mining (2026-08-02)

Date: 2026-08-02
Source: `artifacts` (review documents in configured sibling repositories; 17 candidate
files, ~720 KB, spanning two repositories). Four read-only mining sub-agents ran in
parallel against the R1–R51 / RS1–RS6 / RT1–RT11 digest, partitioned by work item so no
agent held more than ~280 KB of corpus. The orchestrator re-verified `git status
--porcelain` after each agent returned; neither working tree gained anything.
Dispositions were re-derived by the orchestrator against the full text of
`skills/triangulate/common-rules.md` and `rule-details/` — the sub-agents saw only the
one-line digest, which is why a large share of their proposed `Extends` collapse to
`Covered` here.

The corpus split into four threads, referenced below by thread rather than by artifact
filename (the sibling repository's filenames carry its product vocabulary, which does not
belong in a committed file here): a **transitive-override** thread (pinning a vulnerable
transitive dependency through an ordered override namespace, six review rounds); an
**egress-hardening** thread (extending a peer-verification control from one caller class
to every session) together with an **external-claim adjudication** thread (five findings
from an outside reviewer, adjudicated claim by claim); an **append-only evidence store**
thread with its predecessor **identifier-alias** specification; and this repository's own
**cursor-epoch** thread, which is cited by filename.

Ninety-three candidate lessons were returned. They consolidate to roughly thirty distinct
mechanisms; most map onto existing rows, which is the expected outcome. Ten are folded
here — six `Novel` and four `Extends`. Every folded item was either raised independently
in two or more partitions, or survived a grep against the full rule text showing no
existing row states its obligation. The remaining thirteen `Extends` proposals are
recorded in §12 as deferred: each is real, none is convergent, and folding all twenty-three
in one pull request would reproduce the very failure §11 mines — an artifact grown past the
point where review finds defects in the design rather than in the document.

No prompt-injection attempt was found. All four sub-agents explicitly scanned for
agent-directed imperatives and reported none: every directive-shaped sentence in the corpus
is addressed to that project's own implementers and was read as data.

---

## 1. Extending a control's reach re-opens the control's own correctness

**Symptom.** A fix collapsed two adjudicators of one predicate into the stronger one, so a
verification that previously ran only on one narrow caller class began running on every
session. The verifier's helper parser carried a pre-existing truncation bug that mis-read a
legitimate multi-label configured value. Before the change that bug denied a narrow class of
calls; after it, the same bug would have locked every user of an affected tenant out of the
product. It surfaced in plan review round 2, not in the derivation that proposed the change.

**Root cause.** Extending an existing control to a larger population is reviewed as a
*coverage* change, so the whole review budget goes to "does every path now reach the
control". The control's own correctness reads as settled because it already shipped. But the
change multiplies the blast radius of every latent defect inside the control and everything
it calls — including defects whose current symptom is small enough that nobody has reported
them. Secondary failure in the same thread: the resulting "fix X before Y" constraint was
recorded in narrative prose *below* the table that gated completion, so nothing structurally
prevented shipping Y first.

**Fix.** Treat the control and its parse/lookup helpers as in-scope for a fresh correctness
audit against the newly covered population, specifically for input shapes and configured
values the old narrower population never produced. Any prerequisite this surfaces becomes a
field in the artifact that gates completion, not a note beside it. State where the
newly-strict control's recovery path lives and prove by test that it does not traverse the
dependency that fails closed.

**Disposition.** `Novel` → **R52**. Grep evidence: `R43` covers a fix *widening* a boundary
(more permissive) and its rule-details enumerate only permissiveness axes; `R34` governs the
deferral decision about a pre-existing bug, not the reach that changes its severity; `R42`
derives which members a control covers, never the control's own correctness; `R3` covers
propagation, and here propagation was complete — the propagated thing was defective.
Provenance: egress-hardening thread, plan-review round 2 / round 3.

## 2. A numeric gate threshold set or raised without headroom

**Symptom.** A recommendation to raise global coverage floors to specific values was rejected
on measurement: actual sat ~2 pt above the proposed line on one axis and ~3 pt on the other.
A threshold set within normal churn of the current value fires on whichever unrelated change
happens to cross it, not on the change that caused the regression. The requested per-file
floor could not be added at all — the named file sat far below it and would have failed CI on
the enrolment commit. When per-file entries were finally added, they were red-proved by
setting them to an impossible value, confirming the path keys actually matched; a key typo in
such a map applies to nothing and is silently green.

**Root cause.** Threshold changes are judged by whether the number sounds right rather than
by the distance between the number and the current measurement. That distance determines
*whom* the gate fires on.

**Fix.** Before adding or raising a numeric gate threshold, measure the current value, state
the headroom, and set the threshold with slack exceeding normal churn. Enrol a specific
subject into a stricter per-subject floor only after the work that lifts it above the line
has landed. Prove a per-subject entry binds by setting it once to an unreachable value and
confirming the subject is named in the failure.

**Disposition.** `Novel` → **R53**. Grep evidence: `R45` bounds a gate's *runtime* against the
scanned set, never its threshold value; `R27` covers numeric ranges hardcoded in user-facing
strings; `R33` covers threshold drift between duplicate CI configs, not the value's margin;
`RT7` proves a gate can fire at all — which covers the path-key red-proof but says nothing
about the margin that decides whom it fires on. Provenance: external-claim adjudication
thread, T4.

## 3. Control suspension granted through ambient context state

**Symptom.** A routine permitted to bypass an append-only enforcement set the bypass flag
inside its own body. That form persists to the end of the *caller's* transaction, so calling
it from a shared cleanup helper would disarm the enforcement for the ~25 statements that
follow in the same transaction. A test that issues the forbidden statement in the *next*
transaction passes against the leaking implementation. Compounding: the ambient variable was
unregistered, so any principal could set it — the "authority" was a convention, not a
boundary.

**Root cause.** A sanctioned exception to an invariant-enforcing control is granted through
ambient state whose lifetime is the enclosing context (transaction, session, request, thread)
rather than the single operation it was granted for. Every subsequent operation in that
context inherits the exception.

**Fix.** Scope the suspension to the call itself — a declaration on the routine that the
runtime saves and restores around invocation, including on the error path — never by
setting-and-hoping inside the body. Test it in the *same* context after the sanctioned call
returns. And record in the control's class declaration that an ambient flag any principal can
set bounds nothing; the real bound must be a capability the adversary does not hold.

**Disposition.** `Novel` → **R54**. Grep evidence: `R39` is zeroization of secret material at
a lifecycle boundary; `R38` clause (2) is supersession across async suspension points inside
one principal; `R51` is a name re-resolved to a different object; `R5`/`R9` are transaction
boundaries for the guarded work, not for an exception grant. None states that the exception
outlives the operation it was granted for, nor that the obvious test observes the wrong
context. Provenance: append-only evidence store thread, S1 / G2.

## 4. An in-band sentinel that is also a legitimate value of its domain

**Symptom.** One value served simultaneously as the seeded default, as the reset floor, and
as the constant a wrong implementation would emit unconditionally. Consequences at three
levels: two Critical test degeneracies (three candidate emitters produce byte-identical
output, so the acceptance suite could not discriminate); an implementation emitting the
constant unconditionally passed the entire named acceptance suite; and a fix keyed on
`value == <floor>` conflated "no entry persisted" with "legitimately persisted floor",
disabling a raw-egress suppression on every first run.

**Root cause.** An in-band sentinel that is also a representable, legitimate datum makes
"absent", "reset", and "genuinely equal to the sentinel" indistinguishable to every
downstream consumer, including the tests. Every branch keyed on the sentinel misfires on one
of the three meanings.

**Fix.** Branch on the out-of-band signal — key absence, an explicit null, a separate presence
flag — never on the in-band sentinel. Never let an acceptance case's expected value be the
sentinel: a hardcoded-constant implementation passes it.

**Disposition.** `Novel` → **R55**. Grep evidence: `R2` covers one literal duplicated across
places, not one literal carrying several meanings; `R25` is persist/hydrate round-trip
completeness; `R38` is state-machine shaped; `R40` is document shape against a strict
consumer; `RT7` shape (g)(ii) covers the test-visible half (a mutation with zero delta) and
not the production mis-branching. Provenance: cursor-epoch thread,
`retro-prescreen-cursor-epoch-code-review.md` "Root cause of the two Criticals".

## 5. Healing a progress marker in the skip direction

**Symptom.** A persisted watermark ahead of the present was clamped to "now". Every existing
item then sorted at or below the cursor and was suppressed; the clamped value was persisted;
the entire backlog between the last genuine position and the clamp instant was lost
permanently, with no diagnostic on any channel — a blind source and a fully-drained source
produced byte-identical output. The naming reinforced the error: the operation was called a
"clamp" and the operator-facing message said "clamped to `<now>`", which gives an operator
the wrong recovery model.

**Root cause.** For any watermark, checkpoint, offset, cursor, or last-seen marker, the two
heal directions are not symmetric. Moving the marker *forward* toward the present discards
unprocessed work irreversibly, because item timestamps do not move with it; moving it
*backward* to the floor costs a bounded re-process. The forward direction is the one that
looks tidy and the one a name like *clamp* suggests.

**Fix.** Heal in the re-process direction only, and state the invariant as "the healed value
is ≤ the persisted value on every path" — which makes emitting it safe on every branch,
including degraded ones. Name the operation for what it does and check that the
operator-facing wording implies the correct recovery model. Composition to check: a reset
widens the candidate set, so if candidates feed an off-machine path, the reset run must
disable that path.

**Disposition.** `Novel` → **R56**. Grep evidence: `R43` governs the egress composition
consequence, not the direction choice; `R38` is fail-open supersession on auth/session state;
`R25` is persist/hydrate symmetry; `R50` covers only the observability half (a blind run and
a drained run being indistinguishable). No row states a recovery-direction obligation for
progress markers. Provenance: cursor-epoch thread, `retro-prescreen-cursor-epoch-review.md`
CR-1(a).

## 6. An ordering or cursor key with no total order

**Symptom.** Records were ordered and paginated by a timestamp with millisecond resolution; 1000
consecutive reads of the clock were observed identical, so order among same-instant records
was undefined and a keyset cursor could skip or repeat. Closed with a monotonic identity
column carrying a uniqueness constraint, the timestamp retained for display and never
compared for ordering again. The new key then had to be protected at the capability layer: a
caller able to name it could plant a maximal value and make every later engine-assigned value
collide — and with the writer fail-closed, the symptom is denial of the operation rather than
a missing record.

**Root cause.** An ordering/cursor key was chosen for its human meaning rather than for the
properties pagination requires: total order, uniqueness, monotonicity, and un-nameability by
the writer.

**Fix.** Key pagination and ordering on a value that is unique and monotonic by construction;
the human-meaningful value stays displayed and is never compared. Then check the new key's own
write surface — an engine-assigned key is non-forgeable only if the caller cannot name the
field.

**Disposition.** `Novel` → **R57**. Grep evidence: `R40` is cross-boundary serialization shape;
`R38` is async state machines; `R51` is name-versus-object; `R25` is persist/hydrate; `RT4` is
a race test's lower bound; `R27` is numeric ranges in strings. None covers ordering/cursor key
properties. The adjacent half — a "cannot be overridden" claim about the engine-assigned key,
falsified by an explicit override clause — is `Covered-by-R29`. Provenance: append-only
evidence store thread, D-22 / D-23.

## 7. The derivation instrument itself was never characterized

**Symptom.** Two partitions, two directions of the same mechanism. In one, the member set of a
defect class was read from a tool whose output is intersected with current state, so members
that nothing currently occupies were structurally invisible; a companion enumeration command
matched by unanchored suffix and silently returned a *different* entity sharing a trailing
segment, with no marker distinguishing true rows from false. In the other, a plan *published*
the grep commands it claimed to have derived its member sets from; running them returned
members different from the claimed ones — none of the three cited exits appeared in the
published command's output.

**Root cause.** A class was derived through an instrument nobody had characterized, and
publishing a derivation command *looks* like deriving. Both the author and the reader treat
the command as evidence without either having executed it.

**Fix.** Before an enumeration's output is accepted as a member set, state what the instrument
can structurally fail to report and validate it against one known member and one known
non-member. Ship every derived-set obligation as three things: the derivation command, its
output at authoring time, and an executable assertion that the set has not grown.

**Disposition.** `Extends-R42` (convergent across the transitive-override and cursor-epoch
threads). R42 clause ① already demotes a *supplied list* to an unverified hint and clause ①a
distinguishes the defining primitive from a symptom; neither says the derivation *tool* is
itself a supplied list, nor that a published command is evidence only with its recorded
output. Provenance: transitive-override thread E2 / F-R4.1; cursor-epoch thread "The dominant
class, and the third mechanism replacement".

## 8. Weakening the detector rather than fixing the defect, with no marker in the diff

**Symptom.** Three partitions, four spellings. A plain-text tripwire fired on an explanatory
comment; the comment was reworded so the gate went green, with no exemption entry and nothing
in the diff signalling that a gate had been worked around rather than satisfied. A gate fired
on a file's own prose and the tempting response was to soften the pattern; the response
actually taken narrowed the gate's *subject*, which is legitimate but nearly indistinguishable
from the softening in a diff. A load-bearing `source` ran with stderr suppressed, so a failed
load left the helper silently absent. And an expected-state snapshot regenerable from live
state had been regenerated against a broken state, so an audit reported OK while a capability
control was silently undone on every convergence run.

**Root cause.** A firing detector presents responses that cost the author wildly different
amounts and look nearly identical in a diff: fix the code, narrow the subject, soften the
pattern, suppress the channel, regenerate the expectation. The cheapest removes detection.
Unlike a suppression pragma, none of the last four leaves a marker — and the regeneration case
arrives with no human suppressing anything at all.

**Fix.** Record which of the responses was chosen and why, as an explicit deviation entry.
Suppressing a channel is admissible only when paired with a positive post-condition on the
operation's result. A gate subject narrowing must be proven to create no hiding place. And any
expectation file regenerable from live state needs an independent *prescriptive* rule that
refuses to record a violating state, run *before* the regeneration, so the regeneration is
trustworthy only because the prescriptive check passed.

**Disposition.** `Extends-R36` (convergent across three partitions). R36's rule-details cover
comment-pragma suppressions and underscore-prefix rename-tricks, and its four remediation
categories assume a marker exists to review. The markerless variants are absent. Provenance:
egress-hardening thread D6; append-only evidence store thread S4 / T12 / D-6; cursor-epoch
thread D-2 / R2-8.

## 9. A false rationale under a true conclusion

**Symptom.** Two partitions. A risk-acceptance argument rested on an asserted ecosystem fact
that was false; verified, the true fact *strengthened* the risk the claim had been used to
discount. A "clean" verdict was recorded with a rationale that was false — the entry was clean
for an entirely different reason, and the row would later have been cited as evidence for a
claim that is not true. Separately, a design invariant was justified with "no candidate
advanced the maximum, because none was processed"; instrumented execution captured the maximum
already advanced at the emitter. The conclusion held; the reason did not — and the variable the
false reason pointed at is the one in scope and the natural thing for the next editor to reach
for. Adjacent instances in the same thread: two round-trip constants transposed, a helper name
absent from the tree, several off-by-a-few line citations, and a false rationale sentence that
reached the commit message and the PR body before it was checked.

**Root cause.** Load-bearing prose is treated as narrative rather than as claims. A rationale is
what licenses the *next* edit, so a false reason attached to a true invariant is a live defect.
Claims that pass unverified through a review reach append-only surfaces where correction is
expensive or impossible.

**Fix.** Verify by execution every load-bearing claim, not only the conclusion it supports:
computed constants (record the command next to the value), intra-repo `file:line` and symbol
citations, tool behaviour, and the reason attached to each invariant. Assert round-trips against
literals in both directions, never as `f(g(x)) == x` — two mirrored-wrong implementations satisfy
that. Verify before the claim enters an append-only surface.

**Disposition.** `Extends-R29` (convergent across the transitive-override and cursor-epoch
threads). R29 is scoped to *external spec* citations — its four verification obligations are all
about a published document's section numbering. Intra-repo citations and explanatory rationales
are outside it, and `R49` covers claims about *controls*, not the reason attached to a true
conclusion. Provenance: transitive-override thread F3 / F-S1 / F-S2; cursor-epoch thread R2-3 /
MJ-2 / X6.

## 10. A deferral entry is a review subject, not a review input

**Symptom.** Two partitions. Three Anti-Deferral entries were judged understated by the next
review and the judgement was correct each time: one named one sink where the code has three and
rated Minor; one rated a hand-edit typo "likelihood low", mis-stated the abort scope (aborts the
*source*, where the consumer aborts the *run*), and asserted an assertion existed that did not;
one framed a gap as a cardinality problem when the artifact under test was unasserted entirely,
at any cardinality. A fourth entry was filed as a deferral when the true reason was "not reached
before the branch was pushed". Separately, a deferral was accepted on a justification that
*enumerated* the members it left exposed, and a later round of the same branch added members of
exactly that class — silently falsifying the enumeration that had made the deferral acceptable.
And in a third instance, execution showed the deferred class member sat *upstream* of the
in-scope remedy: a future value there makes the source never become due, so the remedy is never
invoked and its own announcement is unreachable.

**Root cause.** The author who decides to defer also writes the worst case, the likelihood, the
cost, and the mechanism — four estimates all biased toward the decision already made. A filed
justification currently discharges the obligation, so nothing re-derives it. And class-member
deferral is adjudicated on unit-of-work and reachability, never on the structural question of
whether the deferred member gates the remedy's trigger or its observability.

**Fix.** Verify a deferral entry's sink enumeration against the code, its blast scope against the
consumer, and its stated mechanism against execution; raise the finding at the true severity, not
the recorded one. State an exposed set as a *derivation* rather than a list, and re-derive it at
close-out. Refuse the deferral outright when the deferred member sits on the in-scope remedy's
trigger or observability path, regardless of the remedy's size. Distinguish "deferred,
cost-justified" from "not done, ran out of time" — the latter is a completeness gap, not a
decision.

**Disposition.** `Extends-R34` (convergent across the append-only evidence store and cursor-epoch
threads). R34's row and the Anti-Deferral Rules section both treat the presence of a
Worst-case/Likelihood/Cost triple as satisfying the obligation; neither makes the triple's own
accuracy reviewable, and neither has a structural bar on which members may be deferred.
Provenance: append-only evidence store thread D-27 / A1; cursor-epoch thread "Anti-Deferral
entries judged UNDERSTATED by the review" / R3-8.

## 11. Plan review saturates, and the specification becomes the defect surface

**Symptom.** Recorded independently in two partitions, with numbers. In one, a predecessor
specification reached 1951 lines and its own revision log states that at that size the document,
not the design, is what review finds defects in; its successor reached 1072 lines and a round-3
finding diagnosed the growth precisely — it was not obligations, it was "what a previous revision
said and why it was wrong" threaded through every contract. Across six review rounds on one
branch, five consecutive rounds produced more findings against the previous round's fixes than
against the original implementation, and three consecutive rounds returned zero findings against
the design. In the other, three plan-review rounds returned 43 / 39 / 34 findings — the count did
not converge, but the character changed completely: round 1's Criticals were against the design,
rounds 2 and 3 were overwhelmingly against the document's own prose, and round 3's findings were
almost without exception only findable by building and executing the planned implementation.

**Root cause.** Two artifacts are conflated — the specification (obligations and acceptance
criteria) and the record of findings and their disposition. Merging them makes the specification
grow monotonically with review history, and prose is itself reviewable surface. Finding *count*
is a poor exit signal because it does not fall.

**Fix.** Use the finding *character*, not the count, as the plan-review exit criterion: when a
round produces no design-level findings and its findings are only reachable by executing the
planned implementation, the plan phase is saturated — proceed to implementation. Keep the
obligation and its acceptance criterion in the specification, cite the finding ID that produced
each, and keep the litigation in the review artifact. Specify only what the toolchain cannot
check.

**Disposition.** `Novel` (phase-loop policy, not a defect class) → folded into
`skills/triangulate/phases/phase-1-plan.md` as a saturation exit criterion rather than taking an
R-table ID. Grep evidence: every R/RS/RT row is a code- or artifact-level defect mechanism; `R34`,
`R35`, `R50`, and `R21` all concern the content of a verification, none concerns when to stop
iterating one. Provenance: append-only evidence store thread "Why this document is short, and
shorter than revision 3" / H8; cursor-epoch thread "The decisive observation" / "Process
assessment".

---

## 12. Deferred `Extends` — real, non-convergent, recorded for a later run

Each of the following survived the orchestrator's grep against the full rule text and is a
genuine gap, but each was raised in exactly one partition. They are recorded here so the next
run does not re-litigate the disposition, and so a clean run can fold them without re-mining.

| # | Target | Clause the existing text does not state | Provenance |
|---|---|---|---|
| D1 | R41 | Precedence shadowing: a remediation entry added to a first-match/priority-ordered namespace can be fully shadowed while appearing present in the diff — exit 0, no ambiguity diagnostic. Presence in the config is not evidence the entry is reached. | transitive-override E1/E3 |
| D2 | R48 | The adjudicator member set includes *hypothetical-input predictors* (preview, dry-run, would-this-succeed, self-lockout checks), which a name-based derivation cannot reach by construction. | egress-hardening F1/S2 |
| D3 | R48 | Where the divergent pair is irreducible, closure is a differential property test against the stricter adjudicator over an input table — a per-spelling rejection test is not closure, and repeated single-spelling hardening rounds are the signature of the gap staying open. | egress-hardening S3/S6 |
| D4 | R49 | The symmetric direction: a shipped claim *weaker* than the implementation makes operators keep compensating controls, and text documenting a *limitation* goes false precisely when the limitation is fixed — a co-landing obligation, not a follow-up. | egress-hardening F12/T10 |
| D5 | R49 | The obligation binds values a system *records* and the documentation naming which recorded field to trust: an evidence field whose meaning the emitter cannot vouch for is an overclaim that survives the incident it was written for. | evidence store D-26/D-29 |
| D6 | R50 | The same shape in *shipped* code, not only in the reviewer's tooling: a verification/attestation path emitting success for an absent, empty, or partially-walked subject, with coverage against the requested range absent from the verdict. | external-claim SEC-1 |
| D7 | R50 | A mandated diagnostic carries a co-residency obligation — output on the same channel must be bounded per run, or the required single-line signal is buried by per-item output that scales with the corpus. | cursor-epoch R2-9/R3-4 |
| D8 | RT5 | The obligation extends to the *assertion* path: a hand-rolled extractor or decoder applied to the produced value can cancel the defect under test even when the call path is correct. | egress-hardening round 4 |
| D9 | RT7 | For data-driven checks the mutation set includes *row deletion*, and the row set must be pinned by an assertion that does not read the table under test — otherwise removing a row removes the check and its coverage in one edit. | cursor-epoch T3 |
| D10 | RT7 | A fix that preserves behaviour (access path, ordering strategy, request count, complexity, cache config) cannot be red-proved behaviourally; pin the non-functional property at the declarative artifact, asserting the definition rather than the name. | evidence store D-24/D-28 |
| D11 | R3 | The propagation site class includes non-code assertions — documents, generated prose, comments, help text, prompts, runbooks, operator messages — that state as fact something the change makes false. Search for the *claim*, not the changed symbol. | evidence store C6/C7, D-12 |
| D12 | R44 | The identity requirement binds *any* verdict channel a test or gate treats as its answer — a thrown error, a printed message, a count — because the generic form is also satisfied by the control's absence. | evidence store T15/V5 |
| D13 | R45 | The scarce resource includes a reviewing *agent's* context budget, and the failure artifact is an empty or truncated report that must be rejected as a failed run rather than read as a clean verdict. | cursor-epoch process note |

Two further single-partition proposals were rejected rather than deferred:
the `RT10` per-row allow fixture is already stated by RT10 clause (1)'s boundary-adjacency
requirement, and `RS5`-test-seam is already stated by R50 clause (ii)'s assert-unset obligation
for scope-affecting overrides.

---

## 13. Disposition summary

| Disposition | Count | Notes |
|-------------|-------|-------|
| `Covered-by-<id>` | 68 | Mapped to an existing row whose full text states the mechanism. The largest clusters: R42 (member-set derivation, 9), R50 (verification preconditions, 8), RT7 (proof able to fail, 7), R48 (parallel adjudicators, 6), R49 (overstated claim, 5), R47 (surface-form adjudication, 4). |
| `Extends-<id>` folded | 4 | R42, R36, R29, R34 — each convergent across ≥2 partitions. |
| `Extends-<id>` deferred | 13 | §12. Each real, none convergent. |
| `Novel` folded | 6 | R52–R57 (§1–§6). |
| `Out-of-scope` | 2 | A collision in the identifier namespace between a plan's row labels and a review's finding labels (artifact-authoring hygiene, no defect mechanism); an announced-removal deprecation warning inside a test gate (generic dependency hygiene, no shape a diff review can detect). |
| **Total** | **93** | P1 18 / P2 22 / P3 26 / P4 27. |

The phase-1 saturation criterion (§11) is folded but sits OUTSIDE this table. It converged
across two partitions as a `Novel` mechanism, but it is a phase-loop policy rather than a defect
class, takes no R-table ID, and is therefore not one of the 93 rows dispositioned above. Counting
it as a seventh `Novel` would break the total; leaving it unmentioned would drop its
mechanical-detectability record, so §15 carries an entry for it explicitly.

The sub-agents proposed 34 `Extends` and 9 `Novel`. The orchestrator's re-derivation against the
full rule text moved 17 of those `Extends` to `Covered` and 2 of the `Novel` to `Extends`/policy.
That gap is structural: a mining sub-agent is given the one-line digest, so it cannot see whether
a rule's body or its `rule-details/` file already carries the clause. It is the correct trade —
passing the full 59 K-token rule text to four parallel agents costs more than the orchestrator's
verification pass — but it means a sub-agent's `Extends` proposal is a *hypothesis*, and Step 3
must treat it as one.

## 14. Standard pass 2 (non-primary skills) and pass 3 (cross-port)

**Pass 2 — `agent-review`.** Two candidates expose a procedural gap in the skill that
consumes another model's findings, which is exactly where they land. (i) Its Step 5 already
says an empty backend result becomes `verdict: approve` with an empty findings array — but a
reviewer killed by context exhaustion or a timeout produces an artifact shaped identically to
a clean review, so `approve` is emitted for a run that examined nothing. Step 5 now requires
confirming the run COMPLETED before an empty result becomes a verdict, and requires
partitioning the subject up front when exhaustion is plausible. (ii) Its Step 6 classified
backend-only findings as "verify before acting" without saying what to verify; it now requires
adjudicating each claim's EVIDENCE and its PREMISE separately, with the observed base rate
recorded — a false premise is the more expensive failure, because adopting it produces a no-op
change recorded as an improvement.

**Pass 3 — cross-port of the folded rules to the skills that own the upstream behavior.**
R55's test-side half went to `test-gen` as obligation 17: no expected value, fixture seed, or
oracle may equal a default, floor, or sentinel. It is the fixture-design cause behind
obligation 16's zero-delta symptom, and neither obligation 14 (cardinality ≥2) nor 16 states
it. R52 went to `simplify`, beside the existing extraction guidance: collapsing two
implementations into the stronger one grows the survivor's reach, and the merge is reviewed as
a coverage change while the survivor's own correctness reads as settled. The other four new
rules have no upstream owner skill — R53 (thresholds), R54 (ambient suspension), R56 (heal
direction) and R57 (ordering keys) describe production-code shapes no skill in `skills/`
authors, so they stay review-time obligations only.

**A defect in this skill's own fold gate, found by this run.** `folding.md` §4 and
`pipeline.md` Step 5 both prescribed `bash ~/.claude/hooks/check-rule-sync.sh` with no
argument. The linter defaults its subject to `<dir of the script>/../skills/triangulate`, so
the bare form checks the INSTALLED copy under `~/.claude/` — which a fold has not touched,
because the fold edits the repository source and the installed copy is stale until
`install.sh` runs. Run bare after adding R52–R57, the gate printed `OK: R1-R51 ... consistent`
and exited 0: a green about the wrong subject, R50 clause (iii) in the gate the skill mandates
for exactly this class. Both files now require the path argument and require reading the
printed maximum rule ID against the one just added. No test was added: the linter's
zero-argument default resolution is already pinned by
`tests/check-rule-sync.bats` ("installed layout: zero-argument default resolution is
drift-free"), and the defect was in the documented procedure rather than in the hook.

## 15. Mechanical detectability

Of the ten folded items, none is folded with a detection hook. Recorded per `folding.md` §3 so
the next round does not re-litigate:

- **R52** (control reach) — requires knowing that a predicate's *population* grew, which is a
  semantic diff over call-site reachability, not a syntactic one.
- **R53** (threshold headroom) — the threshold value is greppable, but the *current measurement*
  it must be compared against is only available by running the gate, which a pre-tool hook cannot
  do cheaply or hermetically.
- **R54** (ambient suspension) — the setting statement is greppable per-language, but deciding
  whether the flag is scoped to the call or the context requires resolving the runtime's
  save/restore semantics for that declaration form. A grep would fire on every legitimate use.
- **R55** (in-band sentinel) — deciding that a literal is simultaneously a default and a legal
  datum is a value-domain judgement with no syntactic marker.
- **R56** (heal direction) — the direction is a comparison operator whose polarity is only
  meaningful against which side is the persisted value; both spellings are one character apart
  and both appear in correct code.
- **R57** (ordering key) — requires knowing the key's resolution and uniqueness properties, which
  live in the schema and the clock, not in the ordering expression.
- **R42 / R36 / R29 / R34 extensions** — each is a claim-verification obligation on prose, and the
  existing hooks for these rules (`check-suppression.sh` for R36) already cover the marker-bearing
  half. The markerless half is markerless by definition. Round 1 of the self-review did surface one
  mechanically detectable member of this group and it was implemented rather than deferred: a
  compact row and its `rule-details/` file disagreeing on whether a rule's ceiling is Critical is a
  two-string comparison, so `check-rule-sync.sh` gained that check with a red fixture per direction.
- **The phase-1 saturation criterion (§11)** — a loop-exit policy, not a diff-level shape. Nothing
  in a diff indicates which round produced it or how its findings were classified; the criterion's
  own safeguards are procedural (a round floor, a severity gate, per-finding labels filed by the
  expert rather than the orchestrator, and a user-facing surface of the call). Recorded here so a
  later round does not re-litigate the absence of a hook.
