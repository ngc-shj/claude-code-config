# Rule firing frequency — 2026-08-05

1493 review artifacts from nine repositories, 2026-03-08 to 2026-08-04, asked a
question the ablation harness is too expensive to ask 74 times: **which rules
ever actually fire?**

Tool and limits: `evals/rule-firing/`. No fixtures, no agents — it reads
reviews that already existed.

## Why this came before more folding

Rounds 1–9 established what a rule buys when it fires: the literal clauses it
states, at full rate, and nothing else. That result is about *mechanism*, and
it is now settled well enough to act on. It says nothing about *which* rules
are worth stating clauses in.

Auditing all 74 rules the way rounds 5–6 audited five would cost roughly 300
agents and a defect sketch per rule. Before paying that, it is worth knowing
which rules have ever produced a finding — because the catalogue was built on
the theory that a review missed something *because the rule was not written
down*, and that theory has a cheap observational test.

## The catalogue is a long tail

| | |
|---|---|
| median firing rate | **0.50%** of the reviews where the rule existed |
| rules firing in under 1% of their opportunities | **48 of 74** |
| highest rate among mature rules | R2 at 5.36% (55 findings / 1026 opportunities) |

The routing protocol is being followed — RT1 was cited in 628 of its 1026
opportunities, R3 in 582 — so the low rates are not reviewers skipping the
check. They are reviewers running the check and finding nothing.

Top by findings produced:

| rule | fire% | findings | checked | opportunities |
|---|---|---|---|---|
| R2 | 5.36 | 55 | 486 | 1026 |
| R3 | 4.97 | 51 | 582 | 1026 |
| RT1 | 2.83 | 29 | 628 | 1026 |
| R1 | 2.73 | 28 | 579 | 1026 |
| RT5 | 3.38 | 23 | 333 | 680 |
| R19 | 2.24 | 23 | 387 | 1026 |
| RT7 | 4.68 | 21 | 244 | 449 |

## Eight rules have never fired, with every chance to

Zero findings across every review that postdates them, each checked in the
Recurring Issue Check dozens to hundreds of times, in six repositories:

| rule | added | opportunities | checked | findings |
|---|---|---|---|---|
| R10 Circular module dependency | 2026-04-23 | 1026 | 270 | **0** |
| R8 UI pattern inconsistency | 2026-04-23 | 1026 | 262 | **0** |
| R16 Dev/CI environment parity | 2026-04-23 | 1026 | 247 | **0** |
| R15 Hardcoded env values in migrations | 2026-04-23 | 1026 | 200 | **0** |
| RS5 | 2026-06-14 | 449 | 187 | **0** |
| R33 | 2026-04-29 | 977 | 166 | **0** |
| RS6 | 2026-07-04 | 297 | 100 | **0** |
| R40 | 2026-06-14 | 449 | 96 | **0** |

Spot-checked: every one of R10's 270 citations is a checklist line — `R10: N/A
— flat shell sourcing, no cycles`, `R10: checked, unidirectional` — and none is
a defect. The extraction was red-proved by mutation before these numbers were
written down (`tests/rule-firing.bats`).

Their cost is 6.8% of `common-rules.md` and **7.5% of the digest**, which is
the routing index every review reads.

## What this licenses, and what it does not

It licenses recording them as deletion candidates. It does **not** license
deleting them yet, for two reasons that are not rhetorical:

1. **Prophylaxis is invisible here.** Rules are read during implementation, not
   only review. A rule that stops the defect being written produces zero
   findings and looks exactly like a dead one. Rounds 1–3 did show the
   catalogue makes no measurable difference to *detection*, which removes the
   "safety net" argument — but the authoring pathway was never tested.
2. **Demotion is self-fulfilling.** A rule dropped from the digest can never be
   routed to, so it can never fire, so the measurement can never be revisited.
   Acting on this data forecloses re-measuring it, which is a one-way door and
   deserves to be walked through deliberately rather than as a side effect.

The corpus is also one person's repositories — mostly TypeScript/Next.js web
apps plus a Swift client and shell tooling. R10 dead here is evidence about
these codebases, not about circular dependencies.

## What follows

1. **Panel-audit where the firing is**, not alphabetically: R2, R3, RT1, R1,
   RT5, R19, RT7 account for the bulk of findings and are where a missing
   clause costs the most. That is seven defect sketches, not seventy-four.
2. **Decide the eight deliberately.** The honest options are delete, demote to
   a non-routed appendix, or keep and accept the routing cost — and the
   self-fulfilling-demotion trap means the choice should be made once, on the
   record, rather than drifting.
3. **Re-run this before folding anything new.** It costs one command, and a
   rule folded into a catalogue whose median row fires twice a year should have
   to clear a higher bar than "a reviewer once missed this".
