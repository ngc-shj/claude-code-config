# 7. The method, stated as reusable gate design

This chapter states the method the measurement series converged on, as design
rules a reader could apply to their own review system. Two limits govern
everything in it. First, the rules were extracted from one series — one
repository, one model epoch, and authored fixtures whose count differs by
line: eight behind the ablation conclusions, three (F9, F10, F11) behind the
precision conclusions, and **one** (F11) behind every replay figure — and
nothing here claims they are generally valid; what would make them portable is
Chapter 8's open obligation, not this chapter's assertion. Second, the chapter describes **two method
families that are deliberately not merged**, because they answer different
questions and neither did the other's job:

- **identification** — claim-level adjudication, same-batch controls, and
  inference separated from power. This family identified the Finding Floor's
  effect and bounded what remained open (Chapters 3–4).
- **refutation** — causal replay over pinned session transcripts. This family
  refuted three optimization candidates before any forward test (Chapter 6).
  It identified nothing and cannot: its verdicts are bounds, not effects.

A **gate**, throughout, is a decision procedure that can only **terminate a
line of work or permit the next step** — never confirm, never ship. The
asymmetry is the point: a gate that a candidate survives has established
nothing about the candidate except that the cheapest available refutation
failed.

A note on grades, because this chapter is bound by the writing rules it cites.
The numbers here are **method exhibits** — probe counts, retractions, gate
firings, amendment tallies — documenting what a procedure caught, not what an
intervention did. Each is a process record from the cited round document or
protocol and carries the grade **MEASURED** unless tagged otherwise. **No new
effect estimate is introduced here**; where the chapter names the series'
substantive results in passing, it names them with their ledger grades — the
Finding Floor's effect (REPLICATED), the three candidate refutations
(REFUTED) — and their full statements live in Chapters 2–6.

## 7.1 Identification under pre-declared quality constraints

### 7.1.1 The unit of measurement is an adjudicated claim, not a finding

Review replies do not share a vocabulary: forty reviewers can report one defect
forty ways, and a finding count rewards verbosity. The series' unit is the
**claim** — findings clustered when a single change resolves both *and* they
assert the same thing about the same code, then adjudicated `real` / `wrong` /
`not-a-defect` by a panel that is **blind to popularity**: claims are shuffled
and member counts withheld, so a claim forty reviewers made looks exactly like
a claim one reviewer made
(`../evals/rule-precision/README.md`, Method; adjudicator agreement 84–94%).

Three rules make the inventory reusable across rounds rather than rebuilt per
round:

1. **The brief is held fixed**, with only the round-varying slots open
   (`../evals/rule-precision/adjudication-brief.md`). A verdict recorded in one
   round then means the same thing in the next.
2. **Old verdicts are never re-adjudicated.** Only genuinely new claims are
   judged. Re-judging would let the standard drift between arms and rounds.
3. **Convergence is checked, not assumed.** The inventory earned reuse when 599
   new findings produced six claims the earlier round had not recorded
   (MEASURED; `../evals/rule-precision/README.md`, Round 12).

The panel's standing assumption — judge the diff as a real pull request into a
working codebase where everything not shown exists and is correct — does most
of the work in the `not-a-defect` verdict and is applied identically to both
arms. What that buys is bounded: holding the explicit standard fixed prevents
*drift* in the standard between arms and rounds. It does not make the contrast
unbiased — an intervention that changes the **kinds** of claims reviewers
produce meets the panel's per-kind error rates differently, and measurement
invariance across arms was not tested. Panel error therefore sits in the
contrasts in principle, not only in the absolute levels, and every number in
this monograph inherits the assumption either way.

### 7.1.2 Controls: same batch, one variable, wiring before content

- **Same-batch comparison.** Arms are compared within one generation batch,
  never across batches. The series' standing exhibit is a saturation claim that
  read 1/8 → 8/8 across batches and shrank to something honest when the
  control ran in-batch
  (MEASURED; `../docs/archive/audit/2026-08-04-rule-ablation.md`, Round 9).
- **One variable per round.** Arms differ in shipped files, never in prompts;
  where a round tests a structure, both arms are rendered from one template so
  the manipulation is the role line and nothing else
  (`../evals/rule-ablation/README.md`, Arms).
- **Reachability precedes ablation.** Before a section is credited or debited,
  a tool-call-trace probe establishes that reviewers read it at all. The Remedy
  Floor as merged was read by zero of four probed reviewers — ablating it
  against absence would have compared two arms that both lacked it in practice
  (MEASURED; `../evals/rule-ablation/README.md`, Round 7). The general rule: **a
  documented control that nothing routes to is dead text, and measuring its
  content before its wiring measures nothing.**

### 7.1.3 Instruments: fixed before the run, independent of the treatment

- **Oracle before run.** What the review must state is written down before any
  review runs; fixing it afterwards is fitting the oracle to the data
  (`../evals/rule-ablation/README.md`, Protocol).
- **Rubric independence.** A remedy rubric derived from the rule's own text
  scores the rule-holding arm against the document it was handed; part of the
  measured advantage is then definitional. The series rebuilt its rubric with
  panels that never saw the rule, and the **blinded re-score** of the old
  fixes against it moved results in both directions — it retained the F6 gap
  and reduced the F9 gap (MEASURED; `../evals/README.md`, ledger; the ablation
  audit, Rounds 5 and 6.5). Self-scoring had erred both ways, which is the
  argument for blinding stated as an observation.
- **Saturation check before reuse.** An instrument at its ceiling returns a
  null whatever the arms do. Round 11 caught its rubric saturated (9.00/9)
  before reuse and rebuilt it, frozen, before the first arm ran
  (MEASURED; `../evals/rule-ablation/README.md`, Rounds 10–11).
- **Structured extraction, not per-round regexes.** The heading regex lost
  findings twice, both times in the arm whose treatment makes reviewers invent
  heading shapes — a loss correlated with the arm is a bias, not noise
  (`../evals/rule-precision/README.md`, `extract.py`).

### 7.1.4 Power and inference, separated

`../evals/rule-precision/methods.md` is the normative statement; the design
rules are four:

- **Before the run, the planned MDE is an investment quantity.** Computed
  from a borrowed sd, it answers "is this n worth running?" and gates the
  spend: if it exceeds the effect the round is sized for, the round is resized
  or abandoned before an agent runs.
- **After the data, before the comparison, the observed-MDE sensitivity gate
  is an inference-eligibility quantity.** Recomputed from the observed sds and
  checked against a pre-registered ceiling — run first and alone, before any
  arm difference is looked at — it decides whether confirmatory inference is
  licensed, not whether the round should have run: by the time it can fire,
  the spend is committed. Round 22 is the executed example (ledger: OPEN): the
  gate fired after all observations existed — 25 reviews per arm, each a
  three-agent review, 150 agent outputs in all — the pre-registered response
  was to report the primary underpowered and **not** extend n, and everything
  below the gate is descriptive. The two MDEs are the same formula at
  different times doing different jobs, and conflating them is how a
  spend-gate quietly becomes a result-gate.
- **The test and interval are observation quantities.** An observed effect
  does not have to exceed the MDE to be significant; requiring that is a
  stricter test than α = .05 applied by accident. Round 19 is the worked
  example (MEASURED; `../evals/rule-precision/methods.md`) — CI
  [−3.76, −0.24] excluding zero, and a pre-registered rule that demanded more
  and was wrong to; the record keeps both statements and does not rewrite the
  rule after the fact.
- **Confirmatory is a label about timing, not about strength.** A comparison
  is confirmatory only if its decision rule predates the data and is applied
  as written; everything else is exploratory and stays exploratory, however
  strong — Round 22's below-zero exploratory subtype is reported *because it
  was pre-registered as exploratory*, and reading it as the finding after the
  confirmatory gate fired is the substitution the structure exists to prevent
  (`../evals/rule-precision/round-22/README.md`).

Nulls are reported as **"no detectable difference"** with the MDE or power
caveat beside them, never as equivalence. Where a size would matter, the
protocol pre-registers a SESOI — fixed by what the intervention is for, not by
the variance of a previous batch — and reads the interval against it.

## 7.2 Refutation by causal replay

The second family prices an intervention's *perfect form* against transcripts
of the system as it ran, at zero new review-agent cost. Its logic is an
asymmetry: an oracle bound that fails the bar refutes every implementable form
below it, while a bound that clears the bar establishes nothing — so the replay
can only terminate work or permit the next, more expensive question.

### 7.2.1 The pre-registration contract

Each candidate gets a protocol that fixes, before any figure exists: the
intervention **verbatim** (a reformulation voids the protocol and requires a
new one); the gates in order, each able only to terminate or permit; the
decision bar and which side of it decides; and the statement that **no gate
permits shipping** (`../evals/rule-precision/routing-trim/protocol.md` and its
two successors). Where a later design choice could leak information — the
dev/holdout split of the compiler gate — it is fixed **in its own commit,
containing no code and no measurement**, so the repository's history evidences
the ordering instead of the author asserting it
(`../evals/rule-precision/packet-compiler/protocol.md`, second amendment).

The leak the split exists to close is worth stating generally: **the author is
an input.** Restricting a tool's runtime inputs does not stop the scoring set
reaching it through whoever writes the tool; only a holdout the author cannot
have fitted to can score it.

### 7.2.2 Bound discipline

Every quantity in a replay verdict is classified by direction, and the
classification decides what it can do:

- an **upper bound** on the saving, below the bar, **refutes**;
- a **lower bound** below the bar decides **nothing** — a real implementation
  could save more;
- a **witness** — one arrangement the intervention can reach, priced with a
  cost it would not actually pay — above the bar shows the perfect form clears
  it, and below the bar decides **nothing**. A gate built on witness
  arithmetic has no refutation path at all, and says so
  (`../evals/rule-precision/packet-compiler/protocol.md`, first amendment).

Two working rules keep the classification honest. **Before publishing a
refutation, ask what arrangement would have saved more**: the series' verdicts
crossed the bar twice in one protocol because a quantity called a ceiling was
not one, and both crossings were found by exactly this question
(`../evals/rule-precision/request-batching/protocol.md`, amendments one and
two). And **every remaining looseness is measured with its direction stated,
and the dangerous direction is bounded, not banished**: a looseness that
understates the saving gets a quantified ceiling, and the refutation stands
only if the figure remains below the bar after those corrections are added.
The record is not that every approximation ran the safe way — the routing-trim
refutation carried a quantified ≤0.03-point understatement from code-point
byte counting, small against a multi-point margin, and said so
(`../evals/rule-precision/routing-trim/README.md`, MEASURED). A refutation
resting on an unquantified dangerous-direction looseness is not one.

### 7.2.3 Replay accounting

The rules that made the difference between a number and a bound, stated
generally:

- **A round trip is eliminated only when every result it ingests is removed** —
  scoped-only elimination put most of the trip term on work that still had to
  happen (`../evals/rule-precision/routing-trim/protocol.md`, sixth
  amendment).
- **Moved content is charged where it now sits**: a result delivered earlier is
  re-sent by every surviving request in between, and a figure that omits the
  carry is not a saving. Savings are allowed to come out negative, and on real
  agents they did.
- **Removed requests keep the work their responses did.** Output relocates
  unless the response did nothing but fetch what the replay replaces; crediting
  it as vanished moved one verdict across the bar
  (`../evals/rule-precision/request-batching/protocol.md`, first amendment).
- **A cost charged must be a cost something incurs.** The compiler gate charges
  the bytes of its own invocation, and a test executes that exact command
  string — the first version priced a command the tool could not parse
  (`../evals/rule-precision/packet-compiler/`, Gate C1).

### 7.2.4 The union argument

Where an intervention must produce **one artifact serving many consumers**
under a coverage condition — here, one packet that must carry every rule any
reviewer used — the per-consumer oracle converts into a bound on **every
selection rule within the fixed intervention**: the artifact must contain each
consumer's set, hence their **union**, so the union is the cheapest artifact
satisfying coverage, whatever rule chose its members. The verdict then does
not depend on how well the evaluated implementation was written, and no tuning
on a dev split can move it (`../evals/rule-precision/packet-compiler/gate_c1.py`).

The conditions are narrower than "coverage plus a shared artifact", and all of
them did hold in the case measured: a **fixed representation** of the
artifact's members (catalogue rows and pages as shipped), a **fixed shared
delivery form** (one packet, one arrival), and a **cost model monotone in
added members**. Compressing the members, re-representing them, or delivering
per-consumer subsets are outside the bound — in this series they are
reformulations, which void the protocol and require their own. What the
argument buys, inside its conditions, is a verdict independent of the
selection rule or compiler mapping — and the conditions are checkable before
any code exists.

### 7.2.5 Pinning, and checks that can fail

- **Manifests are checked, not printed.** Transcript sets, the
  agent-to-review mapping (which review a transcript *is* changes every
  retention set, so it is hashed with the bytes), the catalogue by
  path-and-content, the fixture diff — each gate stops on mismatch. A hash
  that is displayed but never compared accepts any input
  (`../evals/rule-precision/packet-compiler/gate_c1.py`, review history).
- **Two forms of the total, where both were built.** In the batching and
  compiled-witness gates the closed-form difference is checked against the
  same quantity rebuilt from scratch — costing the transformed round request
  by request — over each gate's own domain: B0 across every agent, scope,
  calibration and both registered arrangements; B1 for the fixed intervention
  across every agent and calibration; C0 across every agent, calibration and
  legal packet position. The other gates carry different self-checks (the
  routing-trim replay's degenerate-case equality, Gate C1's union logic
  pinned as set algebra). Where the two forms
  exist, what is independent is the **aggregation path**, not the inputs: both
  consume the same classifier, request mapping and cost primitives, so
  agreement is evidence against arithmetic error in either path and none about
  a defect in the shared classification.
- **Degenerate-case equality catches shared-input defects only when the paths
  use them asymmetrically.** The `is_detail` defect was caught because two
  independently written scans exercised the shared predicate differently; a
  shared defect that biases both paths identically passes every such check.
  The residual exposure is named rather than waved at: known classifier
  behaviours are pinned by behavioural tests (`../tests/gate0-classify.bats`),
  which mitigates but does not eliminate classifier-level misspecification —
  an unknown shared misreading of the transcripts survives both the tests and
  every cross-gate agreement.
- **Degenerate-case equality across independently written gates.** With its
  distinguishing feature disabled, a new gate must reproduce the prior gate's
  figure to the token. The routing-trim replay's empty-retention case must
  equal its Gate 0's generous ceiling, and that check caught a live classifier
  defect neither gate's own tests had
  (`../evals/rule-precision/routing-trim/gate0.py`, `is_detail`); the batching
  gate's causal floor likewise reduces to the prior gate on a one-position
  window, to the token.

## 7.3 The record

- **Pre-registration, plus post-result directional amendment records.** These
  are different objects and the vocabulary keeps them apart. An **amendment**
  is a correction made *after* a figure existed, recorded in place with the
  direction it moves the conclusion; the series' protocols carry fourteen. The
  recorded norm: amending after a result is defensible when the correction
  moves **against** the conclusion previously drawn — and a correction that
  *rescues* a conclusion is the one demanding the most scrutiny, which is why
  direction is part of the record rather than commentary
  (`../evals/rule-precision/routing-trim/protocol.md`, first amendment).
- **Graded claims.** Every empirical statement carries REPLICATED / CONFIRMED
  / MEASURED / REFUTED / OPEN, per the ledger's key (`../evals/README.md`),
  and an interval that crosses zero is a failure to detect, never a
  demonstration of nothing.
- **Mutation red-proofs, scoped.** In the efficiency gates, every rule a
  verdict rests on was mutated and observed to go red — including two cases
  added because a first sweep found rules no test exercised. This is claimed
  for the efficiency gates only, not retrofitted onto the earlier rounds, and
  is adopted as a standing rule for anything this monograph's claims come to
  rest on.
- **Evidence that outlives its scratch space.** Raw review outputs, the
  round-22 transcripts every replay figure derives from, and one-off inputs
  are archived under sha1 manifests, with catalogue reconstruction recipes
  verified against the live snapshots before those expired
  (`../evals/README.md`, "Where the evidence is").

## 7.4 What this method has not yet established

Stated here so the reader carries it into every earlier chapter, and handed to
Chapter 8 as obligations rather than caveats:

- **No external calibration.** Every gate parameter — the 20% investment bar
  above all — was chosen, not derived, and the whole apparatus has run in one
  repository and one model epoch, on eight ablation fixtures, three precision
  fixtures, and a single replay fixture. Nothing here shows the gates'
  verdicts track anything outside that setting.
- **No positive control.** The replay family has never passed a candidate
  through to a forward test, so a gate chain that quietly refutes everything
  is empirically indistinguishable from one that refutes the right things.
  Chapter 8 specifies the validation this requires: predictions fixed before
  a forward test, verdicts compared with outcomes, and at least one
  gate-passing candidate or positive control in the design.
- **No false-refutation estimate — and the risk is external validity, not
  arithmetic.** A genuinely valid upper bound on the same intervention and the
  same estimand cannot under-price it; that much is definitional. The risk is
  that the replayed quantity fails to be that bound for the deployed one:
  reviewer behaviour changes under the intervention, the deployment
  distribution drifts from the replayed round, or the fixed intervention and
  the deployed intervention are not the same object. How often that happens —
  a replay verdict of "refute" beside a forward test that would have
  vindicated — is unmeasured, and §7.2.2's bound discipline cannot measure
  it, because it controls error direction inside the replay only.
- **Identification's own external validity** is inherited from its
  instruments: panel judgement is not ground truth, and the fixtures were
  partly authored by people who knew the rules (Chapter 8, with the ledger's
  validity section, owns the full statement).
