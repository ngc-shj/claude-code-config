# Evidence-gated row routing — Gate 1 refutes it

**Gate 0 could not refute the candidate. Gate 1 does: the strictest oracle rule
saves 9.92–10.89% of raw processed tokens against a 20% bar, and the other three
save 2–4%. The line of work stops. Nothing was adopted or implemented, and no
agents were spent.** `protocol.md` fixes the gates and carries six amendments;
`gate0.py` and `gate1.py` reproduce every number here and stop if the transcript
set they read is not the one these numbers came from.

**What a refutation here means.** Gate 1 bounds a *perfect* gate — one that
decides from what the reviewer did after reading the row, which no real gate can
see. The bound is on the intervention **as fixed** in `protocol.md`; a
reformulated one is a different candidate and voids this protocol. It is not a
finding that the catalogue is cheap, and it does not touch the review-efficiency
audit's other observations.

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
| **the candidate**, strict (rows + page content) | 3.5 | 2.43% | 9.48% | 21.67% | **28.73%** | 38.15% |
| | 3.8 | 2.23% | 8.73% | 21.67% | **28.17%** | 38.07% |
| | 4.2 | 2.02% | 7.90% | 21.67% | **27.55%** | 37.98% |
| the same, generous (any traffic into the dir) | 3.5 | 2.60% | 10.21% | 31.82% | 39.43% | 43.65% |
| of which rows alone | 3.5 | 1.48% | 6.51% | 1.57% | 6.59% | 1.40% |
| the whole catalogue | 3.5 | 3.55% | 15.36% | 39.44% | 51.25% | 49.50% |
| catalogue + the diff | 3.5 | 5.33% | 25.32% | 50.02% | 70.01% | 66.76% |

**27.55–28.73% clears the 20% bar, so Gate 0 cannot end the work.** That is the
strict reading — calls that pull the content of a `<ID>.md` page, by absolute
path or by a `cd` into the directory plus a reading command. A generous reading
that also removes directory listings reaches 38.16–39.43%; the conclusion does
not depend on which is used, and the strict figure is the one quoted.

A request counts as removed **only when every result it ingests goes** — 142 of
the 323 requests that carry a scoped result also carry something out of scope,
usually the diff, and those survive. Gate 0 could have left this loose, since
overstating the trip term only makes refutation harder, but a bound wrong in a
knowable direction is worth tightening and doing so does not change the verdict.

Rows alone now reach **5.76–6.59%**: a row fetch almost always shares its
request with something out of scope, so removing rows removes bytes but rarely a
round trip. Scoping Gate 0 to rows produced a refutation the intervention never
warranted, and this is how thin that scope really was. Nothing here is exact: bytes are measured, tokens are modelled from them, so every figure is
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
**7.90–9.48%**, below the bar on its own. Gate 1 has to separate the two, and it
can only refute or fail to refute.

Gate 1's costing rules for detail pages are now fixed in `protocol.md` — which
pages survive a retained ID, how bytes and requests are attributed to them, what
happens when a row and a detail share one request, and how calls that touch the
directory without naming a page are treated. They were still rows-only after
Gate 0 was widened, which would have measured the same too-narrow intervention
one gate later.

## Gate 1 — the replay, and the end of the line

Gate 0 asked what removing everything would save. Gate 1 asks what a gate saves
when it has to **keep the rules the agent actually used**. Four retention rules
were pre-registered, strictest first; all four decide from what the agent did
*after* reading the row, so all four bound a perfect gate from above.

| retained per agent | mean | median | max | agents retaining nothing |
|---|---|---|---|---|
| candidates in the `rg` pattern | 18.2 | 17.0 | 33 | — |
| **G1** IDs cited in its own findings | 5.9 | 6.5 | 13 | 21 |
| **G2** + pages it opened | 7.9 | 8.0 | 13 | 0 |
| **G3** + the other two reviewers of the review | 12.1 | 12.0 | 18 | 0 |
| **G4** + the other arm at the same review index | 14.5 | 14.0 | 20 | 0 |

| saving, share of the round | B/tok | trip | content | **with consolidation** | content only |
|---|---|---|---|---|---|
| **G1** | 3.5 | 5.50% | 5.31–5.39% | **10.80–10.89%** | 5.28–5.39% |
| | 3.8 | 5.50% | 4.89–4.96% | **10.38–10.46%** | 4.87–4.96% |
| | 4.2 | 5.50% | 4.42–4.49% | **9.92–9.99%** | 4.40–4.49% |
| **G2** | 3.5 | 0.08% | 3.57% | **3.65–3.66%** | 3.54–3.57% |
| **G3** | 3.5 | 0.08% | 2.73% | **2.81–2.82%** | 2.67–2.70% |
| **G4** | 3.5 | 0.08% | 2.37–2.38% | **2.46%** | 2.31–2.34% |

**The upper end of every rule is below 20% at every calibration, so Gate 1
refutes.** The ranges are the band: 14 of the 781 results in scope carry several
pages with no boundary between them (`cat R3.md R40.md`), and both ends of that
band are carried through. The band is worth 0.09 points at G1 — it decides
nothing. Consolidation decides nothing either: with it G1 reaches 10.89%,
without it 5.39%.

### Why it collapses

**G2, G3 and G4 cannot remove a single detail page.** A page is retained when its
ID is retained *and* the agent opened it — and from G2 on, every page the agent
opened is retained by construction. So those three rules gate rows only, and Gate
0 already measured what removing **100%** of the rows is worth: **5.76–6.59%**.
They come in under it because they do not even remove all the rows.

**G1 is the only rule that removes pages, and it is still 10.89%.** Half of that
is not a gate at all:

| where G1's 10.89% comes from | |
|---|---|
| 21 agents whose findings cite no rule → the gate retains nothing | 5.48% |
| 129 agents that cite at least one | 5.41% |

For an agent that cites nothing, G1 degenerates into Gate 0's generous ceiling —
it removes the whole catalogue because the oracle happens to know, in advance,
that this reviewer will never name a rule. No implementable gate has that. Strike
those 21 agents and the perfect gate saves **5.41%** of the round.

The mechanism is the one Gate 0 already exposed. 93.6% of raw tokens are
transport, so the saving lives in requests that disappear, not in bytes; and a
request disappears only when **every** result it ingests goes. Retain one page or
one row and the request stays, taking the round trip with it — G1's trip term is
5.50% where Gate 0's was 31.82%, and G2–G4's is 0.08%.

### What was checked, because a refutation needs an upper bound

Gate 1 refutes on the upper end, so anything that could *understate* the saving
is a defect that matters. Four things were checked and one was wrong:

- **the arithmetic itself** — with nothing retained, `gate1.py` must reduce to
  Gate 0's generous ceiling. It reproduces it to the token at all three
  calibrations, against a separately written scan of the same transcripts. That
  check is what caught the `is_detail` defect below.
- **consolidation** — the protocol's consolidated form fetches the retained IDs
  "in one `rg`". Costing each historical fetch on its own merits left a second
  fetch alive whenever it carried a retained ID, understating both terms for the
  five agents that fetch rows more than once. Raised in review; fixed before any
  Gate 1 figure was computed.
- **the citation set** — an over-generous reading of "cited" retains too much and
  saves too little. 884 of the 886 cited IDs fall inside the agent's own
  candidate set, and 12 sampled occurrences are all real references, so the
  reading is not inflated. Citations the sheet does not carry would only *raise*
  the saving, which is the safe direction.
- **the trip term under a different call structure** — see below.

Two known slacknesses are left in, both smaller than the margin and measured:
bytes are counted in code points rather than UTF-8, which understates the scoped
bytes by 0.43% (≤0.03 points here); and a removed byte is credited to later
requests that the trip term has already removed whole, which *overstates* G1 by
0.40 points. Removing that overstatement leaves 10.48%, and Gate 1 is reported on
the looser figure.

### What this refutation does not cover

Gate 1 prices the intervention **as fixed**: which rows and pages to open, with
the retained rows fetched in one `rg` and each retained page still read. A gate
that also **batched every retained catalogue read into a single request** would
be a different intervention — the protocol says so, and voids itself for a
reformulated one. Its trip term is bounded above by Gate 0's generous trip,
**31.82%**, which does not fall below the bar. So the refutation is of the
routing change, not of every conceivable way to cut what a reviewer reads.

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

Thirteen corrections. Twelve were raised in review; one — number 12 — was caught
by a check written into the work itself, which is the first time this line of
work found a defect without a reviewer.

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
   Including them moves the ceiling from rows-only to the candidate scope and
   **reverses the refutation** — the third time the ceiling was found not to be
   one.
6. **Gate 1 was still costed on rows alone**, and would have repeated (5) one
   gate later. Its detail rules are fixed in `protocol.md` before it runs.
   Separately, "detail pages are the larger half" overstated what the numbers
   support, and `is_detail` was a superset of actual pages.
7. **The strict predicate matched only absolute page paths**, missing all 57
   relative-path reads, so the "identifiable pages only" ceiling was not that.
   And a result can name **several** pages, so Gate 1 needs an ID *set* per
   result. `page_ids()` returns the set.
8. **`page_ids()` then still missed the commonest loop form** —
   `for f in R3 R49; do cat $f.md; done`, 18 of the 58 page-reading commands —
   while `wc -l …/R3.md` and `ls -l …/R49.md` wrongly yielded IDs, contradicting
   the protocol's own definition. Fixing the second broke plain `Read` calls
   until a path-only target was treated as the content read it is; all three
   behaviours are now pinned by mutation-tested cases.
9. **Gate 1's all-or-nothing rule was a lower bound, and Gate 1 refutes on an
   upper one.** A saving below 20% computed that way could not refute anything.
   Replaced by exact splitting where the result is splittable — row lines carry
   their own ID, and the `for` form writes a per-page separator — and an
   explicit lower/upper band where it is not, with refutation conditional on the
   upper end.
10. **A wide reading-verb list misread two compound commands** — `wc -l … | tail`
    and `ls | head && wc` fetch no page content, but `tail`/`head` counted as
    reading verbs while they read another command's output. Bash classification
    is now restricted to `cat`, the only page-reading form in this pinned corpus.
11. **Request elimination asked whether every *scoped* result was removed**, when
    the question is whether every result is. 142 of the 323 requests that ingest
    a scoped result also carry something out of scope — usually the diff — and
    those requests survive. Applied to Gate 0 as well, which drops the strict
    ceiling to 27.55–28.73% and rows-only to 5.76–6.59%, and changes no verdict.
    The decision is now one function, `removable_requests()`, pinned by cases
    that go red if it reverts to the scoped-only rule or lets the final request
    go.
12. **`is_detail` was a superset of `is_detail_page` only by accident.** Its
    docstring claimed the generous scope contains the strict one; the predicate
    tested `'rule-details/'` or `'rule-details'` with `'ls '`, and the second
    matched the tail of `rule-details ` itself — so a path ending in anything but
    a space (`cd ".../rule-details" && cat R3.md`, two calls) was a page read the
    generous ceiling did not count. Plain containment makes the claim hold by
    construction. The generous ceiling moves to 38.16–39.43% and no verdict
    changes. Found by Gate 1's self-check, which could not reconcile the two
    scans until it was fixed.
13. **Gate 1 costed each row fetch on its own merits**, while the protocol's
    consolidated variant fetches the retained IDs "in one `rg`". A second fetch
    that happened to carry a retained ID stayed alive, understating both the
    bytes and the round trip for the five agents that fetch rows more than once —
    the dangerous direction, since Gate 1 refutes on an upper bound. Raised in
    review, before any Gate 1 figure was computed.

`protocol.md` carries all six amendments in place, each with the direction it
moves the conclusion.

## What this does not license

- It does not adopt, implement, or schedule anything, and Gates 2–4 are not run:
  a refutation at Gate 1 is the whole point of putting the cheap gate first.
- It is not a measurement of an evidence gate. Every figure is an oracle bound,
  and the oracle's advantage is visible in the numbers: the 21 agents that cite
  no rule contribute half of G1 precisely because the oracle knows in advance
  that they will not.
- It does not show the catalogue is cheap. Removing all of it is worth
  49.28–51.25%; what fails is gating it on evidence, not trimming it.
- It does not carry to a reformulated intervention. Batching the retained reads
  into one request is a different candidate, and it needs its own protocol.
