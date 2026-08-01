---
sources: [artifacts]
cursors:
  # Per-repo MINIMUM, per pipeline.md Step 4 — a scalar cannot reconstruct
  # the per-repo map, and only the minimum is safe in the recovery direction.
  artifacts: 2026-07-14T16:44:06Z
---

# Retrospective: artifacts source mining (2026-07-31)

Date: 2026-07-31
Source: `artifacts` (review documents in configured sibling repositories; 31 candidate
files, ~1.2 MB, spanning three repositories). Five read-only mining sub-agents ran in
parallel against the R1–R50 / RS1–RS6 / RT1–RT10 digest, partitioned by repository and
by work item so no agent held more than ~400 KB of corpus. The orchestrator re-verified
`git status --porcelain` after each agent returned; the working tree gained nothing.
Dispositions were re-derived by the orchestrator with grep evidence over
`skills/triangulate/common-rules.md` and `rule-details/`.

The corpus split into six threads, referenced below by thread rather than by artifact
filename (the sibling repositories' filenames carry their product vocabulary, which does
not belong in a committed file here): a six-round **identity-key** hardening branch; an
append-only **event-record** branch whose specification became its own defect surface; a
**console-sink** elimination sweep; a **gate-harness** serial-to-parallel conversion; a
**caller-contract** branch; and a cross-process **text-relay** feature with three
post-merge security passes. A seventh thread — the phase-file load-integrity work — is
this repository's own and is cited by filename.

One hundred and twenty candidate lessons were returned. They consolidate to roughly
forty distinct mechanisms; most map cleanly onto existing rows, which is the expected
outcome. Five are folded here. Two of the five are `Novel` and each was raised
independently by two or three sub-agents reading different repositories — that
convergence, not a single artifact's argument, is what promoted them.

No prompt-injection attempt was found. Four sub-agents reported inert imperatives
(operator runbook steps, agent-directed procedure text in this repository's own
artifacts, product strings that are themselves instructions to an automated reader);
all were dispositioned `Out-of-scope` and quoted inertly in the sub-agent reports.

---

## 1. A validated identity is not bound to the object the operation uses

**Symptom.** Two sub-agents reading unrelated repositories reported the same shape. In
one, a path was resolved and containment-checked before an untrusted command ran and
written after it returned — the untrusted command being the analyzed subject's own
build entry point, free to replace the resolved path with a link during the interval.
In the other, a consumer probed a handoff object with link-following existence calls
and no type check, and a collector validated a directory by path and then re-resolved
the same path to enumerate and delete its contents, in a namespace other principals can
write. Both were verified by execution in their own reviews.

**Root cause.** A name is a lookup key, not a handle. Every re-resolution is a fresh
lookup that anyone with write access to an intermediate component can influence, and
the ordinary existence/stat/open helpers follow links by default. The failure survives
the remedies for the rules that look adjacent: consulting the authoritative resolver
(R47) fixes the *spelling* of the reference and leaves the *interval* open, so R47's
obligation reads as discharged while the hole is still there.

**Fix.** When a decision about an object is made before its use and any other principal
can act in between, carry the decision on a handle acquired without traversing any
component that principal can write — refusing to follow a link on the final component is
not enough, since every intermediate directory is still resolved by name during that open.
Validate the descriptor (type, owner, mode, size ceiling), then operate relative to it one
non-symlink component at a time; a multi-component relative path re-resolves the names in
it. Where no handle exists, re-checking at the instant of use only narrows the window — it
must be paired with making the write conditional on the checked state (compare-and-swap
over every field the check read and the write mutates), and the remainder declared.
Restrictive creation mode on one's own directory does not protect operations that
re-traverse the path afterwards.

**Disposition.** `Novel` → **R51**. Grep evidence over `common-rules.md` and
`rule-details/`: `descriptor` = 0 hits, `link-following` = 0, `O_NOFOLLOW` = 0,
`check-then-use` = 0, `time-of-check` = 0, `rebind` = 0. `TOCTOU` = 3 hits, none of them
this mechanism — one in R5 scoped to a read-then-write inside a database transaction,
two inside R42 where a TOCTOU class is used as the worked example of a *member-set
derivation* error. `symlink` = 2 hits, both about enumerating spellings (R47's
equivalence-class sequence, RT10's illustrative axis set); `lstat` = 1 hit, inside
R47's remedy. Considered R5 (transactional stores only), R47 (notation, not interval),
R46 (lexical binding inside an analyzer), RS3/RS5 (validation happened, with the right
criteria), R38 (state-machine terminality).
Provenance: `triangulate-r50-evidence-deferred.md` — Open items 1–2;
`triangulate-rt10-r50-detection-hooks-review.md` — R2-F4;
text-relay thread — deviation log — Post-merge and Second security-review passes.

## 2. A test fixture escapes its own sandbox, or survives the failure path

**Symptom.** Three sub-agents, three repositories. Tests registered cleanup only *after*
assertions that can throw, so a failing run leaked records together with their globally
unique keys and the next run failed on a uniqueness violation — a different failure from
the original one, five records in a single round. A suite built its
"outside the guarded root" fixtures by walking a parent segment out of its temp root,
placing them directly in shared system temp under fixed, guessable names that only the
root's own teardown would have reclaimed. A recorder appended to a shared file resolved
from the working directory, so an earlier test's record satisfied a later test's
existence assertion.

**Root cause.** Two separable defects that present as one. The sandbox is scoped to the
subject root rather than one level above it, so any fixture the test needs *outside* the
subject necessarily lands outside the reclaimed tree; and cleanup is registered at the
end of the happy path rather than at the moment of acquisition, so the abort-on-failure
semantics of the runner skip it in exactly the runs that leak. Where the leaked resource
carries a global uniqueness constraint or a cumulative sink, the damage lands in the
*next* run, as a failure that does not name its cause.

**Fix.** Register every acquired fixture for teardown at the moment of acquisition —
including identifiers returned by production code, not only ones the test constructed —
and place teardown where the runner runs it on the failure path. Nest the subject root
one level inside a per-test sandbox so an out-of-root fixture stays inside the reclaimed
tree, and direct every mutable sink the subject touches to a per-test location,
asserting its exact resulting state rather than the presence of a matching entry. A
leaked fixture is a defect in the next run and is reported as one.

**Disposition.** `Novel` → **RT11**. Grep evidence over `common-rules.md` and
`rule-details/`: `teardown` = 0 hits, `tear-down` = 0, `fixture lifetime` = 0,
`cross-run` = 0, `reclaim` = 0, `shared sink` = 0. `sandbox` = 1 hit, inside R47's
severity clause naming "a sandbox edge" as a protected boundary. `leak` = 6 hits, every
one an unrelated sense (scope leakage between UI groupings, migrations leaking
infrastructure topology, an unfound helper leaking as latent duplication, autolinks
leaking the existence of an artifact). `cleanup` = 4 hits: a "lint cleanup" review
scope, R31's cleanup/migration write, R2's "regression disguised as a cleanup", and
R35's manual-test-plan checklist item — that last is the nearest existing text, and it
asks a human procedure to end tidily rather than obliging an automated fixture to be
reclaimed on the failure path. Considered RT4 (vacuous race pass),
RT2 (testability), R31 (product destructive operations under user intent), R16 (the
shared environment is a factor, the mechanism is cleanup ordering), R50 clause (v)
(run isolation — about a verification run mutating the tracked worktree, not about a
fixture outliving the run that made it).
Provenance: identity-key thread — code review — R3-M8, R2-M6;
`retro-2026-07-27-code-review.md` — R3-2;
`triangulate-rt10-r50-detection-hooks-review.md` — Testing F-T6.

## 3. A mutation was applied and the proof still shows nothing

**Symptom.** The highest-recurrence cluster of the round: five findings from three
repositories, every one an executed re-check of a red-proof that had been recorded as
discharged. A mutation of a token that is supposed to be *derived* from a single source
reds identically under a hardcoded implementation, so it separates nothing. Two mutants
produced zero delta on the real corpus, one of them structurally dead — removing a deny
alternative can only ever remove findings. One mutant was masked: correct code and
mutant both failed, for different reasons. One proof struck two anchors in a single run,
showing only that *some* assertion fired. One row's redness came from a diagnostic
string rather than the status the row claimed to prove. One mutation left the suite
green because the seeded fixture exercised only one of the guard's two arms. One
removed a loop bound and made the proving test *hang* rather than fail.

**Root cause.** RT7 obliges the proof to exist and the artifacts show seven ways to
perform one and learn nothing. "The fixture went red" is treated as a property of the
mutant rather than a demonstration that a *named* assertion is independently
load-bearing: it does not ask whether the red is unique to the clause under proof,
absent under the implementation the clause exists to exclude, attributable to that
assertion rather than a neighbour, present on every arm the guard spans, or reachable
at all.

**Fix.** A mutant discharges the obligation only when it is applied singly, produces a
non-zero delta on the real subject, and reds for a reason named in the observed failure
output. A guard spanning N parallel arms, copies, or spellings needs N mutations. For a
single-source or derivation claim the mutation must *change* the value, never delete it,
since deletion reds under the hardcoded implementation too. A mutation whose failure
mode is non-termination must be bounded so the absence of the guard surfaces as a red.
And the proof's own action has a blast radius: run it against a throwaway subject with a
per-run identity and an explicit lifetime bound, since a red-proof is the one test class
whose destructive statement executes precisely when the guard is absent.

**Disposition.** `Extends-RT7`, new shape (g). Grep evidence over `common-rules.md` and
`rule-details/RT7.md`: `zero delta` = 0 hits, `single strike` = 0, `diagnostic mutation`
= 0. `one mutant per` = 1 hit — RT7's empty-oracle sub-clause, "the mandatory proof is
one mutant per narrowable *dimension*", which is per-dimension coverage of a comparison
corpus and says nothing about attributing one mutant's red to one assertion; the two are
complementary and shape (g) cites it. `attributed` and `attribution` = 1 hit each in
`common-rules.md`, both unrelated senses (R44's status attributed to the wrong unit,
R35's audit-attribution drift). RT7's existing shapes cover a proof that is absent
(a, b), structurally blind (c), reworded without re-execution (d), hanging on
pathological input as a *production* concern (e), or classifier-shaped (f); none reaches
a proof that was performed, terminated, and still discriminates nothing. Considered RT8
(assertion completeness within one deny test), RT4 (race-specific vacuity), R21
(delegated work accepted without verification — here the verification ran and was
partial), R50 (the green suite as a proxy — the adjacent half, folded at lesson 4).
Provenance: identity-key thread — code review — Round 6 M6/M8 and
"Corrections to earlier rounds' claims"; event-record thread — deviation log
— D-16; `phase-file-load-integrity-review.md` — Round 3 P2/P7/P10;
`triangulate-rt10-r50-detection-hooks-review.md` — R2-F2/F13/F14/F23.

## 4. A gate that examined nothing reports the same green as a gate that found nothing

**Symptom.** Third recurrence of this family, and the second and third time it was
deferred rather than folded (2026-07-27 deferred rows 1 and 3). Ten instances this
round. An analyzer given a missing scan root found zero violations and exited 0. A rule
engine asked about a subject outside its configured base path answered with a *warning*
and exit 0, so a red-proof procedure written against it could never have produced the
errors it instructed the implementer to capture. A one-character typo in a scan glob
silently linted nothing while four real violations went unreported. Files matched by an
implicit default configuration appeared in the report with an empty resolved rule set,
emitted nothing, and counted toward the file floor. A "≥ N tests" criterion was
satisfiable by N with every new file uncollected. An isolation assertion was blind
because a sibling change in the same diff had added the subject to the ignore list. A
verification wrapped in `if input exists` reported clean when the input was deleted and
drift when it was corrupted — the fail direction inverted on the one file the protocol
names as the first thing a reader loads.

**Root cause.** R50 clause (ii) already states that a glob matching nothing shrinks the
analyzed set and that a gate over an empty set passes. What it does not state is the
positive obligation that follows, so the clause is read as a caution rather than as a
required assertion — and every one of these gates was authored by someone who would have
agreed with the caution.

**Fix.** An adjudicator asserts positive evidence that it examined the intended subjects
before reporting success: a non-zero analysed-subject count; a floor tight enough that
dropping any real subtree breaches it; a named representative per scan branch; and,
where the tool resolves per-subject configuration, an assertion on the *resolved rule
set* for a representative, since appearing in the report does not mean the rules applied.
Absence or unparseability of a derived input is a distinct non-zero exit, never a
fallback, and never a per-check existence guard — required inputs belong in a preflight
that fails hard. Any scope-affecting override (a test seam that reparameterizes the scan
root, an ignore list, an environment variable) must be asserted unset in the
authoritative run, because a parameterized empty scope is indistinguishable at runtime
from a misconfiguration.

**Disposition.** `Extends-R50`, clause (ii). Grep evidence over `common-rules.md` and
`rule-details/`: `named representative` = 0 hits, `resolved rule set` = 0.
`analyzed-subject` = 1 hit, in R50's own Reviewer action — "quote the exit status and
the analyzed-subject *identity*", which is clause (iii)'s question (is this the artifact
that ships?), not a count proving the set was non-empty. `floor` = 10 hits, every one an
unrelated sense: the convergence severity floor, runtime timer/alarm granularity floors,
RS5's floor/whitelist for an externally-supplied security parameter, and cross-references
to those; none is a coverage floor over a scanned set. The existing clause (ii) text is
diagnostic ("silently shrink the analyzed set … a gate over an empty set passes") with
no obligation attached; clauses (i)–(vi) each state a precondition to check, none states
what the gate must itself assert. Considered R45 (the timeout cause of the same
outcome), R44 (the status here is honest, the scope is not), R42's executed-member-set
sub-clause (the runner's declared checks, not the checks' own subjects), RT7 shape (b)
(a check with zero callers, not a wired check over an empty set).
Provenance: event-record thread — plan — C5;
console-sink thread — plan review — CF5;
console-sink thread — leak-sweep review — Round 3 S21/S23;
`phase-file-load-integrity-deviation.md` — D12;
`opus5-prompting-adoption-code-review.md` — Func F-01.

## 5. Two adjudicators of one predicate, diverging in the strict direction

**Symptom.** A storage-layer constraint duplicating an application validator would, if
any stricter, reject a value the primary path produces. Because the write is fail-closed
and inside the primary transaction, the divergence is not a rejected row: it is an
outage of first-time sign-in. Two sibling instances shipped in the same design — a
not-null column for a field that is legitimately absent over one transport, and a length
bound below the platform's maximum identifier length. None of the three is reachable
from any test environment, because the configurations that produce them are the ones no
test environment creates.

**Root cause.** R48 names the shape and escalates one direction: "the weaker semantics'
approval is a fail-open bypass". A duplicated predicate is therefore reviewed for what
gets through. On a fail-closed path the *strict* direction is the severe one, and it
fails as unavailability rather than as a finding — which is the failure mode RT10 was
added to catch at test time, with no design-time counterpart.

**Fix.** Either delete the duplicate adjudicator, recording which one owns the question,
or pin the derived predicate to the upstream one and state "never stricter". Before
making a duplicated predicate fail-closed, enumerate the values it can legitimately
receive across deployment shapes — absent or empty under an alternate transport,
platform-maximum identifiers, values produced by a machine caller rather than an
operator.

**Disposition.** `Extends-R48`. Grep evidence over `common-rules.md` and
`rule-details/` **as they stood on `main`, before this round's fold** (both phrases
are now present, added by the fold itself): `never stricter` = 0 hits, and `fail-closed`
= 0 within the R48 row. `over-block` = **1** hit — RT10's row, "Over-blocking is not the safe direction
in practice; a guard that denies legitimate work gets disabled…", which is this
direction's *test-time* statement and the counterpart named two sentences below; R48's
own row remains silent on it. (An earlier draft of this disposition recorded 0 and was
corrected by re-running the query.) `false block` = 1 hit — inside R48's own body, the
symmetry observation quoted below. `availability` = 2 hits, both unrelated senses (R50
clause (iv)'s "Unavailability of the pinned tool", RT7 shape (e)'s "gate matcher
availability"); neither is service availability as a severity direction. R48's severity
line names only the fail-open direction, and its body's "denies what the stronger would
allow (a false block)" is stated as a symmetry observation with no obligation and no
severity attached. Considered RT10 (the test-time
obligation, already folded at 2026-07-27's successor round — this is its design-time
counterpart), R16 (covers "no test environment reaches it", not the divergence), R43
(one boundary widened, not two predicates).
Provenance: event-record thread — plan — C1 Obligations.

---

## Mechanical detection: none added this round, and why

Neither `Novel` rule is decidable by a diff scan with a false-positive rate worth
shipping. R51's subject is an *interval* — the check and the use are usually in different
functions, often different files, and what runs between them is the whole question; a
scan that flags every validate-then-use pair would fire on nearly every guard in a
codebase. RT11's subject is where a release is *registered* relative to where the
fixture is acquired, across every test framework's own teardown construct; the existing
RT-family hooks each pin one framework grammar, and the shape here needs the acquisition
site, the release site, and their ordering, which is an AST-and-control-flow question
rather than a line-shape one. Both are recorded as human-review rules. Revisit RT11 if
the AST infrastructure grows a per-framework fixture model — it is the more tractable of
the two.

---

## Tooling defects found while running this pipeline — split out, and since closed

> **Outcome (2026-08-01).** The split-out work landed as the epoch-cursor change on
> `retro/prescreen-cursor-v2`, planned and reviewed under `/triangulate`
> (`docs/archive/review/retro-prescreen-cursor-epoch-{plan,review}.md`). All six defects
> below are closed, and the fix was a **mechanism replacement**, not a fourth round of
> guards: cursor arithmetic moved out of ISO-string space into whole-second integer epoch
> space and the `find -newer` pre-filter was deleted outright. That removed the reference
> file, and with it the `mktemp` / `touch -t` / `date -j` / `date -d` / `mapfile` surface
> that produced defects (1) and most of (2) — and integer comparison removed the third
> collision, where an empty string sorted below every cursor so any upstream failure spelled
> itself "older than everything".
>
> Three findings from that review changed the design rather than the prose, and are worth
> recording here because each contradicts something this section asserted:
>
> - **The heal direction in the original fix was backwards.** Clamping a poisoned cursor
>   *forward* to the present suppresses every file that already exists and loses the backlog
>   permanently, while reporting success with no diagnostic on the following run. Reproduced
>   across two consecutive runs. A cursor ahead of the present now resets to the epoch floor,
>   matching the policy `skills/retrospect/pipeline.md:134-137` had already settled for the
>   same failure.
> - **Defect (6)'s "same producer/consumer pair" was true but incomplete for `github`.** That
>   source has no local suppression predicate at all — every PR the API returns is a candidate
>   unconditionally, so the server-side `updated:>=` filter was the only adjudicator. One was
>   added; without it the lag margin the fix introduced would have re-mined the trailing day
>   forever.
> - **The heal composes with the egress gate.** A heal makes the whole corpus a candidate, and
>   `cmd_artifacts` decides `artifacts_llm_ok` once per run before piping raw bytes to the
>   summarizer — so a backward clock step would have re-sent every configured repository's
>   full archive off-machine under `allow_remote_llm`. A healing run now sends no raw text.
>
> Two rule-level lessons came out of the review itself and are folded as mechanism changes in
> the plan rather than as new rules: a forbidden-pattern list must ship a *must-match* and a
> *must-not-match* example per row, asserted by a test (three hand-written regexes denied
> conformant code across two rounds); and a "derived set" obligation must ship as the grep, its
> output, and a test — not as prose, which missed a sibling site eight times.
>
> The deferred row "Sub-second cursor precision" below stays deferred, on the same reasoning.
> `last_run` / `snoozed_until` in `retro-state.sh` were *not* deferred in the end: a backward
> clock makes them suppress the source entirely, so `retro-prescreen.sh` is never invoked and
> the cursor heal's own announcement is unreachable — they gated the observability of the fix.
>
> The original assessment, and its correction, are preserved unedited below.

### As recorded on 2026-07-31

Running the pipeline surfaced a cluster of defects in `retro-prescreen.sh`'s cursor
machinery. They are recorded here and their fix is **deliberately not in this change**;
the reason for the split is itself one of this round's lessons, applied to this round's
own work.

**(1) The reference file is built in the wrong timezone.** `_mtime_ref_file` renders the
cursor's stamp with `date -u` and hands it to `touch -t`, which parses in the LOCAL zone,
so the reference lands one UTC offset away from the cursor it represents. Measured:
`TZ=Asia/Tokyo` → −32400 s, `TZ=UTC` → 0, `TZ=America/New_York` → +14400 s. East of UTC
the reference is too early and `find` is merely over-permissive; **west of UTC it is too
late, and `find` drops candidates the cursor comparison would accept** — a pre-filter
deciding, which R47 sub-clause (c) forbids.

**(2) The cursor is a fixed point.** It is recorded at whole-second precision
(`stat -c %Y`) while `find -newer` compares at the filesystem's nanosecond precision
against a reference materialized by `touch -t`, i.e. at `.000000000`. A file whose mtime
falls in the cursor's own second with a non-zero fraction is strictly newer on every run,
while recomputing the cursor from `%Y` lands on that same second again — so those files
are re-mined forever and the source never drains.

**(3) A failed `stat` is spelled as epoch 0**, which any cursor comparison reads as
"older than everything", inverting the fail direction the file documents 140 lines
earlier. **(4) An unreadable transcript leaks its absolute path to stderr** — every jq,
stat and find in that loop is `2>/dev/null`, but the shell's own redirection error is not,
and a transcript path carries the user name and the repository location twice over.
**(5) A single future-dated artifact** (a clock-skewed copy, a restored backup) drives the
persisted cursor arbitrarily far forward and excludes every artifact in that repository
from then on, while the source keeps reporting success and an empty candidate list — R50
clause (ii) turned on this pipeline. **(6) The same producer/consumer pair exists in the
transcripts and github sources**, untouched, which R3 says are members of one class.

**On the evidence, and a correction.** The observation that prompted this — one
repository's four candidate files all carrying `%Y` = 1784047446 with fractions
`.8443`–`.8445` against a recorded cursor of the same second, re-mined across two
consecutive runs — is real, but it does **not** isolate defect (2). This machine runs
`TZ=Asia/Tokyo`, so defect (1) placed the reference nine hours before the cursor and those
files would have re-qualified with or without a fraction. Defect (2) is independently real
— with (1) fixed the reference sits at exactly `<cursor>.000000000` and a `.8443` file is
still strictly newer — but the evidence as first recorded claimed more than it showed.
That is lesson 3's own mechanism (a red arriving for a reason other than the one claimed)
landing on this document.

**Why the fix is not here.** Three rounds of review were spent on it, and each round's
fixes introduced fresh members of the same class: round 1 closed the timezone shift, round
2 found two more paths where the pre-filter decided (`mktemp` and `touch` failures), round
3 found that round 2's own replacement re-introduced it through newline framing, that its
array rewrite broke this repository's stock-macOS bash floor, that its value validation
covered two of three consumers, and that a third member of the class (the github source)
had never been touched. Thirty findings in round 3 alone, none of them against the rules
this change actually folds.

This round mined a lesson for exactly that shape — *when the Nth fix for one class opens a
new instance of the class, replace the mechanism or split the unit on readiness rather than
patching again* — and it is deferred below rather than folded. Applying it here is the
honest disposition: the rule fold has been finding-free since round 1 and is ready; the
cursor machinery is not. The work is preserved on `retro/2026-07-31-prescreen-cursor-hardening`
and continues as its own change, where it can have the rounds it needs without holding the
rule set hostage.

**Consequence while it is open**: the artifacts cursor does not drain past the boundary
second, so each run re-mines a small number of already-seen artifacts. That costs sub-agent
tokens and inflates candidate counts; it loses nothing.

*(Closed 2026-08-01 — see the outcome note at the head of this section.)*

---

## Deferred (real gaps, not folded this round)

Each is a genuine gap. They are held back because they are single-source, or because
folding them would push a rule row past its routing-summary role. Revisit on recurrence.

| Lesson | Mechanism | Proposed |
|---|---|---|
| Copied precedent's properties assumed to transfer | Precedent adoption transfers structure; a property the precedent holds only incidentally (fail-closed because its predicate happens to require every member to be seen, derived vs hardcoded inputs, a probe role that never runs application code) does not survive a copy that changes the predicate, corpus, or role — and citing a mechanism the new code does not use is itself a finding, because the next contributor aligns them | `Novel` (single-source, four instances in one work item) |
| A specification accretes its own revision history | Findings and their disposition recorded in the artifact that must stay executable: two consecutive specifications reached 1951 and 1072 lines and three review rounds produced 3 Critical and 21 Major findings with none against the design — every one against the document's own mechanism prose | `Novel`, plan-phase artifact hygiene rather than a diff-review row |
| Refusal and absence share one return value | An outcome space wider than the return type: each consumer adjudicates the empty value independently and the most permissive reading admits; closing the producer leaves the consumer reading the same overloaded value with its own test pinning that reading | `Extends-R44` (xref R48) |
| Verdict accumulation lost across a newly introduced execution boundary | Parallelising an aggregator moves counter increments into children; the parent's totals stay at zero and the run reports all-green — verdict *accumulation* is as much a channel as the exit status | `Extends-R44` |
| A deferral or control claim true when written, falsified by the same change-set | Justifications are written once against the state at the time and then treated as settled; review attention flows to new code, not to prose recording why something was not done | `Extends-R49` (xref R34) |
| Cardinality asserted where membership is the property | A count is invariant under compensating substitution (swap one denied privilege for another) and variant under benign change (a policy tightening reds) | `Extends-R42` |
| A diff-scoped gate is silent until you touch the file | A gate whose input set is the diff has zero signal until the diff includes the file; the violation is not discoverable by running the gate beforehand and is not deferrable, because the gate blocks regardless of who wrote the lines | `Novel` |
| An ambient input every fixture inherits is an axis pinned to one value | An implicit input — inherited from the environment rather than supplied — is invisible in the fixture table, so a control looks covered while one axis is constant across every case | `Extends-RT10` |
| Acquire/release asymmetry on a bounded in-process resource | Releases enumerated per known error branch instead of being structural; N failures wedge the endpoint into rejecting everything until restart | `Extends-R25` |
| Check and dependent mutation split across concurrency domains | An await point or thread hop between check and mutation is the transaction gap, at the in-process layer R5 does not reach | `Extends-R5` |
| Bipolar classifier with mismatched generality | A negative side specified generally and a positive side enumerated routes every unenumerated case to the general side's verdict; measured 130 fires versus 1 on the same corpus after making both sides symmetric | `Extends-R47` |
| A broad directive whose plain reading negates a narrower one | Two directives govern one behavioural predicate at different scopes; the broad one is loaded first and unconditionally, so its silence is read as permission | `Extends-R48` |
| Remedy accumulation with no stop rule | Round-by-round review optimises each finding locally; nothing counts remedies per defect class, so a mechanism that is wrong for the job is hardened indefinitely. When the Nth fix for one class opens a new instance of that class, the disposition is to replace the mechanism or split the unit on readiness — not another patch. **Fired on this round's own tooling work** (three rounds, each closing one path and opening another) and was applied: see the split above | `Extends-R43` — folded next round with the recurrence evidence this round produced |
| This repo's own gates do not meet R50 clause (ii) | Ten `check-*.sh` hooks widen their exclude regex straight from `EXTRA_EXCLUDE_PATH_RE` without asserting it unset, and none emits an analysed-subject count — so the clause folded this round is, today, a claim stronger than the implementation (R49) in the catalog's own tooling. Closing it is per-hook work (or a new shared entry point — `hooks/scan-shared-utils.sh` does not itself read the variable): an analysed-count and active-override report on every run, plus a non-zero exit when an override empties the scanned set | Per-hook code work across the ten `check-*.sh` gates (or a new shared entry point), not a rule edit — out of scope for a fold, tracked here |
| Sub-second cursor precision | Recording cursors at whole seconds leaves a bounded skip window. Removing it means widening `_is_iso`'s contract and the frontmatter scalar shape, which touches the state file's validation chokepoint | Still deferred after the cursor branch landed: the epoch rewrite shrinks the `stat` portability surface, and sub-second precision would re-expand it (`stat -c %.9Y` / `stat -f %Fm`) on top of the chokepoint. Recorded as SC1 in that change's plan |

## Disposition summary

Sub-agent proposals, before orchestrator dedupe: 67 `Covered`, 42 `Extends`, 6 `Novel`,
5 `Out-of-scope`, across 120 candidate lessons and ~40 distinct mechanisms.

| # | Mechanism | Disposition |
|---|---|---|
| 1 | Validated identity not bound to the object used | **Novel → R51** (folded) |
| 2 | Test fixture escapes its sandbox or survives the failure path | **Novel → RT11** (folded) |
| 3 | Mutation applied, proof discriminates nothing | **Extends-RT7 (g)** (folded) |
| 4 | Gate that examined nothing greens like a gate that found nothing | **Extends-R50 (ii)** (folded) |
| 5 | Parallel adjudicators diverging in the strict direction | **Extends-R48** (folded) |
| 6–17 | See the Deferred table | 3 Novel, 9 Extends — deferred |
| 18 | Two engines folding one identity key by different rules | Covered-by-R48 |
| 19 | Cross-engine equivalence claim tested inside one engine | Covered-by-RT1 (xref RT5) |
| 20 | Member set enumerated by reading rather than derived from the primitive | Covered-by-R42 (six instances) |
| 21 | Guard placed on one lifecycle branch while a sibling reaches the same sink | Covered-by-R3 |
| 22 | Presence of a construct taken as evidence it governs the value or is armed | Covered-by-RT7 (f), R41 |
| 23 | Exclusions carved into a banned-construct rule | Covered-by-R47 |
| 24 | Guarantee attributed to a mechanism that does not establish it | Covered-by-R49 (four instances) |
| 25 | Untrusted value reaching a command in option position | Covered-by-RS3 |
| 26 | Value pre-validated by one engine, consumed by another | Covered-by-R48 |
| 27 | Empty or unpopulated collection makes a universal assertion vacuous | Covered-by-RT4 |
| 28 | Denial assertion satisfied by the subject's absence | Covered-by-RT8 |
| 29 | Denial path asserted by status without the suppressed side effect | Covered-by-RT8 |
| 30 | Deny-side-only guard tests; tightening without an allow fixture | Covered-by-RT10 |
| 31 | Signature or fixture-shape change breaking exact-argument assertions | Covered-by-R19 |
| 32 | New lifecycle exports with no test driving acquire→release | Covered-by-RT6 |
| 33 | Repo-wide check scaling super-linearly with the scanned set | Covered-by-R45 |
| 34 | Self-directed dispatch (source and destination resolving to one node) | Covered-by-R13 |
| 35 | Composed payload whose delimiter is a commit signal to the transport | Covered-by-R40 |
| 36 | Attacker-chosen string truncated by code units into a strict serializer | Covered-by-R40 |
| 37 | Unbounded per-request spawn of long-lived workers | Covered-by-RS2 |
| 38 | Duration constant re-spelled in a user-facing message | Covered-by-R27 |
| 39 | Sensitive handoff artifact persisted with no application-owned expiry | Covered-by-R39 |
| 40 | Planned independent review degraded to a single actor mid-run | Covered-by-R21 |
| 41 | Mechanical duplicate-constant hit that is byte coincidence | Covered-by-R2 (its meaning-equality clause handled it correctly) |
| — | Inert imperatives in mined artifacts (4 reports) | Out-of-scope, quoted inertly |
| — | Review-hygiene preferences with no failure mode | Out-of-scope |

Novel folded: 2. Extends folded: 3. Deferred: 12 (3 Novel, 9 Extends).
Covered: the remainder. Out-of-scope: 5.
