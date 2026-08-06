# Round 13 protocol — how many reviewers, now that the Finding Floor is in?
(written before any run; no output read)

## Why this round

Coverage is now the binding constraint. One review reaches about **16.5 of the
43 genuine defects** the adjudicated inventory holds — under half — and round 11
found the third reviewer still adding 2.5 to 4.8 real defects, with no sign of a
plateau. Nothing ever chose three; the number is inherited.

Adding reviewers also added noise, which is what made the trade-off unattractive.
Round 12 changed that: the Finding Floor cut the Critical/Major findings that are
not defects from 4.12 per review to 1.62, and the residual is almost entirely one
category (`outside-diff`, 12 of 13). **The cost side of "add a reviewer" is now
about a third of what it was**, so the curve has to be redrawn before anyone
picks an N.

This is the question the repository owner posed at the outset — the most effect
for the fewest tokens — asked directly for the first time.

## Design: one batch, six points

Eight reviews of **six identical general reviewers** each, on F9, HEAD materials
(Finding Floor included). 48 agents. For each review and each k in 1…6, the
metric is averaged over all C(6,k) subsets of its replies, so one batch yields the
whole curve.

**Sub-sampling is only valid for identical reviewers, and that decides the arm.**
Any k of six generalists is an unbiased sample of "k generalists". With the
specialised split it is not: a 2-subset can be {functionality, security} or
{security, testing}, which are different configurations, and six agents would
mean two of each role rather than six roles. The specialist curve needs its own
run and does not get one here.

So this measures the **cheap default**, which is also the configuration whose
marginal value is least known.

## Pre-registered metrics

1. **Primary — distinct real defects reached, as a function of N**, against the
   89-claim adjudicated inventory (83 from round 11, 6 added by round 12), with
   the marginal gain of each added reviewer.
2. **Cost — Critical/Major findings that are not defects, as a function of N.**
   These accumulate with N as surely as the real ones do, and an N chosen on
   coverage alone is chosen on half the evidence.
3. **Recorded — total findings per N**, and real defects per 1000 tokens.

## Pre-registered decision rule

Written now so the number is not chosen to fit the curve:

> **Adopt the smallest N at which the next reviewer's marginal gain falls below
> 1.0 real defect.** A reviewer costs about 71k tokens (round 11–12 measured
> average). One that does not reliably surface even one further genuine defect
> does not earn that, whatever the total looks like.

If the marginal gain has not fallen below 1.0 by N=6, **the honest output is "the
curve has not turned yet", not a recommendation** — and the next run extends it
rather than this one rounding it off.

## Pre-registered predictions

- Diminishing returns, with the marginal gain falling monotonically. Round 11's
  generalist arm went 10.5 → 14.2 (+3.7) → 16.8 (+2.5); the extrapolation would
  put the crossing somewhere around N=5.
- The cost curve rises roughly linearly in N — non-defects are less redundant
  between reviewers than real defects, since each reviewer invents its own.
  **If it rises faster than the coverage curve, the answer is a smaller N than
  coverage alone would suggest.**
- Compare within the batch. Round 11 and 12 figures are context, never a control.

## Adjudication

The standard stays fixed, third round running: findings are assigned to the 89
existing claims, and only genuinely new claims are adjudicated — same brief,
blind, shuffled, counts withheld, three agents, majority vote. Round 12 produced
only 6 new claims from 599 findings, so this is expected to be a small job; if it
is not, that is itself worth reporting.

## What this cannot settle

- **One fixture**, and the inventory is the union of what previous runs found, so
  "of 43" is coverage of the discovered set rather than of the fixture.
- **Identical reviewers only.** The specialised split reached more real defects
  at N=3 in round 11, and this run says nothing about where its curve turns.
- **One round of review.** Whether a missed defect is caught by the next round of
  the fix loop is untested, and it is the thing that would most change how much a
  missed defect costs.
- **Sub-sampling shares reviewers between points**, so adjacent points on the
  curve are correlated. The marginal gains are estimates from one batch of eight,
  not eight independent experiments per N.
