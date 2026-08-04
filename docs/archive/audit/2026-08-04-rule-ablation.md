# Rule ablation — 2026-08-04

110 review runs across eight fixtures, measuring whether the triangulate rule set
changes what a review produces. Protocol and fixtures: `evals/rule-ablation/`.

Four rounds. Rounds 1 and 2 each produced a headline the next round retracted;
both retractions are kept in place rather than edited out, because a measurement
log that quietly replaces its wrong answers is not a log. Round 4 changed what
was being scored and found the first effect that replicated.

## Why

Anthropic removed over 80% of Claude Code's system prompt for the Claude 5
generation with no measurable loss on their coding evaluations, and the
context-engineering guidance names "exhaustive rule catalogs" and "comprehensive
upfront context loading" as anti-patterns.

The comparison that matters is not the 80%. It is that **they knew deletion was
safe because they had evaluations.** This repo had 74 rules and none.

## Arms

- **A** — pattern-name index + the target rule's full procedure (one rule, spotlit)
- **B** — pattern-name index only. The measurement of shrinking a row to its digest line.
- **C** — no catalogue
- **F** — the **deployed configuration**: the digest as routing index, all 74 rows
  available, `rule-details/` pages, and SKILL.md's extract-what-matches protocol

## Rounds 1–3: detection

| Fixture | Rule | Shape | A | B | C |
|---|---|---|---|---|---|
| F1 | R44 | 1 file | 2/2 | — | **3/3** |
| F2 | R56 | 1 file | 2/2 | — | **3/3** |
| F3 | RT8 | 2 files | 2/2 | — | **3/3** |
| F4 | R54 | 1 file | 2/2 | — | **3/3** |
| F5 | RT9 | 8 files | 3/3 | 3/3 | 3/3 |
| F8 | RT9 | 8 files, twin cues removed | 3/3 | 3/3 | 3/3 |
| F6 | R54 | 8 files, buried | 8/8 | 6/8 | 6/8 |
| F9 | R54 | 8 files, buried, other domain | 8/8 | — | 8/8 |

**Round 1's retraction.** From n=3 on F6: the name-only arm scored *worse than no
catalogue* (2/3 vs 3/3). At n=8 both are 6/8. Noise.

**Round 2's retraction.** What survived that: on F6 the full procedure hit 8/8 at
Critical rank 1 against 6/8 for the others. F9 reproduced F6's shape in another
domain — Arm A 8/8, Arm C 8/8, no difference. Fixture-specific.

Across rounds 1–3, **no detection difference survived replication.**

## Round 4: score the remedy, under the deployed configuration

Detection was saturated, so the remaining question was what each arm proposes to
**do**. Both arms were asked for a `Fix:` on every Critical and Major finding.

R54's procedure prescribes three things. Each scored as a binary:

1. **call-scoped** — a derived context or an acquire/release wrapper, not
   "reset it afterwards" (which the rule names as the wrong shape)
2. **error path** — the restore happens on the throw path too
3. **same-context test** — assert the control still refuses in the SAME context
   immediately after the sanctioned call returns

| | detection | call-scoped | error path | same-context test | total |
|---|---|---|---|---|---|
| **F9 · Arm F** | 8/8 | 8/8 | 8/8 | 8/8 | **24/24** |
| **F9 · Arm C** | 8/8 | 8/8 | **1/8** | 6/8 | 15/24 |
| **F6 · Arm F** | 8/8 | 8/8 | 8/8 | 8/8 | **24/24** |
| **F6 · Arm C** | 5/8 | 5/5 | 5/5 | **0/5** | 10/24 |

**Every Arm F run scored 3/3. No Arm C run in either fixture scored 3/3.** 16 and
0 out of 16.

The clause Arm C drops is not stable — on F9 it loses the error path seven times
in eight; on F6 it takes `finally` every time (natural for `SET LOCAL`) and never
once asks for the same-context test. **The unaided reviewer reaches two of three,
and which two is fixture-dependent.**

F6 also shows a detection gap that rounds 1–3 saw and round 4 confirms: Arm C
missed the defect entirely in 3 of 8 runs, Arm F in 0 of 16.

This replicated on a second fixture **before** being written down, which the two
retracted claims did not.

## Round 5: the rubric was too small, and round 4's headline was wrong

Round 4's rubric came from R54's own text, so the arm holding R54 was scored
against the document it had been handed. Round 5 fixed that: ten agents, five per
defect variant, given only the defective code and asked to enumerate every
property a correct fix must have. None saw the rule set; each had the whole task
to itself. Full method and result: `evals/rule-ablation/independent-rubric.md`.

**The good news for round 4.** Its three clauses — scoped construct, restore on
the error path, test the next write in the same context — were all required by a
panel that had never read R54. They are not an artifact of self-scoring.

**The bad news.** The panel demanded **six more**, unanimously, and R54 taught
none of them: restore the *previous* value rather than a hardcoded off; **await**
the covered work before restoring; do not mutate caller-shared state; abort if
the restore itself fails; test the throw path; test nesting or concurrency.

One panellist named the consequence precisely: **a naive `try/finally` on the
shared object passes the return-path and throw-path tests and fails only the
concurrency one.** The two tests R54 asks for certify exactly the wrong fix.

So round 4's headline was wrong in the direction I had not guarded against. Not
"the rules produce a complete fix and their absence does not", but:

> Carrying the rules reliably produces **the three properties the rule contains**.
> A correct fix needs about nine. **Neither arm produced those.**

R54 has been extended with the six (`skills/triangulate/rule-details/R54.md`).
That extension is a fold made under this eval's own standard — direct evidence
that sixteen reviewers holding the rule still fixed it wrong — and it is owed its
own ablation before anyone claims it works.

The blinded re-score of the 32 round-4 fixes against the nine-property rubric is
set up (`evals/rule-ablation/score/rubric.md`) and **not run**. Scoring them by
hand would reintroduce the bias round 5 exists to remove.

## Other limits

- Fixtures were authored by someone who knew the target rule. That bias runs
  toward legibility, which makes a null the weaker reading and a positive the
  stronger one.
- One rule (R54), two fixtures. Nothing here generalises to the other 73.
- Long-context conditions and later rounds of a fix loop are still untested.

## Scoring note

Oracles were fixed in writing before each run. Four detection trials named an
adjacent R54 clause — the GUC is unregistered, so the authority is a convention —
without naming the leak past the call, and are scored misses.

## What follows

1. **Run the blinded re-score.** The rubric is checked in; the 32 round-4 fixes
   need arm identity stripped and scoring by agents that do not know which arm
   wrote what. That quantifies how far short of nine each arm actually falls.
2. **Ablate the R54 extension.** It was added on this eval's own standard, which
   makes it the first fold here with real evidence behind it — and the standard
   applies to it too.
3. **Run the independent-panel step for a second rule.** If R51 and R38 are also
   missing half of what a panel demands, the finding is about the rule set rather
   than about R54.
4. **Do not shrink rows to digest names.** Arm B measured exactly that and scored
   identically to carrying nothing.
5. **Report n, and replicate before writing.** Three claims from this eval have
   now been corrected by the round that followed them.
