# Titles are enough — 2026-08-06

Handing a second wave only the **titles** of what the first wave found buys
everything handing it the full findings buys: the same coverage, the same
restatement suppression, to the second decimal place. The pre-registered rule
fires for the cheap form.

It fires on weaker ground than it looks, and the reason is worth more than the
result: **round 14's cost penalty did not replicate in this batch**, so the rule's
second condition was met partly because the arm it was measured against lost its
own penalty. The skill is not changed on that.

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

## What is and is not established

**Established, across two batches:** conditioning a second wave on what the first
found suppresses restatement almost completely (30.00 → 0.17) and converts it
into real coverage (+3.33 here, +2.00 in round 14).

**Established here:** if you condition, **titles are enough**. The full text buys
nothing over them on any measured dimension, and costs more input.

**Not established, and now less settled than it was:** whether conditioning costs
precision. Round 14 said yes at n=8; round 15 says no detectable difference at
n=6, and the comparison arm's own penalty moved by more than the effect under
test. **Two batches disagree**, which is a weaker state of knowledge than round
14 alone appeared to leave.

## Why the skill is not changed

Shipping T means adopting conditioning, and round 14 declined to adopt
conditioning on cost. That cost question is now open rather than answered, so
adopting on the strength of a rule whose second condition rested on a
non-replication would be reading the batch that happens to agree.

What the round does license: **if conditioning is ever adopted, it should be the
titles-only form.** That is settled and it is cheap — the treatment is a list of
one-line strings.

## What this cannot settle

- **One fixture**, six reviews, identical generalists, one level of conditioning.
- **No fixes applied between waves**; a real second round reviews changed code.
- **The base is from an earlier batch**, shared by all three arms, so it cannot
  bias the comparison.
- **The cost disagreement needs a third batch**, ideally at n=8, before either
  reading is trusted.
