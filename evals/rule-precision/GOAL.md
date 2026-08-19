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
does not match clause 2. Reconciled on 2026-08-20 in favour of the margin, because
a literal reading is not a rule a study can be **planned** to meet:

| floor | margin vs W | n per arm | agents |
|---|---|---|---|
| 95% | 1.014 claims | 37 | **222** |
| 97.5% | 0.507 claims | 148 | 888 |
| 99% | 0.203 claims | 923 | 5,538 |
| 100%, with confidence | 0 | unbounded **at θ=0** | not plannable |

(One-sided α=0.05, power 0.8, plug-in on the observed sd. `routing-trim/protocol.md`
records a more conservative n ≈ 49 per arm — 294 agents — for the same floor, and
notes that variance uncertainty raises it further. These are **sizing figures
only**. Whether any of them is worth spending is not settled here: the
review-efficiency audit prices a run of that order at ≈124M raw / 86.7M api-eq,
and the design audit has already recorded a decision not to spend it once. What
this table establishes is the ratio — a tighter floor costs four times and then
twenty-five times the sample, and a margin of zero cannot be planned for at all.)

**The last row is a statement about planning, not about possibility.** Every row
is sized under the assumption a non-inferiority design makes — that the true
difference is zero — and at that assumption the n needed to put a confidence bound
above a margin of zero with 80% power is unbounded. It does **not** say a zero
margin can never be shown: a candidate whose true effect is positive can produce
an interval clear of zero at a perfectly ordinary n. What cannot be done is
*commit in advance* to demonstrating it, which is what an adoption rule has to do.

Requiring instead that the *point estimate* not fall below control is plannable,
but a candidate whose true effect is exactly zero fails it about half the time —
the test would then reject for reasons that have nothing to do with the
intervention.

**Round 22's nominal pairing did not improve precision**, so it gives no basis for
sizing a future design as paired. Both arms review the same change at the same
index, which makes a paired analysis look free — but on that one round the
correlation between arms is **0.136** and the sd of the per-review difference
(2.309) exceeds the pooled sd (1.752). That is a single sample of 25 reviews, and
it supports only the sizing statement: it is not a finding about where review
variance comes from. A design that intends to pair has to establish its own
correlation first.

## What this file does not settle

- Whether any candidate reaches the goal. Three have been priced; two are refuted
  and one is at Gate C1.
- The forward test's design beyond its floor and its endpoint.
- Anything about a second fixture: every figure here is F11 unless stated.
