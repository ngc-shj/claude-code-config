# Monograph — working skeleton

**Working title:** *Evidence-Calibrated Improvement of LLM Code Review: Rule
Ablation, Claim-Level Quality, and Cheap Falsification of Token Optimizations*

**Status:** all eight chapters drafted (`01`–`08`); chapters 7 and 6 merged
after review; 4, 2, 3, 5, 1 and 8 under batch review on one branch, per the
amended rule 5. This file fixes the thesis, the
chapter-to-evidence mapping, and the writing rules **before prose exists**, for
the same reason every protocol in `../evals/` fixed its rules before its
numbers: the ledger (`../evals/README.md`) took two review rounds to purge ten
aggregation errors, and a draft that cites evidence from memory will
manufacture the same class of defect at chapter scale.

## Thesis

> Improving LLM code review has to be measured as a decision problem under
> **pre-declared quality constraints** — zero Critical loss, non-inferior claim
> reach at a stated margin, and no worsening of Critical/Major not-a-defect
> findings — not as the presence or absence of individual rules. Claim-level adjudication, same-batch controls, and inference separated
> from power (MDE) identify interventions whose effects **repeat across
> fixtures, at graded strength**, and keep what does not resolve **explicitly
> open** rather than silently assumed; causal replay over pinned session
> transcripts **replay-refutes some optimization candidates before any
> forward test** — trace-conditional verdicts — at zero new review-agent
> cost.

The two method families are deliberately not merged: the first identified and
bounded the Finding Floor, the second replay-refuted the three efficiency
candidates under the trace-conditional model, and neither did the other's
job.

The earlier phrasing "identify effective interventions" is deliberately not
used: the ledger's grades support *measured on one fixture, with qualified
replication evidence on a second, open on a third* for the strongest positive
result — the F10 repeat's post-hoc n-extension keeps it short of the
REPLICATED bar — and the thesis claims exactly that and no more.

## What this can and cannot be, on current evidence

- **Writable now:** a single-repository empirical monograph (master's-thesis
  scale). Every number below re-runs from pinned inputs or the private
  evidence archive (`ngc-shj/claude-code-config-eval-raw`).
- **Not yet a completed doctoral claim:** novelty against related work is
  unverified, and the method has no prospective validation on a second
  repository or model. Chapter 8 owns both gaps; neither blocks drafting.

## Writing rules, inherited from the ledger

1. **Numbers re-run or they do not appear.** A historical prose figure that no
   pinned input reproduces (the catalogue's "5 of 128") may be *discussed* as
   recorded rationale, never cited as a result.
2. **A null is never written as equivalence.** "No detectable difference",
   with the MDE or the power caveat beside it, every time.
3. **Costs in the efficiency audit's units** (raw / api-eq), never
   final-context. The 19M-vs-86M error is the standing example.
4. **Every empirical sentence carries its grade** — REPLICATED / CONFIRMED /
   MEASURED / REPLAY-REFUTED / OPEN, per the ledger's key — or cites a ledger
   entry that does. (REPLAY-REFUTED is trace-conditional; no current entry
   meets the REPLICATED bar.)
5. **Chapters are reviewed like everything else here.** Rule as first written:
   one chapter per PR. Amended 2026-08-23, at the owner's direction, once the
   vocabulary and rule set had stabilised over chapters 7, 6 and 4: the
   remaining chapters (2, 3, 5, 1, 8) are drafted as one commit each on a
   single branch and reviewed as a batch — reviewer round-trips, not drafting,
   being the scarce resource. The ledger remains the source of figures;
   chapters cite it and the round documents, and a chapter that needs a number
   the ledger lacks adds it to the ledger first.

## Chapters, each pinned to its evidence

### 1. The problem, and quality as a constraint

The decision frame: a lexicographic adoption rule (zero Critical loss, ≥95%
of current k=3 distinct real claims, false positives no worse, then and only
then fewer raw tokens), the 95% floor as a stated margin (1.014 claims/review
against control W at 20.28 — round 22's W arm, three identical generalists,
the proxy for "current"), θ=0 as the chosen planning assumption, and the
20% bar as an investment threshold that decides nothing about adoption.
*Source:* `../evals/rule-precision/GOAL.md` — including its recorded
correction history (more corrections than the chapter's five selected
rule-shaping ones), which is part of the argument.

### 2. Rule ablation: what the catalogue does and does not do

- Detection: no detectable difference, rounds 1–3, eight fixtures — stated
  with the power audit's caveat (binary at n=8 could only catch a very large
  effect). Two n=3 claims retracted at n=8.
- The load-bearing null: a name-only catalogue vs no catalogue, no detectable
  difference (arm B).
- Remedy, blinded re-score: 6.25/9 vs 4.40/9 on F6 (diff 1.85, MDE 1.21),
  MEASURED; self-scoring had erred in both directions.
- The catalogue's deficit is structural: rows carry 2–5 of the ~11–15
  properties independent panels require (round 6); a section no routing path
  names is dead text (round 7: 0/4 read it; wired: +1.6/8, +3.6/5).
- Taught obligations get produced (round 8: 0/29 → produced).
*Sources:* `../evals/rule-ablation/README.md`,
`../docs/archive/audit/2026-08-04-rule-ablation.md`.

### 3. Finding precision and what buys coverage

574 findings → 83 claims → 39 real (panel, agreement 84–94%); finding-level
precision G 81.6% vs S 73.5%; coverage 16.8 vs 19.1 of 39; the marginal
reviewer (+4.8 vs +2.5, Jaccard 0.116 vs 0.246); the reviewer-count curve
(10.8 → 20.0 real, 0.7 → 4.4 non-defects, N=1..6); conditioning (+43% real,
+89% non-defects, restatement −96%; titles-only vs full: no detectable
difference, identical point estimates beside MDE 2.86).
*Sources:* `../evals/rule-precision/README.md` rounds 11–15;
`../evals/rule-precision/measure.py` and
`../evals/rule-precision/round-15/measure.py` re-runs.

### 4. The Finding Floor: a measured intervention with qualified replication evidence, and its open edge

Diagnosis re-run: 127 of 574 findings non-real, 2 misread — the failure mode
is ungrounded assertion, not misreading. Effect: 1.62 vs 4.12 (F9), 2.44 vs
4.56 (F10, fixture built blind to the floor), coverage with no detectable
change in either. Decomposition: clause 1 CONFIRMED on F10 (paired CI
[−2.27, −0.39]); clauses 2–3 nulls inside their MDEs, no deletion licensed.
The open edge, reported as such: F11 transfer not resolved (round 21 CI
crosses zero; round 22's sensitivity gate fired, 1.41 vs 1.33), ≈86M raw /
≈61M api-eq processed by the two F11 rounds' review agents alone, and the
recorded decision not to run round 23.
*Sources:* `../evals/rule-precision/round-12/`,
`../evals/rule-precision/round-17/`, `../evals/rule-precision/round-18/`,
`../evals/rule-precision/round-19/`, `../evals/rule-precision/round-20/`,
`../evals/rule-precision/round-21/`, `../evals/rule-precision/round-22/`;
`../evals/rule-precision/design-audit/`.

### 5. Token accounting: the number everyone reports is not consumption

`subagent_tokens` is final-request context — that identification is what the
552-agent reconciliation establishes (median relative error 0.0009). In round
22, final-context accounting understated raw processing by 5.1×; the round-22
shape is ≈421.6k raw per review agent across a mean 7.6 requests, 93.6%
transport. Costs for rounds 17–22 — the rounds whose review transcripts were
recovered — restated in raw / api-eq; earlier rounds keep only their reported
final-context figures, and the chapter says which is which.
*Source:* `../evals/rule-precision/review-efficiency/`.

### 6. Cheap falsification: three optimization candidates, zero agents

The three axes — **what** is read (routing-trim, oracle ceiling 9.92–10.89%),
**when** it is fetched (batching, 19.32–19.52%, the one-request causal
window), **who** selects (packet compiler, 12.19–14.60%, the union argument
binding every selection rule; reviewer disagreement measured at 46/74 for the
W holdout, 54/74 for the round, mean 18.2 per agent). Each refuted below the
20% bar by causal replay over pinned transcripts — the round-22 generalist
configuration; the shipped specialist split is untested by the replays. The amendment history is
data, not embarrassment: verdicts crossed the bar twice in one protocol
before settling, each move recorded with its direction.
*Sources:* `../evals/rule-precision/routing-trim/`,
`../evals/rule-precision/request-batching/`,
`../evals/rule-precision/packet-compiler/`;
`../evals/rule-precision/GOAL.md` for the closure and resume conditions.

### 7. The method, stated as reusable gate design

Oracle-before-run; same-batch controls; MDE/inference separation
(`../evals/rule-precision/methods.md`); saturation checks before reuse; blinded re-scoring;
pre-registration, plus **post-result directional amendment records** — an
amendment is a correction made after a figure existed, recorded with the
direction it moves the conclusion, and is not part of the pre-registration; the witness/ceiling
distinction (a witness or lower bound below the bar cannot refute; only an
upper bound below the bar can); the union argument
(coverage conditions turn per-agent oracles into compiler-independent
bounds); manifest pinning for transcripts, catalogues, and agent-to-review
mappings; pre-registering splits in their own commit so git evidences the
ordering; mutation red-proofs for every rule an efficiency-gate verdict rests
on — practiced there, not retrofitted onto the earlier rounds, and adopted as
a rule for anything this monograph's claims come to rest on.

### 8. Limits, and what completion as a doctoral claim requires

Fixture authorship bias, its direction indeterminate in principle; panel
judgement is not ground truth; three fixtures behind precision, one behind efficiency; one model
epoch; whether reviewer disagreement is F11's property or reviewing's is
unknown. **Open obligations:** a related-work novelty check, and prospective
validation of the gate method — which is method validation, distinct from the
efficiency search GOAL.md closed, and underspecified as "try it elsewhere".
What it requires: an independent repository and model; **gate predictions fixed
before the forward test runs**; the gate verdicts compared against the forward
outcomes; **at least one positive control or gate-passing candidate**, so the
exercise can detect a gate that refutes everything; and an assessment of the
false-refutation risk that comparison implies.

## Order of drafting

7 → 6 → 4 → 2 → 3 → 5 → 1 → 8. The method chapter first, because every other
chapter cites its vocabulary; the refutations second, because they are the
freshest and their protocols are the cleanest exhibits; framing and limits
last, when the middle exists to be framed.
