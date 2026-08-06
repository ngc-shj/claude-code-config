# Round 12 protocol — does a FINDING FLOOR cut the findings that are not defects?
(written before any run; no output read)

## Why this round, and where the question came from

This one is not the eval's own idea, and the record should say so. Rounds 1–11
all scored the same thing: whether a review's fix for **one seeded defect** has
the properties a correct fix needs. The repository owner made two challenges that
the measurements could not answer and that turned out to be right:

1. That the three experts visibly raise *different* findings, and calling that
   "no measurable return" was wrong. It was. An adjudicated defect inventory
   showed the specialised arm reaches 19.1 real defects to the generalists' 16.8
   (`docs/archive/audit/2026-08-06-finding-precision.md`), which the remedy
   rubric could not see.
2. That measurement which never feeds back into the skill is pointless, and that
   the thing worth improving is **whether the findings are accurate**, because
   bad findings make every downstream step bad.

That second challenge is this round. The precision adjudication says where the
inaccuracy comes from, and it is not what one would guess: of 128 rejected
claims, only **5 misread the code**. The rest are accurate as far as they go and
are still not defects — **34 rest on code the change does not contain**, and
**83 are preferences stated as defects**.

Reviewers are not hallucinating. They are asserting requirements the diff cannot
support. That is a property of the catalogue as a whole rather than of any one
rule, which is the same shape the Remedy Floor had — and the floor is the only
intervention this eval has measured working across rules (round 7).

## The intervention, frozen before the run

A **Finding Floor**: a section of `common-rules.md` inherited by every finding,
wired into the loading protocol by one digest line, exactly as round 7 wired the
Remedy Floor. Verbatim text of arm W's addition:

> ### Finding Floor
>
> **Every finding carries the three clauses below, whichever rule it was routed
> through.** They are stated once here because they belong to no single rule: an
> adjudication of 574 findings from sixteen blind-scored reviews found that where
> a finding was not a defect, the cause was almost never a misreading of the code
> (5 of 128) — it was a requirement asserted about code the change does not
> contain (34), or a preference stated as a defect (83).
>
> 1. **Point at the evidence inside the change.** Name the file and the line or
>    symbol in the diff that makes the finding true. Where the assertion is that
>    something is MISSING, the evidence is what shows it missing — a call site the
>    guard does not cover, a branch with no counterpart, a declared contract the
>    change contradicts. "It is not in the diff" is not that evidence: a change is
>    a change, not the system, and the limiter, the schema, the policy or the
>    layer you cannot see are the author's to know about rather than yours to
>    assume absent.
> 2. **A requirement you cannot ground is a QUESTION, and ranks as one.** Where
>    the finding rests on code the change does not contain, ask rather than
>    assert: record it as Minor, phrase it as a question, and state what answer
>    would close it. Reserve Critical and Major for what the change itself makes
>    true. An ungrounded requirement reads exactly like a defect and costs the
>    same attention to dismiss.
> 3. **A preference is not a defect.** Where the change is defensible as written
>    and you would merely have written it differently, say that in those words or
>    do not say it. "Could be extracted", "would be cleaner", "consider using" are
>    not Major.

Note what the clauses do **not** say: nothing here tells a reviewer to drop a
finding. Clause 2 re-ranks and re-phrases. That is deliberate, and the control
metric below is what checks it.

## Arms

- **W** — HEAD materials plus the Finding Floor section and one digest line
  wiring it (extract the section once per review; every finding satisfies it).
- **N** — HEAD materials, unchanged.

The arms differ only in the shipped files, never in the prompt — round 7's rule.
Both arms use round 11's **generalist** reviewer prompt, since round 11 showed
that is the higher-precision configuration and this round is about precision.

Fixture F9, three agents per review merged mechanically, n=8 reviews per arm,
48 agents. F9 because it is the only fixture with an adjudicated defect
inventory, and reusing that inventory holds the verdict standard fixed.

## Pre-registered metrics, with the difference each can catch

Stated before the run because a null read off an underpowered design is worth
nothing (`docs/archive/audit/2026-08-04-rule-ablation.md`, power audit).

1. **Primary — Critical/Major findings per review that are not defects.** Lower
   is better. Round-11 baseline for this prompt: **4.38 per review, sd 0.92**,
   so n=8 per arm detects a drop of **1.38** at 80% power. That is a 31%
   reduction — a real effect size, not a rounding error.
2. **Control — distinct real defects reached per review.** Must NOT drop. If the
   floor works by silencing reviewers, precision rises and this falls, and the
   intervention has made the review worse. A fall larger than the noise voids
   the primary claim.
3. **Secondary — precision over all findings**, and **the Critical/Major to
   Minor ratio**. Clause 2 predicts findings move down a band rather than
   disappearing; the ratio is where that shows.
4. **Recorded, not claimed** — total findings per review.

## Pre-registered predictions

- **If the floor works**: primary drops by at least 1.38, the control holds, and
  the Critical/Major share falls while total findings stay roughly level —
  ungrounded requirements re-ranked, not deleted.
- **The failure mode to watch for**: primary drops AND the control drops. That is
  suppression, and it is worse than the disease.
- **The null**: no movement, because the floor is prose about judgement rather
  than a procedure with a checkable output, and rounds 8–9 only ever showed
  transmission of *concrete* clauses.
- Compare within the batch. Round 11's numbers are context, never the control
  arm.

## Adjudication

Same standard, reused rather than rebuilt: the 83 claims from
`evals/rule-precision/` keep their verdicts, new findings cluster into them where
they match, and **only genuinely new claims are adjudicated** — by the same brief,
blind, shuffled, counts withheld, three agents, majority vote. Holding the
standard fixed across rounds is the point; re-adjudicating the old claims would
let the standard drift between arms.

## Reachability probe, run after batch 1 and recorded before batches 2–4

Round 7's ablation began with a probe of whether the section was read at all,
because a wired-vs-absent comparison means nothing if the wired arm never
extracts it. That step was skipped here and is recovered mid-run, on the first
twelve agents only, before the remaining thirty-six were launched. Written down
because looking at any output creates an obligation to say what was looked at.

| | replies | findings | Critical+Major share | phrases only the floor produces |
|---|---|---|---|---|
| W | 6 | 73 | 74% | **10** |
| N | 6 | 82 | 79% | **0** |

The floor is reachable and exclusive: its vocabulary appears ten times in the
wired arm and never in the unwired one, so W is applying it and N cannot have
been contaminated by it. The severity shift runs in the pre-registered
direction. **No metric, subset or prediction above was changed after seeing
this** — the check answers "did the manipulation arrive", which the design
requires before its result can be read at all.

## What this cannot settle

- **The adjudication standard is the measurement.** "Judge the diff as a real PR
  where everything not shown exists and works" is what makes an ungrounded
  requirement a non-defect. A reviewer who wants the rate-limiter question raised
  regardless would call this floor a regression, and this design cannot tell them
  they are wrong.
- **One fixture**, and one whose defects are known to the person who wrote it.
- **Nothing here measures the fix phase**, which is where the saved attention was
  supposed to go. The claim is about the tax, not about the receipt.
