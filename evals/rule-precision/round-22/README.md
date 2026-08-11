# Round 22 — the gate fired: no confirmatory claim about replication

Pre-registration: `../../rule-ablation/protocols/round-22.md`.

```bash
evals/rule-precision/round-22/measure.py --gate   # the gate, run first and alone
evals/rule-precision/round-22/measure.py
evals/rule-precision/round-22/combined.py         # the two exploratory cross-round quantities
```

Round 20 confirmed, on F10, that clause 1 reduces Critical/Major `not-a-defect`
findings. This round attempted that replication on F11 at a sensitivity chosen to
see an effect of round 20's size, with 25 fresh reviews per arm.

## The result in one paragraph

**The observed Welch MDE came in at 1.41 against a pre-registered ceiling of
1.33, so the gate fired and the round makes no confirmatory claim.** The
variance did not transfer: round 21's se on this metric implied per-arm sds near
1.42, and this round measured 1.895 (W) and 1.590 (W₂₃). That possibility is
exactly what the gate was placed to catch — the protocol named round 17 as the
standing reminder that variance does not always transfer — and the pre-registered
response, followed here, is to report the primary as underpowered and **not** to
extend n. Everything below the gate is descriptive.

| | |
|---|---|
| arm sds on the primary | W **1.895**, W₂₃ **1.590** |
| Welch df | 46.6 |
| observed MDE at n=25 | **1.41** |
| pre-registered ceiling | 1.33 → **exceeded** |

The protocol put the chance of this at about 6%, under the stated assumption
that round 21's variance was exactly right. It was not, and the assurance figure
was never a probability about the world — it was a probability conditional on an
assumption this round falsified.

## Descriptive, not confirmatory

| C+M per review | W | W₂₃ |
|---|---|---|
| **PRIMARY** `not-a-defect`, all reasons | 4.44 | 5.12 |
| .. `preference` | 3.36 | 3.12 |
| .. `scope` | 0.64 | 1.04 |
| .. `outside-diff` | 0.44 | 0.96 |
| .. `misreads-code` | 0.00 | 0.00 |
| `wrong` | 0.08 | 0.04 |
| real claims reached | 20.28 | 21.48 |
| findings written | 59.44 | 60.48 |

| Welch, independent groups | difference | se | df | 95% CI | MDE |
|---|---|---|---|---|---|
| primary W − W₂₃ | −0.68 | 0.495 | 46.6 | [−1.68, +0.32] | 1.41 |
| exploratory `outside-diff` subtype | −0.52 | 0.220 | 40.2 | [−0.97, −0.07] | 0.63 |

The index-paired sensitivity analysis agrees: −0.68, CI [−1.89, +0.53].

**The `outside-diff` subtype interval lies below zero. That is not this round's
result.** The confirmatory rule attaches to the primary and to nothing else; the
subtype was pre-registered as exploratory and is reported here because it was
pre-registered, not because it came out the way it did. Reading a below-zero
exploratory interval as the finding, after the confirmatory one failed its gate,
is the substitution this whole protocol structure exists to prevent.

## Inventory — four different numbers that must not be conflated

| | |
|---|---|
| round 21's pinned inventory | 79 |
| existing claims **reached** by this round's reviews | 71 (8 were not reached) |
| claims new here | 21 |
| claims **represented** here | 92 |
| cumulative inventory after this round | 100 |
| adjudicated `real`: among the 92 represented / cumulative | 39 / 42 |

The 71 are claims this round *matched*, not the inventory it was given. Their ids
and claim texts were copied byte-for-byte from `../round-21/clusters.tsv` — checked
mechanically across all 116 rows citing an existing claim, zero defects.

**New-claim share of the primary**, per the pre-registered definition (C+M on a
claim new here **and** adjudicated `not-a-defect`, over that arm's primary total):

| | W | W₂₃ |
|---|---|---|
| | 3 / 111 = **2.70%** | 4 / 128 = **3.12%** |

So ~97% of each arm's primary rests on claims whose verdicts were fixed before
this round's arms ran. That was the improvement over round 21, and it held.

## The two exploratory cross-round quantities

Both pre-registered, both exploratory, neither affected by or affecting the gate.

| | difference | se | 95% CI |
|---|---|---|---|
| combined over rounds 21+22, fixed-effect inverse-variance | **−0.48** | 0.398 | [−1.26, +0.30] |
| `D = Δ_F11 − Δ_F10` | **+0.65** | 0.667 | [−0.69, +1.99] |

Weights: round 21 35%, round 22 65%. No naive 34-per-arm pool is computed.

`D` is a **descriptive cross-study heterogeneity contrast**: fixture is confounded
with round, inventory history, and review batch, so its interval cannot attribute
any difference to the fixture alone. Its interval contains zero, which does not
show the two fixtures' effects are equal.

## Deviations, declared

1. **Clustering was split ten ways, not eight.** The protocol said one agent per
   changed file; `worker.go` drew 1474 findings, 2.8× the largest bucket any
   single agent has handled, so it was cut into three chunks. The split is a
   slice of an already content-ordered file, so arm blinding is preserved, and
   every chunk received the same existing-claim list. The cost of the split
   showed up exactly where expected: two pairs of duplicate new claims written in
   parallel, resolved by the merge agent (`merge-map.tsv`), plus one new claim
   that turned out to duplicate an existing one.
2. **One finding has an empty `what_is_wrong`.** It kept its `File:` and title, so
   it was clustered rather than dropped; it is Minor and therefore outside the
   primary.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 25 × 2 arms × 3 | 150 | ≈12.5M |
| clustering, 8 files with worker.go in 3 chunks | 10 | 0.95M |
| merge and verbatim check | 1 | 0.05M |
| adjudication, new claims only | 3 | 0.14M |
| **total** | **164** | **≈13.7M** |

The review figure is the per-agent mean over the batch times 150, not an exact
tally; the weekly meter moved 50% → 66% across the round, which is consistent
with it. Against the protocol's estimate of ~163 agents and ≈13.8M.

## What this round did and did not buy

It did not buy an answer about replication. It bought two things worth having:

- **A measurement of this metric's variance on F11 at n=25** — the quantity every
  future power calculation for it depends on, and the one round 21's nine reviews
  estimated badly.
- **A demonstration that the gate works.** A round that had skipped it would have
  reported [−1.68, +0.32] as a replication failure at adequate power. It was not
  adequate power, and the protocol caught that before any arm mean was computed.

## What this cannot settle

- **Whether the effect replicates on F11.** Not at this power. The interval is
  reported; no claim is attached to it.
- **Whether the effect differs between F10 and F11.** `D` is descriptive and
  confounded.
- **Whether clause 1 acts on the `outside-diff` subtype.** That interval is
  exploratory here, and round 21 — which *was* powered for the subtype — did not
  detect it.
- **Anything licensing removal of clause 1.** Removal needs a non-inferiority
  design with a declared margin. This is not one, and neither was any round before
  it.

## What the next round needs, and what it must not assume

Plugging **this round's** observed sds (1.895, 1.590) into the same gate:

| n/arm | MDE | P(gate exceeded)¹ |
|---|---|---|
| 25 (this round) | 1.411 | 69% |
| 29 | 1.307 | 40% |
| 32 | 1.242 | 20% |
| 36 | 1.170 | 5% |
| 40 | 1.109 | 1% |

¹ same assurance approximation as the protocol's: equal variances across arms,
expected df held fixed. Margins to compare with each other, not exact risks.

n = 29 is the formal minimum and n ≈ 36 buys back the margin round 22 was designed
for. **Neither number is adopted here.** Two rounds have now estimated this
variance and disagreed by 25%; a third estimate from a single round is not a
firmer basis than the second was. The variance audit comes first — why W's spread
grew — and the next round's n is chosen after it, not from this table.
