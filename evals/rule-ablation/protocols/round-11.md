# Round 11 protocol — does SPECIALISATION buy anything on a SECURITY-flavoured defect?
(written before any run; no output read)

## Why this round

Round 10 found no difference between three specialised experts and three
identical generalists on F3, a testing-flavoured defect (6.25 vs 6.50 of 11,
point estimate favouring the generalists, both arms missing the same three
properties). Its own "what follows" named the next step: replicate on a
security-flavoured fixture, because a null that holds where the *security*
expert should have the advantage is a much stronger statement than a null where
only the QA expert was on home ground.

If it replicates, the cheapest form of this skill is N general reviewers with N
a budget knob — a larger structural change than any rule edit this eval has
produced. That is the decision this round feeds.

## Deviation from round 10's plan, and why

Round 10 said "replicate on F9". The fixture is kept. **The instrument is not**,
and the reason is checkable rather than a matter of taste:

```
$ score.py --round 9
F9 Cnew   P1..P9 = 8/8 8/8 8/8 8/8 8/8 8/8 8/8 8/8 8/8   total 9.00/9
```

The only rubric F9 has — the round-5 independent nine-property rubric — is
**saturated under HEAD materials**. Both arms of round 11 carry HEAD materials
by construction (only the prompts differ), so both would score 9.00/9 and the
round would measure nothing. A ceiling cannot show a difference in either
direction, and a null read off one is worthless.

So round 11 builds F9 a rubric with headroom, by the round-5/6 panel method,
**before any arm runs** — and keeps the nine as a control (below).

The alternative considered and rejected: switch to F1, whose 19-property rubric
does have headroom (round 7's best arm reached 15.38/19). It was rejected
because F1's defect is a shell gate — the Senior Software Engineer's ground as
much as the Security Engineer's — and round 10's whole point was to test the
arm the last fixture did not favour.

## The instrument

**Primary rubric** — a merged panel rubric for F9's defect, built here:

- Four panellists, each shown only the defect sketch
  (`../sketches/F9-audit-skip.md`) and one neutral sentence stating what is
  wrong. None sees the rule set, the arms, the fixture diff, or any review
  output. Each has the whole task to itself.
- Each enumerates every property a correct fix must have — mechanism, failure
  modes, evidence.
- Clusters kept at ≥3/4 support, merged by an agent shown only the four panel
  outputs. Dropped clusters recorded with their support, as in
  `../score/R44-merged.md` and `../score/RT8-merged.md`.
- The merged rubric is written to `../score/F9-merged.md` and frozen **before
  the first arm agent runs**. Nothing in it may be edited afterwards.

**Control rubric** — the round-5 nine (`../independent-rubric.md`). Expected
saturated in both arms. It is not the primary metric; it is the check that the
arms are the same in everything except the prompt. A cell that is *not* at
ceiling on the nine means the arms differ in more than specialisation, and the
primary comparison is void.

**Pre-registered metric split.** After the merged rubric exists and before any
arm output is read, each merged property is tagged `taught` (it corresponds to
one of the round-5 nine, which R54's shipped text now teaches) or `untaught`.

- **Primary — untaught subset.** R54 teaches the taught ones to both arms
  equally, so any effect of who is reading must appear here or nowhere.
- **Control — taught subset.** Expected flat and near-ceiling in both arms.

The tagging is a mechanical mapping of merged property to round-5 property and
is recorded in `../score/F9-merged.md` at freeze time.

## Arms

Identical to round 10, on the new fixture. Both arms run **three agents** on the
same fixture with the same materials; only the prompts differ. "Three experts vs
one reviewer" would measure multiplicity, which wins trivially.

- **Arm S** — the three specialised experts as `phases/phase-3-review.md`
  defines them: Senior Software Engineer / Security Engineer / QA Engineer, each
  with its own focus, exclusions, and the `[Adjacent]` tag obligation.
- **Arm G** — three identical general reviewers. No role, no scope split, no
  exclusions, no `[Adjacent]`.

Materials in both arms are the deployed HEAD configuration: the digest as
routing index, anchored extraction from `common-rules.md`, `rule-details/`
pages, and the Remedy Floor (wired since round 7). Neither arm's materials are
edited — the manipulation is entirely in the prompt.

Merge is **mechanical and identical in both arms**: the union of the three
replies, scored as one review. No agent performs the merge; a merging agent
could favour one arm's shape.

n = 8 reviews per arm = 48 agents. Eight preambles, paired across arms, so arm S
review k and arm G review k differ only in the role framing.

## Scoring

Blind. The 16 merged reviews are redacted of arm identity — role names, "as the
security expert", expert-specific section headers, `[Adjacent]` tags, and the
phase-3 scaffolding section names that only the specialised prompt produces —
then shuffled with a fixed seed and scored by three agents against
`../score/F9-merged.md`, in different orders. Majority vote per property.
`score.py --round 11` computes the table.

Redacting `[Adjacent]` is necessary to blind the scorer and it removes the one
mechanism specialisation uniquely exhibits. That limitation is inherited from
round 10 and is stated in the result, not fixed here.

## Pre-registered metrics

1. **Primary — remedy quality on the target defect**: untaught-subset coverage
   of the merged panel rubric.
2. **Control — taught subset**: expected saturated in both arms. Not at ceiling
   ⇒ the arms differ in more than the prompt ⇒ primary comparison void.
3. **Secondary — detection**: does the union name the target defect (the oracle
   in `../README.md`: `enterSystemOperation()` never clears the flag, so every
   write after the staging step runs unaudited)? Expected saturated in both
   arms; a difference here would be the stronger result.
4. **Tertiary — breadth**: count of distinct genuine defects the union reports.
   Recorded, not claimed — more findings is not better if they are noise, and
   F9 has no adjudicated defect inventory.

## Pre-registered predictions

- **If specialisation works**: S > G on the primary, and the gap concentrates in
  properties a *security* specialist would own — blast radius of the leaked
  exemption, which later writes lose their audit record, whether the exemption
  can be reached from an attacker-controlled path, least privilege on the
  bypass.
- **The null**: no difference. Rounds 8–10 say a rule transmits exactly what it
  states and that routing is by pattern match, so every reviewer arrives at the
  same row whatever their role.
- **Claim nothing at n≤3. Report n beside every number.**
- **Compare within the batch.** Arm S and arm G run interleaved. Round 10's F3
  numbers are context, never a control — different fixture, different rubric,
  different batch, and round 9 showed a blind-scored baseline moving four points
  across batches on byte-identical materials.

## Amendments, made after the rubric was built and before the first arm ran

Both are recorded rather than edited into the text above, so what was written
first stays inspectable.

1. **The `taught`/`untaught` tagging needed a wider definition than "the round-5
   nine".** Applying it turned up two classes the wording did not anticipate:
   R54 teaches a clause that is not among the nine (a failed restore must abort
   and must not mask the callback's error), and the Remedy Floor plus the shared
   cross-cutting obligations teach properties R54 never mentions. The split is
   therefore "the materials both arms carry state this property", which is what
   the metric was for. The resolved tagging, the borderline cases, and the
   reasoning are in `../score/F9-merged.md`, written before any arm ran.
2. **Both arms' prompts are rendered from one template.** Everything phase 3
   asks of every expert regardless of role — the digest-first loading protocol,
   the Remedy Floor obligation on every `Fix:`, cross-cutting verification,
   codebase-awareness, the severity vocabulary, the `Fix:` requirement on every
   Critical and Major — appears identically in both arms. Arm S adds the role
   line, the scope/out-of-scope pair, and the `[Adjacent]` obligation; arm G
   adds nothing. Without this the comparison would confound specialisation with
   "arm S was told more things".

## What this cannot settle

Unchanged from round 10, and the second fixture does not touch any of them:

- **Disagreement** between experts, which the general arm cannot enter the same
  way.
- **The `[Adjacent]` routing**, removed by the redaction that makes scoring
  blind.
- **Multi-round convergence and escalation.** One review, one round.
- **Prophylaxis.** The split may pay while code is written, not while it is
  reviewed. Nothing here looks at the authoring pathway.

A null across F3 and F9 means "specialisation did not change what one review
produced on either defect, at equal compute". It licenses measuring the split's
remaining dimensions before paying 3× for it — not deleting it.
