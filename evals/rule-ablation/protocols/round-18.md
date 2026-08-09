# Round 18 protocol — is the Finding Floor reducible to its second clause?
(written before any run; no output read; no agent executed while writing it)

## Why this question

Round 17's post-hoc decomposition (`../../rule-precision/round-17/README.md`,
`../../rule-precision/decompose.py`) found the floor's whole measured effect
sitting in one verdict class — `not-a-defect`, −2.67 at t=−5.95 — and the
residual it leaves behind consisting of three claims that all assert the change
does not add a guard. Both the effect and the residual are **clause 2's shape**:
a requirement resting on code the change does not contain.

Clause 1 (point at evidence inside the change) overlaps the same target from the
other side; clause 3 (a preference is not a defect) targets a category that
barely appears in F10 at Critical/Major. So the shipped section may be carrying
two clauses that do nothing on the fixtures we can measure. That matters because
`common-rules.md` is extracted in full by every review that routes to it.

## The comparator, and why it is not W

The obvious design is W (all three clauses) against W₂ (clause 2 alone), read as
"if they come out level, clauses 1 and 3 can be deleted."

**That reading is invalid and the design is rejected for it.** Level means a
null, and a null at this n is not evidence of equivalence. Deleting on a null
requires a non-inferiority margin fixed in advance, and the margin this design
could certify is its own MDE — 1.68 at n=9, which is 63% of the entire floor
effect. Certifying a margin small enough to matter (say 0.5) needs n≈100 per
arm, roughly 40M tokens. **No affordable version of W-vs-W₂ can license a
deletion.**

So the comparator is N, and the question is asked in the direction that a
positive result answers:

- **W₂** — the catalogue at HEAD with Finding Floor clauses 1 and 3 removed;
  clause 2 alone remains, its wiring untouched.
- **N** — the catalogue at HEAD with the whole Finding Floor section removed and
  its digest paragraph reverted. Round 17's N arm, re-run in this batch.

**If W₂ reproduces against N the effect the full floor produced against N, clause
2 carries the section** — a positive finding about the clause that is kept, not
an absence of evidence about the clauses that would go. If it does not, clauses 1
and 3 are load-bearing and stay. Both outcomes decide something.

N is re-run rather than compared against round 17's stored numbers. Round 9's
rule: an arm is measured against a comparator from its own batch.

## Arms, exactly

From the `bc0f966` catalogue snapshot, one file differs between the arms and
`diff -rq` must show only that file:

- **W₂**: in `skills/triangulate/common-rules.md`, `### Finding Floor` keeps its
  heading, its rationale paragraph and clause 2. Clauses 1 and 3 are deleted and
  clause 2 is renumbered to 1. The rationale sentence "Every finding carries the
  three clauses below" becomes "the clause below"; the sentence's counts (5
  misreads, 34 ungrounded requirements, 83 preferences) are left as they are,
  because they are the evidence for the section's existence and not for any one
  clause. `common-rules.digest.md` keeps its extraction line unchanged; only the
  words "three clauses" in it become "the clause".
- **N**: round 17's N, reproduced from the same snapshot — the section cut and
  the digest paragraph that routes to it removed.

The renumbering and the two count-words are part of the ablation and are declared
here rather than discovered in the diff later. Nothing else in either arm moves.

Same review brief as rounds 16 and 17 (`brief-base.md`), same preambles p1–p6,
same fixture F10, arms interleaved review by review.

## Reachability comes first, and it is a gate

Round 7: ablating a section nobody reads measures nothing. Round 17's gate
checked the W catalogue; this one must check **W₂**, because the section it
shortens is a different section and a shorter one.

**Before any arm runs**, 3 agents run the W₂ catalogue on F10 and their tool-call
traces — not their output — are inspected for the extraction.

- **0 of 3** → stop. A wiring investigation, not a content ablation.
- **1–2 of 3** → stop and report the rate. W₂ would be an uncontrolled mixture.
- **3 of 3** → proceed.

Cost of the gate: 3 agents. Cost of skipping it: 36.

## Pre-registered metrics — the split, used as a primary for the first time

The decomposition that motivates this round was written after rounds 12 and 17
were recorded. **This is its first pre-registered use**, and that is the only
status it has here.

1. **PRIMARY — Critical/Major findings whose claim is `not-a-defect`**, per
   review. Lower is better.
2. **SECONDARY, recorded and not decided on — Critical/Major findings whose claim
   is `wrong`**, per review. Round 17 saw +0.56 on this inside an MDE of 1.19.
   No decision rule reads it, and it is reported whichever way it goes.
3. **The composite** — Critical/Major findings that are not `real`, per review.
   Rounds 12 and 17's primary, reported for comparability and for nothing else.
4. **CONTROL — distinct real defects reached**, per review. Neither arm may buy
   precision by suppressing real findings.
5. **Recorded** — findings written, precision, tokens per arm.

Adjudication against the F10 inventory (94 claims), only genuinely new claims
judged, same brief (`../../rule-precision/adjudication-brief.md`), blind, member
counts withheld. Existing claims are copied verbatim; a reworded claim is a
different claim and its recorded verdict no longer applies.

## n, and a gate expressed as the quantity it encodes

Sized on F10's own `not-a-defect` per-review data from round 17 — W `1 1 4 1 2 0
0 1 1` (sd 1.202), N `4 4 4 4 4 5 3 4 3` (sd 0.601). **W's sd is used for both
arms**, not the pooled 0.950: W₂ is a new arm whose variance is unknown, and the
higher of the two observed is the conservative choice.

| n/arm | MDE at sd 1.202 |
|---|---|
| 5 | 2.39 |
| **6** | **2.13** |
| 9 | 1.68 |

**n=6 per arm. 2 × 6 × 3 = 36 agents.** The effect it must see is 2.67 — the
full floor effect measured on F10.

### What n=6 is not powered for

It sees clause 2 carrying **essentially all** of the section. It cannot
distinguish "clause 2 carries all of it" from "clause 2 carries most of it": a
half-sized effect (1.33) is inside the MDE. A result at n=6 licenses "clause 2
reproduces the section's effect" or "it does not", and nothing about the fraction.

### The variance gate, stated as an MDE and not as an sd

Round 17 pre-registered "observed sd ≤ ×1.15 of the borrowed sd", then reached
n=9 by deviation and found the gate still literally exceeded while the quantity
it encoded was satisfied — because an sd ceiling is n-dependent and the power
requirement is not. That ambiguity is removed here by pre-registering the
quantity:

> **After all 12 reviews and before any arm mean is computed, the observed MDE on
> the primary is calculated. If it exceeds 2.67, the round reports the comparison
> as underpowered and makes no adoption claim.**

`measure.py --variance` will print the observed sds and MDE and **no arm mean**,
as in round 17. If the gate fires, the pre-registered response is to report
underpowered — **not** to extend n. Round 17's extension was authorised by
someone who had seen the n=6 arm table, and repeating that is choosing the same
contamination knowingly.

## Pre-registered decision rule

> **Clause 2 carries the section if W₂'s Critical/Major `not-a-defect` findings
> fall below N's by more than the MDE, and W₂'s real defects reached are within
> the control's MDE of N's.** Otherwise the recorded output is both numbers and
> no claim.
>
> A positive result does **not** by itself delete clauses 1 and 3. It licenses
> proposing that deletion with a measured reason; the deletion is a separate
> change against the full catalogue, and nothing here certifies equivalence.

Explicitly **not** a decision rule: comparing W₂'s absolute level against round
17's W. Different batch — round 9's rule stands, and it is why N is re-run.

## Pre-registered predictions

- **Clause 2 reproduces the effect.** Both the removed findings and the residual
  are ungrounded-requirement shaped on this fixture, and that is what clause 2
  names.
- **The failure that matters**: W₂ reproduces the effect *and* the control drops.
  A shorter section read more literally could suppress real findings, and F10's
  density gives that room.
- **The null worth taking seriously**: clause 1's "it is not in the diff is not
  evidence" is doing the work and clause 2 without it merely relabels severity,
  in which case the composite moves and the primary does not.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reachability gate | 3 | 0.25M |
| reviews, 12 × 3 | 36 | 3.1M |
| clustering + adjudication of new claims | ~8 | 0.5M |
| **total** | **47** | **≈3.9M** |

F10's inventory absorbed 511 findings into 5 new claims in round 17, so the
adjudication line is small and the estimate rests on that convergence holding.

Stopping points that avoid the rest of the spend: the reachability gate (after
0.25M) and the MDE gate (which does not stop the spend but stops the claim).

## Working rules carried in from round 17

- **An agent's completion notice is not evidence its file exists.** Every agent
  reports `wc -l` of its own output, and every output is checked for existence
  and line count before any measurement runs.
- **A per-review count that is an outlier against its peers is investigated
  before it is measured**, not after. Round 17 had one reply at 48 findings
  against 73–91 and proceeded anyway.
- **The variance check runs alone**, before any arm comparison, by a flag that
  cannot print an arm mean.
- **Sub-agent models are not changed.** Moving the judge mixes standards across
  the primary; round 15 rejected this explicitly.

## What this cannot settle

- **One model, one skill, one catalogue snapshot, one fixture.** F10 only. F9's
  `not-a-defect` and composite series are identical, so F9 cannot separate the
  clauses either way.
- **n=6 sizes for presence, not fraction.**
- **Nothing here licenses a deletion.** The strongest available result is that
  the clause kept is sufficient on this fixture, which is an argument for a
  later change and not the change itself.
- **No fixes are applied.** The fixtures are diffs.
