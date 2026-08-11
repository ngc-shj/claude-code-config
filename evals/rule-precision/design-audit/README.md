# Design audit — is another round of this experiment worth running?

**Retrospective and exploratory.** It changes no confirmatory conclusion from
rounds 20–22, establishes no cause, and proposes no change to clause 1. It asks
one operational question: *would a further round change what we would do?*

**It does not show clause 1 is harmful.** Every interval at the loss ratios that
matter includes zero, and no round was designed to detect the coverage quantity
this audit puts at the centre.

Run with `design-audit/audit.py`. No new agents were run for it: everything comes
from rounds 20, 21 and 22 as committed.

## What the data actually is

**Two fixtures, three rounds.** F10 was reviewed once (round 20); F11 was
reviewed twice (rounds 21 and 22). The two F11 samples are fresh reviews but
**not independent fixture-level replicates** — anything they agree on is agreement
about F11, not about fixtures in general.

## 1. The two metrics, in their own units

| C+M `not-a-defect` per review | W | W₂₃ | diff | 95% CI |
|---|---|---|---|---|
| round 20 (F10) | 1.78 | 3.11 | −1.33 | [−2.29, −0.38] |
| round 21 (F11) | 5.11 | 5.22 | −0.11 | [−1.53, +1.31] |
| round 22 (F11) | 4.44 | 5.12 | −0.68 | [−1.68, +0.32] |

| distinct real claims reached | W | W₂₃ | diff | 95% CI |
|---|---|---|---|---|
| round 20 (F10) | 35.67 | 36.89 | −1.22 | [−4.44, +2.00] |
| round 21 (F11) | 21.11 | 21.22 | −0.11 | [−2.35, +2.13] |
| round 22 (F11) | 20.28 | 21.48 | **−1.20** | **[−2.20, −0.20]** |

The units are different and the difference is not cosmetic. The first counts
**Critical/Major findings** whose claim was adjudicated `not-a-defect`. The second
counts **distinct real claims** reached by the three reviewers of a review
*together* — a claim count over a union.

Only round 20's false-positive difference was confirmatory. **Every coverage
figure above is a control that fired no rule in its round**, including round 22's,
whose interval lies below zero.

## 2. Net benefit, and the judgement it depends on

Let ρ = cost(one missed real claim) ÷ value(one avoided false positive), in the
units above. **The value of ρ is an operational judgement, not a result.** This
audit computes the arithmetic across a range and takes no position on which ρ is
right for this catalogue.

Computed per review as `u = fp − ρ·real`, so the within-review correlation between
the two is carried. Positive favours keeping clause 1.

| ρ | round 20 | round 21 | round 22 |
|---|---|---|---|
| 0.0 | +1.33 [+0.38, +2.29] | +0.11 [−1.31, +1.53] | +0.68 [−0.32, +1.68] |
| 0.5 | +0.72 [−0.73, +2.18] | +0.06 [−1.38, +1.50] | +0.08 [−1.07, +1.23] |
| 1.0 | +0.11 [−2.80, +3.03] | 0.00 [−2.15, +2.15] | −0.52 [−1.98, +0.94] |
| 2.0 | −1.11 [−7.18, +4.96] | −0.11 [−4.27, +4.04] | −1.72 [−4.01, +0.57] |

Break-even ρ from the point estimates: **round 20 = 1.09, round 21 = 1.00, round
22 = 0.57.**

**What can be said: at ρ > 1.1 the point estimate is negative in all three
rounds.** What cannot: that clause 1 is harmful. Every interval at ρ ≥ 0.5
includes zero. The finding is that **the sign of the decision depends on a
quantity no round was sized to measure**, not that the sign is known.

## 3. Three reviewers per observation — right for one metric, wrong for the other

Effect ÷ MDE at a fixed agent budget, averaged over all C(3,k) subsets of round 22
so every k uses the same agents. A value of 1 would mean the observed effect
exactly clears the MDE.

| agents | C+M not-a-defect | | | real claims reached | | |
|---|---|---|---|---|---|---|
| | k=1 | k=2 | k=3 | k=1 | k=2 | k=3 |
| 200 | **0.62** | 0.59 | 0.56 | 0.32 | 0.79 | **0.98** |
| 300 | **0.76** | 0.72 | 0.69 | 0.39 | 0.98 | **1.21** |

The metrics disagree about k, for a structural reason. The finding count is a
**sum**: its effect grows linearly with k (−0.23, −0.45, −0.68) while its sd grows
*faster* than √k (1.749 against 1.597 under independence, a 1.10× penalty from the
between-reviewer covariance). Coverage is a **union**: one reviewer already
reaches 15.45 of the ~20 claims three reach, and the arm gap only opens on
aggregation (−0.17, −0.75, −1.20), so k=3 gains against independence (0.74×).

**No single configuration optimises both.** A design that must be powered for
superiority on one and non-inferiority on the other cannot pick k freely.

## 4. What non-inferiority on coverage would cost

n per arm, one-sided α .025, power .80, **equal variances assumed**, plugging in
round 22's observed pooled sd (1.752) **as if it were known**:

| margin | θ = 0.0 | θ = −0.5 | θ = −1.0 |
|---|---|---|---|
| 0.5 | 193 | unreachable | unreachable |
| 1.0 | 49 | 193 | unreachable |
| 1.5 | 22 | 49 | 193 |
| 2.0 | 13 | 22 | 49 |

θ is the **assumed** true W − W₂₃ coverage difference. **If θ equals round 22's
observed −1.20**, no margin below 1.20 is reachable at any n — but that is a
conditional statement about an assumed θ, not a property of the world. Every
figure here inherits the plug-in and equal-variance assumptions, which is the
same weakness round 22 paid for.

## 5. Where each side comes from — and why they are not symmetric

**False positives avoided, round 22 on F11: net +17 findings over 25 reviews/arm.**

| cluster | W | W₂₃ | diff | claim |
|---|---|---|---|---|
| R21-RTR-01 | 9 | 23 | **+14** | no rate limiting on the three new routes |
| R21-RTR-02 | 2 | 10 | +8 | no per-org cap on schedules |
| R21-API-04 | 3 | 10 | +7 | no per-org schedule cap |

Dropping R21-RTR-01 alone takes the per-review difference from +0.68 to +0.12.
Concentrated, and concentrated in one shape: demands for infrastructure the diff
does not show. **This describes round 22 on F11 and nothing else.**

**Coverage, same round: net −30 review-reaches (−1.20 per review), across 16
claims W reached less often (sum −44) against 7 it reached more often (+14).** The
three largest negatives sum −18 of −30 — the largest single one is −8.

**The two sides are not shaped alike.** The benefit sits in one claim family; the
loss is spread over sixteen claims. **It therefore cannot be assumed that a
narrower clause would keep the benefit and drop the loss**, and this audit does
not propose one.

## 6. Sizing without paying in full first

Round 22 spent 150 agents and then learned its MDE was 1.41 against a 1.33
ceiling. Replaying its own first n₁ indices as an internal pilot:

| pilot n₁ | pooled sd | re-sized n |
|---|---|---|
| 8 | 1.808 | 30 |
| 10 | 1.810 | 30 |
| 12 | 1.694 | 27 |
| **15** | **1.618** | **25** |

Full sample (n=25): sd 1.749, would ask for n=29.

**The pilots at n₁ = 8, 10 and 12 point above 25; the pilot at n₁ = 15 lands
exactly on 25 and would not have flagged a shortfall.** A pilot is not a
guarantee — its own variance estimate is imprecise — which argues for a cap and a
stop rule rather than for trusting its point estimate.

**It is also not automatically alpha-free.** Pooling the two arms' variances uses
the group labels even though it never looks at the arm *means*. Any future use has
to pre-register the re-estimation method and calibrate its type-I error rather
than assume it is unaffected.

## The operational conclusion

**Do not run round 23.** Not because clause 1 is shown to be harmful — it is not —
but because **the expected decision value of another round is low at the current
cost**:

1. The decision turns on net benefit, and the break-even ρ sits at 1.09, 1.00 and
   0.57 across the three rounds. Sharpening the false-positive estimate alone does
   not move a decision that depends on ρ and on coverage.
2. The design that would settle it — superiority on false positives plus
   non-inferiority on coverage — is not affordable at margins a reader would find
   persuasive, and no single reviewer configuration is efficient for both halves.
3. Two F11 rounds have already cost ≈19M tokens without resolving the replication
   question they were built for.

**This records a decision not to spend, and nothing else. Clause 1 is unchanged.**

## What this audit deliberately does not do

- It does not propose new wording for clause 1. Section 5 shows why a narrow fix
  cannot be assumed to work, and designing one needs its own evidence.
- It does not choose ρ.
- It does not test whether the rounds' variances differ, explain the
  between-reviewer covariance, or promote any exploratory interval.
- It does not license removing clause 1. That still needs a non-inferiority design
  with a declared margin, which section 4 prices and does not run.
