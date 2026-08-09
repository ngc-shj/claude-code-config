# Round 21 protocol — does clause 1's effect land where predicted, and off F10?
(written before any run; no output read; no agent executed while writing it)

## The hypothesis

> **Clause 1 reduces high-severity non-defect findings whose alleged defect
> depends on code outside the change, and that reduction appears on F11.**

The hypothesis is stated in the terms the primary actually measures. An earlier
draft said clause 1 "selectively reduces" findings about "a guard or requirement
absent from the change". **Both words were wider than the decision rule.**
`outside-diff` is the adjudicators' tag for "depends on code the diff does not
show", which is broader than guards-and-requirements; and *selectively* asserts
a contrast against the other reasons that no test here evaluates. The
difference-in-differences that would license it is recorded below and is
explicitly **not** a confirmatory quantity in this round.

Round 20 established that clause 1 is the only Finding Floor component with
positive evidence of an effect. It did not measure **why**, and every clause
result rests on F10 alone. This asks both at once, because the prediction makes a
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

### F11 is generated once and frozen

The generating prompt is committed **before** F11 is generated, and **the commit
id is recorded in this protocol** before the generating agent is launched. F11
is produced from that prompt **once** and frozen. The order is the point: a
prompt written after seeing a fixture is a fixture chosen twice. Regeneration is permitted only for a pre-defined
mechanical failure — the output does not apply as a diff, or is truncated — and
never for anything about its content: not its subject matter, not how many
ungrounded-requirement openings it happens to offer, and above all **not its
`outside-diff` base rate**, which cannot be known before the arms run and must
not be sampled for.

A fixture regenerated until it suits the hypothesis measures the hypothesis.

## Metrics — using a tag that predates the hypothesis

The standing adjudication brief has asked for a reason tag since round 11:
`misreads-code | outside-diff | preference | scope`. **`outside-diff` is the
subtype this hypothesis is about** — "it depends on code the diff does not
show" — and it is assigned by adjudicators who see neither the arm nor the
member counts. No new classification step is introduced, and the criterion was
fixed years of rounds before anyone asked this question.

1. **PRIMARY (confirmatory)** — Critical/Major findings whose claim is
   `not-a-defect` with reason `outside-diff`, per review.

   **Aggregation rule, fixed here because the primary depends on it.** The three
   adjudicators each return a verdict and a reason. A claim counts as
   `outside-diff not-a-defect` **only when at least two of the three assign that
   JOINT label** — `not-a-defect` *and* `outside-diff` from the same
   adjudicator. A claim that two call `not-a-defect` for different reasons is
   not in the primary. Agreement on this binary classification is reported
   alongside the usual pairwise verdict agreement. Deciding how to combine split
   reasons after seeing which way they split is the failure this forecloses.
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

| n/arm | Welch MDE at round 20's arm sds | paired MDE at sd_d 0.972 |
|---|---|---|
| 6 | 1.32 | 1.35 |
| **9** | **1.00** | 1.02 |
| 12 | 0.84 | 0.86 |

Round 20's subtype arm sds were 0.707 (W) and 0.726 (W₂₃); Welch df at n=9 is
16.0. If the sd fails to transfer and comes in at 1.4 per arm, the Welch MDE at
n=9 is 1.47 — still under the 1.78 the subtype showed on F10, which is what the
gate below tests.

**n=9 per arm. 2 × 9 × 3 = 54 review agents.** n=6 suffices if the sd transfers;
round 17 is the reason not to assume it does — F9's sd did not transfer to F10
and that round had to be extended by declared deviation.

> **GATE.** After all 18 reviews and before any arm mean is computed, the
> observed Welch MDE on the PRIMARY is calculated. If it exceeds **1.78** — the effect
> the subtype showed on F10 — the round reports the primary as underpowered and
> makes no confirmatory claim. It does **not** extend n.

## Inference (after the run)

**Welch's two-sample t interval, independent groups.** The arms share review
indices and nothing else — there are no per-review preambles, so index *i* in
one arm has no factor in common with index *i* in the other. Round 19 measured
that directly: sd of the paired differences was 1.323 where independence
predicts 1.344. Treating a pairing that carries no information as if it did
costs degrees of freedom and asserts a structure the design does not have.

**The nominal index-paired analysis is computed and reported as a sensitivity
analysis**, not as the primary. On round 20's subtype series the two agree to
within noise — Welch CI [−2.49, −1.06] against paired [−2.52, −1.03], MDE 1.00
against 1.02 — so the choice does not decide n and is made for correctness
rather than for power.

> **CONFIRMATORY RULE. Clause 1 reduces the `outside-diff` subtype on F11 if the
> Welch 95% CI for W − W₂₃ on the PRIMARY lies entirely below zero.**

The observed difference is **not** required to exceed the MDE; that was round
19's error and `../../rule-precision/methods.md` records the separation.

## How the result will be read — fixed in advance

| PRIMARY (`outside-diff`) | SECONDARY (all non-defects) | reading |
|---|---|---|
| CI below zero | CI below zero | the **predicted mechanistic signature is observed**, and it appears on F11 |
| CI crosses zero | CI below zero | exploratory evidence of transfer; **the predicted signature is not observed** |
| CI below zero | CI crosses zero | **the finding mix shifted** off the subtype without a detectable change in total non-defect cost |
| CI crosses zero | CI crosses zero | **no transfer detected on F11** |

The SECONDARY is exploratory, so a CI below zero on it is *exploratory evidence
of transfer*, never a confirmed one — the confirmatory claim is the PRIMARY's
alone.

Row 3 is the one worth stating plainly: it would mean the mix of findings moved
off the subtype without the total bill falling. That is a real result and not a
disappointing version of row 1. It is a statement about what reviewers wrote,
not about what they were doing when they wrote it.

### The contrast that would license the word "selective"

`Δ(outside-diff) − Δ(other reasons)` is computed and **recorded**. If clause 1
acts on the subtype rather than on non-defects at large, that difference is
negative. **It is exploratory here.** Calling the effect selective requires this
difference to be the pre-registered test, with its own n; this round is sized
for the subtype's own effect and is not sized for a contrast between two noisy
counts. Round 20's post-hoc values — −1.78 on the subtype against +0.44 on the
rest — are the reason to record it and are not a substitute for testing it.

**An interval that crosses zero is a failure to detect, never a demonstration
that the effect is absent.** No row above licenses an equivalence claim.

## The claim inventory, and a cost decision this protocol does not hide

F10's inventory took a dedicated seed round (round 16: five panellists, 93
claims, 64 kept) so that `real` and its reason tags were fixed **before** any arm
ran. F11 has no inventory. Two options, and the protocol picks the cheaper one
with its weakness stated rather than pretending the choice is free:

- **Chosen: adjudicate after the arms run**, blind, counts withheld, order
  shuffled, same standing brief. **The union of both arms' claims is clustered
  and adjudicated together**, with the arm and the member counts withheld, so no
  claim is judged in the knowledge of which arm produced it. This is what rounds
  17–20 did for their new claims, and what round 11 did for all of its own.
  **Weakness: the claim space is defined by the arms themselves**, so a claim
  only one arm ever makes still enters the inventory and is judged there.

  The primary survives this, because it counts findings each arm actually wrote
  and their adjudicated reason — not coverage of a fixed defect set. What a seed
  inventory would mainly improve is real-defect coverage, and **that is a
  recorded metric here that fires no rule**. Accordingly, **F11's real-defect
  counts are a record over an arm-generated claim space and are not compared
  with F10's fixed inventory** in any direction.
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
- **The reviewer-side mechanism.** This round tests whether clause 1's effect
  lands on the finding class the prediction names. Why a reviewer writes fewer
  of those — what they do instead, whether they look elsewhere or simply write
  less — is not observed here, and the write-up must not narrate it.
- **No fixes are applied.** The fixtures are diffs.
