# A second wave that is told what the first found — 2026-08-06

At equal token cost, three reviewers handed the first three's findings reach
**more genuine defects and file more non-defects** than three reviewers working
blind. The pre-registered decision rule anticipated exactly this case and says
to report both numbers and recommend nothing. That is the output.

Protocol, pre-registered including the rule:
`evals/rule-ablation/protocols/round-14.md`. Reproduce with
`evals/rule-precision/round-14/measure.py`.

## The question

Round 13 measured what an added reviewer buys **independently** — six draws that
do not know about each other. The skill does not work that way: phase 3 frames
its first round as incremental verification on the previous pass, and every later
round sees what came before.

The repository owner put it directly: three roles × two reviewers, versus running
the round twice — what is the difference? **At equal cost the difference is
exactly one thing**, whether the second three see the first three's output. This
isolates that one thing.

## Design

For each of eight reviews the **base** is fixed and shared: the union of that
review's first three replies from round 13, given to both arms as a stimulus.

- **Arm C** — three agents given the standard brief plus the base, asked for what
  the base missed and told not to restate it.
- **Arm I** — three agents given the standard brief alone.

n=8 reviews per arm, 48 agents, 451 findings. Arm I was **re-run rather than
reused** from round 13, because round 9 established that a stored cross-batch
number is context and never the control arm.

Findings assigned to the 95-claim inventory; 20 new claims adjudicated by the
same blind panel under the same standard (9 real, 9 not-a-defect, 2 wrong).
Inventory now 115 claims, 53 real.

## Result

| | C (told) | I (blind) | t | MDE@80% |
|---|---|---|---|---|
| **Primary — real defects the wave ADDS** | **6.62** | 4.62 | 2.17 | 2.78 |
| **Cost — Critical/Major non-defects** | 4.50 | **2.38** | 3.13 | 2.05 |
| six-reviewer total | 22.88 | 20.88 | 1.58 | 3.81 |
| findings written | 19.25 | 37.12 | −12.85 | 4.19 |
| **restating a base claim** | **1.12** | 28.88 | −19.64 | 4.26 |

Base (the shared first three reviewers): 16.25 real defects.
Per review, primary — C `4 5 6 6 6 8 8 10`, I `2 4 4 4 4 5 6 8`.

**The mechanism works, exactly and enormously.** Restatement falls from 28.88 to
1.12 — a 96% cut. Conditioning does what it is supposed to do: it converts the
effort three identical reviewers spend rediscovering each other's findings into
effort spent somewhere else.

**Where that effort goes is the finding.** It buys **+43% more real defects and
+89% more non-defects**:

| second wave | real / reviewer | non-defects / reviewer | signal:noise |
|---|---|---|---|
| C — told | 2.21 | 1.50 | 1.47 : 1 |
| I — blind | 1.54 | 0.79 | 1.94 : 1 |

A conditioned reviewer finds more and is less accurate. The blind reviewer is the
cleaner instrument per unit of attention; the conditioned one covers more ground.

## The decision rule, applied

> Adopt conditioning if arm C adds at least 1.0 more real defect than arm I, **with
> its Critical/Major non-defect count no worse.**

The first half is met — +2.00, and the primary is significant at p<.05 though the
observed difference sits under the MDE, so it is significant and under-powered at
once. **The second half fails**: the cost difference is 2.12 against an MDE of
2.05, so the worsening is real rather than noise.

The pre-registration said what to do here, before any of it was seen:

> If arm C wins on the primary but loses on cost, the honest output is the pair of
> numbers and no recommendation — the trade is a judgement the measurement does
> not make.

**So: no recommendation, and no change to the skill.** What the trade is worth
depends on the price of a missed defect against the price of a reviewer's
attention, and this measurement does not set either.

## What it does settle

The question was whether "three roles × two" and "run the round twice" differ.
They do, measurably, and neither dominates:

- The second wave, told what the first found, **reaches further** — 22.88 against
  20.88 in six-reviewer totals, and 6.62 against 4.62 in what it adds.
- It also **costs more to read** — 4.50 Critical/Major non-defects against 2.38.
- And it writes **half as much** (19.25 findings against 37.12), so the reading
  cost per review falls even as the non-defect count rises. Those are different
  quantities and the trade is not obviously bad.

## What this cannot settle

- **No fixes were applied between waves.** A real second round reviews *changed*
  code. Holding the artifact constant is the isolation the question needed and
  also the reason this does not say what a real second round is worth.
- **One fixture, identical generalists, one level of conditioning.** A shorter
  base, or one listing only Critical findings, is a different treatment.
- **The base came from an earlier batch.** Both arms got the same base, so it
  cannot bias the comparison, but it is not re-drawn per arm.
- **Anchoring was not observed but was not ruled out either.** Arm C added more,
  which is the opposite of the anchoring failure mode; whether it would anchor on
  a base that was wrong is untested.

## What follows

1. **Price the trade before adopting it.** The one thing that would settle this is
   what a missed defect costs relative to a reviewer's attention — which is a
   property of the project, not of the harness.
2. **Try a cheaper conditioning.** The whole effect runs through restatement
   suppression, and that may not need the full base: a list of the base's claim
   titles might buy the same 96% cut without the licence to reach.
3. **Replicate on a second fixture**, which every result here still needs.
