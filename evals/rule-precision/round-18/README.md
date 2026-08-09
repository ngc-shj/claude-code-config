# Round 18 — the Finding Floor is not reducible to its second clause

Pre-registration: `../../rule-ablation/protocols/round-18.md`, including why the
comparator is N rather than W, and the power gate stated as a quantity.

```bash
evals/rule-precision/round-18/measure.py --gate   # the gate: sd and MDE, no arm mean
evals/rule-precision/round-18/measure.py          # the table
```

Round 17's post-hoc split put the whole of the floor's effect in one verdict
class and showed the residual it leaves is the same shape as the effect it
removes — a requirement resting on code the change does not contain, which is
clause 2's target. This asks whether clause 2 is therefore the section.

| | W₂ (clause 2 alone) | N (no floor) | difference | t | MDE@80% |
|---|---|---|---|---|---|
| **PRIMARY** C+M `not-a-defect` | 3.33 | 4.33 | −1.00 | −1.20 | **2.55** |
| SECONDARY C+M `wrong` | 0.33 | 0.83 | −0.50 | −1.10 | 1.39 |
| composite, rounds 12/17's primary | 3.67 | 5.17 | −1.50 | −1.41 | 3.28 |
| **CONTROL** distinct real defects | 36.17 | 34.83 | +1.34 | +0.60 | 6.81 |

n=6 reviews per arm, 3 identical generalists each, 36 agents, 1027 findings.

**The pre-registered decision rule does not fire.** The primary moves by −1.00
against an MDE of 2.55, and the round was powered for 2.67 — the effect the full
three-clause floor produced on this fixture. So an effect of the section's size
is **not** present in clause 2 alone.

Per the pre-registration, that is the answer in the direction the round could
answer it: **clauses 1 and 3 stay.** The evidence does not support deleting
them, and this round never could have licensed deleting clause 2 either — see
the protocol's rejection of the W-versus-W₂ design.

## What this does NOT say

**Not that clause 2 does nothing.** −1.00 sits inside the MDE; the round is blind
to an effect that size. What is ruled out is clause 2 carrying the *whole*
section, which is what a deletion of the other two would have required.

**Not a comparison against round 17's W arm.** W₂'s 3.33 against round 17's
1.22 is the arithmetic a reader will want, and round 9's rule forbids it: those
are different batches, and an arm measured against a stored number from another
batch is the failure that rule exists to prevent. N was re-run here for exactly
that reason, and N's own level (4.33 here, 3.89 there) is the only evidence that
the two batches are comparable at all.

## The gate held, and no deviation was needed

Observed pooled sd on the primary **1.438**, giving an MDE of **2.55** against
the pre-registered ceiling of 2.67. Round 17's variance ceiling was stated as an
sd multiplier and became ambiguous the moment n changed; stating it as the
quantity it encodes — "MDE ≤ the effect being tested" — left nothing to
interpret. The gate was run alone, before any arm mean existed.

## The pre-registered split earned its place independent of the result

The same 36 reviews, scored two ways:

| metric | difference | MDE |
|---|---|---|
| composite (rounds 12 and 17's primary) | −1.50 | 3.28 |
| `not-a-defect` only (this round's primary) | −1.00 | **2.55** |

The split is a **22% tighter instrument on identical data**, because it stops
counting a verdict class the intervention does not act on. Both readings are
null here, so nothing rests on the choice this time — which is the cheapest
possible round in which to have made it.

## Clause 2 was read, applied, and visible in the output

The reachability gate ran first: **3 of 3** agents executed
`awk '/^### Finding Floor/,/^### Remedy Floor/'`, verified at the `tool_use`
level rather than by substring — the digest quotes that command as an
instruction, so a transcript-wide grep also matches the agent that merely read
about it.

And clause 2 left a signature in the reviews themselves. It instructs that an
ungrounded requirement be recorded as Minor and phrased as a question, and
W₂ reviewers invented a heading the brief's template does not contain:

```
### Minor (question, per Finding Floor): does `session_scope` commit on exit?
### Minor (question — not grounded in the diff): rate limiting on the new routes
```

**13 question-phrased findings in W₂, 0 in N.** The extraction step first
dropped these, because the round-17 heading regex did not admit a parenthetical
between the severity and the colon — and every one of them was in one arm. The
regex was widened and all 1027 findings parse; had it not been, the arm that
obeys clause 2 would have been the arm silently missing findings.

So the null is not a reachability failure and not a compliance failure. The
clause was read, obeyed, and visible — and on its own it still does not move the
primary by the section's worth.

## The inventory, and how far F10 has converged

| | claims | real |
|---|---|---|
| carried in (rounds 16 and 17) | 94 | 64 |
| + round 18, from 1027 findings | +9 | **+0** |
| **total** | **103** | **64** |

**1027 findings produced 9 new claims and not one new real defect.** Round 17
saw 511 → 5; this is the same convergence at twice the volume. F10's real set
has been stable for two rounds.

Adjudicator pairwise agreement on the 9: **100%, 100%, 100%**, no three-way
split — against 83.3–93.3% in round 17 and 84.3–94.0% across rounds 11–15. Nine
claims is a small denominator and unanimity on it is weaker evidence than the
percentage looks.

Verdicts for the 94 carried-in claims are unchanged, and no clustering agent
reworded one — checked mechanically over all 87 cluster rows, 0 violations,
1027 findings assigned exactly once with none dropped or duplicated.

## An agent reported a wrong result, not just an early one

Round 17's lesson was that an agent's `DONE` is not evidence its file exists.
This round found the sharper version: the `migrations` clustering agent fired
**two** completion notices, and **the first one was wrong** — it reported
clusters under ids (`MIG-01`, `NEWMIG-01`) that are not in the inventory at all,
described as `existing`. The file on disk when the dust settled was the second,
correct run.

Every clustering agent also *claimed* it had verified byte-for-byte copying and
full coverage. Those claims happened to be true. They were not what established
it: the mechanical check over the merged output was, and it is the only reason
this round can assert the append-only rule held.

**An agent's self-report of having verified something is not a verification.**

## Cost

| | agents | tokens |
|---|---|---|
| reachability gate | 3 | 0.28M |
| reviews, 6 × 2 arms × 3 | 36 | 3.15M |
| clustering, one per target file | 8 | 0.51M |
| adjudication | 3 | 0.11M |
| **total** | **50** | **≈4.0M** |

Against the protocol's estimate of 47 agents and ≈3.9M.

## What this does not settle

- **One model, one skill, one catalogue snapshot, one fixture.**
- **n=6 sizes for presence of a 2.67-sized effect, and nothing finer.** The
  round cannot tell a clause that contributes a third from one that contributes
  nothing.
- **Which of clauses 1 and 3 matters, or whether they matter jointly.** The
  design has one variable and this is not it.
- **Nothing here measures whether a proposed fix works.** The fixtures are
  diffs.
