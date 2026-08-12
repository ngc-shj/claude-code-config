# Protocol — evidence-gated row routing

**Written before any savings figure was computed** — fixed locally before
`gate0.py` was run. The git history does not evidence that ordering, because
this document and the first result landed in the same commit; a reader should
treat the claim as the author's account, not as a verifiable fact. Structural
facts about the current routing were measured first (they are needed to specify
the intervention at all) and are recorded below.

Four clauses have since been amended, each recorded in place below with the
direction it moves the conclusion: Gate 0's ceiling definition (twice), Gate 1's
costing formula, and the counts both were written against. A fifth amendment
fixes Gate 1's treatment of detail pages, before Gate 1 is run.

This protocol governs one candidate intervention and the order in which it may
be evaluated. It authorises no change to the skill.

## The intervention, fixed

> **Evidence-gated row routing.** After obtaining candidates from the digest,
> open the compact row only for rules for which a concrete `file:line` in the
> change can be cited. Read a rule-detail page only when the row itself points
> to a mandatory detail. No cap on the number retained; a fallback when routing
> is inconclusive is allowed and must record its reason.

It removes speculative expansion, not rule content, which is what makes it
consistent with progressive disclosure. **No variant of this is evaluated.** If
the intervention is reformulated, this protocol is void and a new one is written.

## What the current routing does

Measured over the round-22 review agents that issued an anchored `rg`. The
figures below were taken at pre-registration time with a scratch script;
**`gate0.py` is authoritative** and prints different values (18.2 / 19.8 /
21.8 kB / 2.9 / 16.9%) — the scratch script shared the payload-matching defect
the third amendment records. The pre-registration table is left as written
rather than edited after the fact:

| | mean | median | max |
|---|---|---|---|
| candidate rule IDs in the `rg` pattern | 18.2 | 17 | 33 |
| matched row lines returned | 19.4 | 18 | 52 |
| row bytes | 22.0 kB | 21.4 kB | 39 kB |
| bytes per returned row | 1.17 kB | 1.21 kB | 1.34 kB |
| rule-detail pages opened | 3.0 | 4 | 7 |
| detail pages as a share of candidates | 17.0% | 18.9% | 50% |

The candidate set is chosen **from the digest alone, before any row is read**,
and is emitted as one `rg` alternation. The decision point the intervention
targets is therefore well defined, and every candidate is explicitly observable
in the transcript. Only 17% of candidates are ever promoted to a detail page.

Per-agent catalogue content, for orientation (round 22, 150 agents): digest
11.4 kB, anchored rows 24.0 kB, rule-details 11.9 kB, other 5.2 kB — 52.5 kB
total, itself 63% of the 84 kB a reviewer reads. The 24.0 kB figure includes the
Finding Floor / Remedy Floor `awk` extraction, which is a fixed cost the
intervention does not touch; rows alone are the 22.0 kB in the table above.

## Adoption rule, lexicographic — not scalarised

1. zero loss of Critical real claims;
2. distinct real claims reached ≥ **95%** of current k=3;
3. C/M not-a-defect no worse;
4. among candidates passing 1–3, **minimum raw processed tokens**;
5. api-eq is a secondary readout only.

## Gates, in order

Each gate can only terminate the line of work or permit the next one. **No gate
permits shipping.**

### Gate 0 — structural ceiling (no proxy, no new agents)

Compute the raw-token reduction from removing **100% of candidate rows**. This
is an unreachable ideal: it assumes every row is speculative. Bytes are
measured; tokens are modelled from them, so the result is a **model-based
bracket**, reported at three bytes/token calibrations rather than as one exact
figure. For each agent, locate the request that ingests the row content and
account for what its absence removes.

Two figures are pre-registered, and both will be reported:

- **floor** — only the first ingestion is saved (no downstream effect);
- **ceiling** — the ingestion plus the removal from every later request that
  re-sent it.

> **Amendment, 2026-08-12 — the ceiling above is not an upper bound.**
>
> It counts only the removed bytes. With no rows to fetch there is no anchored
> `rg`, so the request that ingests its result is not made either, and since 94%
> of raw tokens are context re-sent across requests, that vanished round trip is
> the larger term. The definition as written under-counts it entirely.
>
> Corrected: **ceiling = the vanished round trip (each such request removed once,
> however many results it carried) + the removed content in every later request
> that would still have re-sent it.**
>
> This amendment was made **after** the first run, whose result it changes: the
> defective ceiling read 7.94% and refuted the candidate; the corrected one reads
> 25.42% and does not. The correction therefore moves **against** the conclusion
> previously drawn from it, which is the only direction in which amending a
> pre-registration after seeing a result is defensible. It was raised in review,
> not found by the author.

**If the corrected ceiling is below 20% of raw processed tokens, the line of work
stops here.** No proxy, replay, telemetry, or forward test can rescue an intervention
whose perfect form does not clear the bar. This is the cheapest possible
refutation and it is why it runs first.

### Gate 1 — counterfactual replay (0 agents), only if Gate 0 passes

The replay retains a candidate row under four pre-registered rules, from
strictest (most saved) to most generous (least saved):

- **G1** — retain only IDs cited in one of this agent's own findings;
- **G2** — retain IDs cited **or** whose detail page this agent opened;
- **G3** — G2 unioned across the three reviewers of the same review;
- **G4** — G3 unioned across both arms at the same review index.

**All four are oracle rules.** Each decides from what the agent did *after*
reading the row, which an evidence gate cannot see. They therefore bound the
savings of a perfect gate from above, and the real intervention can only do
worse.

> **Amendment, 2026-08-12 (second) — the empty/non-empty dichotomy was wrong.**
>
> An earlier version of this clause said the round trip is available only when
> the retained set is empty, and called the share of empty sets the decisive
> quantity. That assumed one row-fetch request per agent, and multi-fetch agents
> exist, so a non-empty retained set can still drop requests. Corrected before
> Gate 1 was run.
>
> The counts this amendment was first written with (0 x3, 1 x107, 2 x36, 3 x4;
> "40 agents fetch rows more than once") were themselves wrong — see the third
> amendment. The true figures are 1 x145, 2 x4, 3 x1: **five** agents.

> **Amendment, 2026-08-12 (third) — the classifier counted the reviewer's own
> output as a catalogue fetch.**
>
> It tested substrings of the whole serialised tool input, so a finding quoting
> `common-rules.md` and showing an `rg` command matched. That invented 37 row
> fetches and the requests to go with them. Classifying on what a call TOUCHES —
> a Bash command, a Read path, never a Write payload — gives 1 x145, 2 x4, 3 x1.
>
> `tests/gate0-classify.bats` pins this and fails if the whole-input form
> returns. Raised in review; its diagnosis named streaming snapshots of a
> repeated `tool_use.id`, which does not occur in this corpus — all 1623 ids are
> unique — but the counts it gave were right and the mechanism above produces
> them exactly.

> **Amendment, 2026-08-12 (fourth) — Gate 0's scope was narrower than the
> intervention.**
>
> The intervention gates two things: which rows to open, and which detail pages
> to follow from them. Gate 0 measured rows only, so it bounded a narrower
> intervention than the one written down, and on that narrower figure
> (17.74–18.58%) it declared a refutation.
>
> Removing 100% of what the intervention actually gates — rows and the detail
> pages they gate — clears the bar, so **Gate 0 does not refute and the work
> proceeds to Gate 1**. This reverses the third amendment's verdict and is the
> third time the ceiling was found not to be one. Raised in review.
>
> The figure this amendment was written with (35.76–36.89%, and the claim that
> "detail pages are the larger half") is superseded twice over: the detail
> predicate was a superset of pages, and then it was found to miss every
> relative-path page read, and the request rule beneath it changed twice more.
> `gate0.py` prints the current values; no figure is quoted here, because every
> one written into this amendment has since been superseded.

> **Amendment, 2026-08-12 (fifth) — Gate 1 costed rows only, like Gate 0 did.**
>
> The fourth amendment widened Gate 0 to rows plus the detail pages they gate,
> but left this clause costing row-result requests and row bytes alone. Gate 1
> would then have measured a narrower intervention than the one written down —
> the same defect, one gate later. The rules below replace it, and are fixed
> **before Gate 1 is run**. Raised in review.

> **Amendment, 2026-08-13 (sixth) — the all-or-nothing rule pointed the wrong
> way, `page_ids` missed the commonest loop form, and a request was treated as
> removable while it still carried the diff.**
>
> The fifth amendment resolved unattributable results by keeping them whole and
> crediting zero bytes. That is a **lower** bound on the saving, and Gate 1
> refutes on an **upper** one — so a figure below the bar computed that way could
> not have refuted anything. Replaced above by exact splitting where the result
> is splittable and an explicit lower/upper band where it is not, with refutation
> conditional on the upper end.
>
> Request elimination asked whether every *scoped* result was removed, when the
> question is whether every result is: 142 of the 323 requests that ingest a
> scoped result also carry something out of scope, most often the diff, and
> those requests survive. Applied to Gate 0 as well; its verdict is unchanged.
>
> Separately, `page_ids()` read literal `<ID>.md` only, so
> `for f in R3 R49; do cat $f.md; done` — 18 of the 58 page-reading commands —
> yielded nothing, while `wc -l .../R3.md` and `ls -l .../R49.md` yielded IDs the
> protocol says are not detail results at all, and `wc -l … | tail -15` was read
> as a page fetch because `tail` counted as a reading verb while it was reading
> `wc`'s output. All fixed and pinned by tests. Raised in review, before Gate 1
> was run.

Each candidate is costed over **rows and the detail pages the rows gate**, with
the same two terms as the corrected Gate 0. `retained` is the ID set a rule
keeps; everything below follows from it mechanically.

**Which detail pages survive.** A detail page is retained **iff its rule ID is in
`retained` and the agent actually opened it**. The intervention reads a detail
only when a retained row points to a mandatory one, so a page whose ID the gate
drops is removed with its row, and a page for a retained ID that the agent never
opened cannot be conjured into existence.

**Every result carries an ID SET, not an ID.** A single call can fetch several
pages — `cd .../rule-details && cat R3.md R40.md R49.md`, or a loop over the
same — and 57 calls do. A row result likewise carries every ID in its `rg`
alternation. So each scoped result is `(bytes, request index, id_set)`:

- detail results — the IDs whose page content the call reads, absolute
  (`rule-details/<ID>.md`) or relative (a `cd` into the directory plus a
  content-reading command). Commands that name pages without reading them
  (`wc -l`, `ls`) carry no page content and are not detail results;
- row results — the IDs in the `rg` pattern.

**Partial retention: split where the result is splittable, band where it is not.**

Gate 1's decision rule refutes when an **upper** bound falls below the bar, so
every unattributable quantity has to be resolved in the direction that makes the
saving *larger*, not smaller. An earlier version of this clause kept partially
retained results whole and credited them zero bytes. That is a **lower** bound:
a real implementation that trimmed line by line could save more, so a figure
below 20% computed that way could not refute anything.

- **Row results split exactly.** An anchored `rg -n` returns one line per matched
  rule and each line names its own ID, so bytes attribute per line with no
  guesswork. Dropped IDs contribute their lines; retained IDs do not.
- **Detail results split where the command wrote a separator.** The
  `for f in …; do echo "##### $f"; cat $f.md; done` form marks each page, so its
  bytes attribute per page. `cat R3.md R40.md` does not, and cannot be split.
- **Everything still unattributable is reported as a band**, and both ends are
  carried through every table:
  - **lower** — the result is kept whole and saves nothing;
  - **upper** — every byte of the mixed result is removable, while the request
    that carried it **stays** (it is still needed for the retained IDs).

**Gate 1 refutes only if the UPPER end is below 20% for every rule G1–G4 at
every calibration.** A lower end below the bar establishes nothing.

**Bytes and requests.** Removed bytes are credited to the request that ingested
them and to every later request that would still have re-sent them, exactly as
in Gate 0.

**When a request disappears.** A request is eliminated **only if every tool
result it ingests is removed** — not merely every *scoped* one. A request that
also carried the diff, or any other out-of-scope result, is still needed and
survives. 142 of the 323 requests that ingest a scoped result are mixed like
that, so the distinction is most of the term, not a corner case.

The same applies within the scope: if one retained result shares the request,
it stays and only the removed bytes are saved. A gate cannot delete a round trip
it still needs for something else.

Gate 0 applies this rule too. It could have been left loose there — Gate 0 is an
upper bound, and overstating the trip term only makes refutation harder — but a
bound that is wrong in a knowable direction is worth tightening, and doing so
does not change its verdict.

**Calls that touch the directory without naming a page** — `ls rule-details` and
the like — carry no ID, so no rule can retain or drop them on their merits. They
are **removed only when `retained` is empty**, and kept otherwise. Gate 0's
generous variant removes them unconditionally; Gate 1 does not, because that
variant is a bound and Gate 1 is meant to be a replay.

**Round trip.** A request disappears only under the rule stated above — **every
tool result it ingests is removed**, scoped or not. With the retained set empty
that is every row-result and detail-result request whose other results (if any)
also go; with it non-empty the retained IDs are fetched in one `rg` and each
retained page is still read, so fewer qualify. A request that also carried the
diff never qualifies.

**Content.** The removed row and detail bytes, in every later request that would
still have re-sent them.

**The trip term depends on consolidation being part of the evaluated form.** The
intervention as fixed says which rows to open, not how many calls to make. Gate 1
therefore reports two variants and does not choose between them:

- **with consolidation** — the formula above; the trip term is available;
- **without consolidation** — the number of calls is whatever the reviewer
  happens to make, so the trip saving is **not identifiable** and Gate 1 reports
  the content term alone. It is then not an upper bound on the trip side and
  cannot be used to clear the bar.

The share of empty retained sets is still reported, but it is one input, not the
decisive quantity.

Decision:

- whole bracket **below 20%** → stop; the conclusion does not depend on which
  proxy is right;
- whole bracket **at or above 20%** → an upper bound clears the bar, which is
  **not** evidence the real gate does. Proceed to Gate 2;
- bracket **straddles 20%** → the replay cannot decide. Proceed to Gate 2.

Note the asymmetry: Gate 1 can end the work but can never justify continuing to
a live test.

### Gate 2 — telemetry (0 new review agents)

Record, in normal operation, `candidate / opened / fallback` rule IDs per run and
`rule ID | none` per finding. This is the only way to observe what an actual
evidence gate retains, as against what an oracle would. It also closes the
rule-attribution gap the review-efficiency audit recorded as unmeasured.

### Gate 3 — rescue screen (small)

Run a full-catalogue screen against the trimmed configuration on a small sample.
**If the rescue surfaces even one real claim the trimmed run missed, the
intervention is rejected.** No margin, no averaging.

### Gate 4 — formal non-inferiority, only if it amortises

A 95% floor is a non-inferiority margin of about 1 claim per review on F11. At
round 22's observed pooled sd of 1.752, an optimistic plug-in gives n ≈ 49 per
arm — 294 agents, ≈124M raw / 86.7M api-eq. Variance uncertainty raises it. The
design is written **only** if the projected saving amortises that cost over a
defensible number of future reviews, and that projection is stated in advance.

Any pilot-based re-estimation of n must pre-register its method and calibrate
its type-I error: pooling arm variances uses the group labels, so it is not
automatically alpha-free.

## What this protocol will not do

- It will not report a savings figure without saying which gate produced it and
  whether that figure is an oracle bound.
- It will not treat a passed Gate 1 as evidence the intervention works.
- It will not scalarise the adoption rule into a single score.
- It will not compare across fixtures: everything here is F11 unless stated.
