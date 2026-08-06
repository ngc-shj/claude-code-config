# How many reviewers — 2026-08-06

The three-expert split was never chosen by measurement. This round measures the
curve, and the answer is that **the shipped configuration is already where the
pre-registered decision rule lands — at 60% of what an equivalent generalist team
would cost.** Nothing changes in the skill. That is the result.

Protocol, pre-registered including the decision rule:
`evals/rule-ablation/protocols/round-13.md`. Reproduce with
`evals/rule-precision/round-13/measure.py`.

## Design

Eight reviews of **six identical general reviewers**, F9, HEAD materials
(Finding Floor in place), 48 agents, 591 findings. For each review and each N in
1…6, the metric is averaged over all C(6,N) subsets, so one batch yields six
points.

**Why generalists:** sub-sampling is only unbiased for identical reviewers. Any N
of six generalists is a sample of "N generalists"; a 2-subset of the specialised
split could be {functionality, security} or {security, testing}, which are
different configurations. The specialist curve needs its own run.

Findings were assigned to the 89-claim inventory rounds 11–12 built, and only the
6 genuinely new claims were adjudicated — same brief, blind, counts withheld.
Inventory now 95 claims, 44 real.

## The curve

| N | real defects | marginal | Critical/Major non-defects | marginal | tokens | per defect |
|---|---|---|---|---|---|---|
| 1 | 10.8 | — | 0.7 | — | 71k | 6.6k |
| 2 | 14.3 | **+3.5** | 1.5 | +0.7 | 142k | 10.0k |
| 3 | 16.4 | +2.2 | 2.2 | +0.7 | 213k | 13.0k |
| 4 | 17.9 | +1.5 | 2.9 | +0.7 | 284k | 15.8k |
| 5 | 19.1 | +1.1 | 3.6 | +0.7 | 355k | 18.6k |
| 6 | 20.0 | **+0.9** | 4.4 | +0.7 | 426k | 21.3k |

**The pre-registered rule fires at N=5** for generalists: the sixth reviewer adds
0.9 real defects, under the 1.0 bar. It fires by a tenth of a defect, on one
batch, so read it as "the curve flattens around five", not as a threshold with a
sharp edge.

**The cost side is linear, exactly as predicted.** Every added reviewer brings
0.7 more Critical/Major findings that are not defects, whatever N already is,
while the coverage gain decays. Signal-to-noise per added reviewer runs 5:1 at
the second and 1.3:1 at the sixth. **An N chosen on coverage alone is chosen on
half the evidence.**

## What the shipped configuration costs, placed on that curve

| configuration | N | real defects | tokens | per defect |
|---|---|---|---|---|
| **three specialised experts** (round 11) | 3 | **19.1** | 213k | **11.2k** |
| three identical generalists | 3 | 16.4 | 213k | 13.0k |
| five identical generalists | 5 | 19.1 | 355k | 18.6k |
| six identical generalists | 6 | 20.0 | 426k | 21.3k |

**Three specialists reach what five generalists reach, for 60% of the tokens.**
The role split is worth about two extra reviewers.

That comparison crosses batches and inventories, so by this eval's own rule it is
context and not a control — the within-batch fact is the generalist curve itself.
It is stated because the direction is large and consistent with round 11's
within-batch finding that specialised replies overlap half as much as identical
ones (Jaccard 0.116 vs 0.246).

## What this licenses

**No change.** The decision rule was written to pick an N, and applied to the
generalist curve it picks 5 — which the shipped three-role configuration already
matches on coverage while costing less. Adding identical generalists to the
current three is the one move this round rules out.

It also answers a question asked directly: should the three agents be increased?
Not with more of the same. The remaining candidates are two, and neither is
measured:

1. **Three roles × two reviewers each.** The natural next point, because the
   mechanism that makes reviewers pay is non-overlap, and roles are what produce
   it. Round 11's per-role analysis supports it: **75% of the union is found by
   exactly one role**, only 1% by all three, and each role uniquely contributes
   4–6 real defects — four to six times the bar a reviewer must clear.
2. **A conditioned second wave** — three reviewers given the first three's union
   and asked for what it missed. At equal cost to six parallel, and testable
   within one batch against the independent 4th–6th reviewers this round already
   holds.

## What this does not settle

- **One fixture**, and the inventory is the union of what previous runs found, so
  "of 44" is coverage of the discovered set rather than of the fixture. Some
  claims are near-duplicates split across file groups by per-file clustering, so
  44 is somewhat inflated and the coverage percentages are a lower bound.
- **Sub-sampling shares reviewers between points**, so adjacent points are
  correlated. The marginal gains are estimates from one batch of eight, not eight
  independent experiments per N.
- **Identical reviewers only.** Where the specialist curve turns is unmeasured.
- **One round of review.** Whether a missed defect is caught by the next round of
  the fix loop is untested, and it is the thing that would most change what a
  miss costs.
