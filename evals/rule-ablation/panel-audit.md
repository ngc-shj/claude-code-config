# Panel audit — what the other rules are missing

Round 5 audited R54 by asking a panel that had never seen it what a correct fix
must satisfy, and found the rule carried three of the nine properties the panel
demanded. This is the same method applied to four more rules, to settle whether
that deficit was R54's or the catalogue's.

## Method

Sixteen agents, four per rule. Each was given only the defective code and a
neutral statement of what is wrong, and asked to enumerate every property a
correct fix must have. None saw the rule set. None was reviewing anything — each
had the whole task to itself, so the results are not attention artifacts.

Rules: **R44** (gate exit status through a lossy channel), **RT8** (vacuous
denial-path test), **R56** (progress-marker heal direction), **RT9** (twin
drift). Fixtures: `fixtures/F1-R44.diff`, `F3-RT8.diff`, `F2-R56.diff`,
`F8-RT9hard.diff`.

## Result

| Rule | Properties the panel required | Present in the rule |
|---|---|---|
| R44 | ~13 | 2 |
| RT8 | ~11 | 2 |
| R56 | ~15 | 5 |
| RT9 | ~14 | 5 |
| R54 (round 5) | 9 | 3 |

**The deficit is the catalogue's, not R54's.** Each rule carries roughly a
quarter to a third of what an unhurried panel requires for the very defect it
names.

## The finding that matters

The missing properties are not new knowledge. **Most of them are already in this
catalogue — in a rule the reviewer did not route to.** The same five classes were
absent from all four rules, and all five exist elsewhere:

| Missing from every rule audited | Already stated in |
|---|---|
| the allow-side case that must still succeed | RT10 |
| red-proof, executed, one mutation per clause | RT7 |
| fail loudly when the check cannot run at all | R50 clause ii |
| do not fix by deleting the useful behaviour | R36's shape |
| which side of the boundary, and what happens on a tie | R57 |

So the rules do not fail because the knowledge is absent. They fail because each
one is written as though its reader will also apply the other seventy-three, and
in practice the reviewer applies the one they routed to.

Sharpest single instance: **RT8 — the rule whose entire subject is "your test is
vacuous" — prescribes a vacuous remedy.** Its `expect(spy).not.toHaveBeenCalled()`
passes unconditionally when the mock wiring is broken, and RT8 never asks for the
positive control that would catch it. All four panellists did.

## What was done about it

`skills/triangulate/common-rules.md` gains a **Remedy Floor**: the five clauses,
stated once, inherited by every rule's `Fix:`. Five paragraphs rather than five
paragraphs times seventy-four — the total prose goes *down* while what each rule
transmits goes up.

That is a fold made under this eval's own standard: direct evidence, on four
rules and sixteen panels, that reviewers routed to a rule fix the defect
incompletely in a way the rule does not warn about.

## Owed — paid (round 7, 2026-08-05)

The Remedy Floor's ablation ran under the standard this file set, with one
finding this file did not anticipate: **as merged, the floor was unreachable** —
a section no routing path names, and a probe showed zero of four deployed-arm
reviewers read it. Wired (one digest line), reviewers carrying it produced the
floor's clauses and reviewers without it did not, on both fixtures, with the
mechanism control flat: floor-mapped subset 6.75 vs 5.12 on F1 (R44) and 3.88
vs 0.25 on F3 (RT8), n=8 per cell, blind-scored against this file's merged
panel rubrics. The wiring line now ships in the digest. Full protocol and
tables: the audit doc, round 7.
