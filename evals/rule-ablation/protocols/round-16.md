# Round 16 protocol — can an explicit stopping rule cut the cost of conditioning?
(written before any run; no output read; no agent executed while writing it)

## What this round is for

Rounds 14 and 15 established, over fourteen matched pairs, that conditioning a
second wave on what the first found does two things at once: it adds real defects
(+2.57, 95% CI +1.16 to +3.98) **and** it adds Critical/Major findings that are
not defects (+1.57, CI +0.67 to +2.47). Applying round 14's own rule — adopt only
if the non-defect count is no worse — the cost condition fails, so conditioning is
not adopted despite a coverage benefit that replicated twice.

The mechanism the two rounds suggest is not the material supplied: round 15 showed
titles alone buy exactly what the full findings buy, on every measured dimension.
What is left is **the pressure to be novel**. A reviewer told to find what the
others missed has been given a reason to report, and the marginal thing it reaches
for is by construction the thing three reviewers already declined to report.

This round tests one sentence aimed at exactly that.

## Arms — two, differing in one sentence

Both arms are round 15's **T**: three agents given the base's finding titles only,
no file, no severity, no explanation. Finding Floor identical. Everything in the
brief identical.

- **T** — round 15's conditioned brief, unchanged.
- **TS** — T plus this sentence and nothing else:

  > If there is no defect worth reporting that the list does not already cover,
  > end with `No findings`. That a finding is not on the list is not by itself a
  > reason to report it.

One variable. The arms are rendered from one template and differ by that
paragraph, verifiable by `diff`.

## Pre-registered metrics

1. **Primary — Critical/Major findings that are not defects**, per review.
   Lower is better.
2. **Control — real defects added beyond the base**, per review. Tested for
   **non-inferiority**, not for difference: the stopping rule must not buy its
   precision by silencing reviewers.
3. **Mechanism — findings written**, and **the number of replies ending in
   `No findings`**. If the second is zero the sentence did not arrive, and the
   round says nothing about stopping rules — only about that wording.
4. **Recorded, not claimed — restatements of the base, and tokens per arm.**

## Sample size, computed rather than assumed

`n=8` is the habit of this eval and it is **wrong for this question**. The paired
standard deviations come from round 15's T-vs-C differences — two conditioned
arms on the same reviews, which is the closest available analogue to T vs TS:

| | paired sd (round 15, T−C) |
|---|---|
| Critical/Major non-defects | **2.32** |
| real defects added | **2.53** |

**These are borrowed surrogates and should be read as such.** They come from
**six** paired reviews of a *different* contrast (T against C, two conditioning
variants) on a *different* fixture (F9). An sd estimated from n=6 is itself
imprecise — its own 95% interval spans roughly ±40% — and the new fixture may be
noisier or quieter than F9. Every n below inherits that.

Reviews required per arm, paired one-sided test at α=.05 and 80% power:

| primary effect to detect | n | | non-inferiority margin | n |
|---|---|---|---|---|
| −0.75 | 61 | | 1.00 | 41 |
| −1.00 | 35 | | 1.50 | 19 |
| −1.25 | 23 | | 2.00 | 12 |
| −1.57 (the estimated penalty, below) | 15 | | 2.50 | 8 |

**1.57 is not a ceiling.** It is the conditioning-attributable penalty *estimated*
from two batches (95% CI +0.67 to +2.47), not a theoretical maximum a stopping
rule could remove. TS could in principle undercut it — a stopping rule may
suppress non-defects the base wave's own pressure never caused — or remove only
part of it. The row is a landmark on the scale, not a bound.

**The design point is n=20 per arm**, which detects a reduction of about **1.35**
against a non-inferiority margin of **1.5 real defects**. Both are pre-registered
here.

A rate-based primary was considered and rejected as the headline. Pooled over
round 15, T's Critical/Major findings are 26.3% non-defects against I's 9.0%, and
a rate moves further than a count because T writes a third as many findings. But
detecting 26.3% → 18% needs about 25 reviews, no cheaper than the count, and a
rate can fall while the absolute burden on the fixer does not. **The rate is
recorded as a secondary; the count is the primary.**

### Sensitivity to the borrowed sd

Pre-registered because a design point that only survives at its point estimate is
not a design point. n per arm at the chosen effects, as both sds move together:

| sd multiplier | primary sd | control sd | n needed |
|---|---|---|---|
| ×0.70 | 1.62 | 1.77 | **11** |
| ×0.85 | 1.97 | 2.15 | **15** |
| **×1.00 (point estimate)** | 2.32 | 2.53 | **20** |
| ×1.15 | 2.67 | 2.91 | **26** |
| ×1.30 | 3.02 | 3.29 | **33** |

**n=20 is adequate only if the new fixture is no noisier than F9.** The first
window of a split run therefore doubles as a variance check: with 10 paired
differences in hand, recompute both sds and, if either exceeds ×1.15 of the
borrowed value, **the second window is re-sized before it is run** rather than
the result being reported underpowered. That re-sizing is declared here so it is
not a reaction to the first window's effect estimate — it is keyed to the
variance only, and the effect estimate is not to be looked at until both windows
are complete.

**If the budget cannot reach the n the variance demands, the round is not run at
a smaller n.** The alternative is the split below, not a weaker version.

## Running it across two budget windows

Round 15's own correction licenses this. Arms T and TS share a review id, a base
and a preamble, so **each review is a matched pair**, and pooling paired
differences from two batches is legitimate — what round 9 forbids is measuring an
arm against a *stored number* from another batch, which this is not.

So n=20 may be run as **10 + 10 in separate windows**. Both halves must carry
both arms; a half with only one arm is worthless. The split is declared here so
it cannot be chosen after seeing the first half.

**The analysis is stratified by window, not a flat pool of 20.** Each window's
paired differences are kept as a block and its own mean and variance retained;
the combined estimate is the **inverse-variance weighted mean of the two window
means**, and the reported interval uses the within-window variance. Collapsing
the twenty differences into one undifferentiated sample would hide exactly the
thing round 9 warned about — that a batch can move on identical materials — by
averaging it away.

**Between-window heterogeneity is pre-registered as a reported quantity, not a
gate**: the difference between the two window means, its interval, and Cochran's
Q with I² on the two blocks. Two windows cannot estimate a between-batch variance
component with any precision, so **no adoption decision is conditioned on the
heterogeneity statistic** — it is reported so a reader can see whether the two
windows agreed, and a visible disagreement is grounds for saying so rather than
for a post-hoc rule. If the window means differ in **sign** on the primary, the
round reports both windows separately and draws no pooled conclusion.

## Fixture — a second one, and what "frozen" can honestly mean

**F9 is not reused.** Five conclusions now rest on it, and this round would make
six. A second fixture is the single highest-value thing the eval can buy.

Requirements, all fixed before any arm runs:

1. A unified diff of comparable size and defect density to F9, in a different
   domain, authored without reference to any arm's expected behaviour.
2. A **seed defect inventory**: five panellists enumerate every defect they can
   find in the diff, clusters kept at ≥3/5, then adjudicated real /
   not-a-defect / wrong by three agents under the **same brief rounds 11–15
   used, unchanged**.
3. The seed inventory and the adjudication brief are written to the repository
   **before the first arm agent runs**.

**What cannot be frozen, and why the request needs this caveat.** A seed panel
that has not seen the arms will miss defects the arms find; F9's inventory works
because four rounds of arm output accumulated into it. So what is frozen is **the
standard and the seed**, and the inventory grows **append-only** from there.

The append rules, all pre-registered:

- **A verdict already recorded is never revisited.** New claims are added; no
  existing claim is re-adjudicated, re-worded, or removed, in this round or a
  later one. This is what makes a claim's verdict mean the same thing in window 1
  and window 2.
- **Adjudication is arm-blind by construction.** Adjudicators receive claim text
  only — shuffled, with the arm withheld, the member counts withheld, and the
  claims from both arms interleaved in one set. They are not told which arm
  produced a claim, nor how many findings did, nor that arms exist.
- **The brief is byte-identical** to the one rounds 11–15 used, and is checked in
  with the round so the comparison can be audited rather than trusted.
- **Both windows' new claims are adjudicated together**, after the second window,
  so no verdict is drawn under knowledge of the first window's result. If the
  windows are analysed separately for any reason, that constraint is stated as
  broken.

Freezing the *complete* claim set before seeing arm output is not possible without
discarding every finding the seed panel missed, which would bias against whichever
arm searches more widely — here, against TS's control.

## Pre-registered decision rule

> **Adopt the stopping rule as a candidate if TS reduces Critical/Major
> non-defects against T, and its real defects added falls within 1.5 of T's** —
> the non-inferiority margin, one-sided. Otherwise change nothing.
>
> "Candidate" is the ceiling this round can reach: one fixture, one wording. A
> second fixture would be required before it enters the skill.

Explicitly **not** a decision rule: any ratio of the primary to the control. A
real defect and a non-defect are not the same unit, and dividing one by the other
imports a price the measurement never set. That slip was made and corrected in
the round-15 write-up; it is barred here in advance.

## Pre-registered predictions

- **If the sentence works**: the primary falls, `No findings` replies appear,
  findings written falls, and the control holds inside the margin.
- **The failure that matters**: the primary falls *and* the control falls past
  the margin. That is silencing, and it is the reason the control is
  non-inferiority rather than a two-sided test.
- **The null**: no movement, because a reviewer that has already decided a finding
  is worth writing has already passed the bar the sentence states, and the
  sentence changes only what it says about that decision rather than the decision.
- **The mechanism check comes first.** Zero `No findings` replies means the
  wording did not land, and no conclusion about stopping rules follows.

## Cost

Per review: 3 base + 3 T + 3 TS = **9 agents**. At n=20, plus the seed inventory
(5 panellists + 1 merge + 3 adjudicators) and the analysis (about 10 clustering,
3 adjudicators for new claims):

| | agents | ≈ tokens |
|---|---|---|
| seed inventory on the new fixture | 9 | 0.6M |
| reviews, 20 × 9 | 180 | 13.0M |
| clustering + adjudication | 13 | 0.8M |
| **total** | **202** | **≈ 14.4M** |

Split across two windows: **101 agents and ≈7.2M each**.

For comparison, the entire rounds 11–15 sequence was about 350 agents. This one
question at adequate power costs 60% of that, which is the honest price of the
variance in the metric and is stated here so the round can be declined rather
than run underpowered.

## Reproduction

```bash
# before any run — the effect this round attacks, and this design's arithmetic
evals/rule-precision/pooled.py                       # +1.57 CI +0.67..+2.47
evals/rule-ablation/protocols/round-16-power.py      # the n table and the sd sensitivity

# the one-variable check: the two briefs differ by the stopping paragraph and nothing else
diff <(sed '/^## When to stop$/,$d' <run>/brief-TS.md) <run>/brief-T.md

# after the run
evals/rule-precision/round-16/measure.py             # the two-arm table, per window
evals/rule-precision/round-16/measure.py --stratified # inverse-variance pooled + Q, I2
```

`round-16-power.py` is written with this protocol, before any run, so the n table
and the sensitivity above are re-derivable rather than asserted.

`round-16/` will carry `findings.tsv`, `clusters.tsv`, `adjudications/`, the seed
inventory, and `measure.py`, on the pattern rounds 12–15 established.

## What this cannot settle

- **One wording.** A null is a null for this sentence, not for stopping rules.
- **One fixture**, even though it is a new one. Two would be needed to ship.
- **No fixes applied between waves**; a real second round reviews changed code.
- **The paired sd is borrowed** from round 15's T-vs-C on F9. If the new fixture
  is noisier, n=20 is optimistic, and the first half of a split run should be used
  to check the assumption before committing the second.
