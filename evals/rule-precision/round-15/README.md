# Round 15 — raw data, analysis not yet run

Pre-registration: `../../rule-ablation/protocols/round-15.md`.

`findings.tsv` holds every finding the review agents produced, with the arm, the
review and the reviewer position. `base/` holds the titles-only stimulus arm T
was given; arm C's full-text stimulus is round 14's, and arm I had none.

**Six of the eight pre-registered reviews ran.** The run was stopped there
against a budget ceiling rather than completed and left unanalysed — an
unadjudicated round produces nothing, while a short one still produces a result
with a wider MDE. The deviation is recorded here and in the audit doc when the
analysis lands.

What is NOT done: assigning these findings to the 115-claim inventory,
adjudicating whatever claims are new, and computing the three-arm table. Those
need roughly eleven agents and no new reviews.

Descriptively, before any adjudication:

| arm | reviews | findings | per reply | Critical+Major |
|---|---|---|---|---|
| T (titles only) | 6 | 107 | 5.9 | 76 |
| C (full base) | 6 | 121 | 6.7 | 82 |
| I (blind) | 6 | 228 | 12.7 | 178 |

Findings-per-reply is not a metric this round pre-registered; it is here because
it is the one number available without adjudication, and it says only that the
treatment arrived.
