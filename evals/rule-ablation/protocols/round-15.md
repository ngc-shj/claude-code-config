# Round 15 protocol — can the cheap half of conditioning be had without the expensive half?
(written before any run; no output read)

## What round 14 left

Handing a second wave the first wave's findings cut restatement by 96% (28.88 →
1.12) and spent the freed attention on **more ground, less accurately**: +43%
real defects, +89% Critical/Major non-defects. The pre-registered rule cleared on
coverage, failed on cost, and returned no recommendation.

Every part of that effect runs through one mechanism — the reviewer knows what is
already covered and stops writing it. **That mechanism may not need the full
base.** Round 14's arm C was handed each finding's severity, title, file and a
sentence of explanation: enough to suppress restatement, and also enough to read
as "here is the shape of this change's problems, now go past it".

This round separates the two. If a bare list of titles buys the same restatement
cut without the licence to reach, it dominates both of round 14's arms and is
the configuration to ship.

## Arms — three, in one batch

The base is the same fixed stimulus round 14 used: the union of that review's
first three replies from round 13.

- **T (titles)** — three agents given only the base's finding **titles**, one line
  each, with no file, no severity, no explanation.
- **C (full base)** — three agents given the base as round 14 gave it. Re-run,
  not reused, because a stored cross-batch number is context and never a control.
- **I (blind)** — three agents given the standard brief alone. Also re-run.

n = 8 reviews × 3 arms × 3 agents = **72 agents**, the largest single batch this
eval has run. It is three arms rather than two because the question is whether T
lands at C's coverage and I's cost, and neither pairwise comparison alone can say
that.

## Pre-registered metrics

Against the 115-claim inventory (53 real), only genuinely new claims adjudicated,
same brief, blind, counts withheld.

1. **Primary — real defects the wave ADDS**, beyond the base.
2. **Cost — Critical/Major non-defects the wave files.**
3. **Mechanism — findings restating a base claim.** This is what the treatment
   acts on; if T does not cut it, T is not a weaker conditioning but a different
   one, and the rest of the comparison means nothing.
4. **Recorded — findings written**, and the six-reviewer total.

## Pre-registered decision rule

> **Ship T if it is not worse than C on the primary and not worse than I on the
> cost**, both judged against the difference this design can catch. That is the
> hypothesis stated as a test: the cheap half without the expensive half.
>
> If T lands between C and I on both, there is no dominant arm and the output is
> the three-way table with no recommendation — the same outcome round 14 reached,
> for the same reason.

Stated now because "T is closer to C than to I, so ship T" is an argument that
can be made after the fact about almost any middle result.

## Pre-registered predictions

- **The hypothesis**: T cuts restatement about as far as C does, because knowing
  a title is enough to recognise your own finding — while the noise stays near I,
  because a title gives nothing to build a new theory on.
- **The plausible failure**: titles are too thin to recognise a finding by, so T
  restates nearly as much as I and buys nothing.
- **The other failure**: the noise was never about the detail. If T's non-defect
  count matches C's, then what raises it is being asked to find something the
  others missed, not the material supplied — and no cheaper conditioning helps.
- Compare within the batch. Round 14's numbers are context, never a control.

## Manipulation check, run after batch 1 and recorded before batches 2–4

Standard since round 12: verify the treatment arrived before paying for the rest,
and write down what was looked at.

| | replies | findings | per reply | Critical |
|---|---|---|---|---|
| T (titles) | 6 | 30 | 5.0 | 1 |
| C (full base) | 6 | 40 | 6.7 | 3 |
| I (blind) | 6 | 76 | 12.7 | 17 |

T sits with C, not with I, so **titles alone do suppress restatement** — the
first prediction's direction, on two reviews. Whether the freed attention lands
where C's did is the primary metric and is not answered here. **No metric,
threshold or prediction above was changed after seeing this.**

## Where this round stopped

**Six of the eight pre-registered reviews ran, and the analysis has not.** The
batch was halted against a budget ceiling. The raw findings are checked in
(`evals/rule-precision/round-15/`) so the 54 agents already spent are not lost
with the scratchpad, and a later session can finish from them without re-running
a single review.

n=6 raises the minimum detectable difference by about 19% against the
pre-registered n=8 (df 10 rather than 14, and √(2/6) rather than √(2/8)). The two
missing reviews can be run later, but not in the same batch as the six, so
completing to n=8 afterwards would mix batches — which this eval treats as
context rather than control. **The defensible completion is to analyse the six.**

Substituting a different model for the clustering was considered as a way to
finish inside the ceiling and **rejected**. It was not rejected for adjudication's
reason — moving the judge would count the primary metric against a mixed
standard — but for one specific to this round: a clusterer's recognition of a
restatement **interacts with the arms**, since I restates the base about 29 times
per review where T and C restate about once. Whatever its recognition rate, it
lands almost entirely on one arm.

## What this cannot settle

Everything round 14 could not: no fixes between waves, one fixture, identical
generalists, and a base drawn from an earlier batch (shared by all three arms, so
it cannot bias the comparison). Additionally, **"titles only" is one point in a
space of possible summaries** — severity-filtered, file-grouped, or count-only
bases are all untested, and a null for T is not a null for cheap conditioning in
general.
