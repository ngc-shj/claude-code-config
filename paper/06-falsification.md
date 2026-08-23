# 6. Cheap falsification: three optimization candidates, zero review agents

Chapter 5 established what a review costs and where the cost sits: in round 22,
≈421.6k raw tokens per review agent across a mean of 7.6 requests, 93.6% of it
transport — the same content re-sent — rather than new bytes (MEASURED;
`../evals/rule-precision/review-efficiency/`). A cost with that shape invites
optimization, and this chapter is about three attempts to buy it down, on
three examined axes of the delivery pipeline: **what** is read, **when** it is
fetched, and **who** selects it. Three axes were examined; nothing below
claims they are all the axes there are. All three were **REPLAY-REFUTED**
below a pre-declared investment bar by causal replay over pinned transcripts
(§7.2) — trace-conditional verdicts, per the identification assumption stated
in the scope bullets below — and the price of all three
verdicts together was **zero new review agents**: every figure derives from the
150 round-22 transcripts that already existed
(`../evals/README.md`, "the closed search"). One property of that corpus scopes
every verdict below: round 22's reviews are **three identical generalists per
review** (`../evals/rule-precision/round-22/measure.py`), while the shipped
skill runs three specialised roles — so each refutation binds its intervention
**on the round-22 generalist configuration**, and rule-use unions, request
orderings and packet coverage under the specialist split are untested by these
replays.

Three scope statements govern everything below.

- **The bar is an investment threshold, not an adoption criterion.** A
  candidate below 20% raw-token reduction is not worth a forward test; one
  above it has earned nothing but the next, more expensive question
  (`../evals/rule-precision/GOAL.md`).
- **Each refutation binds the intervention as fixed in its protocol, and is
  trace-conditional.** A reformulation voids the protocol (§7.2.1); one
  refutation below explicitly withholds its family claim for exactly that
  reason; and every verdict assumes reviewer behaviour under the intervention
  matches the replayed behaviour — the identification assumption §7.4 names
  and Chapter 8's validation is designed to test.
- **Every refutation verdict rests on one fixture** — F11, round 22 — and
  binds the interventions' perfect forms through oracle bounds. Some reported
  figures price implementations rather than bounds (the blind compiler below)
  and are labelled as such. The chapter shows three refutations, not the
  exhaustion of a direction space; the goal these candidates served is unmet
  and its resume conditions are fixed (`../evals/rule-precision/GOAL.md`).

The candidates are presented in the order they were priced, because each
refutation located the constraint the next candidate was built to escape.

## 6.1 The shared frame

All three protocols share the replay contract of §7.2 and differ only in the
intervention they fix: pinned transcripts under checked manifests;
token-saving quantities modelled from bytes and evaluated at three
calibrations (3.5, 3.8, 4.2 bytes/token), so each saving is reported as a
bracket; the request-elimination, carry, and
relocated-output accounting of §7.2.3; and the bound discipline of §7.2.2 —
only an upper bound below the bar refutes. Their amendment records are
post-result directional corrections in the sense of §7.3, and this chapter
treats them as data about the method: fourteen across the three protocols.
Several moved verdicts — the routing ceiling's own history reversed its gate
more than once (§6.2) — and §6.3 reports, in place, the two crossings of the
bar inside the batching protocol.

## 6.2 What is read: evidence-gated row routing

**The intervention, as fixed:** open a rule's compact row only when a concrete
`file:line` in the change can be cited for it; read a rule-detail page only
when the row points to a mandatory one. Nothing else changes
(`../evals/rule-precision/routing-trim/protocol.md`).

**Gate 0 — remove everything, and ask what that is worth.** The cheapest
question first: deleting 100% of what the intervention gates — rows and the
pages they point to — is worth 27.55–28.73% of the round (MEASURED;
`../evals/rule-precision/routing-trim/README.md`). Above the bar, so the
perfect form is worth pricing and Gate 0 cannot end the line. Two structural
facts from the same computation shaped everything after it: a row fetch almost
always shares its request with out-of-scope results, so **rows alone** are
worth only 5.76–6.59% — removing bytes rarely removes a round trip — and most
of the ceiling is vanished requests rather than removed content (the trip term
is 21.67 of the 27.55–28.73 points).

**Gate 1 — keep what the reviewer actually used.** Four oracle retention
rules, pre-registered strictest-first, each deciding from what the agent did
*after* reading — bounds no implementable gate can beat. Retaining only the
rules an agent cited in its own findings (G1) saves **9.92–10.89%**; adding
the pages it opened (G2), 3.66%; unioning across the review's three reviewers
(G3), 2.82%; across both arms (G4), 2.46% — every upper end below the bar at
every calibration, so the candidate is **REPLAY-REFUTED**
(`../evals/rule-precision/routing-trim/README.md`, Gate 1).

The collapse has two measured mechanisms. From G2 on, every page the agent
opened is retained by construction, so those rules gate rows alone — and Gate
0 had already priced removing *all* rows at 5.76–6.59%. And half of G1's
saving is not a gate at all: 21 of 150 agents cite no rule in any finding, and
for them the oracle deletes the whole catalogue because it knows in advance
the reviewer will never name one — 5.48 points of the 10.89 come from those
21 agents (MEASURED; `../evals/rule-precision/routing-trim/README.md`,
"where G1's 10.89% comes from"). No implementable gate has that foreknowledge.

**The verdict's history is part of the result.** The quantity first called a
ceiling was found not to be one three times — it omitted the vanished round
trip, then covered a narrower intervention than the one fixed, then treated a
lower bound as refuting — and a classifier once counted the reviewer's own
written output as catalogue fetches, moving the verdict across the bar until
behavioural tests pinned the fix. Every correction is recorded in place with
its direction (`../evals/rule-precision/routing-trim/protocol.md`, six
amendments; the README's corrections list). The refutation that survived that
history carries one quantified dangerous-direction looseness, ≤0.03 points of
code-point byte counting, per §7.2.2's bounded-not-banished rule.

## 6.3 When it is fetched: catalogue batching

The routing refutation could reach transport only where a request's every
result vanished — its ceiling's 21.67 trip points are exactly that — and it
changed nothing about when the remaining fetches happen or how they aggregate.
That residue is the second candidate's target: 93.6% of the round is re-sent
context, and routing's own Gate 0 had measured 31.82% of the round sitting in
round trips the catalogue costs. **The intervention, as fixed:** keep every catalogue byte
the reviewer reads and issue the fetches in one turn, so one request ingests
every result (`../evals/rule-precision/request-batching/protocol.md`).

**Gate B0 — every round trip removed.** After two post-result amendments, the
figure is **25.25–25.60%** and the gate does not refute (MEASURED;
`../evals/rule-precision/request-batching/README.md`). The amendments are the
chapter's exhibit for §7.2.2, because the verdict crossed the bar twice before
settling. The first run credited removed requests with output their responses
still had to produce — 153 of 297 removed requests also wrote review text or
read the change, work that relocates rather than vanishes — and correcting
that took 23.77–23.97% to 19.32–19.52%, below the bar: a refutation. Asking
the mandated question — *what arrangement would have saved more?* — found the
answer: the batch needs no request of its own, because the fetches can be
issued in a turn that was happening anyway and ride a request that survives
for its own reasons — the one that reads the change. That took the ceiling to
25.25–25.60%, above the bar. Both moves are recorded with their directions.

**Gate B1 — the reviewer's own dependency order.** B0's arrangement assumes
the batch can land where the digest lands, which means knowing the candidate
rule IDs before reading the digest that produces them. B1 restores causality
— nothing derived from the digest may arrive before the request after it —
and measures the constraint: **the causal window is one request wide in all
150 agents** (MEASURED; the first catalogue result always arrives exactly one
request after the digest). The batch's host is forced, and the intervention
as fixed is worth **19.32–19.52%**: below the bar at every calibration,
**REPLAY-REFUTED**
(`../evals/rule-precision/request-batching/README.md`, Gate B1).

The refutation's reach was then narrowed rather than stretched. Two variants
outside the fixed intervention — batching only the fetches worth batching,
and deferring the host — reach 20.01% and 20.02% as measured, over the bar by
a hair's width; the four known approximations all run in their favour and are
worth 0.47 points (which would put them at 19.55%), but those are estimates
favouring refutation and the verdict does not lean on them. The protocol's
fifth amendment records the narrowing: **the gate refutes the intervention as
fixed and says nothing about every batching form** — a family claim the
arithmetic could not support.

## 6.4 Who selects: the deterministic packet compiler

The batching refutation established something narrower than a law: the
**fixed, digest-derived intervention** could not cross its own causal window,
because a reviewer whose choices derive from the digest cannot receive them
earlier than the digest. Other model-in-the-loop forms — selecting from the
diff directly, say — are unexamined. The third candidate steps around the
question by removing the chooser. **The intervention, as fixed:** the reviewer no longer
reads the digest and selects rows; a deterministic script derives one review
packet from the change and the catalogue, delivered once — k=3, the role
split, and the finding format unchanged
(`../evals/rule-precision/packet-compiler/protocol.md`). The protocol's
"role split unchanged" fixes the intervention; the replay that prices it runs
on the generalist corpus above, so the coverage unions below are generalist
unions, and the verdict carries that scope.

**Gate C0 — a witness, with no refutation path.** Handing each agent exactly
the material it turned out to use, at the digest's own arrival, is worth
**26.80–26.90%** — 28.05–28.15% at the best position the packet may legally
occupy (MEASURED; `../evals/rule-precision/packet-compiler/README.md`). Per
§7.2.2 this figure is a witness: it charges the command payload of historical
fetches the compiled form would never issue, so it understates, and a gate
built on it can only permit the next gate or be inconclusive. Its outcome
function cannot return a refutation, and a test pins that. The structural
reason the witness clears where batching could not is measured in this gate's
replay: **in 147 of 150 agents the request that ingests the digest also
ingests the change** (MEASURED; the compiler-gate README), so the packet
needs no request of its own — *and* the request the reviewer spent fetching
rows, which B1 was forced to keep alive as the batch's host, is gone
entirely.

**Gate C1 — one packet must serve every scored reviewer.** A compiler sees the
change, not the reviewer, and F11 is one change reviewed 25 times per arm —
so it emits one packet for all of them, and the protocol's coverage
condition — the packet carries every rule a scored review used, a miss being
a refutation rather than a cost, with the verdict read over the control arm's
holdout of 45 agents — triggers the union argument of §7.2.4, whose
conditions (fixed representation, fixed shared delivery, cost monotone in
members) all hold here. The cheapest covering packet for the control arm's holdout is the union
of what those 45 agents used: **46 of the 74 catalogue rules, 94.94 kB**,
worth **12.19–14.60%** — below the bar at every calibration,
**REPLAY-REFUTED**,
independently of any selection rule
(`../evals/rule-precision/packet-compiler/README.md`, Gate C1).

The flanking measurements locate the two tested endpoints — they do not
survey the space between. A compiler written blind
to the reviewers — 7 rules, 17.40 kB, from the catalogue's own trigger
vocabulary — would save 30.43–31.18% and covers **0 of 150** agents: the
measured blind packet was cheap and missed every agent. Delivering the whole catalogue covers everyone and saves
**−20.91% to −12.98%**: total packets cost more than they save, because 230 kB
rides every request from arrival onward. The measured cause is reviewer
disagreement: 54 of 74 rules were used by at least one agent in the round, 46
by the control holdout alone, against a mean of 18.2 per agent (MEASURED).
What follows is exactly two statements: every packet that covers the holdout
costs at least the union, so **no covering packet clears the bar** — and the
one sub-catalogue packet actually measured, the blind compile, covered
nobody. Whether some other small packet satisfies some other coverage
condition is not measured and not claimed.

Two records matter beyond the number. The dev/holdout split was fixed in a
commit containing no compiler and no measurement, because the author is an
input (§7.2.1) — and it then changed nothing, which is itself evidence the
union bound is fitted to nothing. And the third amendment moved the primary
from both arms to the control arm's own holdout **after** figures existed,
weakening the refutation from 7.96–10.96% to 12.19–14.60% — recorded in the
direction that demands scrutiny, and the verdict survived it.

## 6.5 What the three refutations establish, and what they do not

**Three separate measured reasons, not one** (`../evals/rule-precision/GOAL.md`,
closure). Routing died of thin removable mass: keeping what the reviews used
leaves an upper bound of 10.89%, vanished requests included. Batching died of
the causal window: one request wide in every agent, and the **fixed,
digest-derived intervention** could not cross it — no wider claim. Compilation
died of reviewer disagreement: covering the W holdout alone takes 46 of the 74
rules (54 of 74 across all 150 is the side figure). The three reasons were
discovered in that order, and each successor candidate escaped its
predecessor's constraint and met its own. All three verdicts are bounds on the
round-22 generalist configuration, per the corpus note in the chapter's
opening; none has been computed on specialist transcripts.

**What was bought, stated at its real size.** Three candidates were refuted
**without starting a forward review-agent experiment**: zero new review-agent
tokens. What that avoided, had a candidate advanced, is priced by the adoption
rule's floor — ≈222 agents, ≈94M raw / 65.5M api-eq at the audit's per-agent
figures (≈294 and ≈124M / 86.7M at the conservative sizing) — a comparison
with the next step, not a counterfactual claim about what would otherwise
have run. And the verdicts were not free: the protocols, the gate
implementations, the fourteen amendments and the human-and-model review that
forced them are real costs, uncounted here. The asymmetry that remains after
both qualifications is the thesis contribution: the expensive instrument —
forward review agents — was never spent on a candidate that a replay could
kill first.

**What was not bought.** No candidate passed, so the chain has never been
observed to pass anything — Chapter 7's missing positive control (§7.4). The
refutations bind fixed interventions at a chosen bar on one fixture; whether
the disagreement that killed the compiler is a property of F11 or of
reviewing is not known. And the goal all three candidates served — zero
Critical loss, distinct real claims at ≥95% of current k=3, Critical/Major
not-a-defect no worse, and raw tokens below current k=3, demonstrated on
forward data — is **unmet**: the line is closed with resume conditions, not
resolved (`../evals/rule-precision/GOAL.md`, status).
