# Evidence-gated row routing — Gate 0 does not refute it

**The candidate survives. Nothing is adopted, nothing is implemented, and no
agents were spent.** `protocol.md` fixes the gates; `gate0.py` reproduces every
number here and stops if the transcript set it reads is not the one these
numbers came from.

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
| **candidate rows only** | 3.5 | 1.44% | 6.33% | 18.56% | **23.45%** | 17.17% |
| | 3.8 | 1.33% | 5.83% | 18.56% | **23.06%** | 17.11% |
| | 4.2 | 1.20% | 5.27% | 18.56% | **22.63%** | 17.05% |
| the whole catalogue | 3.5 | 3.56% | 15.38% | 67.09% | 78.92% | 87.33% |
| catalogue + the diff | 3.5 | 5.34% | 25.35% | 67.29% | 87.29% | 88.76% |

**22.63–23.45% clears the 20% bar, so Gate 0 cannot end the work.** Nothing here
is exact: bytes are measured, tokens are modelled from them, so every figure is
a model-based bracket reported at three calibrations. The denominator is the
whole round — all 150 agents, including the three that fetched no rows — so the
figures are a share of the round, not of the subset the intervention touches.

## Read the columns before reading that as encouragement

Almost the whole ceiling is the vanished round trip, and **a gate that retains
anything reaches that term only by also consolidating what it retains into fewer
calls.** Row fetches per agent are 0 ×3, 1 ×107, 2 ×35, 3 ×4, 4 ×1 — 40 agents
fetch rows more than once, so a non-empty retained set can still drop requests,
but only down to one.

The intervention as fixed says which rows to open, **not how many calls to
make**. Whether the trip term is available at all is therefore a property of the
implementation, not of the gate. Gate 1 reports both variants:

- **with consolidation** — retained set empty: every row-result request goes;
  non-empty: `max(existing row-result requests − 1, 0)` go; plus content;
- **without consolidation** — the call count is whatever the reviewer happens to
  make, the trip saving is **not identifiable**, and only the content column
  (5.27–6.33%) applies.

The share of empty retained sets is one input to that, not the decisive
quantity — an earlier version of this document said it was, on the assumption of
one row fetch per agent, and that was wrong.

## What the current routing does (measured, for the record)

147 of 150 round-22 review agents issued **at least one** anchored `rg` (0 ×3,
1 ×107, 2 ×35, 3 ×4, 4 ×1), 145 of them with rule IDs parseable from the
pattern. The candidate set is chosen from the digest
**before any row is read**, so the intervention's decision point is well defined
and every candidate is observable.

| | mean | median | max |
|---|---|---|---|
| candidate rule IDs in the `rg` pattern | 18.0 | 17.0 | 33 |
| matched row lines returned | 18.9 | 18.0 | 52 |
| row bytes | 21.7 kB | 21.4 kB | 39 kB |
| rule-detail pages opened | 3.0 | 4.0 | 7 |
| detail pages as a share of candidates | 17.1% | 19.0% | 50% |

Only 17.1% of candidates are ever promoted to a detail page, so the speculative
expansion the intervention targets is real.

## Where the raw tokens are

| raw processed tokens, round-22 reviews | |
|---|---|
| cache read (context re-sent) | 67.9% |
| cache creation | 25.7% |
| output | 6.1% |
| uncached input | 0.2% |

**93.6% is transport, not content** — the same material re-sent across a mean of
7.6 requests per agent. Row content is 21.7 kB, about 5.7k tokens, against 422k
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
3. **The Gate 1 formula assumed one row fetch per agent.** 40 of 150 make more
   than one, so the empty/non-empty dichotomy it rested on does not hold.
   Corrected before Gate 1 was run.

`protocol.md` carries both amendments in place, each with the direction it moves
the conclusion.

## What this does not license

- It is not evidence the intervention works. Gate 0 can only refute or fail to
  refute, and it failed to refute.
- It does not adopt, implement, or schedule anything.
- It does not name a successor candidate; none is needed while this one is live.
