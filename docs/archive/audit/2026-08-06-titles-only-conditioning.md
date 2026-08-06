# Titles are enough — 2026-08-06

Handing a second wave only the **titles** of what the first wave found buys
everything handing it the full findings buys: the same coverage, the same
restatement suppression, to the second decimal place. The pre-registered rule
fires for the cheap form.

It fires on ground that does not hold. Its second condition — *no worse than
blind on cost* — was met because a six-review batch could not resolve a penalty
round 14 had measured at n=8. **Pooled as fourteen matched pairs, that penalty is
real** (+1.57 Critical/Major non-defects, 95% CI +0.67 to +2.47), and the same
rule applied to the pooled data **fails**. So the cheap form is established and
**conditioning is still not adopted**; the skill is unchanged.

The sections below are left in the order they were written — the single-batch
reading first, the pooling that corrects it after — because a log that replaces
its wrong answers is not a log.

Protocol: `evals/rule-ablation/protocols/round-15.md`, pre-registered, with two
deviations recorded there. Reproduce with `evals/rule-precision/round-15/measure.py`.

## Design

Three arms on the same fixed base (round 13's first three reviewers per review):

- **T** — given the base's finding **titles only**: one line each, no file, no
  severity, no explanation.
- **C** — given the full base, as round 14 gave it.
- **I** — given the standard brief alone.

**Six of the eight pre-registered reviews ran**, halted against a budget ceiling
with the raw findings checked in rather than completed and left unanalysed. n=6
widens the detectable difference by about 19%; every number below carries that.
54 agents, 456 findings, 20 new claims adjudicated by the same blind panel under
the same standard. Inventory now 135 claims, 61 real.

## Result

| | T (titles) | C (full) | I (blind) | T vs C | T vs I |
|---|---|---|---|---|---|
| **real defects ADDED** | **7.83** | 7.83 | 4.50 | t=0.00 | **t=+4.26**, MDE 2.42 |
| **Critical/Major non-defects** | 3.33 | 3.50 | 2.67 | t=−0.21 | t=+0.74, MDE 2.81 |
| six-reviewer total | 23.67 | 23.67 | 20.33 | t=0.00 | t=+3.30, MDE 3.13 |
| restating the base | 0.17 | 0.17 | 30.00 | t=0.00 | t=−13.39 |
| findings written | 17.83 | 20.17 | 38.00 | t=−1.63 | t=−8.99 |

Base: 15.83 real defects. Per review, primary — T `6 7 7 9 9 9`, C `6 6 8 8 8 11`,
I `3 4 4 4 5 7`.

**T and C are identical on everything that matters.** Same coverage, same
restatement, same six-reviewer total, to two decimals. A title is enough to
recognise your own finding by; the file, the severity and the explanation add
nothing measurable.

**Both conditioned arms beat blind on coverage, decisively** — +3.33 real defects
against an MDE of 2.42, replicating round 14's +2.00 on a second batch and with
the arms not overlapping at all per review.

## The rule fired, and here is what it fired on

> Ship T if it is not worse than C on the primary and not worse than I on the
> cost, both judged against the difference this design can catch.

Both conditions hold: T equals C on the primary, and T's cost sits 0.67 above I
against an MDE of 2.81.

**But round 14's cost penalty did not replicate.** There, C filed 4.50
Critical/Major non-defects against I's 2.38 — a gap of 2.12 against an MDE of
2.05, the finding that made round 14 decline to recommend conditioning. Here the
same comparison is 3.50 against 2.67, a gap of 0.83. Same materials, same brief,
different batch — exactly the movement round 9 warned about when it found a
blind-scored baseline shifting four points on byte-identical inputs.

So the second condition was satisfied in a batch where **the arm it is measured
against also lost its penalty**. That is not a reason to distrust T; it is a
reason not to read "T costs no more than blind" as established.

## Pooling the two batches settles the cost question — against conditioning

Added after the tables above, and **post-hoc**: neither round pre-registered it,
so it is exploratory. `evals/rule-precision/pooled.py` re-derives it.

Arms C and I share a review id, a base and a preamble in both rounds, so each
review is a **matched pair** and the pooling is over 14 paired differences — 8
from round 14, 6 from round 15 — not over arm means. (Round 9's rule forbids
measuring an arm against a stored number from another batch. It does not forbid
combining two within-batch paired differences, which is what this is.)

| paired difference, C − I | mean | sd | se | t | 95% CI |
|---|---|---|---|---|---|
| Critical/Major non-defects | **+1.57** | 1.55 | 0.42 | +3.78 | **+0.67 to +2.47** |
| real defects added | +2.57 | 2.44 | 0.65 | +3.94 | +1.16 to +3.98 |

**Both intervals exclude zero.** Conditioning raises coverage *and* cost.

**Rounds 14 and 15 never disagreed about the sign.** Twelve of the fourteen pairs
show a positive cost difference; the batches differed in whether the effect was
*detectable*, not in its direction. Round 15's 0.83 was an estimate a six-review
batch could not resolve, and reading it as evidence of no penalty was wrong — the
correction above ("less settled than round 14 left it") overstated the
disagreement.

**Applied to the pooled data, round 14's rule fails on cost.** It said adopt only
if the non-defect count is no worse; the interval runs from +0.67 upward. So
**conditioning is not adopted**, and this analysis makes that firmer rather than
softer.

One thing this section must not be read as saying: 2.57 against 1.57 is a
**descriptive exchange rate, not a decision**. A real defect and a non-defect are
not the same unit, and dividing one by the other smuggles in a price the
measurement never set.

## What is and is not established

**Established, across two batches:** conditioning a second wave on what the first
found suppresses restatement almost completely (30.00 → 0.17) and converts it
into real coverage (+3.33 here, +2.00 in round 14).

**Established here:** if you condition, **titles are enough**. The full text buys
nothing over them on any measured dimension, and costs more input.

**Established once the two batches are pooled as matched pairs:** conditioning
does cost precision, +1.57 Critical/Major non-defects with a 95% interval of
+0.67 to +2.47. The batches never disagreed on the sign, only on whether a single
batch could resolve it. That is post-hoc and exploratory, and it is the reason
the paragraph this replaces — "two batches disagree" — was itself wrong.

## Why the skill is not changed

Shipping T means adopting conditioning, and the pooled analysis says the cost
penalty is real: round 14's rule, applied to fourteen matched pairs, **fails on
its cost condition**. Round 15's rule fired only because the single batch it ran
in could not resolve that penalty.

What the round does license: **if conditioning is ever adopted, it should be the
titles-only form.** That is settled and it is cheap — the treatment is a list of
one-line strings.

## What this cannot settle

- **One fixture**, six reviews, identical generalists, one level of conditioning.
- **No fixes applied between waves**; a real second round reviews changed code.
- **The base is from an earlier batch**, shared by all three arms, so it cannot
  bias the comparison.
- **The pooled analysis is post-hoc**, over two batches, and cannot separate a
  real batch effect from sampling noise. A third batch would sharpen it; it is
  not what the next budget should buy, because every result here still rests on
  **one fixture**.
