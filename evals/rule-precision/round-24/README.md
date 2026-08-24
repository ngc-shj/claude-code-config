# Round 24 — preflight record

**No agent has been launched. No measurement exists.** This file records the
state the round would start from, written before the reachability probe and
before any review, so that what was true at the starting line is on record
rather than reconstructed afterwards.

Protocol: `../../rule-ablation/protocols/round-24.md`.
Reproduce everything below with:

```bash
evals/rule-precision/round-24/preflight.py --out <dir>
```

A plain run **compares every row of `preflight-manifest.tsv` against a fresh
build** and fails on any difference; it does not merely print hashes. `--write`
creates the manifest and **refuses to replace one that exists** — moving the
registered starting line takes `--re-register`, which says so loudly and is
never routine.

## Baseline

| | |
|---|---|
| protocol baseline commit | **`9f4026c11d6630cc451f0c479de0f906043c353a`** |
| | *Pre-register round 24: the clean F10 confirmation, with its analysis committed first* (#185), squash-merged 2026-08-23T22:57:35+09:00 |
| | Held as the constant `PROTOCOL_BASELINE` in `preflight.py`, **not** read from `HEAD` or `origin/main` — a baseline taken from the current branch silently becomes whatever was committed last. The preflight asserts it is an ancestor of `HEAD`. |
| preflight run | **2026-08-23T23:09:51+09:00**, timezone **JST (UTC+09:00)** |
| host | Linux 6.17.0-1021-nvidia, Python 3.14.6 |
| repository | `ngc-shj/claude-code-config`, branch `main` |

## Execution environment

The protocol requires this recorded before the first batch, because round 17
recorded none of it and that is what makes a null unidentifiable. Each row gives
the most specific string obtainable **and its provenance**; where a value cannot
be obtained it says so instead of estimating.

| | value | source |
|---|---|---|
| orchestrator model id | **`claude-opus-5[1m]`** | session environment, "The exact model ID is …" |
| orchestrator model name | Opus 5 (1M context) | same |
| model snapshot / build date | **NOT OBTAINABLE** — no dated snapshot identifier is exposed to the session. Not estimated. | — |
| training cutoff | **May 2026** | session environment, "Assistant knowledge cutoff is May 2026". Month granularity is all that is published; no day is inferred. |
| reviewer / clustering / adjudicator model | **NOT YET OBSERVED.** No round-24 agent has run. Sub-agents inherit the session model unless a call overrides it, and no round-24 call exists to inspect. | — |
| system-prompt fingerprint | **NOT OBTAINABLE** — the system prompt is not readable as a file from the session, so no hash can be taken. Not estimated. | — |
| CLI | Claude Code **2.1.211** | `claude --version` |
| Agent SDK | **0.3.220** | `CLAUDE_AGENT_SDK_VERSION` |
| entrypoint | `claude-vscode` | `CLAUDE_CODE_ENTRYPOINT` |
| reasoning effort | `high` | `CLAUDE_EFFORT` |
| model pinned in settings | none — `settings.json` sets no `model` | `grep '"model"' settings.json` |

**Registered intent, before the run:** every role — review, clustering, merge,
adjudication, tie-break, bridge — runs on the **session model with no per-call
override**. No round-24 call sets a model, and none may. Round 22's working rule
was "sub-agent models are not changed"; this states the same thing as an intent
that can be checked against the agent records afterwards rather than assumed.

**The per-role model identifier is the one thing this preflight cannot supply,
and it is required.** It must be captured from the first batch's own agent
records and appended here before any arm table is read. If any role's observed
identifier differs from the orchestrator's, that is a deviation to declare, not
a detail to absorb.

### Contamination check

Round 17's material is committed in this public repository dated **2026-08-09**;
its reviews ran 2026-08-08. The executing model's stated training cutoff is
**May 2026**, which precedes that. Per the protocol's wording: **ordinary
pretraining exposure to the fixture and to round 17's arm table is not supported
by the stated timeline.** That is what a cutoff date can establish and no more —
it is not proof of absence, and it does not cover a model that has encountered
this repository by another route. Recorded as the evidence, not asserted as a
conclusion.

## Arms

Built by `preflight.py` from `bc0f966:skills/triangulate` plus
`../round-17/arms.diff`, with no agent involved.

1. `git archive bc0f966:skills/triangulate | tar -x` into `cat-W` and `cat-N`.
2. In **each** arm, `common-rules.digest.md` has `skills/triangulate/` rewritten
   to that arm's own directory — the digest, and only the digest, exactly as
   `arms.diff`'s preamble describes.
3. In `cat-N`, `arms.diff` is applied with `git apply -p0`, its `<CAT>` slot
   substituted for `cat-N`. The Finding Floor section leaves `common-rules.md`
   and the digest paragraph that routes to it leaves the digest.

**Hashes are taken over a normalised copy** — each arm's own directory path
replaced by `<CAT>` — because a literal hash would depend on where the arm was
built. Verified: two builds under different directories produce byte-identical
manifests.

| arm | files | normalised tree hash |
|---|---|---|
| `cat-W` | 44 | `2f241a02802bdaf35bd99c94ecfe9aba6a15fd50` |
| `cat-N` | 44 | `641e83e2d88986867adafec6b22a98f6a35da294` |

Per-file hashes for both arms are in `preflight-manifest.tsv`.

### `diff -rq` — the complete result

```
Files <out>/cat-W/common-rules.digest.md and <out>/cat-N/common-rules.digest.md differ
Files <out>/cat-W/common-rules.md and <out>/cat-N/common-rules.md differ
```

**Two files, and no `Only in` line.** 42 of 44 files are byte-identical; the two
that differ are the one variable.

### A preflight finding: one path an arm copy does not capture

`preflight.py` step 3b records something round 17 did not. Two files in the
catalogue name `skills/triangulate/` — the digest, which each arm rewrites to
itself, and **`phases/phase-3-review.md`, which is left alone**. It carries

```
awk '/^### Remedy Floor/,/^### Anti-Deferral/' skills/triangulate/common-rules.md
```

a **repository** path, not an arm path. A reviewer who follows it reads the live
catalogue rather than its own arm's copy.

What it is not: it extracts the **Remedy** Floor, which both arms hold
unchanged, so it cannot carry the arm variable into `N`. What it is: a path by
which the run could read bytes from a catalogue that has moved since `bc0f966`.

Rewriting that path would close it, and would also make a third file differ
between the arms — breaking the very `diff -rq` invariant the protocol registers,
and building arms that are not round 17's. **The construction is left matching
round 17, and the risk is bounded by assertion instead**: the preflight fails if
`skills/triangulate/common-rules.md` at HEAD is not byte-identical to `bc0f966`,
or if any third file starts naming the repository path. Both pass today. If the
catalogue is edited before the round runs, the preflight goes red and this
decision gets taken again with the facts in front of it.

## Pinned material, re-verified

All 18 files the protocol pins hash as the protocol states, and every one is a
row in `preflight-manifest.tsv` that a plain run re-checks. The templates and
the frozen inputs:

| file | sha1 |
|---|---|
| `briefs/review.template.md` | `1eacfac5de5c37d067f566642626b78f44f2c183` |
| `briefs/cluster.template.md` | `66f9c6acd23869299a624d3085fb46c400205a54` |
| `../adjudication-brief.md` | `64d9827be5206e1739a95f8bbdef6576493ab43f` |
| `cluster-inventory.tsv` | `5278058c57e364ae5cbee55854106210290abddf` |
| `bridge-sample.tsv` | `e5026fea2629a2eec253b2afbc4dc2be925761b7` |
| `bridge-input.tsv` | `beaf2e39e21eb89dd046697241467adb42a0df8e` |

All three generated files were re-emitted from `measure.py` and match the
committed copies byte for byte.

### The clustering brief points at 94 claims, not 64

`cluster-inventory.tsv` is emitted by `measure.py --cluster-inventory`: the
**94 frozen claims** — round 16's 64 seed claims plus the 30 round 17 added —
with `cluster_id` and canonical claim text only, sorted, ids unique. It is
committed here as a zero-data artifact and the preflight checks it regenerates
from its two sources.

It exists because the obvious file to hand the clustering agent is
`round-16/seed/inventory.tsv`, and that is **the seed alone**. A clustering
brief that names 64 claims cannot recognise the 30 that round 17 adjudicated, so
those thirty come back as new claims, get re-adjudicated by a second panel, and
the append-only rule that makes `real` mean the same thing across rounds is
broken from the inside. The preflight renders `brief-cluster.md` against this
file with `--n-claims 94`, and `render.py`'s row-count check makes a mismatch
between the file and the number fatal.

## Briefs

Four of the six render now. `adjudicate-new.md` and `adjudicate-tiebreak.md`
cannot: their claim sets do not exist until the round produces new claims and
until an adjudication panel splits three ways. They are rendered, hashed and
recorded at those points.

**`brief-W.md` and `brief-N.md` are identical modulo the catalogue path** —
verified by substituting each arm's directory for `<CAT>` and comparing. The arm
variable lives in the catalogue, where `arms.diff` puts it, and not in the brief.

Rendered hashes below are from this preflight's build directory and are
**path-dependent by construction**: the run's own renders will hash differently
and must be recorded then, beside the template hashes above.

| rendered | sha1 (this preflight build) |
|---|---|
| `brief-W.md` | `0c305475de9ff85a604378553429b81faae78821` |
| `brief-N.md` | `7f442857bbb70a93cffd1428f113bb20cabb5167` |
| `brief-cluster.md` | `0938500dd7e432aaa9d3ae82126c1971743d0ad2` |
| `adjudicate-bridge.md` | `750b7c38d0550dcec466823a3e892654a2360e84` |

## State

| | |
|---|---|
| reachability probe | **RUN — 3/3, gate passed** (see below); its 3 agents enter no metric |
| review agents launched | **0 of 72** |
| measurement rows on disk | **0** — no `findings.tsv`, `clusters.tsv`, `reviews.tsv`, `tiebreak.tsv`, `adjudications/` or `bridge/` |
| preflight verdict | **PASSED**, 0 failures |

The preflight asserts the last row rather than trusting it: it fails if any
round-24 measurement artifact exists.

### Re-verified on merged `main`

The preflight was written on a branch, so it was re-run against the merged
result rather than trusted from the branch it was authored on.

| | |
|---|---|
| preflight merged as | **`88d16da9630e1b035b133141ede02897b671226e`** (#186), 2026-08-23T23:38:18+09:00 |
| worktree at that commit | clean |
| `preflight.py` | **PASSED**, 0 failures — all 20 checks, including the baseline ancestry, the two-file `diff -rq`, 18 pinned hashes and all 109 manifest rows |
| `bats tests/` | **1236 pass, 0 fail** |
| state | unchanged: reachability **NOT RUN**, review agents **0 of 72**, measurement rows **0** |

Two baselines are recorded because they answer different questions. `9f4026c` is
the **protocol** baseline — the design the round is registered against.
`88d16da` is the **validated preflight tree**: the last measurement-affecting
tree whose arms, manifest and briefs were checked. It is not the launch commit.
**The actual launch HEAD is recorded with the reachability result**, and
record-only descendants of `88d16da` — commits that add no measurement-affecting
material — do not alter the arms, the manifest or the briefs, so they do not
move the validated tree.

### Known, not yet closed

The manifest comparison in `preflight.py` tests row **membership** in both
directions, not sequence equality, so a manifest with a duplicated row would
still compare clean. The committed manifest has no duplicates — the row count
is checked and every pinned row is verified against the file it names — so this
is a hardening gap rather than a live hole, and it is recorded here instead of
being fixed in the same commit that records a verification result.

## Reachability gate — RUN, 3/3

The one gate that runs before any arm. Three agents took the **W** catalogue over
F10; their tool-call traces were read and nothing else.

| | |
|---|---|
| launch HEAD | **`6bdcd8dda8535116e6fbd20ebc115ad0059ee845`** |
| validated preflight tree | `88d16da`; the only difference to launch HEAD is this README, which touches no measurement-affecting material |
| launched | 2026-08-23T23:56:35+09:00 (JST) |
| agent window | 2026-08-23T14:56:53Z → 15:04:14Z |
| agents | exactly 3, arm W, no per-call model override |
| preflight at launch | PASSED, 0 failures, worktree clean |

**Result: 3 of 3 executed the Finding Floor extraction** — issued the call *and*
had it return without error. All three also read the digest first, which is the
weaker precondition. The gate's other two branches — 1–2/3 and 0/3, both "stop
and investigate the wiring" — did not fire.

| agent | tool calls | all returned ok | digest read | Finding Floor extraction |
|---|---|---|---|---|
| `a3ed8e17…` | 9 | yes | yes | **yes** |
| `a95a6cd7…` | 12 | yes | yes | **yes** |
| `a7fef430…` | 9 | yes | yes | **yes** |

Counts are of tool calls in the trace, recorded because the protocol asks what
the agents *did*. They are not finding counts.

**Issuing is not executing.** A `Bash` call that names the Finding Floor and then
fails still puts the command in the trace, and the first draft of the analyser
would have counted it. Each `tool_use` is now joined to the `tool_result`
carrying its id, and the outcome is read as one of four states — only the first
is an execution:

| state | meaning |
|---|---|
| `ok` | the result carries `is_error` as the boolean **`false`** |
| `ERROR` | the result carries `is_error` as the boolean `true` |
| `no-flag` | a result exists and says nothing usable about success |
| `no-result` | no result carries this id at all |

`bool(block.get('is_error'))` was the second draft and reads a *missing* flag as
`False`, i.e. as success. That is the one direction this gate must never be
generous in: a transcript shape that omitted the field would have turned every
issued call into an executed one. All three real results carry an explicit
`false`, so the 3/3 is unchanged — but it is now 3/3 for the stated reason.

**The three transcripts are named, not searched for.**
`reachability-manifest.tsv` pins the session, the three agent ids and each
transcript's **git blob sha1** — `sha1("blob <len>\0" + bytes)`, what
`git hash-object` prints, **not** the plain file digest `sha1sum` prints. The
column is named `git_blob_sha1` so nobody has to infer that from a mismatch.
The analyser reads those three files and no others. The
first draft selected "every sub-agent after time T", which cannot survive the
round: once 72 review agents have run in the same session, a timestamp no longer
identifies the probe. Naming them also makes an edited transcript fail on the
hash rather than pass quietly, and makes the gate replayable by anyone holding
the files:

```bash
evals/rule-precision/round-24/reachability.py    # re-derives 3/3 from the pinned three
```

**How "only the traces" is enforced.** The analyser emits `tool_use` blocks only:
assistant `text` and `thinking` blocks — where a review's findings live — and
`tool_result` *content* are dropped before anything is printed; the only thing
ever taken from a result is its `is_error` flag. Printed tool inputs are reduced
to a path or a matched marker. There is no flag to disable that. The brief also
ends "reply with the single word `DONE`", and all three did, so no finding
reached the orchestrator's context by the return path either.

The three review files were written to `<scratchpad>/round-24-run/probe-*.md` and
**were never opened**. They are outside the analyser's reach by construction — it
resolves transcripts from the manifest and never touches a review file — and
nothing from these agents enters any metric.

> **They are also gone.** The host rebooted at **2026-08-24 00:28:06 JST** —
> 24 minutes after the probe finished — and `/tmp` did not survive it, taking the
> whole session scratchpad with it. (An earlier draft of this paragraph said
> "cleared between sessions". That was wrong: the session id never changed. The
> cause was the reboot.) Nothing measured depends on it: the gate was derived
> from the transcripts, which live under `~/.claude/projects/…` — outside `/tmp`,
> which is why they survive — are pinned by hash above, and re-derive 3/3 on
> demand. The reviews themselves entered no metric by design. They are
> recoverable in principle — each agent's `Write` call carries its content in the
> transcript — but **recovering them means reading them**, which is exactly what
> this gate forbids, so it is not done and they are left unread. Recorded because
> a record that quietly loses a named artifact is worse than one that says where
> it went.

### Where the measurement is written, and why not `/tmp`

**Forward operational amendment, 2026-08-24, before any review agent ran.**

The measurement gets its own directory, and that directory is **outside `/tmp`
and outside the repository**:

```
/home/noguchi/.local/state/claude-code-config/round-24-measurement/
```

Arms, rendered briefs and all 72 review outputs are written **there directly
from the first batch** — not staged in `/tmp` and copied afterwards, because a
copy-after-batch scheme leaves a window in which a reboot destroys the batch it
has not yet saved.

The reason is measured rather than hypothetical: the probe's three reviews were
written to `/tmp` and a reboot 24 minutes later removed them. The probe survived
that because its evidence is the transcripts, which live under
`~/.claude/projects/…`; the round would not. Twelve batches spanning several
five-hour windows is many hours of exposure to exactly the event that has
already happened once during this round's preparation.

The directory also isolates the probe: nothing named `probe-*` may exist under
it, and extraction takes **the 72 registered output paths explicitly** — it never
runs `*.md` over a shared tree. `preflight.py --out <dir>` enforces the first
half by walking the tree and failing on any `probe-*` file at any depth;
`measurement-outputs.tsv` is the registered list that enforces the second.

`register-outputs.py` generates that list — 12 indices × 2 arms × 3 parts — and
**refuses to write it if any of the 72 already exists**, so it can only ever be a
reservation. The registry is committed before the first batch.

### Pre-launch verification, against the persistent root

Run after the amendment above and before any review agent:

| check | result |
|---|---|
| `preflight.py --out <persistent root>` | **PASSED**, 0 failures — 21 checks including `no probe output under round-24-measurement` |
| `reachability.py` replay from the pinned three transcripts | **3/3**, gate passes, no agent re-run |
| arms `cat-W` / `cat-N` normalised tree hashes | `2f241a02…` / `641e83e2…` — unchanged from `preflight-manifest.tsv` |
| template hashes | `1eacfac5…`, `66f9c6ac…`, `64d9827b…` — unchanged |
| pinned material | 18 files, all 109 manifest rows match |
| CLI / SDK / entrypoint / effort | 2.1.211 / 0.3.220 / `claude-vscode` / `high` — unchanged from the probe |
| model pinned in `settings.json` | none, as at the probe |
| kernel | `6.17.0-1031-nvidia` — **changed**, declared above |
| 72 output paths | reserved in `measurement-outputs.tsv`, none exists |

Everything that could change what the gate measured is unchanged. What changed
is the kernel and the storage location, both declared.

Rendered `brief-W.md` / `brief-N.md` hash differently from the preflight build
because they name the catalogue directory, which moved with the root — that is
the path-dependence recorded above, not a change of instrument. Their **template**
hashes are identical, and `diff` over the two rendered briefs still returns only
the catalogue-path lines.

Also visible in the traces, and worth recording: no agent read anything under the
repository except the fixture. The brief's prohibition held.

### Deviation to declare: the sub-agent model identifier

The registered intent was that every role runs on the session model with no
per-call override. **No override was passed** — and the observed identifiers
still differ:

| | |
|---|---|
| orchestrator | `claude-opus-5[1m]` |
| all three probe agents | **`claude-opus-5`** |

The `[1m]` suffix is the 1M-context variant, a main-loop setting that sub-agents
do not inherit. The intent held; the identifier is not the orchestrator's, and
this record says so rather than absorbing it.

**What this establishes is the probe-side model, and only that.** `claude-opus-5`
is what these three agents ran on. It is a strong prediction for the review,
clustering and adjudication roles — same harness, same absence of override — and
it is **not** a measurement of them. Each role's identifier is recorded from its
own agents' records when that role runs, and a difference from this one is a
deviation to declare at that point.

The reason to record any of it: round 17 wrote none of it down, which is what
makes its null unidentifiable. Registering the intent in a form that could be
checked is what turned "sub-agents inherit the session model" from an assumption
into an observation that turned out to be half wrong.

### Deviation to declare: the host kernel changed between the gate and the round

The host rebooted at 2026-08-24 00:28:06 JST, between the reachability probe and
the review batches, onto a **different kernel**:

| | |
|---|---|
| kernel at the probe | `6.17.0-1021-nvidia` |
| kernel for the round | `6.17.0-1031-nvidia` |

Declared because this record's whole discipline is that unrecorded execution
differences are what make a null unidentifiable, and "the machine was rebuilt
mid-round" is exactly the kind of thing round 17 would not have noticed.

**It is not a reason to re-run the probe.** The gate measures whether the
Finding Floor's digest wiring reaches a reviewer, and the things that could
change that answer — the catalogue, the arm construction, the brief templates
and their rendered output, the CLI, the SDK, the model identifiers — are
re-verified by hash before the round starts and are unchanged. A kernel version
and a storage location are operational facts to declare, not instrument changes
to re-measure. **If any of the hashed items had moved, the round would stop here
instead** and the question would be re-opened as its own forward amendment.

Re-running three agents now would also create an unregistered *second* gate with
no rule for combining it with the first — a worse record than the one this
paragraph replaces.

## What happens next, in order

1. ~~The preflight commit is reviewed.~~ **Done** — #186, re-verified on merged
   `main`.
2. ~~Reachability gate only, 3 agents, arm W, explicitly approved.~~ **Done —
   3/3.** Recorded above with the launch HEAD, the timestamps, and the
   sub-agent model identifier the round will carry.
3. **The 72 review agents are a separate decision, and it has not been taken.**
   The gate passing licenses nothing by itself: it says the manipulation
   arrives, which is the precondition for the ablation meaning anything, not a
   reason to spend ≈27.8M raw tokens on it.

**Nothing beyond step 2 has been authorised.** The next thing that happens is
someone deciding whether to run the round, with this record in front of them.

## Tie-break: not required

`measure.py`'s own `new_ids()`, `panel()` and `splits()` were run unchanged over
the three committed adjudication sheets. **`splits()` returned empty: no claim
drew three different verdicts**, so the registered tie-break branch does not
fire.

Nothing was created for it, and that is the point of recording it. There is no
`tiebreak.tsv`, not even a header-only one — `measure.py` refuses a tie-break
file when nothing split, so an empty sheet written "for completeness" would stop
the round rather than tidy it. No tie-break brief was rendered, no output
manifest registered, no envelope or composer written, and no fourth adjudicator
launched.

The branch decision is the only thing this step produced. The number of splits
and the ids involved were computed inside the frozen functions and never
printed; no majority verdict, verdict distribution or arm value was computed at
all.


## Bridge panel: delivered, unread

Three fresh Claude sub-agents judged the 24 claims of `bridge-input.tsv` — the
claim-only sibling of the frozen `bridge-sample.tsv`, whose verdicts are what
the bridge exists to compare against. Launched one at a time in registered
order, each on the session model with no per-call override:

| panel | agent | model | calls | errors | write | reply | composed prompt sha1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `a9059ba52a4aa4ac3` | `claude-opus-5` | 3 | 0 | `Write` | `DONE` | `042e89e0…` |
| 2 | `a2d089be8f95a293f` | `claude-opus-5` | 3 | 0 | `Write` | `DONE` | `a0d09b8b…` |
| 3 | `a8f5c4699decc4d73` | `claude-opus-5` | 3 | 0 | `Write` | `DONE` | `ffbbd9ed…` |

`--verify-sent` compared each composed prompt against what the agent's own
transcript shows it received: all three byte-identical. The three prompts differ
only in the output path line. Each transcript's tool inputs were greped for
`bridge-sample`, `adjudications/` and the other two panellists' paths — no hit
in any of the three.

Nine checks then ran over the sheets without displaying them: exactly three
sheets; header `cluster_id / verdict / reason`; id set **and order** identical to
`bridge-input.tsv`; no duplicate, missing or added id; verdict/reason
combinations following the same rule as the new-claim panel; the three
`adjudications/` sheets unchanged against a pre-launch hash snapshot; and no
bridge-shaped output anywhere but `bridge/`. All nine pass.

The sheets are committed unread. No agreement rate, verdict distribution,
majority verdict or arm value has been computed — `measure.py --bridge` has not
been run.
