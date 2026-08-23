# Round 24 protocol — does the Finding Floor's effect on F10 survive a clean confirmatory test?
(written before any run; no output read; no agent executed while writing it)

## The hypothesis

> **The Finding Floor reduces Critical/Major `not-a-defect` findings on F10.**

That is round 17's claim with two things changed and nothing else: the primary is
the `not-a-defect` class rather than the composite round 17 pre-registered, and
the design is fixed-n with no peek and an interval rule.

## Why this is round 24, with 23 left vacant

The design audit's recorded decision is **do not run round 23**
(`../../rule-precision/design-audit/README.md`) — clause 1 on F11, an
affordability decision that stands untouched by this round. Reusing the number
here would overwrite that record with an unrelated question on a different
fixture. The gap *is* the decision, so it stays, and this round takes the next
free number.

## What this round is for, stated as a grade and not as a hope

The purpose is **not** a shipping decision — the floor ships either way, and
nothing below licenses removing a clause. The purpose is to settle what grade the
Finding Floor's own effect carries. The arithmetic, against the ledger's key
(`../../README.md`):

- **Round 12, F9** measured the effect cleanly and pre-registered its rule as
  *"primary drops by at least 1.38"* (`round-12.md`, "Pre-registered
  predictions") — the MDE pressed into inference duty that
  `../../rule-precision/methods.md` §2 names as the error. F9 is therefore
  clean **MEASURED** evidence and **not** a confirmatory fixture. Its data
  cannot be promoted by re-analysis: a rule invented after the data exists is
  not the rule that was registered.
- **Round 17, F10** is **qualified replication evidence** — its n-extension was
  authorised in sight of the arm table and its literal sd gate still fails at
  n = 9.
- **This round, if the rule below fires: CONFIRMED (F10)** for the whole-floor
  contrast on the `not-a-defect` metric.

That is a claim the series does not yet have. Round 20 already carries
**CONFIRMED (F10)** on the same metric and the same fixture, but for a different
contrast — W − W₂₃, the *clause 1* effect with clauses 2 and 3 present. W − N is
the floor against its absence. The two are different quantities and the write-up
must not merge them.

**REPLICATED remains out of reach and out of scope.** It needs a second fixture
confirmed under this same rule and this same contrast. No spend in this round
moves toward it, and the write-up may not describe this round as a step toward
it.

## Why the `not-a-defect` class, and why not the composite at a larger n

Round 17's pre-registered primary was the composite — Critical/Major findings
whose claim is not adjudicated `real`, which pools `not-a-defect` with `wrong`.
Three facts decide the choice:

1. **§4.2 registered the split forward.** The monograph's own words are *"the
   lesson is registered forward, not applied backward: pre-register the split
   before leaning on it"* (`../../../paper/04-finding-floor.md`). This round is
   that registration. Choosing the composite here would leave the debt unpaid
   for a second time.
2. **The floor targets one of the two classes.** Clauses 2 and 3 address
   ungrounded requirements and preferences. Neither addresses misreading, and
   the composite counts misreadings.
3. **On F9 the two metrics coincide** — F9 contains no Critical/Major misread at
   all — so choosing the split does not break comparability with round 12. On
   F10 they diverge by the inventory's two `wrong` claims.

The composite is also the far more expensive quantity to test, because it carries
both a smaller effect and a larger variance. Under the same inflation policy as
the table below (F10's own per-arm sds, W 1.944 / N 0.726, against the composite
effect of 2.11):

| n/arm | power at ×1 | ×1.5 | ×2 | review agents |
|---|---|---|---|---|
| 12 | 91% | 59% | 38% | 72 |
| 20 | 99% | 83% | 59% | 120 |
| 25 | 100% | 91% | 69% | 150 |

The composite reaches at n = 25 the margin the primary reaches at n = 12, for
**twice the review agents**, and leaves the two-fixture shortfall exactly where
it was. Grade names are not worth that. **The composite is pre-registered here as
a SECONDARY, it fires no rule, and its grade is not promoted whatever it shows.**

## Arms

- **W** — the catalogue at `bc0f966`: the Finding Floor present and wired by its
  digest line.
- **N** — identical except the `### Finding Floor` section is cut from
  `common-rules.md` and the digest paragraph routing to it is removed.

Byte-reproducible from `bc0f966` and `../../rule-precision/round-17/arms.diff`.
**Identical to round 17's arms**; the catalogue is not touched for this round.
`diff -rq` over the two snapshots must return those two files and nothing else,
verified before the first batch.

Three identical generalists per review, as in round 17. The shipped skill runs
three specialised roles; that configuration is **not** tested here and no result
below transfers to it.

## The fixture, and the material frozen before any agent runs

**F10 is reused unchanged.** Its claim inventory and verdicts are fixed before
the first review, pinned by blob hash rather than commit id because a squash
merge rewrites ids:

```
4fc70b4aa80f42d5148a96934a51dbbf9d6346b2  rule-ablation/fixtures/F10-webhooks.diff
64310da334af3272b572ab6a125f53dd4921487c  rule-precision/round-16/seed/inventory.tsv
fd7bea9460bcee551e0da0d9a45901e64f51bf81  rule-precision/round-17/clusters.tsv
b22adfb2860af871eadb6a5232d5de7da436946f  rule-precision/round-17/adjudications/adjudicator1.tsv
e16783e5c8e12ddabafac108b7c905482aa3b8d4  rule-precision/round-17/adjudications/adjudicator2.tsv
0f3489b16543f6507c7c0e4dcaa3d8b925fa39ef  rule-precision/round-17/adjudications/adjudicator3.tsv
3ef74fa934a9c70e0b8f051dd13a99306ad7fe98  rule-precision/round-17/measure.py
3d89a92362e6da5c57c754b6ce1e983e5b0fe7b3  rule-precision/round-17/arms.diff
54a19f0272172cebfbf4ae7dd3b5ca532a70c6a6  rule-precision/round-17/briefs/brief-W.md
17fca9f9ef9deaf3b4e9709b2cce4e8f08d28527  rule-precision/round-17/briefs/brief-N.md
41afbb4e4d0ca1089c933b32d47b95fde43e659b  rule-precision/round-17/briefs/brief-cluster.md
46d24719d7054ea52809891ccca6bc57ffc1dadf  rule-precision/round-17/briefs/adjudicate-brief.md
```

Verified with `git hash-object <path>` before the first batch. The briefs are
reused verbatim: a reworded brief is a different instrument.

`round-16/seed/inventory.tsv` supplies the 64 seed claims — generated
independently before any arm ever ran, which is what makes F10's inventory
stronger than F11's. `round-17/clusters.tsv` and the three sheets supply the 25
claims round 17 added and their verdicts. `round-17/measure.py` is pinned because
it encodes how they combine.

**How this round's findings meet that inventory**, unchanged from round 22's
rules:

- A finding joins an existing cluster on **semantic match** — same assertion
  about the same code, one change resolves both. Wording need not match.
- When it joins, the cluster's **id and canonical claim text are copied verbatim,
  byte for byte.** A reworded claim is a different claim and the recorded verdict
  stops applying to it. Checked mechanically at merge.
- Only a finding matching no existing claim opens a new cluster, adjudicated
  afterwards by the pinned standing brief.
- **Reported, not assumed:** the count of new claims and their share of the
  primary, defined per arm as *C+M findings assigned to a claim new in this round
  and adjudicated `not-a-defect` ÷ that arm's total primary findings.*

The prediction — not a premise — is that new claims will be fewer than round
17's, since F10's claim space has now been through two rounds.

**The size of the frozen inventory, stated once so no later step has to infer
it: 94 claims — 64 seed + 30 added by round 17 — of which 64 `real`, 28
`not-a-defect`, 2 `wrong`.** Round 17 added 25 in batch 1 and 5 more in the
declared batch-2 extension (`round-17/README.md`); `measure.py`'s docstring still
says "the 25 this round added", which is that file's own pre-extension wording
and not a second count. `measure.py` prints 30 at run time from `clusters.tsv`.
Nothing is edited here — the file is pinned by hash above, and rewording it after
quoting its hash would defeat the pinning.

## n = 12 per arm, fixed before any of this round's data exists

**2 × 12 × 3 = 72 review agents.** Round 17's nine reviews per arm are **not
reused and not pooled**: their value on this metric has been read, and reading it
is what motivated this round.

The plug-in is **F10's own per-arm variance on this round's primary** — W sd
1.202, N sd 0.601, Welch se 0.448 at n = 9 — and not F9's. Round 17 borrowed
F9's pooled sd 1.217 and recorded that it did not transfer; repeating that
borrowing would repeat that failure. `round-24-power.py` reproduces the table:

| n/arm | power at ×1 | ×1.5 | ×2 | ×2.5 |
|---|---|---|---|---|
| 9 | 100% | 95% | 78% | 59% |
| **12** | **100%** | **99%** | **90%** | **73%** |
| 15 | 100% | 100% | 96% | 83% |
| 20 | 100% | 100% | 99% | 93% |

Power against round 17's observed difference of 2.67, with **both** arm sds
inflated by the column factor. The inflation is the point: both sds rest on nine
reviews and are imprecise in their own right, and round 22 is the worked example
of a plug-in variance the fresh batch declined to honour. n = 9 would be
defensible on these numbers; **n = 12 lifts the ×2 column from 78% to 90% for a
third more agents**, and that margin is the whole justification.

The MDE does one job here — choosing this n, before the run
(`../../rule-precision/methods.md`, quantity 1). It appears nowhere after.

## No observed-MDE gate, deliberately

Rounds 21 and 22 carried a gate that recomputes the MDE from the observed sds
and compares it against a pre-registered ceiling. `methods.md`'s 2026-08-23
amendment classifies that as an **inference-eligibility** quantity: it can only
fire once every observation exists, when the spend is already committed. Round 22
is what that costs — the gate fired at 1.41 against 1.33, and 150 agents became
descriptive text.

**This round registers no such gate.** With a fixed n, no peek, and an interval
rule, a variance larger than the plug-in widens the interval, the interval fails
to exclude zero, and no claim is made. That is self-limiting and needs no second
mechanism to invalidate the round on top of it. The cost of the choice is stated
plainly: if the variance comes in high, this round will report a wide interval
rather than reporting "underpowered", and **a wide interval that crosses zero is
not evidence against the effect** — the reading table below fixes that in
advance.

## The one gate: reachability, before any arm runs

Round 7's lesson is that ablating a section nobody reads measures nothing, and it
found the Finding Floor's predecessor unread by four of four reviewers. Before
any arm runs, **3 agents take the W catalogue over F10 and their tool-call traces
— not their output — are checked for the digest extraction.**

| result | action |
|---|---|
| 3/3 executed | proceed |
| 1–2/3 | **stop.** W is an uncontrolled mixture; investigate the wiring |
| 0/3 | **stop.** Wiring investigation; the ablation would measure nothing |

Only the traces are inspected. No finding, severity, or count from these three
agents is read, and none of them enters any metric.

### Technical-failure exchange rule, fixed here

A review agent may fail for reasons that are not review outcomes: window
exhaustion, tool error, truncated or unparseable output, an orchestration fault.

- **Before any of its output has been read**, a failed agent is replaced by a
  fresh agent at the same review index, arm and part. The failure and its cause
  are logged. Replacements are counted and reported.
- **If any of its output has been read** — including a partial extraction — the
  replacement is not permitted. The whole review index is voided **in both arms**
  so the arms stay balanced, and **n falls to 11 rather than being backfilled.**
  Backfilling an index whose output was seen is the round-17 defect this round
  exists to avoid.
- A shortfall in n is reported as a deviation with its cause. It is never a
  reason to add an index.

## Metrics

1. **PRIMARY (confirmatory)** — Critical/Major findings whose claim is
   adjudicated `not-a-defect`, per review. Identical to round 20's confirmatory
   metric, deliberately, so that grades across rounds compare on one quantity.
2. **SECONDARY (exploratory)** — the composite: Critical/Major findings whose
   claim is not adjudicated `real`, per review. Round 17's pre-registered
   primary. Reported with its interval, labelled exploratory, **grade not
   promoted**.
3. **CONTROL (fires no rule)** — distinct real claims reached per review. If the
   floor works by silencing reviewers, the primary falls and this falls with it.
   A flat control is **not** non-inferiority and no wording may call it "coverage
   preserved"; the phrase is *no detectable change*, and there is no declared
   margin behind it.
4. **RECORDED** — `wrong` claims per review; total findings written; the
   Critical/Major-to-Minor ratio; new claims and their per-arm share of the
   primary; per-agent tokens; replacements; the execution record of §"What
   cannot be held the same"; the bridge agreement below; and:
   - **Round 12's F9 data re-analysed as a Welch interval.** Zero agents, and
     pre-registered *here* so that it cannot be computed after this round's
     result is known and presented as corroboration. It is **exploratory and
     unpromotable** — round 12's registered rule was not an interval rule and
     retro-fitting one does not make F9 a confirmatory fixture.

## Inference

**Welch's two-sample t interval, independent groups.** The arms share review
indices and nothing else; round 19 measured that directly. The nominal
index-paired analysis is computed and reported as a **sensitivity analysis**,
never as the primary.

> **CONFIRMATORY RULE. The Finding Floor's effect on F10 is confirmed if the
> two-sided Welch 95% CI for W − N on the PRIMARY lies entirely below zero.**

The observed difference is **not** required to exceed the MDE. That was round
19's error and `methods.md` records the separation.

**Fixed n. No peek. No extension.** No arm mean, no difference, and no per-review
value is computed or looked at until all 24 reviews have landed and the
adjudication of new claims is complete. Nobody who could authorise a change to
this protocol sees a partial table. If n falls short by the exchange rule above,
the round is analysed at the n it has.

## What is deliberately the same, and what cannot be held the same

The intent is that **nothing about the instrument changes**: same fixture, same
arms, same briefs, same inventory, same reviewer configuration, same metric
machinery. What differs is the execution environment, and the honest statement of
that difference is narrower than it is tempting to write.

**Round 17 recorded no model identifier.** No round in this series did — the
ledger's "one model epoch" is an assertion about dates, not a pinned fact. What
is on record is that round 17's 54 review agents all ran on **2026-08-08**,
between 15:24 and 16:26 UTC by the cost ledger's timestamps, and were committed
2026-08-09; and that this repository adopted Opus 5 prompting guidance on
2026-07-27 (`00a1eff`), which is
**circumstantial evidence that the generation was the same and is not
identification.** The harness version and the agent system prompt of that date
are likewise unrecorded.

Consequently this round **cannot claim that the model epoch is the only thing it
changed.** What it changes is the entire unrecorded execution environment —
model snapshot, harness, system prompt — of which the model generation may or may
not be a part. This round records its own (below) so that a future round can make
the narrower claim this one cannot.

> **Fixed in advance: a null is not identifiable.** If the interval crosses zero,
> this round **cannot distinguish** (a) round 17's result having been an artifact
> of its peeked extension from (b) the effect not surviving whatever changed in
> the execution environment since 2026-08-09. Both readings remain open, the
> write-up states both, and neither is chosen. Nothing about a null licenses
> removing a clause.

**Recorded before the first batch and published with the result:** the executing
model identifier for reviews, clustering and adjudication; its stated training
cutoff; the harness version; and the date.

## Contamination check, and its residue

F10's diff and round 17's numbers are committed in this public repository, dated
2026-08-09. If the executing model's stated training cutoff precedes that date,
pretraining exposure to the fixture and to round 17's arm table is excluded, and
the comparison is recorded as the evidence rather than asserted.

Two limits survive that check and are stated rather than resolved:

- The check covers pretraining. A model that has encountered this repository by
  another route is not excluded by a cutoff date.
- The review brief supplies the diff and the catalogue; it names neither the
  round, the arms, this repository, nor the existence of an experiment. That
  reduces the chance of recognition. It does not exclude it.

## The bridge measurement

Round 17's verdicts were produced by a panel of that date; this round's new
claims are adjudicated by a panel of today's. Without a bridge, the primary mixes
two adjudication generations silently.

- **3 agents, blind**, under the pinned `adjudicate-brief.md`, re-judge a
  **stratified sample of 24 claims** from the frozen 94-claim inventory. The
  strata are fixed here, not chosen later: **both 2 `wrong` claims, 15 of the 64
  `real`, and 7 of the 28 `not-a-defect`** — the two large strata in proportion,
  rounded to the nearest claim. Selection within a stratum is by sorting cluster
  ids and taking every *k*-th, so the sample is reproducible from the pinned
  files and no judgement enters it. Claims are shuffled, counts withheld, and the
  original verdicts are not shown.
- **Reported:** raw agreement with the frozen verdicts, overall and per class.
- **The frozen verdicts are not rewritten.** They remain the measurement standard
  for the primary, exactly as the append-only rule requires.
- **Storage is outside the measurement path.** `round-17/measure.py` reads
  `round-16/seed/inventory.tsv` and `<round>/adjudications/*.tsv`; the bridge
  therefore lands in `round-24/bridge/`, never in `round-24/adjudications/` and
  never in `inventory.tsv`, so no bridge byte can reach a primary number.
- **It fires no rule.** Agreement at n = 24 has a wide interval, and a low
  agreement rate would be a finding about panel drift to report, not a reason to
  re-verdict anything or to void this round.

## How the result will be read — fixed in advance

| PRIMARY, Welch 95% CI for W − N | reading |
|---|---|
| entirely below zero | **the Finding Floor's effect on F10 is CONFIRMED.** Round 17's direction and size held under a fixed-n, no-peek design |
| crosses zero | **no effect was detected under this design.** The interval, not the MDE, states which effect sizes remain compatible. This does **not** show the effect absent, does **not** establish it smaller than any value, and does **not** identify which of the two null causes above applies |
| entirely above zero | recorded as observed, with no story attached |

No row licenses an equivalence claim. No row licenses deleting a clause — that
would need a non-inferiority design with a declared margin, which this is not.
No row changes what ships.

## Publication, pre-registered

**The result is published whichever way it comes out**, in the round README, in
`../../README.md`'s ledger, and in `../../../paper/04-finding-floor.md`. A
confirmed result upgrades the floor's grade to CONFIRMED (F10) on the
`not-a-defect` metric; a null leaves the ledger's current wording — MEASURED with
qualified replication evidence — standing, with this round's interval added
beside it and the non-identifiability recorded.

Publishing only on success is the selection bias this line exists to avoid, and
committing to it before the run is the only time the commitment is worth
anything.

## Cost

Per-agent figures are round 17's own **measured** means from
`../../rule-precision/review-efficiency/cost-ledger.tsv` (54 review agents,
385.8k raw / 302.2k api-eq each); ancillary roles use that ledger's measured
means for the corresponding roles.

| | agents | raw | api-eq |
|---|---|---|---|
| reachability probe, W only, pre-run | 3 | 1.16M | 0.91M |
| **reviews, 12 × 2 arms × 3** | **72** | **27.78M** | **21.76M** |
| clustering, one per changed file — F10 has 8 | 8 | 3.71M | 1.49M |
| merge and verbatim-claim check | 2 | 1.14M | 0.61M |
| adjudication, new claims only | 3 | 0.53M | 0.29M |
| bridge re-adjudication | 3 | 0.53M | 0.29M |
| **total** | **91** | **≈34.9M** | **≈25.3M** |

**The headline 27.8M is review agents alone.** The round costs ≈34.9M raw.
Ancillary per-agent means are borrowed across rounds and are estimates; the
review line is measured on this exact configuration and this exact fixture.

Reviews are batched **one review index at a time** (2 arms × 3 parts = 6),
confirmed landed before the next, across twelve batches spanning several
five-hour windows. `../../rule-precision/preflight.py` runs before every batch
and the round pauses rather than losing agents to a full window.

## Working rules carried in

- `../../rule-precision/preflight.py` before every batch. Round 20 lost fourteen
  agents to the five-hour window by not asking.
- `../../rule-precision/await_outputs.py` for every wait. A `DONE` is not
  evidence, and one `ls` cannot tell "not yet" from "never".
- Extraction by `../../rule-precision/extract.py`; heading count reconciled
  against parsed count per file. Clustering split by
  `../../rule-precision/split_clusters.py`, which reads the changed-file set from
  the fixture rather than from an extension list.
- Existing claims reused verbatim, checked mechanically at merge.
- **Changed from round 22:** sub-agent models are not *varied* within the round,
  and the identifier in force is **recorded**. Round 22's rule was "sub-agent
  models are not changed", which silently assumed a fact no round wrote down.

## What this cannot settle

- **Fixture-independence.** One fixture, whichever way this comes out. REPLICATED
  is not reachable from here.
- **The specialised configuration.** Three identical generalists are tested; the
  shipped skill runs three specialised roles.
- **Which clause carries the effect.** That is the W − W₂₃ contrast, and round 20
  already holds it on F10. This round does not re-open it.
- **Clause 1 on F11.** Untouched. The design audit's "do not run round 23" stands.
- **Whether a null licenses removing anything.** It does not.
- **What changed in the execution environment since round 17.** Not recorded then,
  not recoverable now.
- **The adjudication standard.** "Judge the diff as a real PR where everything not
  shown exists and works" is what makes an ungrounded requirement a non-defect. A
  reviewer who wants those questions raised regardless would call this floor a
  regression, and this design cannot tell them they are wrong.
- **No fixes are applied.** The fixture is a diff.
