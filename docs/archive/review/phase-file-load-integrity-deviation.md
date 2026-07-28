# Coding Deviation Log: phase-file-load-integrity

Recorded during Phase 2. Each entry names what the locked plan said, what was built instead, and
why. Written directly rather than via the Ollama `generate-deviation-log` helper: the helper takes
plan + existing log + full diff on stdin, and the diff here is large enough that the round trip
costs more than the deltas it would find — all of which were decided consciously during
implementation and are recorded below with their reasoning intact.

## D1 — The digest-stem fixture lives in the staged installed layout, not in `$FIX`

- **Plan (C5, C7 / I28)**: add a generated `common-rules.digest.md` to the bats fixture tree so the
  `END-OF-DIGEST` stem equality has a fixture home, "which also brings check 7 under fixture
  coverage for the first time". The plan named the staged `inst/` layout as the acceptable
  alternative.
- **Built**: no digest in `$FIX`; the stem-equality assertion is the staged-layout test
  `installed layout: the digest terminator is compared against SKILL.md's declared stem`.
- **Why**: adding a digest to `$FIX` destabilises five existing tests. `check-rule-sync.sh`'s check
  check 7 regenerates the digest from `$FIX/common-rules.md` and compares byte-for-byte, but several
  existing fixtures *mutate* `common-rules.md` (delete an R row, append an Extended-obligations
  block). Those tests would gain an unrelated "digest is stale" drift line — and one of them,
  `pass: extended-obligations pointer with range form matches headers`, asserts **status 0** and
  would have failed outright. Turning five single-purpose fixtures into multi-trip ones to give one
  assertion a home is the wrong trade; the staged layout already carries the real digest and both
  hooks, so the assertion is stronger there (it runs against the real generated artifact, not a
  synthetic one). Check 7 remains without fixture coverage — pre-existing, unchanged by this work,
  and now covered indirectly by the staged run.

## D2 — `decoy-off` replaced by a red-provable inverse fixture

- **Plan (C5 matrix)**: a `decoy-off` row — "remove the fenced decoy from `setup()`" — recorded so
  the fence-awareness ablation has an expectation to compare against.
- **Built**: `drift (I15): the fixture's fenced decoy is counted once its fences are removed` —
  delete the decoy's fence lines, leaving the step-shaped heading, and assert the count rises from
  3 to 4.
- **Why**: as specified, `decoy-off` describes what happens under a *hypothetical non-fence-aware
  linter*; as a bats test it would assert that removing the decoy changes nothing, which is green
  under both implementations and therefore proves nothing. The inverse mutation is a real assertion
  in the pass direction: it fails unless the linter is actually excluding fenced content right now.
  Together with the "heading moved into an indented fence" fixture, both directions of I15 are
  covered.

## D3 — The fixture's fenced decoy heading sits at column 0, not indented

- **Plan (C5)**: "an indented fenced block containing `### Step <N>-9`".
- **Built**: the fence lines are indented (exercising the whitespace-tolerant toggle), the heading
  inside is at column 0.
- **Why**: found by executing D2's fixture, which failed. With the heading itself indented it is
  uncounted for *two* reasons — the fence and the leading whitespace — so removing the fences
  changed nothing and the decoy proved nothing about fence awareness. Column 0 inside an indented
  fence is also the shape the real files actually have (`phase-3-review.md:309` carries
  `### Functionality expert` at column 0 inside a fenced template). This is exactly the class of
  claim the plan's own rule about not writing "red-proves" statements before executing them exists
  to catch.

## D4 — C6's skills-arm block message hoisted into a variable

- **Plan (C6)**: add the arm to both case blocks with "its own message".
- **Built**: `SKILLS_BLOCK_REASON` defined once above the `case`, referenced by both arms.
- **Why**: the two skills arms need the *same* message (unlike the two harness-config arms, which
  carry deliberately different wording), and an identical string duplicated across arms drifts
  silently — and fixture 3 asserts the unmanaged-skill sentence against only one arm, so a drifted
  copy in the other would ship unnoticed (R2).

## D5 — Delegation split

- **Plan**: Phase 2 Step 2-2 delegates implementation batches to sub-agents.
- **Built**: C6 (`block-sensitive-files.sh` + its five fixtures) delegated to one Sonnet sub-agent;
  C1-C5 and C7 implemented by the orchestrator.
- **Why**: C6 is genuinely self-contained — two files, no shared surface with the rest. C1-C5/C7
  interlock through the fixture isolation matrix: the linter's clause boundaries and the fixtures
  that isolate them are one design, and splitting them across agents would have each re-deriving
  the matrix. The sub-agent's report was not accepted as proof (R21): the orchestrator re-ran
  `bats tests/block-sensitive-files.bats`, read the full diff of the hook, and ran the mutation
  residue grep over all changed files (clean).

## D6 — Phase 1 Step 1-5 merge performed mechanically, not via Ollama

- **Plan / skill (Step 1-5)**: the mechanical json-index join seeds deduplication, then
  `merge-findings` produces the merged prose.
- **Built**: the json join was performed and is what produced the merged findings; the Ollama call
  was skipped.
- **Why**: the three expert outputs were held in the orchestrator's context, so feeding them to
  Ollama required writing ~24k tokens of raw output back out first — more Claude tokens than the
  zero-token merge saves. Recorded in the review file's header as well, so the merged document is
  not mistaken for Ollama output.

## D7 — No `Implementation steps` section to batch

- **Plan**: contract-first, per the skill's default; there is no "implementation steps" list.
- **Built**: batches derived from contract boundaries (C1-C3 markdown substrate → C4 linter → C5
  fixtures → C7 digest, with C6 in parallel).
- **Why**: mechanical consequence of the contract-first plan format; recorded so the Step 2-2
  "split the plan's implementation steps" instruction is not read as skipped.

## D8 — Ablation found two clauses with no fixture; both were closed

The plan marked the isolation matrix provisional and required the per-clause ablation runs to
settle it. They did, and they found two declared checks that no mutation could red — the exact
defect class this whole change exists to eliminate:

- **8g's resolution half** (`core names step X, which is not a counted '### Step' heading`). The
  `8g` fixture asserted only the membership message, so removing the resolution check from the
  linter failed nothing. Closed by asserting both messages in that fixture: the mutation
  `core: 1-1 → 1-9` already fires both, because `1-9` exists only inside the fenced decoy.
- **The unbalanced-fence tripwire** (`unbalanced code fence at EOF`). Declared in the plan as
  defence-in-depth and shipped with no fixture at all. Closed by a new fixture that inserts a lone
  fence line before the terminator; the step count is unchanged, so it fires on the desync itself.

Both were re-ablated afterwards and each now fails exactly its own fixture and nothing else.

## D9 — Observed isolation matrix vs the plan's prediction

**Correction (see D12): the "all clauses ablation-proven" claim below was wrong when written.** The
first ablation pass covered the clauses the plan's matrix named and did not enumerate the clauses
the *implementation* actually contains, so three branches it never listed went unexamined. The
statement is left in place with this correction rather than quietly edited, because the failure
mode — proving the set you wrote down instead of the set that exists — is the same one R42 names.

Of the clauses that pass covered, cells where the observed "also fails" set differs from the plan's
prediction:

- `sweep` fails when **8a.1** is ablated, because the stray `phase-4-extra.md` asserts 8a.1's
  message. This is inherent: the sweep fixture proves the *directory sweep*, not a clause of its
  own, and it can only prove it by asserting some clause's message on a file the hard-coded triple
  does not name. The plan predicted it would also red 8h; it does not, because a file failing 8a
  still reports its missing terminator through the ungated 8h — and 8h's message names
  `phase-4-extra.md` too, but no fixture asserts it.
- `8h-dup` and `8h-notlast` do **not** also fire 8h.4, confirming that the r3 fix (excluding
  strict-form lines from the loose scan, I8e) achieved what it was for: before it, both clauses
  were unprovable because the loose scan subsumed them.
- Ablating **8d** fails all three of `8d`, and both I15 fence fixtures — expected and inherent:
  both fence fixtures detect fence blindness *through* the step count, which is 8d's message.
- Ablating **8h.1** fails `8h-dup`, `8h-missing` and the I13 stem fixture — inherent for the same
  reason: the stem fixture detects a non-derived stem through the terminator-count message.

## D10 — Skill-loader inertness checked against a staged `HOME`, not the live one

- **Plan (C1 acceptance)**: record `ls ~/.claude/skills/` before and after `install.sh` and confirm
  it is unchanged with no loader warning naming a phase file.
- **Built**: `install.sh` run with `HOME` pointed at a scratch directory. Observed: exit 0, nine
  skills installed, `diff -r skills/triangulate <staged>/skills/triangulate` clean, the installed
  `phase-3-review.md` beginning with `---` and ending with `## END-OF-PHASE-3`.
- **Why**: running the real installer mid-change would push unreviewed edits into the live config
  before Phase 3 has looked at them. The staged run answers the part that is observable now — the
  installer copies front matter and terminator faithfully and adds no skill. The loader-warning
  half is only observable in a fresh session after the change is installed, and is called out here
  rather than claimed. The live install remains the user's normal post-merge step.
- Incidental confirmation: the staged tree has nine skills, the live tree ten. The extra is
  `improve`, the unmanaged skill C6's message branch exists for.

## D11 — Mechanical pre-step dispositions (Phase 2 Step 2-5)

Eleven mechanical hooks were run against `main`. Nine were clean or not applicable (no source
files, no deployment artifacts, no suppressions, no timing-sensitive comparisons, no new production
exports, no concurrency tests, no dispatch sites, no propagation candidates, no hardcoded-reuse
matches). Two fired:

- **R30 (markdown autolink footguns)** — six `#7` / `#8` tokens in the plan, review and deviation
  documents, referring to linter check numbers. On GitHub these autolink to issues/PRs. **Fixed**:
  rewritten without the `#`. Not a case for Anti-Deferral rule 5 ("fix the check, not the
  artifact") — these are ordinary prose, not documentation *of* the forbidden pattern.
- **RT7b (orphaned check script)** — `hooks/check-rule-sync.sh` reported as "referenced only in
  non-gate files". **Not a finding here, with reasoning**: the hook's gate-surface list is CI
  configs, Makefiles, package.json and pre-commit/pre-pr aggregates — none of which this repo has.
  The authoritative gate in this repo *is* `bats tests/`, and `tests/check-rule-sync.bats` runs the
  linter against the live skill directory asserting exit 0, so the check genuinely cannot rot
  unnoticed. The hook cannot know that a bats file is the gate when no CI exists. Recorded rather
  than silently dismissed, and left unfixed: teaching the hook to treat a bats file as a gate
  surface is a change to a shared detector with its own blast radius, unrelated to this branch.
  `TODO(phase-file-load-integrity): check-orphaned-checks.sh has no gate surface for repos whose gate is the local test suite`.

## D12 — Phase 2 self-R-check findings, all fixed in-phase

The three mini sub-agents ran against the committed implementation. Eight findings, all accepted
and fixed before Phase 3 rather than carried. Five were established by execution.

**Fail-open paths in the linter (security expert, all executed):**

- **Indentation asymmetry.** The fence anchor tolerated leading whitespace while the heading anchor
  was column-0 only, so a `### Step` indented by a single space still rendered as a heading a reader
  executes but was invisible to the count. Both anchors now allow the same 0-3 spaces.
- **Fence desync via indented code blocks.** `^[[:space:]]*` counted backtick lines inside 4-space
  indented code blocks as fences; two of them flip the toggle with even parity, so the balance
  tripwire stayed silent and every heading between them was skipped. Both anchors are now
  CommonMark-strict (`^ {0,3}`). Ignoring an indent-4 backtick line can only *over*-count headings,
  which reds — the fail-closed direction.
- **`SKILL_KEYS` had no emptiness guard** while both terminator stems did, so a declaration line
  naming zero manifest keys made 8i iterate once on the empty string and check nothing.
- **Deleting `common-rules.digest.md` passed clean** while corrupting it reds — the fail direction
  inverted on the file SKILL.md names as the *first* read. It is now a preflight member (exit 2).
  It stays out of `ALL_FILES`, which is the scan list for the range/dangling checks: its content is
  generated and verified byte-for-byte by check 7, and scanning it would flag the generator's own
  boilerplate example as a dangling reference in any skill dir whose table stops below RT4. This
  reopens D1's fixture problem, closed by generating a digest in `setup()` and regenerating it in
  every test that mutates the fixture's `common-rules.md`.
- **The `~/.claude/` guard's member set was re-derived from `install.sh`'s write set** rather than
  extended by the one path that came up. Added: `rules/` (same `rm -rf; cp -r` shape as `skills/`,
  and `rules/common/*.md` is auto-injected into every session), `RTK.md`, `model-routing.md`, and
  `hooks/` without the `.sh` restriction — `install.sh` re-copies `hooks/lib/` wholesale, and
  `ast-runner.js` is the AST engine the detection hooks call.

**Three more clauses with no red-proof (testing expert, ablation-verified):**

- `8j.3` (SKILL.md declares no *digest* stem) — `8j.2` removes the phase stem and the staged test
  *renames* the digest stem, so neither reached it.
- `8g`'s empty-`core_id` branch — the `8g` fixture supplies a wrong ID and takes the else branch.
- The `SKILL_KEYS` guard added above, which arrived without a fixture of its own.

Each now has an isolating fixture, and each was re-ablated: neutralising the clause fails exactly
its own test and nothing else. The two anchor changes were ablated the same way by reverting the
anchor rather than the drift call.

**Also fixed:** `FM_KEYS` was a hoisted constant with zero references under a comment claiming a
property it did not provide (removed, with the real reason the key names are *not* hoisted); the
linter's header enumerated checks 1-7 and never gained an 8; checks 3 and 5 scanned a hardcoded
file list while check 8 swept the phases directory, so a future `phase-4-*.md` would have been
manifest-checked but escaped range/dangling checking.

Full suite after all of it: **847 tests, 0 failures.**

## END-OF-DEVIATION-LOG
