# Plan Review: retro-prescreen-cursor-epoch
Date: 2026-07-31
Review rounds: 1, 2 (round 2 first; round 1 follows below from "## Round 1")

---

# Round 3 (final plan round)

34 findings: 1 Critical, 27 Major, 6 Minor. Scoped to two questions — are round 2's
dispositions folded, and what falls out of deriving over code. All three experts
re-established the baseline (74/74, unpiped) and verified the tree unchanged.

Trend: **43 (3 Crit) → 39 (3 Crit) → 34 (1 Crit)**. Criticals converge; the count does not.

## The decisive observation

Round 3's findings were, almost without exception, **only findable by building and
executing the planned implementation**:

- Testing spliced a hook carrying the planned C1–C5/C7 machinery and measured each
  mutation's delta — finding TC15's delta is zero, TC18's is zero at N=1, and TC17 leaks
  with two repos.
- Functionality **ran the derivation greps the plan publishes** and found they do not
  return the members the plan claims (`rg 'high_water'` returns neither `:453`, `:458`
  nor `:598`).
- Security executed `due` under a backward clock and showed the heal announcement is
  unreachable in the scenario that produces it.

A plan cannot verify these by being read. This is where plan review stops paying, and it
is the reason the loop ends here rather than at "No findings".

## The dominant class, and the third mechanism replacement

Across rounds 2 and 3 one class fired at least eight times: **the remedy was applied at
the named site and a derived sibling was missed** — `hw_map` ×3, forbidden patterns ×4,
per-file diagnostics ×2, sourcing sites, N-R1 spellings, `_json_empty` exits. Round 2
replaced two mechanisms for it; round 3 found the class **inside** one of the
replacements (`date[^|;&]*-d[[:space:]]` matches the hook's own `candidate`/`updated`
vocabulary, and the must-NOT-match example chosen could not detect it).

**Third replacement, folded**: every "derived set" obligation ships as three things —
(a) the grep command, (b) its output at plan time, (c) a bats assertion that the set has
not grown. "Did the author enumerate completely?" stops being a review question. Applied
to N-R1's array spellings, N-R2's per-file diagnostics, C1's stat and sourcing sites,
C5's path-printing diagnostics, and F-R4's cursor-reading exits. Corollary from T7:
**must-NOT-match examples are drawn from the subject's own vocabulary**, not from the
construct being retired.

## Convergence

| Merged subject | Raised by | Severity |
|---|---|---|
| The `hw_map` seed's **value** is unspecified; only a healed pre-loop seed satisfies TC13 | Func F4 · Sec S3 · Test T6 | Major |
| N-R2's output bound covers 1 of 3 per-file diagnostics | Func F5 · Sec S4 | Major |
| TC16 cannot red-prove the identity fix on the stream it was written for | Func F1 · Test T1 (Critical) | **Critical** |
| `_iso_to_epoch`'s stated validation cannot yield "epoch 0, no warning" for pre-1970 | Func F6 · Sec S8 | Major |
| TC15's mutation is vacuous — `cmd_github` has no cursor-deletion path | Func F9 · Test T2 | Major |
| `_repo_relative` at `:63` still degenerates after the R2-14 hoist | Func F2 · Sec S7 | Major |
| The heal→egress remedy is single-repo-shaped and ordering-dependent | Sec S1 · Test T3 | Major |

## Dispositions — all accepted

**Code-changing (folded into the plan):**

- **R3-1 (F4/S3/T6, Critical-adjacent)** — C5/C7's seed value is
  `_heal_cursor(_iso_to_epoch(persisted), now)` per repo, computed in a **single pre-loop
  pass over `repos` from one `retro-state.sh show --json` read**. "The loop only raises
  values" is **dropped** — it contradicted C4's backward heal (a poisoned repo's healed
  value could never be persisted) and TC13's "equals the persisted value" green-lit a seed
  that bypasses the heal (executed: `2100-01-01` re-persisted). TC13 becomes "equals the
  **healed** persisted value" and gains a poisoned arm. The single read also closes the
  per-repo `_state_high_water` interval round 2 recorded and did not raise.
- **R3-2 (F3)** — F-R4's and C6's published derivation instruments do not return their
  claimed members. Replaced with `grep -n '_json_empty\|high_water'`, whose eight members
  are recorded. `:455`/`:460` (gh absent / unauthenticated) gain the hoist F-R4 assumed:
  the seed and heal move **above** the `gh` guards.
- **R3-3 (F7, Critical composition)** — C5's empty-`repos` → `high_water: null` remedy
  composes with `pipeline.md:67-69`'s existing `(when non-null)` guard so `mark-run` is
  **skipped entirely** and `last_run` never advances — the source becomes permanently due
  and prompts at every session start. Executed: `mark-run … <null>` → rc 1;
  `mark-run … <{}>` → rc 0 with the wipe. C12 now states: `high_water == null` → run
  `mark-run <source>` **without** `--high-water-file`, at `:69`, `:71` **and** `:186`/`:189`.
- **R3-4 (F5/S4)** — the aggregate rule covers **all three** per-file diagnostics
  (suppressed / future-mtime / unreadable-mtime). Measured on 200 files: 200 lines /
  19 KB and 200 lines / 28 KB for the two the plan omitted, in the plan's own scenarios 5
  and 3 — and R-4 states the clock-behind case is a *steady* state.
- **R3-5 (F6/S8)** — `_iso_to_epoch` validates `^-?[0-9]+$`; a negative parse returns `0`
  **silently** (a representable pre-epoch instant is not corrupt); `""` only on parse
  failure, and the caller warns on `""`.
- **R3-6 (F2/S7)** — `_repo_relative` takes the root to strip as an argument: `:63` passes
  the **lexical** root, `:380`/`:386` pass the **physical** one, because their operands
  differ in kind. The `resolved_root` hoist stays (required for `set -u`) but is no longer
  justified by the symlink case. `_repo_relative` gains a contract row with its own
  signature, its three call sites, and the root-absent arm.
- **R3-7 (S1/T3)** — the heal verdict is computed for the **whole configured array**
  before `_raw_llm_egress_ok` is consulted. Executed: with `repos = [sane, poisoned]` an
  in-loop heal ships the sane repo's raw bytes off-machine while passing TC17. For
  transcripts the remedy only **defers** the widened egress by one run (the deferred
  emitter persists epoch 0, so run N+1 sends everything) — declared in C6 and R-4, with
  the run-N announcement saying so, plus a run-N+1 case.
- **R3-8 (S2)** — **SC5 is closed, not deferred.** Executed: `last_run` ahead of the
  present makes `cmd_due` return `[]`, so `retro-prescreen.sh` is never invoked and the
  heal announcement never prints — scenario 3 falsified. SC5's members do not merely
  duplicate the class more quietly; they **gate the in-scope remedy's observability**. The
  Anti-Deferral was also mis-costed: SC1's chokepoint is `_is_iso`/`_norm_iso` (value
  syntax); this remedy is in `cmd_due`'s jq comprehension (value ordering) — same file,
  different chokepoint, and smaller than C7's new predicate which was accepted in scope.
  New **C13**.
- **R3-9 (S5)** — the `command -v _file_mtime_epoch` guard covers **both** sourcing sites
  (`:304`, `:738`), and its spelling is `_json_empty` + `exit 2` rather than a bare exit.
  F-R5's taxonomy widens to admit "required primitive unavailable".
- **R3-10 (S6)** — `llm-utils.sh:95` is a sixth member of the persisted-timestamp
  primitive, inside the statement C1 already rewrites: a future cache mtime makes
  `now - mtime` negative, `-lt 300` true, and the host list served stale indefinitely. Two
  tokens close it. `check-pre-pr.sh:437` is cited in C4 as this repo's own healed precedent.
- **R3-11 (F8)** — N-R1 spans bare `"$@"` too: `:853` `for arg in "$@"` is the same
  bash-3.2 class and sits on the dispatch path, including `scrub`, which the file header
  names as the single shared artifact. Spelled `${@+"$@"}`, with a C8 row.
- **R3-12 (T7/T8)** — C8's `date` row becomes `\bdate\b[^|;&]*-d[[:space:]]` (executed:
  the old form matches a comment containing `candidate … -d`), and two rows are added for
  the bash-3.2 constructs N-R1 names but the table did not gate (`declare -A`, negative
  subscripts). Every must-NOT-match example is redrawn from the subject's own vocabulary.
- **R3-13 (S9)** — a `RETRO_PRESCREEN_NOW` **ahead of the real clock** is rejected. The
  seam exists to pin the present *downward* relative to fixture mtimes; a future value
  disables the 300 s freshness rule and admits the in-flight session transcript into the
  Stage-2 egress set. This is RS5's bound, applied only where it costs nothing.
- **R3-14 (F9/T2)** — TC15 is dropped: `cmd_github`'s only repo-loop `continue` precedes
  everything and `hw_map` is written unconditionally, so no seed placement changes the map
  (executed: byte-identical). C7's github seed is built from the **JSON array with empty
  entries dropped** — an empty element would become a `""` key that `_validate_hw`'s
  github arm rejects, making the source worse.
- **R3-15 (S10)** — `cmd_github`'s `title` bypasses `cmd_scrub` while `comment_bodies` go
  through it, contradicting the file header's single-scrub invariant, and it reaches a
  committed artifact via the mining sub-agent. Recorded as **SC7** with the one-line
  closure named (out of scope by declaration, but C7 restates this source's shape).

**Test-plan changes (folded into C11):**

- **R3-16 (F1/T1, Critical)** — TC16 is split. Executed: the `has("index")` filter throws
  on the normal branch (candidates are lesson *strings*, rc 5), is vacuously true on an
  empty candidate set, and `$DOC` and `$output` are the *same variable*
  (`bats:23-33`), so the human-mode stream R2-7 identified was never read. New rows assert
  a non-empty candidate set first, read human mode by a second invocation without `--json`,
  and scope the shape assertions to the deferred branch.
- **R3-17 (T4)** — TC9b's mutation `-gt → -ge` has zero delta against the read-in heal its
  heading names; it reds only on the **future-mtime bound**. The row names that predicate.
- **R3-18 (T5)** — the skipped-repo diagnostic emits the repo's **basename or a per-run
  ordinal**, not the configured path: a repo root has no repo-relative form, every
  artifacts fixture configures an absolute path, and TC8a/TC8b assert the physical root and
  `$HOME` are absent. The diagnostic gains its own mutation (delete it → 1 line becomes 0).
- **R3-19 (T9)** — TC18 pins N ≥ 2; at N = 1 the aggregate and per-file spellings are
  indistinguishable, and every artifacts fixture but one is cardinality 1.
- **R3-20 (T10)** — a `mark-run` round-trip case per **map** source (artifacts, github);
  TC6h round-trips only the transcripts scalar. Executed: a malformed configured github
  repo yields rc 1 and, under C12's new status rule, aborts the whole source.
- **R3-21 (F10)** — `pipeline.md` Step 4 is an unlisted `high_water` consumer: it writes
  the per-repo **minimum** into a committed doc's frontmatter, so a healed run records 1970
  as the durable backup. Added to the walkthroughs with the amplification named.
- **R3-22 (F11, F12, S11, T11)** — batched precision items: a fifth mtime spelling in
  `build-codebase-fingerprint.sh` declared out of class with its reason; three off-by-a-few
  bats citations; C4's stderr wording gains the source prefix every other diagnostic uses;
  `_repo_relative`'s definition site; C8 row 3 subsumed by row 1.

---

# Round 2

39 findings: 3 Critical, 25 Major, 11 Minor. Every expert re-established the baseline
(`bats tests/retro-prescreen.bats` → exit 0, 74/74, read unpiped) and verified
`git status --porcelain` byte-identical at start and finish.

## Verdict on round 1's Criticals

- **CR-1(a) clamp-to-now — genuinely closed.** Functionality and Security independently
  confirm the reset-to-epoch-0 direction is correct, matches `pipeline.md:134-137`, and
  that the "healed ≤ persisted, therefore safe on every branch" argument holds under
  `_heal_cursor`'s definition.
- **CR-1(b) deferred branch — closed at the emitter, false at the justification** (R2-1).
- **CR-1(c) the `continue` between heal and emission — relocated, not closed** (R2-2).

## Round-2 convergence

| Merged subject | Raised by | Severity |
|---|---|---|
| The `hw_map` remedy covers one of three cursor-deletion paths | Func F1 · Sec S2 · Test T3 | **Critical** |
| Every deferred/empty fixture expects `1970`, so an epoch-0-constant build is green | Test T2 | **Critical** |
| C12's safety justification is falsified by execution | Test T7 · Func F6 · Sec S4 | Major |
| C8's forbidden patterns deny conformant code — twice | Test T1 · Func F3 | Major |
| The transcripts identity leaks from a producer C6 does not cite, on a stream C6 does not touch | Func F5 · Sec S3 | Major |
| TC9's allow half is unconstructible | Test T6 · Func F11 | Major |
| C2's "accepts exactly `_is_iso`'s language" is false in three directions | Func F13 · Sec S5 | Major |
| `F-R4`'s "every branch" omits the `_json_empty` exits | Func F7 · Sec S7 | Minor |

## Round-2 Critical findings

### R2-1 — The cursor-deletion path is closed at `:330`, open at `:320`, and open again on empty `repos` (Func F1, Sec S2, Test T3)

C5's round-1 remedy was worded over a **line** — "`hw_map` is seeded immediately after
read-in, before any `continue` that can follow it" — and the read-in is `:323`. Two
`continue`s **precede** it, so no seeding placed after read-in can reach them:

| Site | Condition | Covered |
|---|---|---|
| `:320` `[ -d "$expanded" ] \|\| continue` | repo **root** absent | **no** — precedes read-in |
| `:330` `[ -d "$glob_dir" ] \|\| continue` | archive **subdir** absent | yes |
| loop never entered | `repos` is `[]` → `hw_map` stays `{}` | **no** |

Reproduced end-to-end by two experts independently. With `repoB`'s root moved away, the
emitted map omits `repoB`; `mark-run` returns 0; `retro-state.sh:346`'s whole-object
replacement **deletes** the key; the next run re-mines that archive from 1970 and — with
`allow_remote_llm` — re-sends it. The run's stderr never mentions `repoB`. The empty-`repos`
variant emits `high_water: {}`, which passes `_validate_hw` trivially and wipes **every**
repo's cursor in one write. Test adds that the remedy has no acceptance row at all, and no
mutation, for either `cmd_artifacts` or its `cmd_github` twin.

**Disposition — accepted; the remedy is replaced, not extended.** Twice now the fix has been
written over a named line and twice a sibling line has been found. C5's invariant is restated
over the **loop and the config array**: every string in `repos` appears as a key in the emitted
map on every path through `cmd_artifacts`, seeded from the config array *before* the loop, with
the loop only raising values. Empty `repos` emits `high_water: null`, never `{}`. Acceptance
rows added per `continue` (a single mutant on one arm does not red the other) plus a
repo-relative stderr diagnostic naming the skipped repo — the silence is half the defect.

### R2-2 — Every deferred/empty-branch fixture expects `1970-01-01T00:00:00Z`, so "emit epoch 0 unconditionally on defer" passes the whole named suite (Test T2)

TC6a, TC6b and the two changed existing assertions (`:1304`, `:1511`) all derive their expected
value from a seeded state, and `retro-state.sh:100` seeds `high_water: null` while both
`cmd_transcripts` and `cmd_artifacts` default it to `1970-01-01T00:00:00Z`. An implementation
that emits a **constant** epoch 0 on the deferred path satisfies C12's stated invariant verbatim
("≤ the persisted one") and is green on all four rows. What it ships is R-4's declared heal cost
incurred on **every** deferred run: every `/retrospect` without a loopback LLM resets the
transcripts cursor to 1970 and re-mines the corpus.

**Disposition — accepted.** At least one deferred-branch row gets a **non-default** persisted
cursor. Verified constructible: `mark_high_water transcripts '"2026-07-14T16:44:06Z"'` plus a
transcript aged 600 s makes the three candidate implementations mutually distinct —
cursor-emitter → `2026-07-14T16:44:06Z`, `max_hw`-emitter → the file's mtime, epoch-0 constant →
`1970-01-01T00:00:00Z`. The `max_hw` and epoch-0 spellings each become their own mutation row.

## Round-2 Major findings

### R2-3 — C12's safety justification is falsified by execution (Test T7, Func F6, Sec S4)
C12 justified the deferred-path write with "*no candidate advanced the maximum, because none was
processed*". Stage 1 (`:646-734`) runs to completion and advances `max_hw` at `:664-665`
**before** the Stage-2 egress gate at `:740` is consulted. Security instrumented a scratch copy
and captured `cursor=1970-01-01T00:00:00Z max_hw=2019-12-31T15:00:00Z` at the deferred emitter.
The conclusion survives; the reason does not — and the reason is what licenses the next edit.
`max_hw` is the variable in scope and the one the *normal* branch emits, so it is the natural
thing to reach for; today `pipeline.md:70-72` discards it, and C12 removes that discard.
**Accepted**: the true reason replaces the false one — *the deferred emitter emits the healed
read-in cursor, never `max_hw`; `max_hw` is computed by Stage 1 and deliberately discarded on
this branch* — stated as a C6 invariant on the emitter, with `deferred emitter → $max_hw` added
as a mutation row (the `null` mutant does not discriminate the two correct-looking spellings).

### R2-4 — C8's forbidden-pattern list denies conformant code, for the second round running (Test T1, Func F3)
Round 1 killed `date -[ud][[:space:]]` because it matched the `date -u +%s` C3 requires. Round 2
narrowed that correctly and introduced two patterns with the identical defect. Executed:
- `"\$\{…\[@\]\}"` matches the guarded idiom **C6 itself mandates**
  (`${excerpts[@]+"${excerpts[@]}"}` textually contains `"${excerpts[@]}"`), and also matches
  `:646` `for f in "${files[@]}"` — a genuine N-R1 violation in **neither** C6's edit list nor
  C8's deletion set, guarded today only by the empty-file-set early return that C6 changes.
- `jq [^']*"` matches essentially every correct `jq --arg NAME "$value" '…'` in the hook; C2's
  qualifier "on a program argument" is prose a grep cannot express.

**Disposition — the mechanism is replaced, not the patterns.** Three instances of one class in
two rounds is the trigger this whole change exists to honour. Hand-written regexes reviewed by
eye will keep producing this. Every forbidden pattern now carries, in the same table, a
**must-match** example (a violating spelling) and a **must-not-match** example (the conformant
spelling the plan mandates), and TC12 asserts **both for every pattern**. "Is this regex right?"
stops being a review question and becomes a test assertion. This also discharges Test's T10
(the deny-side proof covered one of eight patterns) with the same construct. `:646` is added to
C6, and the N-R1 obligation is stated as *every* `"${name[@]}"` in the file, derived by the
pattern rather than by a list of two.

### R2-5 — `cmd_github` has no local cursor adjudicator at all, and `LAG_MARGIN` makes F-R2 permanently unmet (Func F4)
Derived from code and reproduced: `cmd_github` contains **no suppression predicate**. Every PR
the API returns becomes a candidate unconditionally; `_iso_to_epoch` on `updatedAt` only bounds
`repo_max`. A stub returning a PR six years older than the cursor yields that PR as a candidate.
Compose with the `LAG_MARGIN` this revision *added*: the query bound becomes `healed − 86400`,
so every run re-requests the trailing 24 hours and nothing local suppresses them — the source
re-mines that window **forever**, not once. The mitigation created the F-R2 violation.
**Accepted**: the missing adjudicator is added (`updated_epoch -le cursor_epoch` → skip;
unparseable → keep, do not advance, warn). That makes `LAG_MARGIN` free and makes C7 satisfy
R47 sub-clause (c) for the first time — the query becomes a genuine narrowing over an
authoritative local decision. Paired acceptance case: a PR below the cursor is returned by the
stub and does **not** appear in `candidates`; no existing github case would fail without it.

### R2-6 — Heal-to-epoch-0 turns any backward clock movement into a full-corpus off-machine egress (Sec S1)
Derived from the predicate rather than the plan's narrative, `_heal_cursor`'s trigger is
`persisted > now`, whose ordinary non-adversarial producers are clock movements — an NTP
step-back, an RTC-local-time dual boot, a VM snapshot restore, a container started before time
sync. `cmd_artifacts` decides `artifacts_llm_ok` **once, not per file** (`:298-310`), and
`_summarize_artifact` pipes each candidate's **raw bytes** to `llm_request` (`:431-433`); with
`allow_remote_llm` that leaves the machine. `github` has `--limit 200`; `artifacts` has no cap
at all. R-4's "re-mines its whole corpus **once**" is also false in the fixed-point case: with
the clock behind every file mtime, every mtime is "future", `repo_max` never leaves 0, and the
re-mine repeats every run.
**Accepted, with the reviewer's own remedy shape.** The heal is *not* bounded — bounding it
would un-mitigate C7's incompleteness mode 3, which is closed precisely by the heal widening the
query. Instead the two boundaries are separated: **when a heal fires for a source, that run
forces `artifacts_llm_ok=0` / `stage2_allowed=0`.** Recovery is preserved in full (the sub-agent
`Read`s locally; file-list-only is already the documented degraded mode), while the off-machine
set does not widen. R-4 and scenario 2 gain the true trigger class and lose the "once" claim.

### R2-7 — The transcripts identity enters at a line C6 does not cite, and leaks on a stream C6 does not touch (Func F5, Sec S3)
Complementary halves of one defect. Func: `:750` only *renames the field*; the session basename
enters at `:726`, where `counts` is **keyed** by it — so an implementer applying C6 literally at
the cited line ships `{"index":"7f3a-…-b21.jsonl","event_count":3}` and F-R6 stays falsified by a
citation. Sec: the **human-mode** branch at `:754` prints `.key` verbatim to **stdout**, which
C6 does not touch at all; reproduced, the printed basename *is* the session UUID.
**Accepted**: the invariant is restated on the **value at its producer** — `counts` is keyed by
a per-run ordinal assigned at `:726`; no basename, path or session identifier enters `counts` or
either emitted stream. Both streams then inherit the fix from one edit. The acceptance case
asserts the emitted index does **not** match `.*\.jsonl` and that neither stream contains the
fixture's basename — an assertion on the field *name* would pass over the defect.

### R2-8 — C1's mandated fourth adopter has no valid definition site (Func F2)
C1 widened the mtime primitive to `llm-utils.sh:94` without saying where `_file_mtime_epoch` is
defined. Both placements are broken, and the plan's own cited evidence contains the
contradiction: it justifies the widening with "`retro-prescreen.sh` sources that file (`:304`,
`:738`)" — and `:738` is **downstream** of the adopter sites at `:619` and `:652`. Defining it in
`retro-prescreen.sh` instead breaks `llm-utils.sh`'s three other independent consumers
(`pre-review.sh:11`, `commit-msg-check.sh:9`, `llm-commands.sh:13`), silently disabling the 300 s
host-discovery cache in all of them.
**Accepted**: `_file_mtime_epoch` is defined in `llm-utils.sh`, `cmd_transcripts`'s `source` is
hoisted above the gather loop, and — because that `source` is `2>/dev/null`-suppressed — a
`command -v _file_mtime_epoch` guard is required after it, or the helper vanishes silently.

### R2-9 — Deleting `-newer` turns the per-file suppression diagnostic into ~127 KB of stderr per steady-state run (Func F9)
The suppression diagnostic fires per suppressed file, unconditionally. With `-newer` gone, a
healthy steady-state run enumerates and suppresses the whole corpus: measured 1167 × 109 bytes =
**1167 lines / ~127 KB every run**, growing linearly. The heal announcement, the future-mtime
warning, the clock-disabled notice, the C3 seam notice and R2-1's new skipped-repo signal are all
single lines on that same stream. R50 clause (ii) is why those diagnostics exist; burying them
defeats them as surely as omitting them. N-R2 bounds the *time* cost of full enumeration; the
*output* cost is the axis the deletion actually changed and no contract mentioned it.
**Accepted**: one aggregate line per source per run (`N of M files at or below the cursor —
suppressed`) replaces the per-file diagnostic. `tests/retro-prescreen.bats:428` asserts on the
effect rather than the string, so nothing obstructs the change. N-R2 gains an output-volume bound.

### R2-10 — C2's "accepts exactly the language `_is_iso` defines" is false in three executed directions (Func F13, Sec S5)
`_is_iso` is a purely syntactic regex; `jq fromdate` is `strptime`-backed and semantic. Executed:

| value | `_is_iso` | `fromdate` | C2's `_iso_to_epoch` |
|---|---|---|---|
| `1969-12-31T00:00:00Z` | accepts | `-86400` | fails `/^[0-9]+$/` → epoch 0 **+ "corrupt" warning** |
| `0000-01-01T00:00:00Z` | accepts | `-62167219200` | same |
| `2026-13-45T99:99:99Z` | accepts | parse error | empty → epoch 0 |
| `2026-02-30T00:00:00Z` | accepts | `1772409600` (→ Mar 2) | silently accepted, **wrong instant** |

All divergences resolve to epoch 0 — which R2-6 shows is now the expensive direction — and
`_is_iso` gates both writers, so such a value is persistable through the supported CLI.
**Accepted**: the equality claim is dropped and replaced by the true statement of the subset plus
its residual; pre-1970 values map to epoch 0 **without** the "unparseable" warning (the warning
misreports a well-formed cursor as corrupt); all four rows join C2's acceptance list.

### R2-11 — `pipeline.md` never reads `mark-run`'s exit status, and C12 adds a fourth silent call site (Func F10)
`cmd_mark_run` returns 1 and leaves state untouched on a rejected high-water file (`:330-337`).
`pipeline.md` invokes it at `:69`, `:71`, `:186` and never inspects the status; there is no
"verify the cursor advanced" step anywhere. Round 1 recorded this and folded it into MJ-3, whose
disposition addressed only the emitted *range* — the status read was never closed, and C12 now
adds a call site on the one path whose entire purpose is persisting the heal.
**Accepted** into C12: `mark-run` is run for its own exit status; a non-zero status aborts the
run and is reported. TC6a's round-trip asserts rc 0 **and** re-reads the state file.

### R2-12 — TC9's allow half is unconstructible; TC10's named assertion has zero delta (Test T6, Test T5, Func F11)
Two mutants that do not discriminate what the plan says they do, both proved by execution.
- TC9 case 1 (`cursor == now`): a file is a candidate only if `mtime > cursor`, which at this
  boundary implies `mtime > now`, which C5 routes to "kept, `repo_max` untouched, warn". The
  cursor cannot advance; "advances normally" is unbuildable.
- TC10 ("candidate *between* cursor and now"): correct and mutant implementations produce a
  **byte-identical** JSON document; only the stderr-absence assertion reds, and the plan names
  two assertions where RT7 (g)(iii) requires attribution to one.

**Accepted with the executed remedies**: TC9's allow half moves to `cursor == now − 1` with a
candidate at exactly `now` (cursor genuinely advances; the `-ge` mutant reds by healing a cursor
legitimately in the past), and `cursor == now` becomes a third cell asserting "no heal fires,
cursor unchanged". TC10's candidate moves **below** the cursor — measured, that puts the delta on
`.candidates` and `.high_water` rather than on a diagnostic string.

## Round-2 Minor findings (all accepted)

- **R2-13 (Func F7, Sec S7)** — F-R4's "every branch" was derived from the plan's reasoning, not
  from the code's exits. Three further `return 0` paths emit a document without reading a cursor:
  `:453-457` (`gh` absent), `:458-462` (`gh` unauthenticated), `:598` (transcripts root absent).
  Nothing is deleted (`null` preserves), so this is bounded; the derivation failure is the point.
  The read-in and heal move above the environment guards, or the three are declared as an SC row.
- **R2-14 (Func F14, Sec S6)** — `_repo_relative` cannot do what C5 says at `_resolve_contained:63`:
  `resolved_root` is computed at `:67`, *after* the control-character branch, and `$dir` there is
  lexical, so stripping a physical prefix is a no-op and the message degrades to the literal
  string `review` for every repo. `resolved_root` is hoisted above the check; TC8c gains a
  presence assertion and an RT10 allow case (round 1 fixed exactly this shape for TC8 and the
  newly-added third member did not inherit it).
- **R2-15 (Func F12)** — C5's emission fallback re-emits the **persisted** (i.e. possibly poisoned)
  value; the design's own rule is that the emitted cursor is a function of the heal. Changed to
  "healed" in C5, C6 and the fail-directions bullet.
- **R2-16 (Func F8)** — the 5-minute rule's clock is unspecified: routing it through `_now_epoch`
  gives `RETRO_PRESCREEN_NOW` a second control it can silently disable (a *valid* integer older
  than the corpus excludes every transcript); keeping `date +%s` leaves two clocks deciding one
  predicate (R48). C6 states which clock and why. Separately, F-R3's universal wording is
  contradicted by every contract's clock-unavailable arm and is narrowed with the residual declared.
- **R2-17 (Func F15)** — N-R2's 2.01 s models one `stat` per file while C1 keeps two adopters in
  `cmd_transcripts` (measured 1.39 s vs 2.81 s / 1167 files). The mtime is read once in the gather
  loop and carried into Stage 1, which also removes 1167 forks; C1's adopter count becomes three
  and the R42 derivation is restated.
- **R2-18 (Func F17)** — C10's acceptance greps test none of C10's invariants, and the `clamp`
  vocabulary survives unguarded for an operation that now resets to 1970 (`:203` would tell an
  operator "clamped to `<now>`" after a full reset). `clamp` joins the forbidden-pattern list and
  C4 states the new wording.
- **R2-19 (Func F16)** — the mtime and codec primitives have unmigrated test-side twins
  (`bats:456`, `:1472`, and `iso_at`). Kept deliberately as an **independent oracle** — that is
  what makes TC0's literal-in-both-directions assertions meaningful — and the reason is now
  recorded rather than left as drift.
- **R2-20 (Test T11, T12, T13, T14)** — C10 has no TC row (folded into TC12); TC7d asserts a range
  where the literal is determined and has no RT10 allow half; C3's "within a second" tolerance is
  replaced by a before/after bracket; TC6a's single mutation reds two assertions.
- **R2-21 (Sec S8, previously overlooked)** — when `_raw_llm_egress_ok` passes but **every**
  `llm_request` in Stage 2 returns empty, the hook emits `candidates: []`, `deferred: false` and a
  fully advanced `high_water`; `pipeline.md:67-69`'s clean-source rule then persists it and the
  scanned transcripts are skipped irrecoverably. The Stage-1/Stage-2 pipeline is out of scope, but
  C12 edits this same `mark-run` decision, so the composition is in reach. Declared as **SC6**
  with the cheap closure named.

## Corrections to round 1's own dispositions

- **SC5's reachability argument is weakened by this revision** (Security, R34). Round 1 deferred
  `last_run`/`snoozed_until` on the grounds that `high_water` is poisonable through untrusted
  sibling-repo mtimes while they are not. C5/C6 now bar a future mtime from advancing `repo_max`
  on **both** arms, so post-change that route is closed and the surviving poisoning paths (legacy
  state written before this change; a backward system clock) reach all three members equally. The
  deferral still stands on cost and unit-of-work grounds — the remedy is the `retro-state.sh`
  chokepoint SC1 declines to open — but SC5's stated *reason* is corrected.
- **A fifth member of the persisted-timestamp primitive** was derived independently
  (Functionality, R42): `last_prompted` vs `_today()` at `retro-state.sh:266-273`. It compares by
  **equality**, not ordering, so a future value fails open toward *more* prompting. Correctly
  outside SC5; recorded so the set is closed rather than merely listed.
- **An R51 interval, recorded not raised** (Security): `_state_high_water` re-invokes
  `retro-state.sh show --json` **per repo** inside the artifacts loop, so a concurrent state write
  mid-run yields a mixed cursor set that the whole-object replacement then persists. Single-user,
  single-writer namespace — racy, not attacker-schedulable.

## Process assessment

Round 1: 43 findings. Round 2: 39. The count has not converged, but the *character* has changed
completely, and the change is the signal.

Round 1's Criticals were against the **design** — the heal direction was wrong, the mechanism
placed the pre-filter in the deciding position. Both experts now confirm that design is closed
and correct. Round 2's findings are overwhelmingly against the **document's own mechanism prose**:
a wrong line citation (R2-7), a justification falsified by execution (R2-3), two regexes that deny
conformant code (R2-4), two acceptance cases that cannot be built (R2-12), an equality claim false
in four directions (R2-10), a helper with no valid definition site (R2-8). Genuine design findings
in round 2 number five (R2-1, R2-2, R2-5, R2-6, R2-9).

This is precisely the pattern this repository mined and deferred in
`retro-artifacts-lessons-2026-07-31.md`: *"A specification accretes its own revision history —
two consecutive specifications reached 1951 and 1072 lines and three review rounds produced 3
Critical and 21 Major findings with none against the design — every one against the document's
own mechanism prose."* The plan is at 800 lines and exhibiting it.

Two mechanism replacements are folded in response, both applying this change's own governing rule
(when the Nth fix opens a new instance of the class, replace the mechanism) one level in:

1. **The forbidden-pattern list** produced its class three times in two rounds. Every pattern now
   ships with a must-match and a must-not-match example asserted by TC12, converting a review
   question into a test assertion.
2. **The `hw_map` remedy** was written over a named line twice and a sibling line was found twice.
   It is restated over the config array and the loop, so a new `continue` cannot open it again.

---

# Round 1

## Changes from Previous Round

Initial review. Three expert sub-agents (Functionality / Security / Testing) reviewed
`retro-prescreen-cursor-epoch-plan.md` in parallel against the R1–R51 / RS1–RS6 / RT1–RT11
rule set, each in an isolated scratchpad, each with a standing instruction to verify claims
by execution rather than by reading. 43 findings: 3 Critical, 29 Major, 11 Minor. A local
LLM pre-screening pass ran first and its 3 findings were addressed before the experts saw
the plan (F-R6 per-stream restatement, the bash-3.2 NUL-loop contract in N-R1, and scoping
the `exit 127` measurement to bash 5.2.21).

All three experts confirmed `git status --porcelain` unchanged; the baseline suite is
74/74 green and `check-rule-sync.sh` exits 0.

## Convergence and merge

Four findings were raised independently by two or three experts. Per "Perspective
Convergence as a Severity Signal" the merged severity takes the highest reported floor,
not the merger's summary:

| Merged subject | Raised by | Merged severity |
|---|---|---|
| The heal emits nothing usable on three separate branches | F1, F2 (Func) · S1 (Sec) · T3 (Test) | **Critical** |
| C7's GitHub pre-filter demotion is not real | F3, F4 (Func) · S4 (Sec) · T8 (Test) | Major |
| C2's acceptance values are numerically wrong | F10 (Func) · T1 (Test) | Major |
| Emission-side range: `todate` exceeds `_is_iso` | F5, F6 (Func) · S11 (Sec) | Major |
| C8's grep is wrong and fails open on a missing subject | F8 (Func) · S9 (Sec) · T13 (Test) | Major |
| R42: the primitive has members outside the plan's set | F11 (Func) · S7 (Sec) | Major (floor from S7) |
| Control class mislabelled `fail-closed` | F12 (Func) · S8 (Sec) | Major (floor from S8) |
| F-R6's transcripts clause falsified on stdout | F9 (Func) · S3 (Sec) | Major |

## Critical Findings

### CR-1 — The heal produces no usable cursor on any of three branches (F1, F2, S1, T3)

Four independent reproductions of one root cause: **the healed value never reaches the
state file, and where it does, it heals in the forbidden direction.**

**(a) F1 — clamp-to-now converts a corrupted cursor into "nothing matched".** After
clamping a future cursor to `now`, every existing file has `mtime ≤ now` and is therefore
suppressed. The emitted cursor is `now`, `mark-run` accepts it, and the backlog between the
last genuine cursor and the heal instant is lost permanently — mtimes do not move and the
cursor never moves back. Reproduced across two consecutive runs with two week-old artifacts
present throughout; after run 1 there is **no diagnostic on any channel**. This inverts
F-R3 and it contradicts this repository's own recovery policy, `pipeline.md:134-137`:

> The minimum is the only value that is safe in the recovery direction — it re-mines
> already-seen artifacts …, which costs sub-agent tokens, rather than dropping unseen ones,
> which loses the lesson.

**(b) F2 — the transcripts heal lands on the deferred branch, which C6 excluded.** Removing
`-newer` means the poisoned-cursor case no longer reaches the empty-file-set early return
that C6 fixes: `find` returns every `*.jsonl`, all are suppressed, and control falls through
to the Stage-2 gate, which emits `high_water: null` unconditionally. Reproduced on a scratch
copy carrying C6's enumeration change. The contract that reasoned about this branch got it
backwards.

**(c) S1 — a `continue` between the clamp and the emission deletes the cursor.**
`hw_map` is written at `retro-prescreen.sh:404`; the clamp is at `:325`; `[ -d "$glob_dir" ]
|| continue` sits at `:330` between them. `retro-state.sh:346` writes
`.sources[$s].high_water = $hw` as a **whole-object replacement**, so an omitted repo key is
*deleted*, not left stale. A repo whose archive directory is momentarily absent is warned
about, dropped, reset to 1970, and re-mines its entire archive next run — re-sending the
full corpus of internal review documents through the LLM path when `allow_remote_llm` is on.

**(d) T3 — the branch has no test.** The one branch whose failure mode is "permanently blind
while reporting success" is fixed with no acceptance case; TC6 covers the non-empty path only.

**Disposition — accepted, with a design change and a widened unit.** The plan is revised so
that (i) a cursor ahead of the present resets to **epoch 0**, not to `now`; (ii) the emitted
high-water is a function of the heal, never of the branch, and is seeded before any
`continue`; (iii) `pipeline.md` writes the high-water file on the deferred path too, which is
newly safe because the healed value is ≤ the persisted one by construction. Acceptance cases
added for each branch.

## Major Findings

### MJ-1 — C7's demotion of the GitHub `updated:>=` pre-filter is not real (F3, F4, S4, T8)
"Exhaustive over whatever the API returns" is a tautology and is the same justification
rounds 1–3 used for `find -newer`. A PR the query excludes is never adjudicated. Composed
with the clamp, a poisoned cursor regenerates the query as `updated:>=<now>` and the backlog
is skipped server-side, unrecoverably — there is no local corpus to re-enumerate. C7 also has
**no consumer-flow walkthrough at all** and never states whether `high_water` is emitted as an
epoch or an ISO string; a bare epoch fails `_validate_hw` and freezes the source forever.
Three of its four invariants have no test, and the `gh` stub ignores `--search` entirely, so
the one acceptance case that exists cannot fail for the reason it claims.

**Disposition — accepted; the recommended remedies diverged and were resolved by execution.**
Security proposed dropping the qualifier; `gh pr list` has no `--sort` flag, so dropping it
also drops `sort:updated-asc` and a repo with more than `--limit` merged PRs since the cursor
gets a permanent middle gap. The qualifier is kept, widened by a declared `LAG_MARGIN`, built
from the healed cursor (which after CR-1 can only widen the query), and the control class is
restated as a pre-filter that *does* decide, with its incompleteness modes named.

### MJ-2 — C2's acceptance values are numerically wrong (F10, T1)
Measured: `"2026-07-14T16:44:06Z" | fromdate` → `1784047446`; `1785501296 | todate` →
`2026-07-31T12:34:56Z`. The plan crossed the two. These are the locked criteria for the codec
the whole replacement rests on. **Accepted** — corrected, with the executed command recorded
next to each row, and the round-trip asserted in both directions against literals rather than
as `f(g(x)) == x`.

### MJ-3 — Emission-side range and the unarmed second bound (F5, F6, S11)
`jq todate` emits 5- and 7-digit years; `_is_iso` anchors on `^[0-9]{4}`, and `_validate_hw`
rejects the **entire** `high_water` object on one bad value. C4's stated reason for having no
emission-side clamp — that the loop's own future-mtime check bounds the running maximum — is
false in exactly the branch where `now_epoch` is empty, since that check does not run.
**Accepted**: when the clock is unreadable the running maximum does not advance past the
persisted cursor; `_epoch_to_iso` validates its output against `_is_iso`'s own regex; a failed
conversion re-emits the persisted value rather than an empty string or a dropped key.

### MJ-4 — C8's forbidden-pattern grep is wrong and fails open (F8, S9, T13)
`date -[ud][[:space:]]` matches `date -u +%s`, which C3 requires — the gate can never pass.
Separately, grep returns 2 for a missing subject and the idiomatic `if ! grep -q … 2>/dev/null`
reports PASS over a file that does not exist; the gate has zero callers in `bats tests/`, the
only gate this repo runs, while VC2 makes it the *entire* mitigation for the bash-3.2 floor.
**Accepted**: the pattern is narrowed to the parsing forms, and the gate becomes a bats case
asserting both the absence of each forbidden pattern **and** the presence of a control token,
with a deny-side proof against a scratch copy carrying `-newer` reinserted.

### MJ-5 — `"${excerpts[@]}"` violates N-R1 and the empty case becomes the steady state (F7)
`retro-prescreen.sh:762` expands a possibly-empty array unguarded. Today a nothing-new run
exits at the `[ "${#files[@]}" -eq 0 ]` early return and never reaches it; after the
enumeration change, every transcript is returned, all are suppressed, and control reaches
line 762 on the **most common path on a healthy system**. On stock macOS this aborts with no
JSON. **Accepted**: `${excerpts[@]+"${excerpts[@]}"}` (the idiom `retro-state.sh:211` already
uses), plus a forbidden pattern for a bare `"${name[@]}"`.

### MJ-6 — C2 pins the codec's mechanism but not its argument passing (S6)
Executed differential: `jq -nr "\"$iso\" | fromdate"` satisfies **every** stated C2 acceptance
criterion while letting the operand choose its own epoch (`'x" | 4102444800 # '` → 4102444800)
and read the process environment (`'x" | (env.FAKE_TOKEN|length) # '` → 20). The plan does not
force the safe implementation and Phase 3 has no criterion to reject the unsafe one.
**Accepted**: `--arg`/`--argjson` mandated, the jq program required to be a fixed
single-quoted literal, and the injection payload added as the acceptance case that separates
the two implementations.

### MJ-7 — F-R6's transcripts clause is falsified on stdout (F9, S3)
The deferred document emits the session basename as `candidates[].file` on the machine-consumed
stream. C6 rewrites that exact call site (`basename` → `${f##*/}`) as a performance edit
without noticing the value is emitted. The existing canary cases assert content redaction, not
identity redaction, so F-R6's "pinned by the existing green canary cases" claim is not
load-bearing for the clause it is cited for.
**Accepted with the stronger of the two offered remedies.** A repo-wide grep for `event_count`
finds exactly two hits — the producer and one test assertion on the *counts*. The `file` key
has **no consumer at all**, so it is replaced by an opaque per-run index: the implementation is
made to match the requirement rather than the requirement weakened, at zero cost to the only
thing that reads the shape (the human run report, which needs cardinality and counts).

### MJ-8 — R42: the defining primitive has members outside the plan's set (F11, S7)
Two independent derivations, two different primitives, one conclusion — the plan drew its
member set at a file boundary rather than at the primitive.
- *`stat -c %Y … || stat -f %m …`*: four members, not three. `hooks/llm-utils.sh:94` carries
  the exact single-command-substitution shape C1's first invariant forbids, plus the `echo 0`
  spelling audit defect (3) names — and `retro-prescreen.sh` **sources that file into its own
  process**.
- *a persisted timestamp compared against the present to decide whether work happens*: two more
  members in `retro-state.sh` (`last_run`, `snoozed_until`), neither clamped. The `due`
  comprehension's `try/catch` arms handle *malformed* values; a *well-formed future* value is
  not caught, and its effect is strictly quieter than the class the plan fixes — the source is
  never invoked at all, so there is no clamp, no warning, and no candidate document.

Both experts independently confirmed the plan's three-member clamp set **within the hook is
correct and complete** — C7 is the member Round 2 missed.
**Accepted, split by reachability.** C1 is widened to `llm-utils.sh:94` (two lines, and it
removes the `echo 0`). `last_run`/`snoozed_until` become **SC5** with an Anti-Deferral
justification: they are written from the real clock at write time, whereas `high_water` is
derived from file mtimes in untrusted sibling repositories — a restored backup or an extracted
archive poisons the latter without touching the former, so the two members differ in
reachability, not merely in cost. F-R4's universal wording is narrowed to match what is fixed.

### MJ-9 — Control class mislabelled `fail-closed` on C1/C2/C3 (F12, S8)
R49 defines a fail-closed gate as one whose unresolved case **denies**; F-R3 requires the
unresolved case to **admit**. C4 already declares its degraded arm honestly as
`detection or audit only`, and the plan calls that "what makes it honest rather than an
overstated control". C1/C2/C3 assert the stronger label for the same shape — and F5 shows the
practical cost: C4 removed the emission-side clamp partly because C3 was believed fail-closed.
**Accepted**: each declaration is split into the fail-closed *validator* and the deliberately
fail-open *policy* it feeds.

### MJ-10 — `_resolve_contained`'s control-character rejection leaks an absolute path (S2)
`retro-prescreen.sh:63` prints `$dir`, always absolute under `${repo/#\~/$HOME}`, triggered by
a filename inside an **untrusted** sibling repository. C5's physical-root-strip remedy is
specified for two warnings and this is a third; C9 marks the function prose-only, so nothing in
the plan reaches the line. **Accepted**: F-R6 becomes an enumeration obligation — every
path-printing diagnostic in the artifacts path routes through one repo-relative helper — and
the plan lists them rather than naming two.

### MJ-11 — `RETRO_PRESCREEN_NOW` silently disables the control it parameterizes (S5)
Executed: with the seam set to `99999999999` the clamp is vacuous and a year-2446 cursor is
persisted with **no announcement whatsoever** — less diagnostic output than the failure the
plan does announce, and the value passes `_is_iso` so `mark-run` accepts it. This is the R50
clause (ii) obligation this repository folded one commit before this branch, turned on the
plan's own seam. **Accepted**: the seam announces itself on stderr on every run in which it is
set (an epoch integer carries no identity), and the boundary cases are pinned.

### MJ-12 — Six contracts have acceptance criteria and no acceptance case (T2)
C1, C2, C3, C4, C8, C10 state acceptance in unit-test form; TC1–TC11 covers none. C3 states no
acceptance at all. The Go/No-Go rows for those contracts would flip on a manual read-through.
Constructibility was verified rather than assumed: `run bash -c 'source "$SCRIPT" scrub
</dev/null; …'` exposes the helpers with `set -u` and the dispatch confined to a subshell.
**Accepted**: a `helpers` unit group is added and C3 gains an acceptance section.

### MJ-13 — TC6 cannot be built on its case's mock (T4)
The case it strengthens uses `setup_curl_fail_mock`, which forces the deferred branch, whose
emitter is unconditional. The assertion would become `.high_water == null` — the branch's
constant, which cannot distinguish a healed cursor from an unhealed one. **Accepted**, and the
resolution folds into CR-1: TC6 splits into a deferred-branch heal case (curl-fail mock, now
meaningful because the deferred branch emits the healed value) and a non-deferred heal case
(loopback mock), with `RETRO_PRESCREEN_NOW` pinned so both expected values are exact.

### MJ-14 — TC2's "both orderings" axis is unspecified and the obvious reading is a no-op (T6)
Executed on ext4: `find`'s traversal order is a function of the filename and invariant under
creation sequence, so a creation-order fixture produces the same traversal twice and both runs
pass vacuously. The working axis is **which filename carries the later mtime**, proved by
emulating the C5 loop against the mutant: ordering A gives no delta, ordering B reds
(1784047560 → 1784047500). **Accepted**: the axis is written into the contract, the executed
delta is recorded as the RT7 (g)(ii) evidence, and the plan states that *which* of the two
assertions reds is platform-dependent so both are required.

### MJ-15 — TC3 does not carry TC2's order symmetry (T5)
`cmd_transcripts` has the identical `max_hw` shape and the identical readdir dependency; TC3
was specified only to have cardinality 2. Fixing the artifacts case and not its twin in the
same fold is the R3 propagation shape this change exists to close. **Accepted**.

### MJ-16 — C4's integer-comparison invariant is undiscriminated by every fixture (T7)
Every clamp fixture uses ten-digit epochs, where lexicographic and numeric comparison agree.
Executed: `[[ "999999999" > "1784047446" ]]` is **true**, `[ 999999999 -gt 1784047446 ]` is
**false**. A `>` implementation would declare any pre-2001 cursor "past the present" and heal
it — the forbidden direction produced by the healing mechanism itself, with nothing going red.
**Accepted**: the nine-digit boundary case is added; it is the single mutation separating the
two implementations.

### MJ-17 — The read-in clamp is covered on its deny side only (T12)
All three deny fixtures sit 74 years from the boundary and there is no case anywhere in which a
cursor is at or just below the present and the heal must **not** fire. The candidate-mtime
clamp has its boundary pair; the read-in clamp — the sole adjudicator — does not. **Accepted**:
`cursor == now` (no heal, cursor advances normally) and `cursor == now + 1` (heal) added.

### MJ-18 — TC8 asserts only an absence (T11)
A negative assertion over `$ERR` is satisfied by a run in which the diagnostic never fires.
C5's guard has two arms and TC8 pins neither. **Accepted**: TC8 asserts the diagnostic is
present, the physical root is absent, and the emitted form is the basename; the RT10 allow case
asserting the **repo-relative** form on a non-symlinked root is added, without which
"fails closed to the basename" is indistinguishable from "always emits the basename".

### MJ-19 — RT7 shape (g) is a policy sentence, not a per-row commitment (T10)
No mutation is named for any TC. Worked through: TC4 and TC5 **collide** on the single natural
mutation (removing the 5-minute rule's operand validation reds both); C1 spans three consumers,
C5's stderr guard two arms, C4 two arms — each needing N mutations; TC7–TC11 name none.
**Accepted**: the C11 table gains *mutation* / *expected red assertion* / *expected delta*
columns, the TC4/TC5 mutants are split, and hygiene-only rows are marked
`no red-proof — hygiene` so the absence is declared rather than assumed.

### MJ-20 — C7's three remaining invariants have no acceptance case (T8)
Covered above under MJ-1; all three were verified constructible with the existing `gh` stub
plus a two-line argv-recording change.

### MJ-21 — The date-only cursor is a live persisted value (F14, T9)
`_is_iso` accepts `YYYY-MM-DD` and `_norm_iso` runs only in `cmd_seed`, not on the
`mark-run --high-water-file` path the pipeline uses. Executed: `mark-run` accepts and stores
`"2026-07-31"` unnormalized. Under the new codec it yields empty → epoch 0 → a full re-mine.
**Accepted**: `_iso_to_epoch` applies the date-only expansion before handing the string to jq,
so the codec accepts exactly the language `_is_iso` defines — the property C2 claimed but did
not have — with an end-to-end case pinning the direction.

## Minor Findings

- **MN-1 (F13, T14)** — `_validate_high_water` does not exist; the function is `_validate_hw`
  (`retro-state.sh:154`). C10's acceptance commands have no file operand and one reads a gate
  **through a pipe**, which the plan's own Testing strategy forbids two lines earlier
  (executed: `grep <absent-token> file | head -1` → pipeline rc=0). **Accepted**, both made
  runnable and read by their own status.
- **MN-2 (S10)** — C9 names the residual's window and principals but not its **sink**. The two
  consumers of the resolved name are a raw-bytes LLM send (subject to the egress gate and
  `allow_remote_llm`, i.e. off-machine) and a sub-agent Read whose output reaches a pull
  request. The Out-of-scope line removes both halves of that composition in one sentence.
  **Accepted**: C9 names the sink; the Out-of-scope entry is qualified to the gate's
  *implementation*, not its composition.
- **MN-3 (T15)** — TC10 verified sound by execution (`rm -rf` reclaims a mode-000 file inside a
  writable directory). But the `export TMPDIR` line in `setup()` stays load-bearing via
  `llm-utils.sh:51`, while its comment justifies it solely by the `mktemp` C8 deletes — a
  future reader following C10's own principle deletes the line and the subject's scratch dirs
  return to shared system temp. **Accepted**: the comment is rewritten to cite the surviving
  consumer. Also recorded: `setup()` clobbers bats' native `BATS_TEST_TMPDIR` with a
  system-temp `mktemp -d`, pre-existing and untouched here — noted as a residual.
- **MN-4 (T16)** — Test *names* and the allow-side TZ rationale describe machinery C8 deletes,
  and the name is what a reader sees when a case fails. TZ ceases to be a discriminating axis
  once `date -u +%s` and jq are the only date paths. TC11 also bundles three unrelated edits
  under one ID. **Accepted**: names and both TZ rationales updated, TC11 split into a/b/c, and
  the TZ axis's retirement declared with its reason.

## Adjacent Findings

- F3 → Testing: the `gh` stub ignores `--search`, so C7's acceptance cannot fail for the reason
  it claims. Converged with T8; resolved together.
- F9 → Security: whether the session UUID belongs on stdout at all is a privacy-boundary
  judgement. Converged with S3; resolved by removing the key.
- F15, F16 → Testing: the vacuous `gh` stub and the untested F2/F7 branches. Converged with
  T8/T3.
- T1, T7, T9 → Functionality: codec values, the integer-comparison predicate, and the date-only
  cursor. Converged with F10/F14 and accepted.
- T11 → Security: TC8's assertion direction versus F-R6. Converged with S2.
- R51 → Security (Testing marked N/A for its own scope): C9's residual. Handled at MN-2.

## Quality Warnings

None. Every finding carried either an executed reproduction or a cited file:line, and the two
cases where an expert's *recommendation* rested on an unverified premise were resolved by
execution before acceptance:

- Security's MJ-1 remedy (a) — "drop the `updated:>=` qualifier" — assumed `gh pr list` could
  still order ascending. `gh pr list --help` has no `--sort` flag; the ordering comes from the
  `--search` string being dropped. Remedy (b) adopted instead.
- Functionality's CR-1(b) remedy — "the deferred path emits `min(persisted, now)`" — is
  necessary but not sufficient: `pipeline.md:70-72` and `:189` run `mark-run <source>`
  **without** a high-water file on the deferred path, so the emitted value is discarded. The
  accepted disposition extends to `pipeline.md`.

## Rejected / deferred findings

None rejected. Two accepted with a narrower scope than recommended:

- **MJ-8** — `last_run` / `snoozed_until` are declared as **SC5** rather than fixed, on a
  reachability argument the reviewer did not make (they are written from the real clock;
  `high_water` is derived from untrusted sibling-repo mtimes). Recorded as an Anti-Deferral
  entry, not as a silent omission.
- **MN-3(3)** — `setup()`'s `BATS_TEST_TMPDIR` clobbering is pre-existing, affects all 74 cases
  equally, and leaks only when bats is killed rather than failing. Recorded as a declared
  residual under R34 rather than fixed inside a cursor-machinery change.

## Recurring Issue Check

### Functionality expert
- R1: Checked — C1/C2/C3 centralize the mtime, codec and clock primitives; one reimplementation found → F11
- R2: Checked — the `1970-01-01T00:00:00Z` default is respelled at three call sites and collapses to a single epoch-0 constant under C2/C5/C6; the `300` freshness constant appears once. No finding
- R3: Finding F1 / F2 / F3 / F7 — each is one class member left open after the sibling was closed
- R4: N/A — no event or notification dispatch in this hook
- R5: N/A — no transactional store; the state write is `mktemp`+`mv` in `retro-state.sh`, untouched by this plan
- R6: N/A — no cascade-delete semantics
- R7: N/A — no E2E selectors
- R8: N/A — no UI
- R9: N/A — no fire-and-forget work inside a transaction boundary
- R10: Checked — `retro-prescreen.sh` sources `llm-utils.sh` only, and `retro-state.sh` is invoked as a subprocess; no cycle introduced or present
- R11: N/A — no subscription groups
- R12: Checked — the mode dispatch (`artifacts|github|transcripts|scout|scrub`) and `KNOWN_SOURCES` are unchanged; every mode still reaches a `cmd_*`
- R13: N/A — no re-entrant dispatch
- R14: N/A — no DB roles
- R15: N/A — no migrations
- R16: Checked — VC1/VC2 declare the BSD and bash-3.2 gaps honestly; no CI exists in this repo, so no parity drift to find beyond those
- R17: Finding F11 — the mtime helper is adopted at three of four derived sites
- R18: Checked — no new config key; the `KNOWN_SOURCES` closed set and `_validate_hw`'s per-source arms are untouched
- R19: Finding F15 (adjacent) — the `gh` stub does not model the `--search` argument the contract now depends on
- R20: Checked — C8's deletions remove whole functions; the `done < <( … )` compound in both loops folds five statements (ref build, warn, `mapfile`, `find`, `rm -rf`) into one `find`, and each removed statement exists only to serve the deleted pre-filter
- R21: N/A — plan phase; no sub-agent completion claims to verify
- R22: Checked — C4 keeps the clamp at read-in only, consistent with the established R48 placement; the related gap is the *unarmed* second bound → Finding F5
- R23: N/A — no interactive input
- R24: N/A — no migrations
- R25: Finding F6 — the ISO→epoch hydrate has a contract (C2), the epoch→ISO dehydrate at emission does not
- R26: N/A — no disabled-state UI
- R27: Checked — the 300 s constant and the "5-minute" prose both survive unchanged; not introduced or widened by this plan
- R28: N/A — no toggle labels
- R29: Finding F10 (jq round-trip values) and Finding F13 (`_validate_high_water` does not exist)
- R30: Checked — the plan doc contains no bare autolinks or angle-bracket URLs
- R31: Checked — the only destructive operation in scope (`rm -rf "$dir"` in `_mtime_ref_file`) disappears with the function; nothing destructive is added
- R32: N/A — no long-running runtime artifact
- R33: N/A — no CI configuration in this repo
- R34: Finding F11 — no Anti-Deferral cost-justification for the fourth mtime site; SC1/SC2/SC3 are properly cost-justified
- R35: Checked — the plan carries five user operation scenarios; scenario 2 is falsified by execution → Finding F1
- R36: Checked — no new suppression; the existing `# shellcheck source=` directives are unchanged
- R37: Checked — stderr strings ("cursor … is past the present — clamped to …", "cannot read mtime of …") name the observation and the action in operator terms
- R38: N/A — no async state machine
- R39: N/A — no secret material with a lifecycle
- R40: Finding F6 (`todate`'s range exceeds `_is_iso`'s `^[0-9]{4}` — measured) and Finding F9 (the deferred document's shape versus F-R6's stated contract)
- R41: Finding F3 — "the local epoch comparison is the authority" is a declared capability with no backing path for anything the server excluded
- R42: Finding F11 — member set derived from the primitive over `hooks/`: four for the mtime read (plan says three), four `_state_high_water` call sites of which three are clamp-eligible (scout derived and excluded, reason recorded)
- R43: Checked — the change narrows the attack surface (removes `mktemp`/`touch -t`/`date -j` and their temp-dir framing); the widening found is behavioural rather than security-boundary, and is Finding F2's branch relocation
- R44: Checked — the plan's Testing strategy explicitly requires each gate's own exit status, never through a pipe; the instance found is at the consumer, where `pipeline.md` never reads `mark-run`'s status → folded into Finding F6
- R45: Checked — N-R2 measured at 2.01 s / 1161 files; I re-measured 1.33 s / 1164 files on the same corpus. Claim stands, no finding
- R46: N/A — no scope-sensitive analyzer
- R47: Finding F3 — sub-clause (c): the surviving GitHub pre-filter decides rather than narrows
- R48: Checked — C4 correctly keeps one adjudicator at read-in rather than adding a second; the defect is that its stated substitute bound is not always armed → Finding F5
- R49: Finding F3 (control class stronger than achievable), Finding F9 (a privacy claim falsified by the shipped document), Finding F12 (C3's class contradicts its own failure mode)
- R50: Finding F1 — clause (ii), reproduced: a blind source and a drained source produce byte-identical machine output, and after the heal run there is no diagnostic on any channel. Finding F15 (adjacent) is clause (iii)
- R51: Checked — C9 restates `_resolve_contained`'s residual as an open residual with its window named, and correctly refuses to assign the re-establishment obligation to a sub-agent whose tool set (Read/Grep/Glob, per `skills/retrospect/sources/artifacts.md`) cannot discharge it. SC2 declares the handle-carrying closure as out of scope with an owner. No finding

### Security expert
- R1: N/A — no shared-utility reimplementation; the plan *consolidates* three date paths into one codec (C2) and three `stat` sites into one primitive (C1), which is the correct direction
- R2: Checked — the `300` freshness constant, the `1970-01-01T00:00:00Z` cursor floor and the 40-hop symlink cap each appear once; the epoch rewrite does not duplicate any of them. The 253402300799 boundary in S11 is a constant the plan *should* name, flagged there
- R3: Finding S7 (the poisoned-timestamp pattern exists in `retro-state.sh` and is not propagated) and S2 (C5's phys-root-strip remedy applied to 2 of 3 path-printing diagnostics). C6's own R3 citation for the "clamp disabled" warning is correct
- R4: N/A — no event/notification dispatch in this change
- R5: N/A — no transactions. The state write is a whole-file replacement, addressed under S1 rather than as a transaction concern
- R6: N/A — no cascade delete. The cursor-key deletion in S1 is an orphaning of a different kind and is reported there
- R7: N/A — no E2E selectors
- R8: N/A — no UI
- R9: N/A — no fire-and-forget work
- R10: N/A — single-file shell hook, no module graph
- R11: N/A — no display/subscription groups
- R12: Checked — the dispatch `case` in `hooks/retro-prescreen.sh:859-879` covers all five modes and the plan adds none; `_known_source` in `retro-state.sh` is the matching enumeration and is unchanged
- R13: N/A — no re-entrant dispatch
- R14: N/A — no DB roles
- R15: N/A — no migrations
- R16: Checked — VC1/VC2 declare the macOS/bash-3.2 environments as unreachable with structural mitigation rather than assumed parity; the pre-screen already corrected the bash-3.2 status claim. I re-ran the arithmetic claim on 5.2.21 (`n=100; f=not-a-number; echo $((n-f))` → aborts, rc=127; `n=; f=5` → `-5`, rc=0) and both halves of C6's stated evidence hold as scoped
- R17: Checked — C1 correctly names all three `stat` consumers as adopters of the single primitive, including the 5-minute freshness rule Round 2 missed
- R18: Checked — C8's forbidden-pattern list is the union of C2's and C5's entries, verified by reading all three; no entry is declared in one place and omitted from the gate
- R19: N/A — no mocks change shape; the `gh` stub and curl mocks are untouched by TC1-TC11
- R20: Checked — C8's deletions are whole functions plus their two `mapfile` call sites; no multi-statement line is being edited in place
- R21: N/A — no delegated work in this plan
- R22: N/A
- R23: N/A — no UI input
- R24: N/A — no migrations
- R25: N/A — no persist/hydrate pair beyond the cursor, covered by S1/S7
- R26: N/A — no UI
- R27: Checked — the "2.01 s / 1161 files" and "under one second" figures appear once each, in the plan; no user-facing string re-spells a numeric range
- R28: N/A
- R29: Checked — the plan's citations resolve: `hooks/check-rule-sync.sh:103`, `hooks/check-input-validation.sh:726` and `tests/retro-prescreen.bats:70` for the bash-3.2 floor, `skills/retrospect/pipeline.md:122` for the frontmatter scalar shape, and `_is_iso`'s regex as quoted in C5's Consumer-2 walkthrough all match the tree
- R30: N/A — no autolinks
- R31: Checked — nothing destructive; C8's deletions are source removals, and TC10's dropped `chmod 644` is a teardown simplification whose reclamation path (`rm -rf` inside a writable dir) I confirmed is sound
- R32: N/A — no long-running runtime artifact
- R33: N/A — no CI configuration
- R34: Checked — SC1's Anti-Deferral cost-justification is present and specific (names `_is_iso`/`_norm_iso`, the frontmatter shape, six `retro-state.bats` cases, the sub-second `stat` surface). S7 asks for the same treatment for the deferral it implies but does not declare; SC2 and SC3 carry theirs
- R35: N/A — `config-only`; per the brief I am not raising process/CI gaps
- R36: N/A — no warning suppression. The `2>/dev/null` on jq in C2 is output-suppression with an explicit output-validation replacement, which is the correct shape
- R37: Checked — stderr diagnostics use domain wording ("cursor", "clamped", "suppressed"), no internal jargon leaks
- R38: Checked — the deferred/early-return/heal branches in C6 are explicitly separated, and the defer correctly stays non-terminal by emitting `high_water: null`
- R39: N/A — no secrets held in the changed paths. S10 names a path by which secret *content* could transit, reported there
- R40: Checked — N-R1's `while IFS= read -r -d ''` / `-print0` contract preserves filenames containing newlines across the enumeration boundary; the `@base64`-per-comment framing in `cmd_github` is untouched and remains correct
- R41: N/A — no newly declared capability without a backing path
- R42: Finding S7. Derived independently: `_state_high_water` has four call sites (artifacts 323, github 472, transcripts 601, scout 805); scout is a hash cursor with no temporal comparison, so the plan's three-member clamp set **within the hook is correct and complete**. The primitive-level derivation adds `last_run` and `snoozed_until` in `retro-state.sh`
- R43: Checked — this is the change the "replace the mechanism rather than the Nth patch" lesson prescribes, and the plan applies it correctly for the local pre-filter. S4 is where the same disposition is not applied to the remote one
- R44: Checked — the Testing-strategy section requires each gate be run for its own exit status and never through a pipe, and C8's grep output be recorded. S9 is the complementary gap (the status is read correctly but proves nothing about the subject)
- R45: Checked — N-R2 bounds enumeration cost with a measured figure (2.01 s / 1161 files) and R-1 records the regression baseline. The transcripts scan is linear in file count; no super-linear path introduced. Egress volume is the unbounded axis and is raised under S1
- R46: N/A — no code analyzer
- R47: Finding S4 (sub-clause (c) on the GitHub server-side filter). Sub-clause (a) is satisfied for the local path — the plan deletes `find -newer` outright rather than approximating it. `_resolve_contained`'s per-component physical resolution already sits at the top of the authority ladder; R51's interval is the remaining gap, covered by S10
- R48: Findings S8 (control class vs actual fail direction) and S11 (strict-direction sub-clause: `_is_iso` stricter than `todate` on a fail-closed write). C4's "one adjudicator, no emission-side clamp" is the correct R48 disposition in the normal arm; S5 shows the justification fails in the degraded arm
- R49: Findings S2, S3, S4, S8, S10 — five claims stronger than the implementation (F-R6 for artifacts stderr; F-R6 for transcripts stdout; C7's named recovery path; C1/C2/C3's control class; C9's residual blast radius). C4's degraded-arm declaration and C8's "not an enforceable boundary" note are both correctly calibrated and are the model the others should follow
- R50: Findings S5 (clause (ii): a scope-affecting env override not asserted unset in the authoritative run) and S9 (clause (ii): a gate with no analysed-subject evidence). Clause (iii) is satisfied — the plan runs `install.sh` last and notes the installed tree is behind `main`
- R51: Finding S10. C9's tool-set argument verified true against `skills/retrospect/sources/artifacts.md` on this branch (Read/Grep/Glob only, no repo root among the declared inputs); the restatement is honest, the blast radius is not fully stated. SC2 correctly records that closing it needs a descriptor the shell cannot carry
- RS1: N/A — no secret comparison
- RS2: N/A — no request-serving routes. The `--limit 200` cap and the 40-hop symlink cap are the two bounded loops and both are present
- RS3: Finding S6. Also checked: `gh pr list --search` receives `_epoch_to_iso`'s output as a **single argv element**, so there is no shell-injection surface there (the concern is the query semantics, S4, and the codec's own argument passing, S6). `--arg`/`-R`/`--argjson` framing is preserved everywhere else the plan touches
- RS4: Checked — the plan document itself carries no usernames, absolute paths or repository identities, consistent with the audit doc's own convention of referring to sibling repos by thread. S2 is the path by which a `$HOME`-carrying string could reach such an artifact via pasted stderr
- RS5: Checked — `RETRO_PRESCREEN_NOW` is an externally-supplied parameter governing a security-relevant control with a numeric-only check and **no floor, ceiling or whitelist**; a value of `99999999999` is accepted and makes the clamp vacuous. Reported under S5 with the R50(ii) framing (announcement) rather than duplicated here, but the RS5 remedy — bound it to a sane range, or accept only when a test marker is also present — is the alternative fix
- RS6: Checked — `cmd_scrub`'s ordered passes (length cap → email → IPv4 → IPv6 → `/home/` → AWS → tilde → generic secret) are untouched by this plan, and the ordering rationale is documented inline at each step

### Testing expert
- R1: Checked — the plan removes the test-side `find` reimplementation (TC2) that duplicated production enumeration; C1 consolidates three `stat` call sites into one primitive. No new duplication introduced
- R2: Checked — `1784047446` is the suite's shared mtime constant and `iso_at`/`set_mtime_frac` are single-definition helpers; the plan's new TCs reuse them. But see T1: C2 spells a *different* constant, wrongly
- R3: Finding T5, T8 — the artifacts fix (TC2) is not propagated to the transcripts twin (TC3); C7's four invariants get one TC while C5/C6 get several
- R4: N/A — no event/notification dispatch in this hook
- R5: N/A — no transactions; state writes go through `retro-state.sh`'s own atomic `mktemp`+`mv`
- R6: N/A — no cascade deletes
- R7: N/A — no E2E selectors
- R8: N/A — no UI
- R9: N/A — no fire-and-forget work
- R10: N/A — flat shell sourcing (`llm-utils.sh` only), no cycles
- R11: N/A — no display/subscription grouping
- R12: Checked — the four sources (artifacts/github/transcripts/scout) are the enum; scout is out of scope by declaration and the other three each get a contract (C5/C6/C7)
- R13: N/A — no dispatch loop
- R14: N/A — no DB roles
- R15: N/A — no migrations
- R16: Checked — VC1/VC2 declare the environment gaps (macOS/BSD, bash 3.2) as `blocked-deferred` with mitigations; the mitigation for VC2 is the C8 grep, which is where T13 lands
- R17: Checked — C1/C2/C3 are the new shared helpers and C5/C6/C7 each declare adoption; T2 notes none has its own acceptance case
- R18: N/A — no allowlist/safelist synchronization in this change
- R19: Checked — the `gh` stub and `curl` mocks stay shape-compatible with the change; T8 recommends extending the `gh` stub to record argv, which is an additive change to the mock
- R20: Checked — TC1 is a whole-case deletion, TC9-TC11 are single-statement edits; no multi-statement mechanical rewrite at risk
- R21: N/A — no subagent delegation inside this plan's verification
- R22: Checked — the plan replaces the mechanism rather than adding a fourth guard, which is the correct perspective inversion for the established helper
- R23: N/A — no UI input
- R24: N/A — no migrations
- R25: Checked — cursor read-in / emission symmetry is the subject of C4/C6; T3 is the emission half with no test
- R26: N/A — no UI
- R27: Checked — the 5-minute (300 s) window and the 200-PR limit are not re-spelled in new user-facing strings by this plan
- R28: N/A — no toggle labels
- R29: N/A — no external spec citations
- R30: N/A — no markdown autolinks in the changed artifacts
- R31: Checked — the red-proof procedure is scoped to "a scratch copy outside the repository" with `git status --porcelain` re-checked after each proof (plan:417-418); no destructive product operation
- R32: N/A — no long-running runtime artifact
- R33: N/A — no CI configuration in this repo
- R34: Checked — SC1/SC2/SC3/SC4 each carry an Anti-Deferral cost justification and an owner; VC1/VC2 likewise
- R35: N/A — no production-deployed component; the plan's "User operation scenarios" section serves the equivalent role and is complete
- R36: Checked — no warning suppression; `2>/dev/null` uses are on jq/stat with the *output* validated instead (C1/C2), which is the correct direction
- R37: N/A — the stderr diagnostics are operator-facing by design and use domain vocabulary already present
- R38: N/A — no async state machine
- R39: N/A — no secret zeroization
- R40: Checked — NUL-framed `find -print0` consumption is pinned in N-R1 as the enumeration contract for C5/C6, with `mapfile` forbidden
- R41: Finding T13 — C8's grep is a declared capability (VC2's whole mitigation) with no working backing path in any gate this repo runs
- R42: Finding T2, T10 — C1's three-consumer member set is stated but not derived by a test; the RT7 (g) obligation generalizes from one mutant across N-arm guards
- R43: Checked — the change narrows rather than widens (deletes the pre-filter, one remaining BSD/GNU divergence); the github `--search` pre-filter is explicitly declared as demoted, and T8 asks for the test that makes the demotion observable
- R44: Finding T14 — C10's acceptance reads a gate through a pipe and conflates grep's count with its exit status
- R45: Checked — N-R2 measures full-enumeration cost (2.01 s / 1161 files) and R-1 records the growth risk with a baseline; this is the R45 obligation discharged
- R46: N/A — no analyzer binding resolution
- R47: Checked — the plan's core move is to stop adjudicating on the surface form (ISO strings, `-newer` reference files) and compare integers; C7 declares the one surviving surface-form pre-filter as unable to decide
- R48: Finding T7, T12 — C4 claims one adjudicator, but the "integer not string" predicate and the read-in-clamp boundary are both untested, so a second, stricter de-facto adjudicator (lexicographic `>`) could ship undetected
- R49: Checked — control classes are declared per contract, C8 explicitly declares "not an enforceable boundary", C4 declares the degraded `detection or audit only` class when `now` is empty, and C9 restates the residual as a residual. T11 is where an *assertion* would otherwise overstate what TC8 pins
- R50: Finding T13 (clause ii — no positive subject evidence for the C8 grep) and T14 (clause i/iv — status read through a pipe). Clause (v) is satisfied: red-proofs run on a scratch copy with `git status` re-checked. Clause (iii): the subject is the shipped hook. I verified the suite's own run isolation by confirming the repo tree is unchanged after my execution
- R51: N/A for testing scope — C9 restates it as an open residual; no test is claimed for it. [Adjacent] Security expert's scope
- RT1: Checked — the `gh`/`curl` mocks stand at genuine system boundaries (network, external CLI); `stat` and `touch` shadowing is PATH-level and does not mock the subject. No mock-reality divergence introduced by C11
- RT2: Checked — I verified constructibility before raising every finding. `source "$SCRIPT" scrub </dev/null` exposes the helpers (executed, rc=0), so T2's asks are real; the both-orderings and `999999999` fixtures are constructible with existing helpers (T6, T7 executed); the `gh` argv capture is a two-line stub change (T8). I withdrew nothing as impossible, but I explicitly did **not** ask for any bash 3.2 or BSD `stat` case — those are correctly `blocked-deferred` under VC1/VC2
- RT3: Checked — `iso_at`, `set_mtime_frac`, `fs_keeps_subsecond`, `write_config` are single-definition shared helpers and the new TCs reuse them; TC2/TC3 should reuse `set_mtime_frac` rather than re-spelling `touch -d`
- RT4: Finding T6 (executed: a creation-order "both orderings" fixture is a no-op on ext4, both runs vacuous) and T11 (TC8's absence-only assertion passes when the diagnostic never fires). Also checked positively: `fs_keeps_subsecond` is a real precondition assertion and the sub-second cases skip rather than pass vacuously
- RT5: Checked — TC2 removes the test-side `find` that reimplemented the production scan, so the traversal under test becomes production's own. Good direction
- RT6: Checked — C1/C2/C3 are three new helpers; T2 is the RT6 gap (new exports with no test driving them directly)
- RT7: Finding T10 (shape (g): no per-TC mutant named, TC4/TC5 collide, N-arm guards get one mutation), T13 (shape (b): authored-but-ungated C8 grep), T16 (shape (d): rationale prose about existing tests rewritten while the case's axis disappears). Shape (g)(ii) non-zero delta: produced for TC2 by execution (see T6)
- RT8: Finding T11 — TC8 asserts the denial by its weakest observable. Also checked positively: the existing suite pairs status with the suppressed effect in most cases (e.g. bats:584-590 asserts candidate count *and* the exact unchanged cursor)
- RT9: Checked — no parallel twin implementation; C8's deletions remove the only duplicated date-handling arms
- RT10: Finding T12 (read-in clamp deny-only, no boundary-adjacent allow on any of the three sources) and T11 (no allow case for the repo-relative diagnostic form). Checked positively: the *mtime* clamp does have its boundary pair (bats:596/615), and the suppression predicate has both sides (bats:398/450)
- RT11: Finding T15 — TC10 verified correct by execution (`rm -rf` reclaims mode-000); the `TMPDIR` line is still load-bearing via `llm-utils.sh:51` but its stated rationale dies with C8; `setup()` clobbers bats' native `BATS_TEST_TMPDIR` with a system-temp `mktemp -d`. No TC1–TC11 fixture can outlive its run
