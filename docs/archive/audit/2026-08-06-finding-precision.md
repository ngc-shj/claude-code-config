# Finding precision, and what a second reviewer is worth — 2026-08-06

Eleven ablation rounds scored one thing: whether a review's fix for **one seeded
defect** carries the properties a correct fix needs. That is remedy quality on a
defect someone planted, and it is a narrow slice of what a review is for.

Two questions gate everything downstream of a review, and neither had ever been
measured here:

- **Are the findings accurate?** A finding that is not a defect costs the person
  fixing it the same attention as one that is.
- **How many genuine defects does a review reach**, and what does the second and
  third reviewer add — real defects, or restatements?

Tool, method and limits: `evals/rule-precision/`. Reproduce with
`evals/rule-precision/measure.py`.

## Method, and the one assumption that does the work

Round 11's material, reused: 48 review replies over F9, eight reviews per arm,
three replies each. **No new reviews were generated**, so nothing here rests on
a second batch — the comparison stays within one.

574 findings → 83 distinct claims (eight clustering agents, one per target file,
told not to judge truth) → three adjudicators, each shown the diff and the 83
claims **shuffled with the member counts withheld**, so a claim forty reviewers
made is indistinguishable from one a single reviewer made. Majority vote;
agreement 84.3–94.0%.

**39 of the 83 claims are real. 43 are not defects. One misreads the code.**

The panel was told to judge the diff as a real pull request into a real working
codebase where everything not shown exists and is correct. Without that
assumption every "X is absent from the diff" scores as a defect and precision
means nothing; with it, some findings a human would value are scored
`not-a-defect`. It is applied identically to both arms, so it moves the absolute
level and not the comparison. It is the first thing to argue with.

## Precision and coverage move in opposite directions

| | finding-level precision | distinct real claims reached, of 39 |
|---|---|---|
| **G** — three identical generalists | **81.6%** (253/310) | 16.8 |
| **S** — three specialised experts | 73.5% (194/264) | **19.1** |
| | t=+2.79, p<.05 | t=−2.22, p<.05 |

Specialisation reaches more genuine defects and wastes more of the reader's
attention getting there. Roughly one finding in four from the specialised arm is
not a defect, against one in five from the generalists.

## Where the split actually pays: the marginal reviewer

| | N=1 | N=2 | N=3 |
|---|---|---|---|
| **S** | 8.1 | 14.4 (**+6.3**) | 19.1 (**+4.8**) |
| **G** | 10.5 | 14.2 (+3.7) | 16.8 (+2.5) |

- **One generalist beats one specialist** (10.5 vs 8.1) — a specialist discards
  two thirds of the ground by design.
- **Two are level** (14.4 vs 14.2).
- **Three specialists win**, and their third reviewer still adds nearly twice
  what the generalists' third adds.

This is the mechanism the redundancy measurement predicted: specialised replies
overlap half as much as identical ones (pairwise Jaccard 0.116 vs 0.246,
t=+2.83). Three generalists keep finding each other's defects; three specialists
do not, so the marginal reviewer stays expensive for longer.

## This corrects rounds 10 and 11

Those rounds concluded that specialisation buys nothing, at 6.25 vs 6.50 and
24.88 vs 24.88. **Both numbers stand and the conclusion was too broad.** They
scored the remedy for one defect, where the arms are genuinely identical. They
never scored how many *other* real defects the review reached, which the round-11
pre-registration listed as tertiary and explicitly declined to claim — because
F9 had no adjudicated defect inventory. This built one.

The corrected statement: **who reads the rule does not change the fix that rule
produces; it does change what else the review finds, and it changes how much a
second and third reviewer are worth.**

## Against the cost

At the ~71k tokens a review agent used in round 11:

| configuration | tokens | real defects | per defect | of the 39 |
|---|---|---|---|---|
| one generalist | 71k | 10.5 | **6.8k** | 27% |
| three generalists | 213k | 16.8 | 12.7k | 43% |
| three specialists | 213k | **19.1** | 11.2k | **49%** |

Tokens per defect is best at N=1 and gets worse with every reviewer added — but
a single review round reaches **about a quarter** of the genuine defects the same
skill finds across eight runs. Where the objective is resolving defects in few
rounds, coverage per round dominates cost per finding, because a missed defect
buys another round of everything.

The honest counter-weight is the precision column: the specialised arm's extra
2.3 real defects arrive with about 15 more non-defects per review, and that lands
on the fix phase.

## What this does not establish

- **`real` is a panel's judgement, not an oracle.** Three agents, 84–94%
  agreement, under a stated assumption.
- **The 39 are the union of what these 48 replies found.** A defect none of them
  reported is invisible, so the percentages are coverage of the discovered set.
- **The coverage difference is significant and under-powered at once**: 2.3
  claims observed against an MDE of 3.23. Replicate before trusting the size.
- **One fixture, one clustering pass.** Cluster boundaries move the per-claim
  counts; they do not move finding-level precision, which does not depend on them.
- **Nothing here says whether a proposed fix works.** The fixtures are diffs.

## What follows

1. **Replicate on a second fixture** before acting on the N curve. The direction
   is the claim; the size is not yet.
2. **Measure N=4 and N=5.** The specialised arm's third reviewer was still adding
   +4.8 real defects. Nothing here shows where that flattens, and "three" was
   never chosen by measurement.
3. **Ask why specialisation costs precision.** The plausible mechanism — an
   expert pressed to find issues in their lane on a diff with few of them starts
   reaching — is a hypothesis, not a finding.
