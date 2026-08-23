# 8. Limits, and what completion as a doctoral claim requires

This chapter gathers every boundary the earlier chapters deferred here, then
states what separates the monograph as it stands — a single-repository
empirical study whose numbers re-run — from a completed doctoral claim. The
two lists are different in kind: the limits are properties of the evidence
that no further work removes retroactively; the obligations are work that has
not been done.

## 8.1 The limits, in one place

- **Fixture authorship, with no determinable direction.** The ablation
  fixtures — eight of them — were written by someone who knew the rule under
  test, and that knowledge cuts both ways: it can make the seeded defect
  legible to every arm, shrinking differences, or shape the defect to the
  rule's own vocabulary, favouring the arm that holds the rule. Nulls and
  positives both inherit arm-aligned authorship, and no direction can be
  assigned in principle. F10 and F11 were authored blind to their arms, which
  removes the arm-aligned component — removal, not reversal; the seed defects
  still went where an author put them.
- **The panel is not ground truth.** `real` is three agents' majority under a
  stated assumption, agreeing 84–94% of the time. Holding the assumption
  fixed prevents drift in the standard; it does not make contrasts unbiased,
  because an intervention that changes the kinds of claims produced meets
  per-kind error rates the panel was never calibrated on (§7.1.1).
  Measurement invariance across arms was not tested.
- **Coverage counts are of the discovered set.** A defect no reply ever
  reported is invisible; "19.1 of 39" is coverage of what these reviews
  found, not of the fixture.
- **Evidence per line, counted.** Eight fixtures behind the ablation
  conclusions; three (F9, F10, F11) behind precision; **one** (F11, one
  round, 150 transcripts) behind every replay figure. The two strongest
  results are thin at the edge: the Finding Floor's effect has exactly one
  fixture beyond its origin, and clause 1's confirmation has **none** — its
  one transfer attempt stands OPEN.
- **The measured configuration is not the shipped one.** Round 22 — the
  corpus behind the quality floor's control and every replay verdict — runs
  three identical generalists per review; the shipped skill runs three
  specialised roles. Chapter 3 measured the two structures differing in both
  precision and coverage, so the mismatch is not presumptively neutral:
  the floor's control and the refutations are scoped to the generalist
  configuration, and nothing here transfers them to the specialist split.
- **One model epoch, one repository, one review skill.** Every number in the
  monograph. Whether the reviewer disagreement that killed the packet
  compiler is a property of F11, of this catalogue, of this model, or of
  reviewing as an activity is **not known**, and nothing here distinguishes
  those.
- **Chosen parameters.** The 20% investment bar, the 95% floor, the
  adjudication assumption, and the calibration bracket (3.5–4.2
  bytes/token) were all chosen. The monograph's claims are conditional on
  those choices and say so where they bind.

## 8.2 What the current evidence supports

A master's-scale empirical claim: on this repository, under these
instruments, the Finding Floor reduces Critical/Major non-defect findings
with no detectable coverage change on F9, repeating in direction and size on
F10 (MEASURED, with qualified replication evidence — the repeat's post-hoc
extension keeps it short of REPLICATED); clause 1 is its only component with
positive evidence, on one fixture (CONFIRMED); three token-optimization
candidates fail their bounds by causal replay (REPLAY-REFUTED —
trace-conditional, at zero new review-agent cost); the reported cost figures
were
final-request context, off by 5.1× on the round measured (MEASURED); and the
method that produced all of the above is stated as reusable design rules
(Chapter 7), with its evidence archived, manifested, and re-runnable. The
goal the series served is **unmet**, and the monograph claims the refutations
and the method, not a delivered efficiency.

## 8.3 The doctoral obligations

Two, and they are not symmetric.

**Novelty against related work — a survey obligation.** Nothing in this
monograph has been systematically compared against the literatures it
plausibly touches: ablation of prompt and instruction components,
LLM-as-judge reliability and calibration, code-review evaluation corpora,
multi-agent redundancy and diversity, and cost modelling of agentic systems.
Until that survey exists, no chapter's contribution can be claimed as novel —
only as independently derived. The claim structure of this monograph was
written to survive that survey (methods and measurements, not priority), but
writing it down is not the same as having done it.

**Prospective validation of the gate method — an experimental obligation,
specified.** One prerequisite precedes it: **clauses 1 and 3 of the adoption
rule must first be operationalised** — estimand, margin, one-sided rule and
error rates pre-registered — because a forward test scored against a tripwire
and an unoperationalised constraint cannot certify the rule it claims to
(Chapter 1 records the current status). "Try it on another repository" is
underspecified in the way §7.4 warns about; what completion requires is:

1. an independent repository and model, with the gate apparatus ported before
   any candidate is examined;
2. **gate predictions fixed before any forward test runs** — the replay
   verdicts committed, then the forward test executed regardless of them, on
   a pre-registered design;
3. the comparison of gate verdicts against forward outcomes as the primary
   endpoint — including, and especially, the false-refutation comparison:
   a forward test of at least one candidate the gates *refuted*;
4. **at least one positive control or gate-passing candidate**, so a gate
   chain that quietly refutes everything is distinguishable from one that
   refutes the right things — the observation §7.4 records is that this
   series never produced a passing candidate, so the chain's pass behaviour
   has never been exercised;
5. an explicit assessment of false-refutation risk as the external-validity
   question it is (§7.4): how often a replay verdict of "refute" sits beside
   a forward outcome that would have cleared the adoption rule;
6. calibration of the chosen thresholds against the new setting's outcomes —
   the 20% investment bar above all — so the bar Chapter 1 flags as chosen
   stops being an uncalibrated choice wherever the method is claimed to
   carry.

These obligations are distinct from the resume conditions in
`../evals/rule-precision/GOAL.md`: those govern re-opening the *efficiency
search on this repository*; the obligations above govern claiming the
*method* generalises. Meeting the second does not require meeting the first.

## 8.4 The honest end state

The series set out to make a review cheaper without making it worse, and did
not. What it produced instead is a system whose quality properties are
measured at stated strengths, whose costs are counted in honest units, whose
dead ends are refuted with their reasons recorded, and whose method is
portable on paper and unvalidated off it. The monograph's contribution is
that inventory — every claim graded, every number re-runnable, every
correction recorded with its direction — and the demonstration, fourteen
protocol amendments and the round documents' own corrections lists long, that
the discipline which produces such an inventory can be applied to an LLM
system by the same standards it applies to the system's own claims.
