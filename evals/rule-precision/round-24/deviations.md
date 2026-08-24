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

### `review-06-N-a`, first attempt: replaced; stale output quarantined

The first index-6 N-a agent, `a8a7edbfa562f5d95`, was launched from a
hand-built prompt carrying the stale registered path for `review-05-N-a`
instead of the registered `review-06-N-a` path. It made twelve tool calls and
eventually landed a late file at the stale path, with its claim marker. The
expected index-6 path remained absent.

The late file and claim marker were moved out of `reviews/` into the index-5
quarantine and are excluded from extraction, clustering, adjudication and every
metric. Its git-blob hash is pinned in `voided-index-05.tsv`. The attempt is
still a replacement for the missing registered index-6 N-a output; the valid
replacement subsequently received the exact composed prompt and landed at the
registered index-6 path. The fault was the orchestrator's, not the agent's, and
it is the reason the prompt is now composed by a script instead of by hand. Its
cost stays in both execution records: `replaced-agents.tsv` identifies the
failed index-6 attempt, and `voided-index-05.tsv` identifies the quarantined
stale-path artifact.

A prior authorizer saw partial raw text from this late quarantined review while
investigating the write. No arm value, finding count, severity or review text
was passed to the continuing authorizer. While confirming the physical
quarantine, the continuing authorizer mistakenly requested file metadata and
saw the late voided file's byte size. It did not open the file or see a size for
any usable review. This is recorded because review size was inside the no-peek
boundary even though the artifact was already excluded. No sample, metric,
analysis, replacement, exclusion or continuation rule changed after either
exposure. The exposed review was already assigned to void index 5 by its
explicit registered output path; index 5 remains void in both arms, final n
remains 11, and completed index 6 remains usable. The prior authorizer recused
before index 7 and is not consulted again.

## 6. Index 7 continuation attempt: invalid landings, replacement pending

The continuation environment exposed no `Write` tool to its six fresh review
agents. All six received the manifest-bound composed prompt, returned only
`DONE`, and put files at the six registered index-7 paths, but a delivery-only
audit established that each file was landed with `apply_patch`. No other write
mechanism was used. No review body, arm value, finding count, severity count or
content-derived quantity was read.

The forward rule fixed after index 5 is categorical: a review counts as landed
only if `Write` produced it. Therefore none of these six files is a valid
output. They were moved out of `reviews/` to
`quarantined/invalid-index-07-apply-patch/`, their blob identities were pinned
in `quarantined-outputs.tsv`, and they are excluded from extraction,
clustering, adjudication and every metric.

Because nothing from their review content was exposed, the exchange rule's
first branch applies: each agent is replaceable at the same index, arm and
part. Replacement is recorded as `pending` in `replaced-agents.tsv`, not as
completed. A fresh replacement cannot be launched from this environment
without knowingly repeating the same deterministic transport failure; index 7
therefore remains incomplete, not void, until a continuation environment with
the required `Write` tool is available. No sample, metric, analysis, exclusion,
replacement or continuation rule was changed.

No per-agent model override was requested. The exact continuation-agent model
identifier was not exposed, so the execution records say
`NOT-EXPOSED-CODEX-CONTINUATION` rather than guessing. This differs from the
previously observed `claude-opus-5` execution environment and must remain a
declared environment deviation even after compliant replacements run.

## 6. Clustering blocked by API 529 — twice, with nothing exposed

Two attempts at the eight-agent clustering fan-out, at 2026-08-24T14:25 and
14:33 JST, ended with **all eight agents terminating on `API Error: 529
Overloaded`** — the second attempt with fresh agent handles. A server-side
condition, not a round fault.

**Delivery state after both attempts: nothing.** Zero of the eight registered
outputs exist, no partial artifact was written anywhere under the measurement
root, no sub-agent transcript was created, and the worktree is clean. So
`--verify-sent` has nothing to check and there is nothing to quarantine.

**Content exposure: none.** The only thing received was the server's own failure
message. No claim, finding, severity, arm-side detail or review body reached the
orchestrator, by reply or by trace.

Unaffected and unchanged: `findings.tsv`, the eight packets, and
`cluster-outputs.tsv` with its eight composed prompts — the prompt hashes are
identical before and after both attempts.

### What is not concluded from this

**That eight concurrent agents caused it.** A 529 is capacity at the service, and
if the service has no capacity then two agents fail for the same reason eight do.
Cutting the fan-out would be a change made on an untested guess, so it is not
made. The recorded plan instead waits for the service condition to change, then
probes with a single sub-agent carrying no measurement data, then runs **one**
clustering slot with a fresh agent, then the rest one at a time — stopping the
moment a 529 recurs, with no automatic retry.

That ordering exists so that a server outage cannot be paid for in measurement
agents, and so that concurrency is only ever ruled in or out by evidence.

