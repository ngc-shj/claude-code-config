# Deterministic review-packet compiler — Gate C1 refutes it

**Gate C0 handed each agent the packet it turned out to need and reached
26.80–26.90% against a 20% bar. A real compiler cannot do that: it sees the change,
not the reviewer, so it emits ONE packet for the fixture — and one packet that
carries what every review used is worth **12.19–14.60%** on the control arm's
holdout. The line
stops. Nothing is adopted, nothing is implemented, and no agents were spent.** `protocol.md` fixes the gates and carries
three amendments. `gate_c0.py` reproduces the Gate C0 figures and `gate_c1.py` the
Gate C1 ones; each stops unless the transcripts, the agent-to-review mapping, the
catalogue and the diff are the ones these numbers came from.

**That figure is a WITNESS, not a ceiling.** It charges the command payload of
every historical `rg`, `cat` and listing as if it moved into the packet, and the
compiled form issues none of them — one compiler command replaces the lot. So it
**understates** the saving: one arrangement the intervention can reach, priced
with a cost it would not pay. A witness above the bar shows the perfect form
clears it; a witness *below* the bar would have shown nothing, and Gate C0 could
not have refuted on this arithmetic. The protocol's first amendment records that.

**The packet is an oracle.** It is exactly what that agent turned out to need,
which no compiler can know in advance. Gate C1 writes the compiler, gives it only
the pinned diff and catalogue, and prices what it actually produces.

## Why this candidate, after two refutations

| candidate | what it changed | verdict |
|---|---|---|
| `../routing-trim/` | **what** the reviewer reads | refuted, 9.92–10.89% |
| `../request-batching/` | **when** the reviewer's own fetches arrive | refuted, 19.32–19.52% |
| this one | **who selects and fetches** — the model, or a script | Gate C0 does not refute |

The second refutation located the constraint rather than just failing: the window
between the digest arriving and the first catalogue result arriving is **one
request wide in all 150 agents**. Anything that leaves the model choosing what to
read has to cross that gap and cannot. Taking the selection out of the request
chain is the one move that does not have to.

## Gate C0 — the digest is not read and the packet arrives once

Four changes and nothing else:

- **removed** — the digest content. The compiler replaces the step it served, so
  its bytes go from where it was ingested and from every surviving request that
  would have re-sent it. Credited only where the request still happens: an
  eliminated request's whole cost is already in the trip term.
- **trip** — a request whose every ingested result is now in the packet is not
  made. Its context always; its output only if that response issued nothing but
  the fetches the packet replaces, because a response that also wrote the review
  has work that relocates.
- **carry** — each packet member is re-sent by every surviving request between the
  packet and where it used to arrive, **and its command payload moves with it**.
  That last charge is why this is a witness: the compiled form issues no such
  command, so the figure pays for something the intervention does not.
- **position** — fixed at the digest's own arrival, and separately computed at
  every position the packet could legally occupy, which is no later than where the
  reviewer first used it. The larger is what the verdict reads.

| | B/tok | digest | trip | carry | **WITNESS** | best position |
|---|---|---|---|---|---|---|
| packet at the digest's arrival | 3.5 | 2.79% | 27.36% | 3.34% | **26.80%** | 28.15% |
| | 3.8 | 2.57% | 27.36% | 3.08% | **26.85%** | 28.10% |
| | 4.2 | 2.32% | 27.36% | 2.79% | **26.90%** | 28.05% |

Bytes are UTF-8 here. The two protocols before this one counted code points, which
understates a carry term; here the same bytes appear on both sides — removing the
digest is a saving denominated in them — so the correct measure is used outright.

## What the packet replaces

| round-22 review agents | |
|---|---|
| packet bytes per agent | mean 38.6 kB, median 38.6 kB, max 55 kB |
| digest bytes no longer read | mean 11.4 kB |
| fetches folded into it | mean 5.2, max 9 |
| requests removed per agent | mean 2.0, median 2, max 4 (of 7.6) |
| agents where the packet rides in a request that survives anyway | 147 of 150 |

That last row is why this clears where batching did not. The request that ingests
the digest almost always ingests the change as well, so the packet needs no
request of its own — and the one the reviewer had to spend fetching rows, which
Gate B1 was forced to keep alive as a host, is not needed at all.

## What was checked

- **the difference form against the round** — `saving()` subtracts what goes;
  `rebuilt()` costs the compiled round from scratch, request by request, with the
  digest taken out of each surviving context and the packet put into it. They
  agree for every agent, calibration and packet position.
- **no better position** — the fixed position is not assumed to be the best; every
  legal one is enumerated and the larger reported. This is the check that moved a
  verdict twice in `../request-batching/`.
- **seven cases in `tests/gate-c0-packet.bats`**, all synthetic. Every rule that
  decides the number was mutated and observed to go red: the host eliminated with
  the rest; the digest credited in requests that no longer happen; command
  payloads left behind; the packet allowed to arrive after it was used; the
  rebuilt round dropping the digest from requests that predate it.

## Gate C1 — the compiler, and why its selection rule does not matter

The packet in Gate C0 was per-agent. A compiler's is per-**change**, and F11 is one
change reviewed 25 times, so a compiler emits one packet that has to serve all 150
agents. The protocol's coverage condition — the packet carries every rule a review
used — then has a consequence that decides the gate without reference to any
selection rule:

> One packet must contain each agent's own set, so it must contain their **union**.
> The union is therefore the cheapest packet that can satisfy coverage, and its
> saving is an upper bound on **every** compiler's.

The control is **arm W** — `../GOAL.md` fixes that, W23 being the arm with clause 1
removed — so the figure the verdict reads is W's holdout, 45 agents, with the
covering packet built from those agents alone.

| packet | rules | pages | kB | W holdout | all 150 |
|---|---|---|---|---|---|
| `compiler.py`, blind and unadjusted | 7 | 3 | 17.40 | 0/45 | 0/150 |
| **union over the W holdout** (primary) | 46 | 12 | 94.94 | 45/45 | 147/150 |
| union over all 150 | 54 | 14 | 108.98 | 45/45 | 150/150 |
| the whole catalogue | 74 | 37 | 230.02 | 45/45 | 150/150 |

| saving, raw processed tokens | B/tok | **W holdout** | W dev | all 150 |
|---|---|---|---|---|
| `compiler.py` (covers nothing) | 3.5 | 31.18% | 33.36% | 31.88% |
| **union over the W holdout** | 3.5 | **12.19%** | 15.06% | 13.00% |
| | 4.2 | **14.60%** | 17.37% | 15.39% |
| the whole catalogue | 3.5 | −20.91% | −16.84% | −19.90% |

**Both refutation conditions fire, on different packets.** The blind compiler is
cheap and misses rules in every single agent; the packet that misses none reaches
14.60% at best, which is under three-quarters of the bar and not close enough to it
for any of the loose ends to matter. Delivering the whole catalogue costs *more* than it saves — the
230 kB is re-sent by every request after it arrives.

**54 of the 74 catalogue rules were used by at least one agent** (46 by the control
arm's holdout alone), and the mean agent used 18.2. That is the shape of the problem: reviewers do not agree on which
rules the change triggers, so a packet built to satisfy all of them is most of the
catalogue, and a packet small enough to save tokens cannot satisfy any of them.

### The split, and what it was for

`protocol.md`'s second amendment fixed **dev = reviews 1–10, holdout = 11–25**
before a line of the compiler was written — in commit `408e83d`, which contains no
compiler and no measurement. The reason: restricting the compiler's *runtime*
inputs to the diff and the catalogue does not stop the opened-rule set reaching it
through the author.

As it turned out the split changed nothing, and that is worth saying plainly. The
verdict rests on the union, which is not fitted to anything — no adjustment of
`compiler.py` on the dev split could have moved it, because no compiler beats the
union. The blind figure was recorded anyway, as the amendment required: **0 of 150
agents covered.**

The **third** amendment is a different matter: the first run took its union over
all 150 agents and scored both arms, which is not the control `../GOAL.md` fixes.
Scoping it to arm W's holdout **weakens** the refutation — 7.96–10.96% becomes
12.19–14.60% — and it was made after those figures existed, which is the direction
that needs recording rather than the one that excuses it.

### What was checked

- **The union really is the cheapest covering packet** — pinned as set logic, not
  argued in prose.
- **The inputs are checked, not merely printed.** Gate C1 stops unless the
  catalogue's path-and-content manifest, the diff's hash, and the agent-to-review
  manifest all match what these numbers came from, and unless arm W is complete at
  25 × 3. The agent side reuses `routing-trim/gate1.py`'s manifest and key check
  rather than restating them.
- **The compiler's own invocation is charged**, 140 bytes carried from the host
  onward. Leaving it out makes the saving larger, which is not a direction a
  refutation may be generous in.
- **The packet is charged to every surviving request from the host onward**, not to
  each member up to where it used to arrive. That is the difference between a
  compiler's packet and Gate C0's bundle, and it is worth points.
- **The digest and the historical fetches come back out** of every surviving
  context, and the host survives even when it fetched nothing but the digest —
  the case the first fixtures could not see, added after a mutation survived.
- **Eight cases in `tests/gate-c1-compiler.bats`**, all synthetic, with every rule
  mutated and observed to go red: the packet charged only to its old arrivals; the
  digest or the old fetches left in; the host eliminated with the rest; the
  compiler invocation left uncharged; generic tokens kept so every rule fires; the
  whole-catalogue baseline selecting nothing.

## What this does not license

- Gate C0 was not evidence that a compiler works: it has two outcomes, permitting
  Gate C1 or inconclusive, and refutation is not among them. Gate C1 is where the
  refutation came from.
- Gate C0's figure was not implementable, which is exactly what Gate C1 measured:
  the per-agent packet was worth 26.80% and the one-packet-for-the-fixture version
  that covers the same reviews is worth 12.19–14.60%.
- It says nothing about claims reached, in either direction. The refutation is on
  cost, under a coverage condition that was chosen precisely because claims reached
  cannot be measured without a forward test.
- It does not refute compiling a review packet in general. What is refuted is a
  packet that carries **every rule any of these reviewers read**, at a 20% bar, on
  this fixture. A weaker coverage condition is a different candidate and needs its
  own protocol — and it would have to say what licenses dropping a rule a review
  used.
- It does not adopt, implement, or schedule anything, and no forward design is
  written.
