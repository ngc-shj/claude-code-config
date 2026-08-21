# 7. The method, stated as reusable gate design

This chapter states the method the measurement series converged on, as design
rules a reader could apply to their own review system. Two limits govern
everything in it. First, the rules were extracted from one series — one
repository, one model epoch, three fixtures — and nothing here claims they are
generally valid; what would make them portable is Chapter 8's open obligation,
not this chapter's assertion. Second, the chapter describes **two method
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
   (`../evals/rule-precision/README.md`, Round 12).

The panel's standing assumption — judge the diff as a real pull request into a
working codebase where everything not shown exists and is correct — does most
of the work in the `not-a-defect` verdict and is applied identically to both
arms. It cannot bias a comparison; it does move the absolute level, and every
absolute number in this monograph inherits it.

### 7.1.2 Controls: same batch, one variable, wiring before content

- **Same-batch comparison.** Arms are compared within one generation batch,
  never across batches. The series' standing exhibit is a saturation claim that
  read 1/8 → 8/8 across batches and shrank to something honest when the
  control ran in-batch
  (`../docs/archive/audit/2026-08-04-rule-ablation.md`, Round 9).
- **One variable per round.** Arms differ in shipped files, never in prompts;
  where a round tests a structure, both arms are rendered from one template so
  the manipulation is the role line and nothing else
  (`../evals/rule-ablation/README.md`, Arms).
- **Reachability precedes ablation.** Before a section is credited or debited,
  a tool-call-trace probe establishes that reviewers read it at all. The Remedy
  Floor as merged was read by zero of four probed reviewers — ablating it
  against absence would have compared two arms that both lacked it in practice
  (`../evals/rule-ablation/README.md`, Round 7). The general rule: **a
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
  fixes against it moved results in both directions — confirming one fixture's
  effect, halving another's (`../evals/README.md`, ledger; the ablation audit,
  Rounds 5 and 6.5). Self-scoring had erred both ways, which is the argument
  for blinding stated as an observation.
- **Saturation check before reuse.** An instrument at its ceiling returns a
  null whatever the arms do. Round 11 caught its rubric saturated (9.00/9)
  before reuse and rebuilt it, frozen, before the first arm ran
  (`../evals/rule-ablation/README.md`, Rounds 10–11).
- **Structured extraction, not per-round regexes.** The heading regex lost
  findings twice, both times in the arm whose treatment makes reviewers invent
  heading shapes — a loss correlated with the arm is a bias, not noise
  (`../evals/rule-precision/README.md`, `extract.py`).

### 7.1.4 Power and inference, separated

`../evals/rule-precision/methods.md` is the normative statement; the design
rules are three:

- **The MDE is a design quantity.** Computed from a borrowed sd before the
  run, it answers "is this n worth running?" and gates the spend — run first
  and alone, before any arm comparison is looked at. When the observed MDE
  exceeds the pre-registered ceiling, the round reports itself underpowered
  and does **not** extend n (Round 22 is the executed example: gate fired,
  no confirmatory claim, everything below it descriptive).
- **The test and interval are observation quantities.** An observed effect
  does not have to exceed the MDE to be significant; requiring that is a
  stricter test than α = .05 applied by accident. Round 19 is the worked
  example — CI [−3.76, −0.24] excluding zero, and a pre-registered rule that
  demanded more and was wrong to; the record keeps both statements and does
  not rewrite the rule after the fact.
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
two). And **every remaining looseness is measured with its direction stated**:
a refutation must show its known approximations all inflate the saving, so a
corrected figure moves toward the verdict rather than away from it.

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
reviewer used — the per-consumer oracle converts into a bound that no
implementation can beat: the artifact must contain each consumer's set, hence
their **union**, so the union is the cheapest artifact satisfying coverage and
its cost bounds every implementation's from below, whatever selection rule
produced it. The verdict then does not depend on how well the evaluated
implementation was written, and no amount of tuning on a dev split can move it
(`../evals/rule-precision/packet-compiler/gate_c1.py`). This is the replay
family's strongest move, and the condition for it — a coverage requirement
plus a shared artifact — is checkable before any code exists.

### 7.2.5 Pinning, and checks that can fail

- **Manifests are checked, not printed.** Transcript sets, the
  agent-to-review mapping (which review a transcript *is* changes every
  retention set, so it is hashed with the bytes), the catalogue by
  path-and-content, the fixture diff — each gate stops on mismatch. A hash
  that is displayed but never compared accepts any input
  (`../evals/rule-precision/packet-compiler/gate_c1.py`, review history).
- **Two forms of every total.** The closed-form difference is checked against
  the same quantity rebuilt from scratch — costing the transformed round
  request by request — for every agent, calibration, and arrangement. The two
  share no terms, so agreement is evidence rather than tautology.
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
  repository, one model epoch, one fixture family. Nothing here shows the
  gates' verdicts track anything outside that setting.
- **No positive control.** The replay family has never passed a candidate
  through to a forward test, so a gate chain that quietly refutes everything
  is empirically indistinguishable from one that refutes the right things.
  Chapter 8 specifies the validation this requires: predictions fixed before
  a forward test, verdicts compared with outcomes, and at least one
  gate-passing candidate or positive control in the design.
- **No false-refutation estimate.** The bound discipline of §7.2.2 controls
  the *direction* of error inside a replay; it does not quantify how often a
  correctly-computed upper bound under-prices an intervention a forward test
  would have vindicated. That risk is unmeasured.
- **Identification's own external validity** is inherited from its
  instruments: panel judgement is not ground truth, and the fixtures were
  partly authored by people who knew the rules (Chapter 8, with the ledger's
  validity section, owns the full statement).
