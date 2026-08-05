# Expert specialisation vs repetition — 2026-08-05

Rounds 1–9 varied the rule catalogue and nothing else. This round varies the
skill's **structure**: the three-expert split, which is the dominant cost of a
review round — three agents plus a merge, repeated per round — and had never
been a variable.

Protocol, pre-registered: `evals/rule-ablation/protocols/round-10.md`.
Scores: `evals/rule-ablation/scores/`, reproducible with `score.py --round 10`.

## The confound this design removes

"Three experts versus one reviewer" measures multiplicity, and multiplicity wins
trivially. Both arms therefore run **three agents** on the same fixture with the
same materials, and differ only in the prompts:

- **S** — the three specialised experts as phase-3 defines them (Senior Software
  Engineer / Security Engineer / QA Engineer, each with its own focus and
  exclusions).
- **G** — three identical general reviewers. No role, no scope split.

The merge is the mechanical union of the three replies, identical in both arms.
No agent performed it: a merging agent could favour one arm's shape.

Fixture F3 (RT8, vacuous denial-path test), n=8 reviews per arm, 48 agents.
Scored blind against the round-6 merged panel rubric (11 properties) by three
agents, arm identity redacted — including the `[Adjacent]` routing tag, which
only a scoped reviewer emits and would otherwise have named the arm outright.

## Result: null, with the point estimate running the wrong way

| arm | merged-rubric coverage |
|---|---|
| **G** (three identical generalists) | **6.50** / 11 |
| **S** (three specialised experts) | 6.25 / 11 |

n=8 per arm. Detection saturated: all sixteen reviews named the target defect.
Scorer agreement 93.2–97.2%.

Per-property, the two arms are the same shape:

| | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | Q8 | Q9 | Q10 | Q11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| G | 8/8 | 8/8 | 8/8 | 1/8 | 8/8 | 8/8 | 0/8 | 3/8 | 8/8 | 0/8 | 0/8 |
| S | 8/8 | 8/8 | 8/8 | 0/8 | 8/8 | 8/8 | 0/8 | 2/8 | 8/8 | 0/8 | 0/8 |

**The properties each arm misses are the same properties.** Q7 (await the
handler before asserting), Q10 (order-independence), Q11 (suite green with
mutations reverted) are absent from all sixteen reviews in both arms.

## What this joins

Rounds 8 and 9 established that a rule transmits exactly what it states, at full
rate. Round 10 adds the other half: **who reads it does not matter.** Routing is
decided by matching the diff against pattern names in the digest, so a security
reviewer and a testing reviewer both arrive at the same row and read the same
procedure. Specialisation changes which reviewer files the finding, not what the
finding says.

Taken together, the skill's output on a defect is close to a function of the
rule text alone.

## What this does not settle

The pre-registration named these, and the null does not touch them:

- **Disagreement.** Nothing here measures what happens when two experts reach
  different conclusions, which is a state the general arm cannot enter in the
  same way.
- **The `[Adjacent]` routing itself.** Redacting it was necessary to blind the
  scorer, which means the mechanism specialisation actually exhibits — deferring
  out-of-scope findings to a named owner — was removed before scoring.
- **Multi-round convergence and escalation.** One review, one round.
- **One fixture.** The protocol said to replicate on F9 only if a difference
  appeared. None did, so this is a single-fixture null: strong enough to rule
  out a large effect on this defect, not a small one.

A null here means "specialisation did not change what one review produced on
this defect, at equal compute". It does not mean the split is worthless.

## What follows

1. **Replicate on a security-flavoured fixture** (F9) before acting. A null that
   holds where the security expert should have the advantage is a much stronger
   statement than a null on a testing-flavoured defect.
2. **If it replicates, the cheapest form of this skill is N general reviewers**,
   with N a budget knob rather than a fixed three — a larger structural change
   than any rule edit this eval has produced.
3. **Measure the parts this could not**: disagreement resolution, `[Adjacent]`
   routing, and whether round 2 of a fix loop behaves differently from round 1.
