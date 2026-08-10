# Round 22 protocol — does round 20's confirmed effect replicate on F11?
(written before any run; no output read; no agent executed while writing it)

## The hypothesis

> **Clause 1 reduces high-severity non-defect findings on F11.**

That is round 20's confirmed claim with the fixture changed, and nothing else.
It is stated in exactly the terms the primary measures — Critical/Major findings
whose claim is adjudicated `not-a-defect`, all reasons, per review — because that
is the metric round 20 pre-registered and fired on.

## Why this, and why not the questions it looks like

Round 21 asked whether clause 1's effect lands on the `outside-diff` subtype and
whether it appears on F11. Its confirmatory interval crossed zero, and its
SECONDARY — **the same quantity round 20 made its confirmatory claim on** — came
back at −0.11 with a 95% CI of [−1.53, +1.31].

**That interval contains round 20's −1.33.** Round 21 was informative but
imprecise on this metric: it was sized for the subtype (MDE 1.31) while the total
non-defect metric ran at MDE 1.99 as an exploratory extra, and its estimate is
compatible with a range of effects. What it **did not resolve is whether the two
fixtures' effects differ.** The temptation after round 21 is to conclude that the
effect may be F10-specific; that question has not been tested, and two things
must be said about why:

- A non-significant result on F11 beside a significant one on F10 is a
  **difference in significance, which is not a significant difference.** Nothing
  in either round tested whether the two effects differ.
- Round 21's interval is wide enough to be compatible with round 20's estimate,
  with zero, and with an effect in the other direction.

So the replication has not been attempted at a sensitivity that could see it, and
this round is that attempt. It does **not** ask whether the effect is *selective*
to the `outside-diff` subtype, whether it is *fixture-independent* (two fixtures
is two), or *why* clause 1 works — the reviewer-side mechanism is unobserved here
and the write-up must not narrate it.

## Arms

- **W** — the catalogue at `bc0f966`: Finding Floor clauses 1, 2, 3.
- **W₂₃** — clauses 2 and 3; clause 1 removed, remaining clauses renumbered.

Byte-reproducible from `bc0f966` and `../../rule-precision/round-21/arms.diff`.
Identical to round 21's arms; the catalogue is not touched between rounds.

## The fixture, and the inventory that is fixed before this round runs

**F11 is reused unchanged**: `../fixtures/F11-exports.diff`, the frozen 684-line
diff whose size deviation is declared in `round-21.md`. Reusing it is the point —
this is a replication on the same fixture at a sensitivity that can see the
effect, not a third fixture.

### What is pinned, and by what

F11's claim inventory and its verdicts are fixed **before** any review here runs,
pinned by blob hash rather than commit id because a squash merge rewrites ids:

```
6166c25dbcc1a21bd4ab5248c24533e54fef691b  round-21/clusters.tsv
78dd1877c07286f0c1f569cac6c067efbd986513  round-21/adjudications/panel-1.tsv
6e276875bc66d61971e25c95d9645cf64f33f83e  round-21/adjudications/panel-2.tsv
0d62f2ef089429fe57019cd9cf33124a3f7bcff4  round-21/adjudications/panel-3.tsv
40fcc5b070e7f6eac6948b095acc55468726787e  round-21/measure.py
```

`clusters.tsv` supplies the 79 cluster ids and their canonical claim text; the
three sheets supply the verdicts; `measure.py` is pinned because it encodes how
they combine — majority verdict across the three, and the 2-of-3 joint rule for
the `outside-diff` label. Verified with `git hash-object <path>` before the first
batch.

### How this round's findings meet that inventory

- A finding is assigned to an existing cluster on **semantic match** — it asserts
  the same thing about the same code, and one change resolves both. Wording need
  not match.
- When a finding is assigned to an existing cluster, that cluster's **id and
  canonical claim text are copied verbatim, byte for byte.** A reworded claim is a
  different claim and the verdict recorded against the original stops applying to
  it. Checked mechanically at merge.
- Only a finding matching no existing claim opens a new cluster, adjudicated
  after the fact by the standing brief.

### The honest limit of this improvement

Round 21 had to build its claim space from the arms themselves. Here the standard
for every claim round 21 already saw is fixed in advance — a real improvement, and
**not the same thing as F10's seed inventory**. F10's was generated independently
before any arm ran; F11's 79 claims are a claim space that W and W₂₃ themselves
produced in round 21. What is fixed in advance for this round is the *labelling*,
not the *origin*.

**Reported, not assumed:** the number of new claims this round adds, and their
share of the primary — defined **per arm** as

> C+M findings assigned to a claim new in this round, adjudicated `not-a-defect`
> ÷ that arm's total primary findings.

A prediction, and not a premise, is that new claims will be few: F11 has been
through exactly one round, so its claim space has one round of convergence behind
it and no more.

## The reviews are fresh, and round 21's nine are not reused

**n = 25 per arm, all newly run. 2 × 25 × 3 = 150 review agents.**

Round 21's nine reviews per arm are **excluded from the confirmatory set.** Their
value on this metric has already been computed and read, and that reading is what
motivated running this round at all. Adding reviews to a series whose first nine
were seen, and then testing the whole at α = .05, is a sequential design without
an alpha-spending rule — the peek is free only if it never influenced whether the
extension happened, and here it plainly did.

- **Confirmatory: the 25 fresh reviews per arm, and only those.**
- **Exploratory:** round 21's estimate and this round's estimate reported
  **separately**, then combined by **fixed-effect inverse-variance weighting**:
  with `d_i` and `SE_i` the Welch difference and standard error of round *i*,
  `w_i = 1/SE_i²`, `d̄ = Σw_i d_i / Σw_i`, `SE(d̄) = 1/√(Σw_i)`, and a normal
  interval `d̄ ± 1.96·SE(d̄)`. Round is the blocking factor; no random-effects
  variance is estimated, because two rounds cannot support one.
  A naive 34-per-arm pool is **not** reported: it would merge two samples drawn
  under different designs and hide which round carries the result.

Round 21's protocol forbade extending n after its gate. This round does not extend
that round; it runs a new one at a size chosen before any of its own data exists.

## Power — n comes from round 21's own measurement of this metric on this fixture

Round 21 measured it: se 0.671 at n = 9 per arm, Welch df 16.0, observed MDE 1.99.
Since se scales as 1/√n, and the gate below is 1.33:

| n/arm | Welch se | df | MDE | P(gate exceeded)¹ |
|---|---|---|---|---|
| 9 (round 21) | 0.671 | 16 | 1.99 | 97% |
| 16 | 0.503 | 30 | 1.451 | 72% |
| 19 | 0.462 | 36 | 1.325 | 46% |
| 20 | 0.450 | 38 | 1.290 | 37% |
| 23 | 0.420 | 44 | 1.199 | 14% |
| 24 | 0.411 | 46 | 1.173 | 9% |
| **25** | **0.403** | **48** | **1.149** | **6%** |

¹ the chance the *observed* MDE lands above 1.33 and the gate fires, **assuming
round 21's variance is exactly right**. Computed from
se&#770;/se ~ √(χ²_{2(n−1)}/2(n−1)) with a Wilson–Hilferty tail. This is an
**assurance calculation, not a test**: it approximates equal variances across arms
and holds each row's expected df fixed rather than propagating its randomness, so
the percentages are design margins to compare against each other, not exact risks.

n = 19 is the smallest n whose *predicted* MDE falls under the gate, and it is not
chosen. A design whose predicted MDE sits 3% under its own gate fires that gate on
ordinary sampling variation alone — at n = 20, 37% of the time. Spending this
round's budget for a better-than-one-in-three chance of ending in "underpowered,
no claim made" is the bad trade this table exists to prevent.

**n = 25 is chosen for the margin the last column shows**, not for its MDE. The 6%
and 9% figures are approximations under the footnote's assumptions, so the choice
between n = 25 and n = 24 is buying design headroom rather than an exact three-point
reduction in risk. n = 24 is the fallback if cost forces it.

> **GATE.** After all 50 reviews and before any arm mean is computed, the observed
> Welch MDE on the PRIMARY is calculated. If it exceeds **1.33** — the effect round
> 20 observed on F10 — the round reports the primary as underpowered and makes no
> confirmatory claim. It does **not** extend n.

## Metrics

1. **PRIMARY (confirmatory)** — Critical/Major findings whose claim is
   `not-a-defect`, all reasons, per review. Identical to round 20's confirmatory
   metric, deliberately, so that "replicates" means something exact.
2. **SECONDARY (exploratory)** — the `outside-diff` subtype under round 21's joint
   2-of-3 label rule. Round 21 measured it at −0.67, CI [−1.60, +0.27]; this round
   is not sized for it and it fires no rule.
3. **RECORDED** — non-defects by each other reason; distinct real claims reached;
   `wrong`; findings written; new claims and their per-arm share of the primary;
   tokens; and **`D = Δ_F11 − Δ_F10`** below, the only quantity that speaks to
   whether the two fixtures' effects differ. It is exploratory, it is not in the
   confirmatory rule, and no wording may treat the F10/F11 comparison as tested
   without it.

### `D = Δ_F11 − Δ_F10` — computation fixed here, before either side is combined

- `Δ_F11` — this round's fresh 25/arm Welch difference for W − W₂₃.
- `Δ_F10` — round 20's **same two arms**, re-estimated unpaired by Welch for
  comparability. Round 20's own paired interval is also reported, as a sensitivity
  analysis, since that is the form its README states.
- `D = Δ_F11 − Δ_F10`, `SE(D) = √(SE_F11² + SE_F10²)`, treating the rounds as
  independent; degrees of freedom by Satterthwaite from each side's Welch SE and df.

> This is a **descriptive cross-study heterogeneity contrast.** Fixture is
> confounded with round, inventory history, and review batch, so the interval
> cannot attribute any difference to the fixture alone.

The control fires no rule. A flat real-claim count is **not** non-inferiority.

## Inference

**Welch's two-sample t interval, independent groups.** The arms share review
indices and nothing else — there are no per-review preambles. Round 19 measured
that directly (sd of paired differences 1.323 where independence predicts 1.344).
The nominal index-paired analysis is computed and reported as a **sensitivity
analysis**, never as the primary.

> **CONFIRMATORY RULE. Clause 1's effect replicates on F11 if the Welch 95% CI for
> W − W₂₃ on the PRIMARY lies entirely below zero.**

The observed difference is **not** required to exceed the MDE. That was round 19's
error and `../../rule-precision/methods.md` records the separation: the MDE gates
the spend before the run and is not a bar the difference must clear.

## How the result will be read — fixed in advance

| PRIMARY (fresh 25/arm) | reading |
|---|---|
| CI below zero | **the effect replicates on F11.** Round 20's result is not a property of F10 alone |
| CI crosses zero, gate held | **no directional replication was detected in the fresh sample.** Under the observed-variance gate the design met its pre-registered power target for a true effect of −1.33. **The confidence interval, not the MDE, states which effect sizes remain compatible with the data.** This does not show that the effect is absent, and it does not show that it is smaller than 1.33 |
| CI crosses zero, gate exceeded | underpowered; the round says nothing about replication |
| CI above zero | recorded as observed, with no story attached |

The MDE is a design quantity: an effect of exactly −1.33 would be detected about
80% of the time, so a null misses such an effect roughly one time in five, and the
observed interval may well still contain effects larger than 1.33. **No row licenses
an upper bound on the effect from the MDE**, none licenses an equivalence claim,
and none licenses deleting clause 1 — that would need a non-inferiority design with
a declared margin, which this is not.

## Pre-registered predictions

- **Most likely.** The CI lands below zero with a point estimate between round 20's
  −1.33 and round 21's −0.11, because round 21's nine reviews are a noisy sample of
  the same quantity rather than a contradiction of it.
- **The failure that matters**: the primary fires and real claims reached drop in W.
  That is a **possible coverage cost — recorded, not confirmed**: the real-claim
  count is a control that fires no rule and no test here licenses calling the drop
  an effect of clause 1.
- **The null worth taking seriously**: the gate holds and the CI still crosses zero.
  The write-up then reports the interval and stops. Whether that means the effect is
  smaller on F11 than on F10 is a question `Δ_F11 − Δ_F10` addresses exploratorily
  and this round does not settle.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 25 × 2 arms × 3 | 150 | 12.6M |
| clustering, one per changed file — F11 has 8 | 8 | 0.8M |
| merge and verbatim-claim check | ~2 | 0.2M |
| adjudication, new claims only | 3 | 0.2M |
| **total** | **~163** | **≈13.8M** |

The most expensive round in the series, and it buys one thing: whether the only
confirmed result about the Finding Floor holds on a second fixture. Cheaper designs
are rejected in the record above — a third fixture at n = 9 buys another
inconclusive interval, a mechanism round presumes the effect it has not
established, and n = 20 buys a 37% chance of paying in full for "underpowered".

Reviews are batched **one review index at a time** (2 arms × 3 parts = 6), confirmed
landed before the next, across twenty-five batches. That spans several five-hour
windows; `../../rule-precision/preflight.py` runs before every batch and the round
pauses rather than losing agents to a full window.

## Working rules carried in

- `../../rule-precision/preflight.py` before every batch. Round 20 lost fourteen
  agents to the five-hour window by not asking.
- `../../rule-precision/await_outputs.py` for every wait. A `DONE` is not evidence,
  and one `ls` cannot tell "not yet" from "never".
- Extraction by `../../rule-precision/extract.py`; heading count reconciled against
  parsed count per file. Clustering split by
  `../../rule-precision/split_clusters.py`, which reads the changed-file set from
  the fixture rather than from an extension list.
- Existing claims are reused verbatim, as specified above, and checked mechanically.
- Sub-agent models are not changed.

## What this cannot settle

- **Fixture-independence.** Two fixtures is two, whichever way this comes out.
- **Whether the effect differs between F10 and F11.** Only `Δ_F11 − Δ_F10` speaks to
  that, it is exploratory, and this round is not sized for it.
- **Whether clause 3 contributes.** Not in this design.
- **The reviewer-side mechanism.** Not observed here.
- **Whether a null licenses removing clause 1.** It does not.
- **No fixes are applied.** The fixtures are diffs.
