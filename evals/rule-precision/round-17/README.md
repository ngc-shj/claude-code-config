# Round 17 — the Finding Floor holds on a second fixture

Pre-registration: `../../rule-ablation/protocols/round-17.md`, including the n
calculation, the reachability gate, and one deviation declared before it ran.

```bash
evals/rule-precision/round-17/measure.py --variance   # the gate: sds only, no arm means
evals/rule-precision/round-17/measure.py              # the two-arm table
```

Round 12 put the Finding Floor in the skill on one fixture, one batch, n=8. This
asks whether that survives a fixture nobody built for it — F10, the Python
webhook diff round 16 bought, with its adjudicated inventory.

| | W (floor) | N (removed) | difference | t | MDE@80% |
|---|---|---|---|---|---|
| **PRIMARY** Critical/Major findings that are not defects | **2.44** | 4.56 | **−2.11** | **−3.05** | 2.05 |
| **CONTROL** distinct real defects reached | 33.78 | 34.78 | −1.00 | −1.01 | 2.94 |

n=9 reviews per arm, 3 identical generalists each, 54 agents, 1488 findings.
**The pre-registered decision rule fires**: the primary falls by more than its
MDE and the control sits well inside its own, so the floor removes non-defects
without silencing coverage.

Against round 12 on F9 — primary 1.62 vs 4.12, difference 2.50, control flat —
**the direction and the size both replicate.**

## What the arms were

- **W** — `skills/triangulate/` at `bc0f966`. The Finding Floor present and
  wired by its digest line.
- **N** — identical except the `### Finding Floor` section is cut from
  `common-rules.md` and the digest paragraph that routes to it is removed.

`diff -rq` over the two catalogue snapshots returns those two files and nothing
else. Arms were interleaved review by review within each batch, so neither sits
systematically earlier than the other.

## Reachability came first, at 3 agents rather than 36

Round 7's lesson: ablating a section nobody reads measures nothing, and it found
the floor unread by four of four reviewers under the then-deployed wiring. So
before any arm ran, 3 agents took the W catalogue over F10 and their tool-call
traces — not their output — were checked for the extraction.

**3 of 3 executed it.** The gate's other two branches (0/3 → stop, a wiring
investigation; 1–2/3 → stop, W is an uncontrolled mixture) were pre-registered
and did not fire.

## The variance gate, and the reading it forced

n=6 was computed from round 12's own per-review data (pooled sd 1.217, effect
2.50). **F9's sd did not transfer.** On F10 the observed sd was 1.742, past the
×1.15 ceiling of 1.400, and the MDE at n=6 was 3.09 — larger than the effect
being replicated. The pre-registered rule fired and the round was extended to
n=9 under a deviation declared in the protocol file before the extra reviews ran.

At n=9 the gate is **still literally exceeded**: sd 1.467 against a 1.400
ceiling. Two readings diverge and both are recorded rather than one being chosen:

| reading | quantity | verdict |
|---|---|---|
| the rule as written | sd 1.467 > 1.400 | underpowered |
| the quantity the rule encodes | MDE 2.05 ≤ 2.50 | powered |

**The ×1.15 figure was n=6's expression of "MDE ≤ 2.50".** At n=6, sd 1.400
gives MDE 2.48; the ceiling *is* the power requirement written as an sd, and it
is n-dependent. At n=9 the same requirement corresponds to sd 1.790, which 1.467
clears. A reader who prefers the literal text should read this round as
underpowered and stop at the recorded numbers; the conventional test agrees with
the permissive reading (t=−3.05 against t_crit 2.120, df=16).

## The batch split, which was a deviation

Round 17 pre-registered no split. Reaching n=9 by adding three reviews in a
second batch was authorised mid-round and declared in the protocol first. Both
arms sit in both batches, so the failure round 9 warned about — an arm measured
against a stored number from another batch — is not this one. Both estimates are
reported:

| | batch 1 (n=6) | batch 2 (n=3) | combined |
|---|---|---|---|
| primary | −2.33 | −1.67 | **−2.11** |
| control | −1.17 | −0.67 | −1.00 |

Pooled and blocked agree to two decimals on the primary. The batch effect the
deviation worried about does not show up as a distortion here.

**The contamination that cannot be removed**: the n=6 arm table had been
computed and read before the extension was authorised. The decision rests on the
sd, which `--variance` prints without any arm mean — but the person authorising
it had seen which way the numbers pointed, and a reader should discount
accordingly.

## A missing reply, caught late

Partway through, four agents fired their completion notification twice, and one
of them — `W-6-b` — had contributed **zero findings** to the first extraction
because its file was still empty when that extraction ran. The per-review
printout showed W's review 6 at 48 findings against 73–91 for the others. That
anomaly was visible and was not acted on; the first variance check ran on data
that silently lacked a reply.

What the repair found, by comparing the old snapshot against a re-extraction:

- **Exactly one reply changed.** The other 53 match title-for-title.
- **The primary series was unaffected.** W's per-review primary was
  `[2, 1, 7, 3, 2, 0]` before and after — the 25 recovered findings were all
  Minor or real, contributing no Critical/Major non-defects. The decision to
  extend therefore stands on figures the repair did not move.
- **The control series moved by one review**, 29 → 31.

The lesson is the one `TESTDOC` had already taught two steps earlier and that
was not carried across: **an agent's DONE is not evidence its file exists or is
complete.** Every later agent in this round was told to `wc -l` its own output
before replying.

## The inventory, and what it says about F10

| | claims | real |
|---|---|---|
| round 16 seed (before any arm ran) | 64 | 54 |
| + round 17 batch 1, from 977 findings | +25 | +9 |
| + round 17 batch 2, from 511 findings | +5 | +1 |
| **total** | **94** | **64** |

511 new findings produced **5** claims the inventory did not already hold. That
is the convergence rounds 12–13 saw on F9 (599 findings → 6 new claims), and it
means the next round on F10 is nearly free of adjudication.

Adjudicator pairwise agreement on the 30 new claims: **83.3 – 93.3%**, against
84.3–94.0% across rounds 11–15. The 1-vs-3 and 2-vs-3 pairs sit just below that
band's floor. No claim split three ways.

Verdicts for the 64 seed claims are carried over unchanged, and no clustering
agent reworded an existing claim — checked mechanically, 0 violations over 147
cluster rows. That is what lets `real` mean here what it meant before any arm ran.

## Cost

| | agents | tokens |
|---|---|---|
| reachability gate | 3 | 0.26M |
| reviews, batch 1 (6 × 2 arms × 3) | 36 | 3.05M |
| reviews, batch 2 (3 × 2 arms × 3) | 18 | 1.53M |
| clustering, both passes | 13 | 0.85M |
| adjudication, both passes | 6 | 0.23M |
| **total** | **76** | **≈5.9M** |

Measured against the plan's own accounting rather than estimated: the weekly
window read **3%** when round 17 began and **11%** when it ended, so the round
cost **8 percentage points** of the weekly allowance. That difference is
account-wide and therefore an upper bound.

**A note on the instrument.** `~/.claude/usage-log.jsonl` collected 22 samples
across this round, and **every value in them is a whole number** —
`14.000000000000002` and `28.000000000000004` are IEEE artifacts of a
percentage computed from a fraction, not sub-integer precision. The hook exists
because "the status line payload carries the same figures with decimals"; over
these 22 samples that premise does not hold. One night, one account, 22 points:
enough to flag, not to conclude. Two rollovers of the five-hour window occurred
and were recorded as `0` rather than carried forward, which is the behaviour the
hook's header specifies.

## What this does not settle

- **One model, one skill, one catalogue snapshot.**
- **n=9 sizes for presence, not magnitude.** "The effect is about 2.1" is not
  something this design supports; "an effect of round 12's size is present" is.
- **Two fixtures is two.** F9 and F10 are both diffs written for this eval, both
  reviewed by the same generalists, and neither is a pull request anyone shipped.
- **Nothing here measures whether a proposed fix works.** The fixtures are diffs;
  there is no repository to apply anything to.
- **The floor's effect varies by review far more than its removal does.** W's
  per-review primary runs `2 1 7 3 2 0 2 2 3` against N's `5 5 5 5 4 5 4 5 3`.
  Most of this round's variance is one arm's, and the review that produced 7 is
  not explained by anything recorded here. Whether the floor is conditionally
  effective rather than uniformly so is a question n=9 cannot answer and this
  round does not claim to.
