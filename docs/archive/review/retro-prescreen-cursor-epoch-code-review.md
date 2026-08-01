# Code Review: retro-prescreen-cursor-epoch
Date: 2026-08-01
Review round: 1 (Phase 3)

## Changes from Previous Round

Initial code review, against `git diff main...HEAD` on `retro/prescreen-cursor-v2`
(base `origin/main` = 94c235e).

**Process note.** The first attempt launched three whole-diff reviewers; all three died
from context exhaustion after ~60 minutes, leaving 163-byte transcripts and no findings.
The review was re-run **file-scoped**: one reviewer per subject, each forbidden from
running the unscoped `git diff main...HEAD`, capped at ~300-line reads, and told to
`grep -n` first. All four completed.

| Reviewer | Subject | Findings |
|---|---|---|
| Functionality | `hooks/retro-prescreen.sh` | 10 (6 Major) |
| Security | `hooks/retro-prescreen.sh` | 10 (4 Major) |
| Testing | `tests/retro-prescreen.bats` | 17 (**2 Critical**, 8 Major) |
| Func+Sec | `llm-utils.sh`, `retro-state.sh`, `pipeline.md` | 9 (7 Major) |

**46 findings: 2 Critical, ~25 Major.** Seed analyzers returned `No findings` for
functionality and security and 4 Minor for testing; one testing seed was **rejected on
polarity** (it claimed inline comments hide constructs from the C8 gate; an inline `#` sits
on a code line, which the full-line strip *keeps*).

---

## The headline: the change's own thesis was violated in three places

This PR exists to close a class rather than patch its members. The review found the class
open in three more members, one of them inside the control built to close it:

1. **`cmd_scout` (Func F3)** — the third source in the same file still dropped cursor keys
   for failed fetches and emitted `{}`, which `_validate_hw` accepts trivially and the
   whole-object replacement then uses to wipe every persisted hash.
2. **The egress gate (Sec S1)** — `healed_any` was set by one of *three* causes that reset
   a cursor to the floor. The other two (an unparseable-but-`_is_iso`-valid persisted
   value; no state entry) reset the cursor **with egress still enabled**, shipping the
   whole corpus off-machine under `allow_remote_llm`. Member set taken from the plan's word
   "heal" instead of derived from "every cause that resets to the floor" — R42, inside the
   R42 remedy.
3. **The C8 conformance gate (Sec S9, Test T3/T4)** — the `clamp` row is a total no-op (its
   must-MATCH example is a full-line comment, exactly what the subject strip removes, so
   the example assertion and the subject assertion run on different subjects); the deny-side
   proof never runs the gate's loop; and the subject omits two files the same change edited.

## The second headline: the tests do not red-prove what the plan says they do

The testing reviewer executed **eight mutations; all eight were green.** Six are mutations
the plan's own C11 table names as RED-expected. Two were re-verified independently by the
orchestrator:

| Mutation | C11 declares | Measured |
|---|---|---|
| deferred emitter → hard-coded epoch 0 | TC6a(iii) red | **0 failures** |
| both transcripts degraded exits → `_json_empty` | TC6b/TC6d red | **0 failures** |
| transcripts `max_hw` → `cursor` | TC3a/b red | green |
| drop the transcripts `now_epoch` check | TC5 red | green |
| github map → whole-object replace | TC15 red | green |
| add a warning to `_iso_to_epoch`'s pre-1970 arm | TC11 red | green |
| neuter all three aggregate suppression diagnostics | (unlogged) | green |
| silence the deferred human branch | (unlogged) | green |

Root cause of the two Criticals: **`1970-01-01T00:00:00Z` is simultaneously the seeded
default, `_heal_cursor`'s floor, and a hard-coded epoch 0** — a three-way degenerate
oracle. The plan's own TC6a row anticipated this ("persisted **`2026-07-14T16:44:06Z`**
(non-default, so the three candidate emitters are mutually distinct)") and the implemented
cases used the default anyway.

The deviation log claimed four test gaps; the real set is at least twelve. TC3a/b, TC4,
TC5, TC6b, TC6d, TC15, TC19, TC20 are unimplemented with no entry.

---

## Findings

### Critical

**T1 — the transcripts deferred emitter's cursor is completely unpinned**
`tests/retro-prescreen.bats:1287`, `:1496`. Both assert
`.high_water == "1970-01-01T00:00:00Z"` with the persisted cursor at the seeded default.
Hard-coding `_epoch_to_iso 0` at `hooks/retro-prescreen.sh:1010` leaves the suite green.
The same degeneracy voids TC6e's allow half: with `persisted == floor`, "heal applied
unconditionally" and "no heal" are byte-identical.
*Fix*: seed both with `2026-07-14T16:44:06Z`, pin `RETRO_PRESCREEN_NOW` past it, assert
equality against that literal.

**T2 — TC6b and TC6d were never written; both transcripts degraded exits revert silently**
`tests/retro-prescreen.bats:1240` ("no root dir"), `:1251` ("no new sessions"). Both assert
only `.candidates == []`; neither asserts `.high_water`. Reverting both exits to
`_json_empty` leaves the suite green. The github twin (`:1831`) *is* covered — an R3 class
asymmetry introduced by the same commit.

### Major — implementation

| ID | Subject | Status |
|---|---|---|
| Sec S1 | Egress gate keyed on one of three reset causes | **FIXED** |
| Sec S2 | PR `title` bypasses `cmd_scrub` on both streams; SC7 entry understated the sinks and the severity | **FIXED** |
| Sec S3 / Func F6 | `CLAUDE_SESSION_ID` disabled the freshness rule for *every other* transcript, admitting in-flight sibling sessions to Stage-2 egress | **FIXED** (rules made cumulative) |
| Sec S4 | No `-type f` anywhere: a FIFO named `*.md` in an untrusted repo hung the hook forever (exit 124, zero output — breaks F-R5) | **FIXED** (`find -type f` **and** `[ -f "$cur" ]` in `_resolve_contained`) |
| Func F1 | An unreadable transcript advanced `max_hw` past itself before the open, then `continue`d — lost permanently | **FIXED** (staged, committed after `exec 3<&-`) |
| Func F2 | Mtime stat'd twice per file; C1 claims "read once and carried" and the deviation log repeats it | **FIXED** (index-aligned `files_epoch`) |
| Func F3 | `cmd_scout`'s `{}`-wipe | **FIXED** (pre-loop seed + `null` on empty) |
| Func F5 / Sec S10 | A malformed configured `github` repo becomes a `high_water` key → `_validate_hw` rejects the whole object → under C12 aborts the *run* | **FIXED** (shape filter at the boundary + diagnostic) |
| X1 | The snooze bound used `snooze_days` (the *default*) while `snooze <src> [days]` takes an explicit argument — every longer snooze silently voided **and blamed on clock skew** | **FIXED** (one-year sanity ceiling) |
| X2 | A non-numeric `snooze_days` aborted the whole `due` comprehension — nothing due for *every* source, the exact failure the try/catch arms exist to prevent | **FIXED** (literal bound) |
| X3 | The skew announcement used a second, divergent predicate — fired for sources `due` did not return | **FIXED** (intersected with `due`) |
| X4 | `snooze` on a source with no state entry was a silent no-op (the missing-entry arm preceded the snooze arm) — pre-existing, reachable for `scout` | **FIXED** (arm reordered) |
| X5 | Step 1's backticked command still showed the fileless `mark-run` its own prose retires | **FIXED** |
| X6 | The rationale sentence was **false**: `mark-run` without a file *does* advance `last_run` (executed, rc 0). The same claim reached the commit message and the PR body | **FIXED in `pipeline.md`; commit message and PR body still carry it** |
| X7 | Step 9's abort-on-non-zero rule lacked Step 1's `(when non-null)` guard — a null `high_water` (reachable for a *processed* source) aborts the run | **FIXED** (guard hoisted for all sources) |

### Major — tests (ALL OPEN)

| ID | Subject |
|---|---|
| T3 | The C8 deny-side proof hardcodes `grep -qE -- '-newer'` and never runs `forbidden_rows` — a tautology about `grep`. Deleting the `-newer` row leaves all four C8 tests green: the row table is entirely unpinned |
| T4 | The C8 gate's subject is `$SCRIPT` alone; this change also edits `hooks/llm-utils.sh` (where `_file_mtime_epoch`, the reason the `stat`-portability row exists, *lives*) and `hooks/retro-state.sh` |
| T5 | Every transcripts fixture is cardinality 1: TC3a/b (`max_hw` → `cursor`) and TC5 (drop the `now_epoch` check) both survive; TC4 (junk `stat`) absent |
| T6 | No two-repo github case: `'. + {($r): $v}'` → `'{($r): $v}'` leaves the suite green, while the same mutation on the artifacts loop reds two tests |
| T7 | All three aggregate suppression diagnostics are **unasserted** — `grep 'suppressed'` matches one *test name*. Neutering all three leaves the suite green. The TC18 Anti-Deferral entry frames this as a cardinality problem; the diagnostic is not asserted at all |
| T8 | `_iso_to_epoch`'s pre-1970 case runs under `2>/dev/null`, so "silently" is unasserted (adding a warning stays green); and the name's second clause contradicts its own assertions — the function never writes to stderr, the *caller* warns |
| T9 | The human-stream half of the identity case is absence-only; silencing the deferred human branch leaves it green |
| T10 | The "flip-fixture" red-proof calls neither `cmd_scrub` nor the hook — it asserts that `echo` echoes, while naming itself the canary-privacy red-proof |
| T17 / Func F7 | The deferred exit bypasses `_transcripts_emit`, lacking its empty→floor fallback — falsifying D-1's "property of the call graph" rationale. Latent (unreachable today), but it is a fourth copy needing its own case |

### Minor

- **Sec S5** unbounded read of an untrusted repo file before the off-machine send — **FIXED** (`head -c 5242880`, matching `cmd_scout`'s bound)
- **Sec S6** `cmd_scrub` missed `/Users/<user>/` on the macOS platform N-R1 targets — **FIXED**
- **Sec S7** the future-seam refusal failed open when `date` was unreadable — **FIXED**
- **Func F8** `_heal_cursor`'s message promised an egress suppression `cmd_github` does not implement — **FIXED** (clause moved to the two call sites that do)
- **X8** `_file_mtime_epoch` breaks `llm-utils.sh`'s `_llm_` namespace convention — OPEN
- **X9** `due`'s header contract unsynced with both heals — **FIXED**
- **Sec S8** four of `_resolve_contained`'s five rejection paths are silent, including the containment escape — OPEN
- **Func F9** github's future-dated / unparseable diagnostics are per-item where every sibling aggregates — OPEN
- **Func F10** a third `exit 2` class F-R5 does not admit — OPEN (header documents it; plan does not)
- **T11** `setup()` does not unset `RETRO_PRESCREEN_NOW`; the `TMPDIR` comment still cites the deleted `_mtime_ref_file` (TC19) — OPEN
- **T12** trailing `chmod 644` runs only on the success path (TC20, RT11) — OPEN
- **T13** the artifacts round-trip discards `mark-run`'s status, contradicting the deviation log's "both assert rc 0" — OPEN
- **T14** the transcripts future-clamp oracle is `<= now`, satisfied by any degenerate value — OPEN
- **T15** `scout: curl missing` asserts one third of its name — OPEN
- **T16** confirms the four logged gaps; TC21b's stale-prose list should also cover `:208` and `:561`

---

## Anti-Deferral entries judged UNDERSTATED by the review

Three of the deviation log's own entries are findings in their own right (R34):

- **SC7** named one sink of three and rated Minor; the unscrubbed title reaches the `--json`
  document, the human report *and* the sub-agent, carrying the `/home/<user>/` spelling the
  same file treats as a hard invariant elsewhere.
- **`[C11-map round-trip]`** rated a malformed configured repo "Likelihood: low" (a typo in a
  hand-edited list is ordinary user error) and said it "aborts the whole source" where
  `pipeline.md` aborts the **run**. It also claims both round-trips "assert rc 0"; the
  artifacts one does not.
- **`[C11-TC18]`** framed the gap as a cardinality problem; the diagnostic is unasserted
  entirely, at any cardinality, on any source.

## Defects introduced *by the fixes* and caught by the suite

Recorded because they are the same "Nth fix opens a new instance" shape this change exists
to stop:

- **`reset_any` keyed on `persisted_epoch -eq 0`** conflated "no state entry" with a
  legitimately persisted `1970-01-01T00:00:00Z`, disabling egress on every first run. Three
  tests went red. Fixed to `-z "$persisted_iso"`.
- **The cumulative freshness rule bounded one side only**, so a future-dated transcript was
  excluded as "written moments ago" and never reached the future-mtime diagnostic. One test
  went red. Fixed to bound both sides.

## Recurring Issue Check

Preserved per reviewer in `docs/archive/review/` alongside this file is not practical for
four agents; the fired rules, consolidated:

- **R3** — Func F3 (scout), Test T2/T5/T6 (transcripts and github twins uncovered), X5/X7
  (`--high-water-file` and the null guard propagated to one step of two)
- **R42** — Sec S1 (reset causes), Sec S2 (free-text fields), Sec S6 (home spellings),
  Func F3 (the `high_water`-emitting source set)
- **R34** — the three understated entries above, plus TC3a/b, TC4, TC5, TC6b, TC6d, TC15,
  TC19, TC20 unimplemented and unlogged, plus Func F1/F6 unlogged
- **R49** — Sec S1/S2/S3/S9, Func F2/F4/F8, X1/X3/X6 (claims falsified by execution)
- **R50** — Sec S9 and Test T3/T4 (a gate reporting PASS by never running), Test T7
- **RT7 shape (g)** — the dominant finding: eight mutations, eight green, six of them
  declared red-expected by the plan
- **RT8/RT10** — Test T9, T15, and `:822`; TC6e/f/g's allow halves absent or unfalsifiable
- **RS3** — Sec S4 (file type never validated), Sec S10 (repo shape validated only after the
  request), X2 (`snooze_days` unvalidated into arithmetic)
- **RS4** — Sec S2, Sec S6
- **R48** — X1/X4 (`cmd_snooze` and `cmd_due` decide the same question by different
  quantities); Sec S1's `_is_iso`-vs-`fromdate` divergence is declared but its consequence
  was not
- **R45** — Func F2 (two stats per file against a one-stat budget)

Checked and clean: R1/R2/R17 (`_file_mtime_epoch` adopted at all four derived sites, no
survivor of the old idiom), R43 (`llm-utils.sh`'s rewrite moves toward denial in every
differing input — a seven-row old/new table was executed), R47, R51 (the `_resolve_contained`
residual declares window *and* both sinks with no understatement), R44 (C12 fixes the
consumer-side status read).

## Environment Verification Report

- `VC1` (BSD/macOS) — `blocked-deferred`, as predicted in Phase 1. Unchanged: the reviewers
  raised no BSD-arm findings and asked for no BSD case.
- `VC2` (bash 3.2) — `blocked-deferred`. Its entire mitigation is the C8 gate, which
  Test T3/T4 and Sec S9 show is under-powered (unpinned rows, two edited files outside the
  subject, one dead row). **This is the constraint whose mitigation the review most
  weakened.**
- `VC3` (sub-second mtimes) — `verified-local`; `fs_keeps_subsecond` still gates.

## Resolution Status

Fixed this round, verified by execution (see the tables above for the full list): Sec
S1/S2/S3/S4/S5/S6/S7, Func F1/F2/F3/F5/F6/F8, X1/X2/X3/X4/X5/X6/X7/X9.

Gates after the fixes: `bats tests/retro-prescreen.bats` 97 ok / rc 0;
`bats tests/retro-state.bats` 46 ok / rc 0; `hooks/check-rule-sync.sh` rc 0.

**Open, and the reason the round is not closed**: every Testing finding (T1–T17 except the
confirmations), plus X8, Sec S8, Func F9/F10. The test findings are not deferrable — they
are the verification mechanism for the fixes above, and while they stand, "the suite is
green" is not evidence about any of them.
