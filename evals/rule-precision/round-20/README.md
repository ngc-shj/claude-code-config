# Round 20 — clause 1 carries the Finding Floor

Pre-registration: `../../rule-ablation/protocols/round-20.md`.
Power table: `../../rule-ablation/protocols/round-20-power.py`.

```bash
evals/rule-precision/round-20/measure.py --gate   # the gate, run first and alone
evals/rule-precision/round-20/measure.py
```

Round 19 measured clauses 1 and 3 contributing **−1.83 jointly** and could not
say which carried it. Four arms in one batch — a 2×2 in (clause 1) × (clause 3),
clause 2 always present — identify each.

| C+M findings whose claim is `not-a-defect`, per review | W | W₁₂ | W₂₃ | W₂ |
|---|---|---|---|---|
| clauses present | 1,2,3 | 1,2 | 2,3 | 2 |
| mean | 1.78 | 1.44 | **3.11** | **3.33** |

| paired comparison | difference | sd_d | t | 95% CI |
|---|---|---|---|---|
| **CONFIRMATORY** W − W₂₃ — clause 1 | **−1.33** | 1.225 | **−3.27** | **[−2.27, −0.39]** |
| exploratory W − W₁₂ — clause 3 | +0.33 | 1.581 | 0.63 | [−0.88, +1.55] |
| exploratory W₁₂ − W₂ — clause 1 | −1.89 | 1.833 | −3.09 | [−3.30, −0.48] |
| exploratory W₂₃ − W₂ — clause 3 | −0.22 | 1.202 | −0.55 | [−1.15, +0.70] |
| exploratory 2×2 interaction | +0.56 | 2.297 | 0.73 | [−1.21, +2.32] |

n=9 per arm, 3 identical generalists each, 108 agents, 3129 findings. `t_crit`
at df=8 is 2.306.

## The confirmatory rule fires

**The 95% CI for W − W₂₃ lies entirely below zero.** Removing clause 1 from the
full section raises Critical/Major non-defects; clause 1 contributes.

The gate ran first and alone: observed sd of differences 1.225, MDE 1.29 against
the pre-registered ceiling of 1.83. The MDE gated the spend and did not judge
the result — the rule reads the interval, which is the separation
`../methods.md` records and round 19 is the worked example for.

## Every exploratory comparison points the same way

The design has two cells for each clause, and they agree:

| clause | with the other clause present | with it absent |
|---|---|---|
| **1** | W − W₂₃ = **−1.33**, CI [−2.27, −0.39] | W₁₂ − W₂ = **−1.89**, CI [−3.30, −0.48] |
| **3** | W − W₁₂ = +0.33, CI [−0.88, +1.55] | W₂₃ − W₂ = −0.22, CI [−1.15, +0.70] |

**Clause 1 shows an effect in both cells; clause 3's interval straddles zero in
both.** The interaction is +0.56, CI [−1.21, +2.32] — the two clauses do not
depend on each other, so the effect is clause 1's alone rather than a pairing.

Only W − W₂₃ was confirmatory. The other four are exploratory and are reported
with their numbers, neither discounted nor promoted.

## What this does NOT license

**It does not license deleting clause 3.** The protocol says so in its own
section and it is the thing these numbers will be misread as saying. This design
measures positive contributions; a null on clause 3 is not equivalence. Deleting
it needs a non-inferiority margin fixed before a run and an n computed for it,
and neither exists. What can be said is that on this fixture, at this n, clause
3's contribution is not distinguishable from zero while clause 1's is.

**No skill file is changed by this round.**

## The control is recorded and nothing is concluded from it

| distinct real defects reached | W | W₁₂ | W₂₃ | W₂ |
|---|---|---|---|---|
| mean | 35.67 | 36.44 | 36.89 | 35.22 |

Flat. Not called non-inferiority — that needs a margin fixed in advance, and
using an observed-variance quantity as the margin lets a noisier arm license a
larger real loss.

## The inventory

| | claims | real |
|---|---|---|
| carried in (rounds 16–19) | 114 | 69 |
| + round 20, from 3129 findings | +18 | +13 |
| **total** | **132** | **82** |

Adjudicator pairwise agreement on the 18: **94.4 / 94.4 / 100%**, no three-way
split.

**The docs granularity drifted again, and further.** Round 18's docs agent
folded 21 doc findings into existing claims; round 19's split 26 into five new
ones; this round's split 59 into **twelve**. Twelve of the eighteen new claims,
and most of the thirteen new `real` ones, are doc-versus-code claims separated
by which subset of documented behaviours each finding names. It is applied
identically to all four arms so it cannot bias the comparison, but **"real
claims reached" is not comparable across rounds** and the growth of the
inventory's `real` set from 69 to 82 is mostly this.

Verified mechanically over all 104 merged cluster rows: 3129 findings assigned
exactly once, none dropped or duplicated, **no existing claim reworded**, no
`existing` id absent from the inventory.

`../extract.py` was run over all 108 review files and **reproduced this round's
`findings.tsv` byte-for-byte**, so the extraction is not a step anyone has to
take on trust. The review files themselves are not checked in — no round keeps
them — and that check cannot be re-run from the repository alone; it was run
once, here, while they existed.

## What the round cost operationally, and what it changed

**Fourteen agents were lost to the five-hour rate limit**, part way through the
reviews, because 108 agents were launched without asking whether they fit. The
usage log had the numbers the whole time and was not consulted. Two tools came
out of it, and both are used by the rest of this round:

- `../preflight.py` — will this batch fit in the window? Its constant is not
  agents-times-a-rate: 108 review agents cost 13 weekly points, worth about 68
  five-hour points, and the window still ran out. The rest is the orchestrator
  re-sending its context every turn, which a long round makes the dominant term.
- `../await_outputs.py` — wait for outputs to exist **and stop changing**. The
  clustering agent for `delivery.py` fired `DONE` before its write landed, a
  single `ls` found nothing, and the work was relaunched needlessly; the file
  appeared a minute later, complete and correct. "Check the file on disk" was
  already the rule. It was not enough, because a check has a time and one check
  cannot tell "not yet" from "never".

Also recorded: the subagent concurrency cap is 20, and excess launches are
rejected rather than queued, which leaves an arm short until someone notices.
One review index at a time — four arms times three parts — and confirm all
twelve landed before starting the next.

## Cost

| | agents | ≈ tokens |
|---|---|---|
| reviews, 9 × 4 arms × 3 | 108 | 9.6M |
| reviews lost to the rate limit | 14 | 1.2M |
| clustering, one per target file | 10 | 1.0M |
| adjudication | 3 | 0.12M |
| **total** | **135** | **≈11.9M** |

Against the protocol's 119 agents and ≈10.4M. The overrun is the fourteen lost
reviews and the needless clustering rerun.

## What this does not settle

- **Whether clause 3 can be removed.** Measured contribution is not equivalence,
  and this design cannot become a non-inferiority one after the fact.
- **One model, one skill, one catalogue snapshot, one fixture.**
- **The pairing is nominal.** Every review in every arm receives an identical
  brief; there are no per-review preambles. Making it real is a change to the
  review condition and remains the obvious next fix.
- **Why clause 1 works is not measured here.** That it points at evidence inside
  the change is the protocol's prediction, not this round's finding.
- **No fixes are applied.** The fixtures are diffs.
