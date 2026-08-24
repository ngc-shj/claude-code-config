# Round 24 — deviations

Declared as they happen, before the next batch runs. Nothing here is a
retrospective reconstruction.

## 1. Sub-agent model identifier differs from the orchestrator's

Registered intent: every role runs on the session model with **no per-call
override**. No override was passed, and the identifiers still differ —
orchestrator `claude-opus-5[1m]`, every review agent `claude-opus-5`. The `[1m]`
suffix is the 1M-context variant, a main-loop setting sub-agents do not inherit.
The reviewer-side model this round carries is **`claude-opus-5`**, observed from
the agents' own records rather than assumed.

## 2. The host kernel changed between the gate and the round

`6.17.0-1021-nvidia` at the reachability probe, `6.17.0-1031-nvidia` for the
review batches, across a reboot at 2026-08-24 00:28:06 JST. Everything that
could change what the gate measured was hash-verified unchanged before the round
started; a kernel version is an operational fact to declare, not an instrument
change to re-measure.

## 3. The measurement moved off `/tmp`

That same reboot destroyed the reachability probe's three review files, which
lived in `/tmp`. Registered as a forward operational amendment before any review
agent ran: arms, briefs and all 72 outputs are written directly to
`/home/noguchi/.local/state/claude-code-config/round-24-measurement/`.

## 4. Index 5 is VOID in both arms — a no-peek breach and a broken `Write`

**This is the one that costs the round something: final n = 11, not 12.**

### What happened

All six index-5 agents launched together at 2026-08-23T18:28–18:29Z. The `Write`
tool was failing for all of them — `PreToolUse hook did not respond before its
timeout (host client may be unreachable)` — and every one of the six logged tool
errors, twenty across the batch against zero in the previous twenty-four agents.

Three agents (W-a, W-b, N-b) worked around it by writing their review through a
`Bash` heredoc and landed a file. Three (W-c, N-a, N-c) kept retrying `Write` and
were terminated at 2026-08-23T21:50:04Z, within seven milliseconds of each other
— a process teardown, not three independent failures.

### The breach

`review-05-W-a`'s reply to the orchestrator did not stop at `DONE`. It carried a
summary of its own output:

> 10 Critical, 14 Major, 5 Minor … 29 findings

**That is an arm-dependent precursor of the primary, for one arm of one index,
and it is now in the orchestrator's context.** It was volunteered rather than
sought, and that changes nothing: the exchange rule exists precisely so that
"it probably didn't matter" is not a judgement anyone gets to make afterwards.

### The decision, by the registered rule

> If any of its output has been read — including a partial extraction — the
> replacement is not permitted. The whole review index is voided **in both arms**
> so the arms stay balanced, and **n falls to 11 rather than being backfilled.**

Applied as written:

- index 5 is **`void` in both arms**; no agent is replaced;
- the three landed files are **not** inputs to extraction, clustering,
  adjudication or any metric. They are held unread and hash-pinned under
  `voided/index-05/` with an `EXCLUDED.txt` beside them;
- the three missing files are **not** recovered;
- all six agents' tool calls, failures and tokens stay in the cost and execution
  record — `voided-index-05.tsv` — because the round spent them.

n = 11 clears the pre-registered design-integrity floor (n ≥ 11 is analysed as
registered), so the round continues without an extension and without a peek.

### Counts, kept distinct

| | |
|---|---|
| review agents launched | **30** |
| outputs landed | **27** |
| analysable, indices 1–4 | **24** |
| voided, index 5 | 6 launched, 3 landed, 0 analysable |

### Forward rule: `Write` is the only valid landing path

Registered here, effective from batch 6:

- **A review counts as landed only if the brief's `Write` produced it.** A file
  written through `Bash`/heredoc is **not** a valid output, whatever it contains.
  The shell route bypasses the hook and the output boundary, and puts review
  prose into a command transcript where trace inspection can hit it.
- A `Write` that fails once and is retried **with `Write`** to a successful
  landing is a complete review.
- No valid `Write` output **and** no review content exposed → replace at the same
  index, arm and part, per the exchange rule's first branch.
- Review content exposed, in a reply or seen during trace inspection → **no
  replacement; void the index in both arms.**
- A bare diagnostic — "Write failed", with no review content — is **not**
  reading the output and does not trigger a void.

Indices 6–12 run to completion with no outcome-dependent stopping. Only quota
and technical success decide what happens next; index 5's leak is sealed as an
excluded observation and does not inform any later choice.
