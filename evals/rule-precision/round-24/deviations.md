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

## 5. The delivery envelope — a transport amendment, and the text change it makes

**The review brief is not edited.** Enforcing the rule above by rewriting the
brief's Output section would make "the instrument is unchanged" false, which is
a worse price than the problem. The output-path line that indices 1–4 already
carried is instead replaced by a fixed **delivery envelope**, appended verbatim
after the pinned brief:

```
1c4102d8129ff9fc1c0b9877e90473d62ad845a7  rule-precision/round-24/delivery-envelope.md
```

It carries the output path, requires `Write` and forbids the shell route, allows
exactly one `Write` retry, and forbids the reply from containing, quoting,
summarising or counting findings. Review criteria are untouched and the envelope
is byte-identical in both arms.

**The text agents receive therefore changes mid-round, and that is recorded
rather than hidden:** indices 1–4 ran under the old envelope — a bare
"Your output path is …" line — and indices 6–12 under this one. Index 5 is void.
This is a transport-layer forward operational amendment, not a change to the
review criteria. The primary analysis is unchanged; if a pre/post-envelope
comparison is ever wanted it is descriptive and secondary.

`compose-prompt.py` builds every prompt and checks rather than trusts: the slot
is substituted exactly once, the path is the one `measurement-outputs.tsv`
reserved for that (index, arm, part), the prompt is exactly brief + separator +
envelope with nothing added by hand, and W and N are identical modulo the
catalogue and output paths. `--verify-sent <agent_id>` compares the composed
prompt against what the transcript shows the agent actually received, so the
check survives the one step a script cannot perform.

### `review-06-N-a`, first attempt: replaced

The first index-6 agent was launched from a hand-built prompt in which the
output-path line had been **replaced** by the new instructions rather than
augmented, so it was never told where to write. It made twelve tool calls, zero
write-path calls, produced no file, and replied `DONE`. No review content was
exposed.

That is the exchange rule's first branch — no valid output, nothing read — so it
is **replaced at the same index, arm and part**, and index 6 is not voided. The
fault was the orchestrator's, not the agent's, and it is the reason the prompt is
now composed by a script instead of by hand. Its cost stays in the record:
`replaced-agents.tsv`, 12 calls, 0 tool errors, 590,525 raw tokens.
