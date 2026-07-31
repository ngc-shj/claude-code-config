# Plan: retro-prescreen cursor machinery — replace the mechanism

Branch: `retro/prescreen-cursor-v2`, cut from `origin/main`, carrying only
`hooks/retro-prescreen.sh` and `tests/retro-prescreen.bats` from the abandoned
`retro/2026-07-31-prescreen-cursor-hardening`.

Revision 3. Rounds 1 and 2 returned 43 and 39 findings; dispositions are in
`retro-prescreen-cursor-epoch-review.md`. **This revision is deliberately shorter than
revision 2.** Round 2's findings were overwhelmingly against the plan's own prose — a
wrong line citation, a justification execution falsified, two regexes that denied
conformant code, two unbuildable acceptance cases — which is the accretion pattern this
repository mined and deferred. Narrative that does not carry an obligation has been cut.

## Project context

- **Type**: `config-only` / CLI shell tooling installed into `~/.claude/` by `install.sh`.
- **Test infrastructure**: `unit + integration` via `bats`; 74 cases green for this hook.
  No CI/CD — gates run locally.
- **Verification environment constraints**:
  - `VC1` — **BSD/macOS branches are not executable here** (Linux/GNU). `blocked-deferred`.
    Mitigation is structural: this change *removes* the BSD/GNU-divergent constructs
    (`date -j -f` / `date -d`, `touch -t`) and leaves one divergence (`stat -c %Y` /
    `stat -f %m`) inside a single helper. Anti-Deferral: a macOS runner for a config repo
    with no CI is not justified against a residual this change shrinks.
  - `VC2` — **bash 3.2 is not executable here** (local 5.2). The floor is declared at
    `hooks/check-rule-sync.sh:103`, `hooks/check-input-validation.sh:726`,
    `tests/retro-prescreen.bats:70`. `blocked-deferred`; mitigated by C8, which after two
    rounds of it denying conformant code is now a bats case with per-pattern positive and
    negative examples rather than a hand-reviewed regex list.
  - `VC3` — **sub-second-mtime filesystems**: the suite asserts the precondition
    (`fs_keeps_subsecond`) and skips where absent. `verifiable-local` (ext4 preserves ns).

## Objective

Close the `retro-prescreen.sh` cursor defects **by replacing the mechanism**. Three prior
rounds each closed one path and opened another instance of the same class; the disposition
mandated by `docs/archive/audit/retro-artifacts-lessons-2026-07-31.md` is replacement.

## Requirements

**Functional**

- **F-R1** The local cursor comparison is decided by exactly one adjudicator; no local
  pre-filter narrows the candidate set. The one remote pre-filter is declared, not demoted
  by assertion (C7).
- **F-R2** Every source drains: a subject mined in run N is not re-mined in run N+1. This
  holds for `github` too, which today has no local suppression predicate at all (C7).
- **F-R3** Unknown values degrade to "everything is new", never to "nothing matched".
  Scoped to the two cases the contracts implement — **unreadable mtime** (candidate kept)
  and **unparseable cursor** (epoch 0, announced). The third case is stated separately
  because it does *not* obey the rule: an **unreadable clock** disables the heal and leaves
  the persisted cursor in force, so a poisoned cursor stays suppressive until a run with a
  readable clock. Declared residual, not a contradiction hidden in a universal.
  This is a deliberately **fail-open policy**; contracts implementing it must not be
  labelled fail-closed (C1/C2/C3).
- **F-R4** A persisted `high_water` ahead of the present is healed on the run that observes
  it, on **every path in `hooks/retro-prescreen.sh` that reads a cursor**. Derived, not
  listed: `rg -n 'high_water|_state_high_water' hooks/retro-prescreen.sh`. Three exits
  (`:453`, `:458`, `:598`) return before any cursor read; the read-in and heal move above
  them, so the derived set and the implemented set are equal.
  Healing moves the cursor **backward only**. Scope is `high_water` in this hook;
  `retro-state.sh`'s `last_run` / `snoozed_until` are SC5, `last_prompted` is out of the
  class (equality comparison, fails open toward more prompting).
- **F-R5** Exit 0 on every degraded path; exit 2 only on unknown mode / missing config. A
  JSON document is emitted on every path reaching a `cmd_*`, including paths where the
  shell would otherwise abort mid-loop.
- **F-R6** **Diagnostics carry no absolute path and no transcript identity.** Per stream and
  per source; an obligation stated per-warning is what let two rounds each find one more
  leaking site.
  - `stdout`, `artifacts`: `candidates[].path` is absolute **by design** — the orchestrator
    hands it to a sub-agent's `Read`. Unchanged.
  - `stderr`, `artifacts`: may name a **repo-relative** path; never absolute. Enumerated in
    C5 over the derived set, not over a list.
  - both streams, `transcripts`: **no path and no filename at all.** Enforced at the single
    producer (`:726`), not at either projection — `:750` (JSON) and `:754` (human) both read
    the same `counts` keys.

**Non-functional**

- **N-R1** bash 3.2 / stock-macOS: no `mapfile`, `readarray`, associative arrays, negative
  array subscripts, and **no `"${a[@]}"` on a possibly-empty array** — use
  `${a[@]+"${a[@]}"}` (`hooks/retro-state.sh:211`). The obligation is over **every**
  `"${name[@]}"` in the file, derived by grep, not over a named list: revision 2 named
  `:762` and missed `:646`. NUL-delimited `find` output is consumed with
  `while IFS= read -r -d '' f; do … done < <(find … -print0)` (bash 2.04+).
- **N-R2** Full enumeration is bounded on **both** axes it changed:
  - *time*: measured 1.39 s (one `stat`/file) and 2.81 s (two) over 1167 `*.jsonl`. C1
    reads the mtime once per file, so 1.39 s is the figure to regress against.
  - *output*: the per-file suppression diagnostic must not scale with the corpus. Measured
    unbounded: 1167 lines / ~127 KB per steady-state run. One aggregate line per source per
    run (C5/C6).

## Technical approach

### The replacement

**Cursor arithmetic moves from ISO-string space to whole-second integer epoch space, and
the `find -newer` pre-filter is deleted.** Three colliding parts go with it:

| Part | Failure it kept producing |
|---|---|
| `find -newer <ref>` | narrows before the authority sees it; every bug in building `<ref>` decides the outcome |
| a materialized reference file (`mktemp` + `touch -t` + `date -j`/`date -d`) | TZ shift, unstampable reference, temp-dir framing, BSD/GNU divergence |
| lexicographic ISO comparison | an empty string sorts below every cursor, so any upstream failure spells itself "older than everything" |

Deleting the pre-filter deletes the reference file and with it the whole
`date`/`touch`/`mktemp`/`mapfile` surface. Integers delete the third: an unknown epoch is
the empty string, not comparable at all, so it *must* be branched on. jq becomes the single
ISO↔epoch codec at the two boundaries.

### Heal direction — backward, never forward

Round 1 reproduced that clamping a future cursor to `now` suppresses every existing file and
loses the backlog permanently. `pipeline.md:134-137` already decided this question for the
same failure: *"The minimum is the only value that is safe in the recovery direction — it
re-mines already-seen artifacts …, rather than dropping unseen ones, which loses the lesson."*

**A cursor ahead of the present resets to epoch 0.** Two consequences are load-bearing:

1. The healed value is **≤ the persisted value, always**, so emitting it can never record
   progress and it is safe on *every* branch — including deferred. The emitted cursor is a
   function of the heal, never of the branch.
2. A corrupted cursor **widens** the GitHub query instead of narrowing it (C7).

**The heal's trigger is `persisted > now`, whose ordinary producers are clock movements**, not
corruption: an NTP step-back, an RTC-local-time dual boot, a VM snapshot restore, a container
started before time sync. A reset therefore makes the whole corpus a candidate, and
`cmd_artifacts` decides `artifacts_llm_ok` once (`:298-310`) then pipes each candidate's raw
bytes to `llm_request` (`:431-433`) — with `allow_remote_llm`, off-machine, uncapped
(`github` has `--limit 200`; `artifacts` has nothing). So:

**When a heal fires for a source, that run forces `artifacts_llm_ok=0` / `stage2_allowed=0`.**
Recovery is unaffected — the mining sub-agent `Read`s locally and file-list-only is already
the documented degraded mode (`:309`) — while the off-machine set does not widen with the
candidate set. The heal itself is *not* bounded: bounding it would un-mitigate C7's
incompleteness mode 3.

## Contracts

### C1 — `_file_mtime_epoch <path>` → epoch or empty

```
_file_mtime_epoch(path) -> stdout: /^[0-9]+$/ | ""   ; always returns 0
```

- GNU and BSD arms are separate commands with **distinct exit statuses**: `$(a || b)`
  concatenates both stdouts when `a` prints and fails.
- Output validated all-digit and non-empty before return.
- **Defined in `hooks/llm-utils.sh`**, because that file has three consumers that never load
  this hook (`pre-review.sh:11`, `commit-msg-check.sh:9`, `llm-commands.sh:13`) and would
  otherwise lose their 300 s host-discovery cache silently. `cmd_transcripts`' `source`
  (currently `:738`) is **hoisted above the gather loop**, since its adopter sites are at
  `:619`/`:652`; and because that `source` is `2>/dev/null`-suppressed, it is followed by
  `command -v _file_mtime_epoch >/dev/null || { … exit 2; }` — an unsourced helper must not
  vanish silently.
- **Member set, derived from the primitive** (`grep -rn 'stat -c %Y' hooks/`), four
  production sites: `retro-prescreen.sh:345` (artifacts cursor), `:619` (5-minute
  freshness), `:652` (transcripts cursor), `llm-utils.sh:94` (300 s TTL — the exact
  single-substitution shape this contract forbids, plus the `echo 0` audit defect (3) names).
  `:619` and `:652` read the same value for the same file: the mtime is read **once** in the
  gather loop and carried into Stage 1, so the shipped adopter count is **three** and N-R2's
  one-stat figure is the correct baseline.
  Two test-side twins exist (`bats:456`, `:1472`) and are **kept deliberately** as an
  independent oracle — that is what makes TC0's literal assertions meaningful (C11).

**Control class**: the value producer is a `fail-closed verification gate` (it cannot return
an unvalidated number; every error path yields empty). The **cursor-suppression policy it
feeds is deliberately fail-open** per F-R3 — stated so a reader does not assume denial.

### C2 — `_iso_to_epoch` / `_epoch_to_iso`

```
_iso_to_epoch(iso)   -> stdout: /^[0-9]+$/ | ""   ; always returns 0
_epoch_to_iso(epoch) -> stdout: ISO-8601 Z | ""   ; always returns 0
```

- `jq -nr … fromdate` / `todate` and **nothing else**. No `date -j`, no `date -d`.
- **The operand is passed with `--arg` (string) or `--argjson` (integer, after numeric
  validation); the jq program is a fixed single-quoted literal and never contains an
  interpolated shell value.** Round 1 demonstrated the injectable spelling satisfies every
  other criterion here while letting the operand pick its own epoch and read the process
  environment.
- jq's stderr suppressed; the **output** validated.
- Date-only expansion (`YYYY-MM-DD` → `T00:00:00Z`) before handing to jq: `_norm_iso` runs
  only in `cmd_seed`, so a date-only value is a live persisted spelling (executed).
- `_epoch_to_iso` validates its output against **`_is_iso`'s own regex**; `todate` emits
  5- and 7-digit years that `_validate_hw` rejects for the whole object.
- **`_iso_to_epoch` accepts a strict subset of `_is_iso`'s language, and the plan says so
  rather than claiming equality** — revision 2's claim was false in four executed directions.
  `_is_iso` is a syntactic regex; `fromdate` is `strptime`-backed and semantic:

  | value | `_is_iso` | `fromdate` | `_iso_to_epoch` |
  |---|---|---|---|
  | `1969-12-31T00:00:00Z` | accepts | `-86400` | epoch 0, **no warning** (a valid pre-1970 cursor is not corrupt) |
  | `0000-01-01T00:00:00Z` | accepts | `-62167219200` | epoch 0, no warning |
  | `2026-13-45T99:99:99Z` | accepts | parse error | empty → epoch 0 **+ warning** |
  | `2026-02-30T00:00:00Z` | accepts | `1772409600` (→ Mar 2) | accepted; **residual**: normalised, not rejected |

  Tightening `_is_iso` to match is the `retro-state.sh` chokepoint SC1 declines to open.

**Control class**: as C1 — fail-closed validator, fail-open policy.

**Acceptance** (values re-derived by running jq, not recalled):
```
jq -nr '"2026-07-14T16:44:06Z" | fromdate'  -> 1784047446
jq -nr '1784047446 | todate'                -> 2026-07-14T16:44:06Z
jq -nr '"2026-07-31T00:00:00Z" | fromdate'  -> 1785456000
jq -nr '253402300800 | todate'              -> 10000-01-01T00:00:00Z
```
- `_iso_to_epoch 2026-07-14T16:44:06Z` → `1784047446`; `_epoch_to_iso 1784047446` →
  `2026-07-14T16:44:06Z` — asserted against **literals in both directions**, never as
  `f(g(x)) == x`, which two mirrored-wrong functions satisfy
- `_iso_to_epoch 2026-07-31` → `1785456000`
- `_iso_to_epoch 1969-12-31` → `0`, **no** warning
- `_iso_to_epoch 2026-13-45` → `0` **with** warning
- `_iso_to_epoch not-a-date` → `0` with warning, no jq diagnostic on stderr
- `_iso_to_epoch 'x" | 4102444800 # '` → `0` with warning — the only case separating the
  safe and injectable spellings
- `_epoch_to_iso 253402300800` → empty

### C3 — `_now_epoch`

```
_now_epoch() -> stdout: /^[0-9]+$/ | ""   ; always returns 0
```

- `RETRO_PRESCREEN_NOW` when set, else `date -u +%s`; numeric-validated; empty means "no
  heal available", never epoch 0.
- **When `RETRO_PRESCREEN_NOW` is set, that is announced on stderr on every run.** It is a
  production seam that can disable a control, and the numeric-but-absurd case was otherwise
  silent (executed: a year-2446 cursor persisted with no diagnostic at all). An epoch integer
  carries no identity, so the value is safe to print. R50 clause (ii) applied to this plan's
  own seam. RS5's alternative (bounding the seam) was considered and not adopted: under the
  inverted heal a low value produces the same full re-mine the old clamp produced from the
  same input, so bounding buys nothing the announcement does not.
- Named in the file header alongside `retro-state.sh`'s `RETRO_NOW`.

**Control class**: fail-closed validator; the empty case is `detection or audit only` — it
disables the heal, announced at every call site.

**Acceptance**: seam unset → **bracketed**, not toleranced:
`before=$(date -u +%s); v=$(_now_epoch); after=$(date -u +%s); [ "$v" -ge "$before" ] &&
[ "$v" -le "$after" ]`. Seam `1784047446` → exactly that, plus the notice. Seam
`not-a-number` → empty, plus the heal-disabled notice.

### C4 — `_heal_cursor <value> <now> <source> <label>` → epoch

Renamed from `_clamp_epoch`: it is not a clamp, and calling it one is what made the forbidden
direction look reasonable.

- **Integer comparison (`-gt`), never string.** Executed: `[[ "999999999" > "1784047446" ]]`
  is **true**, `[ 999999999 -gt 1784047446 ]` is **false** — a `>` implementation heals away
  any pre-2001 cursor. Every existing fixture uses ten-digit epochs where the two agree.
- `value > now` → returns **0**, announced. Empty `now` → returns `value` unchanged, and the
  caller additionally refuses to advance the running maximum.
- Applied **only where a cursor is read in** — one adjudicator (R48).
- **Stderr wording states what the operation does**: `cursor <v> is past the present — reset
  to 1970-01-01T00:00:00Z; this source will re-mine once`. The surviving "clamped to `<now>`"
  wording would give an operator the wrong recovery model, and `clamp` joins C8's list.

**Control class**: fail-closed gate on the poisoned-cursor predicate; `detection or audit
only` when `now` is empty, announced.

**Acceptance**: `(4102444800, 1784047446)` → `0` + stderr; `(1784047446, 1784047446)` →
unchanged, **no** stderr; `(1784047447, 1784047446)` → `0` + stderr;
`(999999999, 1784047446)` → `999999999`, **no** stderr; `(4102444800, "")` → unchanged.

### C5 — `cmd_artifacts`

Emits `{source, candidates:[{path,summary}], high_water:{<repo>:<iso>}, deferred:false}`.

- `find "$glob_dir" -maxdepth 1 -name "$glob_pat" -print0` — no `-newer`, no reference file.
- **`hw_map` is seeded from the configured `repos` array, before the loop.** Stated over the
  loop and the config array rather than over a line: revision 2 seeded "after read-in, before
  any `continue`", and two `continue`s (`:317`, `:320`) *precede* the read-in at `:323`, so a
  repo whose **root** was momentarily absent still had its key deleted by
  `retro-state.sh:346`'s whole-object replacement — reproduced end-to-end by two reviewers,
  with exit 0 and no stderr. The loop only **raises** values. Empty `repos` emits
  `high_water: null`, never `{}` (an empty object passes `_validate_hw` and wipes every key).
- The persisted cursor is `_heal_cursor`'d on read-in.
- Suppression predicate: `[ "$mtime_epoch" -gt "$cursor_epoch" ]`.
- Unknown mtime → candidate kept, `repo_max` untouched, warn.
- Future mtime (`> now_epoch`) → candidate kept, `repo_max` untouched, warn.
- Clock unavailable → `repo_max` does not advance past the persisted cursor at all, heal
  disabled, announced.
- Emission: `repo_max` → `_epoch_to_iso`; on empty, re-emit the **healed** value (not the
  persisted one — the persisted value is the one that may be poisoned).
- **A heal on this source forces `artifacts_llm_ok=0` for the run** (see Heal direction).
- **The per-file suppression diagnostic is replaced by one aggregate line per repo per run**
  (`N of M files at or below the cursor — suppressed`). Per-file it scales with the corpus:
  measured 1167 lines / ~127 KB per steady run, burying every single-line diagnostic on the
  same stream. `tests/retro-prescreen.bats:428` asserts the effect, not the string.
- **Every stderr diagnostic that can name a path routes through `_repo_relative`**, derived
  rather than listed:

  | Diagnostic | Site | Path spelling it receives |
  |---|---|---|
  | `cannot read mtime of …` | `:386` | physical (`resolved`) |
  | `… has a future mtime …` | `:380` | physical (`resolved`) |
  | `rejecting filename with control characters in …` | `:63` | **lexical** (`$dir`) |
  | *(new)* `skipping <repo>: root/archive dir absent` | `:320`/`:330` | configured value |

  `_repo_relative` strips the repo's **physical** root and falls back to the basename if a
  leading `/` survives, so the privacy invariant fails closed. At `:63` the physical root is
  not yet computed — `resolved_root` is assigned at `:67`, *after* the control-character
  branch — so `resolved_root=$(cd -P -- "$root" …)` is **hoisted above** that branch (it is
  already a hard `return 1` on failure, so no fail direction changes). Without the hoist the
  strip is a no-op under a symlinked root and the message degrades to the literal `review`
  for every repo: fails closed, useless for recovery.

**Consumer-flow walkthrough**
- *pipeline Step 1/9* reads `{candidates[].path, high_water, deferred}`; passes each `path`
  to a mining sub-agent and writes `high_water` to `mark-run --high-water-file`.
- *`retro-state.sh` `_validate_hw` (`:154`)* requires an object, every key present in
  `.sources.artifacts.repos`, every value passing `_is_iso`. `_epoch_to_iso` validates against
  that same regex, so the accepted sets are equal by construction. One rejected value discards
  the whole object — which is why C2 bounds the range and why this contract re-emits rather
  than dropping a key.
- *the mining sub-agent* reads `candidates[].path` with `Read`; it has Read/Grep/Glob only,
  no Bash, and no repo root (C9).

### C6 — `cmd_transcripts`

Emits, Stage-2-allowed: `{source, candidates:[<lesson>], high_water:<iso>, deferred:false}`;
deferred: `{source, candidates:[{index,event_count}], high_water:<iso>, deferred:true}`.

- `find "$root" -name '*.jsonl' -print0`, no `-newer`.
- **The 5-minute freshness rule reads `_now_epoch`** — one clock for the function, not two
  (R48) — and validates **both** operands. Executed on bash 5.2.21: under `set -u`,
  `n=100; f=not-a-number; echo $(( n - f ))` aborts with `not: unbound variable`, status 127;
  the status is version-dependent and not claimed for bash 3.2, but the abort — and therefore
  **no JSON at all**, breaking F-R5 — is. Symmetrically, an empty `now_epoch` makes
  `$(( 0 - f ))` negative and excludes every transcript as "too fresh".
  Routing it through `_now_epoch` gives `RETRO_PRESCREEN_NOW` a second control it can affect,
  so C3's announcement covers both; a seam value merely *older than the corpus* excludes every
  transcript, which is why the announcement is unconditional rather than error-only.
- Unknown either operand → the file is **kept**.
- **Every exit path emits the healed cursor**, derived from `rg -n 'high_water' ` over the
  function rather than enumerated by hand: normal, deferred, empty-file-set, **and the
  root-absent `_json_empty` return at `:598`**, which revision 2's three-path list omitted.
  Safe because the healed value is ≤ the persisted one.
  - **The deferred emitter emits `cursor`, never `max_hw`.** Revision 2 justified this with
    "no candidate advanced the maximum, because none was processed", which execution
    falsifies: Stage 1 (`:646-734`) advances `max_hw` at `:664-665` *before* the Stage-2 gate
    at `:740` — captured at `cursor=1970-01-01T00:00:00Z max_hw=2019-12-31T15:00:00Z`. The
    conclusion held; the reason licensed the opposite edit, and `max_hw` is the variable in
    scope and the one the normal branch emits.
- **`counts` is keyed by a per-run ordinal assigned at `:726`.** The identity enters there —
  `:750` (JSON) and `:754` (human) are both projections of the same keys, and revision 2
  changed only `:750`, leaving the session UUID on human stdout. Fixing the producer fixes
  both streams. No basename, path or session identifier enters `counts` or either stream.
  Grep evidence: `event_count` has exactly two code hits (`:750`, `bats:1306` asserting counts
  only), so the key has no consumer; the only reader is the human run report, which needs
  cardinality and counts and gets both from an ordinal.
- **Both** unguarded array expansions are fixed: `:646` `"${files[@]}"` and `:762`
  `"${excerpts[@]}"` → `${a[@]+"${a[@]}"}`. Full enumeration makes the empty case the *steady
  state* — today a nothing-new run exits at the empty-file-set return and never reaches
  `:762`; afterwards every transcript is enumerated, all suppressed, and control reaches it on
  the most common path on a healthy system. Revision 2 named `:762` and missed `:646`, which
  is why N-R1 is now stated over the derived set.
- `basename` per file → `${f##*/}`; the mtime is read once per file (C1) and carried into
  Stage 1.
- Clock unavailable → `max_hw` does not advance past the persisted cursor.
- **A heal on this source forces `stage2_allowed=0` for the run.**
- Aggregate suppression diagnostic as C5.

**Consumer-flow walkthrough**
- *pipeline Step 1/9* writes `high_water` (a bare JSON **string** here) to
  `mark-run --high-water-file`, on the deferred path too after C12.
- *`_validate_hw` (transcripts arm)* requires `jq -r .` to pass `_is_iso`; satisfied by
  `_epoch_to_iso`'s validated output.
- *pipeline Step 1/4* reads `deferred` and `candidates[]`. On the deferred path
  `candidates[]` is `[{index, event_count}]`; no machine consumer reads either key.

### C7 — `cmd_github`

Emits `{source, candidates:[{repo,number,title,comment_bodies}],
high_water:{<owner/repo>:<iso>}, deferred:false}`.

- **A local suppression predicate is added — there is none today.** Derived from code and
  reproduced: every PR the API returns becomes a candidate unconditionally, so a stub PR six
  years older than the cursor is emitted as a candidate. After `_iso_to_epoch "$updated_at"`,
  skip the PR when `updated_epoch -le cursor_epoch`; an unparseable value keeps the PR,
  does not advance `repo_max`, and warns.
  Without it, `LAG_MARGIN` below would make F-R2 **permanently** unmet for github: the query
  re-requests the trailing 24 h every run and nothing suppresses the result. The mitigation
  would have created the violation.
- Persisted cursor `_heal_cursor`'d on read-in; `hw_map` seeded from `repos` before the loop
  (C5's rule, same twin).
- `repo_max` does not advance past `now_epoch`, and does not advance at all when `now_epoch`
  is empty. Converted with `_epoch_to_iso` **before emission** — a bare epoch fails
  `_validate_hw` and the source never advances again (`bats:1113`, `:1120` pin the ISO string).
- Query: `gh pr list --search "updated:>=<bound> sort:updated-asc"`, bound
  `max(0, healed_cursor - LAG_MARGIN)` with `LAG_MARGIN=86400` covering GitHub's index lag.
  If `_epoch_to_iso` returns empty the bound is `1970-01-01T00:00:00Z`; the query is never
  issued with an empty qualifier.

**Control class**: the query is an **accepted, cost-justified pre-filter that DOES decide
membership** — R47 sub-clause (a): GitHub's search index cannot be consulted at decision time,
so the control is declared under R49 rather than claimed as a boundary. Incompleteness modes:
(1) `updated:>=` is date-granular; (2) the index lags — narrowed by `LAG_MARGIN`, residual
declared (a PR whose lag exceeds it is skipped permanently); (3) **any defect in the cursor
used to build the bound** — closed by the heal resetting to 0, so a corrupted cursor widens
the query. With the local predicate added, the query becomes a genuine narrowing over an
authoritative local decision, which satisfies sub-clause (c) for the first time.

**Why the qualifier is kept.** Dropping it was the other candidate remedy. Rejected on
executed evidence: `gh pr list` has no `--sort` flag, so ascending order comes from
`sort:updated-asc` *inside* the search string. Without it a repository with more than
`--limit` merged PRs since the cursor gets a permanent middle gap — an unbounded invisible
loss traded for a bounded visible one the `--limit 200` warning already covers.

**Consumer-flow walkthrough**
- *pipeline Step 1/9* writes `high_water` verbatim to `mark-run --high-water-file`.
- *`_validate_hw` (github arm, `:161-184`)* requires an object with
  `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` keys and `_is_iso` values.
- *the mining sub-agent* reads `candidates[].comment_bodies` and `.title`; never `high_water`.

### C8 — Deletions, and a gate that cannot deny conformant code

Removed: `_mtime_ref_file`, `_find_newer_args`, `_now_iso`, `_clamp_iso`, both `mapfile -t
_nf` call sites.

**The mechanism is replaced, not the patterns.** Hand-written regexes reviewed by eye
produced this class three times in two rounds: round 1's `date -[ud][[:space:]]` matched the
`date -u +%s` C3 requires; round 2's array pattern matched the guarded idiom C6 *mandates*,
and its `jq [^']*"` matched every correct `jq --arg NAME "$value" '…'` in the hook. Every
pattern now carries **both** examples in the table, and TC12 asserts both for **every** row —
"is this regex right?" becomes a test assertion instead of a review question.

| Pattern | must MATCH | must NOT match | Reason |
|---|---|---|---|
| `-newer` | `find "$d" -newer "$r"` | `find "$d" -maxdepth 1` | pre-filter that decided (rounds 1-3) |
| `_mtime_ref_file` | `hw_ref=$(_mtime_ref_file "$c")` | `_file_mtime_epoch "$f"` | deleted with the pre-filter |
| `_find_newer_args` | `_find_newer_args "$r"` | `_repo_relative "$p"` | deleted with the pre-filter |
| `\bmapfile\b\|\breadarray\b` | `mapfile -t a < <(f)` | `map_file_name=x` | bash 4.0+ (N-R1) |
| `(^\|[^+])"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"` | `for f in "${files[@]}"` | `for f in ${files[@]+"${files[@]}"}` | unguarded array, bash 3.2 + `set -u` |
| `touch -t` | `touch -t "$s" "$r"` | `touch "$f"` | local-zone stamp parsing |
| `date -j` | `date -j -f %s "$e"` | `date -u +%s` | BSD arm of the removed codec |
| `date[^\|;&]*-d[[:space:]]` | `date -u -d "$iso" +%s` | `date -u +%s` | GNU arm of the removed codec |
| `clamp` | `# clamped to now` | `_heal_cursor` | vocabulary for an operation that now resets |

The `jq` program-argument pattern is **dropped**: "on a program argument" is prose a grep
cannot express, and C2's acceptance case
(`_iso_to_epoch 'x" | 4102444800 # '` → `0`) already separates the safe and injectable
spellings — it is the only check that actually can.

**The gate is TC12, a bats case**, not a hand-run grep — round 2 established it had zero
callers in `bats tests/` while VC2 makes it the entire bash-3.2 mitigation. It asserts, in
order: (1) **positive subject evidence** — `$SCRIPT` exists, is non-empty, and a control token
known to be present (`cmd_artifacts`) matches, so a renamed hook or typo'd path denies rather
than passing green over an empty set; (2) each pattern's must-MATCH example matches and its
must-NOT-match example does not, **driven from the shipped table** rather than re-spelled;
(3) each pattern matches zero times in `$SCRIPT`, read as grep's status being exactly 1.

**Control class**: `fail-closed verification gate` — an unexaminable subject denies at step 1.
**Not** an enforceable boundary: a contributor can spell around it, and its subject is the
hook only, so stale prose in the test file is out of reach (C11 TC15).

### C9 — `_resolve_contained`'s residual is a residual

The current comment ends *"every consumer of the emitted path must re-establish containment at
its own moment of use"*. The consumer has Read/Grep/Glob only, no Bash, and no repo root; it
**cannot**. The comment states what the function does guarantee ("no link planted before the
scan escapes the root") and declares the rest as an open residual, naming its **window**
(check-to-use, any principal that can write in the repo) **and its sink**:

1. `_summarize_artifact` (`:431-433`) opens the resolved path with `< "$file"` and pipes raw
   bytes to `llm_request`; with `allow_remote_llm` that content leaves the machine. The egress
   gate decides *whether* raw text leaves; this check decides *whose*. Only their composition
   is a control.
2. The mining sub-agent `Read`s the swapped target and its content reaches a pull request.

Prose-only. No Bash/repo-root grant is added to `skills/retrospect/sources/artifacts.md`.

### C10 — Header and docstrings

- File header gains `RETRO_PRESCREEN_NOW`.
- `_now_epoch`'s docstring states its reason **once**.
- No docstring describes a function or a clamp that no longer exists.

**Acceptance** — the greps test the stated invariants, each read by its **own** status
(revision 2's version asserted two arbitrary words and read one through a pipe):
```
for t in _mtime_ref_file _find_newer_args _now_iso _clamp_iso -newer clamp; do
  ! grep -q -- "$t" hooks/retro-prescreen.sh || exit 1
done
grep -n 'RETRO_PRESCREEN_NOW' hooks/retro-prescreen.sh   # first hit's line number < 40
```
Folded into TC12 as assertions on the same subject, so C10 has a gate rather than a read-through.

### C11 — Test changes

Each row names its **mutation**, the assertion it must red, and the expected delta. RT7 shape
(g): applied singly, non-zero delta, red attributable to one named assertion, N arms ⇒ N
mutations. Mutations run on a scratch copy outside the repo; `git status --porcelain` verified
clean after each.

| ID | Change | Mutation → expected red | Closes |
|---|---|---|---|
| TC0 | `helpers` unit group via `run bash -c 'source "$SCRIPT" scrub </dev/null; …'` (constructibility executed: rc 0). Covers C1's four rows, C2's eight, C3's three, C4's five | one per row; C1's split-exit-status row needs a `stat` stub dispatching on `$1` | R1-T2 |
| TC1 | Delete `artifacts: an unstampable mtime reference scans without the pre-filter` | — (removal) | reference file gone |
| TC2a/b | Artifacts two-file max: **two fixtures with identical filenames**, later mtime on `a-*` in one and `b-*` in the other. Axis is *which filename carries the later mtime* — executed: `find`'s ext4 order is a function of the filename and invariant under creation sequence, so a creation-order fixture runs the same traversal twice | `repo_max` → `cursor_epoch`. Executed delta: ordering A none, ordering B `1784047560 → 1784047500`. *Which* reds is platform-dependent, so both are required | T-05, R2-T6 |
| TC3a/b | The transcripts twin, same axis, both files past 300 s **and** past the cursor | `max_hw` → `cursor` | T-02, R2-T5 |
| TC4 | `transcripts: a non-numeric file mtime keeps the file` | drop **only** the file-epoch check | T-03 |
| TC5 | `transcripts: a non-numeric clock does not exclude every session` | drop **only** the `now_epoch` check — split because removing the whole validation reds both | F-06 |
| TC6a | Deferred-branch heal: curl-fail mock, persisted **`2026-07-14T16:44:06Z`** (non-default, so the three candidate emitters are mutually distinct), ≥1 transcript aged 600 s. Assert `.deferred == true` and `.high_water == "2026-07-14T16:44:06Z"` | (i) emitter → `null`; (ii) emitter → `$max_hw` (reds with the file's mtime); (iii) emitter → constant epoch 0 (reds with `1970-…`) | R2-T2, R2-T7 |
| TC6b | Empty-file-set branch, seam pinned; exact healed value | early-return emitter → `null` | R1-T3 |
| TC6c | Normal branch, loopback mock | read-in heal removed | T-01, F-03 |
| TC6d | Root-absent branch (`:598`) emits the healed cursor | `_json_empty` left in place | R2-S7 |
| TC6e/f/g | RT10 allow half **per emitter** (deferred / empty / normal), each with a sane cursor and transcripts below it; assert the emitted value equals the persisted one | heal applied unconditionally | R2-T8 |
| TC6h | `mark-run` round-trip: feed TC6a's value back and assert rc 0 **and** `show --json` stores it | emit a bare epoch instead of ISO | R2-T14, R2-F10 |
| TC7a | `github: a persisted future cursor is healed` | github read-in heal removed | S-06 |
| TC7b | **`github: a PR at or below the cursor is not a candidate`** — the predicate that does not exist today | remove the suppression predicate | R2-F4 |
| TC7c | `github: an unparseable updatedAt does not advance the cursor` | remove the `_iso_to_epoch` guard | R1-T8 |
| TC7d | `github: repo_max does not advance past now` | remove the `now_epoch` bound | R1-T8 |
| TC7e | Search bound built from the healed cursor — `setup_gh_mock` appends `"$@"` to a log. Assert `grep -qF -- 'updated:>=1970-01-01T00:00:00Z sort:updated-asc'` (exact, not a range) | build the bound from the unhealed cursor | R1-T8, R2-T12 |
| TC7f | RT10 allow half: sane cursor → bound is exactly `cursor - LAG_MARGIN` | never subtract | R2-T12 |
| TC8a | Artifacts repo-relative form on a **plain** root: diagnostic **present**, physical root absent, message carries the repo-relative path | strip removed → absolute path appears | S-03, R1-T11 |
| TC8b | `_resolve_contained:63` under a **symlinked** root: diagnostic present, `$repo` and `$HOME` absent, message carries the repo-relative **directory** (not the degenerate `review`) | `resolved_root` hoist removed | S2, R2-F14 |
| TC8c | RT10 allow half for `:63` on a plain root | as TC8b | R2-S6 |
| TC9a | Read-in heal boundary: cursor `== RETRO_PRESCREEN_NOW`, files **below** now → no heal, emitted cursor equals persisted | `-gt` → `-ge` | R1-T12 |
| TC9b | cursor `== now - 1`, candidate at exactly `now` → cursor advances to `now`, no heal message. (Executed: at `cursor == now` no candidate can both clear the cursor and escape the future-mtime bound, so revision 2's "advances normally" was unbuildable) | `-gt` → `-ge` | R2-T6, R2-F11 |
| TC9c | cursor `== now + 1` → heal | read-in heal removed | R1-T12 |
| TC10 | Integer-vs-string: cursor `iso_at 999999999`, seam `1784047446`, candidate **below** the cursor. Executed: with the candidate *between* them both implementations emit a byte-identical document; below the cursor the delta lands on `.candidates` and `.high_water` | `-gt` → `[[ > ]]` | T-07, R2-T5 |
| TC11 | Date-only persisted cursor end-to-end; plus `1969-12-31` → epoch 0 **without** the corrupt warning | remove the date-only expansion / add the warning | F14, R2-S5 |
| TC12 | C8's gate (positive subject evidence + per-pattern must-match/must-not-match + zero matches) and C10's greps | per pattern: swap in the must-NOT-match example and assert the row still passes; swap in the must-MATCH example and assert it denies | R1-T13, R2-T10 |
| TC13 | **Cursor survives a repo whose root is absent**: two repos, one root moved away → `.high_water | keys` contains both, `[repoB]` equals the persisted value, stderr names the skipped repo (repo-relative) | move the `hw_map` seed below `:320` | R2-F1/S2 |
| TC14 | Same for a repo whose **archive dir** is absent; and for empty `repos` → `high_water == null`, not `{}` | seed below `:330`; emit `{}` | R2-F1/S2 |
| TC15 | The `cmd_github` twin of TC13 | seed below the github `continue` | R2-S2 |
| TC16 | **Transcripts identity**: deferred **and** normal, both streams — assert neither `$DOC` nor `$output` contains the fixture basename, and `jq -e '.candidates \| all(has("index") and (has("file")\|not))'`, and the index does not match `.*\.jsonl` | restore `{file: .key}` at `:750`; restore the basename key at `:726` (two arms, two mutations) | R2-F5/S3 |
| TC17 | **A heal disables raw egress for the run**: poisoned cursor + reachable consenting LLM → `.candidates[].summary == null` | remove the `artifacts_llm_ok=0` on heal | R2-S1 |
| TC18 | Aggregate suppression diagnostic: N files below the cursor → exactly one suppression line on stderr | restore the per-file diagnostic (delta: N lines) | R2-F9 |
| TC19 | `setup()` unsets `RETRO_PRESCREEN_NOW`; `TMPDIR` comment cites `llm-utils.sh:51` (the surviving consumer after C8 deletes the `mktemp` its comment names) | *no red-proof — hygiene* | T-07, R1-T15 |
| TC20 | Drop the trailing `chmod 644` (executed: `rm -rf` reclaims a mode-000 file in a writable dir; the restore sits after the assertions and is skipped on the failure path) | *no red-proof — hygiene* | T-10 (RT11) |
| TC21a | Rename `artifacts: -newermt high-water excludes files older than the cursor` — it names a construct that will not exist, and the name is what a reader sees on failure | *no red-proof — hygiene* | R1-T16 |
| TC21b | Rewrite **both** TZ rationales (`:374` deny, `:512` allow). TZ cannot affect the result after this change (`date -u +%s`, jq, no `-newer`), so the axis is **retired** with its reason rather than left as a leftover `export TZ` implying coverage | *no red-proof — the axis is declared retired* | T-06, R1-T16 |
| TC21c | Exact healed cursor where the seam is pinned instead of a range; drop the seam where the real clock suffices | covered by TC9's mutant | T-08, T-09 |

Two existing assertions change deliberately: `bats:1304` and `:1511` assert
`.high_water == null` on the deferred path and become "equals the persisted cursor". They are
promoted to TC6e/f rows rather than left as an incidental note.

**Declared unreachable, so its absence from the table is deliberate**: C5/C6's
"`_epoch_to_iso` empty → re-emit healed" arm. `repo_max` is bounded by `now_epoch` or by the
persisted cursor, both `_is_iso`-valid and inside `todate`'s representable range, so no
constructible input reaches it (RT2 — an unreachable arm is declared, not given a case that
cannot red).

### C12 — `skills/retrospect/pipeline.md`

- **On the deferred path the orchestrator writes the high-water file**, as on the clean path.
  Safe because **the deferred emitter emits the healed read-in cursor, never `max_hw`** —
  `max_hw` is computed by Stage 1 and deliberately discarded on that branch (C6). Revision 2's
  reason ("no candidate was processed") is false and is replaced: execution shows Stage 1 runs
  to completion before the Stage-2 gate.
- **`mark-run` is run for its own exit status**; a non-zero status aborts the run and is
  reported, naming the source. It rejects a bad high-water file and leaves state untouched
  (`retro-state.sh:330-337`), and `pipeline.md` inspects the status at none of its three call
  sites today, so a rejected write is indistinguishable from a successful one.

**Acceptance**: TC6h is the executable half for the deferred path — rc 0 **and** the state
file re-read. `pipeline.md`'s prose has no gate; that is declared, not claimed.

## Go/No-Go Gate

| ID  | Subject | Status |
|-----|---------|--------|
| C1  | `_file_mtime_epoch` — one validated primitive, defined in `llm-utils.sh`, source hoisted | pending |
| C2  | codec — `--arg`, output bounded to `_is_iso`, subset declared not equality | pending |
| C3  | `_now_epoch` — announced seam, bracketed acceptance | pending |
| C4  | `_heal_cursor` — backward heal, integer compare, wording matches the operation | pending |
| C5  | `cmd_artifacts` — hw_map from the config array, aggregate diagnostic, heal disables egress | pending |
| C6  | `cmd_transcripts` — one clock, every derived exit heals, identity fixed at the producer, both arrays guarded | pending |
| C7  | `cmd_github` — local suppression predicate, declared pre-filter, ISO emission | pending |
| C8  | Deletions + gate with per-pattern positive/negative examples | pending |
| C9  | `_resolve_contained` residual: window **and** sink | pending |
| C10 | Header / docstrings, gated by TC12 | pending |
| C11 | TC0–TC21c with per-row mutants | pending |
| C12 | `pipeline.md` deferred write + `mark-run` status | pending |

## Testing strategy

- `bats tests/retro-prescreen.bats`, then `bats tests/` — **own** exit status, never through a
  pipe. Record the case count; a suite that ran 0 cases is not green.
- `bash hooks/check-rule-sync.sh` — own exit status, must be 0.
- The C8 conformance gate runs inside `bats tests/` (TC12).
- Per-guard red-proof per the C11 mutation column, on a scratch copy outside the repo, with
  `git status --porcelain` verified clean after each.
- `bash ./install.sh` last. The installed tree is behind `main` (its triangulate digest ends
  at RT10 while `main` carries R51/RT11), so running the installer is part of completion.

## Considerations & constraints

### Scope contract

- **SC1 — Sub-second cursor precision.** A cursor stays whole-second, so an artifact written
  into the cursor's own second *after* the run that recorded it is skipped permanently
  (under one second, per repo, per run; announced). Anti-Deferral: closing it requires
  widening `_is_iso`/`_norm_iso` — the single validation chokepoint for the whole retrospect
  state file — plus `pipeline.md:122`'s frontmatter shape, six `retro-state.bats` cases, and a
  new sub-second `stat` portability surface this change is otherwise shrinking. Owner:
  follow-up issue, seeded from the audit doc's deferred row.
- **SC2 — R51 handle-carrying containment.** `_resolve_contained` returns a name, not a
  descriptor; closing it needs a file descriptor the shell cannot carry across the sub-agent
  boundary. Considered and not adopted: `[ -L "$resolved" ] && continue` before
  `_summarize_artifact`'s open closes a milliseconds-wide arm while the minutes-wide sub-agent
  arm stays open — narrowing, not closure, plus a second partial adjudicator in a function
  this change does not otherwise touch. Owner: unowned; recorded in the hook's prose.
- **SC3 — The ten `check-*.sh` gates' R50 clause (ii) debt.** In the audit doc's deferred
  table. Untouched.
- **SC4 — `skills/retrospect/sources/artifacts.md`** stays at its `main` state; the abandoned
  branch's edit added an obligation the sub-agent's tool set cannot discharge (C9 fixes the
  hook-side prose instead).
- **SC5 — `last_run` / `snoozed_until` in `retro-state.sh` are unhealed.** Same primitive —
  *a persisted timestamp compared against the present to decide whether work happens* — read
  by the `due` comprehension, whose `try/catch` arms handle *malformed* values but not a
  well-formed *future* one. Their effect is quieter than the class this change fixes: the
  source is never invoked, so there is no heal, no warning, no document.
  Anti-Deferral: **on unit of work, not on reachability.** Revision 2 justified the deferral
  by claiming `high_water` is poisonable through untrusted sibling-repo mtimes while these are
  not; C5/C6 now bar a future mtime from advancing `repo_max` on both arms, so post-change that
  route is closed and the surviving paths (state written by a pre-heal version; a backward
  system clock) reach all three members equally. The deferral stands because the remedy is two
  clauses in `retro-state.sh`'s `due` comprehension plus `retro-state.bats` cases — the
  chokepoint SC1 declines to open. `last_prompted` (`:266-273`) is **outside** the class: it
  compares by equality, so a future value fails open toward more prompting. Owner: follow-up.
- **SC6 — A total Stage-2 distillation failure drains the transcripts source.** When
  `_raw_llm_egress_ok` passes but every `llm_request` returns empty, the hook emits
  `candidates: []`, `deferred: false` and a fully advanced `high_water`; `pipeline.md:67-69`'s
  clean-source rule persists it and the scanned transcripts are skipped irrecoverably. The
  Stage-1/Stage-2 pipeline is out of scope, but C12 edits this same `mark-run` decision so the
  composition is in reach. Cheap closure if wanted later: emit the healed cursor rather than
  `max_hw` when `stage2_allowed=1` and `lessons` is empty while `excerpts` was not. Owner:
  follow-up.

### Risks

- **R-1 Enumeration cost.** 1.39 s / 1167 files at one `stat` per file. An order-of-magnitude
  growth makes the transcripts scan ~14 s. Recorded as the baseline; not pre-optimised,
  because the only pre-filter available is the one being deleted for cause.
- **R-2 BSD arms remain unexecuted** (VC1); their number drops from four constructs to one.
- **R-3 `jq` becomes a hard dependency of the date path.** It already is one (line 34).
- **R-4 A heal costs a full re-mine of the affected source.** The trigger is
  `persisted > now`, whose ordinary producers are **backward clock movements** — NTP step-back,
  RTC-local-time dual boot, VM snapshot restore — not only cursor corruption. It is not
  necessarily once: if the clock is behind every file's mtime, every mtime reads as future,
  `repo_max` never leaves 0, and the re-mine repeats each run until the clock is corrected.
  Sub-agent tokens are the cost; raw egress is **not**, because a heal disables it for that
  run (C5/C6). Announced on stderr so the cost is attributable.

### Out of scope

Everything in `hooks/retro-prescreen.sh` outside the cursor machinery: `scrub`, the `scout`
source, the Stage-1/Stage-2 transcript pipeline (except SC6's declared composition), and
`_resolve_contained`'s symlink-chase logic (prose only, per C9). The S3 loopback egress gate's
**implementation** is out of scope; its **composition** with `_resolve_contained` (C9) and with
the heal (R-4) is not.

## User operation scenarios

1. **Steady state.** Two repos, ~30 artifacts each, cursors a week old. Only artifacts newer
   than each cursor become candidates; the emitted high-water round-trips through `mark-run`;
   an immediate second run yields zero candidates and **one** aggregate suppression line per
   repo, not thirty.
2. **Recovering from the poisoned state this pipeline is in.** A repo's persisted cursor is
   `2100-01-01T00:00:00Z`. One stderr line naming the source and the reset, an emitted cursor
   of `1970-01-01T00:00:00Z`, the archive re-mined once, **and no raw artifact text sent to
   the LLM on that run** — normal incremental behaviour from the run after.
3. **A clock stepped back one hour.** Every source's cursor is ahead of `now` and resets. Same
   as scenario 2 across all sources, and the announcement names the reset so an operator can
   connect it to the clock rather than to corruption.
4. **A clock-skewed sibling checkout.** One artifact carries a future mtime: it is *mined*
   this run, the cursor does not follow it, stderr says so.
5. **A degraded toolchain.** `stat` shadowed by a wrapper printing a localized string and
   exiting 0: every candidate kept, no cursor advances, exit 0, a JSON document still emitted.
6. **A transcript being written now.** `CLAUDE_SESSION_ID` unset, one `.jsonl` 30 s old and one
   20 min old: the fresh one excluded, the old one mined, the emitted cursor is the old one's
   mtime.
7. **A repo whose root or archive directory is briefly absent** (unmounted share, mid-clone,
   `git worktree` move). Its cursor is still present in the emitted map at its persisted value,
   stderr names the skipped repo, and the next run mines incrementally rather than from 1970.
