# Evidence-gated row routing — refuted at Gate 0

**The candidate is rejected. No trim was implemented, no telemetry was added,
no replay was run, and no agents were spent.** `protocol.md` was fixed before
any savings figure was computed; `gate0.py` reproduces every number here.

## What was being evaluated

The review-efficiency audit (`../review-efficiency/`) ended by recommending one
thing to test forward: cut what each reviewer reads from the catalogue, holding
k=3 and the role split fixed. The concrete form was pinned as:

> **Evidence-gated row routing.** After obtaining candidates from the digest,
> open the compact row only for rules for which a concrete `file:line` in the
> change can be cited. Read a rule-detail page only when the row itself points
> to a mandatory detail.

with a termination gate: **if the reduction in raw processed tokens is below
20%, stop.**

## Why it was refuted without a replay

The planned order was replay → telemetry → 20% gate. A cheaper gate goes first
and needs no proxy at all: **how much would removing 100% of the target save?**
That is an unreachable ideal — it assumes every row is speculative — so any real
gate does worse. An intervention whose perfect form misses the bar is refuted
outright.

Two figures, both computed exactly per agent from the round-22 transcripts.
*Floor* saves only the first ingestion; *ceiling* also removes the content from
every later request that re-sent it. Reported at three bytes/token calibrations
so the conclusion does not rest on one:

| removed entirely | floor | **ceiling** | api-eq ceiling |
|---|---|---|---|
| **candidate rows only** (the intervention, perfect) | 1.23–1.47% | **6.62–7.94%** | 2.96–3.55% |
| the whole catalogue | 2.97–3.56% | 15.79–18.95% | 7.13–8.56% |
| catalogue + the diff under review | 4.45–5.34% | 25.58–30.69% | 10.97–13.17% |

**The candidate's perfect form removes at most 7.94% against a 20% bar** — it
misses by 12 points, at every calibration, in both units.

The failure is not specific to this candidate: removing the **entire** catalogue
reaches at most 18.95%. But note the difference in robustness — that bound misses
by 1.1 points, so the broader claim ("no catalogue-routing intervention clears
20%") holds under this model and would not survive a materially more generous
one. The candidate's own failure would.

## Why the intuition was wrong

The candidate was chosen because the catalogue is **63% of the content bytes** a
reviewer reads. That statistic does not transfer to tokens:

| raw processed tokens, round-22 reviews | |
|---|---|
| cache read (context re-sent) | 67.9% |
| cache creation | 25.7% |
| output | 6.1% |
| uncached input | 0.2% |

**93.6% of raw tokens are transport, not content** — the same material re-sent
across a mean of 7.6 requests per agent. Row content is 21.7 kB, about 5.7k
tokens, against 422k raw per agent. Cutting what is read removes it once at
ingestion and once per later re-send, which is exactly the ceiling above.

This is the same unit error the review-efficiency audit documented in another
guise: content bytes, raw tokens and api-eq rank things differently, and a share
in one is not a share in another. The audit named the catalogue as the lever
using a content-byte share. That recommendation is now withdrawn.

## What the current routing does (measured, for the record)

146 of 150 round-22 review agents issued one anchored `rg`; the candidate set is
chosen from the digest **before any row is read**, so the intervention's decision
point is well defined and every candidate is observable.

| | mean | median | max |
|---|---|---|---|
| candidate rule IDs in the `rg` pattern | 18.0 | 17.0 | 33 |
| matched row lines returned | 18.9 | 18.0 | 52 |
| row bytes | 21.7 kB | 21.4 kB | 39 kB |
| rule-detail pages opened | 3.0 | 4.0 | 7 |
| detail pages as a share of candidates | 17.1% | 19.0% | 50% |

Only 17% of candidates are ever promoted to a detail page, so the speculative
expansion the intervention targets is real. It is simply too small to matter at
the scale the gate demands.

## What this does not license

- It does not say the catalogue is well designed, only that trimming its
  **routing** cannot reach a 20% token cut. A smaller target is not refuted
  here, because no smaller target was pre-registered.
- It does not identify a replacement candidate. The transport share above says
  where the mass sits — turn count and retained context, and for api-eq, output
  at 5× — but naming a lever from a share statistic is the error that produced
  this rejection. Any successor must pass a Gate-0-style ceiling first.
- It changes no skill, no rule, and no reviewer configuration.

## The durable lesson

**Run the structural ceiling before adopting a candidate.** It costs one script
and no agents, it is proxy-free, and here it refuted in minutes a line of work
whose confirmatory design was priced at 294 agents and ≈124M raw tokens.
