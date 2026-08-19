# The goal, and the rule that decides it

This is the single source for both. The protocols under `routing-trim/`,
`request-batching/` and `packet-compiler/` each restate the adoption rule inline;
where any of them differs from this file, **this file is the one that counts**.

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
4. among candidates passing 1–3, **minimum raw processed tokens**;
5. api-eq is a secondary readout only.

**A 20% token reduction is not part of this rule.** It is the threshold for
*investing* in a candidate at all — the bar the cheap gates use to stop work
early. Clearing it decides nothing about adoption.

## "Practically intact" is a margin, and the margin is stated

Clause 2 concedes a bounded loss, and the concession is real rather than
rhetorical. On F11, round 22, measured over the pinned sheet:

| | |
|---|---|
| distinct real claims per review | mean **20.88** (W 20.28, W23 21.48) |
| a 95% floor | **1.04 claims per review** |
| pooled sd, unpaired | 1.752 |

So the rule permits a candidate that loses **about one claim per review** and pays
for it in tokens. It forbids losing a Critical one at any price, and it forbids
trading quality for tokens beyond that margin — clause 4 minimises tokens
*subject to* 1–3, it does not divide by them.

### Why not a literal 100%

An earlier statement of the goal said "equal or better", which reads as ≥100% and
does not match clause 2. Reconciled on 2026-08-20 in favour of the margin, because
a literal reading is not a rule that can be met:

| floor | margin | n per arm | agents |
|---|---|---|---|
| 95% | 1.04 claims | 35 | **210** |
| 97.5% | 0.52 claims | 140 | 840 |
| 99% | 0.21 claims | 871 | 5,226 |
| 100%, with confidence | 0 | unbounded | unreachable |

(One-sided α=0.05, power 0.8, plug-in on the observed sd. `routing-trim/protocol.md`
records a more conservative n ≈ 49 per arm — 294 agents — for the same floor, and
notes that variance uncertainty raises it further. Either figure is affordable;
none of the tighter floors is.)

A non-inferiority margin of zero cannot be demonstrated at any finite n. Requiring
instead that the *point estimate* not fall below control is attainable, but a
candidate whose true effect is exactly zero fails it about half the time — the
test would then reject for reasons that have nothing to do with the intervention.

**Pairing does not rescue a tighter floor.** Both arms review the same change at
the same review index, so a paired design looks free — but the correlation between
arms on one review is **0.136**, and the sd of the per-review difference (2.309)
is *larger* than the pooled sd. Review difficulty is not what drives the variance;
reviewer-to-reviewer spread is. The measurement is in this file's history rather
than a script, because it is a design input and not a result.

## What this file does not settle

- Whether any candidate reaches the goal. Three have been priced; two are refuted
  and one is at Gate C1.
- The forward test's design beyond its floor and its endpoint.
- Anything about a second fixture: every figure here is F11 unless stated.
