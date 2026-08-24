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

## 7. Clustering blocked by API 529 — twice, with nothing exposed

Two attempts at the eight-agent clustering fan-out, at 2026-08-24T14:25:20–14:26:51
and 14:34:02–14:35:34 JST, ended with **all eight agents terminating on
`API Error: 529 Overloaded`** — the second attempt with fresh agent handles. A
server-side condition, not a round fault. The times are the transcripts' own
timestamps; an earlier draft of this section said "14:33" from memory.

**Delivery state after both attempts: nothing.** Zero of the eight registered
outputs exist, no partial artifact was written anywhere under the measurement
root, and the worktree is clean. There is nothing to quarantine.

**Correction: sixteen sub-agent transcripts were created.** This section
originally said none was, which was wrong — 8 per wave, and the error was found
only when the round's material was archived. They are preserved in the private
evidence archive at commit `fd84f1d`; the expanded prompt-verification record,
including this 16/16 result, is committed at `64e0823`. Checking them
**strengthens** the paragraph below rather than qualifying it: each of the sixteen matches exactly
one of the eight composed clustering prompts, every target appearing once per
wave; across all sixteen there are **zero `tool_use` blocks**, so no file was
opened or written; and the only assistant text any of them produced is the
server's `API Error: 529 Overloaded`. `--verify-sent` therefore has something to
check after all, and it passes 16/16.

**Content exposure: none.** The only thing received was the server's own failure
message. No claim, finding, severity, arm-side detail or review body reached the
orchestrator, by reply or by trace — now verifiable from the archived
transcripts rather than asserted from their absence.

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


## 8. Six RECORDED outputs were never implemented, and were not computed after unblinding

The protocol registers, beyond the three metrics, a RECORDED list (§Metrics
item 4) and an index-paired **sensitivity analysis** (§Inference). Six of those
items have no implementation in `measure.py`:

| item | registered in |
| --- | --- |
| `wrong` claims per review | §Metrics 4 |
| the Critical/Major-to-Minor ratio | §Metrics 4 |
| new claims' per-arm share of the primary | §Metrics 4 (the count is produced; the share is not) |
| per-agent tokens for the 66 executed reviews | §Metrics 4 — `batches.tsv` carries no `raw_tokens` column, so tokens exist only for the voided and replaced agents |
| round 12's F9 data re-analysed as a Welch interval | §Metrics 4 |
| the index-paired sensitivity analysis | §Inference |

**When it was found: after unblinding**, while checking `result.txt` and
`result-bridge.txt` against the protocol clause by clause. It was not found
earlier because nothing looked for it — `measure.py` was reviewed hard on the
confirmatory path, its inputs and its gates, and no test asserted that the
RECORDED list was covered. The protocol's own §"The analysis is committed with
the protocol" makes the confirmatory promise enforceable and says nothing about
the recorded one, so a check that would have caught this had no place to live.

**Decision: not computed.** Two of the six are derivable in a few lines from
figures already published, which is the argument for computing them and the
reason not to. The round-12 clause was pre-registered in *this* protocol
precisely so that it could not be produced with this round's result already
known and then read as corroboration; the same objection applies to the other
five, and applying it selectively would be worse than applying it to none. A
number computed after the fact can be selected without anyone intending to
select it, and the point of the pre-registration is to make that impossible
rather than unlikely.

**What this does and does not touch.** None of the six is a gate, a
sensitivity condition on the primary, or an input to the confirmatory rule; the
primary's Welch interval and its verdict stand exactly as registered, computed
by code committed before the first review existed. What is lost is real
nonetheless: the index-paired sensitivity analysis was registered to show
whether the independent-groups choice mattered, and its absence is published as
a limitation, not as a null, a non-significant result, or an optional extra.
The RECORDED list is **incomplete**, and it is published incomplete.

**Forward, and not applied to this round:** a protocol's recorded outputs need
the same enforcement its confirmatory path has — a test that fails when the
analysis does not produce an item the protocol lists. That is a change to how
the next round is built. Nothing about it is retrofitted here.

The duplicate `## 6.` heading in this file was corrected to `## 7.` when this
section was added; no text of that section changed.

## 9. Index attribution: adjudicated after the fact, not pre-registered

Section 5 records what happened and what was decided at the time; it is left as
written. This section records what a later review established about the
*authority* for that decision, which is a different question and a weaker
answer than section 5's wording implies.

### The ambiguity

`a8a7edbfa562f5d95` was launched as **index 6, arm N, part a**, and wrote to the
registered path for **index 5, arm N, part a**. Part of that file's raw text was
then read. The exchange rule says a read output means "the whole review index is
voided in both arms" — but it never says which index, because it never
anticipates the launch slot and the output path naming different ones.

Two readings follow, and the protocol chooses neither:

- **the registered output path decides** — the file is index 5's N-a slot, index
  5 was already void, nothing further is voided, index 6 is re-run, **n = 11**;
- **the launch slot decides** — the agent was index 6's, so index 6 is voided in
  both arms too, **n = 10**, and by the registered design-integrity floor the
  round would be **DESCRIPTIVE ONLY**: no confirmatory claim, no grade moved.

Round 24 took the first reading. **The alternative interval at n = 10 has not
been computed and will not be** — producing it now, with the result known, is
the selection this round's structure exists to prevent, and the choice between
readings is not improved by seeing what each pays.

### What existed before the round, and what did not

Searched at the protocol baseline `9f4026c` and at `39de187`, the last commit
before any review agent ran.

**Existed:**

- `measurement-outputs.tsv` — a committed bijection of (index, arm, part) to
  path, all 72 rows, written before any output existed;
- `register-outputs.py`'s docstring: *"Extraction takes these paths explicitly.
  It never globs `*.md` over a shared tree."* The analysed content of a slot is
  defined as whatever is at that path — the writer is not part of the
  definition;
- protocol §"n comes from a manifest": `reviews.tsv` keys the round on the 24
  registered (index × arm) pairs.

**Did not exist:**

- any wording anywhere anticipating launch slot ≠ output path, or ranking them;
- `compose-prompt.py`, which mechanically binds a prompt's path to its
  registered slot — it was written at `f07d53a`, *after* this incident and
  because of it.

So the registry settles **which file feeds which metric**. It does not settle
**which index an agent's failure voids**, and the second does not follow from
the first. Section 5's phrase "already assigned to void index 5 by its explicit
registered output path" is a sound reading of a pre-registered artifact, but it
is a reading made afterwards, not a rule applied.

### The timeline, which supports the reading without establishing it

| time (JST) | commit | event |
| --- | --- | --- |
| — | `39de187` | the 72-path registry is committed, before any review agent runs |
| 08-24 10:16:35 | `db67210` | **index 5 voided in both arms** — cause: `review-05-W-a`'s severity summary reaching the orchestrator and a broken `Write`. Nothing to do with the index-6 agent |
| 08-24 10:35:47 | `f07d53a` | the delivery envelope, `compose-prompt.py`, and this incident's record |
| 08-24 11:24:38 | `9e16a55` | the late file `ca19f223…` pinned into `voided-index-05.tsv` as `5 / N / a` |

Index 5 was already void, for an independent cause, nineteen minutes before the
incident was recorded. Under the path reading the stale write added a file to an
already-void index and changed nothing. That is a fact about ordering, not a
pre-registered priority.

The honest counter-argument is also on record: the twelve indices are
replicates of the same (arm, fixture) cell, so what an authorizer saw was
N-arm review text whatever index it is labelled, and the exchange rule's purpose
— drop one index-pair, keep the arms balanced — is satisfied once under the
path reading and twice under the slot reading. Neither is the registered answer,
because there is no registered answer.

### Consequence for the grade

**The result is reported as CONFIRMED (F10) under the registered-output-path
attribution**, and nowhere as an unconditional CONFIRMED. The round README, the
ledger and the chapter each carry the condition and the alternative in the same
place as the grade. The committed registered-output-path analysis is unchanged:
it produces −1.73, CI [−2.39, −1.07], n = 11. **Under the launch-slot reading
n would be 10** — `reviews.tsv` would carry index 6 as void in both arms and
`manifest()` would return one fewer index — and the round would be descriptive
only. No alternative interval has been computed.

### Forward, not applied here

A future protocol's exchange rule must state which of launch slot and registered
output path determines the index when they diverge, and its prompt composer must
make divergence impossible in the first place — round 24's does, from
`f07d53a` onward, but that arrived one incident too late. Nothing is
retrofitted to this round.

## 10. Replacement ledger completed, and where the protocol says it should live

`replaced-agents.tsv` carried `replaced=pending` on index 7's six Codex
continuation attempts long after their compliant replacements had run and
landed. The ledger is now final: every row reads `replaced=yes` and carries a
new `replacement_agent_id` column naming the agent that filled the slot, matched
against `batches.tsv`. No measured value depends on this file — nothing in
`measure.py`, no test and no other script reads it — and none of the six
quarantined outputs was ever opened.

The protocol says something different from what the round did:

> Every replacement and every void is written to `round-24/reviews.tsv` as it
> happens, with its cause.

`reviews.tsv` holds the two voids with their cause, and holds the 24 registered
(index × arm) pairs and nothing else — it is the manifest `manifest()` reads to
fix n. Replacement history went to `replaced-agents.tsv` and
`quarantined-outputs.tsv` instead. **That divergence is a deviation and is
recorded as one.** `reviews.tsv` is deliberately not amended now: it is an
analysis input, and adding rows to it after unblinding would touch the path n is
derived from to fix a bookkeeping defect that does not affect n.

## 11. `measure.py` does not reject a finding in two clusters — forward only

`assignment()` builds its finding-to-cluster map by plain assignment, so a
finding id appearing in two clusters would silently take the later one instead
of failing. Round 24's committed data does not exercise it: 1765 findings, 1765
distinct membership entries, no id in more than one cluster, no unclustered
finding and no unknown id — verified structurally against the committed
`clusters.tsv`, and `apply-merge.py` regenerates the same file byte-for-byte.

This is registered as a **gate a future round's analysis should carry**, and
nothing more. `measure.py` is frozen, its outputs are committed, and a code
change now would invalidate the byte-identity that makes those outputs
checkable.
