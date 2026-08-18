# Catalogue fetch batching — Gate B0 does not refute it

**Removing every round trip the catalogue costs, while keeping every byte of it,
is worth 25.25–25.60% of raw processed tokens against a 20% bar. Gate B0 cannot
end this line, and it proceeds to Gate B1. Nothing is adopted, nothing is
implemented, and no agents were spent.** `protocol.md` fixes the gates and
carries four amendments — two that moved this verdict, and two that rewrote
Gate B1 into a form that can be run and can only refute on a real upper bound.
`gate_b0.py` reproduces every number here and stops if the transcript set it
reads is not the one these numbers came from.

**This is a different candidate from `../routing-trim/`,** which was refuted at
its Gate 1. That one asked *which rules to read* and lost on content. This one
keeps every rule row, every detail page and every listing, and changes only
**when they arrive**: the catalogue fetches are issued in one turn, so one
request ingests every result instead of several. k=3, the role split and the
material read are untouched, so it is not an intervention on coverage.

**Two things this figure is not, stated before it is used.** It is an oracle
bound: it assumes the reviewer could name every fetch before reading a row, which
is exactly what Gate B1 has to test. And **it rests on a scope choice** — rows and
identified pages alone reach 15.86–16.08%, below the bar. The pre-registered
primary scope also contains the directory traffic that comes with them, because
batching absorbs any catalogue call whether or not it names a page. Unlike Gate 0
in `../routing-trim`, the conclusion here **does** depend on which reading is
used.

## Why transport, after content was refuted

The routing trim was refuted on content: the strictest oracle rule saved
9.92–10.89%. That left the larger mass unpriced. In this corpus **93.6% of raw
processed tokens are transport** — the same material re-sent across a mean of 7.6
requests per agent — and Gate 0 measured that removing every catalogue result
would delete **31.82%** of the round in vanished round trips alone, against
7.90–9.48% of removed bytes.

Content and transport are separately attackable. Batching attacks the second
without touching the first.

## Gate B0 — one request ingests every catalogue result

Three rules decide the number, and two of them were wrong once each:

- **trip** — a request whose every ingested result is in scope is not made at
  all. Its **context** is genuinely never sent; its **output** is saved only if
  that response did nothing but fetch the catalogue. 153 of the 297 removed
  requests also wrote the review or read the change, and that work **relocates**
  rather than vanishing.
- **early carry** — a result moved to an earlier request is in the context
  sooner, so every surviving request in between now re-sends it. **A figure that
  omits this is not a saving.**
- **where the batch lands** — in a request that survives anyway, the one that
  reads the diff. Nothing in the intervention says the batch needs a turn of its
  own, so keeping a catalogue-only request alive to host it understates the
  trip term.

| scope | B/tok | trip | early carry | **SAVING** | as registered | api-eq |
|---|---|---|---|---|---|---|
| **rows + pages + directory traffic** (primary) | 3.5 | 27.36% | 2.11% | **25.25%** | 19.32% | 10.42% |
| | 3.8 | 27.36% | 1.95% | **25.42%** | 19.41% | 10.44% |
| | 4.2 | 27.36% | 1.76% | **25.60%** | 19.52% | 10.47% |
| strict: rows and identified pages only | 3.5 | 17.22% | 1.37% | 15.86% | 14.53% | 5.13% |
| | 4.2 | 17.22% | 1.14% | 16.08% | 14.73% | 5.17% |
| the whole catalogue (digest and floors too) | 3.5 | 34.88% | 2.78% | 32.10% | 32.03% | 14.84% |
| | 4.2 | 34.88% | 2.32% | 32.56% | 32.50% | 14.91% |

The **as registered** column is the arrangement `protocol.md` first fixed, which
kept one catalogue-only request alive to host the batch. It is reported because
the amendment that replaced it moved the verdict, not because it is a second
reading of the same quantity.

The saving **rises** with the bytes-per-token calibration, which is the opposite
of every table in `../routing-trim`. There the modelled bytes were the saving;
here they are only the penalty, so a coarser calibration makes the cost smaller
and the result larger. The bracket is 0.35 points wide for that reason.

## What there is to batch

| round-22 review agents, primary scope | |
|---|---|
| requests ingesting a catalogue result, per agent | 2 ×83, 3 ×58, 4 ×8, 5 ×1 |
| agents whose catalogue already lands in one request | **0** |
| requests removed per agent | mean 2.0, median 2, max 4 |
| where the batch lands | request 2.5 of 7.6 |
| removed requests whose response relocates rather than vanishes | 153 of 297 |
| agents batching makes **worse** | 1 |

Every agent spreads its catalogue reads across at least two requests, so there is
something to batch everywhere — and the median agent loses two requests of 7.6.
For one agent the early carry still outweighs what vanishes (−5.2k tokens against
a best of +251k), which is the case a trip-only figure would have hidden.

## The verdict moved twice before it settled

Both corrections are recorded as amendments in `protocol.md`, with the direction
each moves the conclusion.

1. **The trip term credited work that relocates.** A removed request's whole
   measured usage was counted as saved, including a response that wrote the
   review. 23.77–23.97% became **19.32–19.52%** — below the bar, a refutation.
   Worth 4.45% of the round. Raised in review, not found by the author.
2. **"Where the batch lands" was not the maximum.** Keeping one catalogue-only
   request alive to host the batch understated the trip term: the fetches can be
   issued in a turn that was happening anyway. 19.32–19.52% became
   **25.25–25.60%** — above the bar, no refutation. Found while checking whether
   the refutation from (1) rested on an upper bound.

That is the second time in two rounds that a quantity called a ceiling was not
one. The check that caught it is the one worth keeping: **before publishing a
refutation, ask what arrangement would have saved more.**

## What is still loose, and in which direction

Gate B0 did not refute, so the figure being generous is the safe direction — but
each is measured rather than waved at. All four make the reported saving **larger**
than the truth, so a corrected figure moves toward refutation, not away:

- a response that issued **no** tool call is credited as vanishing;
- the moved `tool_use` blocks and command payloads are not charged early carry;
- bytes are counted in code points, not UTF-8, which understates the penalty;
- a Bash call that mentions `rule-details` puts its whole result in scope, so a
  command combining a floor extraction with a listing is moved entire — worth
  about 0.18 points on the primary scope.

## What was checked

- **The formula against its own definition.** `saving()` subtracts what is
  removed; `saving_reconstructed()` adds up what the batched round would cost —
  every surviving request's context, the moved results now in it, every surviving
  response, and every relocated response of a request that no longer exists. They
  agree to a token for every agent, scope, calibration **and both arrangements**.
- **The classifier is not re-implemented.** `gate_b0.py` imports `gate0.py`,
  pinned by `tests/gate0-classify.bats` and by the transcript manifest. Gate 0's
  manifest is the only pin needed: nothing here asks which review a transcript
  is, so Gate 1's agent-to-review manifest does not apply.
- **Twelve cases in `tests/gate-b0-batching.bats`**, all synthetic. Each rule that
  decides the number was mutated and observed to go red: the penalty dropped,
  charged to eliminated requests, or clamped at zero; the host eliminated with the
  rest, or chosen without co-location, or allowed to be a request that ingests
  nothing; a removed request's output always credited, or never.

## What this does not license

- It is not evidence that batching works, and Gate B0 can only refute or fail to
  refute. It failed to refute.
- It is not an implementable figure. The ceiling assumes **one** turn issues every
  fetch, and that is a knowledge assumption, not a scheduling one: **79 of the 150
  agents have the host at the very request that ingests the digest**, so landing
  the rows there means knowing the candidate IDs before reading the digest that
  produces them. **Gate B1** rebuilds every agent as a causal chain — the digest
  first, then everything derived from it no earlier than the request after it
  arrives — and prices that. It hands each agent the detail set it turned out to
  open, so no implementable rule can beat it, and it still cannot reach this
  ceiling.
- It says nothing about claims reached. Batching does not change what is read, so
  the adoption rule's first three clauses are threatened only through ordering —
  which Gate B1 examines and only the forward test can settle.
- It does not adopt, implement, or schedule anything.
