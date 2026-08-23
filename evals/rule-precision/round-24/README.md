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

**Result: 3 of 3 executed the Finding Floor extraction.** All three also read the
digest first, which is the weaker precondition. The gate's other two branches —
1–2/3 and 0/3, both "stop and investigate the wiring" — did not fire.

| agent | tool calls | digest read | Finding Floor extraction |
|---|---|---|---|
| `a3ed8e17…` | 9 | yes | **yes** |
| `a95a6cd7…` | 12 | yes | **yes** |
| `a7fef430…` | 9 | yes | **yes** |

Counts are of tool calls in the trace, recorded because the protocol asks what
the agents *did*. They are not finding counts.

**How "only the traces" was enforced.** `round-24/reachability.py` parses each
transcript and emits `tool_use` blocks only: assistant `text` blocks — where a
review's findings would be — and `tool_result` blocks are dropped before
anything is printed, and printed tool inputs are reduced to a path or a matched
marker. There is no flag to disable that. The brief also ends "reply with the
single word `DONE`", and all three did, so no finding reached the orchestrator's
context by the return path either. The three review files were written to a
scratchpad path and **have not been opened**. Nothing from these agents enters
any metric.

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
this record says so rather than absorbing it. **The reviewer-side model for this
round is `claude-opus-5`** — which is the fact round 17 never wrote down, and the
reason the intent was registered in a form that could be checked.

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
