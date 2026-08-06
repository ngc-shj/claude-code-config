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
