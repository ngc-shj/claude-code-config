# Round 10 protocol — does expert SPECIALISATION buy anything over REPETITION?
(written before any run; no output read)

## Why this and not more catalogue work

Rounds 1-9 measured the rule catalogue and nothing else. The three-expert split
is the dominant cost of a review round - three agents plus a merge, repeated per
round - and has never been a variable. It is also the only measurement that can
redirect the others: if specialisation carries the review, thinning the
catalogue is safe; if it does not, a 3x cost is available immediately and the
catalogue becomes the main lever.

## The confound this design removes

Comparing "three experts" against "one reviewer" measures multiplicity, not
specialisation, and multiplicity trivially wins. Both arms therefore run THREE
agents on the same fixture with the same materials. Only the prompts differ.

- **Arm S** - the three specialised experts as phase-3 defines them
  (Functionality / Security / Testing, each with its own focus, exclusions and
  severity criteria).
- **Arm G** - three identical general reviewers, same materials, no role, no
  focus split, no exclusions.

Merge is mechanical and identical in both arms: the union of the three replies,
scored as one review. No agent performs the merge, since a merging agent could
favour one arm's shape.

## Fixture

F3 (RT8, vacuous denial-path test) first, n=8 per arm = 48 agents. It carries a
detection oracle and a merged panel rubric (`score/RT8-merged.md`, 11
properties), and its target defect is testing-flavoured - the case where
specialisation should help most, since one arm has a dedicated testing expert
and the other has nobody whose job it is.

Replicate on F9 (R54, security-flavoured) only if a difference appears. A
difference on one fixture is a look, not a result.

## Scoring

Blind: the 16 merged reviews redacted of arm identity (role names, "as the
security expert", expert-specific section headers), shuffled, scored by three
agents against `score/RT8-merged.md`, majority vote per property. Same pipeline
as rounds 7-9; `score.py` computes the table.

## Pre-registered metrics

1. **Primary - remedy quality** on the target defect: merged-rubric coverage.
2. **Secondary - detection**: does the union name the target defect (oracle)?
   Expected saturated in both arms; a difference here would be the stronger
   result.
3. **Tertiary - breadth**: count of distinct genuine defects the union reports.
   Recorded but not claimed - more findings is not better if they are noise,
   and no adjudicated defect inventory exists for F3.

## Pre-registered predictions

- **If specialisation works**: S > G on the primary, and the gap concentrates in
  properties a testing specialist would own.
- **The null**: no difference. The three specialised prompts differ from three
  general ones in framing only, and the fixture plus the catalogue drive the
  output. Rounds 1-3 already showed prompt framing did not move detection.
- Claim nothing at n<=3. Report n beside every number. Compare within the batch:
  arm G and arm S run interleaved, never against a stored figure.

## What this cannot settle

The split's value may lie in dimensions this fixture does not exercise -
disagreement between experts, the [Adjacent] routing, escalation, or multi-round
convergence. A null here means "specialisation did not change what one review
produced on this defect", not "the split is worthless".
