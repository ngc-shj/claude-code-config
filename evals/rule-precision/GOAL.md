# The goal, and the rule that decides it

This is the single source for both. `packet-compiler/protocol.md`, the live one,
points here and states nothing itself. The two closed protocols — `routing-trim/`
and `request-batching/`, both refuted — still carry an inline five-clause form,
which is the rule their gates actually ran under and is left as their record;
**it is superseded, and where it differs from this file, this file counts.**

## The goal

> Adopt a skill change that **keeps real-claim reach practically intact**, does not
> worsen false positives, and reduces the tokens a unit of review quality costs —
> demonstrated on **forward data**, not on a replay.

Nothing short of that is arrival. A gate that a candidate survives has not reached
it; a gate that refutes a candidate has only saved the cost of finding out later.

## The rule that decides it, lexicographic — not scalarised

1. **zero loss of Critical real claims;**
2. distinct real claims reached ≥ **95%** of current k=3;
3. C/M not-a-defect no worse;
4. **raw processed tokens below current k=3** — the goal is to reduce what a
   review costs, and a candidate that passes 1–3 while costing more than the
   configuration it replaces has not done that;
5. among the candidates passing 1–4, **minimum raw processed tokens**;
6. api-eq is a secondary readout only.

Clause 4 is what makes this a reduction rather than a tournament: without it, the
cheapest of several candidates wins even if every one of them is dearer than what
is running today.

**A 20% token reduction is not part of this rule.** It is the threshold for
*investing* in a candidate at all — the bar the cheap gates use to stop work
early. Clearing it decides nothing about adoption.

## "Practically intact" is a margin, and the margin is stated

Clause 2 concedes a bounded loss, and the concession is real rather than
rhetorical. On F11, round 22, measured over the pinned sheet:

| | |
|---|---|
| **current k=3** — arm W, the control | **20.28** distinct real claims per review |
| a 95% floor of that | **1.014 claims per review** |
| pooled sd plug-in, unpaired | 1.752 |

Arm W23 reaches 21.48, but it is the arm with clause 1 removed, not the current
configuration; averaging the two would set the floor against something nobody
runs. The control is W.

So the rule permits a candidate that loses **about one claim per review** and pays
for it in tokens. It forbids losing a Critical one at any price, and it forbids
trading quality for tokens beyond that margin — clauses 4 and 5 constrain and then
minimise tokens *subject to* 1–3, they do not divide by them.

### Why not a literal 100%

An earlier statement of the goal said "equal or better", which reads as ≥100% and
does not match clause 2. Reconciled on 2026-08-20 in favour of the margin. The
reason is not that a zero margin is unplannable in general — it is that **a finite
margin is what lets quality maintenance be verified under a neutral candidate**,
and a rule has to be sized for the case where the candidate changes nothing:

| floor | margin vs W | n per arm | agents |
|---|---|---|---|
| 95% | 1.014 claims | 37 | **222** |
| 97.5% | 0.507 claims | 148 | 888 |
| 99% | 0.203 claims | 923 | 5,538 |
| 100%, with confidence | 0 | unbounded **under this θ=0 assumption** | — |

(One-sided α=0.05, power 0.8, plug-in on the observed sd. `routing-trim/protocol.md`
records a more conservative n ≈ 49 per arm — 294 agents — for the same floor, and
notes that variance uncertainty raises it further. These are **sizing figures
only**. Whether any of them is worth spending is not settled here: the
review-efficiency audit prices a run of that order at ≈124M raw / 86.7M api-eq,
and the design audit has already recorded a decision not to spend it once. What
this table establishes is the ratio — a tighter floor costs four times and then
twenty-five times the sample, and no n sizes a zero margin under that assumption.)

**θ=0 is a planning assumption this table chose, not a property of
non-inferiority.** It is the neutral case — the candidate changes nothing — and it
is the case an adoption rule has to survive, because a rule that only works when
the candidate happens to be better is not a rule. Sized at θ=0, the n needed to
put a confidence bound above a margin of **zero** with 80% power is unbounded.

Assume instead that the candidate is genuinely better, θ>0, and a zero margin is
perfectly plannable at a finite n. So the last row is not "impossible" and not
"unplannable" — it is **unbounded under the assumption this table makes**, and
that assumption is the one worth making.

Requiring instead that the *point estimate* not fall below control is applicable
at any n, but it cannot be **sized**: at θ=0 it succeeds about half the time and
raising n does not move that. It is a coin, not a test.

**Round 22's nominal pairing did not improve precision**, so it gives no basis for
sizing a future design as paired. Both arms review the same change at the same
index, which makes a paired analysis look free — but on that one round the
correlation between arms is **0.136** and the sd of the per-review difference
(2.309) exceeds the pooled sd (1.752). That is a single sample of 25 reviews, and
it supports only the sizing statement: it is not a finding about where review
variance comes from. A design that intends to pair has to establish its own
correlation first.

## Status, 2026-08-21 — stopped, unmet

Three candidates were priced on F11 and all three were refuted below the bar:

| candidate | what it changed | |
|---|---|---|
| `routing-trim/` | **what** the reviewer reads | 9.92–10.89% |
| `request-batching/` | **when** its own fetches arrive | 19.32–19.52% |
| `packet-compiler/` | **who** selects and fetches | 12.19–14.60% |

**Nothing was adopted, no forward test was run, and the goal above is unmet.** The
search on this fixture is closed — not paused pending a better idea, closed.

The reason they converge is measured rather than guessed: **54 of the 74 catalogue
rules were used by at least one agent and the mean agent used 18.2**. Reviewers do
not agree on what a change triggers, so material that satisfies all of them is most
of the catalogue and material small enough to save tokens satisfies none. And 93.6%
of raw tokens is the same content re-sent, which the three candidates between them
have now attacked from every side that costs nothing to try.

**Do not open a fourth candidate to keep the line moving.** Work resumes only when
a specific intervention can, from data already in hand, do all three of:

1. show headroom above 20% **before** it is built;
2. explain the mechanism by which coverage is preserved;
3. be refuted cheaply by a 0-agent gate.

Absent that, running nothing is what the goal asks for: it is the option with the
lowest tokens and no loss of review quality.

## What this file does not settle

- The forward test's design beyond its floor and its endpoint. None was written.
- Anything about a second fixture: every figure here is F11 unless stated. Whether
  the agreement problem above is a property of F11 or of reviewing is not known,
  and finding out is not free.
