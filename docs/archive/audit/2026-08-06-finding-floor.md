# The Finding Floor — 2026-08-06

The first intervention in this eval aimed at whether findings are **accurate**
rather than at whether a fix is complete. Blind-adjudicated, pre-registered, and
above its own detection threshold: the Critical and Major findings that turn out
not to be defects fall from **4.12 per review to 1.62**, while the genuine
defects a review reaches stays flat.

Protocol, pre-registered before any run:
`evals/rule-ablation/protocols/round-12.md`.

## Where this came from

Not from the eval. Eleven rounds scored the remedy for one seeded defect and
never asked whether the other thirty-odd findings in a review were true. The
repository owner made two challenges that the measurements could not answer:

1. That the three experts visibly raise *different* findings, and summarising
   rounds 10–11 as "no measurable return" was wrong. It was — an adjudicated
   inventory then showed the specialised arm reaching 19.1 real defects to the
   generalists' 16.8 (`2026-08-06-finding-precision.md`).
2. That measurement which never feeds back into the skill is pointless, and that
   the quality worth improving is **whether the findings are accurate**, because
   everything downstream inherits it.

This round is the second challenge, carried out. The record should say so; the
eval did not find this on its own.

## What the diagnosis actually was

The precision adjudication of round 11 rejected 128 claims. Only **5 misread the
code**. The rest were accurate as far as they went: **34 rested on code the
change does not contain**, and **83 were preferences stated as defects**.

Reviewers were not hallucinating. They were asserting requirements a diff cannot
support — which is a property of the catalogue as a whole rather than of any one
rule, the same shape the Remedy Floor had.

## The intervention

A **Finding Floor**: three clauses in `common-rules.md` inherited by every
finding, reachable through one line the digest generator emits — the wiring
pattern round 7 established, because a section nothing routes to is dead prose.

1. **Point at the evidence inside the change.** Where the assertion is that
   something is missing, the evidence is what shows it missing. "It is not in
   the diff" is not that evidence.
2. **A requirement you cannot ground is a QUESTION, and ranks as one.** Record
   it as Minor, phrase it as a question, state what answer would close it.
3. **A preference is not a defect.**

Nothing in it tells a reviewer to drop a finding. Clause 2 re-ranks and
re-phrases — which is what made the control metric necessary.

## Result

Arms W (floor wired) and N (HEAD), identical in every other shipped file, the
two briefs byte-identical but for the catalogue path. Fixture F9, three agents
per review, n=8 reviews per arm, 48 agents. 599 findings, assigned to the 83
claims round 11 adjudicated plus 6 new ones adjudicated by the same blind panel
under the same standard.

| | W (floor) | N (HEAD) | t | MDE @80% |
|---|---|---|---|---|
| **Primary — Critical/Major findings that are not defects** | **1.62** | 4.12 | −4.11 | 1.83 |
| **Control — distinct real defects reached** | 16.50 | 16.88 | −0.59 | 1.93 |
| Critical/Major findings | 26.75 | 30.88 | −4.74 | 2.62 |
| all findings | 36.12 | 38.75 | −2.41 | 3.28 |
| precision over all findings | 88.8% | 83.9% | 1.96 | 8 pts |

Per review, the primary barely overlaps: W `0 1 1 1 2 2 3 3`, N `3 3 3 4 4 4 5 7`.

**The pre-registered bar is met.** The primary falls by 2.50 against an MDE of
1.83 — a 61% reduction in the findings that cost the fixer attention and return
nothing. **The control holds**: 0.38 apart, well inside noise, so the floor is
not buying precision by silencing reviewers.

Of the 4.13 fewer Critical/Major findings, about 1.5 moved down a band and about
2.6 were not written at all. The prediction said "re-ranked, not deleted"; the
truth is mostly re-ranked, partly dropped, and the dropped ones were
overwhelmingly non-defects, which is what the flat control establishes.

## The manipulation was verified, not assumed

Round 7 probed reachability before its ablation. That step was skipped here and
recovered mid-run, after the first twelve agents and before the remaining
thirty-six, then recorded in the protocol. Across the full run the floor's
vocabulary appears **43 times in the wired arm and 0 times in the unwired one**,
so W applied it and N cannot have been contaminated by it.

## What this does not establish

- **The adjudication standard is the measurement.** "Judge the diff as a real PR
  where everything not shown exists and works" is what makes an ungrounded
  requirement a non-defect. A reviewer who wants the missing-rate-limiter
  question raised regardless would call this a regression, and this design
  cannot tell them they are wrong. It can only tell them the cost.
- **One fixture**, whose defects are known to the person who wrote it.
- **Only the digest wiring was ablated.** The floor is shipped exactly as
  measured: the section plus the generator's pointer. No phase-file citation was
  added, because none was tested.
- **The fix phase was not measured.** The claim is that the tax fell, not that
  the saved attention was spent well.

## What follows

1. **Replicate on a second fixture.** F9 is the only fixture with an adjudicated
   inventory; building a second is the price of a replication, and this result
   is worth it.
2. **Re-measure the N curve with the floor in place.** Round 11 found the third
   reviewer still adding real defects, and adding reviewers also adds noise. The
   floor changes that trade-off and the curve should be redrawn under it.
3. **Point the same instrument at individual rules.** Rule-level precision is
   computable from this data and finds a class the firing measurement cannot: a
   rule that fires reliably and is reliably wrong is worse than one that never
   fires. Two candidates are already visible and neither is folded, because one
   adjudicated claim is not evidence enough to rewrite a rule on.
