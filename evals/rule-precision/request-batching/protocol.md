# Protocol — catalogue fetch batching

**Written before any saving figure was computed.** The git history cannot
evidence that ordering, because this document and the first result will land in
the same commit; treat it as the author's account. Structural facts about the
current call pattern were measured first — they are needed to specify the
intervention at all — and are recorded below.

Two clauses have since been amended, both recorded in place in Gate B0 with the
direction they move the conclusion. Both were made **after** a figure had been
computed, and between them they moved the verdict across the bar twice: the first
made it refute, the second made it not. That sequence is the same failure the
routing-trim protocol records four times over — a quantity called a ceiling that
was not one — and it is recorded here rather than smoothed over.

This protocol governs one candidate and the order in which it may be evaluated.
It authorises no change to any skill.

## Why this is a new protocol

`../routing-trim/protocol.md` fixed a different candidate — *which* rows and
pages to open — and refuted it at Gate 1: the strictest oracle rule saves
9.92–10.89% against a 20% bar. That protocol says a reformulated intervention
voids it and needs its own, and this is one. The two share only their corpus and
their bar.

The refutation was of **content**. It left the larger mass unpriced: 93.6% of raw
processed tokens are transport, not content — the same material re-sent across a
mean of 7.6 requests per agent — and Gate 0 measured that removing every
catalogue result would delete 31.82% of the round in vanished round trips alone.
Content and transport are separately attackable, and only one has been tried.

## The intervention, fixed

> **Catalogue fetch batching.** Keep every catalogue byte the reviewer reads
> today — every rule row, every detail page, every listing. Issue those fetches
> in **one turn**, so their results are ingested by one request instead of
> arriving across several. Nothing is dropped: k=3, the role split, and the set
> of rules read are untouched.

It removes round trips, not rule content, which is what makes it orthogonal to
progressive disclosure rather than a second attempt at it. **No variant of this
is evaluated.** If the intervention is reformulated, this protocol is void and a
new one is written.

## Adoption rule, lexicographic — not scalarised

Unchanged from `../routing-trim/protocol.md`:

1. zero loss of Critical real claims;
2. distinct real claims reached ≥ **95%** of current k=3;
3. C/M not-a-defect no worse;
4. among candidates passing 1–3, **minimum raw processed tokens**;
5. api-eq is a secondary readout only.

Batching does not change what is read, so 1–3 are threatened only through the
ordering effect named in Gate B1 — which is why Gate B1 exists.

## Gates, in order

Each gate can only terminate the line of work or permit the next one. **No gate
permits shipping.**

### Gate B0 — the batching ceiling (0 agents, no content removed)

Compute the raw-token reduction from ingesting **every** in-scope catalogue
result in a single request. Nothing is removed, so this is not a content bound:
it prices call structure alone. Bytes are measured, tokens are modelled from
them, so the result is a **model-based bracket**, reported at three bytes/token
calibrations.

**The two terms, and the second one is a cost.**

- **trip** — a request whose every ingested tool result is in scope is not made
  at all; its fetches moved to the batch. Counted once per request, however many
  results it carried. A request that also ingests anything out of scope — the
  diff, a source file, the change itself — **survives**, exactly as in
  `../routing-trim`'s Gate 0.
- **early carry** — a result moved from where it arrived to an earlier request is
  in the context sooner, so every surviving request in between now re-sends it.
  This is a **penalty**, and a figure that omits it is not a saving. It is
  subtracted.

> saving = raw(eliminated requests) − Σ over moved results of
> tok(result) × (surviving requests between the batch and where it used to arrive)

**Where the batch lands.** At the request that ingests the agent's **first**
in-scope result. That request survives and hosts the batch. It is also the latest
position the batch may occupy — a reviewer cannot fetch at turn 5 what it acted
on at turn 2 — and the penalty falls as the batch moves later, so this choice
**maximises the saving**. Both readings of "where" agree, so the ceiling is not
sensitive to it.

> **Amendment, 2026-08-14 (first) — the trip term credited work that relocates.**
>
> A request whose every ingested result is in scope may still have a RESPONSE
> that does something else: 143 of this corpus's removable requests emit the
> review `Write`. That work does not disappear because the fetch beside it moved
> into the batch — it relocates, and relocated output is paid wherever it lands.
> The clause above credited the whole measured usage of a removed request.
>
> Corrected: a removed request's **context** is saved; its **output** is saved
> only when its response issued nothing but catalogue fetches.
>
> This was made **after** the first figure was computed, and it changes it:
> 23.77–23.97% became 19.32–19.52%, which crosses the bar and would have refuted
> the candidate. The correction moves **toward** the refutation, which is the
> direction that demands the most scrutiny, not the least. It was raised in
> review, not found by the author. Worth 4.45% of the round.

> **Amendment, 2026-08-14 (second) — "where the batch lands" was not the maximum.**
>
> The clause above keeps one catalogue-only request alive to host the batch, and
> justified that as maximal by looking only at the penalty. It is not maximal: the
> fetches can be issued in a turn that was happening anyway — the one that reads
> the diff — so the results land in a request that survives for its own reasons
> and **no** catalogue-only request is left standing. Nothing in the fixed
> intervention says the batch needs a turn of its own.
>
> Corrected: the batch lands at the **latest surviving request at or before** the
> first in-scope arrival, and every catalogue-only request goes. Where no such
> request exists the original clause applies and the first arrival hosts it.
>
> Made after the first amendment's figure was computed, and it reverses it:
> 19.32–19.52% becomes 25.25–25.60%, so Gate B0 does **not** refute. This is the
> second time in two rounds that a quantity called a ceiling was not one, and the
> third time this line of work has had a verdict move because of it. Found by the
> author while checking whether the first amendment's refutation rested on an
> upper bound; both readings are reported and `gate_b0.py` prints them side by
> side.

**Why this is an upper bound.** Every purely-in-scope request is assumed
eliminable, which assumes the reviewer could have named all of its fetches up
front — the exact thing Gate B1 has to check, and which no real reviewer can do
for a detail page whose necessity is stated by a row it has not read yet. The
denominator is the whole round, all 150 agents, including any the scope never
touches.

**Scope.** The intervention names row and detail fetches, so the primary scope is
those plus the directory traffic that comes with them — `../routing-trim`'s
generous reading, since batching does not care whether a call names a page. Two
further scopes are reported and neither is the figure quoted: the strict reading
(rows and identified pages only), and the whole catalogue (digest, `SKILL.md` and
the floor extractions as well), which is a superset the intervention does not
claim.

**If the ceiling is below 20% of raw processed tokens at every calibration, the
line of work stops here.** No proxy, replay, telemetry, or forward test can
rescue an intervention whose perfect form does not clear the bar.

### Gate B1 — is the batch decidable in advance? (0 agents), only if B0 passes

The ceiling assumes one turn issues every fetch. A reviewer that reads a row and
*then* learns which detail page is mandatory needs two. Gate B1 asks, from the
transcripts alone, whether the detail set is predictable from what is known
before the row arrives:

- the share of agents whose opened detail pages are a function of the digest
  candidate set alone — i.e. openable in the same turn as the row;
- for the rest, the ceiling recomputed with **two** rounds instead of one (rows
  in the first, details in the second), which is the honest form of the
  intervention if the set is not predeterminable.

Gate B1 can refute — if the two-round ceiling is below the bar, batching cannot
be implemented in a form that clears it — but **passing is not evidence** that
the trimmed configuration reaches the same claims.

### Gate B2 — an implementable lower bound, only if B1 passes

An oracle bound is not a proposal. Gate B2 states the concrete instruction a
skill would carry, and prices **that**, not its perfect form. Only if the
implementable figure clears 20% does the work proceed to a skill change and a
small forward test under the adoption rule above.

The forward test is what checks claims reached, and nothing before it does.

## What this protocol will not do

- It will not report a saving without saying which gate produced it and whether
  that figure is an oracle bound.
- It will not treat a passed gate as evidence the intervention works.
- It will not omit the early-carry penalty from any figure it calls a saving.
- It will not compare across fixtures: everything here is F11 unless stated.
