---
sources: [artifacts]
cursors:
  artifacts: 2026-07-26T15:45:52Z
---

# Retrospective: artifacts source mining (2026-07-27)

Date: 2026-07-27
Source: `artifacts` (review documents in configured sibling repositories; 53 candidate
files since the previous cursor, spanning three repositories). One read-only mining
sub-agent against the R1–R46 / RS1–RS6 / RT1–RT9 digest; dispositions verified by the
orchestrator with grep evidence over `skills/triangulate/common-rules.md` and
`rule-details/`. The corpus split into three threads: a serial-to-parallel conversion of
an aggregate gate harness (the highest-signal artifact — its plan review carries executed
probes and a built counter-example), a multi-round fail-closed guard-hardening thread,
and a frame-residency refactor that widened a sensitive broadcast. No prompt-injection
content was found; the sub-agent confirmed no artifact contained an imperative addressed
to the reading agent.

Fifteen candidate lessons were extracted. Eight map cleanly onto existing rows with no
gap. Three are narrow extensions deferred pending recurrence. Four are folded here — each
backed by a probe actually executed or a counter-example actually built inside the
artifact, not by an argued claim.

---

## 1. A concurrent unit's exit status read without unit identity

**Symptom.** A plan to parallelize a serial gate harness proposed reading a "wait for any
child" primitive's return status and attributing it to the dispatch loop's current index.
An executed probe with a declaration truth of `0 0 7` (third step failing) made the
harness report `7 0 0` — a failing security gate reported as passing, and a passing one
reported as failed. Compounded by a status value that is simultaneously a real program
exit code (missing interpreter → 127) and a supervisor bookkeeping sentinel ("no such
job"), so branching on it fails open exactly on environment drift.

**Root cause.** The verdict-attribution channel and the completion-notification channel
were conflated. A "some child finished" primitive carries no identity; binding its return
status to a loop index is a fabricated join. This is the identity half of R44's
mechanism — R44 covers a status *transformed* by a pipeline (wrong value), this is a
status *mis-owned* by concurrent dispatch (right value, wrong unit).

**Fix.** When a verdict is derived from a concurrent unit's exit status, read the status
from a per-unit handle keyed by that unit's own identity; any "wait for any / next
completion" primitive is a throttle only and its return value must be discarded. No
status value a supervised child can itself produce may be branched on as a
control/bookkeeping signal — a sentinel that collides with a real exit code fails open.

**Disposition.** `Extends-R44`. Grep evidence: `\bwait -n\b|\bper-unit\b` = 0 hits in
`common-rules.md` and `rule-details/`. The broader `identity` = 8 hits, all unrelated
senses ("service identity", "exploitable identity") — none about attributing a status to
the unit that produced it. R44's text is scoped to pipeline aggregates.
Considered R21 (subagent completion vs verification — different actor), R38 (async state
machine — no transient-state wedge), R45 (scaling — adjacent context only).
Provenance: `pre-pr-parallelization-review.md` — Functionality F1/F2, probe table under
"Headline outcome".

## 2. An aggregate harness asserts each verdict but never which checks ran

**Symptom.** Two independent defects with one consequence. (a) The join phase aborted
under the harness's own strict-error mode: a probe showed the script exiting with the
first failure's status, the remaining steps never joined and the results block never
printed — every check after the first failure silently never evaluated. (b) No acceptance
criterion pinned the executed *step set*; a silently un-dispatched gate lowers both the
executed set and the reported count consistently, so count-vs-count cannot detect it —
any of ~40 guards could stop running while the harness reports all-green. Counters
mutated inside backgrounded jobs are discarded by the parent, yielding a zero/zero
summary with a success exit.

**Root cause.** The harness's contract was "each check's verdict is correct", never
"every declared check actually ran". Reformulating the runner — parallelism, early exit,
dispatch restructuring — changes membership of the executed set, and no assertion
observed that set. A count is a projection of a set that is invariant under the exact
substitution being made.

**Fix.** An aggregate verification harness must assert set-equality between the labels it
actually executed and a checked-in manifest, failing in both directions (declared member
missing from the run AND unknown member appearing in it). Any restructuring of a harness
that runs N gates must red-prove that removing one gate from dispatch reds the harness.
Related: when a meta-gate enforces a property over a class of controls, derive its
member-set from the ROLE (what can silently disable a control), not from a path glob —
the harness that runs all the gates is the most privileged member and is routinely
outside the naming convention that defines membership.

**Disposition.** `Extends-R42`. Grep evidence: `set-equality|set equality` = 0 hits in
`common-rules.md` and `rule-details/`. `manifest` = 8 hits, all unrelated senses
("package manifest", "Kubernetes manifest", "downloaded manifest") — none about a
runner's declared check set. R42's existing
fingerprint/attestation sub-clause covers deriving a skip-attestation's input class from
the real read surface; the runner's own executed-member-set as a first-class asserted
class is the same discipline, unstated. Considered R44 (status reading, not membership),
RT7(b) (authored-but-ungated detector — covers a check with zero callers, not a wired
check silently dropped by a runner rewrite), R33 (CI config duplicates).
Provenance: `pre-pr-parallelization-review.md` — Security S2/S4, Functionality F4,
Testing T8.

## 3. A differential oracle over a detector whose output set is empty by design

**Symptom.** A refactor of a security gate was to be validated by "byte-identical output
before and after". Independently verified in the review: the gate emits zero bytes on a
clean tree, so the acceptance criterion reduced to comparing two empty streams — an
unconditional-success stub would have passed it. The security reviewer then built the
counter-example: a narrowed gate passing 30/30 self-tests AND producing a byte-identical
differential while genuinely losing detection of a literal at a specific window offset.
The same trap held in the fixture dimension — the suite's call-site × manifest-id
cross-product was empty (no fixture had two ids reaching one call site), so every
execution iterated a manifest of cardinality 1, and cross-contamination, the exact bug
class the optimization introduces, was unobservable.

**Root cause.** A differential or golden oracle over a detector's output is only as strong
as the comparison corpus's *positive* density. On a healthy repository a detector's output
set is empty by design, so output-equivalence carries zero information about detection
power. Distinct from RT7(c)'s "golden vectors omit a legal variant" — here the oracle is
measurably empty and no variant-coverage argument even applies.

**Fix.** Before accepting a behavior-preservation argument for a detector refactor,
measure the oracle's discriminating power: confirm the comparison corpus produces
non-empty output under the PRE-change implementation, and that fixture cardinality along
each dimension the rewrite can collapse (per-item windows, multi-key manifests,
multi-file scope) is at least 2. Where either is not met, the differential is not
evidence — the mandatory proof is one mutant per narrowable dimension, red-proven,
promoted from escalation-only to unconditional.

**Disposition.** `Extends-RT7`, shape (c). Grep evidence: `differential|golden|
byte-identical|discriminating|cardinality` = only RT7(c)'s "golden vectors omit a legal
variant" in `rule-details/RT7.md`; nothing covers an empty oracle or fixture cardinality.
Considered RT4 (vacuous race pass — same vacuity family, wrong domain), R45 (perf
rewrite — adjacent).
Provenance: `pre-pr-parallelization-review.md` — "Headline outcome", Security S1, Testing
T1/T2/T3/T5.

## 4. Sender authenticity mistaken for a bound on the recipient set

**Symptom.** After a refactor made fill listeners resident in all frames, a tab-wide
message send delivered payment-card and identity fields in plaintext to every frame,
including cross-origin third-party ones. A first-round security review had cleared the
path, reasoning that the sender-identity gate mitigated the risk. It does not: sender
identity proves the message came from the extension; it says nothing about which frames
receive it. The sibling credential path was safe on the same broadcast only because its
payload carries an allowlist each frame self-verifies — and the card/identity entries are
hostless by design, so no such per-frame gate can exist for them.

**Root cause.** Two orthogonal properties on one channel — authenticity of the sender and
scope of the recipient set — were treated as one. The widening came from a *residency*
change on the receive side, with no diff at the send site, so R43's "diff every boundary
predicate the fix touches" never fired; and the authenticity gate that was present created
the appearance of coverage during review.

**Fix.** For any broadcast-shaped delivery of a sensitive payload, bound the recipient set
explicitly at the send site (scope to the originating context, else the single trusted
default), and review recipient scope as an axis distinct from sender authenticity — an
authenticity gate is never evidence of recipient bounding. A change that makes a handler
resident in MORE contexts is a recipient-scope widening even when no send site was
edited: the boundary diff must cover handler-residency changes, not only send-site
predicates.

**Disposition.** `Extends-R43`. Grep evidence: `recipient scope` and `broadcast` appear in
`rule-details/R43.md` (widening by deliberate edit at the delivery site) but `residency`,
`authenticity` = 0 hits; the receive-side-residency vector and the
authenticity-masks-scope review failure are both unstated. Considered R41 (declared
capability — inverse), RS3, RT9 (the twin-drift removal that enabled it — already
covered).
Provenance: `autofill-fillable-input-type-filter-plan.md` — "Phase 3 Resolution — Round 2
(post-push High finding)".

---

## Deferred (real gaps, too narrow for this round)

| Lesson | Mechanism | Proposed |
|---|---|---|
| Gate scan scope shrinkable to empty via environment override | Test-seam parameterization of a gate's scan root is indistinguishable at runtime from a misconfiguration that empties the scan set; the authoritative run must assert no scope-affecting override is set | `Extends-RT7` (xref RS5) |
| Fail-safe direction inverts for record-then-enforce paths | "Fail closed = abort" holds for read-then-decide paths and inverts where aborting skips a security-relevant side effect (an attempt counter never advances); the safe direction there is a restrictive-value fallback, never cached | `Extends-R43` (xref R38 Part 2 §6) |
| Gate greens on its own internal failure | A gate deriving its search signatures from a subprocess whose status is lost cannot distinguish "scanned and found nothing" from "could not scan"; and an exit-code-only fail-closed test cannot separate fail-open from aborting earlier | `Extends-R44` (xref RT8) |

Each is a genuine gap but narrow, and folding all seven would lengthen three rule rows
past their routing-summary role. Revisit on recurrence.

## Disposition summary

| # | Lesson | Disposition |
|---|---|---|
| 1 | Concurrent unit status read without unit identity; sentinel/exit-code collision | **Extends-R44** (folded) |
| 2 | Executed-check-set membership unasserted in an aggregate harness | **Extends-R42** (folded) |
| 3 | Vacuous differential oracle / cardinality-1 fixture cross-product | **Extends-RT7** (folded) |
| 4 | Sender authenticity mistaken for recipient-scope bound | **Extends-R43** (folded) |
| 5 | Gate scan scope shrinkable to empty via env override | Extends-RT7 — deferred |
| 6 | Fail-safe direction inverts for record-then-enforce paths | Extends-R43 — deferred |
| 7 | Gate greens on its own internal failure; exit-code-only fail-closed test | Extends-R44 — deferred |
| 8 | Guard accepting a syntactic family instead of the property proven | Covered-by-RT7 (f) |
| 9 | Guard vouching at file/function granularity for per-site risk | Covered-by-RT7 (f), R46 |
| 10 | "Single-sourced" declaration true for only one of N consumers | Covered-by-R3 + RT7 |
| 11 | Environment-dependent primitive gating an unconditional guarantee | Covered-by-R16 (xref RT7 b) |
| 12 | Reworded red-proof rationale never executed (third recurrence) | Covered-by-RT7 (d) |
| 13 | Class-wide sweep deferred until the user asked | Covered-by-R42 (b) |
| 14 | Meta-gate's own runner excluded from its member-set | Folded into lesson 2 |
| 15 | Per-item vs aggregate cap verified only in aggregate | Out-of-scope (plan arithmetic; below the bar for a rule) |

Novel: 0. Extends folded: 4. Extends deferred: 3. Covered: 6. Out-of-scope: 1.
