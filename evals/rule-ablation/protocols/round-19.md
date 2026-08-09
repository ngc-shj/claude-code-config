# Round 19 protocol — W, W₂ and N on one ruler
(written before any run; no output read; no agent executed while writing it)

## Why this and not another two-arm round

Three levels of the Finding Floor have been measured on F10 and **no two of them
are on the same ruler**:

| | arm | round | batch | C+M `not-a-defect` |
|---|---|---|---|---|
| all three clauses | W | 17 | A | 1.22 |
| clause 2 alone | W₂ | 18 | B | 3.33 |
| no floor | N | 17 **and** 18 | A, B | 3.89 / 4.33 |

Round 9's rule forbids measuring an arm against a stored number from another
batch, and N — the only arm run twice — moved **+0.44** between them. Every
statement anyone wants to make across those rows is currently blocked, and the
block is correct.

This round puts all three in one batch so the comparisons become legal. It does
**not** re-ask round 18's question as its primary.

## What three arms can and cannot identify

They identify the **joint** contribution of clauses 1 and 3, as the difference
between the full section and clause 2 alone. They do **not** identify which of
clause 1 and clause 3 carries that contribution, or whether either does alone.
Separating them requires arms this design does not contain — W₁₂ (clauses 1 and
2) and W₂₃ (clauses 2 and 3) — and is a different round.

Nothing in this protocol should be read as answering "which clause".

## Arms

From the `bc0f966` catalogue snapshot, differing only in
`common-rules.md` and `common-rules.digest.md`, verified by `diff -rq`:

- **W** — the section as shipped: clauses 1, 2 and 3, wired by the digest line.
  Round 17's W arm, reproduced.
- **W₂** — clause 2 alone, renumbered to 1, rationale paragraph kept, plural
  agreement repaired. Round 18's W₂ arm, reproduced byte-for-byte from
  `../../rule-precision/round-18/arms.diff`.
- **N** — the section and its digest paragraph removed. Rounds 17 and 18's N.

Same brief, same fixture F10, arms interleaved review by review so none sits
systematically earlier. **There are no per-review preambles** — every review in
every arm receives the identical brief, as in rounds 17 and 18. That is what
makes the pairing nominal; see the analysis section.

## The comparisons, and their standing

**One inferential comparison. The other two are not.**

1. **PRIMARY — W vs N.** Does the full three-clause section reproduce, inside
   one batch and on the pre-registered `not-a-defect` metric, an effect of the
   size round 17 measured? This is the only comparison a decision rule reads.
2. **SECONDARY — W vs W₂.** The joint additional contribution of clauses 1 and
   3 over clause 2 alone. Reported with its own MDE; **see the power note — it
   is underpowered by design and its null carries no information.**
3. **RECORDED — W₂ vs N.** Round 18's comparison, repeated for calibration
   against a same-batch N. Not a primary for any new claim, and no decision rule
   reads it.

The multiplicity is handled by fixing the inferential comparison in advance
rather than by correcting α after the fact: only W vs N can fire a rule.

## Metrics

Unchanged from round 18, which pre-registered them:

1. **C+M findings whose claim is `not-a-defect`**, per review — the primary
   quantity for all three comparisons.
2. C+M findings whose claim is `wrong`, per review — recorded, no rule.
3. The composite (C+M not `real`) — rounds 12 and 17's primary, for
   comparability only.
4. **Distinct real defects reached**, per review — recorded per arm, read by no
   decision rule. See the decision-rule section for why this round does not call
   a flat result non-inferiority.
5. Recorded — findings written, precision, tokens per arm.

Adjudication against F10's 103-claim inventory, only genuinely new claims
judged, same brief (`../../rule-precision/adjudication-brief.md`), blind, member
counts withheld, existing claims copied verbatim.

## The analysis is PAIRED, and one honest word about what that buys

The three arms are run over the same review indices in one batch, so the
statistic, the sd and the MDE are all computed on the **per-review difference**,
not on two arm means with a pooled sd. `round-19-power.py` reproduces every
number below.

**Pairing here is exact and conservative, not more powerful, and the reason is a
fact about how rounds 17 and 18 were actually run**: every review within an arm
received an IDENTICAL brief. There were no per-review preambles. Review *i* in
one arm therefore shares nothing with review *i* in another except its index,
and the data say so —

| | value |
|---|---|
| sd(W − N) observed | **1.323** |
| sd(W − N) implied by independence | 1.344 |

a correlation of about zero. The paired test is still what this design asserts
and so is what gets pre-registered; it simply costs degrees of freedom (t at
n−1) and buys nothing back. **Making the pairing real — one shared preamble per
review index across all three arms — is a change to the review condition, is not
made in this round, and is the obvious thing for a later round to fix.**

| comparison | sd of differences | effect expected | **MDE n=6** | n=9 | n=12 | n=15 |
|---|---|---|---|---|---|---|
| **PRIMARY** W vs N | 1.323 | **2.67** | **1.84** | 1.39 | 1.16 | 1.02 |
| SECONDARY W vs W₂ | 2.124 | 1.67 | 2.96 | 2.23 | 1.87 | 1.64 |
| RECORDED W₂ vs N | 1.095 | 1.00 | 1.53 | 1.15 | 0.96 | 0.84 |

**n=6 per arm. 3 × 6 × 3 = 54 review agents.** The unpaired reading of the
primary at n=6 would be 1.99; both clear the 2.67 ceiling, so the choice of
analysis does not decide n.

W vs W₂ has never been run in one batch, so no difference series exists for it;
its sd is estimated under independence, which the table above shows is what the
observed paired series look like anyway.

### What n=6 buys, honestly

- **The primary is powered**: 2.67 against a paired MDE of 1.84.
- **The secondary is not, and no affordable n fixes it.** Its expected effect,
  1.67, comes from subtracting round 17's W from round 18's W₂ after removing
  the +0.44 batch shift N showed — a cross-batch estimate, which is exactly the
  quantity this round exists to stop relying on. n=15 (135 agents, ~11.7M
  tokens) puts the MDE at 1.64, a 2% margin against a number that soft.
  **The secondary's null is therefore uninformative and is pre-declared as
  such**; only a difference *larger* than 2.96 would say anything.
- **The recorded comparison is calibration, not evidence**, whatever its MDE.

### The power gate, stated as the quantity

> **After all 18 reviews and before any arm mean is computed, the observed MDE
> on the PRIMARY comparison is calculated. If it exceeds 2.67, the round reports
> the primary as underpowered and makes no adoption claim. It does not extend n.**

`measure.py --gate` prints sds and MDEs and no arm mean, as in round 18.

## Reachability, measured on the reviews themselves

Ablating a section nobody reads measures nothing (round 7). W's gate passed 3 of
3 in round 17 and W₂'s passed 3 of 3 in round 18, on this catalogue and this
fixture, so **no separate gate agents run**.

Instead the extraction rate is measured on **the 36 real W and W₂ review agents'
own tool-call traces**: a `tool_use` whose input carries the Finding Floor
extraction, counted per arm and reported with the result. A transcript-wide
substring match does not count, because the digest quotes that command as an
instruction and would match an agent that only read about it.

**If an arm's reviews did not extract the section, no causal claim is made for
that arm.** The rate is reported whatever it is.

The heading-count-against-parsed-count check also runs, per file — round 18
found 13 findings that one arm's obedience to clause 2 had put outside the
template. That check establishes the extraction was complete; **it is not
evidence that any rule was read**, and the two are reported separately.

## Pre-registered decision rule

> **The full section's effect is confirmed in-batch if the per-review paired
> difference W − N on Critical/Major `not-a-defect` findings is negative by more
> than the primary MDE.** Otherwise the recorded output is the numbers and no
> claim.
>
> **The control does not appear in this rule.** Real defects reached are
> recorded per arm and per review, and nothing more is said about them. Judging
> them "within the control's MDE" would be using an observed-variance quantity
> as an equivalence margin, which lets a noisier arm license a larger real loss —
> the noisier the data, the easier the arm passes. A non-inferiority claim needs
> a margin fixed before the run and an n computed for it; neither exists here,
> so **this round does not claim the floor leaves real defects untouched.** A
> control drop that is visible will be reported as visible, and it would be a
> reason to stop trusting the primary rather than a rule that fires.
>
> Firing re-ships nothing. What it changes is that the three levels finally sit
> on one ruler, and that round 17's 2.67 stops depending on a single batch.

Explicitly **not** decision rules: the control, the secondary, the recorded
comparison, and any comparison of this round's absolute levels against round
17's or 18's.

## Pre-registered predictions

- **The primary fires.** The effect replicated across two fixtures already; a
  third batch on the same fixture is the easiest of the three.
- **The failure that matters**: W's control drops with its primary. That is
  suppression, and it is the one result that would argue against the shipped
  section.
- **The null worth taking seriously**: N's level drifts again, as it did by
  +0.44, and the whole difference turns out to be batch noise that two rounds
  read as an effect.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 18 × 3 | 54 | 4.7M |
| clustering, one per target file | 8 | 0.5M |
| adjudication | 3 | 0.1M |
| **total** | **65** | **≈5.3M** |

No reachability gate: both arms' gates are already paid. F10's inventory took
1027 findings to 9 new claims in round 18, so the adjudication line rests on
that convergence holding a third time.

## Working rules carried in

- **An agent's `DONE` is not evidence, and its claim to have verified something
  is not a verification.** Round 18 had a clustering agent fire twice with a
  *wrong* first result. Every output is checked mechanically on disk: existence,
  line count, ids resolve, nothing dropped, duplicated, or reworded.
- **A per-review count that is an outlier against its peers is investigated
  before it is measured.**
- **The gate runs alone**, by a flag that cannot print an arm mean.
- **Sub-agent models are not changed.**

## What this cannot settle

- **Which of clause 1 and clause 3 matters.** Stated again because it is the
  question this design is most likely to be misread as answering.
- **One model, one skill, one catalogue snapshot, one fixture.**
- **n=6 sizes the primary for a 2.67-sized effect and nothing finer.**
- **No fixes are applied.** The fixtures are diffs.
