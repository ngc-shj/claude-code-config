# 1. The problem, and quality as a constraint

An LLM code-review system is easy to change and hard to improve. Rules can be
added on any plausible theory; material can be trimmed on any plausible
economy; and the review still produces thirty findings a run, so every change
*looks* like it did something. The series this monograph reports began with
the two failures that framing invites — rules whose counterfactual was never
measured (Chapter 2), and cost figures wrong by 5.1× (Chapter 5) — and
converged on the discipline the thesis states: **treat every proposed change
as a decision problem under pre-declared quality constraints, and buy its
verdict as cheaply as the constraints allow.**

## 1.1 Why not rule-presence

The natural unit of improvement — add the rule, the reviews get better — is
the unit the evidence declined to support. Detection did not detectably move
with the catalogue present, absent, or reduced to names (Chapter 2, with its
power caveats); what moved was the literal transmission of clauses a routed
rule states. The natural unit of economy — trim what nobody seems to need —
fared no better: the three cheapest-looking savings all failed their bounds
(Chapter 6). What remained measurable, and decision-relevant, were properties
of the *review*: how many of its findings are true, how many distinct real
defects it reaches, and what it costs to run. Those three quantities are the
decision problem's axes, and the goal document fixes their trade
(`../evals/rule-precision/GOAL.md`).

## 1.2 The decision rule

Adoption is lexicographic — constraints first, economy strictly after:

1. zero loss of Critical real claims;
2. distinct real claims reached ≥ 95% of the current configuration's;
3. Critical/Major not-a-defect findings no worse;
4. raw processed tokens **below** the current configuration's;
5. among candidates passing 1–4, minimum raw tokens;
6. api-eq as a secondary readout only.

Three features carry the argument. The rule is **not scalarised**: no token
saving buys back a Critical claim, and clause 4 is what makes the exercise a
reduction rather than a tournament among candidates that might all cost more
than what runs today. The floor in clause 2 is a **stated margin, not
rhetoric**: 95% of the measured control's 20.28 distinct real claims per
review is a concession of 1.014 claims, and the rule's honesty is that it
says so — with one scope caveat the rule inherits from its data: the control
is round 22's W arm, **three identical generalists per review**, standing in
for a shipped configuration that runs three specialised roles. Chapter 8
records the mismatch as a limit.
And the familiar-sounding alternative — "equal or better" — is not a rule a
study can be *planned* to meet: sized at the planning assumption a
non-inferiority design must survive (θ = 0, the candidate changes nothing),
a zero margin needs unbounded n, and requiring the point estimate to sit at
or above control succeeds about half the time at θ = 0 however large n grows
— applicable at any n, sizeable at none. The 95% floor at θ = 0 prices at
≈222 agents per test (≈94M raw / 65.5M api-eq at Chapter 5's per-agent
figures; ≈294 and ≈124M / 86.7M at the conservative sizing); tightening the
floor to 97.5% quadruples the sample, to 99% multiplies it by twenty-five.

θ = 0 is the sizing table's chosen planning assumption, not a property of
non-inferiority — a candidate that is genuinely better sizes a zero margin at
finite n — but an adoption rule has to survive the neutral case, because a
rule that only works when the candidate happens to be better is not a rule.

One honesty the rule owes the reader before it is used anywhere: **only
clause 2 is a fully operationalised statistical rule.** Clause 1 is an action
tripwire — any *observed* Critical loss fails the candidate at any n, which
governs what is done, not what is inferred; a run with no observed loss
establishes nothing about the true loss rate, for the same finite-n reason a
zero margin cannot be planned for, and that residual risk is unquantified.
Clause 3 names no margin, interval, or error rate at all. A forward design
must pre-register both operationalisations before the rule can run
end-to-end — Chapter 8 carries this as a prerequisite of its validation
obligation — and until then the rule is one executable clause, one tripwire,
and one stated value. No decision in this series exercised clauses 1 or 3.

## 1.3 The bar that is not part of the rule

A separate threshold governs *investment*: a candidate whose perfect form
cannot save 20% of raw tokens is not worth a forward test, and the cheap
gates of Chapter 6 exist to apply that threshold at zero review-agent cost.
Clearing the bar decides nothing about adoption — the asymmetry §7.2 builds
on. The 20% figure was chosen, not derived; its external calibration is
specified inside Chapter 8's validation obligation (item 6 of §8.3).

## 1.4 The goal document as an instrument

`../evals/rule-precision/GOAL.md` is the single source for the goal and the
rule, and its history is part of this chapter's evidence rather than its
housekeeping. The statement above reached its final form through recorded
review corrections — more than are listed here; five rule-shaping ones,
selected: the margin re-based from a two-arm mean to the
control arm actually running; a beat-current clause added when the rule was
found to permit adopting a candidate dearer than the incumbent; the
sizing-table row for a zero margin conditioned on its planning assumption
instead of declared impossible; a screen's authority separated from a formal
evaluation's; and affordability judgements removed from a document that had
already been contradicted by two audits that made them properly. A goal
stated once, in a file, with review, converges; the same goal restated from
memory in each conversation was observed to drift in exactly the ways the
corrections record. That observation — governance documents are instruments
and drift like instruments — is as much a finding of this series as any
number in it.

The document also records the series' end state, which frames every chapter
that follows: three candidates refuted, nothing adopted, the goal **unmet**,
and resumption conditioned on a specific intervention showing headroom above
the bar before it is built, explaining its coverage mechanism, and being
cheaply refutable by a zero-agent gate.
