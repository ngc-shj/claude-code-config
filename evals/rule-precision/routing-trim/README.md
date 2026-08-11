# Evidence-gated row routing — refuted at Gate 0

**The candidate is rejected. Gate 1 is not run, nothing is implemented, and no
agents were spent.** `protocol.md` fixes the gates and carries three amendments;
`gate0.py` reproduces every number here and stops if the transcript set it reads
is not the one these numbers came from.

**Scope: this refutes one candidate, not the audit that proposed it.** Removing
the entire catalogue reaches 61.77%, so a different and larger intervention on
the same material is untouched by this result.

## What is being evaluated

The review-efficiency audit (`../review-efficiency/`) recommended one thing to
test forward: cut what each reviewer reads from the catalogue, holding k=3 and
the role split fixed. The concrete form:

> **Evidence-gated row routing.** After obtaining candidates from the digest,
> open the compact row only for rules for which a concrete `file:line` in the
> change can be cited. Read a rule-detail page only when the row itself points
> to a mandatory detail.

with a termination gate: **if the reduction in raw processed tokens is below
20%, stop.**

## Gate 0 — the cheapest question, asked first

Before replaying anything, ask what removing **100%** of the target would save.
That is unreachable by construction, so any real gate does worse, and an
intervention whose perfect form misses the bar is refuted without a replay.

The ceiling has to include the **round trip the removal deletes**, not only the
bytes: with no rows to fetch there is no anchored `rg`, so the request that
ingests its result is never made. Since 94% of raw tokens are context re-sent
across requests, that vanished request is the larger term by far.

| removed entirely | B/tok | floor | content | trip | **CEILING** | api-eq |
|---|---|---|---|---|---|---|
| **candidate rows only** | 3.5 | 1.48% | 6.51% | 13.55% | **18.58%** | 9.66% |
| | 3.8 | 1.36% | 5.99% | 13.55% | **18.18%** | 9.61% |
| | 4.2 | 1.23% | 5.42% | 13.55% | **17.74%** | 9.54% |
| the whole catalogue | 3.5 | 3.55% | 15.36% | 49.96% | 61.77% | 65.54% |
| catalogue + the diff | 3.5 | 5.33% | 25.32% | 50.02% | 70.01% | 66.76% |

**17.74–18.58% misses the 20% bar at every calibration, so Gate 0 refutes the
candidate.** An evidence gate can only do worse than removing everything, so no
replay, telemetry or forward test can rescue it. Nothing here
is exact: bytes are measured, tokens are modelled from them, so every figure is
a model-based bracket reported at three calibrations. The denominator is the
whole round — all 150 agents, including the three that fetched no rows — so the
figures are a share of the round, not of the subset the intervention touches.

## Read the columns

Most of what is there is the vanished round trip, and **a gate that retains
anything reaches that term only by also consolidating** what it retains into one
call. Row fetches per agent are 1 ×145, 2 ×4, 3 ×1 — five agents fetch more than
once, so consolidation buys almost nothing even where it applies.

The intervention as fixed says which rows to open, **not how many calls to
make**. Without consolidation only the content column applies: **5.42–6.51%**.
Either reading is below the bar.

## What the current routing does (measured, for the record)

All 150 round-22 review agents issued **at least one** anchored `rg` (1 ×145,
2 ×4, 3 ×1), every one with rule IDs parseable from the pattern. The candidate
set is chosen from the digest
**before any row is read**, so the intervention's decision point is well defined
and every candidate is observable.

| | mean | median | max |
|---|---|---|---|
| candidate rule IDs in the `rg` pattern | 18.2 | 17.0 | 33 |
| matched row lines returned | 19.8 | 18.0 | 61 |
| row bytes | 21.8 kB | 21.1 kB | 30 kB |
| rule-detail pages opened | 2.9 | 4.0 | 7 |
| detail pages as a share of candidates | 16.9% | 19.0% | 50% |

Only 16.9% of candidates are ever promoted to a detail page, so the speculative
expansion the intervention targets is real.

## Where the raw tokens are

| raw processed tokens, round-22 reviews | |
|---|---|
| cache read (context re-sent) | 67.9% |
| cache creation | 25.7% |
| output | 6.1% |
| uncached input | 0.2% |

**93.6% is transport, not content** — the same material re-sent across a mean of
7.6 requests per agent. Row content is 21.8 kB, about 5.7k tokens, against 422k
raw per agent. This is why the round trip dominates the bytes, and why a
content-only model of the saving was wrong.

## Correction, recorded

Three corrections, all raised in review, none found by the author.

1. **The ceiling was not an upper bound.** The first version counted only the
   removed bytes and read 7.94%; on that figure this document refuted the
   candidate and withdrew the recommendation in `../review-efficiency/`. Both
   were wrong: it omitted the request that disappears with the rows — the
   dominant term, and the same transport mass this audit had itself identified.
2. **Three arithmetic defects.** Eliminated requests were counted once per tool
   result rather than once (ceilings above 100% for the wider scopes); the
   denominator excluded agents the scope did not touch; `later` counted one
   request too many; and the api-eq column added the removed content's first
   cache-write on top of the eliminated request that already contained it.
3. **The Gate 1 formula assumed one row fetch per agent**, and the empty/non-empty
   dichotomy it rested on does not hold.
4. **The classifier counted the reviewer's own output as a catalogue fetch.** It
   tested substrings of the whole serialised tool input, so a finding quoting
   `common-rules.md` and an `rg` command matched. That invented 37 row fetches
   and the requests to go with them: the true counts are 1 ×145, 2 ×4, 3 ×1, not
   0 ×3 / 1 ×107 / 2 ×35 / 3 ×4 / 4 ×1. **This is the correction that restored the
   refutation**, moving the ceiling from 22.63–23.45% to 17.74–18.58%.
   `tests/gate0-classify.bats` pins it, and fails if the whole-input form
   returns.

`protocol.md` carries both amendments in place, each with the direction it moves
the conclusion.

## What this does not license

- It does not refute the review-efficiency audit, or the idea of reducing what a
  reviewer reads. It refutes **this** candidate: evidence-gated row routing,
  against a 20% raw-token bar.
- It does not adopt, implement, or schedule anything.
- It does not name a successor candidate. Naming a lever from a share statistic
  is the error that produced this candidate; any successor must clear a
  Gate-0-style ceiling before anything else is spent on it.
