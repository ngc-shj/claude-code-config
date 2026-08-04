# Rule ablation — 2026-08-04

78 review runs across eight fixtures, measuring whether the triangulate rule set
changes what a review finds. Protocol and fixtures: `evals/rule-ablation/`.

Three rounds. Rounds 1 and 2 each produced a headline that the following round
retracted. Both retractions are kept in place rather than edited out, because a
measurement log that quietly replaces its wrong answers is not a log.

## Why

Anthropic removed over 80% of Claude Code's system prompt for the Claude 5
generation with no measurable loss on their coding evaluations, and the
context-engineering guidance that came with it names "exhaustive rule catalogs"
and "comprehensive upfront context loading" as anti-patterns.

The comparison that matters is not the 80%. It is that **they knew deletion was
safe because they had evaluations.** This repo had 74 rules and none. Every rule
was added on the theory that a review missed something because the rule was not
written down; the counterfactual was never run.

## Arms

- **A** — pattern-name index + the target rule's full procedure
- **B** — pattern-name index only. This is the measurement of shrinking a rule
  row to its digest line.
- **C** — no catalogue

Single-file fixtures used a two-arm form (A: the rule alone; C: nothing), which
is the condition *most* favourable to the rule.

## All results

| Fixture | Rule | Shape | A | B | C |
|---|---|---|---|---|---|
| F1 | R44 | 1 file, 74 lines | 2/2 · C·#1 | — | **3/3 · C·#1** |
| F2 | R56 | 1 file, ~60 lines | 2/2 · C·#1 | — | **3/3 · C·#1** |
| F3 | RT8 | 2 files, ~90 lines | 2/2 · C·#1 | — | **3/3 · M·#2–4** |
| F4 | R54 | 1 file, ~90 lines | 2/2 · C·#1 | — | **3/3 · mixed** |
| F5 | RT9 | 8 files, ~280 lines | 3/3 · C·#1 | 3/3 · C·#1 | 3/3 · C·#1 |
| F8 | RT9 | 8 files, all twin cues removed | 3/3 · C·#1 | 3/3 · C·#1 | 3/3 · C·#1 |
| **F6** | R54 | 8 files, buried | **8/8 · C·#1** | **6/8** | **6/8** |
| **F9** | R54 | 8 files, buried, different domain | **8/8 · C·#1** | — | **8/8 · C·#1** |

(C = Critical, M = Major, #n = rank in the emitted finding list.)

## Round 1's retraction

Round 1 reported, from n=3 on F6, that the **name-only arm scored worse than no
catalogue at all** (2/3 against 3/3) — the sole miss in thirty trials. Written up
as a signal, with replication named as the next step.

It did not replicate. At n=8: **6/8 and 6/8**, identical. Round 1's secondary
claim, that Arm C consistently rated the finding Major at rank 4–7, failed the
same way — the replication runs rated it Critical at ranks 2 and 4.

## Round 2's retraction

Round 2 reported what survived that correction: on F6, the **full procedure**
detected 8/8 at Critical rank 1 while both other arms managed 6/8 and scattered
from Major rank 7 to Critical rank 2. Read as evidence that the rule buys
reliability and consistency, and that the value lives in the procedure rather
than the name. It was flagged as resting on one fixture, with replication on a
second buried-security-control fixture named as the next step.

F9 is that fixture: same rule, same shape (a control suspension leaking past its
intended scope, buried in an 8-file diff), different domain — an
`AsyncLocalStorage` audit-skip flag in a Node importer rather than a Postgres
GUC. **Arm A 8/8 at Critical rank 1. Arm C 8/8 at Critical rank 1.** No
difference at all.

So the F6 result is most likely fixture-specific too, not a property of the rule
or of the defect shape it was thought to represent.

## What the whole thing shows

Across eight fixtures and 78 runs, **no arm-level difference has survived
replication.** Two apparent effects were found, written up with their n and their
limits stated, and both dissolved when tested again.

That is also a finding about the *method*: in this measurement, differences
visible at moderate n are usually noise, and a single round is not a result. The
protocol now says so.

What this does **not** license:

- It is not "the catalogue is worthless". It is "I have no reproducible evidence
  that the rule text changes DETECTION on diffs I construct". The fixtures were
  written by someone who knew the target rule, and that bias runs toward
  legibility — which makes a null the weaker reading, not the stronger one.
- **The oracle only scored detection.** R54's procedure also prescribes the fix
  — call-scoped grant, restored on the error path, tested in the same context —
  and nothing here scored whether the review got the remedy right. A rule whose
  value is in the fix would be invisible to every run above.
- Arm A always supplied **one rule with nothing competing**. The live
  configuration loads 74 at once, which is the condition most unfavourable to
  them, and it remains unmeasured.

## Scoring note

Oracles were fixed in writing before each run. Four F6 trials named an adjacent
R54 clause — the GUC is unregistered, so the authority is a convention — without
naming the leak past the call, and are scored misses. Rescoring them hits would
have been fitting the oracle to the data, and would have erased the one
difference round 2 reported.

## What follows

More fixtures of this kind will most likely keep returning null. The next steps
change the design rather than adding to it:

1. **Full-load condition.** Give Arm A the whole 74-rule set the way triangulate
   actually loads it, against Arm C. That is the arrangement the catalogue is
   deployed in and the only one never tested.
2. **Score the fix, not the finding.** Compare what each arm proposes to DO
   about the defect. Half of what these rules contain is remedy, and no run here
   has looked at it.
3. **Ablate before folding**, and treat a single round as a look. Two headline
   claims from this eval died on replication.
