# Finding precision

`../rule-ablation/` asks whether a review's fix for **one seeded defect** has the
properties a correct fix needs. Eleven rounds of that measured remedy quality and
nothing else — and remedy quality on one defect is a small part of what a review
is for.

This asks the two questions that gate everything downstream:

- **Are the findings accurate?** A finding that is not a defect costs the person
  fixing it exactly as much attention as one that is, and buys nothing.
- **How many genuine defects does a review reach?** And what does the second and
  third reviewer add — real defects, or more of the same?

```bash
evals/rule-precision/measure.py
```

## Method

The material is round 11's, reused: 48 review replies over one fixture, eight
reviews per arm, three replies each (`../rule-ablation/protocols/round-11.md`).
No new reviews were generated, so nothing here depends on a second batch.

1. **Extract.** Every finding heading with its file and its one-sentence claim —
   574 findings.
2. **Cluster.** Eight agents, one per target file, group the findings into
   distinct claims: same cluster only when a single change resolves both AND
   they assert the same thing about the same code. 83 clusters, every finding in
   exactly one, none dropped. The clustering agents were told not to judge truth;
   a verdict from them would contaminate the panel.
3. **Adjudicate.** Three agents, each shown the diff and the 83 claims —
   **shuffled, with the member counts withheld**, so a claim forty reviewers made
   looks exactly like one that a single reviewer made. Popularity is not
   evidence. Majority vote per claim; agreement 84.3–94.0%.

`adjudication-brief.md` is the brief every round from 11 on has used, with the
three lines that vary per round (`{N}`, `{DIFF}`, `{CLAIMS}`) left as slots.
Holding it fixed is what lets a verdict recorded in one round mean the same thing
in the next; rendering it at each round's own counts and paths reproduces all
five instances byte-for-byte, and `round-16/README.md` lists their checksums.

Verdicts are `real` (accurate about the code and worth changing before merge),
`wrong` (misreads the code), and `not-a-defect` (accurate but a preference, out
of the change's scope, or resting on code the diff does not show).

**The standing assumption the panel was given** does most of the work and is the
first thing to argue with: judge the diff as a real pull request into a real
working codebase, where everything not shown — the ORM schema, the middleware,
the session layer, the rest of the suite — exists and is correct. Without it,
every "X is absent from the diff" scores as a defect and precision means
nothing. With it, some findings a human reviewer would value get scored
`not-a-defect`. It is applied identically to both arms, so it cannot bias the
comparison; it does move the absolute level.

## What it found

Full write-up: `docs/archive/audit/2026-08-06-finding-precision.md`.

| | precision | distinct real claims reached (of 39) |
|---|---|---|
| G — three identical generalists | **81.6%** | 16.8 |
| S — three specialised experts | 73.5% | **19.1** |

and the marginal reviewer, which is where the split actually pays:

| | N=1 | N=2 | N=3 |
|---|---|---|---|
| S | 8.1 | 14.4 (+6.3) | 19.1 (+4.8) |
| G | 10.5 | 14.2 (+3.7) | 16.8 (+2.5) |

One generalist beats one specialist, two are level, three specialists win — and
the specialists' third reviewer still adds nearly twice what the generalists'
does, because specialised replies overlap half as much (Jaccard 0.116 vs 0.246).

## Round 12: the first intervention aimed at precision

`round-12/` — the same instrument used as an outcome measure rather than a
diagnosis. A **Finding Floor** (three clauses inherited by every finding, wired
by one digest line) against HEAD, arms identical in every other shipped file,
n=8 reviews per arm.

| | W (floor) | N (HEAD) | t | MDE@80% |
|---|---|---|---|---|
| Critical/Major findings that are not defects | **1.62** | 4.12 | −4.11 | 1.83 |
| distinct real defects reached (control) | 16.50 | 16.88 | −0.59 | 1.93 |

```bash
evals/rule-precision/round-12/measure.py
```

Two things this reuse buys, and they are the reason to build an inventory once:

- **The standard is held fixed.** The 77 claims round 11 adjudicated keep their
  verdicts; only the 6 genuinely new claims were judged, by the same brief.
  Re-adjudicating the old ones would let the standard drift between arms and
  between rounds, which is the same failure the same-batch rule guards against.
- **The claim space converged.** 599 new findings produced only 6 claims the
  earlier round had not already recorded, which is evidence the inventory is
  near-complete for this fixture rather than an artifact of one sample.

Full write-up: `docs/archive/audit/2026-08-06-finding-floor.md`.

## Round 13: how many reviewers

`round-13/` — the same inventory used a third time, now as the scale on a
reviewer-count curve. Eight reviews of six identical generalists, sub-sampled to
six points from one batch.

| N | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| real defects | 10.8 | 14.3 | 16.4 | 17.9 | 19.1 | 20.0 |
| Critical/Major non-defects | 0.7 | 1.5 | 2.2 | 2.9 | 3.6 | 4.4 |

```bash
evals/rule-precision/round-13/measure.py
```

Coverage decays, cost is linear at +0.7 per reviewer, and **three specialised
experts reach what five identical generalists reach for 60% of the tokens**.

Two method notes worth carrying to any repeat: sub-sampling is unbiased **only
for identical reviewers**, and the inventory is what makes a third round nearly
free — 591 findings produced 6 new claims, so almost all of the adjudication was
already paid for.

Full write-up: `docs/archive/audit/2026-08-06-reviewer-count.md`.

## Round 14: a second wave that is told what the first found

`round-14/` — the inventory used a fourth time, now to price conditioning. Both
arms sit on the same fixed base (round 13's first three reviewers); only arm C
sees it.

| | C (told) | I (blind) |
|---|---|---|
| real defects added | **6.62** | 4.62 |
| Critical/Major non-defects | 4.50 | **2.38** |
| restating a base claim | **1.12** | 28.88 |

```bash
evals/rule-precision/round-14/measure.py
```

Conditioning cuts restatement by 96% and spends the freed attention on more
ground, less accurately — **+43% real defects, +89% non-defects**. The
pre-registered rule clears on coverage and fails on cost, so the recorded output
is both numbers and no recommendation.

Full write-up: `docs/archive/audit/2026-08-06-conditioned-second-wave.md`.

## Round 15: is a titles-only base as good as the full one?

`round-15/` — three arms on the same fixed base. T (titles only) and C (the full
base) came out identical to two decimals on everything that matters, and round
14's cost penalty did not replicate. Six of the eight pre-registered reviews ran.
Numbers and both deviations: `round-15/README.md`.

## Round 16: a second fixture at last

`round-16/` — five conclusions rested on F9, so this round bought a second
fixture (`../rule-ablation/fixtures/F10-webhooks.diff`, Python/asyncio webhook
delivery, written by an agent blind to the arms) and a seed defect inventory on
it: 361 enumerated entries from five panellists, 93 claims, **64 kept at ≥3/5 and
adjudicated — 54 real**, adjudicator agreement 92.2–96.9%.

It was to test whether an explicit stopping sentence cuts the Critical/Major
non-defects conditioning adds. **It stopped at its own manipulation check after
2 of 10 reviews**: no reply in either arm ended in `No findings`, which the
protocol pre-registered as meaning the wording did not arrive.

| | replies | findings | per reply | `No findings` |
|---|---|---|---|---|
| base | 6 | 163 | 27.2 | 0 |
| T | 6 | 51 | 8.5 | 0 |
| TS | 6 | 40 | 6.7 | 0 |

TS wrote 21% fewer findings than T, which is **recorded and not claimed** — n=2,
no adjudication behind it. The eight remaining reviews and 5.4M tokens were not
spent. `../rule-ablation/protocols/round-16.md`, `round-16/README.md`.

## Round 17: the shipped Finding Floor, on the second fixture

`round-17/` — round 12 put the Finding Floor in the skill on F9 alone. This asks
whether it survives F10, a fixture nobody built for it.

| | W (floor) | N (removed) | t | MDE@80% |
|---|---|---|---|---|
| Critical/Major findings that are not defects | **2.44** | 4.56 | −3.05 | 2.05 |
| distinct real defects reached (control) | 33.78 | 34.78 | −1.01 | 2.94 |

```bash
evals/rule-precision/round-17/measure.py --variance   # the gate, run first and alone
evals/rule-precision/round-17/measure.py
```

**The direction and the size replicate** — round 12 measured 2.50 on F9 with a
flat control; this is 2.11, also flat. n=9 per arm, reached by a declared
deviation after the pre-registered variance check fired at n=6, because F9's sd
did not transfer. Three things a reader should carry: the sd gate is still
literally exceeded at n=9 and both readings are recorded; the extension was
authorised by someone who had already seen the n=6 table; and one reply was
found missing partway through, though the primary series turned out unaffected.
`round-17/README.md`.

## Round 19: all three levels in one batch

`round-19/` — rounds 17 and 18 left W, W₂ and N on three different rulers, and
round 9's rule blocked every comparison across them. This runs all three
together, paired by review, with one inferential comparison fixed in advance.

| C+M `not-a-defect`, per review | W | W₂ | N |
|---|---|---|---|
| mean | **1.67** | 3.50 | 3.67 |

| paired | difference | t | MDE |
|---|---|---|---|
| **PRIMARY** W − N | −2.00 | −2.93 | 2.33 |
| SECONDARY W − W₂ | −1.83 | −5.97 | 1.05 |
| RECORDED W₂ − N | −0.17 | −0.25 | 2.23 |

```bash
evals/rule-precision/round-19/measure.py --gate   # the gate, run first and alone
evals/rule-precision/round-19/measure.py
```

**The interval excludes zero** ([−3.76, −0.24]); the pre-registered rule
additionally required the difference to exceed the MDE, which it did not, so the
round recorded no confirmatory claim. That rule was wrong — an MDE is a design
quantity, not a significance threshold — and `methods.md` separates the two for
every protocol from round 20 on, rather than the correction being applied
retroactively here.

What the arms show: clause 2 alone is indistinguishable from no floor (−0.17,
CI [−1.85, +1.51]), and the whole measured gap sits between W and W₂ (−1.83,
CI [−2.62, −1.04], **exploratory**). **Which of clause 1 and clause 3 does that
is not identifiable here** and needs W₁₂ and W₂₃ arms.

Extraction rate, taken from the real reviews' tool-call traces rather than from
separate gate agents: W 18/18, W₂ 18/18, N 0/18. Two things round 18's claims
did not survive: the `not-a-defect` split was **not** the tighter instrument this
time (the composite was), and a pre-declared "underpowered" threshold computed
from a borrowed variance stopped meaning what it meant when the variance
changed — the same failure this round's protocol had fixed for the gate and not
for the secondary. `round-19/README.md`.

## Round 18: is the floor reducible to its second clause?

`round-18/` — round 17's decomposition put the whole effect in one verdict class
whose shape is clause 2's target, so this asks whether clause 2 is the section.
It is not.

| | W₂ (clause 2 alone) | N | difference | t | MDE |
|---|---|---|---|---|---|
| PRIMARY C+M `not-a-defect` | 3.33 | 4.33 | −1.00 | −1.20 | 2.55 |
| CONTROL real defects reached | 36.17 | 34.83 | +1.34 | +0.60 | 6.81 |

```bash
evals/rule-precision/round-18/measure.py --gate   # the gate, run first and alone
evals/rule-precision/round-18/measure.py
```

Powered for 2.67 — the full floor's effect on this fixture — and the decision
rule does not fire, so **clauses 1 and 3 stay**. It does not show clause 2 is
inert: −1.00 is inside the MDE. The comparator is N rather than W because a null
against W could not have licensed a deletion at any affordable n; the protocol
works that arithmetic out.

Three things this round contributes beyond its own result: the pre-registered
split is a **22% tighter instrument** than the composite on identical data; the
power gate stated as a quantity rather than an sd ceiling needed no
interpretation when it mattered; and 1027 findings produced **9 new claims and
zero new real defects**, so F10's real set has now been stable for two rounds.
`round-18/README.md`.

## How power and inference are kept apart

`methods.md` — what the MDE is for (sizing a round before it runs), what the
paired test and interval are for (what the round observed), and when a SESOI is
pre-registered instead. Rounds 12–19 used the MDE for both jobs; round 19 is the
worked example of the two disagreeing.

```bash
evals/rule-precision/extract.py <review-dir> <out.tsv>   # structured, not regex
```

`extract.py` replaces the per-round heading regex that lost findings in rounds
18 and 19 — both times in the arm carrying the Finding Floor, because clause 2
makes reviewers invent heading shapes the brief's template has no slot for. A
block is a finding if it carries a `File:` field; severity is whichever severity
word is in the heading; fields run across hard-wrapped lines. It reproduces
round 19's `findings.tsv` byte-for-byte.

## The primary metric mixes two failure modes (post-hoc, rounds 12 and 17)

```bash
evals/rule-precision/decompose.py
```

Every round's primary counts Critical/Major findings whose claim is not `real`,
and that set contains both `not-a-defect` (a preference, or a requirement about
code the change does not contain) and `wrong` (a misread). The Finding Floor
targets the first and says nothing about the second.

| | W | N | difference | t |
|---|---|---|---|---|
| round 12 (F9), published = not-a-defect | 1.62 | 4.12 | −2.50 | −4.11 |
| round 17 (F10), published composite | 2.44 | 4.56 | −2.11 | −3.05 |
| round 17 (F10), **not-a-defect only** | 1.22 | 3.89 | **−2.67** | **−5.95** |

F9 produced **no** Critical/Major misread at all, so there the two metrics
coincide; F10 contains one misread trap and they do not. The composite is
therefore sensitive to a property of the fixture that has nothing to do with the
intervention, and it under-reports. **Pre-register the split before leaning on
it** — this analysis was written after both rounds were recorded.
`round-17/README.md` has the trap, the residual, and the caveats.

## What it cannot tell you

- **`real` is a panel's judgement, not ground truth.** Three agents under a
  stated assumption, agreeing 84–94% of the time. There is no oracle here.
- **The 39 real claims are the union of what these 48 replies found.** A defect
  none of them reported is invisible, so "16.8 of 39" is coverage of the
  discovered set, not of the fixture.
- **One fixture, one batch.** The coverage difference (2.3 claims) is smaller
  than what this design detects at 80% power (3.23), so it is significant and
  under-powered at once. Replicate before leaning on the size.
- **Clustering was one pass by one agent per file.** A second, independent
  clustering has not been run, and cluster boundaries move the per-claim counts
  (not the finding-level precision, which does not depend on them).
- **Nothing here measures whether a proposed fix works.** The fixtures are
  diffs; there is no repository to apply anything to.
