# 5. Token accounting: the number everyone reports is not consumption

Every cost decision in this series — which rounds to run, which candidates to
price, when to stop — depends on knowing what a review costs, and for most of
the series that number was wrong by a factor of five. This chapter is the
correction (`../evals/rule-precision/review-efficiency/`): retrospective,
descriptive, no new agents, and load-bearing for Chapters 4 and 6, whose
spend and refutation figures are all denominated in its units.

## 5.1 The identification: what `subagent_tokens` actually is

The number the task notification reports — and every round README's cost
table was built from — is **the final request's context size**, not
consumption. Reconciled against the session transcripts of the 552 agents
that reported one: median relative error **0.0009**, the notification running
~73 tokens high; summed over rounds 21 and 22 it reproduces the published
4.53M and 12.5M (MEASURED;
`../evals/rule-precision/review-efficiency/README.md`). The identification is
the chapter's one strong claim: the reported number is peak context, to
within a tenth of a percent, across every agent that reported one.

What peak context omits is everything an agentic loop does: it counts no
re-sent context from earlier turns and no output at all. For a round-22
review agent the shapes diverge by 5.1× (MEASURED; round-22 values):

| per round-22 review agent | tokens |
|---|---|
| `ctx_final` — what was reported | 83.1k |
| sent (uncached input + cache writes) | 109.6k |
| re-sent (cache reads) | 286.1k |
| output | 25.9k |
| **raw processed** | **421.6k** |
| **api-eq** | **294.9k** |

**93.6% of raw processing is transport** — material re-sent across a mean of
7.6 requests — which is the single number that shaped Chapter 6: a cost that
is mostly re-sending invites exactly the three candidates that chapter
refutes.

## 5.2 Two units, and what neither of them is

Nothing in this accounting is a bill. The rounds ran on a subscription whose
allowance is a separate scheme from API metering, and no transcript records
draws against it. Two derived units are used instead:

- **raw tokens** — what the API processed: uncached input + cache writes +
  cache reads + output, unweighted;
- **api-eq** — the same counts weighted by published price ratios (cache
  write 1.25× at 5-minute TTL, 2× at 1-hour; cache read 0.1×; output 5×) —
  *what this would price at API rates*, never an invoice.

The units rank interventions differently where transport dominates — a
vanished request is mostly cheap cache reads in api-eq — and where they
disagree, the source audit says so. Chapter 6's bar is defined on raw.

## 5.3 The restatement, scoped to the rounds it covers

Costs are restated **for rounds 17–22 only** — the rounds whose review
transcripts were recovered into the evidence archive; earlier rounds keep
their reported final-context figures, labelled as such (MEASURED; the audit's
per-round table):

| round | agents | api-eq / agent | round total (api-eq) |
|---|---|---|---|
| 17 | 54 | 302.2k | 16.3M |
| 18 | 36 | 331.7k | 11.9M |
| 19 | 54 | 342.9k | 18.5M |
| 20 | 110 | 314.4k | 34.6M |
| 21 | 54 | 303.2k | 16.4M |
| 22 | 150 | 294.9k | 44.2M |

Round 22's 150 review agents processed **63.2M raw tokens** against the 12.5M
its README states; the two F11 rounds together processed **≈86M raw
(≈61M api-eq) in review agents alone** — the figure Chapter 4's stopping
decision is denominated in. The evaluation machinery around the reviews is
separated in the source: 458 production-shaped review agents at 142.0M api-eq
in total, against 2.3M for adjudicators, 10.6M for clustering, 0.6M for seed
panels — the instrument is cheap relative to what it measures.

## 5.4 What the correction changed downstream

The design audit had priced future rounds at the reported rate, so the
designs it called unaffordable **process 5.1× more and price 3.5× higher**
than it stated — both errors pointing the same way, so its do-not-spend
conclusion is strengthened and nothing else about it changes (the audit
records this consequence itself). Forward-test pricing in Chapters 1 and 6
inherits the corrected per-agent figures: ≈222 agents at the plug-in sizing
is ≈94M raw / 65.5M api-eq; ≈294 at the conservative sizing is ≈124M / 86.7M
(`../evals/README.md`, "what deciding costs").

## 5.5 What this chapter claims, and no more

The identification — reported figures are final-request context — is
established across the 552 reporting agents to median relative error 0.0009.
The 5.1× multiplier, the 421.6k per-agent shape, the 7.6-request mean and the
93.6% transport share are **round-22 values**, not constants of the system;
rounds 17–21 have their own per-agent figures above, and rounds before 17
were not restated at all. The units are models of cost, not bills; the
subscription draw remains unrecoverable; and every figure re-runs from the
archived transcripts under the manifests of §7.2.5.
