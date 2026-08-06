# Expert specialisation vs repetition — 2026-08-05

Rounds 1–9 varied the rule catalogue and nothing else. These rounds vary the
skill's **structure**: the three-expert split, which is the dominant cost of a
review round — three agents plus a merge, repeated per round — and had never
been a variable. Round 10 measures it on a testing-flavoured defect, round 11
replicates on a security-flavoured one.

Protocols, pre-registered: `evals/rule-ablation/protocols/round-10.md` and
`round-11.md`. Scores: `evals/rule-ablation/scores/`, reproducible with
`score.py --round 10` and `--round 11`.

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

## Round 11: it replicates, on the fixture where the security expert should win

Protocol, pre-registered: `evals/rule-ablation/protocols/round-11.md`.
Reproducible with `score.py --round 11`.

F9 (R54, an audit-skip flag set on a request context and never cleared, so every
later write in the request bypasses the audit guard). Same design: three
specialised experts against three identical generalists, three agents each, same
HEAD materials, mechanical union, n=8 per arm, 48 agents. Both arms' prompts are
rendered from one template, so arm S differs only by the role line, the
scope/out-of-scope pair, and the `[Adjacent]` obligation.

**The instrument had to be rebuilt first.** F9's existing rubric — the round-5
nine — is saturated under HEAD materials (`score.py --round 9`: F9·Cnew is
9.00/9, every property 8/8), and a ceiling cannot show a difference in either
direction. A fresh four-panellist rubric was built by the round-5/6 method and
frozen before the first arm agent ran: 34 majority properties
(`evals/rule-ablation/score/F9-merged.md`), from a sketch of the defect
(`evals/rule-ablation/sketches/F9-audit-skip.md`).

| arm | untaught (primary) /12 | taught (control) /22 | total /34 |
|---|---|---|---|
| **G** (three identical generalists) | 7.38 | 17.50 | **24.88** |
| **S** (three specialised experts) | **7.75** | 17.12 | **24.88** |

n=8 per arm. Detection saturated: all sixteen reviews named the defect and
proposed a fix for it; no `no-fix`. Scorer agreement 87.7–94.7%.

The totals are equal to the second decimal place, and the two subsets differ by
less than four tenths of a point **in opposite directions** — S ahead on the
properties nothing teaches, G ahead on the properties everything teaches. Of the
34 properties, 21 are identical between arms, 7 differ by one to three reviews
out of eight, and 6 sit at zero in both.

Round 10 found the null where the QA expert was on home ground. Round 11 finds
it where the security expert is. **Two fixtures, two domains, no effect.**

### The pre-registered control condition was not met as written

The protocol said the taught subset should be *saturated* in both arms, and that
a cell short of ceiling means the arms differ in more than the prompt. It came
out 17.50 and 17.12 of 22.

The expectation was wrong rather than the arms. Four taught properties sit at
0/8 in **both** arms, and each has a legible reason:

- **Q24 (executed red-proof) and Q34 (full suite green)** are unreachable on
  this harness. A reviewer is handed a diff, not a repository; there is nothing
  to run. Round 7's corresponding property saturated because it was worded less
  strictly — this panel demands the observed failure output be shown. Do not
  read 0/8 as the Remedy Floor failing.
- **Q17 and Q21** are two of the borderline taggings the rubric file names.

What the control was *for* — detecting a difference between arms in
material-taught content — is satisfied: the taught subset is flat, 17.50 against
17.12, the same magnitude as the primary difference and in the other direction.
The comparison stands; the ceiling clause did not.

### What this round found that the null did not: a disjunction transmits its first branch only

The sharpest result here is not the arm comparison. The panel stated nesting and
concurrency as two properties where round 5 had stated one:

| | Q29 — a nesting test | Q30 — a concurrency test |
|---|---|---|
| G | 8/8 | **0/8** |
| S | 8/8 | **0/8** |

R54's obligation (f) reads *"test nesting **or** concurrent use"*. Sixteen
reviews out of sixteen took the first branch and none took the second.

That is the branch that matters. Round 5's panel named the consequence in so
many words: a naive save/restore **passes the return-path and throw-path tests
and fails only the concurrency one**. And it revises how round 8's headline
should be read — P9 went 16/16 with the extension, but P9 was itself worded as a
disjunction, so that 16/16 was carried entirely by nesting. Round 8 scored what
it defined; the property it certified is weaker than its name suggests.

Round 9 established the repair for exactly this shape: split the clause into
named variants and it saturates. **Splitting R54 (f) into two obligations is the
recommended next fold**, and under this eval's own standard it is owed its own
ablation before anyone claims it works.

### Breadth, recorded and not claimed

Findings per merged review, counted as finding headings before any dedup:

| arm | range | mean |
|---|---|---|
| G | 33–43 | 39.1 |
| S | 27–38 | 32.9 |

The generalist arm reports about six more findings per review. This is the
tertiary metric and it is not a claim: F9 has no adjudicated defect inventory,
more findings is not better if they are noise, and an arm with per-expert
exclusions reporting less is what exclusions are for. It is recorded because it
runs the same direction as round 10's point estimate.

### What round 11 still does not settle

Everything round 10 could not, unchanged: disagreement between experts, the
`[Adjacent]` routing (redacted to make scoring blind), escalation, multi-round
convergence, and the authoring pathway. One further limit is specific to this
design — arm S's three parts are role-partitioned, so their *shape* differs from
arm G's three even after every role word is stripped. No redaction removes that,
and a scorer could in principle infer the arm from it.

## Correction (2026-08-06): the null is real and the conclusion was too broad

Both tables above stand. What they license does not.

Rounds 10 and 11 scored **the remedy for one seeded defect**, and on that the
arms are genuinely identical. They never scored how many *other* real defects
each review reached — the round-11 pre-registration listed breadth as tertiary
and declined to claim it, because F9 had no adjudicated defect inventory.

One was then built, from this round's own material and with no new reviews:
574 findings → 83 distinct claims → three blind adjudicators, counts withheld.
39 claims are real. Against that inventory
(`2026-08-06-finding-precision.md`):

| | precision | real defects reached, of 39 | N=1 | N=2 | N=3 |
|---|---|---|---|---|---|
| G | **81.6%** | 16.8 | 10.5 | 14.2 (+3.7) | 16.8 (+2.5) |
| S | 73.5% | **19.1** | 8.1 | 14.4 (+6.3) | 19.1 (**+4.8**) |

Specialisation reaches more genuine defects and is less precise getting there,
and the split's real payoff is in **the marginal reviewer**: three generalists
keep rediscovering each other's defects, three specialists do not.

So the corrected statement is narrower than "specialisation buys nothing":
**it does not change the fix produced for the defect that was routed to; it does
change what else the review finds, and how much a second and third reviewer are
worth.** The "N general reviewers" conclusion below was drawn from a metric that
could not see the difference, and is withdrawn pending replication.

## What follows

1. **The replication is done and it holds — for what it measured.**
   Specialisation did not change the remedy one review produced, on a
   testing-flavoured defect or a security-flavoured one, at equal compute.
2. ~~**The cheapest form of this skill is therefore N general reviewers**~~ —
   withdrawn 2026-08-06, see the correction above. What is licensed is measuring
   the N curve, which has never been done: nothing chose three, and the
   specialised arm's third reviewer was still adding +4.8 real defects.
3. **Split R54's obligation (f).** A disjunctive clause transmits its first
   branch and drops the branch the round-5 panel said was the one that matters.
   Then ablate it, the way round 9 ablated its own rewording.
4. **Check the other disjunctive clauses.** (f) was found by accident, because a
   panel happened to split one property into two. Nothing has looked for the
   same shape elsewhere in the catalogue.
