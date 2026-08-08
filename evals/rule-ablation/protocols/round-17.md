# Round 17 protocol — does the shipped Finding Floor hold on a second fixture?
(written before any run; no output read; no agent executed while writing it)

## Why this and not round 16 again

The Finding Floor is **in the skill**. Round 12 put it there on one fixture, one
batch, n=8. Round 16's stopping sentence is not shipped and never will be on the
evidence available. A constrained budget spends on the claim that is already
acting on users.

F10 and its 64-claim seed inventory exist (`../../rule-precision/round-16/`),
which is what makes this affordable: the inventory absorbs most of the
adjudication, exactly as rounds 12–13 did on F9.

## Arms

Round 12's, on F10 instead of F9:

- **W** — the catalogue at HEAD. The floor is present and wired by its digest line.
- **N** — identical except the Finding Floor section is removed from
  `common-rules.md` and the `Fix:` template pointer reverted.

One variable. Both arms are rendered from the same snapshot and differ by that
section, verifiable by `diff`. Same review brief as round 16's `brief-base.md`,
same preambles p1–p6.

## Reachability comes first, and it is a gate

Round 7's finding: the floor was a section no routing path named, and zero of
four reviewers read it. Ablating a section nobody reads measures nothing.

**Before any arm runs**, 3 agents run the W catalogue on F10 and their tool-call
traces are inspected for the floor extraction. Output is not read — only whether
the extraction happened.

- **0 of 3 read it** → the round stops. What would follow is a wiring
  investigation, not a content ablation.
- **1–2 of 3** → the round stops and reports the rate. A partially-reached
  section makes W an uncontrolled mixture.
- **3 of 3** → proceed.

Cost of the gate: 3 agents. Cost of skipping it: 36.

## n, computed from round 12's own per-review data

W `0 1 1 1 2 2 3 3`, N `3 3 3 4 4 4 5 7`. Pooled sd **1.217**, observed effect
**2.50**. Two-sample, α=.05 two-sided, 80% power:

| n/arm | MDE |
|---|---|
| 4 | 2.83 |
| 5 | 2.42 |
| **6** | **2.16** |
| 8 | 1.82 (round 12's, reproduced — the arithmetic checks) |

**n=6 per arm. 2 × 6 × 3 = 36 agents.** n=8 is round 12's number and copying it
here would be the habit round 16's protocol named and rejected.

### What n=6 is not powered for

It detects an effect the size round 12 measured. It does **not** distinguish
"replicates at full size" from "replicates at half size" — that needs roughly
n=20 per arm. A result at n=6 licenses "the effect is present on F10" or "it is
not detectable on F10", and nothing about whether it is as large.

### The borrowed sd, and the stopping rule that follows

1.217 comes from F9. On F10 at n=6:

| sd multiplier | MDE | verdict |
|---|---|---|
| ×1.00 | 2.16 | powered |
| ×1.15 | 2.48 | razor-thin |
| ×1.30 | 2.81 | underpowered |

**Pre-registered**: after all 12 reviews, the observed pooled sd is computed
before any arm comparison. If it exceeds ×1.15 of 1.217, the round reports the
comparison as underpowered and makes no adoption claim, rather than reporting a
null as evidence of absence.

## Pre-registered metrics

Against the F10 seed inventory, only genuinely new claims adjudicated, same
brief (`../../rule-precision/adjudication-brief.md`), blind, counts withheld.

1. **Primary — Critical/Major findings that are not defects**, per review. Lower
   is better. This is round 12's primary, unchanged.
2. **Control — distinct real defects reached**, per review. The floor must not
   buy its precision by suppressing real findings.
3. **Recorded** — findings written, precision, tokens per arm.

## Pre-registered decision rule

> **The floor replicates if W's Critical/Major non-defects fall below N's by more
> than the MDE, and W's real defects reached are within the control's MDE of
> N's.** Otherwise the recorded output is both numbers and no claim.
>
> A replication does not re-ship anything. What it changes is what the skill's
> evidence rests on: one fixture or two.

Explicitly **not** a decision rule: any comparison of F10's absolute levels
against F9's. Different fixture, different batch — round 9's rule stands.

## Pre-registered predictions

- **Replicates.** The floor's mechanism is a filter on what qualifies as a
  finding, which has nothing to do with the fixture's domain.
- **The failure that matters**: the primary moves and the control moves with it.
  That is suppression, and F10 being denser than F9 gives it more room.
- **The null**: F10's non-defect rate is already low because the seed panel's
  ≥3/5 filter produced a fixture whose obvious findings are mostly real, leaving
  the floor nothing to remove.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reachability gate | 3 | 0.25M |
| reviews, 12 × 3 | 36 | 2.6M |
| clustering + adjudication of new claims | ~8 | 0.5M |
| **total** | **47** | **≈3.4M** |

Two points where the round stops without paying the rest: the reachability gate
(after 0.25M) and the variance check (which does not stop the spend but stops the
claim). Against round 16's actual spend of 2.0M for a round that stopped at its
manipulation check, this is the same order and buys a shipped claim rather than
an unshipped one.

## What this cannot settle

- **One model, one skill, one catalogue snapshot.**
- **n=6 sizes for presence, not magnitude.**
- **The seed inventory is F10's, and it was built before any arm ran** — claims
  the arms find that the seed missed are adjudicated fresh, so the standard is
  fixed but the claim space is not complete.
- **No fixes are applied.** The fixtures are diffs; nothing measures whether a
  proposed remedy works.
