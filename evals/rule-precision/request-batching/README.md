# Catalogue fetch batching — Gate B1 refutes it

**Gate B0 removed every round trip the catalogue costs and reached 25.25–25.60%
of raw processed tokens against a 20% bar, so it could not end the line. Gate B1
puts the reviewer's own dependency order back — the catalogue cannot arrive before
the digest that names it — and the same perfect batch is worth 19.32–19.52%. That
is below the bar at every calibration, so the line stops. Nothing is adopted,
nothing is implemented, and no agents were spent.** `protocol.md` fixes the gates and
carries five amendments — two that moved Gate B0's verdict, two that rewrote
Gate B1 into a form that can be run and can only refute on a real upper bound,
and one that narrowed what its refutation claims once the variants were priced.
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

## Gate B1 — with the reviewer's own dependency order

B0's ceiling assumes one turn issues every fetch. That is a knowledge assumption,
not a scheduling one, and the corpus says where it fails: **79 of the 150 agents
have B0's host at the very request that ingests the digest**, so landing the rows
there means knowing the candidate IDs before reading the digest that produces
them.

B1 rebuilds each agent as a chain — stage 0 the digest, out of scope and never
moved; stage 1 everything derived from it, arriving no earlier than the request
after the digest. Per the protocol's fourth amendment the figure the verdict is
read from **hands each agent the detail set it turned out to open**, so the chain
is two-stage for all 150 and no derivation rule can beat it.

**The causal window has one position.** The first catalogue result arrives exactly
one request after the digest in **all 150** agents, so the host is forced and
there is nothing left to choose — which also means the lower/upper band the
protocol reserved for directory traffic is empty: with a single host, every result
moves to the same place.

| | B/tok | (a) as registered | (b) move-subset | (c) + deferred host |
|---|---|---|---|---|
| **as measured** | 3.5 | **19.32%** | 19.91% | 19.92% |
| | 3.8 | **19.41%** | 19.96% | 19.97% |
| | 4.2 | **19.52%** | 20.01% | 20.02% |
| + UTF-8 bytes | 4.2 | 19.51% | 20.01% | 20.02% |
| + floor extractions out | 4.2 | 19.43% | 19.50% | 19.58% |
| + moved calls charged | 4.2 | 19.40% | 19.46% | 19.55% |

**(a) is the intervention this protocol fixed** — one turn issues every fetch —
and it is below the bar at every calibration. **Gate B1 refutes it.**

### The family claim does not follow, and is not made

(b) and (c) are not the fixed intervention. (b) is free to batch only the fetches
worth batching: a result whose request survives anyway buys no round trip and only
costs early carry. (c) additionally defers the host. A refutation phrased as *no
batching form clears the bar* would have to cover them, and it cannot: (c) reaches
**20.02%** at the coarsest calibration, over the bar by 0.02 points.

Every known approximation in that count runs the same way — all four credit the
intervention with something it does not get — and together they are worth 0.47
points, which would put (c) at 19.55%. They are estimates applied in the direction
that favours refutation, so nothing here leans on them. **A subset-batching,
deferred-host form is a different candidate and needs its own protocol.** The
protocol's fifth amendment records this narrowing: Gate B1 was written to say that
its ceiling falling below the bar refutes *any* batching form, and that was more
than it can support. What can
be said is that its ceiling sits on the bar, where the fixed form is half a point
under it.

### What was checked

- **the causal floor** — every one of the 781 ingested catalogue results has the
  host at or before it, and the host is the digest arrival plus one in all 150
  agents. Asserted, not assumed.
- **no better placement** — the host is not taken on a closed-form rule's word.
  (c) enumerates every position the batch could occupy at or after the floor, and
  none beats the reported figure.
- **the formula against the round** — (a) equals the batched round costed from
  scratch, for every agent and calibration: one subtracts what goes, the other
  adds up what stays.
- **the degenerate case** — with the causal floor removed, (a) reproduces
  `gate_b0.py`'s registered arrangement to the token, which a one-position window
  requires. Two independently written implementations, same number.
- **eight cases in `tests/gate-b1-causal.bats`**, all synthetic. Each rule that
  decides the number was mutated and observed to go red — the floor ignored,
  losses taken instead of declined, carry charged to requests the same bound is
  removing, the enumeration reduced to the floor position, the floor extraction
  correction disabled, the rebuilt round shifted by one request.

## What this does not license

- It is not evidence that batching works, and Gate B0 can only refute or fail to
  refute. It failed to refute.
- It is not an implementable figure, and Gate B1 below is what happens when the
  reviewer's dependency order is put back.
- It says nothing about claims reached, in either direction. Batching does not
  change what is read; the refutation is on cost alone.
- It does not adopt, implement, or schedule anything, and Gate B2 is not run: a
  refutation at B1 is the point of putting the cheap gate first.
- It does not refute trimming transport in general. What is refuted is moving the
  same fetches into one turn, at a bar of 20%, on this fixture.
