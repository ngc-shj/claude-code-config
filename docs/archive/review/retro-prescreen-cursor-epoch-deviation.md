# Deviation log: retro-prescreen-cursor-epoch

Phase 2 implementation against plan revision 3 plus the round-3 dispositions recorded in
`retro-prescreen-cursor-epoch-review.md`. Branch `retro/prescreen-cursor-v2`, commit
`d84ca51`.

## Structural deviations (implemented differently from the contract text)

### D-1 — Two emitter helpers introduced that no contract names
`_github_emit` and `_transcripts_emit` were added. C7 and C6 each require that *every* exit
path emit the cursor, and both functions have exits that predate the cursor read (the `gh`
absent / unauthenticated guards, the root-absent return). Duplicating the projection at each
exit would have been four and three copies respectively of the "convert with `_epoch_to_iso`,
fall back to the floor, warn" rule — the shape the plan spends C5 arguing against. One
emitter per source makes "no exit path can drop the cursor" a property of the call graph
rather than of four consistent copies.

Consequence: `_repo_relative`, `_github_emit` and `_transcripts_emit` are three new helpers
that C1–C4's contract style would have given signatures and control classes. They have unit
coverage only for `_repo_relative`.

### D-2 — C8's gate subject is the hook's CODE, not the whole file
The plan says the gate's subject is `$SCRIPT`. As implemented it strips **full-line comments**
before matching. Reason, discovered by running the gate: the `-newer` and `clamp` rows matched
the hook's own prose explaining why those constructs were removed. Forbidding the file from
naming the retired construct would push that explanation out of the file, which is the
opposite of what the rows are for.

This narrows the *subject*, not the pattern, and only full-line comments are stripped, so an
inline `# ...` cannot hide code. Recorded here because "narrow the gate under pressure" is the
exact move C8 was written to prevent, and the distinction between narrowing a subject and
weakening a pattern is the whole of the justification.

### D-3 — The seam announcement fires on every run, not only on the absurd-value case
C3 says `RETRO_PRESCREEN_NOW` "is announced whenever set". Implemented literally, which means
every bats case that pins the seam now emits a line on stderr. No existing case asserts stderr
emptiness, so nothing broke, but the suite's stderr is noisier than before.

## Contract rows implemented as planned, noted for the reviewer

- C1's helper is defined in `hooks/llm-utils.sh` and the `cmd_transcripts` `source` was hoisted
  above the gather loop; **both** sourcing sites carry the `command -v` guard
  (`retro-prescreen.sh:416`, `:814`).
- C1's adopter count is three in the hook (the mtime is read once per file and carried) plus
  `llm-utils.sh:94`.
- `llm-utils.sh:95` gained the future-mtime clause (round-3 S6), citing `check-pre-pr.sh:437`
  as the in-repo precedent.
- C13 (`retro-state.sh`'s `due` comprehension heal) was added — round 3 moved this from SC5's
  deferral to in-scope, on the finding that a future `last_run` suppresses the source entirely
  and therefore makes the cursor heal's own announcement unreachable.

## Resolved in Phase 3 (code review round 1)

Every entry that stood as "Skipped" below was **closed**, not carried. Three of them were
judged **understated** by the review, and that judgement was correct in each case:

- **[SC7]** rated the unscrubbed PR `title` Minor and named one sink. It reaches the `--json`
  document, the human report **and** the mining sub-agent, carrying the `/home/<user>/`
  spelling this same file treats as a hard invariant elsewhere. Fixed.
- **[C11-map round-trip]** rated a malformed configured repo "Likelihood: low" — a typo in a
  hand-edited list is ordinary user error — and said it "aborts the whole source" where
  `pipeline.md` aborts the **run**. It also claimed both round-trips assert rc 0; the
  artifacts one did not. Both fixed, plus a boundary shape filter on the config.
- **[C11-TC18]** framed the gap as a cardinality problem. The diagnostic was unasserted
  **entirely**, at any cardinality, on any source — neutering all three left the suite green.
  Fixed with one case per source at N ≥ 2.

**[C11-TC7e/f]** (the `--search` bound) was verified accurate: the bound is built from
`hw_epoch`, which holds only healed values, confirmed by execution.

**[R3-21]** (`pipeline.md` Step 4 as an unlisted `high_water` consumer) remains open and is
the only entry below that survives — see the tail of this file.

## Defects the fixes themselves introduced

Recorded because they are the "Nth fix opens a new instance" shape this change exists to
stop, and because the suite — not a reviewer — caught all three:

- **`reset_any` keyed on `persisted_epoch -eq 0`** conflated "no state entry" with a
  legitimately persisted `1970-01-01T00:00:00Z`, disabling raw egress on every first run.
  Three tests red. Keyed on `-z "$persisted_iso"` instead.
- **The cumulative freshness rule bounded one side only**, so a future-dated transcript was
  excluded as "written moments ago" and never reached the diagnostic that reports it. One
  test red. Bounded on both sides.
- **`find -type f`** was added as the non-regular-file guard. `find` tests the LINK, so it
  silently excluded a legitimate artifact symlinked into the archive directory — a case
  `_resolve_contained`'s symlink chase exists to support — while still missing a FIFO reached
  *through* a symlink. The mutation battery surfaced it as an unprovable guard. The
  terminal-type assertion after the chase is the containment authority; the `find` predicate
  was removed.

## Remaining open

### [R3-21] [Minor] `pipeline.md` Step 4 is an unlisted `high_water` consumer
- **Worst case**: Step 4 writes the per-repo **minimum** into a committed retrospective doc's
  frontmatter as the durable state backup. After a heal that minimum is
  `1970-01-01T00:00:00Z`, and `retro-state.sh seed --high-water artifacts=<scalar>` expands a
  scalar over *all* configured repos — so a later recovery from that doc re-mines every repo
  from 1970.
- **Likelihood**: low. The direction is the safe one `pipeline.md:134-137` mandates, and the
  next heal-free run rewrites the doc.
- **Cost to fix**: two sentences in C5/C6's walkthroughs and one in `pipeline.md`.

### [Func F9] [Minor] github's per-item diagnostics
`cmd_github`'s future-dated and unparseable-`updatedAt` lines are per-PR where every sibling
source aggregates. Bounded by `--limit 200`, so N-R2's output bound is not breached, but 200
lines still buries the single-line signals they share the stream with.

### [Func F10] [Minor] a third `exit 2` class
A missing `_llm_file_mtime_epoch` exits 2, which F-R5 admits only for unknown mode / missing
config. It is the right call — the alternative is every mtime unreadable, every file a
candidate, no cursor ever advancing — and the file header documents it; the plan does not.

---

## Skipped — with Anti-Deferral entries

### [C11-TC7e/f] [Major] The `--search` bound has no acceptance case — Skipped
- **Worst case**: C7's one *declared surviving* pre-filter is unverified. If the bound is built
  from the unhealed cursor, a poisoned `2100-…` cursor makes the server return nothing and the
  local adjudicator has nothing to adjudicate — the demoted-pre-filter-decides class re-entering
  through the door the plan deliberately left open, with a green suite.
- **Likelihood**: low that the shipped code is wrong (the bound is computed from `cursor_epoch`,
  which is the healed value by construction), high that a future edit breaks it undetected.
- **Cost to fix**: two lines in `setup_gh_mock` to append `"$@"` to a log, plus two cases.
- **Why deferred**: not deferred on cost — it was not reached before the branch was pushed.
  It is the highest-priority item of this log.

### [C11-TC18] [Major] The aggregate-diagnostic bound has no acceptance case — Skipped
- **Worst case**: N-R2's output bound is unproven. A revert to per-file diagnostics restores
  ~1167 lines / ~127 KB of stderr per steady-state run and buries every single-line signal
  (the heal announcement, the clock-disabled notice, the skipped-repo line) that R50 clause (ii)
  exists to surface.
- **Likelihood**: moderate — the per-file form is the more natural spelling and there is nothing
  to stop it coming back.
- **Cost to fix**: one case with N ≥ 2 files below the cursor asserting exactly one suppression
  line. Note N = 1 is vacuous (aggregate and per-file are indistinguishable), and every existing
  artifacts fixture but one is cardinality 1.

### [C11-TC21a/b] [Minor] Test names and rationales still describe deleted machinery — Skipped
- **Worst case**: `@test "artifacts: -newermt high-water excludes files older than the cursor"`
  (`tests/retro-prescreen.bats:374`) names a construct that no longer exists, and the name is
  what a reader sees when it fails. Three further names say "clamped" for an operation that now
  resets. The TZ rationales at `:47`, `:59`, `:394`, `:410`, `:512-515` describe `touch -t`,
  `date -u` and `-newer`; `:515`'s "Reds against the -u form" is now **unfalsifiable**, i.e. a
  coverage claim a mutation cannot check.
- **Likelihood**: certain — the text is already wrong.
- **Cost to fix**: prose only.
- **Why deferred**: no behavioral risk, and C8's gate is scoped to the hook so it cannot reach
  the test file. The unfalsifiable coverage claim at `:515` is the part that matters.

### [C11-map round-trip] [Minor] The map round-trip does not re-read state, and has no deny arm — Skipped
- **Worst case**: `artifacts` (`:867`) and `github` (`:1143`) both round-trip through
  `mark-run --high-water-file` and assert rc 0, but neither re-reads `show --json`, so a write
  that is accepted-and-wrong is not distinguished. No case covers a malformed configured repo,
  which under C12's new status rule now aborts the whole source.
- **Likelihood**: low.
- **Cost to fix**: one assertion each, plus one deny case.

### [SC7] [Minor] `cmd_github`'s `title` bypasses `cmd_scrub` — not recorded in the plan
- **Worst case**: `comment_bodies` are scrubbed (`:689`) and `title` is not (`:668`), while the
  file header states the scrub is "the single shared artifact invoked by every source that
  emits free-text content". A merged-PR title carrying an email address or a secret-shaped token
  reaches the mining sub-agent and from there a committed retrospective document.
- **Likelihood**: low but not negligible — PR titles are attacker-controllable API text.
- **Cost to fix**: one line, the same shape as `:689`.
- **Why deferred**: out of scope by the plan's own Out-of-scope clause (everything outside the
  cursor machinery), but C7 restates this source's emitted shape, so the asymmetry is in reach
  of this change and should not be left for the next reader to re-derive. **This entry is the
  record the round-3 disposition asked for and the plan never got.**

### [R3-21] [Minor] `pipeline.md` Step 4 is an unlisted `high_water` consumer — Skipped
- **Worst case**: Step 4 writes the per-repo **minimum** into a committed retrospective doc's
  frontmatter as the durable state backup. After a heal that minimum is `1970-01-01T00:00:00Z`,
  and `retro-state.sh seed --high-water artifacts=<scalar>` expands a scalar over *all*
  configured repos — so a later recovery from that doc re-mines every repo from 1970.
- **Likelihood**: low; the direction is the safe one `pipeline.md:134-137` mandates and the next
  heal-free run rewrites the doc.
- **Cost to fix**: two sentences in C5/C6's walkthroughs and one in `pipeline.md`.

## Not done

- **Go/No-Go gate**: all 12 rows still read `pending`. The gate was never flipped after
  implementation.
