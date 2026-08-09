# Round 21 protocol — does clause 1 work the way we think, and off F10?
(written before any run; no output read; no agent executed while writing it)

## The hypothesis

> **Clause 1 selectively reduces findings that report a guard or requirement
> absent from the change as a high-severity defect, and that effect appears on a
> fixture other than F10.**

Round 20 established that clause 1 is the only Finding Floor component with
positive evidence of an effect. It did not measure **why**, and every clause
result rests on F10 alone. This asks both at once, because the mechanism makes a
prediction that a second fixture is the natural place to test: if clause 1 works
by refusing ungrounded requirements, the effect should land on that subtype and
not on non-defects at large.

## Arms — the minimum that answers it

- **W** — the catalogue at HEAD: Finding Floor clauses 1, 2, 3.
- **W₂₃** — clauses 2 and 3; clause 1 removed, remaining clauses renumbered.

Both are byte-reproducible from `bc0f966` and round 20's `arms.diff`. Two arms,
not four: round 20 already located the effect, and this round asks what it is
made of and whether it travels.

## The fixture: F11, and what a second fixture can prove

F11 is written for this round by an agent **blind to the arms and to this
hypothesis**, given only the shape brief that produced F10 (`round-16`). It must
not be built to contain ungrounded-requirement bait, which would make the
primary a measurement of the fixture.

**A result on F11 establishes transfer to F11.** It does not establish
fixture-independence, and no wording in the write-up may imply otherwise. Two
fixtures is two.

## Metrics — using a tag that predates the hypothesis

The standing adjudication brief has asked for a reason tag since round 11:
`misreads-code | outside-diff | preference | scope`. **`outside-diff` is the
subtype this hypothesis is about** — "it depends on code the diff does not
show" — and it is assigned by adjudicators who see neither the arm nor the
member counts. No new classification step is introduced, and the criterion was
fixed years of rounds before anyone asked this question.

1. **PRIMARY (confirmatory)** — Critical/Major findings whose claim is
   `not-a-defect` with reason `outside-diff`, per review.
2. **SECONDARY (exploratory)** — Critical/Major `not-a-defect`, all reasons.
3. **RECORDED** — Critical/Major `not-a-defect` with any other reason;
   distinct real defects reached; `wrong`; findings written; tokens.

The control fires no rule. A flat real-defect count is **not** non-inferiority.

## Power (before the run) — the MDE's only job

Calibrated on round 20's W-vs-W₂₃ series recomputed on the `outside-diff`
subtype. **That recomputation is post-hoc** — nobody pre-registered the subtype
in round 20 — and it is used here only to pick n:

| round 20, W − W₂₃ | difference | sd_d |
|---|---|---|
| `outside-diff` subtype | −1.78 | **0.972** |
| all `not-a-defect` | −1.33 | 1.225 |
| other reasons | +0.44 | 1.130 |

| n/arm | MDE at sd_d 0.972 | at 1.4 (if it does not transfer) |
|---|---|---|
| 6 | 1.35 | 1.95 |
| **9** | **1.02** | 1.47 |
| 12 | 0.86 | 1.24 |

**n=9 per arm. 2 × 9 × 3 = 54 review agents.** n=6 suffices if the sd transfers;
round 17 is the reason not to assume it does — F9's sd did not transfer to F10
and that round had to be extended by declared deviation.

> **GATE.** After all 18 reviews and before any arm mean is computed, the
> observed MDE on the PRIMARY is calculated. If it exceeds **1.78** — the effect
> the subtype showed on F10 — the round reports the primary as underpowered and
> makes no confirmatory claim. It does **not** extend n.

## Inference (after the run)

Paired t and 95% CI on the per-review difference, df = n−1.

> **CONFIRMATORY RULE. Clause 1 acts on the ungrounded-requirement subtype, on
> F11, if the 95% CI for W − W₂₃ on the PRIMARY lies entirely below zero.**

The observed difference is **not** required to exceed the MDE; that was round
19's error and `../../rule-precision/methods.md` records the separation.

## How the result will be read — fixed in advance

| PRIMARY (`outside-diff`) | SECONDARY (all non-defects) | reading |
|---|---|---|
| CI below zero | CI below zero | the mechanism is supported and the effect transfers to F11 |
| CI crosses zero | CI below zero | the effect transferred; **the proposed mechanism is not supported** |
| CI below zero | CI crosses zero | attention moved off the subtype without a detectable change in total non-defect cost |
| CI crosses zero | CI crosses zero | **no transfer detected on F11** |

Row 3 is the one worth stating plainly: it would mean clause 1 redirects where
reviewers look — "this is not mine to demand, so look elsewhere" — without the
total bill falling. That is a real finding and not a disappointing version of
row 1.

**An interval that crosses zero is a failure to detect, never a demonstration
that the effect is absent.** No row above licenses an equivalence claim.

## The claim inventory, and a cost decision this protocol does not hide

F10's inventory took a dedicated seed round (round 16: five panellists, 93
claims, 64 kept) so that `real` and its reason tags were fixed **before** any arm
ran. F11 has no inventory. Two options, and the protocol picks the cheaper one
with its weakness stated rather than pretending the choice is free:

- **Chosen: adjudicate after the arms run**, blind, counts withheld, order
  shuffled, same standing brief. This is what rounds 17–20 did for their new
  claims, and what round 11 did for all of its own. **Weakness: the claim space
  is defined by the arms themselves**, so a claim only one arm ever makes still
  enters the inventory and is judged there.
- Rejected: a seed round first. It buys a standard fixed before the arms at
  roughly the cost of the measurement itself.

## Pre-registered predictions

- **Row 1.** The subtype falls and the total falls with it.
- **The failure that matters**: the primary fires and real defects reached drop
  in W. That is clause 1 buying its precision by suppressing coverage.
- **The null worth taking seriously**: F11's shape gives reviewers little to
  demand about absent code, the subtype is rare in both arms, and the round
  measures nothing because the fixture had no room for the effect. The
  **subtype's base rate in W₂₃ is recorded first** for exactly this reason: a
  W₂₃ mean below 1.0 means the round could not have seen its own effect, and
  that is reported whatever the intervals say.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| F11, written blind | 1 | 0.15M |
| reviews, 9 × 2 arms × 3 | 54 | 4.8M |
| clustering, one per target file | ~8 | 0.8M |
| adjudication | 3 | 0.2M |
| **total** | **~66** | **≈6.0M** |

Higher per finding than round 20 because a new fixture has no inventory to
absorb the adjudication.

## Working rules carried in

- `../../rule-precision/preflight.py` before every batch. Round 20 lost fourteen
  agents to the five-hour window by not asking.
- `../../rule-precision/await_outputs.py` for every wait. A `DONE` is not
  evidence, and one `ls` cannot tell "not yet" from "never".
- One review index at a time — 2 arms × 3 parts = 6 — confirmed landed before
  the next. The subagent cap is 20 and excess launches are rejected, not queued.
- Extraction by `../../rule-precision/extract.py`; heading count reconciled
  against parsed count per file.
- Sub-agent models are not changed.

## What this cannot settle

- **Fixture-independence.** F11 is one more fixture, not a population.
- **Whether clause 3 contributes.** Not in this design and not this round's
  question.
- **Why clause 1 works, at any level below the subtype it acts on.** This
  measures *what* it selects against, not the reviewer-side process that
  produces the selection.
- **No fixes are applied.** The fixtures are diffs.
