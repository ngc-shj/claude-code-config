# Evidence-gated row routing — Gate 0 does not refute it

**Gate 0 fails to refute the candidate; it proceeds to Gate 1. Nothing is
adopted, nothing is implemented, and no agents were spent.** `protocol.md` fixes the gates and carries five amendments;
`gate0.py` reproduces every number here and stops if the transcript set it reads
is not the one these numbers came from.

**Scope note.** The fixed intervention gates two things — which rows to open and
which detail pages to follow from them — so Gate 0 must remove both. An earlier
revision of this document measured rows alone, found 17.74–18.58%, and declared
the candidate refuted. That was a ceiling on a narrower intervention than the
one written down.

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
| **the candidate**, strict (rows + page content) | 3.5 | 2.29% | 9.06% | 32.21% | **38.98%** | 42.85% |
| | 3.8 | 2.11% | 8.35% | 32.21% | **38.44%** | 42.77% |
| | 4.2 | 1.91% | 7.55% | 32.21% | **37.85%** | 42.69% |
| the same, generous (any traffic into the dir) | 3.5 | 2.59% | 10.18% | 38.56% | 46.15% | 47.89% |
| of which rows alone | 3.5 | 1.48% | 6.51% | 13.55% | 18.58% | 9.66% |
| the whole catalogue | 3.5 | 3.55% | 15.36% | 49.96% | 61.77% | 65.54% |
| catalogue + the diff | 3.5 | 5.33% | 25.32% | 50.02% | 70.01% | 66.76% |

**37.85–38.98% clears the 20% bar, so Gate 0 cannot end the work.** That is the
strict reading — calls that pull the content of a `<ID>.md` page, by absolute
path or by a `cd` into the directory plus a reading command. A generous reading
that also removes directory listings reaches 44.89–46.15%; the conclusion does
not depend on which is used, and the strict figure is the one quoted.

Rows alone reach 17.74–18.58%, which is why scoping Gate 0 to rows produced a
refutation the intervention does not warrant. Including details **raises the
ceiling by about 20 points** — a marginal contribution once rows are already
removed, not an independent share of the total, and not larger than the rows
term at every calibration. Nothing here is exact: bytes are measured, tokens are modelled from them, so every figure is
a model-based bracket reported at three calibrations. The denominator is the
whole round — all 150 agents — so the figures are a share of the round, not of
the subset the intervention touches.

## Read the columns

Most of what is there is the vanished round trip, and **a gate that retains
anything reaches that term only by also consolidating** what it retains into one
call. Row fetches per agent are 1 ×145, 2 ×4, 3 ×1 — five agents fetch more than
once, so consolidation buys little where it applies at all.

The intervention as fixed says which rows and details to open, **not how many
calls to make**. Without consolidation only the content column applies:
**7.55–9.06%**, below the bar on its own. Gate 1 has to separate the two, and it
can only refute or fail to refute.

Gate 1's costing rules for detail pages are now fixed in `protocol.md` — which
pages survive a retained ID, how bytes and requests are attributed to them, what
happens when a row and a detail share one request, and how calls that touch the
directory without naming a page are treated. They were still rows-only after
Gate 0 was widened, which would have measured the same too-narrow intervention
one gate later.

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

Seven corrections, all raised in review, none found by the author.

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
5. **Gate 0's scope was narrower than the intervention.** It measured rows only,
   while the intervention also gates the detail pages the rows point to.
   Including them moves the ceiling from 17.74–18.58% to 37.85–38.98% and
   **reverses the refutation** — the third time the ceiling was found not to be
   one.
6. **Gate 1 was still costed on rows alone**, and would have repeated (5) one
   gate later. Its detail rules are fixed in `protocol.md` before it runs.
   Separately, "detail pages are the larger half" overstated what the numbers
   support, and `is_detail` was a superset of actual pages.
7. **The strict predicate matched only absolute page paths**, missing all 57
   relative-path reads (`cd .../rule-details && cat R3.md R40.md`), so the
   "identifiable pages only" ceiling was not that. And a result can name
   **several** pages — two calls fetch four each — so Gate 1 needs an ID *set*
   per result, with an all-or-nothing rule for partial retention. Both are now
   in `protocol.md`; `page_ids()` returns the set.

`protocol.md` carries all five amendments in place, each with the direction it
moves the conclusion.

## What this does not license

- It is not evidence the intervention works. Gate 0 can refute or fail to
  refute, and it failed to refute.
- It does not adopt, implement, or schedule anything.
- It does not show the intervention reaches the ceiling. Most of the ceiling is
  the round trip, which needs consolidation the intervention does not specify;
  the content term alone is below the bar.
