# Rule ablation — 2026-08-04

110 review runs across eight fixtures, measuring whether the triangulate rule set
changes what a review produces. Protocol and fixtures: `evals/rule-ablation/`.

Four rounds. Rounds 1 and 2 each produced a headline the next round retracted;
both retractions are kept in place rather than edited out, because a measurement
log that quietly replaces its wrong answers is not a log. Round 4 changed what
was being scored and found the first effect that replicated.

## Why

Anthropic removed over 80% of Claude Code's system prompt for the Claude 5
generation with no measurable loss on their coding evaluations, and the
context-engineering guidance names "exhaustive rule catalogs" and "comprehensive
upfront context loading" as anti-patterns.

The comparison that matters is not the 80%. It is that **they knew deletion was
safe because they had evaluations.** This repo had 74 rules and none.

## Arms

- **A** — pattern-name index + the target rule's full procedure (one rule, spotlit)
- **B** — pattern-name index only. The measurement of shrinking a row to its digest line.
- **C** — no catalogue
- **F** — the **deployed configuration**: the digest as routing index, all 74 rows
  available, `rule-details/` pages, and SKILL.md's extract-what-matches protocol

## Rounds 1–3: detection

| Fixture | Rule | Shape | A | B | C |
|---|---|---|---|---|---|
| F1 | R44 | 1 file | 2/2 | — | **3/3** |
| F2 | R56 | 1 file | 2/2 | — | **3/3** |
| F3 | RT8 | 2 files | 2/2 | — | **3/3** |
| F4 | R54 | 1 file | 2/2 | — | **3/3** |
| F5 | RT9 | 8 files | 3/3 | 3/3 | 3/3 |
| F8 | RT9 | 8 files, twin cues removed | 3/3 | 3/3 | 3/3 |
| F6 | R54 | 8 files, buried | 8/8 | 6/8 | 6/8 |
| F9 | R54 | 8 files, buried, other domain | 8/8 | — | 8/8 |

**Round 1's retraction.** From n=3 on F6: the name-only arm scored *worse than no
catalogue* (2/3 vs 3/3). At n=8 both are 6/8. Noise.

**Round 2's retraction.** What survived that: on F6 the full procedure hit 8/8 at
Critical rank 1 against 6/8 for the others. F9 reproduced F6's shape in another
domain — Arm A 8/8, Arm C 8/8, no difference. Fixture-specific.

Across rounds 1–3, **no detection difference survived replication.**

## Round 4: score the remedy, under the deployed configuration

Detection was saturated, so the remaining question was what each arm proposes to
**do**. Both arms were asked for a `Fix:` on every Critical and Major finding.

R54's procedure prescribes three things. Each scored as a binary:

1. **call-scoped** — a derived context or an acquire/release wrapper, not
   "reset it afterwards" (which the rule names as the wrong shape)
2. **error path** — the restore happens on the throw path too
3. **same-context test** — assert the control still refuses in the SAME context
   immediately after the sanctioned call returns

| | detection | call-scoped | error path | same-context test | total |
|---|---|---|---|---|---|
| **F9 · Arm F** | 8/8 | 8/8 | 8/8 | 8/8 | **24/24** |
| **F9 · Arm C** | 8/8 | 8/8 | **1/8** | 6/8 | 15/24 |
| **F6 · Arm F** | 8/8 | 8/8 | 8/8 | 8/8 | **24/24** |
| **F6 · Arm C** | 5/8 | 5/5 | 5/5 | **0/5** | 10/24 |

**Every Arm F run scored 3/3. No Arm C run in either fixture scored 3/3.** 16 and
0 out of 16.

The clause Arm C drops is not stable — on F9 it loses the error path seven times
in eight; on F6 it takes `finally` every time (natural for `SET LOCAL`) and never
once asks for the same-context test. **The unaided reviewer reaches two of three,
and which two is fixture-dependent.**

F6 also shows a detection gap that rounds 1–3 saw and round 4 confirms: Arm C
missed the defect entirely in 3 of 8 runs, Arm F in 0 of 16.

This replicated on a second fixture **before** being written down, which the two
retracted claims did not.

## Round 5: the rubric was too small, and round 4's headline was wrong

Round 4's rubric came from R54's own text, so the arm holding R54 was scored
against the document it had been handed. Round 5 fixed that: ten agents, five per
defect variant, given only the defective code and asked to enumerate every
property a correct fix must have. None saw the rule set; each had the whole task
to itself. Full method and result: `evals/rule-ablation/independent-rubric.md`.

**The good news for round 4.** Its three clauses — scoped construct, restore on
the error path, test the next write in the same context — were all required by a
panel that had never read R54. They are not an artifact of self-scoring.

**The bad news.** The panel demanded **six more**, unanimously, and R54 taught
none of them: restore the *previous* value rather than a hardcoded off; **await**
the covered work before restoring; do not mutate caller-shared state; abort if
the restore itself fails; test the throw path; test nesting or concurrency.

One panellist named the consequence precisely: **a naive `try/finally` on the
shared object passes the return-path and throw-path tests and fails only the
concurrency one.** The two tests R54 asks for certify exactly the wrong fix.

So round 4's headline was wrong in the direction I had not guarded against. Not
"the rules produce a complete fix and their absence does not", but:

> Carrying the rules reliably produces **the three properties the rule contains**.
> A correct fix needs about nine. **Neither arm produced those.**

R54 has been extended with the six (`skills/triangulate/rule-details/R54.md`).
That extension is a fold made under this eval's own standard — direct evidence
that sixteen reviewers holding the rule still fixed it wrong — and it is owed its
own ablation before anyone claims it works.

The blinded re-score of the 32 round-4 fixes against the nine-property rubric is
set up (`evals/rule-ablation/score/rubric.md`) and **not run**. Scoring them by
hand would reintroduce the bias round 5 exists to remove.

## Other limits

- Fixtures were authored by someone who knew the target rule. That bias runs
  toward legibility, which makes a null the weaker reading and a positive the
  stronger one.
- One rule (R54), two fixtures. Nothing here generalises to the other 73.
- Long-context conditions and later rounds of a fix loop are still untested.

## Scoring note

Oracles were fixed in writing before each run. Four detection trials named an
adjacent R54 clause — the GUC is unregistered, so the authority is a convention —
without naming the leak past the call, and are scored misses.

## Round 6: the deficit is the catalogue's, not R54's

The panel method applied to four more rules — R44, RT8, R56, RT9 — with four
panellists each. Full result: `evals/rule-ablation/panel-audit.md`.

| Rule | Properties the panel required | Present in the rule |
|---|---|---|
| R44 | ~13 | 2 |
| RT8 | ~11 | 2 |
| R56 | ~15 | 5 |
| RT9 | ~14 | 5 |
| R54 | 9 | 3 |

Every rule carries a quarter to a third of what an unhurried panel requires for
the defect it names.

**And the missing content is mostly already here, in a rule the reviewer did not
route to.** The same five classes were absent from all four: the allow-side case
that must still succeed (RT10), red-proof executed per clause (RT7), failing
loudly when the check cannot run (R50 ii), not fixing by deleting the useful
behaviour (R36's shape), and naming the boundary and the tie (R57).

The rules do not fail for lack of knowledge. Each is written as though its reader
will also apply the other seventy-three, and the reviewer applies the one they
routed to.

Sharpest instance: **RT8 — whose whole subject is "your test is vacuous" —
prescribes a vacuous remedy.** Its negative assertion passes unconditionally when
the mock wiring breaks, and it never asks for the positive control. All four
panellists did.

**Action:** `common-rules.md` gains a **Remedy Floor** — the five clauses stated
once and inherited by every `Fix:`. Five paragraphs instead of five times
seventy-four: total prose down, per-rule transmission up. It is not yet ablated,
and under `folding.md`'s own rule it does not get to claim it works until it is.

## Round 6.5 (2026-08-05): the blinded re-score, and what it corrects

The 32 round-4 fixes, recovered verbatim from the session transcript, arm
identity redacted (protocol headers, rule IDs, catalogue vocabulary, fixture
filenames), shuffled with a fixed seed, and scored by three independent agents
against the nine-property rubric in different orders. Majority vote per
property; pairwise scorer agreement 94.6–99.6%.

| | n | no-fix | mean /9 |
|---|---|---|---|
| F6 · Arm F | 8 | 0 | **6.25** |
| F6 · Arm C | 8 | **3** | 4.40 |
| F9 · Arm F | 8 | 0 | 7.25 |
| F9 · Arm C | 8 | 0 | 6.75 |

**What survives.** On F6 the arm-F advantage is real and blind: three arm-C runs
never fixed the defect at all, and among those that did, the same-context test
(P7) went 8/8 vs 0/5 and restore-previous-value (P3) 3/8 vs 0/5.

**What gets corrected.** Round 4 scored F9 arm C's error path at 1/8. Blind,
P2 is **8/8** for that same cell — the `AsyncLocalStorage` mechanism arm C
reviewers proposed restores on throw by construction, and the self-score missed
it. The F9 gap is a quarter of round 4's headline (7.25 vs 6.75), and six of
eight F9 arm-C runs carry all three of R54's original clauses. The honest
statement is now: **the rules' remedy advantage is real where the defect is
buried and the mechanism unfamiliar (F6), and marginal where the platform's
idiom already encodes the fix (F9).**

**What is confirmed.** P8 (throw-path test) is 2/16 for F and 0/13 for C; P9
(nesting/concurrency — the property a naive fix uniquely fails) is **0/29
across every arm and fixture**. Round 5's conviction stands blind: what no rule
teaches, no reviewer produces, with or without the catalogue.

## Round 7 (2026-08-05): the Remedy Floor — unreachable as merged, effective when wired

Protocol, pre-registered mappings, and preambles:
`evals/rule-ablation/` (round-7 section of the README) — metric subsets and the
floor mapping were written before any run output was read.

**The wiring gap.** The floor merged in #126 as a section of `common-rules.md`
that no routing path names: the digest doesn't mention it, SKILL.md's loading
protocol extracts triggered rows and named sections only, and phase-3's expert
requirements never cite it. A 4-run probe of the deployed configuration (F1,
varied preambles) confirmed by tool-call trace: **zero of four reviewers read
the section.** As merged, the floor was dead wiring.

**The ablation.** Arm W: HEAD materials plus one digest line wiring the floor
(extract the section, every Fix: satisfies it). Arm N: HEAD materials with the
floor section removed and the template pointer reverted. Same prompts, eight
paired preambles per fixture, n=8 per cell, on F1 (R44, shell gate) and F3
(RT8, vacuous denial test) — two rules untouched by #125, detection saturated,
panels demanding ~13/~11 properties of which the rules carry 2. Outputs
redacted (including the token "Remedy Floor"), shuffled, blind-scored by three
agents against the round-6 panels' merged majority rubrics; scorer agreement
89.8–95.7%.

| | floor-mapped subset | mechanism subset |
|---|---|---|
| F1 · W | **6.75**/8 | 8.62/11 |
| F1 · N | 5.12/8 | 7.75/11 |
| F3 · W | **3.88**/5 | 3.12/6 |
| F3 · N | 0.25/5 | 2.88/6 |

The discriminating properties are exactly the floor's clauses: on F3, the
positive control (7/8 vs 2/8), the wiring-break guarantee (8/8 vs 0/8), and
executed red-proof with the failure landing on the side-effect assertion
(8/8 vs 0/8 twice); on F1, the allow-side test (8/8 vs 0/8) and executed
red-proof (8/8 vs 1/8) — while the floor items R44's own routing already
covers (fail-loud via R50) sit saturated in both arms. The mechanism subsets
move a fraction of a point. **The floor transmits its own clauses, nothing
else, and only when routed to.**

Replicated on both fixtures in different domains before being written down.
Action taken: the digest generator now emits the wiring line round 7 tested,
and phase-3's expert requirements cite the floor. What this round does NOT
show: any detection change (saturated by design), and any effect of the floor
*without* the wiring — that condition measured zero reads.

## Round 8 (2026-08-05): the R54 extension — taught, they produce it

The counterpart to round 6.5's conviction. The blinded re-score showed the
concurrency test (P9) at 0/29 across every arm — nothing any reviewer carried
taught it, and no reviewer produced it. #125 extended R54 with six obligations
on exactly that evidence, and the extension was owed its own ablation.

**Arms.** E: HEAD materials (wired floor, extended R54). O: identical, except
`rule-details/R54.md` reverted to its pre-#125 content. One variable; the floor
stays wired in both. Same prompts, eight paired preambles, F6 + F9, n=8/cell.
Scored blind against the round-5 independent nine-property rubric (which
pre-dates and is independent of the extension), 32 outputs redacted and
shuffled into one set, three scorers, majority vote. Agreement 99.7–100%.

Pre-registered split: extension properties P3/P4/P5/P8/P9; control P1/P2/P7
(the original clauses, expected saturated in both arms).

| | ext (P3,P4,P5,P8,P9) /5 | orig (P1,P2,P7) /3 | total /9 |
|---|---|---|---|
| F6 · E | **4.12** | 3.00 | 7.50 |
| F6 · O | 0.25 | 3.00 | 3.62 |
| F9 · E | **5.00** | 3.00 | 9.00 |
| F9 · O | 1.75 | 3.00 | 5.75 |

- **P9 — the property that was 0/29 everywhere — is 16/16 with the extension
  and 0/16 without it.** P8 (throw-path test): 16/16 vs 1/16. P4 (await before
  restore): 16/16 vs 0/16.
- The control is exactly flat: P1/P2/P7 saturate at 3.00 in all four cells.
  The arms differ only in what the extension teaches.
- The honest exception: P5 (isolation — same connection handle for the GUC,
  fresh frame for ALS) reaches only 1/8 in F6·E against 8/8 in F9·E. The ALS
  phrasing ("fresh frame") lands; the Postgres phrasing ("same handle
  throughout") mostly does not. The one extension clause that under-transmits
  is the one whose wording is platform-split.

Round 6.5 established: what no rule teaches, no reviewer produces. Round 8
establishes the converse: **taught, they produce it — at full rate, on both
fixtures, with the control unmoved.** Together they close the question rounds
1–3 could not: the catalogue's value is not detection and not general "remedy
quality" — it is the specific, literal transmission of the clauses the routed
rule states. A rule is worth exactly what it says.

## Round 9 (2026-08-05): rewording obligation (c) — and what the same-batch control caught

Round 8 left one clause under-transmitting: P5 (isolation) at 1/8 on the GUC
fixture even when carried. The fix: (c) rewritten into two named variants —
FRESH FRAME for the context-carried flag, ONE HANDLE for the connection-scoped
setting, with the pooled-connection failure mode stated concretely and "name
which variant applies" made explicit.

**Arms.** Cnew: HEAD with the reworded (c). Cold: round-8 arm E materials
re-run fresh, so the F6 comparison is same-batch. Cells: F6×Cnew, F6×Cold
(n=8 each), F9×Cnew (n=8, regression check). Blind-scored as before; redaction
additionally strips the rewording's CAPS anchors and obligation-letter
references. Agreement 99.1–100%.

| cell | P5 | everything else |
|---|---|---|
| F6 · Cnew | **8/8** | saturated (P4 7/8; P6 2/8) |
| F6 · Cold | 5/8 | saturated (P6 1/8) |
| F9 · Cnew | 8/8 | **all nine at 8/8** — no regression |

The pre-registered bar is met: P5 rises on F6, nothing regresses, F9 stays at
ceiling. The rewording ships.

**What the same-batch control caught.** Cold's P5 came out 5/8 — against 1/8
in round 8, on byte-identical materials. A blind-scored baseline moved four
points between batches with nothing changed. Had round 9 compared Cnew only
against round 8's stored number, it would have claimed a 1/8→8/8 effect;
the defensible claim is "Cnew saturates P5 (8/8) against a same-batch 5/8,
direction as predicted". Round 8's P5-specific point estimate carries this
caveat now; its headline (extension properties E vs O, all cells within one
batch) is unaffected. The lesson joins the standing set: **arm comparisons are
valid within a batch; a stored cross-batch number is context, not a control.**

## Power audit (2026-08-06): which nulls here are worth anything

Every round above reports n. None reported the difference its n could have
caught, and the two are not the same statement. `score.py` now prints it for
each arm pair (`diff` against `MDE`, two-sided .05 at 80% power).

**The remedy nulls are tight.** Round 10 observed 0.25 against an MDE of 0.94 of
11; round 11 observed 0.00 against 1.79 of 34. Those bound the effect at roughly
5–9% of the rubric, which is a real statement.

**The detection nulls of rounds 1–3 are not.** Detection was scored as a binary
at n=8 per arm, where 8/8 against 6/8 is p=0.47 and even 8/8 against 4/8 is
p=0.077. Nothing short of 8/8 against 3/8 would have registered. "No detection
difference survived replication" is therefore true and much weaker than it
reads: those rounds could only ever have ruled out a very large effect, and the
F6 cell they did flag (arm C missing the defect in 3 of 8 runs) sits at p=0.20.

**One published point estimate is inside the noise.** Round 6.5's F9 cell —
"marginal where the platform's idiom already encodes the fix (7.25 vs 6.75)" —
is a difference of 0.50 against an MDE of 0.70. The direction is not
established; the F6 cell beside it (diff 1.85, MDE 1.21) is.

This audit costs one command over sheets already checked in, and it is the
cheapest instrument this eval has found. Run it before writing a null down.

## What follows

1. **Do not shrink rows to digest names.** Arm B measured exactly that and scored
   identically to carrying nothing.
2. **Report n, and replicate before writing.** Six claims from this eval have
   been corrected by the round that followed them — round 8's P5 point estimate
   joined when the same-batch control moved it from 1/8 to 5/8, and rounds 10–11's
   headline joined when an adjudicated defect inventory showed the metric could
   not see what it was being used to rule out
   (`2026-08-06-finding-precision.md`).
3. **Compare within the batch.** Round 9's same-batch control is the difference
   between an honest saturation claim and an inflated 1/8→8/8 one.
4. **Report the difference n could have caught, beside the difference observed.**
   A null read off a design that could only catch an enormous effect is not a
   null worth citing.
5. **Ask what the metric cannot see.** Rounds 10–11 scored the remedy for one
   seeded defect and concluded about the review as a whole. The scored slice was
   sound; the generalisation was not.
