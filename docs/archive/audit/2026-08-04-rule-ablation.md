# Rule ablation — 2026-08-04

62 review runs measuring whether the triangulate rule set changes what a review
finds. Protocol and fixtures: `evals/rule-ablation/`.

Round 1 (38 runs) produced a headline that round 2 (24 runs) **retracted**. The
retraction is kept in place below rather than edited out, because a measurement
log that quietly replaces its wrong answers is not a log.

## Why

Anthropic removed over 80% of Claude Code's system prompt for the Claude 5
generation with no measurable loss on their coding evaluations, and the
context-engineering guidance that came with it names "exhaustive rule catalogs"
and "comprehensive upfront context loading" as anti-patterns.

The comparison that matters is not the 80%. It is that **they knew deletion was
safe because they had evaluations.** This repo had 74 rules and none. Every rule
was added on the theory that a review missed something because the rule was not
written down; the counterfactual was never run.

That is the defect this rule set already names one level down — writing a
convention is not installing its inspector — applied to the rule set itself.

## Arms

- **A** — the pattern-name index plus the target rule's full procedure
- **B** — the pattern-name index only (name present, procedure absent). This is
  what shrinking a rule row to its digest line buys.
- **C** — no catalogue at all

Single-file fixtures used a two-arm form (A: the rule alone; C: nothing), which
is the condition *most* favourable to the rule.

## Results

### Single-file fixtures (round 1)

| Fixture | A (rule) | C (nothing) |
|---|---|---|
| F1 / R44 | 2/2 · Critical · #1 | **3/3 · Critical · #1** |
| F2 / R56 | 2/2 · Critical · #1 | **3/3 · Critical · #1** |
| F3 / RT8 | 2/2 · Critical · #1 | **3/3 · Major · #2–#4** |
| F4 / R54 | 2/2 · Critical · #1 | **3/3 · Critical #1 ×2, Major #3 ×1** |

12/12 detection without the rule. Detection difference: none.

### Multi-file fixtures — the condition the catalogue was built for

8 files, 280–425 lines, target defect outside the file the change is nominally
about.

| Fixture | A (full) | B (name only) | C (nothing) |
|---|---|---|---|
| F5 / RT9 | 3/3 · Critical · #1 | 3/3 · Critical · #1 | 3/3 · Critical · #1 |
| F8 / RT9-hard | 3/3 · Critical · #1 | 3/3 · Critical · #1 | 3/3 · Critical · #1 |
| **F6 / R54** | **8/8 · Critical · #1** | **6/8** | **6/8** |

F8 was built for round 2 specifically to remove F5's weakness: F5 names the twin
relationship in comments in both files. F8 has no such comment, the two files do
not share a basename, and the pairing is discoverable only by reading the deploy
config against the test imports. It made no difference — three arms, nine runs,
all Critical at rank 1.

## The retraction

Round 1 reported, from n=3 on F6, that **the name-only arm was worse than no
catalogue at all** (2/3 against 3/3) — the sole miss in thirty scored trials. It
was written up as a signal rather than a finding, with replication named as the
first thing round 2 should do.

It did not replicate. At n=8 the two arms are **6/8 and 6/8** — identical. The
round-1 result was noise. Round 1's secondary claim, that Arm C consistently
rated the finding Major at rank 4–7, also failed: the five replication runs rated
it Critical at ranks 2 and 4.

## What survived, and it is the part round 1 under-read

On F6 the **full procedure** detects 8/8 and rates the defect **Critical at rank
1 in every single run**. Both other arms detect 6/8, and when they do hit, they
scatter from Major at rank 7 to Critical at rank 2.

So the rule's contribution on this fixture is **reliability and consistency**,
and it belongs to the **procedure, not the name** — Arm B, holding the name, is
indistinguishable from holding nothing. That bears directly on the shrink
decision: cutting a row down to its digest line would trade 8/8 for 6/8 and buy
nothing back.

Set against that: five of six fixtures show no detection difference at all.

## Scoring note

Oracles were fixed in writing before any run. Four trials named an adjacent R54
clause — the GUC is unregistered so the authority is a convention — without
naming the leak past the call, and are scored misses. Rescoring them hits would
have been fitting the oracle to the data, and would also have erased the only
difference between the arms.

## Limits

- Fixtures were authored by someone who knew the target rule. 5–15 genuine
  competing defects each does not remove that. A null result means "adds nothing
  on a fixture I wrote"; a positive result is the stronger reading, since the
  bias runs the other way.
- The surviving effect rests on **one fixture**. It is well-powered on that
  fixture (n=8 per arm) and unreplicated on any other. F6 is also the only
  fixture whose target is a *security-control-suspension* defect, so the effect
  may belong to that shape rather than to rules in general.
- Untested: long-context conditions, later rounds of a fix loop, and the live
  configuration where all 74 rules compete for attention at once. Arm A supplied
  one rule with nothing competing, so the real setting is worse for the rules
  than anything measured here.

## What follows

1. Replicate the surviving F6 effect on a second buried-security-control
   fixture. One fixture is a result; two is a property.
2. Do not delete mined rules on this evidence, and do not shrink rows to their
   digest names — Arm B is the measurement of exactly that move, and it bought
   nothing.
3. Ablate before folding. A new rule should arrive with the run that shows the
   finding degrades without it, the same obligation the hooks already carry.
4. Report n. Round 1's retracted claim came from three trials, and three trials
   were enough to see a difference that was not there.
