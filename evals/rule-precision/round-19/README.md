# Round 19 — W, W₂ and N on one ruler

Pre-registration: `../../rule-ablation/protocols/round-19.md`. Power table:
`../../rule-ablation/protocols/round-19-power.py`.

```bash
evals/rule-precision/round-19/measure.py --gate   # the gate, run first and alone
evals/rule-precision/round-19/measure.py
```

Three levels of the Finding Floor had been measured on F10 and no two sat on the
same ruler — round 9's rule blocked every comparison across rounds 17 and 18,
and N, the only arm run twice, had moved +0.44 between them. This round runs all
three in one batch.

| C+M findings whose claim is `not-a-defect`, per review | W | W₂ | N |
|---|---|---|---|
| mean | **1.67** | 3.50 | 3.67 |

| paired comparison | difference | sd_d | t | 95% CI | MDE |
|---|---|---|---|---|---|
| **CONFIRMATORY** W − N | −2.00 | 1.673 | **−2.93** | **[−3.76, −0.24]** | 2.33 |
| exploratory W − W₂ | −1.83 | 0.753 | **−5.97** | [−2.62, −1.04] | 1.05 |
| exploratory W₂ − N | −0.17 | 1.602 | −0.25 | [−1.85, +1.51] | 2.23 |

n=6 reviews per arm, 3 identical generalists each, 54 agents, 1526 findings.
`t_crit` at df=5, two-sided .05, is 2.571.

## The pre-registered rule asked the wrong question, and was followed anyway

**The interval excludes zero: [−3.76, −0.24], t=−2.93 against t_crit 2.571.**
The full Finding Floor reduced Critical/Major non-defects relative to no floor.

**And the pre-registered rule did not fire**, because it required the observed
difference to exceed the MDE of 2.33. That rule was wrong. An MDE answers "is
this n worth running?" before the data exist; significance needs only
`|t| > t_crit`, which is a lower bar. Requiring the observed effect to clear the
MDE applied a stricter test than α=.05 by accident.

The rule was followed as written, so **this round records no confirmatory claim
of the kind its own rule was reaching for** — and the correction is separated
out rather than applied retroactively. `../methods.md` states the separation the
protocols use from round 20 on: MDE for the pre-run gate, paired test and
interval for the finding, and a SESOI pre-registered separately when a
substantive size is what matters.

**The gate held**: observed sd of differences 1.673, MDE 2.33, against the 2.67
ceiling. The round was powered for what it was sized for. It was not powered for
what it found.

## What the three arms show, and what that is worth

- **Clause 2 alone is indistinguishable from having no Finding Floor at all.**
  W₂ − N is −0.17 with t=−0.25. In-batch, this is a sharper version of round
  18's −1.00, which was also null.
- **The whole of the measured gap sits between W and W₂**, −1.83 of the −2.00.
  On this fixture, clauses 1 and 3 jointly carry the section.

**This does not identify which of clause 1 and clause 3 matters**, or whether
either works alone. That needs W₁₂ and W₂₃ arms this design does not contain.
The protocol says so twice and it is repeated here because it is the thing these
numbers are most likely to be misread as answering.

**Nor is any of it a decision rule.** Only W − N could fire one, and it did not.

## The secondary is strong exploratory evidence, and is not promoted

W − W₂ is −1.83, 95% CI **[−2.62, −1.04]**, t=−5.97.

The protocol pre-declared the secondary underpowered and said "only a difference
larger than 2.96 would say anything", so by the letter of the pre-registration
it says nothing. **The honest record is exploratory, strong.** The threshold it
missed is not replaced by one it clears — a rule that was wrong before the round
started cannot be rewritten after it, and a comparison is confirmatory only if
its rule was fixed in advance and applied as written.

That 2.96 came from an sd estimated at 2.124 — round 17's W variance combined
with round 18's W₂ variance, under independence. The observed sd of differences
is **0.753**, less than half, because both arms were far less variable in this
batch and the pairing actually helped here. At the observed variance the MDE is
1.05 and the effect is 1.83, t=−5.97.

| reading | quantity | verdict |
|---|---|---|
| the rule as written | 1.83 < 2.96 | says nothing |
| the interval | [−2.62, −1.04] | excludes zero |

Both are recorded. The second is what the data show; the first is what this
round had promised to ask. **This is the same failure round 19's own protocol
fixed for the primary gate** — stating a power condition as a
number computed from a borrowed variance, rather than as the quantity it
encodes, so that it stops meaning what it meant when the variance changes. The
fix was applied to the gate and not to the secondary's threshold. It should have
been applied to both.

## The control is recorded and nothing is concluded from it

| distinct real defects reached, per review | W | W₂ | N |
|---|---|---|---|
| mean | 35.33 | 35.50 | 35.50 |

Flat. **This round does not call that non-inferiority.** A margin for such a
claim has to be fixed before the run with an n computed for it, and neither
exists here; using the observed MDE as the margin would let a noisier arm
license a larger real-defect loss. What can be said is what the numbers say:
nothing visible moved.

## The split was not the tighter instrument this time

Round 18 found the pre-registered `not-a-defect` split 22% tighter than the
composite on identical data. Here the composite is tighter:

| W − N | difference | sd_d | t | MDE |
|---|---|---|---|---|
| primary (`not-a-defect`) | −2.00 | 1.673 | −2.93 | 2.33 |
| composite (rounds 12/17) | −1.83 | 1.472 | −3.05 | 2.05 |

Neither clears its own MDE; both are significant by the conventional test. **The
split's advantage is not a property of the metric, it is a property of how much
`wrong` a batch happens to contain**, and this batch contains little (0.50 /
0.83 / 0.33 per review). The round-18 claim should be read as "on that batch",
not as a general improvement.

## Reachability, measured on the reviews themselves

No separate gate agents ran; both arms' gates were already paid on this
catalogue and fixture. The rate was taken from **the real review agents' own
tool-call traces**, matching transcripts to reviews by the output path each
agent wrote to:

| arm | executed `awk '/^### Finding Floor/,/^### Remedy Floor/'` |
|---|---|
| W | **18 of 18** |
| W₂ | **18 of 18** |
| N | 0 of 18 — the section is not there to extract |

Only a `tool_use` carrying the command counts. A transcript-wide substring match
would also fire on an agent that merely read the digest quoting it, which is the
failure round 7 measured.

## Clause 2 keeps inventing headings the template has no slot for

Round 18 found `### Minor (question, per Finding Floor): ...` — 13 findings, all
in the floor-carrying arm, all dropped by the first extractor. This round found
the next variant, `### Minor question: ...`, without the parentheses the round-18
regex had been widened to admit. Again in a floor-carrying arm.

The parser now takes two shapes, and the qualified one requires a colon so a
phrase cannot run into the title of an ordinary `### Major: foo — bar` heading.
The heading-count-against-parsed-count check is what surfaced both, and it is
reported separately from the extraction rate: **completeness of parsing is not
evidence that any rule was read.**

## One agent hard-wrapped its fields, and the check caught it before measurement

`N-4-a` reported 630 lines against 137–197 for its peers. The outlier rule says
investigate before measuring, and the investigation found 30 findings — a normal
count — with 446 hard-wrapped continuation lines, against at most five for any
other agent in the round. Taking only a field's first line had been truncating
its sentences mid-clause, degrading the clustering input for that review.

The extractor now runs a field to the next field label, heading, or blank line.
Wrapping was not arm-correlated (W 298, W₂ 13, N 453, and 446 of the N total is
this one agent).

## The inventory

| | claims | real |
|---|---|---|
| carried in (rounds 16–18) | 103 | 64 |
| + round 19, from 1526 findings | +11 | +5 |
| **total** | **114** | **69** |

Adjudicator pairwise agreement on the 11: **81.8 / 90.9 / 90.9%**, no three-way
split, against 84.3–94.0% across rounds 11–15 and 100% on round 18's nine.

**A clustering-granularity caveat that moves the control's absolute level.**
Round 18's docs agent folded all 21 doc findings into existing claims; this
round's split 26 into five new ones, four of which adjudicated `real`. That is
where four of the five new real claims came from. The granularity is applied
identically to all three arms, so it cannot bias the comparison, but it does
mean "real claims reached" is not comparable to round 18's absolute number.

Verified mechanically over all 83 merged cluster rows: 1526 findings assigned
exactly once, none dropped or duplicated, **no existing claim reworded**, no
`existing` id absent from the inventory.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 6 × 3 arms × 3 | 54 | 4.8M |
| clustering, one per target file | 8 | 0.63M |
| adjudication | 3 | 0.12M |
| **total** | **65** | **≈5.5M** |

Against the protocol's 65 agents and ≈5.3M.

## What this does not settle

- **Which of clause 1 and clause 3 matters.** Stated three times now.
- **One model, one skill, one catalogue snapshot, one fixture.**
- **No clause is deleted, and this design could not license deleting one.** It
  measures positive contributions; deleting on a null needs a non-inferiority
  design with a margin fixed in advance.
- **Nothing here licenses a change to a shipped file** — including the change of
  leaving it alone, which needs no licence.
- **The pairing is nominal by construction.** Every review in every arm received
  an identical brief; there are no per-review preambles. Making it real is a
  change to the review condition and is the obvious next fix.
- **No fixes are applied.** The fixtures are diffs.
