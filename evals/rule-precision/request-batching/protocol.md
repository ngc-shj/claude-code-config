# Protocol — catalogue fetch batching

**Written before any saving figure was computed.** The git history cannot
evidence that ordering, because this document and the first result will land in
the same commit; treat it as the author's account. Structural facts about the
current call pattern were measured first — they are needed to specify the
intervention at all — and are recorded below.

Four clauses have since been amended, each recorded in place with the direction
it moves the conclusion. Two are in Gate B0 and were made **after** a figure had
been computed; between them they moved the verdict across the bar twice — the
first made it refute, the second made it not. That sequence is the same failure
the routing-trim protocol records four times over, a quantity called a ceiling
that was not one, and it is recorded here rather than smoothed over. The third
and fourth rewrite Gate B1 — the first version could not be executed, the second
could refute on the strength of a rule the author happened to pick — and both
were made **before** Gate B1 was run.

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

**Scope.** The verdict rests on this choice — the strict reading falls on the
other side of the bar — so it is stated here and repeated wherever a figure is
quoted. The intervention names row and detail fetches, so the primary scope is
those plus the directory traffic that comes with them — `../routing-trim`'s
generous reading, since batching does not care whether a call names a page. Two
further scopes are reported and neither is the figure quoted: the strict reading
(rows and identified pages only), and the whole catalogue (digest, `SKILL.md` and
the floor extractions as well), which is a superset the intervention does not
claim.

**If the ceiling is below 20% of raw processed tokens at every calibration, the
line of work stops here.** No proxy, replay, telemetry, or forward test can
rescue an intervention whose perfect form does not clear the bar.

### Gate B1 — the causal form (0 agents), only if B0 passes

B0 assumes one turn issues every fetch. That is not a scheduling assumption, it
is a knowledge assumption, and it fails in a measurable place: **79 of the 150
agents have B0's host at the very request that ingests the digest**, and 71 have
it later. None have it earlier. Landing the rows there requires knowing the
candidate IDs before reading the digest that produces them. B1 prices the whole
dependency chain instead of one link of it.

> **Amendment, 2026-08-14 (third) — Gate B1 as first written was not executable.**
>
> It asked for "the share of agents whose opened detail pages are a function of
> the digest candidate set alone". That test has no power over this corpus: all
> 150 candidate sets are distinct, so no input ever repeats and **every** observed
> detail set is trivially a function of its candidate set. The clause is withdrawn
> and replaced by the staged form below. It also omitted the row-acquisition step
> and said nothing about where directory traffic sits — and directory traffic is
> the ~9 points that decide B0's verdict, so leaving it unstated would have
> carried that choice into B1 silently. Raised in review, before Gate B1 was run.

**The stages, fixed.** Every agent is rebuilt as a chain, and each stage's batch
may be ingested no earlier than the request after its input arrives:

- **stage 0 — the digest.** Out of the primary scope and not moved. It is the
  causal floor: nothing derived from it may be ingested before the request that
  ingests it. Let that request be `d`.
- **stage 1 — rows.** Earliest possible arrival `d + 1`. Its host is the latest
  request in `[d + 1, first row arrival]` that survives for its own reasons; if
  there is none, the first row arrival hosts it and survives.
- **stage 2 — detail pages.** Earliest possible arrival `h1 + 1`, where `h1` is
  the stage-1 host — a page is mandatory because a row says so, and the row
  arrives at `h1`. Its host is chosen in `[h1 + 1, first detail arrival]` by the
  same rule. This stage exists for the auxiliary three-stage readout; the figure
  the verdict is read from collapses it into stage 1, per the fourth amendment.

**Stage 2 collapses into stage 1 for every agent, on the oracle set.** The figure
Gate B1 refutes on gives each agent the detail set it turned out to open and lets
that set ride with the rows, so the refutation chain is two-stage — digest, then
everything else — for all 150.

> **Amendment, 2026-08-15 (fourth) — collapsing only on a named rule's exact
> match was not an upper bound over the candidate.**
>
> The clause above previously required a pre-fixed derivation rule to reproduce
> the agent's opened pages exactly, and sent every mismatch to a three-stage
> chain. One rule failing does not show that no implementable rule succeeds, and
> with all 150 candidate sets distinct there is nothing in this corpus that could
> tell the two apart — the same non-identifiability the third amendment retracted,
> re-entering as a choice of rule. A figure built that way could refute "no
> batching form clears the bar" on the strength of the rule the author happened to
> pick.
>
> Corrected: the refutation UPPER always collapses stage 2 into stage 1, on the
> oracle set. A concrete derivation's agreement with the opened pages, and the
> three-stage chain it implies, are **auxiliary readouts** and belong to Gate B2,
> which is where an implementable form is priced. The correction makes the saving
> **larger**, so it moves against refutation. Raised in review, before Gate B1 was
> run.

**Directory traffic gets a stage, and the unidentifiable side goes to the upper.**
A call that names no page belongs to no stage on its face. Each such result is
therefore assigned to a host by its own bound:

- **upper** — the **latest** stage host at or before where it actually arrived,
  which minimises its early carry.
- **lower** — the earliest stage host, which maximises the early carry.

Placing such a result at a stage host at all is an **oracle relaxation, not a
causal fact**: it assumes the reviewer knew to make that call at that point, and
it **enlarges the saving**, because it is what lets the request that carried the
result disappear. It is used because Gate B1 refutes on the upper end. The
assignments do not interact — a request is eliminated when all its results move,
whichever host each moves to — and the rule is total on this corpus: all 134
ingested directory results arrive after the digest, so every one of them has a
stage host at or before it and none has to be moved later than it arrived.

Both ends are carried through every table. **Gate B1 refutes only if the UPPER end
is below 20% at every calibration**, and a lower end below the bar establishes
nothing.

**Reported alongside, and not part of the verdict.** Two forms outside the fixed
intervention are priced and printed with it: one free to batch only the fetches
worth batching, and one that additionally defers the host. They can only be larger
than the registered figure. The verdict is read from the registered figure, which
is the intervention this protocol fixed; where a variant crosses the bar, the
refutation is stated as covering the fixed form only and the family claim is
withheld. This adds reporting and changes nothing the gate decides on.

Gate B1 can refute the intervention as fixed — no implementable form beats an
oracle handed the answer at stage 1 — but **passing is not evidence** that the
batched configuration reaches the same claims.

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
