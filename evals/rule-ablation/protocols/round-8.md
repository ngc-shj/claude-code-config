# Round 8 protocol — R54 extension ablation (written before any run output was read)

## Question

#125 extended R54's procedure with six obligations (a)–(f) on direct evidence
that sixteen reviewers holding the original rule fixed the defect incompletely.
Does carrying the extension change what a reviewer's Fix: states, on the
properties the extension teaches?

## Arms

- **E** — materials at eval/remedy-floor-ablation HEAD (wired floor digest,
  extended R54).
- **O** — identical, except `rule-details/R54.md` reverted to its pre-#125
  content (`git show 2d79b7e^`). The floor stays wired in BOTH arms — round 8
  varies one thing.

Same 5-step review prompt as rounds 4/7, same eight paired preambles.

## Fixtures

F6 (GUC / `SET LOCAL`, buried) and F9 (ALS flag, buried) — the two R54
fixtures, different platform idioms. n=8 per cell → 32 runs.

## Scoring

The independent nine-property rubric (`evals/rule-ablation/score/rubric.md`,
round-5 panels — derived without seeing the rule, so scoring the extended arm
against it is not self-scoring). Outputs redacted (rule IDs, protocol traces,
floor tokens, catalogue vocabulary, fixture filenames), all 32 shuffled into
one blind set, three scorers in different orders, majority vote per property.

## Pre-registered predictions

- **Primary**: E > O on the extension's properties P3 (restore previous value),
  P4 (await before restore), P5 (isolation), P8 (throw-path test), P9
  (nesting/concurrency test). P9 is the decisive one: 0/29 in every arm so far;
  if E moves it off zero the extension pays where nothing else has.
- **Control**: P1, P2, P7 (the original three clauses) should sit near
  saturation in both arms — a gap there means the arms differ in more than the
  extension.
- Baselines for context, not comparison (different config: pre-floor): blinded
  round-6.5 arm F means 6.25 (F6) / 7.25 (F9).
- A difference that does not appear in BOTH fixtures is fixture-specific and is
  not a claim. Report n beside every number.

## Preambles (same order both arms)

Identical to round 7's list of eight.
