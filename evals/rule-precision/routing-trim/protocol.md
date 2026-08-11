# Protocol — evidence-gated row routing

**Written before any savings figure was computed.** Structural facts about the
current routing were measured first (they are needed to specify the
intervention at all) and are recorded below; nothing about how much a trim
would save was calculated before this document was fixed.

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
**`gate0.py` is authoritative** and prints marginally different values (18.0 /
18.9 / 21.7 kB / 3.0 / 17.1%) because it filters agents slightly differently.
The pre-registration table is left as written rather than edited after the
fact:

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
is an unreachable ideal: it assumes every row is speculative. It is computed
exactly, not estimated — for each agent, locate the request at which the row
content entered the context and subtract those tokens from that request's cache
creation and from every subsequent request's cache read.

Two figures are pre-registered, and both will be reported:

- **floor** — only the first ingestion is saved (no downstream effect);
- **ceiling** — the ingestion plus the removal from every later request that
  re-sent it.

**If the ceiling is below 20% of raw processed tokens, the line of work stops
here.** No proxy, replay, telemetry, or forward test can rescue an intervention
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
