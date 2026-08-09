# Round 20 protocol — separating clause 1 from clause 3
(written before any run; no output read; no agent executed while writing it)

## What round 19 left

Clauses 1 and 3 of the Finding Floor contribute **−1.83 jointly** (95% CI
[−2.62, −1.04], exploratory), and clause 2 alone showed no detectable
difference from no floor at all. Which of the two carries that is not identifiable from three arms.
This round adds the two arms that identify it.

## Arms — a 2×2, with clause 2 always present

From the `bc0f966` catalogue snapshot, differing only in `common-rules.md` and
`common-rules.digest.md`, verified by `diff -rq`:

| arm | clause 1 (evidence in the change) | clause 2 (ungrounded → question) | clause 3 (preference ≠ defect) |
|---|---|---|---|
| **W** | ✓ | ✓ | ✓ |
| **W₁₂** | ✓ | ✓ | — |
| **W₂₃** | — | ✓ | ✓ |
| **W₂** | — | ✓ | — |

W is round 19's W; W₂ is round 19's W₂, byte-identical. Remaining clauses keep
their order and are renumbered from 1; the rationale sentence's count word and
its plural agreement follow the number of clauses left, which is a consequence
of the ablation and is declared here rather than found later in a diff.

Same brief, same fixture F10, arms interleaved review by review. **No per-review
preambles** — the review condition is unchanged from rounds 17–19, so the
pairing stays nominal by construction and this round does not confound a design
change with a content one.

## What this design identifies, and what it cannot

It identifies the **positive contribution of each clause** in the presence of
the others. It is **not a non-inferiority design.** A null on any comparison
does not license deleting the clause it isolates: that needs a margin fixed in
advance and an n computed for it, and neither exists here. No result of this
round can justify removing anything from a shipped file.

**"About 0.9 each" is a design assumption, not an observation.** Round 19
measured the joint contribution, never its split. The assumption is used to pick
n and appears nowhere in the analysis.

## The comparisons

1. **PRIMARY (confirmatory) — W vs W₂₃**, the contribution of clause 1.
2. **SECONDARY (exploratory) — W vs W₁₂**, the contribution of clause 3.
3. **RECORDED (exploratory)** — W₁₂ vs W₂ (clause 1 on top of clause 2 alone),
   W₂₃ vs W₂ (clause 3 on top of clause 2 alone), and the 2×2 interaction
   `(W − W₂₃) − (W₁₂ − W₂)`.
4. **Recorded, no rule** — distinct real defects reached, per arm.

Only the primary is confirmatory. Multiplicity is handled by fixing that in
advance rather than correcting α afterwards, and every other comparison is
reported with its numbers and labelled exploratory — neither discounted nor
promoted later by swapping a threshold it missed for one it clears.

## Metrics

Unchanged since round 18:

1. **C+M findings whose claim is `not-a-defect`**, per review — the quantity all
   comparisons are computed on.
2. C+M findings whose claim is `wrong`, per review — recorded.
3. The composite (C+M not `real`) — rounds 12/17's primary, for comparability.
4. Distinct real defects reached, per review — recorded per arm.
5. Findings written, precision, tokens per arm.

Adjudication against F10's 114-claim inventory, only genuinely new claims
judged, same brief, blind, member counts withheld, existing claims copied
verbatim. Extraction by `../../rule-precision/extract.py`.

## Power (before the run) — the MDE's only job

Sized on round 19's observed paired series, whose sd of differences for W − W₂
— the joint effect this round splits — was **0.753**.
`round-20-power.py` reproduces the table.

| sd_d assumed | MDE n=6 | **n=9** | n=12 |
|---|---|---|---|
| 0.753 (observed) | 1.05 | **0.79** | 0.66 |
| 1.0 | 1.39 | 1.05 | 0.88 |
| 1.2 | 1.67 | 1.26 | 1.05 |
| 1.5 | 2.09 | 1.57 | 1.32 |

**n=9 per arm. 4 × 9 × 3 = 108 review agents.**

n=6 sees an even split of the joint 1.83 only if sd_d comes in at or below 0.66,
and round 19's was 0.753. Sizing for the lopsided case would leave the likelier
one undetectable, so the extra 36 agents buy the case the round exists for.

> **GATE.** After all 36 reviews and before any arm mean is computed, the
> observed MDE on the PRIMARY difference is calculated. If it exceeds **1.83** —
> the whole joint contribution, the largest clause 1 could possibly carry — the
> round reports the primary as underpowered and makes no confirmatory claim. It
> does **not** extend n.

`measure.py --gate` prints sds and MDEs and no arm mean.

## Inference (after the run)

Paired t and 95% CI on the per-review difference, at df = n−1.

> **CONFIRMATORY RULE. Clause 1 contributes if the 95% CI for W − W₂₃ on
> Critical/Major `not-a-defect` findings lies entirely below zero.** Otherwise
> the recorded output is the numbers and no confirmatory claim.

**The observed difference is not required to exceed the MDE.** That was round
19's error; `../../rule-precision/methods.md` records it and this rule is
written the corrected way.

**No SESOI is pre-registered, deliberately.** The confirmatory question here is
whether a clause contributes at all, not whether it contributes enough to be
worth its prose — the second question would need a size fixed from what the
clause is meant to buy, and this round is not asking it.

## The control fires no rule

Real defects reached are recorded per arm and per review. A flat control is
**not** called non-inferiority: that needs a margin fixed before the run and an
n computed for it. Using an observed-variance quantity as the margin lets a
noisier arm license a larger real loss.

## Reachability

W's and W₂'s extraction rates are already paid on this catalogue and fixture
(18/18 each in round 19). W₁₂ and W₂₃ are new arms, so **the rate is measured on
their own review agents' tool-call traces** — a `tool_use` whose input carries
the extraction, not a substring match over the transcript — and reported with
the result. An arm that did not extract the section gets no causal claim.

## Pre-registered predictions

- **Clause 1 carries most of it.** Round 19's residual under the full floor was
  entirely "the change does not add a guard" claims, which is what clause 1's
  "point at the evidence inside the change" addresses head-on.
- **The failure that matters**: the primary fires and the control drops in W₂₃.
  That would be clause 1 buying precision by suppressing real findings.
- **The null worth taking seriously**: neither clause carries it alone and the
  2×2 interaction is where the effect lives — the two clauses working only
  together, which no single-clause deletion could preserve.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 9 × 4 arms × 3 | 108 | 9.5M |
| clustering, one per target file | 8 | 0.7M |
| adjudication | 3 | 0.15M |
| **total** | **119** | **≈10.4M** |

## Working rules carried in

- **An agent's `DONE` is not evidence, and its claim to have verified something
  is not a verification.** Every output is checked on disk: existence, line
  count, ids resolve, nothing dropped, duplicated, or reworded.
- **A per-review count that is an outlier against its peers is investigated
  before it is measured**, not after.
- **The gate runs alone**, by a flag that cannot print an arm mean.
- **Sub-agent models are not changed.**

## What this cannot settle

- **Whether any clause can be removed.** This measures contribution, not
  equivalence, and says so above.
- **One model, one skill, one catalogue snapshot, one fixture.**
- **The pairing is nominal.** Every review in every arm gets an identical brief.
- **No fixes are applied.** The fixtures are diffs.
