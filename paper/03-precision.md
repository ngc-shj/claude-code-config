# 3. Finding precision, and what buys coverage

The ablation harness scored one seeded defect per fixture and was blind to the
other thirty findings a review reports. This chapter is about the instrument
that sees them — the adjudicated claim inventory of §7.1.1 — and the three
structural questions it answered on its first fixture: whether findings are
true, what a second and third reviewer add, and what conditioning a second
wave costs. Everything here is **MEASURED** on single batches, one fixture at
a time; the replication story belongs to Chapter 4, and the instrument's own
biases to §7.1.1 and Chapter 8.

## 3.1 The instrument, briefly

Forty-eight review replies over F9 — the round-11 material reused, no new
reviews — yielded 574 findings, clustered into 83 distinct claims, adjudicated
to **39 real** by a popularity-blind panel under the standing assumption
(agreement 84.3–94.0%; `../evals/rule-precision/README.md`, Method; re-run by
`../evals/rule-precision/measure.py`). Precision is a property of findings;
coverage is a property of a review's three replies unioned over distinct real
claims. The two move independently, which is the chapter's recurring fact.

## 3.2 Specialists against generalists: the trade, and where it pays

Three identical generalists against three specialised experts — the S/G pair
of `../evals/rule-ablation/README.md`, the only arms that vary the skill's
*structure* — on the same fixture, prompts rendered from one template
(MEASURED; `../evals/rule-precision/README.md`, "What it found"):

| | precision | distinct real claims, of 39 |
|---|---|---|
| G — three identical generalists | **81.6%** | 16.8 |
| S — three specialised experts | 73.5% | **19.1** |

The split pays at the margin, not the average. One generalist beats one
specialist (10.5 vs 8.1); two are level; three specialists win — because the
specialists' third reviewer adds **+4.8** distinct real claims where the
generalists' adds +2.5, their replies overlapping half as much (Jaccard 0.116
vs 0.246). Structure buys coverage by buying *decorrelation*, and pays for it
in precision.

The coverage difference is significant (t = −2.22) and small relative to
what the round was built to see: the design's MDE was 3.23 claims at 80%
power — a statement about the design's sizing, not a post-hoc verdict on the
observed effect (§7.1.4 keeps those apart; the source round's own
"significant and under-powered at once" predates that separation). The
size's uncertainty is a matter for an interval and for replication, and
neither exists here. One batch, one fixture.

## 3.3 The reviewer-count curve, and the case for k = 3

Eight reviews of six identical generalists, sub-sampled to a six-point curve
— unbiased only because the reviewers are identical (MEASURED;
`../evals/rule-precision/round-13/`):

| N | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| distinct real claims | 10.8 | 14.3 | 16.4 | 17.9 | 19.1 | 20.0 |
| C/M non-defects | 0.7 | 1.5 | 2.2 | 2.9 | 3.6 | 4.4 |

Coverage decays toward the discovered-set ceiling while the false-positive
cost climbs linearly at ~0.7 per reviewer. Within this batch, the shipped
k = 3 is a choice based on this curve, not a measured optimum: the third
reviewer's marginal claims fall to about three-fifths of the second's
(+2.1 against +3.5) while the cost stays linear. A widely quotable splice — §3.2's specialists at
19.1 matching this curve's five-generalist point for roughly 60% of the
tokens — crosses batches, which §7.1.2 classifies as context rather than a
control, and the source audit says the same of cross-batch numbers; it is
reported here as context and **not** carried as a measured case. No change to
k was ever adopted, and none of Chapter 6's three refuted candidates touches
it.

## 3.4 Conditioning a second wave: the trade nobody shipped

Round 14 told a second wave what the first found. Restatement collapsed by
96% (1.12 base-claim restatements against 28.88 blind), and the freed
attention bought more ground, less accurately: **+43% real claims added,
+89% Critical/Major non-defects** (MEASURED;
`../evals/rule-precision/round-14/`). The pre-registered rule cleared on
coverage and failed on cost, and the recorded output is both numbers and no
recommendation — the round is the series' cleanest example of an intervention
measured, priced, and not adopted.

Round 15 then asked whether the conditioning base could be titles-only: no
detectable difference from the full base — identical point estimates on the
primary, 7.83 vs 7.83, beside an MDE of 2.86, which is precisely why an
identical point estimate is not equivalence — and round 14's cost penalty
**did not replicate** (MEASURED; `../evals/rule-precision/round-15/`; six of
the eight pre-registered reviews ran, both deviations recorded).

## 3.5 The second fixture, and a round that stopped itself

Five conclusions rested on F9 alone, so round 16 bought F10: authored by an
agent told the domain, the file shape and the line budget and **nothing about
the arms** — the authorship bias running the other way for once — with a
361-entry seed inventory panel-reduced to 54 adjudicated real claims
(MEASURED; `../evals/rule-precision/round-16/`). The round's substantive
question was never answered: its pre-registered manipulation check — replies
must end `No findings` where the stopping sentence applies — failed in the
first 2 of 10 reviews, and the round stopped, spending none of the remaining
5.4M tokens. The 21%-fewer-findings difference visible at n = 2 is recorded
and not claimed. What the stop bought is the instrument itself: F10's
inventory proved stable across the rounds that followed — by round 18, 1,027
new findings were producing nine new claims and zero new real defects — which
is what made Chapter 4's replication affordable.

## 3.6 What this chapter claims, and no more

On one fixture and one batch each: structure trades precision for coverage
and pays at the third reviewer; reviewer count buys coverage at a linear
false-positive cost (the specialists-match-five-generalists splice is
cross-batch context, not a result); conditioning eliminates restatement and
inflates both yield and error, and was not shipped; a titles-only base is not detectably
different from a full one, beside its MDE. The 39-claim denominator is the
union of what these 48 replies found — coverage of the discovered set, not of
the fixture; `real` is a panel's judgement under a stated assumption; the
clustering was one pass. Replication, where it exists, is Chapter 4's story,
and only for the Finding Floor.
