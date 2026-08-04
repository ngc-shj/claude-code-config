# Rule ablation, round 1 — 2026-08-04

38 review runs measuring whether the triangulate rule set changes what a review
finds. Protocol and fixtures: `evals/rule-ablation/`.

## Why

Anthropic removed over 80% of Claude Code's system prompt for the Claude 5
generation with no measurable loss on their coding evaluations. The
context-engineering guidance that came with it names "exhaustive rule catalogs"
and "comprehensive upfront context loading" as anti-patterns, and replaces rules
with judgement wherever the model can carry it.

The comparison that matters is not the 80%. It is that **they knew deletion was
safe because they had evaluations.** This repo had 74 rules and none. Every rule
was added on the theory that a review missed something because the rule was not
written down; the counterfactual was never run.

That is the same defect this rule set already names one level down — writing a
convention is not installing its inspector — applied to the rule set itself.

## Experiment 1 — single-file fixtures, two arms

Arm A: the target rule's full procedure, alone. Arm C: no catalogue. Arm A alone
is the condition most favourable to the rule; the real skill loads 74 at once.

| Fixture | Arm A (rule) | Arm C (nothing) |
|---|---|---|
| F1 / R44 | 2/2 · Critical · #1 | **3/3 · Critical · #1** |
| F2 / R56 | 2/2 · Critical · #1 | **3/3 · Critical · #1** |
| F3 / RT8 | 2/2 · Critical · #1 | **3/3 · Major · #2–#4** |
| F4 / R54 | 2/2 · Critical · #1 | **3/3 · Critical #1 ×2, Major #3 ×1** |

Detection: **12/12 without the rule.** The rule changed detection in zero
trials. It changed severity consistently for RT8 only.

Suggestive, small-n, and worth naming because it is a *cost* rather than a null:
the no-catalogue arm was consistently **broader**. Findings only it produced —
a `vi.mock` factory closing over variables declared after the hoisted call, so
the suite dies at collection (2/3 vs 0/2); Prisma's 5-second interactive
transaction default (3/3 vs 0/2); a `GROUP BY` that drops a tenant whose rows
were all just deleted, so the counter row vanishes rather than reading zero
(3/3 vs 0/2). The arm holding the rule stayed near the rule.

## Experiment 2 — multi-file fixtures, three arms

The condition the catalogue was built for: 8 files, 280–425 lines, the target
defect outside the file the change is nominally about. Arm B added: the pattern
name without the procedure — what shrinking a row to its digest line buys.

| Fixture | Arm A (full) | Arm B (name only) | Arm C (nothing) |
|---|---|---|---|
| F5 / RT9 | 3/3 · Critical · #1 | 3/3 · Critical · #1 | 3/3 · Critical · #1 |
| F6 / R54 | **3/3 · Critical · #1** | **2/3** | 3/3 · **Major · #4–#7** |

### F5 is the weak fixture

No difference anywhere. But both files carry a comment naming the twin
relationship (`Typed twin of content/sanitize.js`, `Keep in sync with
src/sanitize.ts`), which is realistic and also the strongest possible cue. A
harder fixture leaves the pairing discoverable only by reading the manifest
against the test imports. F5's null is not evidence about RT9; it is evidence
about F5.

### F6 is where a rule finally earned something

Without the catalogue the defect was still found 3/3 — as **Major, ranked 4th to
7th of sixteen findings**, and in one run stated conditionally ("any missing
`tenantId` filter added later would silently read all tenants") rather than as
the live leak it is. With the full procedure: Critical, rank 1, three times out
of three.

The contribution is **not detection. It is prioritisation and consistency.**
That is a real effect with real value — the fix loop treats "Critical, must fix
immediately" and "Major at position 6" differently, and a 10-round loop is
exactly where a mis-ranked finding gets deferred — but it is a far smaller claim
than the one the catalogue's growth has implicitly rested on.

### The result that changes a decision

**Arm B, the name-only arm, was the worst of the three.** 2/3 detection, and the
sole miss in 30 scored trials. Arm C, with no catalogue at all, went 3/3.

n=3, so this is a signal and not a finding. But it has a mechanism: a bare
pattern name announces that a class exists without conveying its failure mode,
so it can consume attention while supplying nothing to reason with — worse than
silence, which at least leaves the reviewer's own judgement unobstructed.

If it replicates it argues directly **against** shrinking rule rows toward their
digest names, which was the shape the bloat work was heading for. Replicating it
is the first thing the next round should do.

## Scoring note

Oracles were fixed in writing before any run. One Arm-B trial on F6 named the
adjacent R54 clause (an unregistered GUC any principal can set, so the authority
is a convention) without naming the leak past the call, and is scored a miss.
Scoring it a hit would have been fitting the oracle to the data.

## Limits

- Fixtures were authored by someone who knew the target rule. Noise (5–15 other
  genuine defects each, several of them Critical) does not remove that bias. A
  null result therefore means "adds nothing on a fixture I wrote"; a positive
  result is the stronger reading, since the bias runs the other way.
- 6 rules of 74. Three arms × three trials is enough to see a gradient, not
  enough to size one.
- Not tested: long-context conditions, later rounds of a loop, and the real
  configuration in which all 74 rules compete for attention at once. Arm A gave
  one rule with nothing else competing, so the live setting is *worse* for the
  rules than anything measured here.

## What follows

1. Replicate the Arm-B result. It is the one that would change what gets built.
2. Build a harder RT9 fixture with the twin relationship undocumented.
3. Do not delete mined rules on this evidence. What it supports is demoting
   rules whose only measured contribution is severity to a severity cue — a
   fraction of the bytes of a full procedure — and only for rules that have been
   ablated, one at a time.
4. Ablate before folding. A new rule should arrive with the run that shows the
   finding disappears without it, the same obligation the hooks already carry.
