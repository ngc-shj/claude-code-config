# Protocol — deterministic review-packet compiler

**Written before any saving figure was computed.** The git history cannot evidence
that ordering, because this document and the first result will land in the same
commit; treat it as the author's account.

This protocol governs one candidate and the order in which it may be evaluated.
It authorises no change to any skill.

## Why this is a new protocol

Two candidates have been refuted on this fixture, and each one failed for a reason
that this one does not inherit:

- `../routing-trim/` cut **what** the reviewer reads. Refuted at its Gate 1:
  9.92–10.89% against a 20% bar.
- `../request-batching/` moved **when** the reviewer's own fetches arrive.
  Refuted at its Gate B1: 19.32–19.52%. The binding constraint was found there —
  the causal window between the digest arriving and the first catalogue result
  arriving is **one request wide in all 150 agents**, so a form that keeps the
  model in the selection loop cannot cross it.

This candidate takes the selection out of the loop entirely. It is not a
reformulation of either: nothing is dropped, and no fetch of the model's is
rescheduled, because the model issues none.

## The intervention, fixed

> **Deterministic review-packet compiler.** The reviewer no longer reads the
> digest and then chooses rows and detail pages. A deterministic script derives
> the packet from the change and the catalogue, and it arrives once. k=3, the role
> split, and the finding format are unchanged.

**No variant of this is evaluated.** If the intervention is reformulated, this
protocol is void and a new one is written.

## Adoption rule, lexicographic — not scalarised

Unchanged from the two protocols before it:

1. zero loss of Critical real claims;
2. distinct real claims reached ≥ **95%** of current k=3;
3. C/M not-a-defect no worse;
4. among candidates passing 1–3, **minimum raw processed tokens**;
5. api-eq is a secondary readout only.

The compiler changes what reaches the reviewer, so 1–3 are live here in a way they
were not for batching, and only the forward test can settle them.

## Gates, in order

Each gate can only terminate the line of work or permit the next one. **No gate
permits shipping.**

### Gate C0 — the compiled ceiling (0 agents, oracle packet)

Recompute the round under four changes and nothing else:

1. **the digest content is removed.** The compiler replaces the step it served;
   its bytes are saved where it was ingested and in every surviving request that
   would have re-sent it.
2. **every catalogue result the agent actually read — rows, detail pages,
   directory listings — becomes one packet**, ingested at the request that used to
   ingest the digest. This is an oracle packet: it is exactly what that agent
   turned out to need, which no compiler can know in advance, so it bounds every
   compiler from above.
3. **the round is rebuilt.** A request whose every ingested result is now in the
   packet is not made. Its **context** is saved; its **output** only if that
   response issued nothing but the fetches the packet replaces — a response that
   also wrote the review has work that relocates and is paid wherever it lands.
4. **the moved bytes are charged where they now sit.** Each packet member is
   re-sent by every surviving request between the packet and where it used to
   arrive, and its **command payload is charged with it**.

Bytes are counted in UTF-8. Tokens are modelled from bytes at three
bytes/token calibrations, so every figure is a model-based bracket.

**Where the packet lands** is fixed at the digest's own arrival, per the clause
above. Because a later position would carry less, the figure is also computed at
**every position the packet could legally occupy** — no later than the request
that first ingested a catalogue result, since the reviewer used it there — and the
larger is reported. A ceiling taken on a closed-form rule's word is how the two
previous protocols got a verdict wrong three times between them.

**If the saving is below 20% of raw processed tokens at every calibration, the
line of work stops here.** No proxy, replay, telemetry, or forward test can rescue
an intervention whose perfect form does not clear the bar.

### Gate C1 — the compiler itself (0 agents), only if C0 passes

Write the compiler. Its **only** inputs are the pinned diff and the catalogue at
the pinned commit — never an agent's behaviour, never an adjudication. Replay it:

- the packet it produces, its size, and the requests it removes;
- **a run that misses any rule the agent historically opened is a refutation**,
  not a cost — the packet has to carry what the review used;
- pages it adds that nobody read are charged as real bytes.

Only if the replayed figure still clears 20% does the work proceed to a small
forward test under the adoption rule above. The forward test is what checks claims
reached, and nothing before it does.

## What this protocol will not do

- It will not report a saving without saying which gate produced it and whether
  that figure is an oracle bound.
- It will not treat a passed gate as evidence the intervention works.
- It will not omit the early-carry penalty, or the command payloads, from any
  figure it calls a saving.
- It will not claim a refutation wider than the intervention it fixed.
- It will not compare across fixtures: everything here is F11 unless stated.
