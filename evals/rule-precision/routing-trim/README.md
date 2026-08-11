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
| **candidate rows only** | 3.5 | 1.47% | 7.94% | 18.96% | **25.42%** | 20.32% |
| | 3.8 | 1.36% | 7.31% | 18.96% | **24.91%** | 20.04% |
| | 4.2 | 1.23% | 6.62% | 18.96% | **24.35%** | 19.73% |
| the whole catalogue | 3.5 | 3.56% | 18.95% | 67.09% | 82.48% | 94.20% |
| catalogue + the diff | 3.5 | 5.34% | 30.69% | 67.29% | 92.64% | 99.07% |

**24.35–25.42% clears the 20% bar, so Gate 0 cannot end the work.** Nothing here
is exact: bytes are measured, tokens are modelled from them, so every figure is
a model-based bracket reported at three calibrations.

## Read the columns before reading that as encouragement

Almost the whole ceiling is the vanished round trip, and **that term is only
available when the retained set is empty** — no rows to fetch, no `rg`, no
request. An evidence gate that keeps even one row still issues the `rg` and
still pays for that request, so it harvests the **content** column alone:
6.62–7.94%.

The intervention is defined to keep evidence-backed rows. So on any review with
at least one such row the reachable saving is the content figure, and the
ceiling is reachable only on reviews where nothing is evidence-backed at all.

That makes the decisive quantity a single countable thing:

> **How often is the retained set empty?**

Gate 1 measures it, costed with the same two terms — round trip where the
retained set is empty, content elsewhere.

## What the current routing does (measured, for the record)

147 of 150 round-22 review agents issued one anchored `rg`, 145 of them with
rule IDs parseable from the pattern. The candidate set is chosen from the digest
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

The first version of `gate0.py` counted only the removed bytes and reported a
ceiling of 7.94%. On that figure this document said the candidate was refuted
and the recommendation in `../review-efficiency/` was withdrawn. **Both were
wrong**: the model was not an upper bound, because it omitted the request that
disappears with the rows — the dominant term, and the same transport mass this
audit had itself identified. The error was raised in review, not found by the
author. `protocol.md` carries the amendment in place, including the direction it
moves the conclusion.

## What this does not license

- It is not evidence the intervention works. Gate 0 can only refute or fail to
  refute, and it failed to refute.
- It does not adopt, implement, or schedule anything.
- It does not name a successor candidate; none is needed while this one is live.
