# The measurement line — what it established

Measurement ran against the triangulate review skill from 2026-08-04 to
2026-08-21: the rule-ablation rounds (1–11), the finding-precision rounds
(11–22, the first reusing the ablation line's material), three retrospective
audits (variance, design, review-efficiency), and three pre-registered
efficiency candidates.
Their conclusions are scattered across twenty READMEs and protocols, each scoped
to its own round. This file is the cross-line ledger: every claim the line
established, at the strength it actually has, and what each one changed — or
refused to change — in the shipped skill.

Grades, strictest first: **REPLICATED** (confirmed on two fixtures),
**CONFIRMED** (one pre-registered confirmatory interval, one fixture),
**MEASURED** (descriptive or single-batch, no confirmatory rule), **REFUTED**
(a pre-registered gate ended it), **OPEN** (attempted and not resolved). A null
is never graded as equivalence.

## The chain of questions

Each line exists because the previous one was blind to something:

1. `rule-ablation/` rounds 1–3 asked whether catalogue rules change **detection**
   of a seeded defect. No detectable difference — at a power that could only have
   caught a very large one — and the harness could not see the other thirty
   findings per review.
2. Rounds 4–9 asked whether rules change the **remedy** — and whether the
   catalogue's problem was content or wiring.
3. `rule-precision/` rounds 11–22 asked whether findings are **true**, what the
   second and third reviewer add, and whether the Finding Floor built from that
   diagnosis survives contact with fixtures nobody built for it.
4. The three audits asked what the rounds vary by, what they **cost**, and
   whether another one would change any decision.
5. `rule-precision/{routing-trim,request-batching,packet-compiler}/` asked
   whether the cost can come down without the quality. **These three interventions
   could not**; whether other directions exist is not established.
   (`rule-precision/GOAL.md` is the canonical statement of the goal, its decision
   rule, the closure, and the resume conditions.)

## The ledger

### What reviews get wrong, and the floor that fixes part of it

- **MEASURED — the failure mode is not misreading.** Re-run from the pinned
  round-11 material (`rule-precision/measure.py`): 574 findings, **127 not
  adjudicated `real`, of which 2 misread the code**; at claim level 39 real /
  43 not-a-defect / 1 wrong. The catalogue's Finding Floor preamble carries a
  finer historical breakdown ("5 of 128", ungrounded requirements vs
  preferences) that no pinned input reproduces — it is cited there as the
  floor's recorded rationale, and this ledger's numbers are the re-runnable
  ones.
- **REPLICATED — the Finding Floor cuts Critical/Major non-defects with no
  detectable coverage change.** Round 12 (F9): 1.62 vs 4.12 per review, t = −4.11. Round 17 (F10,
  a fixture built blind to the floor): 2.44 vs 4.56, t = −3.05. Coverage showed
  no detectable change in either (nulls inside their MDEs, not equivalence). The floor's digest wiring line exists because round 7 proved a
  section no routing path names is dead text.
- **CONFIRMED (F10) — clause 1 is the active component.** Round 20's 2×2: W −
  W₂₃ = −1.33, paired CI [−2.27, −0.39]. Clause 2 alone is indistinguishable
  from no floor (round 19: −0.17); clause 3 has no positive evidence in any
  cell — and no round licenses deleting it, because every null sat inside its
  MDE (round 18 was powered for 2.67 and observed −1.00).
- **OPEN — clause 1 on F11.** Round 21: no transfer detected (−0.67,
  CI [−1.60, +0.27]). Round 22: the pre-registered sensitivity gate fired
  (observed MDE 1.41 vs ceiling 1.33) and the round makes no confirmatory claim;
  its descriptive tables lean the same ambiguous way, real claims 20.28 (W) vs
  21.48 (W₂₃). Two F11 rounds processed ≈86M raw tokens (≈61M api-eq, review
  agents alone; the design audit's own "≈19M" was final-context accounting, which
  the efficiency audit superseded at 5.1×) without resolving it, and the
  design audit's recorded decision is **do not run round 23** — break-even on
  the false-positive/coverage trade sits at ρ ≈ 0.6–1.1 and another round does
  not move a decision that depends on ρ. Clause 1 ships unchanged.

### What buys coverage

- **MEASURED (F9, one batch) — precision and coverage trade by reviewer
  structure.** Three identical generalists: 81.6% precision, 16.8 of 39 distinct
  real claims. Three specialised experts: 73.5%, 19.1 — and the specialists'
  third reviewer adds +4.8 claims where the generalists' adds +2.5, because
  specialised replies overlap half as much (Jaccard 0.116 vs 0.246). This is the
  measured case for the three-expert split.
- **MEASURED (F9) — the reviewer-count curve.** 10.8 real claims at N=1 rising
  to 20.0 at N=6, non-defects rising 0.7 → 4.4. The shipped k=3 is a choice
  based on this curve — the third reviewer's marginal claims fall to about
  three-fifths of the second's (+2.1 vs +3.5) while the false-positive cost is
  linear. The oft-quoted splice — specialists at 19.1 matching the
  five-generalist point for ~60% of the tokens — crosses batches (the
  specialist figures are round 11's), which the method classifies as context,
  not a control; it is retracted as "the measured case for k=3" (corrected
  2026-08-23).
- **MEASURED (F9) — conditioning a second wave.** Telling wave two what wave one
  found cuts restatement 96% and spends the freed attention on more ground, less
  accurately: +43% real, +89% non-defects. Recorded with no recommendation;
  round 15 found no detectable titles-only-vs-full difference (primary 7.83 vs
  7.83, t = 0.00, but MDE 2.86 — identical point estimates are not equivalence)
  and round 14's cost penalty did not replicate.

### What the rules themselves do

- **MEASURED — no detectable detection difference.** Rounds 1–3, eight fixtures:
  no detection difference survived replication — and the power audit's caveat is
  part of the result: binary scoring at n=8 could only have ruled out a very
  large effect. Two early n=3 claims in both directions were retracted at n=8.
- **MEASURED (blinded re-score) — procedure-bearing rules move the remedy,
  where the fixture is hard.** F6, remedy quality against the independent rubric:
  **6.25/9 with the full R54 procedure vs 4.40/9 without** — diff 1.85 against an
  MDE of 1.21, scored blind to arm. (The oft-quoted 8/8 vs 6/8 is the detection
  count, a different and weaker observation.) The round-6.5 re-score confirmed
  F6, halved F9, and showed self-scoring had erred in both directions. Round 6's
  panels: catalogue rows carry 2–5 of the ~11–15 properties independent panels
  require — the deficit is the catalogue's, not one rule's.
- **MEASURED — taught obligations get produced.** R54's six added obligations
  went from 0/29 appearances to produced when shipped (round 8, one variable per
  round). The Remedy Floor moved its own clauses with no detectable mechanism
  change once wired (round 7: +1.6/8 and +3.6/5, agreement ≥89.8%).
- **MEASURED, load-bearing null — a name-only catalogue showed no detectable
  difference from no catalogue** (arm B, rounds 1–3; same power caveat as the
  detection nulls). Shrinking rows to their digest names re-proposes something
  measured to show no detectable benefit, and the ablation audit's first listed
  consequence is "do not".

### What it costs, and the closed search

- **MEASURED — the cost structure.** A round-22 review agent processes ≈422k raw
  tokens across a mean 7.6 requests; **93.6% is transport** — the same content
  re-sent — not new bytes. `subagent_tokens` in every round README is final-
  request context (median relative error 0.0009), not spend.
- **REFUTED, three times, on the round-22 generalist configuration —** the
  efficiency search (`rule-precision/GOAL.md`); round 22's reviews are three
  identical generalists per review, while the shipped skill runs three
  specialised roles, so the verdicts bind the generalist corpus and are
  untested on the specialist split: trimming what a reviewer reads (oracle ceiling
  9.92–10.89% vs the 20% investment bar), batching when its fetches arrive
  (19.32–19.52%; the digest→rows causal window is one request wide in all 150
  agents), compiling the packet deterministically (12.19–14.60%; the union
  argument makes this bind every selection rule). Reviewer disagreement is the
  packet-compiler's measured cause: 46 of 74 rules were needed by the W-holdout
  alone, 54 of 74 by the round, mean 18.2 per agent. **Nothing was adopted; the
  goal — real-claim reach practically intact (zero Critical loss, ≥95% of current
  k=3), false positives no worse, fewer raw tokens than current, on forward
  data — is unmet**, and GOAL.md fixes the resume conditions.
- **MEASURED — what deciding costs.** A forward non-inferiority test at the 95%
  floor is ≈222 agents at GOAL.md's plug-in sizing — ≈94M raw / 65.5M api-eq at
  the efficiency audit's per-agent figures — or ≈294 at `routing-trim/`'s more
  conservative sizing, ≈124M raw / 86.7M api-eq. Round-22's nominal pairing
  tightens neither (r = 0.136).

## What the skill ships because of this, and despite it

| shipped element | evidence | grade |
|---|---|---|
| Finding Floor, digest-wired | rounds 11 (diagnosis), 12, 17, 7 (wiring) | REPLICATED |
| .. clause 1 kept | round 20 | CONFIRMED (F10); OPEN (F11) |
| .. clauses 2, 3 kept | rounds 18, 19, 20 — nulls inside their MDEs | no deletion licensed |
| Remedy Floor, wired | round 7 | MEASURED |
| R54 extended obligations | rounds 6.5, 8 | MEASURED |
| three specialised experts | precision S/G + marginal reviewer | MEASURED (F9) |
| k=3 | round 13 curve; efficiency audits | MEASURED |
| full rows, not digest names | arm B null | MEASURED null |
| no efficiency change | three refuted candidates | REFUTED |

## Validity, in one place

Ablation fixtures were written by people who knew the rules — a null there means
"no detectable effect on a fixture I wrote", a positive is stronger. F10 and F11 were
authored blind to their arms. `real` is a three-agent panel's judgement under a
stated assumption (agreement 84–94%), not ground truth; coverage counts are of
the discovered set, not the fixture. Three fixtures (F9, F10, F11) carry the
precision conclusions; one (F11) carries every efficiency figure. Everything is
one model epoch.
Whether reviewer disagreement (the packet-compiler's cause of death) is a
property of F11 or of reviewing is not known.

## Where the evidence is

Every number is re-runnable: measured sheets and adjudications are committed
per round; raw review outputs, the round-22 session transcripts (the efficiency
line's entire input), and recovered one-off material are in the private archive
`ngc-shj/claude-code-config-eval-raw`, sha1-manifested, with catalogue
reconstruction recipes verified before the originals expired. The method kit the
line minted — oracle-before-run, same-batch controls, MDE/inference separation
(`rule-precision/methods.md`), saturation checks, blinded re-scoring, directional
amendments, witness-vs-ceiling, mutation red-proofs, manifest pinning — lives in
the protocols and is the part most portable beyond this repository.
