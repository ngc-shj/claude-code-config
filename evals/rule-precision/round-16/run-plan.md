# Window 1 run plan

Written before the first arm agent runs, because every choice below could
otherwise be made after seeing output and would then be unfalsifiable. The
protocol (`../../rule-ablation/protocols/round-16.md`) fixes the arms, the
metrics, n, and the decision rule; it does not fix these, and they have to be
fixed by someone.

## The unit of the design is the review, and a review is a matched triple

Per review k: **3 base agents → titles → 3 T and 3 TS on the same titles.**

The base is generated fresh on F10 — round 15 could inherit a base from round
13's stored replies, and there is no stored batch for a fixture that did not
exist yesterday. Both arms read the **same** `titles-k.md`, which is what makes
review k a matched pair rather than two independent draws; the pairing is the
whole reason two windows may be pooled at all.

Window 1 is reviews 1–10. 10 × (3 + 3 + 3) = **90 agents**.

## Preambles, fixed here

Review k uses preamble p*k* in **all nine** of its agents — base, T and TS
alike. A preamble that differed between arms would be a second variable; one
that were constant across reviews would make ten reviews ten samples of one
prompt, which round 11 already rejected.

p1–p8 are round 11's, unchanged. p9 and p10 are new, written in the same
register — framing only, naming no part of the diff and no kind of defect:

| | |
|---|---|
| p1 | (plain — no extra framing) |
| p2 | Work independently; do not assume any particular defect is present. |
| p3 | This change is going to production; review it as the last check before it ships. |
| p4 | Be concrete. A finding another engineer cannot act on is not a finding. |
| p5 | The change is large. Budget your attention across all eight files rather than the first two. |
| p6 | Report what you find in the order you would want it fixed. |
| p7 | Assume the author is competent and was pressed for time. |
| p8 | Someone has already read this diff once. You are the second pair of eyes. |
| p9 | Take the change on its own terms; the author had reasons you cannot see. |
| p10 | Write for a reader who will fix these in one sitting. |

**p8 is worth a note.** "You are the second pair of eyes" says something the
conditioned arms are also told structurally, so in review 8 the framing and the
treatment point the same way. It is applied identically to base, T and TS, so it
cannot separate the arms — but review 8's base is primed in a way the other nine
are not, and if review 8 is an outlier on the primary that is the first thing to
look at. Recorded now so it is not discovered later as an explanation.

## What is recorded per agent, and what is not

Recorded: the reply, the arm, the review, the reviewer position, and the
completion report's token count. The protocol lists **tokens per arm** as a
"recorded, not claimed" quantity and that is where it comes from — the rate-limit
percentages are not available in this environment (`README.md`), and a token
count is not a share of a weekly window, so the two are never substituted for
each other.

Not recorded, because nothing may condition on it before both windows are done:
any count of findings per arm, any verdict, any comparison. The manipulation
check below is the single exception and its scope is stated.

## The manipulation check, and its exact scope

Standard since round 12: verify the treatment arrived before paying for the
rest. After **reviews 1–2 only** (18 agents), record for each arm: replies,
findings written, replies ending in `No findings`. Nothing else is computed, and
no metric, threshold or prediction is changed after seeing it.

The mechanism the protocol names is `No findings` replies. Read
`README.md` § "The manipulation is smaller than the protocol implies" before
interpreting a zero: T's own brief already licenses `No findings`, so a zero in
**both** arms falsifies the premise that a reviewer takes an offered escape
hatch, not TS's wording.

## The variance check, which decides whether window 2 is affordable

After all 10 reviews of window 1 are clustered and adjudicated, recompute the
paired sd of both metrics from the 10 differences. If either exceeds **×1.15**
of the borrowed value (2.32 primary, 2.53 control), window 2 is re-sized before
it runs. This is keyed to the variance only. **The effect estimate is not
looked at until both windows are complete** — including by whoever runs the
variance check, which is why that check computes sds and prints nothing else.

## Order of operations

1. 10 × 3 base agents → `base/raw/`
2. titles extracted mechanically → `base/titles-k.md` (one title per line, no
   file, no severity, no explanation — the extraction is a script, not an agent,
   so it cannot summarise or select)
3. 10 × 3 T and 10 × 3 TS, each pair reading the same `titles-k.md`
4. findings extracted to `findings.tsv`
5. clustering against the seed inventory: only claims the seed does not already
   carry go to adjudication
6. adjudication of the new claims **after window 2**, per the protocol's
   append-only rule — window 1's new claims are held, not judged, so no verdict
   is drawn under knowledge of window 1's result

Step 6 is the one that costs discipline: window 1's numbers cannot be computed
until window 2's claims are adjudicated alongside them.
