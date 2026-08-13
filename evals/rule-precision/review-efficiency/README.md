# Review-efficiency audit — what a review costs, and what buys the coverage

**Retrospective, exploratory, descriptive.** It states no confirmatory result,
tests no pre-registered hypothesis, and changes no skill. It exists to identify
*what to change to raise token efficiency* — not to change it.

**Follow-up in progress.** The forward-test candidate recommended below was made
concrete in `../routing-trim/` as *evidence-gated row routing* and is being
evaluated there under a pre-registered protocol. Its first gate did not refute
it. Nothing in this document is superseded.

Two earlier revisions of this note said the candidate had been refuted, on
ceilings of 7.94% and then 17.74–18.58%. Both were computed on models that were
not upper bounds, and both are withdrawn.

**It does not touch clause 1.** The replication question rounds 21 and 22 were
built for is still unresolved and nothing here bears on whether it replicates.
It does re-price what those rounds cost, which is a separate matter and is in
the first section.

Run with `review-efficiency/audit.py`. No new agents were run for it. Inputs are
pinned: `inputs.sha1` lists the 39 files whose bytes can move a number — the
round sheets and adjudication panels at base
`17248a03cc011ca48f998f6d77ae434aa4e1ffe8`, plus `design-audit/_data.py` (which
decides which claims are real) and the two files this PR derives,
`cost-ledger.tsv` and `_ledger.py`. `verify()` checks the path set and every
hash before a number is produced. Claim verdicts are imported from
`../design-audit/_data.py` rather than re-derived, so the two audits cannot
disagree about which claims are real.

## Two units, and what neither of them is

Nothing in this audit is a measured bill. These rounds ran on a Claude
subscription, whose weekly allowance is a **separate scheme from API metered
billing**, and no transcript records consumption against that allowance — it is
not recoverable here at all. Two units are used instead, both derived from
measured counts:

- **raw tokens** — what the API actually processed: uncached input + cache
  writes + cache reads + output, unweighted.
- **api-eq** — each count weighted by its price relative to one base input
  token, using Anthropic's published API ratios (cache write 1.25× at 5m TTL /
  2× at 1h, cache read 0.1×, output 5×). Read it as *"what this would price at,
  at API rates"*, never as an invoice.

They rank things differently, and where they do, this audit says so.

## The token figures in every previous round README are peak context

`subagent_tokens`, the number the task notification reports and every round's
cost table is built from, is **the final request's context size**. Reconciled
against the transcripts: median relative error **0.0009** over the 552 agents
that reported one, the notification running ~73 tokens higher. Summed over round
21's reviews it gives 4.52M against the 4.53M that README states, and over round
22's 12.46M against 12.5M — the identification reproduces the published figures.

It counts no re-sent context from earlier turns and **no output at all**. Per
round-22 review agent:

| measure | |
|---|---|
| `ctx_final` — what was reported | 83.1k |
| sent (uncached + cache writes) | 109.6k |
| re-sent (cache reads) | 286.1k |
| output | 25.9k |
| **raw processed** (sent + re-sent + output) | **421.6k** |
| **api-eq** (1× / 1.25× / 0.1× / 5×) | **294.9k** |

Round 22's 150 review agents therefore processed **63.2M tokens** and price at
**44.2M api-eq**, against the 12.5M its README states. All three are real
numbers about different things; only the first two describe work done.

Consequence outside this audit: the design audit priced future rounds at the
reported rate, so the designs it called unaffordable **process 5.1× more tokens
and price at 3.5× more at API rates** than it stated. Neither is a
subscription-allowance draw. Both point the same way, so its "do not spend"
conclusion is strengthened and nothing else about it changes.

| round | agents | sent | re-sent | output | api-eq | ctx_final | round total (api-eq) |
|---|---|---|---|---|---|---|---|
| 17 | 54 | 113.5k | 245.1k | 27.2k | 302.2k | 84.9k | 16.3M |
| 18 | 36 | 126.1k | 321.5k | 28.4k | 331.7k | 88.5k | 11.9M |
| 19 | 54 | 129.6k | 326.2k | 29.7k | 342.9k | 88.4k | 18.5M |
| 20 | 110 | 111.9k | 303.2k | 28.9k | 314.4k | 73.9k | 34.6M |
| 21 | 54 | 114.8k | 283.1k | 26.3k | 303.2k | 83.8k | 16.4M |
| 22 | 150 | 109.6k | 286.1k | 25.9k | 294.9k | 83.1k | 44.2M |

Evaluation machinery, separated from the production-shaped review agents:
458 review agents at 310.0k api-eq mean (142.0M), 24 adjudicators (2.3M), 57
clustering agents (10.6M), 5 seed panellists (0.6M), 28 other (8.5M). Two agents
were re-runs (round 20, arm W2, review 8, parts b and c). **No Codex or Ollama
agent ran in any of these rounds** — the eval harness is Claude-only. The
production skill does call Ollama for seed findings before the reviewers; that
costs zero Claude tokens and is not measured here.

**Provenance.** `cost-ledger.tsv` is per-agent and **measured**, recovered from
the session transcripts the rounds ran in. Nothing is a round-average estimate.
The transcripts are outside the repository and not redistributable; the ledger
carries counts only — no prompt, no reply, no file content — and records the
sha1 of the transcript set. `_ledger.py --verify` rebuilds it from the
transcripts and diffs all 572 rows across all 22 columns, exiting non-zero on
any difference.

## Where a review agent's tokens go

Content pulled in, as exact tool-result bytes, 150 round-22 agents:

| | kB | share |
|---|---|---|
| catalogue (digest, rules table, rule-detail pages) | 52.5 | 62.8% |
| the diff under review | 26.3 | 31.5% |
| harness (brief, `wc -l` handshake, writing output) | 4.5 | 5.4% |
| other | 0.2 | 0.3% |

The bytes are exact. **The share of processed tokens they carry is not**,
because content is written into the cache repeatedly as the conversation grows:
109.6k tokens ingested against 84 kB of content, ~5.0× what the content alone
would be at 3.8 bytes/token. This audit measures that ratio and does not
establish its mechanism — requests made more than 5 minutes after the previous
one, where the ephemeral cache has certainly expired, carry only 6% of the cache
creation, so plain TTL expiry does not explain it.

The two units disagree about what dominates, and the disagreement is the point:

| | api-eq | | raw tokens | |
|---|---|---|---|---|
| cache writes | 135.7k | 46.0% | 108.6k | 25.7% |
| output | 129.6k | 43.9% | 25.9k | 6.1% |
| cache reads | 28.6k | 9.7% | 286.1k | 67.9% |
| uncached | 1.0k | | | |

Output is 44% of api-eq and **6% of raw tokens**: the dominant line under API
pricing, a rounding error by volume. Cache traffic is the reverse. Any claim
that output is "as big a lever as the catalogue" holds *under API pricing* and
does not hold by volume, and has to carry that condition.

What survives both units: the catalogue is the largest single body of content
the reviewer reads, and neither lever is the reviewer count.

## Reviewer-count replay

Sub-sampling C(3,k) subsets is unbiased only for identical reviewers, which
parts a/b/c are. **This is a curve for k generalists; the shipped configuration
is three role-specialised experts, and no round measured the specialist curve.**
The three reviewers of one review share a brief and a catalogue, so a shared
prefix might have made the 2nd and 3rd cheaper — measured, it does not: round-22
means by position are a=309k, b=294k, c=282k, so k costs k×. Because k scales
every count in the same proportion, the ranking of the rungs is identical in raw
tokens; only the labels change.

Round 22, both arms (25 reviews each):

| | k | real claims | marginal | C+M non-defect | dup rate | severe miss | api-eq |
|---|---|---|---|---|---|---|---|
| W | 1 | 15.45 | 15.45 | 1.48 | 0.00 | 2.47 | 295k |
| W | 2 | 18.43 | 2.97 | 2.96 | 0.37 | 0.79 | 590k |
| W | 3 | 20.28 | 1.85 | 4.44 | 0.52 | 0.00 | 885k |
| W₂₃ | 1 | 15.63 | 15.63 | 1.71 | 0.00 | 3.12 | 295k |
| W₂₃ | 2 | 19.17 | 3.55 | 3.41 | 0.34 | 1.05 | 590k |
| W₂₃ | 3 | 21.48 | 2.31 | 5.12 | 0.49 | 0.00 | 885k |

Rounds 20 and 21 are in the script's output and have the same shape. The third
reviewer costs 295k api-eq for 1.85 further real claims in arm W — 159k per
marginal claim, against 19k for the first reviewer.

**Round 13 is shown separately and must not be pooled**: a different fixture
(F9), a different inventory, an earlier rule set, and one arm. Its k=1…6 curve
reproduces the numbers already published in `../README.md` to two decimals
(10.75 / 14.27 / 16.43 / 17.95 / 19.08 / 20.00 real defects; 0.73 / 1.46 / 2.19
/ 2.92 / 3.65 / 4.38 C+M non-defects), which is an independent check that this
audit's loader agrees with `round-13/measure.py`.

## Adaptive policies

A sequential policy may look only at the **first** reviewer's own output. The
observable is its Critical/Major finding count, which a runtime harness can see
without adjudication.

That statistic barely varies — 12 to 19, mean 15.1, sd 1.4 across 150 (review,
ordering) pairs, because the Finding Floor holds output shape nearly constant.
Its correlation with the claims reviewers 2–3 go on to add is **r = −0.51**:
negative, so escalating when the first reviewer finds *a lot* is backwards. The
correlation is partly mechanical (a reviewer who reports more has already
reached more claims, leaving fewer for the others), so it describes this sample
and is not evidence that the statistic is a good trigger. Both directions are
replayed.

| policy | real | C+M nd | api-eq | escalated | vs k=3 |
|---|---|---|---|---|---|
| always k=1 | 15.45 | 1.48 | 295k | — | −67% |
| always k=2 | 18.43 | 2.96 | 590k | — | −33% |
| always k=3 | 20.28 | 4.44 | 885k | — | 0% |
| 1, then 3 if r1 C+M ≤ 14 | 17.24 | 2.39 | 484k | 32% | −45% |
| 1, then 3 if r1 C+M ≤ 16 | 19.81 | 3.91 | 798k | 85% | −10% |
| 1, then 3 if r1 C+M ≥ 16 | 16.92 | 2.71 | 515k | 37% | −42% |
| ORACLE (not implementable) | 20.28 | 4.19 | 842k | 100% | −5% |

The oracle picks the smallest k that reaches everything k=3 reaches; it reads
the later reviewers' results to decide whether to launch them, so it bounds what
any first-reviewer rule could reach and is not a candidate. It saves 5% — but
that is **a ceiling on scheduling that preserves each review's k=3 real-claim
set exactly**, and on nothing else. Policies willing to lose coverage save far
more (k=1 saves 67%). The 5% is not a bound on adaptive scheduling in general.

## Rule-level ROI: not measured

`findings.tsv` has no rule column — the fields are `id, arm, review, part,
severity, target, file, title, what_is_wrong`. Nothing in the pipeline records
which catalogue row produced a finding, so unique-real-claim, non-defect and
trigger frequency per rule **cannot be computed from what was kept**, and this
audit does not estimate them.

What is recoverable is weaker: 914 of 2998 round-22 findings (30%) name at least
one rule ID somewhere in their text (most-mentioned: R49 ×252, R3 ×161, RT6
×114, RS3 ×105, RS2 ×88). A mention is not an attribution — a finding can cite a
rule it was not routed by, and a routed finding need not cite anything — so this
bounds what text mining could reach at best, not what the rules did.

Minimum telemetry to make it measurable, all inside normal operation:

1. the reviewer emits the rule IDs it routed to, once per run (it already
   extracts them with anchored `rg`; the list exists and is discarded);
2. each finding carries the ID it was written against, or `none`;
3. the run records its own token counts, so cost per rule is divisible.

(1) and (3) are free. (2) is one field in the output shape, and it is the only
one that turns a per-run list into a per-finding attribution.

## Pareto frontier, and what to test forward

Axes: real claims reached (up), C+M not-a-defect (down), api-eq tokens (down).
Every candidate scales all four token counts together, so the ordering is the
same in raw tokens and the frontier does not depend on the price weights.
Dominated = another candidate costs no more, reaches no less, is no noisier,
with at least one strict. Round 22, arm W, one fixture — descriptive of that
sample, not a claim about fixtures in general.

Every escalate-on-a-high-count policy is dominated by an escalate-on-a-low-count
one at similar cost, which is the sign of that correlation showing up in the
frontier. The fixed-k rungs all survive, k=3 included. **"Change nothing" is a
live option and nothing here argues against it.**

**The decision rule, applied literally, is degenerate.** Keep the non-dominated
candidates, take the largest token cut: that selects `always k=1` at −67%. k=1
is on the frontier only because the dominance test has no coverage floor, so a
candidate that loses 24% of the real claims (20.3 → 15.5 per review) is never
excluded — and a forward test of k=1 would measure what three rounds have
already measured consistently.

**What is actually worth running is not on the frontier and cannot be**: cutting
what each reviewer reads from the catalogue. It scores as no candidate here
because no round has ever varied it, so it has no coverage number to be
dominated on. The argument for it is the composition table: the catalogue is
52.5 kB of the 84 kB a reviewer reads (63%), and unlike k it is a *per-reviewer
multiplier* — it multiplies through whatever k is chosen. Output is a second
lever of the same shape but not of comparable size in general: 44% of api-eq
against 6% of raw tokens, so it is worth attacking under API pricing and close
to irrelevant by volume.

So this audit records two things rather than one:

- the rule's own answer, `always k=1`, and why taking it would be a mistake;
- the recommendation — a catalogue-routing trim at k=3 with the role split
  fixed — flagged as a **deviation** from the decision rule because it is
  unscored.

Choosing between them is the repository owner's call. If the trim is run, **the
coverage floor the frontier lacks has to be declared before it starts**, or the
forward test inherits the same defect.

## What this audit deliberately does not do

- It proposes no change to clause 1 and produces no evidence about it.
- It does not edit the catalogue, the skill, or the reviewer count.
- It reports no measured spend, and cannot: subscription-allowance consumption
  is not recorded anywhere this audit can read.
- It does not claim the catalogue trim would save coverage-neutral tokens. That
  is a hypothesis, and the reason to run a forward test rather than to skip one.
- It does not estimate per-rule ROI from rule IDs mentioned in finding text.
- It does not establish why cache creation runs ~5× the content read, only that
  it does and that TTL expiry does not explain it.
