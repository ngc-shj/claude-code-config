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
| median firing rate | **0.40%** of the reviews where the rule existed |
| rules firing in under 1% of their opportunities | **49 of 74** |
| highest count among mature rules | R3 — 37 findings / 1026 opportunities (3.61%) |

The routing protocol is being followed — RT1 was cited in 628 of its 1026
opportunities, R3 in 582 — so the low rates are not reviewers skipping the
check. They are reviewers running the check and finding nothing.

Top by findings produced:

| rule | fire% | findings | checked | opportunities |
|---|---|---|---|---|
| R3 | 3.61 | 37 | 565 | 1026 |
| R2 | 2.83 | 29 | 434 | 1026 |
| RT1 | 2.83 | 29 | 568 | 1026 |
| RT5 | 3.38 | 23 | 316 | 680 |
| R19 | 2.24 | 23 | 384 | 1026 |
| R1 | 2.24 | 23 | 469 | 1026 |
| RT7 | 4.68 | 21 | 235 | 449 |

## Correction, same day: the first numbers were inflated

The first run of this tool matched rule IDs with a plain `\b` anchor on both
sides. A hyphen is a word boundary, so every requirement ID these repositories
use — `NF-R2`, `F-R5`, `Func-R2`, `T-R2` — scored as a rule citation, and both
endpoints of every range reference (`R1-R35`, `RS1-RS3`, `RT1-RT5`) scored too.

It surfaced within the hour, and only because the next step began by reading
the actual findings the tool had pointed at: R1's supposed hits turned out to
be `NF-R1` requirement references and `R1-R13` spans. The pattern now rejects a
preceding word character or hyphen, and rejects a trailing hyphen followed by
another rule ID, while still admitting `R2-F1`-style finding IDs.

What moved: R2 from 55 findings to **29**, R3 from 51 to **37**, R1 from 28 to
**23** — and the top rank changed hands from R2 to R3. Every table above is the
corrected run.

What did not move: **the eight dead rules, all eight, unchanged.** A false
positive can only add a finding, so a rule sitting at zero was never at risk
from this bug. The deletion-candidate list is the one part of the first run
that was safe by construction.

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

1. **Panel-audit where the firing is**, not alphabetically: R3, R2, RT1, RT5,
   R19, R1, RT7 account for the bulk of findings and are where a missing clause
   costs the most. That is seven defect sketches, not seventy-four. Note that
   RT1 and R1 are one-sentence rules carrying 29 and 23 findings apiece —
   rounds 8–9 showed a rule transmits exactly what it states, so a rule this
   short firing this often is the sharpest gap the catalogue has.
2. **Decide the eight deliberately.** The honest options are delete, demote to
   a non-routed appendix, or keep and accept the routing cost — and the
   self-fulfilling-demotion trap means the choice should be made once, on the
   record, rather than drifting.
3. **Re-run this before folding anything new.** It costs one command, and a
   rule folded into a catalogue whose median row fires twice a year should have
   to clear a higher bar than "a reviewer once missed this".
