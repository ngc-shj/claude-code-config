# 4. The Finding Floor: a measured intervention with qualified replication evidence, and its open edge

The Finding Floor is three clauses inherited by every finding a reviewer
writes, whichever rule routed it there: point at the evidence inside the
change; treat a requirement you cannot ground as a question, ranked Minor;
never state a preference as a defect
(`../skills/triangulate/common-rules.md`, "Finding Floor"). It is the series'
one intervention whose effect repeated on a second fixture — at qualified
strength, short of the ledger's REPLICATED bar — and this chapter follows it
through its full arc: the diagnosis it answers, the effect measured twice, the
decomposition into clauses, the replication attempt that did not resolve, and
the recorded decision to stop measuring. Its grades, up front and in the
ledger's vocabulary (`../evals/README.md`): the effect on Critical/Major
`not-a-defect` findings is **CONFIRMED on F10 under the registered-output-path
attribution** by a fixed-n, no-peek round (§4.2.1 states the condition and what
the other reading costs) and **MEASURED on F9**; round 17's F10 repeat remains qualified
replication evidence for the reasons §4.2 states rather than absorbs, and
confirmation on one fixture is **not REPLICATED**, which wants two. Clause 1 as
the active component is **CONFIRMED** on F10 — a decomposition contrast, not
the whole-floor one; the transfer of that component to F11 is **OPEN**; and the
clauses ship as they are, two of them on nulls that license nothing.

## 4.1 The diagnosis it answers

Chapter 3's instrument — 574 findings clustered into adjudicated claims —
doubles as a diagnosis of *why* reviews are wrong when they are. Re-run from
the pinned round-11 material (`../evals/rule-precision/measure.py`): **127 of
the 574 findings were not adjudicated `real`, and 2 of the 127 misread the
code** (MEASURED); at claim level, 39 real, 43 not-a-defect, 1 wrong. The
dominant failure is not misreading. It is assertion the change cannot ground —
requirements about code the diff does not contain, and preferences stated as
defects — which is exactly the pair the floor's clauses 2 and 3 address, with
clause 1 demanding the grounding itself.

The catalogue's own preamble records the same diagnosis with a finer
historical breakdown ("5 of 128"); those counts do not reproduce from any
pinned input and are cited here as the floor's recorded rationale, per the
writing rules — the reproducible numbers are the ones above.

One wiring fact carried over from Chapter 2 frames everything: a
cross-cutting section that no routing path names is dead text — the Remedy
Floor as first merged was read by zero of four probed reviewers (MEASURED;
`../evals/rule-ablation/README.md`, Round 7). The Finding Floor therefore
ships with a digest line that wires it, and the extraction rates in the live
rounds confirm the wiring works — taken from the real reviews' tool-call
traces, not from separate probe agents: W 18/18, W₂ 18/18, N 0/18 (MEASURED;
`../evals/rule-precision/round-19/README.md`).

## 4.2 The effect, measured twice

**Round 12, F9** (`../evals/rule-precision/round-12/`): Critical/Major
findings adjudicated not-a-defect fell from 4.12 per review to **1.62**
(t = −4.11, MDE 1.83, n = 8 per arm), with the coverage control showing no
detectable change (16.50 vs 16.88 distinct real claims, MDE 1.93 — a null
inside its MDE, not equivalence).

**Round 17, F10** (`../evals/rule-precision/round-17/`): the fixture nobody
built for the floor — written by an agent told the domain, the shape, and
nothing about the arms. The composite primary fell from 4.56 to **2.44**
(t = −3.05, MDE 2.05, n = 9), coverage again with no detectable change
(33.78 vs 34.78, MDE 2.94). Direction and size replicate: −2.50 on F9, −2.11
on F10. The round's own deviations are part of the record: n reached 9 by a
declared extension after the pre-registered variance gate fired at n = 6, and
the extension was authorised by someone who had seen the n = 6 table. The
gate's two readings are both recorded and both carried here: applied
literally, the sd ceiling is still exceeded at n = 9 and the round reads
**underpowered**; read through the n-dependent MDE it was written to proxy,
the round is powered (`../evals/rule-precision/round-17/README.md`). The
grade follows the defects, not the disclosure: the extension was not
pre-registered and was authorised in sight of the arm table, so F10 is
**qualified replication evidence — direction and size repeat — and not a
confirmed replication**; disclosure does not restore confirmatory status,
and an independent fixed-n, no-peek replication would.

### 4.2.1 Round 24: the fixed-n, no-peek confirmation

**Round 24, F10** (`../evals/rule-precision/round-24/`) is the replication the
previous paragraph asks for, run to a protocol committed with its analysis code
before any review existed: n fixed at 12 per arm, no interim look at an arm
value, the confirmatory rule and the exact Welch machinery in the repository
before the first agent launched. On Critical/Major `not-a-defect` findings the
arms separate by **−1.73**, Welch 95% CI **[−2.39, −1.07]**, df 13.6, at
**n = 11 per arm** — index 5 was voided in both arms by the registered
technical-failure rule and n was not backfilled, leaving the round above its
pre-registered design-integrity floor of 11. The interval lies entirely below
zero, so the whole floor's effect on this metric is **CONFIRMED (F10) under the
registered-output-path attribution**.

That condition is load-bearing and is not a hedge. One review agent was launched
for index 6 and wrote to index 5's registered output path, and part of that
file's text was read. The exchange rule voids "the whole review index" when an
output has been read, but **it never says which index when the launch slot and
the registered output path name different ones** — the protocol registers no
priority, because it never anticipated the divergence. Round 24 read the
registered output path as decisive, which gives n = 11 and the interval above;
reading the launch slot as decisive voids index 6 as well, gives n = 10, and at
n = 10 the round's own design-integrity floor makes it **descriptive only, with
no confirmatory claim and no grade moved**. The n = 10 interval was deliberately
not computed: producing it after the result is known is the selection the
round's structure exists to prevent, and it would not adjudicate a question that
is textual rather than numerical. The adjudication was made after the fact and
is recorded as such (`../evals/rule-precision/round-24/deviations.md`, §9),
together with what did exist before the round — a committed
(index, arm, part)-to-path registry and an extractor defined to read those paths
and never glob — and what did not, which is any rule ranking the two.

Two further things that grade does not say. **The interval states the size, not the
rule**: the round was never required to reproduce round 17's −2.67, and the
narrower −1.73 neither strengthens nor weakens the confirmation. And **one
fixture is not two**: F10 is now a confirmed fixture and F9 is not, so the
effect does not reach REPLICATED and **fixture-independence remains
unestablished** — nothing here licenses the claim that the floor behaves this
way on a fixture it has not met.

The control moved by +0.55, CI [−1.82, 2.91]: **no detectable change**, with no
declared margin behind it and therefore no claim that coverage is preserved. A
blind bridge panel re-judged 24 of round 17's adjudicated claims and agreed on
66 of 72 individual judgements and 22 of 24 majorities; that is a calibration
record which fires no rule and rewrites no frozen verdict.

The round's own deviation is in its record and belongs here. Six outputs the
protocol registered under RECORDED — `wrong` claims per review, the
Critical/Major-to-Minor ratio, the new claims' per-arm share, per-agent tokens
for the executed reviews, a Welch re-analysis of round 12's F9 data, and the
index-paired sensitivity analysis — were **never implemented**, and the gap was
not caught while the code was still blind. They were **not computed after
unblinding**, because a number produced with the result in view can be selected
without anyone intending to select it; the round-12 clause was pre-registered
in that protocol for precisely this reason. So the round is published with an
incomplete RECORDED list, and none of the six is treated as zero,
non-significant, or safely omitted. None of them gates the primary — the
confirmatory interval and its verdict stand as registered — but the
sensitivity analysis that would have shown whether the independent-groups
choice mattered is among the missing, and its absence is a real limitation
rather than a bookkeeping one.

A post-hoc decomposition sharpens what the primary measures and is labelled
as post-hoc (`../evals/rule-precision/README.md`, "The primary metric mixes
two failure modes"): the composite counts both `not-a-defect` and `wrong`,
the floor targets only the first, and F9 happened to contain no Critical/Major
misread at all — so the two metrics coincide there and diverge on F10, where
one misread trap exists. On the not-a-defect class alone, F10's effect is
−2.67 (t = −5.95). The lesson is registered forward, not applied backward:
pre-register the split before leaning on it.

## 4.3 Which clause carries it

Three rounds interrogate the floor's parts, and the sequence is a worked
example of nulls licensing nothing.

**Round 18** (`../evals/rule-precision/round-18/`) asked whether clause 2 —
whose target class looks most like the measured effect — is the floor.
Clause 2 alone against no floor: −1.00, inside an MDE of 2.55, in a round
powered for the full floor's 2.67. The decision rule does not fire; clauses 1
and 3 stay. This does not show clause 2 inert — the null is inside the MDE —
and the comparator was chosen so that a null could *not* be read as a
deletion licence at any affordable n.

**Round 19** (`../evals/rule-precision/round-19/`) put all three levels in
one batch. The primary W − N interval excludes zero ([−3.76, −0.24]); the
pre-registered rule additionally demanded the difference exceed the MDE, so
the round recorded no confirmatory claim — and the rule itself was wrong, a
design quantity pressed into inference duty (§7.1.4; the correction went into
`../evals/rule-precision/methods.md` for later rounds instead of being
applied retroactively). What the arms show, labelled as the protocol labels
them: clause 2 alone shows no detectable difference from no floor
(W₂ − N = −0.17, MDE 2.23 — a null inside a wide MDE, not equivalence), and
the measured gap sits between the full floor and clause 2 (−1.83,
CI [−2.62, −1.04], **exploratory** — strong, and not promoted).

**Round 20** (`../evals/rule-precision/round-20/`), the 2×2 in clause 1 ×
clause 3 with clause 2 always present, is where a confirmatory rule fires:
clause 1 contributes **−1.33** to the non-defect count — removing it raises
the metric by 1.33 — paired CI **[−2.27, −0.39]**: **CONFIRMED**, on F10. Clause 1 shows an effect in both of its cells
(the other: −1.89, CI [−3.30, −0.48], exploratory); clause 3's intervals
straddle zero in both cells, and the interaction crosses zero. The protocol's
own reading is the one that stands: clause 1 has positive evidence; the
absence of a clause-3 effect is **not established**; nothing licenses
deleting anything.

## 4.4 The open edge: F11

**Round 21** (`../evals/rule-precision/round-21/`) asked whether clause 1's
effect lands on a second fixture, on the finding class the hypothesis names.
The confirmatory interval crosses zero (−0.67, CI [−1.60, +0.27]) and the
pre-registered reading is row four of its own table: **no transfer detected
on F11** — a failure to detect, not evidence against the F10 result. The
round's gate held (subtype base rate 1.33 above the 1.0 floor; observed MDE
1.31 within the 1.78 ceiling), so this is a powered non-detection, reported
as exactly that.

**Round 22** (`../evals/rule-precision/round-22/`) attempted the replication
at a sensitivity chosen for round 20's effect size, 25 reviews per arm — and
its observed-MDE sensitivity gate fired: 1.41 against a pre-registered
ceiling of 1.33, the observed arm sds (1.895, 1.590) having come in above the
plug-in values the sizing borrowed. Per §7.1.4 this is an
inference-eligibility verdict, not a spend verdict — by the time it can fire,
all 150 agent outputs exist — and the pre-registered response was followed:
no confirmatory claim, no extension of n, everything below the gate
descriptive. Descriptively: the primary sits at −0.68 (CI [−1.68, +0.32]),
and real claims reached read 20.28 (W) against 21.48 (W₂₃). One pre-registered
exploratory subtype — `outside-diff` — has an interval below zero
([−0.97, −0.07]); the round's own README states why that is reported and what
it is not: it was pre-registered as exploratory, and reading it as the finding
after the confirmatory gate fired is the substitution the protocol structure
exists to prevent. The transfer question stands **OPEN**, and the gate firing
does not establish that the rounds' underlying variances differ — round 21's
n = 9 estimates were imprecise enough to include round 22's values.

## 4.5 The decision to stop, and what ships

The two F11 rounds processed **≈86M raw tokens (≈61M api-eq) in review agents
alone** (MEASURED; Chapter 5's accounting) without resolving the question they
were built for. The design audit
(`../evals/rule-precision/design-audit/README.md`) — retrospective and
exploratory, establishing no cause and proposing no change to clause 1 —
asked the operational question: would another round change what we would do?
Its recorded answer is **do not run round 23**: the decision turns on a
false-positive/coverage trade whose break-even sits near ρ ≈ 0.6–1.1 across
the three rounds, the design that would settle it is not affordable at
persuasive margins, and sharpening one estimate does not move a decision that
depends on both. That is **a decision not to spend, and nothing else** — the
audit's own emphasis.

So the floor ships as follows, and the traceability is the point:

- the **three clauses, unchanged** — the floor as a whole on a CONFIRMED effect
  (F10, §4.2.1, conditional on that section's attribution reading), clause 1 on
  a CONFIRMED effect of its own (F10) and an OPEN
  transfer (F11); clauses 2 and 3 on nulls inside their MDEs, which
  license neither confidence nor deletion;
- the **wiring line**, on the dead-text result and the 18/18-vs-0/18
  extraction rates;
- and a stopped measurement line, closed by an affordability decision rather
  than a verdict.

## 4.6 What this chapter claims, and no more

The Finding Floor reduces Critical/Major `not-a-defect` findings on F10 —
**CONFIRMED under the registered-output-path attribution**, on a fixed-n,
no-peek round whose rule and analysis code predate its data, with the interval
[−2.39, −1.07] stating the size. The attribution is an after-the-fact
adjudication of a case the protocol left unranked, and under the other reading
the round is descriptive only (§4.2.1); the grade is never to be quoted without
it. On F9 the
effect is MEASURED; round 17's F10 repeat stays qualified replication evidence,
its post-hoc extension not repaired by a later round. **Confirmation on one
fixture is not REPLICATED and does not establish fixture-independence.**
Coverage shows no detectable change in every round that measured it, which is
an absence of evidence against a margin nobody declared. Round 24's six
unimplemented RECORDED outputs — including the registered index-paired
sensitivity analysis — were published as missing rather than computed after
unblinding, and that limitation travels with its result. Clause 1 is the
only component with positive evidence, on F10 — CONFIRMED there and OPEN on
F11, where one round was a powered non-detection and the next was ruled
ineligible for confirmatory inference by its own gate. Clause 2 alone shows
no detectable difference from no floor at the powers run; clause 3 has no
positive evidence and no licensed deletion. Every absolute number inherits the
adjudication assumption of §7.1.1, panel error sits in the contrasts in
principle, and nothing in this chapter extends beyond the three fixtures
named — F9, F10, F11 — or the model epoch all of them share.
