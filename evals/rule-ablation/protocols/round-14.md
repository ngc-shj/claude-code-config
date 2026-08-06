# Round 14 protocol — is a second wave worth more when it is TOLD what the first found?
(written before any run; no output read)

## The question, and why it is the right one now

Round 13 measured what an added reviewer buys when it works **independently**:
the sixth adds 0.9 real defects against a constant cost of 0.7 non-defects. That
is the shape of parallel sampling — six draws that do not know about each other.

But the skill does not work that way. Phase 3 frames its first review round as
*incremental verification on top of Phase 2's self-check*, and every later round
sees the previous round's findings and the fixes made for them. **Sequential
rounds are conditioned draws, and nothing here has ever measured conditioning.**

The repository owner put the question directly: three roles × two reviewers,
versus running the round twice — what is the difference? At equal token cost the
difference is exactly one thing, whether the second three see the first three's
output. This round measures that one thing.

## Design

For each of eight reviews, the **base** is fixed and shared: the union of that
review's first three replies from round 13 (`R<k>-a`, `R<k>-b`, `R<k>-c`). The
base is the stimulus, not the measurement.

- **Arm C (conditioned)** — three agents given the standard brief *plus* the base
  findings, and asked for what the base missed.
- **Arm I (independent)** — three agents given the standard brief alone. This is
  round 13's 4th–6th reviewer, re-run.

n = 8 reviews per arm, 3 agents each, **48 agents**.

**Why arm I is re-run rather than reused from round 13.** Round 9 established
that a blind-scored baseline moved four points across batches on byte-identical
materials, and the standing rule since is that a stored cross-batch number is
context, never the control arm. Reusing round 13's `d`,`e`,`f` would cost 24
agents less and buy an uncontrolled comparison.

## Pre-registered metrics

All computed against the 95-claim adjudicated inventory (44 real), with only
genuinely new claims adjudicated, same brief, blind, counts withheld.

1. **Primary — real defects the second wave ADDS**, i.e. distinct real claims in
   the arm's three replies that are not in the base.
2. **Secondary — the six-reviewer total**: real defects in base ∪ arm.
3. **Cost — Critical/Major non-defects in the arm's own three replies.**
   Conditioning could cut these (the base already covers the obvious ground) or
   inflate them (a reviewer told "find what they missed" reaches for something).
4. **Recorded — findings per reply**, and how many of the arm's findings restate
   a base claim. The restatement rate is the mechanism: conditioning is supposed
   to work by suppressing it.

## Pre-registered decision rule

> **Adopt conditioning if arm C adds at least 1.0 more real defect than arm I**,
> with its Critical/Major non-defect count no worse. One real defect is the same
> bar round 13 set for a reviewer, and a change to how the loop is framed should
> clear at least what an added reviewer must.

If arm C wins on the primary but loses on cost, the honest output is the pair of
numbers and no recommendation — the trade is a judgement the measurement does not
make.

## Pre-registered predictions

- **If conditioning works**: arm C adds more real defects and restates far less.
  Round 13 showed identical reviewers overlap heavily; being told what is already
  found should convert that wasted overlap into coverage.
- **The failure mode to watch**: anchoring. A reviewer handed thirty findings may
  read them as the shape of the problem and search only around them, in which
  case arm C adds *fewer* novel defects than arm I and the restatement rate falls
  for the wrong reason.
- **The null**: no difference, because a reviewer re-derives its findings from the
  diff either way and the base only changes what it bothers to write down.
- Compare within the batch. Round 13's numbers are context, never a control.

## Manipulation check, run after batch 1 and recorded before batches 2–4

Round 12 recovered this step mid-run and it is now standard: verify the
manipulation arrived before paying for the rest, and write down what was looked
at, because looking at any output creates that obligation.

| | replies | findings | per reply | Critical | base-aware phrases |
|---|---|---|---|---|---|
| C | 6 | 34 | 5.7 | 3 | 5 |
| I | 6 | 73 | 12.2 | 17 | 1 |

The conditioned arm writes less than half as much and almost no Criticals — the
headline defects are in the base, so it is not restating them. That is the
mechanism the design predicts; whether the freed effort becomes coverage is the
primary metric and is not answered by this check. **No metric, subset, threshold
or prediction above was changed after seeing it.**

## What this cannot settle

- **The base is a fixed stimulus from an earlier batch.** Both arms get the same
  base, so it cannot bias the comparison, but the base is not re-drawn per arm.
- **No fixes were applied between waves.** A real second round reviews *changed*
  code; this one reviews the same diff. So this measures conditioning alone, with
  the artifact held constant — which is the isolation the question needs and also
  the reason it does not settle what a real second round is worth.
- **One fixture**, one round of conditioning, identical generalists only.
