# Round 9 protocol — obligation (c) per-variant rewording (written before any run output was read)

## Question

Round 8 found P5 (isolation) transmits 8/8 on the ALS fixture but 1/8 on the
GUC fixture even when carried: the clause's "fresh frame" wording fits one
idiom and buries the connection-handle variant mid-sentence. Does rewording (c)
into two named variants transmit P5 for the GUC case, without disturbing
anything else?

## Arms

- **Cnew** — HEAD materials with the reworded (c): variants split, ALL-CAPS
  anchors (FRESH FRAME / ONE HANDLE), the pooled-connection failure mode stated
  concretely, and "name which variant applies" made an explicit obligation.
- **Cold** — round-8 arm E materials (extension with the original (c)),
  re-run fresh so the F6 comparison is same-batch.

## Cells

- F6 × Cnew, n=8 (primary)
- F6 × Cold, n=8 (same-batch control; round-8 reference: P5 = 1/8)
- F9 × Cnew, n=8 (regression check vs round-8 F9·E, cross-batch, expect P5
  stays at/near 8/8 and no other property moves)

24 runs, same prompts, same eight paired preambles.

## Scoring

Blind: 24 outputs redacted (same pipeline as round 8), shuffled into one set,
three scorers vs the round-5 nine-property rubric, majority vote.

## Pre-registered predictions

- Primary: P5 on F6 rises Cnew > Cold (reference floor: 1/8).
- Regression: F9·Cnew P5 ≥ 7/8; P3/P4/P8/P9 stay saturated in all three cells;
  P1/P2/P7 stay 8/8 everywhere.
- Claim only if the F6 rise appears AND no regression cell moves by more than
  noise (±1). A same-direction miss on F9 kills the claim regardless of F6.
