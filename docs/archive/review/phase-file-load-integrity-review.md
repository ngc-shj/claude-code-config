# Plan Review: phase-file-load-integrity
Date: 2026-07-28
Review rounds: 1-2

## Changes from Previous Round

Round 1: initial review of plan revision 1.
Round 2: incremental review of plan revision 2 — see `## Round 2` below. Revision 2 dropped the
`end:` key, moved the terminator convention into `SKILL.md`, removed the trailing `---` rule,
added fence awareness, and added contracts C6 (guard the installed skill copy) and C7 (digest
terminator).

## Merge method — deviation from Step 1-5

The mechanical json-index join across the three experts' fenced indexes was performed
(21 merged findings from 30 reported; 6 convergence pairs/triples identified). The
Ollama `merge-findings` pass was **not** run. Reason: the three expert outputs are held
in the orchestrator's context, and feeding them to Ollama requires writing ~24k tokens
of raw output back out through the Write tool — more Claude tokens than the zero-token
merge saves. The json join, which Step 1-5 designates as the fallback dedup skeleton,
was used instead and is recorded here rather than presented as an Ollama merge.

Severity floors were applied per "Perspective Convergence as a Severity Signal": any
finding independently reported by ≥2 perspectives is at least Major, taking the maximum
of the reported severities.

## Functionality Findings

**M3 [Major] [convergent: functionality+security+testing] Check 8a's "closing `---`" is satisfied by the retained trailing horizontal rule**
Each phase file's only `^---$` today is the trailing rule at EOF, which C2 retained. Deleting
the front-matter *closing* delimiter leaves 8a satisfied by that rule ~490 lines later, and
8b–8g all still pass: the mutation is invisible, and 8a's acceptance criterion is unmeetable
as written.
*Resolution*: **Accepted — fixed in Round 1.** The trailing `---` rule is removed from the
phase files (the sentinel replaces it), so the file has exactly two `^---$` lines. Check 8a is
respecified positionally: line 1 is `---`, the closing `---` is the first subsequent `^---$`
and must occur at line ≤ 10, every line between matches `^[a-z_]+: .+$`, and key extraction
reads only that window. Two red fixtures (missing opening, missing closing).

**M5 [Major] Scenario S2 contradicts the plan's own reproduced evidence**
The Background reproduces one surviving line plus `[N more lines]`; S2 then claims lines 2–7
survive. Under the reproduced behaviour the reader gets `---` and nothing else — strictly less
informative than today's `## Phase 1: …`. The claim "every truncation channel … detectable
with one mechanism" is false for the channel in the Background.
*Resolution*: **Accepted — fixed in Round 1.** Objective, Background and S2 rewritten to state
per-channel coverage: the manifest covers `Read`-with-`limit`/`offset` and context compaction;
the single-line Bash-proxy channel is covered by the standing terminator rule in `SKILL.md`
(which is always loaded in full) and by `SC3`. The line-1 regression is stated explicitly as an
accepted trade.

**M13 [Major] [convergent: functionality+testing] `title:` is normatively specified but only presence-checked, and is not a valid YAML scalar**
Requirement F4 rejects metadata nobody checks; `title` is exactly that. Its real values contain
`": "`, which is not a valid YAML plain scalar in a mapping value.
*Resolution*: **Accepted — fixed in Round 1.** New sub-check compares `title` against the first
`^## ` heading after the front matter; the value is double-quoted in the front matter.

**M16 [Minor] `step_ids`' literal content is never stated, so check 8e is not implementable**
Every rendering uses elided `3-1 … 3-9` notation, including inside what reads as literal front
matter in S1.
*Resolution*: **Accepted — fixed in Round 1.** C1 now shows one file's front matter fully
expanded; the values table's `…` is marked as table shorthand.

**M17 [Minor] Step-ID grammar unspecified for suffixed sub-steps**
No `### Step 3-2a` heading exists today, but `phase-3-review.md` already treats Step 3-2b as an
executable unit in prose. `grep -cE '^### Step [0-9]+-[0-9]+'` would match a suffixed heading
and the obvious ID extraction would silently yield a duplicate `3-2`.
*Resolution*: **Accepted — fixed in Round 1.** ID grammar fixed as `[0-9]+-[0-9]+[a-z]?`, the
heading match is right-anchored, and sub-steps are declared members of `step_ids`.

**M18 [Minor] C5's "hard coupling" claim is false as stated — 2 of 20 tests break, not all**
14 drift tests assert `status -eq 1` plus a specific substring and survive; 3 exit-2 tests
short-circuit at the preflight.
*Resolution*: **Accepted — fixed in Round 1.** Replaced with the enumerated truth, including
the observation that the 14 drift tests stay honest only because of their substring assertions.

**M19 [Minor] Consumer D's "Verified" cites evidence that does not support the claim**
`install.sh:227` establishes which *directories* become skills, not which *files inside* a skill
directory the loader parses — and that premise is what justifies adding front matter at all.
*Resolution*: **Accepted — fixed in Round 1.** Citation replaced with an empirical check
recorded as an acceptance criterion: after install, the skill inventory is unchanged and the
phase files produce no loader warning.

**M20 [Minor] R42 member-set miscounted (21, not 20); one pointer target neither in scope nor scoped out**
`skills/agent-review/schemas/review-output.schema.json` is pointer-loaded and read mid-workflow.
*Resolution*: **Accepted — fixed in Round 1.** Count corrected; non-prose pointer targets
(`review-backend.sh`, `schemas/*.json`) excluded by ID with a stated reason.

## Security Findings

**M1 [Major] [convergent: security+functionality] The reader-side terminator check is vacuously true on every truncated read**
`end: END-OF-PHASE-3` sits in the front matter — the region that by design always survives. A
reader told to look for the sentinel finds it in the declaration on any read that returns
anything. C2's forbidden-pattern bullet and C2's acceptance criterion (`grep -c` equals 2) state
opposite requirements about this same occurrence.
*Resolution*: **Accepted — fixed in Round 1.** The `end:` key is **dropped entirely**. The
terminator convention becomes standing knowledge in `SKILL.md` (always loaded in full), the
linter derives the expected token from the filename, and C3's clause is restated positionally:
*the last non-empty line of what you received must be exactly `## END-OF-PHASE-<N>`*. The token
now appears exactly once per phase file. This also dissolves the 8f/8g isolation problem (M12
family) reported by the testing expert.

**M2 [Major] [convergent: security+testing] Sentinel uniqueness is specified in C2 but absent from the checks C4 implements**
A file with `## END-OF-PHASE-3` at line 8 *and* at EOF passes every one of 8a–8g. A reader
truncated past line 8 sees a properly anchored sentinel at column 0 and certifies its partial
read as complete — indistinguishable from the real one.
*Resolution*: **Accepted — fixed in Round 1.** New sub-check: exactly one line matching
`^## END-OF-PHASE-[0-9]+$` per phase file, and it must be the last non-empty line. Anchored
full-line count, not the unanchored `grep -c` originally specified. Red fixture added.

**M4 [Major] `### Step` headings inside fenced code blocks are counted, so the core step is deletable with the gate green**
`phase-3-review.md:309,313,323` and `phase-2-coding.md:328,348` already carry column-0 `###`
headings inside fenced prompt templates. Moving a real `### Step 3-3` heading into a fence
yields identical results for the step count, the ID list and the terminator check while the
instruction "launch three expert sub-agents in parallel" is gone. `core:` does not catch it
because C1 declared it presence-only.
*Resolution*: **Accepted — fixed in Round 1.** The heading scan is fence-aware (awk toggling on
a triple-backtick fence line); `core:` is upgraded from presence-only to a real assertion — the
ID it names must appear in `step_ids` and must resolve to a counted out-of-fence heading. Red
fixture: relocating a real `### Step` heading into a fence.

**M6 [Major] S5's access-control premise is false — installed skill files are not guarded**
`block-sensitive-files.sh:73-82` matches only `$HOME/.claude/hooks/*.sh`, `settings.json` and
`CLAUDE.md`. `~/.claude/skills/**` appears in no case arm anywhere. The installed copy is the
one the runtime loads, and the new control's routine enforcement (`bats tests/`) targets the
repo copy only.
*Resolution*: **Accepted — fixed in Round 1.** S5's wording corrected, and the expert's option
(a) adopted as new contract **C6**: add `$HOME/.claude/skills/`* to the hook's case arm with a
fixture in the existing `tests/block-sensitive-files.bats`. The axis: option (b) — scope it out
— leaves the runtime-loaded artifact that governs whether the security review runs with no
control at all, which is what the Objective claims to close; cost of (a) is one case arm and
one test, well under the Anti-Deferral 30-minute rule. The noted pre-existing gap (the hook is
wired to `Edit|Write|MultiEdit` only, so a Bash redirect bypasses it even for covered paths) is
recorded as `SC5` — it is a property of the existing hook, not of this change.

**M7 [Major] SC2 defers `common-rules.digest.md`, which *is* read whole and whose truncated tail is the entire RS/RT rule set**
SC2's justification ("verified against the source table by check #7") answers a different
question: check #7 verifies bytes on disk, while the plan's whole thesis is that on-disk
correctness says nothing about what the reader received. `SKILL.md:22` and the digest's own
line 4 direct the reader to read it whole. Its tail is R44–R46, **RS1–RS6**, RT1–RT9 — a
truncated read silently deletes the security and testing checklists and the Recurring Issue
Check then reports clean.
*Resolution*: **Accepted — fixed in Round 1.** Moved out of SC2 into scope as new contract
**C7**: `hooks/generate-triangulate-rule-digest.sh` appends `## END-OF-DIGEST`, its `--check`
path asserts it, `SKILL.md`'s loading protocol names it, and `tests/triangulate-rule-digest.bats`
gains the red fixture. R42 class-membership: this is the highest-value member of the
"read-whole pointer-loaded file" class and was wrongly deferred.

**M14 [Major] [convergent: functionality+security+testing] I8's empty-glob fail-closed branch is unreachable**
The preflight at `check-rule-sync.sh:45-50` exits 2 if any of the three phase files is missing,
and it runs before check #8, so the glob can never be empty. The file's neighbouring idiom
(`[ -e "$f" ] || continue`) is the fail-*open* form an implementer would copy while believing
I8 is satisfied.
*Resolution*: **Accepted — fixed in Round 1.** I8 restated: fail-closed derives from the
existing preflight, which is extended to include the phases directory; the literal-glob guard
is retained as defence-in-depth with an inline "unreachable by construction" comment and is
explicitly **not** listed among the mutation-proven gates. The plan now records that removing
the three phase paths from `ALL_FILES` would break the guarantee.

**M15 [Minor] `exit 2` from the new block would mask drift already accumulated by checks 1–7 (R44)**
C4 forbade `exit 0` but not `exit 2`, while I10 required exit 2 for a missing phases directory —
discarding a `fail=1` set by earlier checks and suppressing the summary. `retrospect/pipeline.md:118`
and `folding.md:91` gate on this exit status.
*Resolution*: **Accepted — fixed in Round 1.** Any `exit` inside the new block is forbidden; the
missing/unparsable case is routed through the existing preflight where exit 2 already fires
before drift accumulates.

**M21 [Minor] Unenforceable prose in the C3/C4 forbidden-pattern lists**
Three "forbidden patterns" are prose or ungreppable; C1's second pattern is honestly
self-labelled as conceptual and is the model.
*Resolution*: **Accepted — fixed in Round 1.** Conceptual entries labelled as such; the two
cheap ones promoted to real sub-checks with fixtures (`SKILL.md` carries no `^### Step`
enumeration; `SKILL.md` names the required tokens). The `sed -i` pattern's trailing space is
fixed so `sed -i.bak` / `sed -i''` are caught.

## Testing Findings

**M8 [Major] C3's static acceptance criteria have no assertion, and VE3 is over-applied**
VE3 honestly covers I7 (a model behaviour with no local oracle), but the plan lets it swallow
all of C3 — including three plain greps. Nothing goes red if the loading-protocol clause is
deleted outright. Worse, `SKILL.md` will name front-matter keys by prose while the linter checks
its own hard-coded list, so renaming a key keeps both green while `SKILL.md` instructs the reader
to look for a key that no longer exists. `tests/install.bats:266,270-283` already does exactly
this class of prose-integrity assertion.
*Resolution*: **Accepted — fixed in Round 1.** VE3 narrowed to I7 alone. Added: bats assertions
for the required `SKILL.md` tokens and the line bound; and a linter sub-check that every
front-matter key named in `SKILL.md`'s protocol clause is present in every phase file's front
matter, red-proven by renaming one key in the fixture.

**M9 [Major] [convergent: testing+functionality(adjacent)] The installed-layout run is neither hermetic nor a gate, and the zero-argument default-resolution path has no coverage**
The acceptance step runs `./install.sh` against the developer's real `~/.claude` (R31), the
`~/.claude/...` acceptance passes an explicit argument so it never exercises the self-relative
default, and no existing test invokes the hook with zero arguments — the form `settings.json:165`
permits and a human will actually run. Repo copy and installed copy are `cp -r` twins with only
one exercised (RT9).
*Resolution*: **Accepted — fixed in Round 1.** Replaced with a hermetic bats test modelled on
`tests/triangulate-rule-digest.bats:22-33`: stage the hook and the real skill dir under
`$BATS_TEST_TMPDIR`, `cd` elsewhere, invoke with **no argument**, assert exit 0 and `OK:`. The
real-`~/.claude` step is dropped from the plan; VE1's status table is corrected accordingly.

**M10 [Major] The C5 fixture repair as specified makes 8e's ordering semantics unfalsifiable**
"At least one `### Step N-M` heading per file" gives a one-element list, and no mutation of a
one-element list distinguishes an ordered comparison from a sorted-set or a count (RT1: the real
files carry 7/5/9).
*Resolution*: **Accepted — fixed in Round 1.** Fixture files get three step headings and
`steps: 3`; a second 8e fixture **permutes** `step_ids` (the unique mutation that reds an ordered
comparison and stays green under a sorted-set one); repeated tokens hoisted into `setup()`
variables (RT3).

**M11 [Major] I8's directory sweep and scenario S4 have no test; all seven fixtures pass a hard-coded-triple implementation**
Every proposed fixture mutates one of the three files a `for f in "$PHASE1" "$PHASE2" "$PHASE3"`
covers identically, so nothing distinguishes the sweep from the triple, and the first genuinely
new phase file is silently unchecked.
*Resolution*: **Accepted — fixed in Round 1.** Added the stray-file fixture: write
`$FIX/phases/phase-4-extra.md` with no manifest, assert exit 1 and the `phase-4-extra.md:
missing front matter block` drift line. It is the only assertion that red-proves I8.

**M12 [Major] The mutation-proof obligation is stated at the wrong granularity**
"Before the corresponding linter check is written" is ambiguous between check #8 as a whole and
each sub-check; under the whole-block reading all fixtures pass-when-they-should-fail
simultaneously and the observation carries no per-sub-check information. It would not have
surfaced M1, M2 or M10.
*Resolution*: **Accepted — fixed in Round 1.** Restated as per-sub-check ablation: comment out
sub-check 8x alone, run `bats tests/check-rule-sync.bats`, confirm fixture 8x goes green **and no
other fixture does**, restore, re-run. Run unpiped and read bats' own status (R44).

Note — the testing expert's F1 (8f not isolable by a single mutation, because mutating `end:`
also reds 8g) is **dissolved rather than fixed**: dropping the `end:` key per M1 removes
sub-check 8f entirely, so there is no longer a pair to collapse. Recorded here so the resolution
is traceable to the finding.

## Adjacent Findings

**Func F11 → testing scope**: installed-layout acceptance not reachable from `bats tests/`,
contradicting VE1. Routed to the testing expert, who reported the same issue independently and
in more depth (Test F7). Merged into **M9** per "Handling [Adjacent] Findings" rule 3.

**Sec F9 → testing scope**: unenforceable prose in the forbidden-pattern lists. The testing
expert did not report it separately; treated as a new finding from the testing perspective and
recorded as **M21**.

## Quality Warnings

None. No finding was flagged VAGUE / NO-EVIDENCE / UNTESTED-CLAIM: every finding above carries a
file:line citation into the real repo, and the security and testing experts executed their
bypasses (fenced-heading substitution, mid-file sentinel, baseline `bats` run) rather than
reasoning about them.

## Recurring Issue Check

### Functionality expert

- R1 (Shared utility reimplementation): [Checked — no issue] — C4 reuses the existing `drift()` helper and the existing script rather than adding a hook (N2).
- R2 (Constants hardcoded in multiple places): [Finding F1] — the `END-OF-PHASE-N` token is written in the front matter, the sentinel, `SKILL.md`, the linter, and the bats fixtures; the front-matter/sentinel pair is the collision that matters.
- R3 (Incomplete pattern propagation): [Checked — no issue] — the manifest/sentinel pattern is applied to 3 of 21 class members, but the remaining 18 are scoped out by ID in SC1/SC2 with cost-justifications (see F8 for the count).
- R4 (Event/notification dispatch gaps): [N/A — no event or notification dispatch in this change]
- R5 (Missing transaction wrapping): [N/A — no transactional storage]
- R6 (Cascade delete orphans): [N/A — no deletes]
- R7 (E2E selector breakage): [N/A — no E2E layer in this repo]
- R8 (UI pattern inconsistency): [N/A — no UI]
- R9 (Transaction boundary for fire-and-forget): [N/A — no async dispatch]
- R10 (Circular module dependency): [N/A — shell/markdown, no module graph]
- R11 (Display group ≠ subscription group): [N/A]
- R12 (Enum/action group coverage gap): [Checked — no issue] — 8a–8g cover each declared invariant I1–I6 plus the delimiter check.
- R13 (Re-entrant dispatch loop): [N/A]
- R14 (DB role grant completeness): [N/A — no database]
- R15 (Hardcoded environment-specific values in migrations): [N/A — no migrations]
- R16 (Dev/CI environment parity): [N/A — no CI exists in this repo; VE1 states this correctly]
- R17 (Helper adoption coverage): [Checked — no issue] — C4 mandates the existing `drift()` reporting shape.
- R18 (Config allowlist / safelist synchronization): [Checked — no issue] — verified `settings.json:165-166` already permits both the bare and `*`-argument forms of `check-rule-sync.sh`; no settings edit needed, as Consumer H claims.
- R19 (Test mock alignment with helper additions): [N/A — no mocks; the bats fixture is a real file tree]
- R20 (Multi-statement preservation in mechanical edits): [Checked — no issue] — the C1/C2 edits are prepend/append, not in-place rewrites.
- R21 (Subagent completion vs verification): [Checked — no issue] — this plan is itself a control against the subagent/orchestrator completion-vs-verification gap; C3's reconciliation obligation is the mitigation, and VE3 states honestly that it is unverifiable.
- R22 (Perspective inversion for established helpers): [Checked — no issue]
- R23 (Mid-stroke input mutation in UI controls): [N/A — no UI]
- R24 (Single migration mixing additive + strict constraint): [N/A — no migrations]
- R25 (Persist / hydrate symmetry): [Checked — no issue] — the declaration→body direction is enforced by 8d/8e; the reverse direction (body→declaration) is the same comparison.
- R26 (Disabled-state UI without visible cue): [N/A — no UI]
- R27 (Numeric range hardcoded in user-facing strings): [Checked — no issue] — C3's `wc -l ≤ 53` is a plan-local acceptance figure, not a shipped user-facing string.
- R28 (Grammatical inconsistency in toggle/switch labels): [N/A — no labels]
- R29 (External spec citation accuracy): [Finding F10] — the `install.sh:227` citation does not support the claim it is offered for. All other in-repo line citations I spot-checked are accurate (`phase-3-review.md:51`/`:56-58`, `check-rule-sync.sh:63-65`/`:109-125`/`:224-240`, `tests/check-rule-sync.bats:4-9`/`:16-22`, `install.sh:225-235`, `settings.json:165-166`, `retrospect/SKILL.md:39-52`).
- R30 (Markdown autolink footguns in citations): [Checked — no issue]
- R31 (Destructive operations without explicit user confirmation): [Checked — no issue] — the only destructive step is `./install.sh`, pre-existing; see F11 for the real-`$HOME` concern.
- R32 (New long-running runtime artifact without boot smoke test): [N/A — no runtime artifact]
- R33 (CI config change applied to one config but not its duplicates): [N/A — no CI configs]
- R34 (Pre-existing bug deferred without Anti-Deferral cost-justification): [Checked — no issue] — SC1, SC2, SC3 and VE3 each carry an explicit cost-justification and named owner.
- R35 (Production-deployed component without manual test plan): [Checked — no issue] — the Testing-strategy section names the manual installed-layout run; see F11 for its verifiability.
- R36 (Static-analysis warning suppression as substitute for fix): [Checked — no issue]
- R37 (Internal implementation jargon in user-facing strings): [Checked — no issue] — the 8a–8g `DRIFT:` messages name the file, key, and both values.
- R38 (Async state machine: non-terminal state + fail-open supersession): [N/A — no state machine]
- R39 (Lifecycle secret/metadata zeroization): [N/A — no secrets]
- R40 (Cross-boundary serialization shape vs strict consumer): [Finding F4] — the front matter is a serialization crossing into a potential strict consumer (any YAML parser), and the unquoted `title:` value is invalid in that shape.
- R41 (Declared capability without a working backing path): [Findings F1, F3] — the plan declares the capability "a partial read is self-detecting"; on the channel that produced the reported failure the backing path does not deliver the manifest (F3), and the completeness check it does deliver can answer wrongly (F1).
- R42 (Class-membership derivation): [Finding F8] — re-derived from `find skills -type f`: the in-scope class `skills/triangulate/phases/*.md` is exactly {`phase-1-plan.md`, `phase-2-coding.md`, `phase-3-review.md`}, matching I5, and C4's directory sweep correctly generalizes past the fixed `PHASE1/PHASE2/PHASE3` triple. The wider "pointer-loaded skill sub-file" class is miscounted (21, not 20) and `skills/agent-review/schemas/review-output.schema.json` is neither in scope nor scoped out by ID.
- R43 (Fix-induced security-boundary widening): [N/A — no security boundary is moved]
- R44 (Gate exit status read through a lossy or identity-less channel): [Checked — no issue for the gate itself] — C4 keeps the 0/1/2 exit contract and the plan's acceptance runs `bash hooks/check-rule-sync.sh` unpiped. Note the plan's *subject* is a lossy read channel, which is the R44 concern applied to content rather than status; F3 covers that.
- R45 (Repo-wide gate scaling super-linearly): [Checked — no issue] — check #8 iterates 3–4 files with a constant number of `sed`/`grep` passes each.
- R46 (Scope-blind binding resolution in a security analyzer): [N/A — not a security analyzer]

### Security expert

- R1 (Shared utility reimplementation): [Checked — no issue; C4 reuses the existing `drift()` helper and adds no new script (N2)]
- R2 (Constants hardcoded in multiple places): [Checked — no issue; the `END-OF-PHASE-N` literal is derived from `phase:`/filename, not re-hardcoded per check]
- R3 (Incomplete pattern propagation): [Finding F1, F2 — the `## END-OF-ANALYSIS` discipline at `phase-3-review.md:56-59` (anchored `^## …$`, tail-bound) is propagated to C2/C3 in a weakened form: unanchored containment, no uniqueness]
- R4 (Event/notification dispatch gaps): [N/A — no event dispatch]
- R5 (Missing transaction wrapping): [N/A — no transactional store]
- R6 (Cascade delete orphans): [N/A]
- R7 (E2E selector breakage): [N/A — no E2E layer]
- R8 (UI pattern inconsistency): [N/A]
- R9 (Transaction boundary for fire-and-forget): [N/A]
- R10 (Circular module dependency): [Checked — no issue; check #8 adds no new inter-file dependency]
- R11 (Display group ≠ subscription group): [N/A]
- R12 (Enum/action group coverage gap): [Checked — 8a-8g cover the six declared keys; the gap is the *unlisted* uniqueness check, reported as F2]
- R13 (Re-entrant dispatch loop): [N/A]
- R14 (DB role grant completeness): [N/A]
- R15 (Hardcoded env values in migrations): [N/A]
- R16 (Dev/CI environment parity): [N/A — no CI by declaration (VE1); bats is the sole gate]
- R17 (Helper adoption coverage): [Checked — no issue; the new block is specified to use the existing `drift()` helper]
- R18 (Config allowlist synchronization): [Checked — no issue; `settings.json:165-166` already permits both the bare and `*`-argument forms, verified; no new entry needed]
- R19 (Test mock alignment with helper additions): [N/A — no mocks; fixtures are real files]
- R20 (Multi-statement preservation in mechanical edits): [N/A]
- R21 (Subagent completion vs verification): [Checked — no issue; the originating failure is R21-shaped (Step 3-3 replaced by inline self-review) and C1's `core:` no-substitute clause is the intended mitigation — though F3 shows `core:` is presence-only and does not yet bind]
- R22 (Perspective inversion for established helpers): [N/A]
- R23 (Mid-stroke input mutation): [N/A]
- R24 (Migration mixing additive + strict constraint): [N/A]
- R25 (Persist/hydrate symmetry): [N/A]
- R26 (Disabled-state UI without cue): [N/A]
- R27 (Numeric range hardcoded in user-facing strings): [Checked — `wc -l ≤ 53` in C3's acceptance criteria is a magic number, but it is a plan-level bound, not a shipped user-facing string]
- R28 (Grammatical inconsistency in toggle labels): [N/A]
- R29 (External spec citation accuracy): [N/A — this review cites no external standard; all citations are repo-internal and were opened and verified]
- R30 (Markdown autolink footguns): [Checked — no issue]
- R31 (Destructive operations without confirmation): [N/A — the change adds no destructive operation]
- R32 (Long-running runtime artifact without boot smoke test): [N/A — no runtime service]
- R33 (CI config change not applied to duplicates): [N/A — no CI configuration exists]
- R34 (Deferral without Anti-Deferral cost-justification): [Checked — SC1/SC2/SC3 and VE3 each carry cost, alternative, and owner. SC2's justification is *present but factually wrong*, reported as F5]
- R35 (Production-deployed component without manual test plan): [Checked — no issue; the testing strategy names the live-repo and installed-layout runs]
- R36 (Static-analysis warning suppression): [N/A]
- R37 (Implementation jargon in user-facing strings): [Checked — no issue; the `DRIFT:` messages in 8a-8g name file, key, and both values]
- R38 (Non-terminal state / fail-open supersession): [Checked — no async state machine; the fail-open analysis is reported as F1, F2, F3, F7]
- R39 (Lifecycle secret zeroization): [N/A — no secret material]
- R40 (Cross-boundary serialization vs strict consumer): [Checked — Consumers C/D/E verified: `install.sh:227-235` copies `cp -r` verbatim, the skill loader reads front matter from `SKILL.md` only, and the digest generator reads `common-rules.md` only. The plan's inertness claim holds]
- R41 (Declared capability without a working backing path): [Finding F2, F9 — C2 declares a uniqueness constraint and C3 declares four acceptance criteria, none of which has a backing check in C4's 8a-8g or a fixture in C5]
- R42 (Class-membership derivation): [Finding F5 — the in-scope member set (3 phase files) is correctly code-derived, but the deferred class in SC2 omits `common-rules.digest.md`, the one whole-file-read member whose truncated tail is RS1-RS6]
- R43 (Fix-induced security-boundary widening): [Checked — no issue; check #8 adds no recipient, permission, or path grant. `settings.json` is unchanged, verified]
- R44 (Gate exit status read through a lossy channel): [Finding F8 — an `exit 2` in the new block would replace an accumulated `fail=1` from checks 1-7, and only `exit 0` is forbidden]
- R45 (Gate scaling super-linearly with the scanned set): [N/A — the sweep is 3 files of ≤ 524 lines; no timeout risk]
- R46 (Scope-blind binding resolution in a security analyzer): [Finding F3 — 8d/8e resolve `### Step` headings without fence scope, so a fenced decoy reads as a legitimate step (fail-open). Note: R46's own rubric rates this Critical when a fake reads as legitimate; I have rated F3 **Major** because it does not meet this review's Critical bar (RCE / auth bypass / injection / data exposure). Implementers may reasonably treat it as Critical under R46]
- RS1 (Timing-safe comparison): [N/A — no secret comparison; the linter compares public metadata]
- RS2 (Rate limiter on new routes): [N/A — no network surface]
- RS3 (Input validation at boundaries): [Finding F6 — the linter parses contributor-controlled files; the trust boundary is the front-matter block, and the plan never bounds the parse range]
- RS4 (Personal-identifying data in committed artifacts): [Checked — no issue; the front-matter fields are phase number, title, step count, step IDs, and a sentinel name. No paths, hostnames, or identifiers]
- RS5 (Untrusted security parameter without floor/whitelist): [Checked — `phase:` and `steps:` are attacker-influenceable but are compared against code-derived values (filename, heading count) rather than trusted; F3 is the case where that derivation is itself weak]
- RS6 (Incomplete sanitization — escape ordering): [Checked — no issue; drift values reach `printf '%s'` in `drift()`, not an interpolation sink. No shell/HTML/SQL sink is introduced]

### Testing expert

- R1 (Shared utility reimplementation): [Checked — no issue; C4 reuses the existing `drift()` helper and joins the existing linter rather than adding a script]
- R2 (Constants hardcoded in multiple places): [Finding F6 — `END-OF-PHASE-<N>` and the front-matter key names live in four places (phase file front matter, phase file terminator, linter, SKILL.md prose); only three are cross-checked]
- R3 (Incomplete pattern propagation): [Checked — no issue; SC1/SC2 defer the retrospect and rule-details classes with Anti-Deferral cost-justifications, and the triangulate class is swept whole]
- R4 (Event/notification dispatch gaps): [N/A — no dispatch surface]
- R5 (Missing transaction wrapping): [N/A — no datastore]
- R6 (Cascade delete orphans): [N/A — no datastore]
- R7 (E2E selector breakage): [N/A — no E2E layer]
- R8 (UI pattern inconsistency): [N/A — no UI]
- R9 (Transaction boundary for fire-and-forget): [N/A]
- R10 (Circular module dependency): [N/A — flat shell/markdown]
- R11 (Display group ≠ subscription group): [N/A]
- R12 (Enum/action group coverage gap): [Finding F1, F2 — the sub-check set 8a–8g is the enum; 8a's second variant and 8f's isolation are the uncovered members]
- R13 (Re-entrant dispatch loop): [N/A]
- R14 (DB role grant completeness): [N/A]
- R15 (Hardcoded environment-specific values in migrations): [N/A]
- R16 (Dev/CI environment parity): [Finding F7 — no CI exists, but this repo's equivalent second surface is the installed `~/.claude` layout, which no test exercises]
- R17 (Helper adoption coverage): [Checked — no issue; the new block uses `drift()` and the existing `DRIFT:` format, keeping Consumer G's contract intact]
- R18 (Config allowlist / safelist synchronization): [Checked — no issue; `settings.json:165-166` already permits both the bare and `*`-argument invocation forms, verified]
- R19 (Test mock alignment with helper additions): [Checked — no issue; C5 correctly binds the `setup()` fixture repair to C4 as a hard coupling rather than a follow-up]
- R20 (Multi-statement preservation in mechanical edits): [N/A]
- R21 (Subagent completion vs verification): [N/A at plan stage — applies to Phase 2 execution of this plan]
- R22 (Perspective inversion for established helpers): [N/A]
- R23 (Mid-stroke input mutation in UI controls): [N/A]
- R24 (Migration mixing additive + strict constraint): [N/A]
- R25 (Persist / hydrate symmetry): [Checked — no issue; `end:` is written in front matter and read at EOF, and 8g checks the pair]
- R26 (Disabled-state UI without visible cue): [N/A]
- R27 (Numeric range hardcoded in user-facing strings): [N/A — the ≤ 53 bound is an acceptance criterion, not a shipped string]
- R28 (Grammatical inconsistency in toggle labels): [N/A]
- R29 (External spec citation accuracy): [N/A — no external spec cited]
- R30 (Markdown autolink footguns): [N/A]
- R31 (Destructive operations without explicit user confirmation): [Finding F7 — the plan's installed-layout step runs `./install.sh` against the developer's real `~/.claude`]
- R32 (New long-running runtime artifact without boot smoke test): [Finding F7 — the installed-layout run is this change's boot-smoke analogue and is manual, not a gate]
- R33 (CI config change not applied to duplicates): [N/A — no CI configs exist]
- R34 (Pre-existing bug deferred without Anti-Deferral cost-justification): [Checked — no issue; SC1, SC2, and SC3 each carry an explicit cost-justification with an owner]
- R35 (Deployed component without manual test plan): [Checked — no issue; S1–S5 supply the scenarios, and C3's runtime residue is declared rather than assumed]
- R36 (Static-analysis warning suppression): [N/A]
- R37 (Internal jargon in user-facing strings): [Checked — no issue; the drift messages name file, key, and both values, matching the existing developer-facing style]
- R38 (Async state machine / fail-open supersession): [N/A]
- R39 (Lifecycle secret zeroization): [N/A]
- R40 (Cross-boundary serialization shape vs strict consumer): [Checked — no issue within testability scope; the Consumer A–E walkthrough covers the front-matter-at-byte-0 change, and the live-repo pass test is the standing gate]
- R41 (Declared capability without a working backing path): [Finding F3, F10 — C2's forbidden pattern is declared with no enforcing sub-check; I8's empty-glob rejection is declared but unreachable]
- R42 (Class-membership derivation): [Finding F4 — the phase-file member-set is correctly code-derived (3 members, step counts 7/5/9 verified), but the *executed-member-set sub-clause* fires on the sub-check set: nothing asserts all seven sub-checks actually run, so the sweep-vs-triple substitution is invisible]
- R43 (Fix-induced security-boundary widening): [N/A — Security expert's scope]
- R44 (Gate exit status read through a lossy channel): [Checked — no issue; existing bats reads `$status` from an unpiped `run bash "$SCRIPT" …` and the plan preserves that shape. Noted in F8 that the ablation runs must not be piped either]
- R45 (Gate scaling super-linearly with the scanned set): [N/A — three files, one pass each]
- R46 (Scope-blind binding resolution in a security analyzer): [N/A]
- RT1 (Mock-reality divergence): [Finding F5 — a one-step fixture resembles no real phase file (7/5/9 steps) and cannot exercise list ordering]
- RT2 (Testability verification): [Checked — no issue; every recommendation above is a bats assertion built from patterns already present in `tests/`, and I7 is correctly accepted as untestable — no model-replay harness proposed]
- RT3 (Shared constant in tests): [Checked — folded into F5's recommendation; the sentinel token and six key names would otherwise be retyped across `setup()` and eight `sed_i` scripts]
- RT4 (Race-test vacuous-pass guard): [N/A — no concurrency]
- RT5 (Test call-path must include the production primitive): [Checked — no issue; `tests/check-rule-sync.bats:13` invokes the real `hooks/check-rule-sync.sh`, no twin or stub]
- RT6 (Newly added production exports without test diff): [Checked — the seven sub-checks are the new surface and C5 pairs each with a fixture; the residual gaps are enumerated at F1, F2, F3, F4]
- RT7 (New guard / test / gate must be proven able to fail): [Finding F1, F2, F3, F4, F5, F8, F10 — see each]
- RT8 (Vacuous denial-path test): [Finding F1 — I12 correctly forbids status-only assertions, but the 8f fixture's residual vacuity is *attribution*: the drift substring is asserted while a second sub-check independently supplies the red]
- RT9 (Parallel-implementation twin drift): [Finding F7 — the repo copy and the `cp -r`-installed `~/.claude` copy are twins, and the suite exercises only the repo one]

---

# Round 2

Incremental review of plan revision 2. 25 findings (functionality 7, security 5, testing 13); all
accepted, none skipped. Three were established by **execution** rather than reading, and are
recorded as such below. Merge method: mechanical json-index join, as in round 1 (same deviation,
same reason).

## Round 2 — Functionality Findings

**N1 [Major] [convergent: functionality+security] C6 over-blocks `~/.claude/skills/improve/` with unfollowable remediation** (Func F4, Sec F12)
`~/.claude/skills/` is not a mirror of the repo: `install.sh:231-236` iterates
`$SCRIPT_DIR/skills/*/` and removes only the destinations it is about to write, so a skill absent
from the repo survives every install — and one does. Orchestrator-verified: `ls ~/.claude/skills/`
has ten entries, `ls skills/` has nine; the extra is `improve`, and `git log -- skills/improve` is
empty. Reusing the hook's existing "edit the repo and run `install.sh`" message for that path is
factually false, leaving the user two bad escapes (disable the hook wholesale, which also un-blocks
`.env`/credentials/`.git`; or use a Bash redirect, training the SC4 bypass).
*Resolution*: **Accepted — fixed in revision 3.** The skills arm gets its own message naming both
cases, and a fourth fixture pins the unmanaged-skill case. The alternative (enumerate the nine
repo-managed skill names in the case arm) was rejected on the axis that it fails open for every
newly added repo skill until someone updates the hook.

**N2 [Major] [convergent: functionality+security+testing] 8i's extraction grammar is unspecified and its fixture mutates the wrong side** (Func F1, Func F2, Sec F14, Test F4)
`SKILL.md` named its keys in two forms (bare `` `step_ids` ``, colon-suffixed `` `core:` ``), so
the natural colon-keyed extractor yields `{core}` only — silently dropping `step_ids` — while a
looser one yields `{read, cat, head, …}` and fires on the good file. Separately, the fixture
("rename a front-matter key") reds 8b and 8e independently, so 8i can never be isolated, and it
reds identically under a *hardcoded* key list — proving neither 8i's existence nor its derivation.
*Resolution*: **Accepted — fixed in revision 3.** C3 now mandates one canonical authoring form
(backticked, colon-suffixed) and defines 8i's extraction as exactly `` `[a-z_]\+:` `` over the
clause region; the fixture mutates the fixture `SKILL.md` only.

**N3 [Major] [convergent: functionality+testing] C7 gates the digest terminator's staleness but not its presence or position** (Func F3, Test F7)
`cmp -s` pins the committed digest to whatever the generator emits — including nothing. Delete the
`echo` and regenerate: both sides agree, `--check` exits 0, everything is green, and `SKILL.md`
now instructs every reviewer to look for a terminator that no longer exists. Moving the `echo`
above the awk pass is worse: the terminator lands mid-file, `cmp` still matches, and a reader
truncated past line 10 certifies a partial read as complete — the M1 bug reproduced in the digest
in the same revision that removed `end:` to fix it. (Testing expert executed the ablation and
confirmed the *staleness* half is not RT8-vacuous: removing the generator's `echo` makes the
stripped copy byte-identical, so the test genuinely fails. The gap is presence and position, not
attribution.)
*Resolution*: **Accepted — fixed in revision 3.** I26 adds last-non-empty-line and anchored-count
assertions on both the committed and the freshly generated digest, red-proven by moving the `echo`.

**N4 [Major] [adjacent → testing] The ablation procedure's "and no other fixture does" clause is unsatisfiable for several fixtures** (Func F5, Test isolation matrix)
Four fixtures necessarily trip more than one sub-check, and the plan never stated whether an 8a
failure short-circuits the rest for that file — a contract question that decides whether four of
the fixtures isolate or cascade.
*Resolution*: **Accepted — fixed in revision 3.** 8a is declared to gate 8b-8i per file (8j is
per-run); the C5 matrix now derives "also reds" for every fixture and marks the two inherently
multi-trip ones (`fence`, `8j`) rather than weakening the clause globally.

**N5 [Minor] C6's literal-tilde arm was specified with the wrong pattern and had no fixture** (Func F6, Test F9)
r2 said to add `"$HOME/.claude/skills/"*` to *both* arms; in the literal arm
(`block-sensitive-files.sh:79`, which matches an un-expanded `~/`) that is a no-op duplicate.
`tests/block-sensitive-files.bats` gives every covered path class a fixture per arm.
*Resolution*: **Accepted — fixed in revision 3.** The literal pattern is written out, and the
acceptance criteria list four fixtures (HOME deny, tilde deny, unmanaged-skill deny, repo-path
approve).

**N6 [Minor] `SKILL.md:45` contradicts C2/C3 after the change** (Func F7)
"Each phase file ends with a summary and a pointer to the next phase" vs. "the last line must be
the terminator" — two statements about how a phase file ends, in the one file the design treats as
standing truth.
*Resolution*: **Accepted — fixed in revision 3.** The sentence is amended in the same edit as C3.

## Round 2 — Security Findings

**N7 [Major] 8h's uniqueness check is evaded by terminator decoys the reader cannot distinguish** (Sec F10) — *executed*
Against the revision-2 spec, three of four decoys passed the strict anchored uniqueness count
while remaining fully legible as a terminator: trailing space, ≤ 3-space indent (still a valid ATX
heading), and U+2010 hyphens. The CRLF case was caught only by GNU grep's `$` tolerance, which the
repo's BSD-portability commitment (I18) does not guarantee. This restores the exact attack M2 was
accepted to close.
*Resolution*: **Accepted — fixed in revision 3.** 8h is split: strict anchoring for presence and
last-line (matching the `END-OF-ANALYSIS` precedent), and a deliberately **loose** second scan
(8h.4) for uniqueness — any non-final line containing the stem case-insensitively after stripping
whitespace, `\r`, and unicode dashes is drift. Over-approximating what a reader might mistake for
a terminator is the fail-closed direction. `\r` is normalized explicitly rather than relying on
grep semantics.

**N8 [Major] I13's fence toggle misses indented fences, restoring the fenced-heading bypass** (Sec F11) — *executed*
`phase-2-coding.md` has 10 indented fences and `phase-1-plan.md` has 2 (orchestrator-verified:
`grep -cE '^[[:space:]]+```'` → 2 / 10 / 0, all balanced list-item blocks, none nested inside a
column-0 fence). A column-0-anchored toggle never fires on them, so a real `### Step` heading moved
into an indented fence leaves 8d, 8e, 8g and 8h passing while the instruction is gone.
*Resolution*: **Accepted — fixed in revision 3.** I15 specifies the anchor literally as
`^[[:space:]]*` + triple backtick, records that the tolerant toggle yields the identical 7/5/9 on
the real files (so no regression), adds an unbalanced-fence-at-EOF tripwire, and the `fence`
fixture now uses an indented fence.

**N9 [Minor] The gate verifies the heading skeleton, not step bodies; I13's rationale overstated this** (Sec F13)
Emptying Step 3-3's body, or rewriting it to permit inline self-review, leaves every check green.
*Resolution*: **Accepted — fixed in revision 3.** Recorded as constraint `VE4` and the rationale
narrowed: fence awareness closes the heading-relocation variant only. No further sub-check is
proposed — prose semantics are I9/VE3 territory, and an "each step section has ≥ 1 non-blank line"
check would catch outright emptying but not a rewrite, and must not be sold as if it did.

## Round 2 — Testing Findings

**N10 [Major] The hermetic staged test as specified exits 1, not 0** (Test F6) — *executed*
Staging only `hooks/check-rule-sync.sh` plus the real skill dir produces
`DRIFT: common-rules.digest.md exists but digest generator is missing` and exit 1
(`check-rule-sync.sh:204-212`), because the real skill dir ships the digest. The tempting repairs
are both wrong: asserting `status -ne 2` hides it, and deleting the digest from the staged copy
silently drops check #7 from the installed-layout run — the opposite of what N3 asks for.
*Resolution*: **Accepted — fixed in revision 3.** C5 stages **both** hooks, which is also the
fidelity-correct shape since the installed layout contains both (RT9).

**N11 [Major] 8h had three clauses and two fixtures; the load-bearing clause had none** (Test F1)
Both listed fixtures attacked "exactly one match". Clause (iii) — *is the last non-empty line* —
is the reader's actual check, and a terminator that is present, unique and not last is exactly what
a truncated-tail write or an appended footer produces.
*Resolution*: **Accepted — fixed in revision 3.** `8h-wrongN` and `8h-notlast` added; the C5 matrix
maps every clause to an isolating fixture.

**N12 [Major] 8g had no isolating fixture** (Test F2)
`8g-fence` reds 8d and 8e, and reds 8g only if `core` happens to name the fenced step — never
specified. 8g's own failure mode (`core` naming a step not in `step_ids`) had no fixture, so an
implementation that parses `core` and forgets to compare it passes all 14.
*Resolution*: **Accepted — fixed in revision 3.** Fixture `8g` (`core: 1-1` → `core: 1-9`) added;
`8g-fence` relabelled `fence` and marked multi-trip.

**N13 [Major] Fence awareness is a measured no-op on the real files, so the pass path cannot distinguish a fence-aware implementation** (Test F3) — *executed*
`naive=7/5/9, fence-aware=7/5/9`. The fenced `###` lines cited are real but are
`### Functionality expert` and `##### MANUAL CHECKS`, none matching `^### Step N-M`. So both pass
tests are invariant under fence awareness and only one directional fixture proves it.
*Resolution*: **Accepted — fixed in revision 3.** A fenced `### Step 1-9` decoy goes into the
**base** `setup()` fixture, so every test in the file carries the assertion: a non-fence-aware
implementation counts 4 headings and both pass tests plus `8d`/`8e-sub`/`8e-perm` go red. Costs no
new `@test`.

**N14 [Major] The fixture `SKILL.md` repair was missing, leaving 8i without substrate** (Test F4)
`$FIX/SKILL.md` (`tests/check-rule-sync.bats:61-64`) is two lines containing none of the required
tokens, so 8j would fire on every test and 8i would **degrade open** — an empty derived key set
checks nothing and reports PASS, with its own fixture inert.
*Resolution*: **Accepted — fixed in revision 3.** C5's fixture repair now covers `$FIX/SKILL.md`,
and revision 3 records that the derived key set in the fixture is `{step_ids, core}`. Verified safe
against check #5's dangling-rule grep.

**N15 [Major] 8a/8b overlapped on empty values and I4's no-extra-key clause had no fixture** (Test F5)
C1 assigned the empty-value pattern to 8b while 8a's line-shape rule rejects it first, so the 8b
fixture red three sub-checks; and no fixture added a key, leaving I4 unproven.
*Resolution*: **Accepted — fixed in revision 3.** The empty-value case is assigned to clause 8a.3
explicitly; the 8b fixture becomes "insert a sixth key `extra: x`", which isolates 8b and
red-proves I4 at once.

**N16 [Major] The terminator token had no cross-file identity check** (Test F8)
8i pinned key names; the token itself lives in seven places and 8j only checked *containment*, so
renaming it in the phase files and the linter together keeps everything green while the reader is
told to expect a token nothing emits — and `END-OF-DIGEST-v2` satisfies containment while failing
the reader's exact match.
*Resolution*: **Accepted — fixed in revision 3.** I13/I28: `SKILL.md` is the single source of both
stems; 8h and C7's assertions compare against the extracted values by **equality**. Fixture `8j`
mutates the stem in the fixture `SKILL.md` only.

**N17 [Major] C6 covered one of two arms and lacked the lookalike negative** (Test F9)
See N5. Additionally the repo's own copy must stay editable — the entire "edit the repo, run
`install.sh`" workflow and this change's implementation depend on it — and a careless arm
(`*"/.claude/skills/"*`) would block it.
*Resolution*: **Accepted — fixed in revision 3.** Recorded as invariant I24 with the repo-path
approve fixture.

**N18 [Minor] `8h-dup`'s insertion point was unspecified and can collide with 8f** (Test F10)
The inserted line is itself a `^## ` heading; inserting it immediately after the front matter reds
8f, which compares `title` against the *first* `## ` heading.
*Resolution*: **Accepted — fixed in revision 3.** Insertion is specified as *after* the fixture's
first `## ` heading.

**N19 [Minor] The sweep fixture's expected drift string was stale; 8a sequencing unspecified** (Test F11)
This review file recorded `phase-4-extra.md: missing front matter block`, but revision 2's 8a
message shape is `<base>: malformed front matter block (<detail>)`.
*Resolution*: **Accepted.** Sequencing is fixed in revision 3 (8a gates 8b-8i); the stale string is
corrected here: the sweep fixture asserts the 8a drift substring for `phase-4-extra.md`, whose
exact text follows C4's message shape.

**N20 [Minor] C3's `wc -l ≤ 55` bound had no assertion** (Test F12)
*Resolution*: **Accepted — dropped in revision 3** rather than asserted. A line count is the wrong
instrument; I12's "no `### Step` enumeration in `SKILL.md`" is the content form, matching the
repo's own idiom at `tests/install.bats:285-295`.

**N21 [Minor] [adjacent → security] C6 extends the perimeter with no path normalization** (Test F13)
`block-sensitive-files.sh` matches `$FILE_PATH` literally, so `$HOME/.claude/../.claude/skills/…`
or a relative path from a cwd inside the tree evades every arm — the same way it evades the
existing arms. Commit `82449bb` shows the repo has treated this class as in-scope before.
*Resolution*: **Accepted — recorded, not fixed.** Folded into `SC4` alongside the
`Edit|Write|MultiEdit`-only wiring, with worst case / likelihood / cost / owner, so C6's fixture
set is knowingly bounded rather than accidentally so. Fixing path normalization in every arm is a
separate contract from adding one arm.

## Round 2 — Methodological finding, adopted

Both the testing expert's isolation matrix and the functionality expert's N4 converge on one
point: **per-sub-check ablation is near-automatic and therefore weak**. Because every fixture
asserts its own `DRIFT:` substring, removing sub-check 8x always removes that substring and always
fails its fixture. What it cannot surface is a *clause inside a sub-check with no fixture* — which
is how 8h's `N`-match and last-line clauses, 8g's binding, and I4's no-extra-key clause all reached
round 2 unproven. Revision 3 restates the obligation as **per-clause** ablation and states the
isolation matrix in the plan so it can be checked once rather than rediscovered per round.

## Round 2 — Recurring Issue Check

Round 1's per-expert sections are preserved above. Round 2's, verbatim, follow.

### Functionality expert (round 2)

- R1: [Checked — no issue] — C4 still joins the existing linter and reuses `drift()`; C7 adds one `echo` to the existing generator block; C6 adds a case arm to an existing hook. No new script.
- R2: [Checked — no issue] — resolved from r1. Dropping `end:` removes the front-matter/sentinel duplication; the expected token is derived from the filename in the linter and stated once in `SKILL.md`. C5 hoists the fixture tokens into `setup()` variables (RT3).
- R3: [Finding F3] — 8h is the pattern; C7 brings the digest into the same class but propagates only the emission, not the verification. Also [Finding F1] — the front-matter/`SKILL.md` key coupling is propagated as a sub-check without its extraction grammar.
- R4-R9: [N/A — no dispatch surface / no transactional storage / no deletes / no E2E layer / no UI / no async dispatch]
- R10: [Checked — no issue] — C7 adds no dependency.
- R11: [N/A]
- R12: [Finding F3] — 8a-8j is the enum over the new invariants; I22's digest-terminator presence is the member with no handler.
- R13-R15: [N/A — no dispatch / no database / no migrations]
- R16: [Checked — no issue] — r1's F11 is resolved; N3's second layout is a hermetic zero-argument bats run modelled on `tests/triangulate-rule-digest.bats:22-33`, verified to have that shape.
- R17: [Checked — no issue] — C4 uses `drift()`; C6 reuses the existing block message (see F4 for why reusing it *unchanged* is the problem, not reusing it at all).
- R18: [Checked — no issue] — `settings.json` unchanged. Verified `:165-166` covers both invocation forms and `:198-201` wires `block-sensitive-files.sh` to `Edit|Write|MultiEdit`, confirming I20.
- R19: [N/A — fixtures are real file trees, no mocks]
- R20: [Checked — no issue] — C2's trailing-`---` removal is a single-line delete; verified no test or hook depends on it.
- R21: [Checked — no issue] — `core:` is upgraded from presence-only to a real assertion (8g), the binding r1 lacked; I9 remains the declared unverifiable residue.
- R22-R24: [Checked — no issue / N/A]
- R25: [Checked — no issue] — with `end:` dropped there is no write/read pair left to desynchronize.
- R26: [N/A]
- R27: [Checked — no issue] — `≤ 55` and `line ≤ 10` are plan-local bounds, not shipped strings.
- R28: [N/A]
- R29: [Checked — no issue] — every r2 citation opened checks out: `block-sensitive-files.sh:73-82` (`~/.claude/skills/**` genuinely absent), `settings.json:200`, `generate-triangulate-rule-digest.sh:50-54`, `check-rule-sync.sh:206-212`, `phase-3-review.md:309,313,323`, `phase-2-coding.md:328,348`, `retrospect/pipeline.md:118`, `folding.md:91`, `tests/triangulate-rule-digest.bats:22-33`, `tests/check-rule-sync.bats:100/:247`. r1's bad `install.sh:227` citation is replaced by an empirical check.
- R30: [Checked — no issue]
- R31: [Checked — no issue] — the real-`~/.claude` `install.sh` acceptance step is dropped.
- R32-R33: [N/A]
- R34: [Checked — no issue] — SC1-SC4 each carry worst case / likelihood / cost / owner, and SC4 correctly records the Bash-redirect bypass as pre-existing.
- R35: [Checked — no issue] — S1-S6 cover the scenarios; the installed-copy path is guarded by C6 and exercised by C5's zero-argument run.
- R36: [N/A]
- R37: [Finding F4] — the C6 block message is user-facing and, reused unchanged, gives unfollowable recovery guidance for unmanaged skills.
- R38-R39: [N/A]
- R40: [Checked — no issue] — `title` is double-quoted, so the block is valid YAML for the first tool that treats it as such; loader inertness is measured rather than argued.
- R41: [Findings F1, F2, F3] — three declarations whose backing path does not work: 8i has no defined extraction, 8i has no isolating fixture, C7's terminator has no presence check.
- R42: [Checked for the in-scope class; Finding F4 for a class the plan did not derive] — the phase-file class is exactly three files and the SC1 class is 21 with the agent-review pointer targets excluded by ID. But C6 introduces a *new* universally-quantified control over `~/.claude/skills/*` whose member set was never derived from the installed tree; `ls` yields ten entries against nine in `skills/`, and the extra one (`improve`) is the member the remediation message does not fit.
- R43: [Checked — no issue] — C6 narrows rather than widens. SC4 correctly declines to widen the hook to `Bash`.
- R44: [Checked — no issue] — I15 forbids any `exit` inside the new block; verified the consumers it protects (`retrospect/pipeline.md:118`, `folding.md:91`). The ablation procedure requires reading bats' own unpiped status.
- R45: [Checked — no issue] — 3-4 files, one awk pass each.
- R46: [Checked — no issue] — I13's fence awareness closes the fenced-decoy path; premise verified real and all three files have balanced fences (26/12/32 backtick lines), so the awk toggle has a well-defined state.

### Security expert (round 2)

- R1: [Checked — no issue; C4 reuses `drift()`, C6 reuses the existing block message and case structure, C7 reuses the existing `cmp -s` staleness path rather than adding a verifier]
- R2: [Checked — materially improved since r1; dropping `end:` removes one of the four homes of the token, and C5 hoists the remaining fixture copies into `setup()` variables (RT3)]
- R3: [Finding F10, F11 — the `END-OF-ANALYSIS` discipline is propagated in the right anchored form for presence, but the uniqueness half was not given its own; and fence awareness is propagated to column-0 fences only, missing the 12 indented fences already in these files]
- R4-R9: [N/A — no dispatch surface / no transactional store / no deletes / no E2E / no UI / no async dispatch]
- R10: [Checked — no issue; C7 adds no new dependency, and check #7's call into the generator already exists]
- R11: [N/A]
- R12: [Checked — 8a-8j now cover every declared invariant; the r1 gap (uniqueness unlisted) is closed as 8h, though its pattern strength is F10]
- R13-R15: [N/A]
- R16: [Checked — no issue; the r1 non-hermetic `install.sh`-against-real-`$HOME` step is replaced by the staged zero-argument run, the right parity surface for this repo]
- R17: [Checked — no issue; C4 mandates `drift()`, C6 reuses `emit_block`]
- R18: [Checked — no issue; `settings.json:165-166` still covers both invocation forms and C6 adds no new wiring, only a case arm in an already-wired hook]
- R19: [N/A — no mocks; fixtures are real files]
- R20: [Checked — no issue; C7's change is one `echo` inside the existing `{ … } > "$TMP"` block, verified not to disturb the row-count guard at `generate-triangulate-rule-digest.sh:45-48`]
- R21: [Checked — no issue; `core` is upgraded from presence-only to a bound assertion (8g). F13 records that the binding reaches the heading, not the body]
- R22-R24: [N/A]
- R25: [Checked — no issue; the r1 `end:` write/read pair is gone]
- R26: [N/A]
- R27: [Checked — the `≤ 55` and `line ≤ 10` bounds are plan-local acceptance figures]
- R28: [N/A]
- R29: [Checked — no external standard cited. The one load-bearing in-repo citation was verified: `generate-triangulate-rule-digest.sh:50-54` is the `cmp -s` block I22 depends on. The CommonMark claims in F10/F11 are `citation unverified` as spec references, but the impact rests on executed byte-level results, not on the spec]
- R30: [Checked — no issue]
- R31: [Checked — resolved since r1; the `./install.sh`-against-real-`~/.claude` acceptance step is dropped]
- R32-R33: [N/A]
- R34: [Checked — no issue; SC1-SC4 and VE3 each carry worst case, likelihood, cost, and owner, with `TODO(...)` markers. SC4 correctly records the `Edit|Write|MultiEdit` gap as pre-existing]
- R35: [Checked — no issue; S1-S6 supply the scenarios and every gate is reachable from `bats tests/`]
- R36: [N/A]
- R37: [Finding F12 — the C6 block message is user-facing and, reused unchanged for the skills arm, gives remediation that cannot be followed for an unmanaged skill]
- R38: [Checked — no state machine; the fail-open analysis is F10, F11]
- R39: [N/A]
- R40: [Checked — no issue; `title` is double-quoted and Consumer D's premise is downgraded from a bad citation to a measured inventory check]
- R41: [Finding F10, F11 — 8h declares terminator uniqueness and I13 declares fence awareness; both backing paths are present but do not reach the cases their own rationales name]
- R42: [Checked — resolved since r1; the digest moved into scope as C7, the count corrected to 21, non-prose pointer targets excluded by ID. F11 is an R42-adjacent membership slip at a different level — the member set of "fence forms" is column-0 only while the corpus contains indented ones]
- R43: [Checked — C6 moves the boundary in the restrictive direction; the collateral of that restriction is F12]
- R44: [Checked — resolved since r1; I15 forbids any `exit`, and the ablation procedure requires reading bats' own status unpiped]
- R45: [Checked — no issue; 3-4 files, one `awk` pass each]
- R46: [Finding F11 — the fence toggle resolves `### Step` bindings against an incomplete notion of fence scope, so an indented-fence fake reads as legitimate (fail-open). Rated Major rather than R46's Critical since it does not meet this review's Critical bar; implementers may reasonably apply R46's rubric instead]
- RS1: [N/A — no secret comparison]
- RS2: [N/A — no network surface]
- RS3: [Checked — resolved since r1; 8a bounds the parse window positionally and 8b compares the exact key set. Verified the real `title:`/`core:` values satisfy `^[a-z_]+: .+$`]
- RS4: [Checked — no issue; front-matter fields carry no paths, hostnames or identifiers. `$HOME` in C6's case arm is expanded at runtime, not committed]
- RS5: [Checked — `phase`, `steps`, `step_ids`, `core` are compared against code-derived values rather than trusted; F11 is the case where the derivation itself is incomplete]
- RS6: [Checked — no issue; drift values reach `printf '%s'`, and C6 reuses `emit_block`, which JSON-encodes the reason via `jq -Rs` (`block-sensitive-files.sh:23-26`) rather than interpolating the path]

### Testing expert (round 2)

- R1: [Checked — no issue; C4 joins the existing linter and `drift()`, C6 reuses the block message and case structure, C7 adds one `echo`]
- R2: [Finding F8 — the terminator token spans seven sites and only some pairs are cross-checked; 8i fixed this for key names and stopped]
- R3: [Finding F7 — the anchored/unique/last-line discipline established in C2 and 8h is not propagated to C7's digest terminator, though the plan cites the correct prior art]
- R4-R11: [N/A — no dispatch surface / no datastore / no E2E / no UI / flat shell+markdown]
- R12: [Findings F1, F2, F5 — the clause set inside 8b, 8g and 8h is the enum; three clauses have no fixture]
- R13-R15: [N/A]
- R16: [Finding F6 — the repo-vs-installed parity test is specified in a form that cannot pass, verified by execution]
- R17: [Checked — no issue; C4 uses `drift()`, C6 reuses `emit_block`, and the C6 fixtures reuse `run_hook`]
- R18: [Checked — no issue; `settings.json:165-166` covers both invocation forms, and C6 needs no settings change since the hook is already wired at `:200`]
- R19: [Finding F4 — the `setup()` fixture tree is this suite's stand-in for the real skill dir, and its `SKILL.md` half was not updated alongside 8i/8j]
- R20: [Checked — no issue; C1/C2 are prepend/append plus one line deletion]
- R21: [N/A at plan stage — applies to Phase 2 execution]
- R22-R24: [N/A]
- R25: [Checked — no issue; with `end:` gone the declaration is in the front matter and the terminator derived from the filename, and 8d/8e/8h cover both directions]
- R26: [N/A]
- R27: [Checked — the `≤ 55` and `line ≤ 10` figures are plan-local bounds; see F12 for the unasserted one]
- R28: [N/A]
- R29: [Checked — no external spec. Re-verified `generate-triangulate-rule-digest.sh:50-54`, `check-rule-sync.sh:36`/`:45-50`/`:204-212`, `block-sensitive-files.sh:73-82`, `tests/check-rule-sync.bats:61-64`/`:100`/`:247`, `tests/triangulate-rule-digest.bats:22-33`, `settings.json:165-166`/`:200`. I13's fenced-heading citations point at real lines but at `### <expert>` and `##### MANUAL CHECKS`, none matching `^### Step N-M` — see F3]
- R30: [N/A]
- R31: [Checked — resolved; the real-`~/.claude` step is dropped]
- R32: [Finding F6 — the staged installed-layout run is this change's boot-smoke analogue and does not pass as written]
- R33: [N/A]
- R34: [Checked — no issue; SC1-SC4 and VE3 each carry worst case, likelihood, cost and owner. See F13 for one residual path not recorded]
- R35: [Checked — no issue; S1-S6 cover the scenarios and C1's loader-inertness check is empirical]
- R36: [N/A]
- R37: [Checked — no issue; the drift messages name file, key and both values]
- R38: [N/A — no state machine. The fail-open shapes present are 8i's empty-derived-key-set (F4) and unfixtured clauses (F1, F2, F5)]
- R39: [N/A]
- R40: [Checked — no issue within testability scope]
- R41: [Findings F1, F2, F5, F7 — I4's no-extra-keys clause, 8h's `N`-match and last-line clauses, 8g's `core` binding, and C7's `tail -1` acceptance criterion are each declared with no backing fixture]
- R42: [Checked — no issue on the phase-file class; membership re-derived as 3 files, counts re-verified 7/5/9, and the `sweep` fixture red-proves the directory sweep. The executed-member-set concern is now the clause-level gaps at F1/F2/F5]
- R43: [Checked — C6 widens a block perimeter (fail-safe direction); the one thing it must not widen into is the repo copy, which is F9's missing negative fixture]
- R44: [Checked — no issue; I15 forbids any `exit`, the ablation procedure is unpiped, and existing bats reads `$status` from a bare `run`. My own verification runs were unpiped]
- R45: [N/A — 3-4 files, constant passes each]
- R46: [Finding F3 — fence-scope resolution is specified but red-proven in one direction only, and is a measured no-op against the current files]
- RT1: [Finding F3, F4 — the repaired fixture matches the real files on step count and terminator, but still has no fenced block (every real phase file has several) and no loading-protocol clause in its `SKILL.md`]
- RT2: [Checked — no issue; every recommendation uses helpers already in `tests/` (`sed_i`, `run_hook`, the `$work/hooks` staging pattern). No model-replay harness proposed; I9 remains correctly classified unverifiable]
- RT3: [Checked — resolved; C5 hoists the terminator token and key names into `setup()` variables. F8 is the production-side counterpart]
- RT4: [N/A — no concurrency]
- RT5: [Checked — no issue; every fixture invokes the real `hooks/check-rule-sync.sh`, and the staged test copies the real hook rather than a twin]
- RT6: [Findings F1, F2, F5 — 8a-8j is the new surface; the sub-check level is covered, the clause level is not]
- RT7: [Findings F1, F2, F3, F5, F7, F9 — each is a declared check or case arm with no mutation that reds it. Methodological note: because I17 mandates a substring assertion, per-sub-check ablation always fails the target fixture, so the procedure is near-automatic; ablation should be run per *clause*]
- RT8: [Checked — no issue. On the coordinator's question: C7's fixture is **not** vacuous — traced `cmp -s` at `generate-triangulate-rule-digest.sh:50-54` and confirmed that ablating the generator's `echo` makes the staged copy byte-identical to the regenerated temp file, so the test fails. Attribution is adequate by construction even though the message is generic. Its real gap is positional, reported as F7]
- RT9: [Finding F6 — the staged installed-layout twin is the right fix but is specified with only one of the two hooks the real layout contains, which is a fidelity gap as well as a failing test]

---

# Round 3

Incremental review of plan revision 3. 21 findings (functionality 5, security 3, testing 13); all
accepted, none skipped. All three experts independently verified that every round-2 finding was
correctly resolved, and re-executed the round-2 empirical claims (indented-fence counts 2/10/0,
tolerant-toggle counts 7/5/9, balanced fence state at EOF, the single-hook staged run exiting 1) —
all reproduced.

**Round 3 is the last plan round.** The gate decision and its reasoning are recorded at the head of
the plan: every round-3 Major except one is an accounting error in the fixture isolation matrix,
which is a *prediction* of runtime behaviour, and the plan's own Testing strategy forbids asserting
such predictions before executing them. The matrix is carried into Phase 2 marked provisional; the
per-clause ablation runs settle it, with contradictions recorded in the deviation log.

## Round 3 — the one finding that changes the implementation

**P1 [Major] `$HOME` shape silently fails the whole hook open** (Sec F15) — *executed*
`block-sensitive-files.sh` interpolates `$HOME` unnormalized into its case patterns. With a
trailing slash the pattern becomes `…//.claude/…`, which never matches the single-slash path the
tool reports — the guard disappears with no error and no drift. With `HOME` unset, `set -euo
pipefail` (`:5`) kills the hook at the `case` line before any decision is emitted, taking down
*every* arm — `.env`, credentials, keys, `.git` internals, harness config — not just the new one.
None of C6's four fixtures could see either: they inherit the developer's ambient `$HOME`, so the
control's only silent failure mode is invisible to the tests written to prove it (RT7).
*Resolution*: **Accepted — fixed in revision 4.** `CLAUDE_HOME="${HOME:?}";
CLAUDE_HOME="${CLAUDE_HOME%/}/.claude"` introduced once and used by **all** arms — patching only
the new arm would be R3, since the three pre-existing arms carry the identical defect. A fifth C6
fixture invokes the hook with a trailing-slash `HOME`. SC4's enumeration notes this third weakness
as fixed here rather than deferred.

## Round 3 — design corrections

**P2 [Major] [convergent: functionality+testing] 8h.4 subsumes 8h.1 and 8h.3, so neither can be isolated** (Func F2, Test F1)
The loose scan's predicate — "any non-final line containing the stem" — is a superset of both
siblings by construction: an exact mid-file duplicate is necessarily non-final and contains the
stem, and a terminator that is not last becomes itself a non-final line containing the stem. Two
matrix cells claimed "also reds: —"; under per-clause ablation, 8h.1 and 8h.3 could never be
red-proven.
*Resolution*: **Accepted — fixed in revision 4 (I8e).** 8h.4 now excludes lines matching 8h.1's
strict pattern. The two options were weighed: marking the fixtures multi-trip (testing expert's
recommendation) preserves the loose superset but permanently exempts two clauses from the
acceptance criterion; making the clauses disjoint (functionality expert's) costs one negated
condition, keeps both diagnostics distinct ("duplicate terminator" vs "terminator lookalike"), and
loses nothing — a strict-form line is already 8h.1's case. The disjoint form was taken.

**P3 [Major] C3's clause shape contradicted its own authoring constraint; I28 was unachievable; empty-stem behaviour undefined** (Func F1)
The constraint said the stems appear as bare tokens while the clause body wrote them decorated, so
8j had nothing well-defined to extract. I28's "no literal in the linter" cannot hold either — the
linter must distinguish which extracted stem is the phase one and which the digest one, and only
the literals `PHASE`/`DIGEST` carry that. And an empty extracted stem makes 8h.4's containment test
match every line of every file.
*Resolution*: **Accepted — fixed in revision 4.** C3 gains one canonical declaration line as the
sole extraction target; I28 is restated to the obtainable property (the linter holds two role
anchors, every *comparison* uses extracted values); I29 makes a failed extraction drift with its
own message that short-circuits 8h for the run.

**P4 [Minor] 8h.4's normalization enumerated three evasions rather than closing the class** (Sec F16) — *executed*
A zero-width space inside the stem renders invisibly and evaded the whitespace/`\r`/dash
normalization.
*Resolution*: **Accepted — fixed in revision 4.** The scan is now structural: strip all
non-alphanumerics, case-fold, match `endofphase`. Verified by the expert to catch everything the
enumerated form catches plus ZWSP, and not to false-positive on the six real `END-OF-ANALYSIS`
occurrences. Letter homoglyphs are declared out of scope, resolved by the plan's drift-not-tamper
boundary — closing them needs transliteration, out of reach under the bash 3.2 / BSD constraint.

**P5 [Minor] [convergent: functionality+security+testing] Gating was specified by letter span, not dependency** (Func F3, Sec F17, Test F10, Test F11)
"8a gates 8b-8i" swept in 8h, whose inputs are the filename and `SKILL.md` — not the parsed window
the rationale cites. Intra-8a and intra-8h sequencing were also unspecified, leaving several matrix
cells implementation-dependent.
*Resolution*: **Accepted — fixed in revision 4.** Gating is restated by dependency: 8a gates
8b-8g and 8i; 8a.1 gates 8a.2 gates 8a.3; 8h runs unconditionally; 8h.1 gates 8h.2/8h.3; 8h.4 is
independent; 8j is per-run.

## Round 3 — matrix and coverage corrections

**P6 [Major] 8j had four properties and one fixture** (Test F4)
Ablate `Read`, the `END-OF-DIGEST` stem, or I12 and nothing goes red — the same shape 8h was
decomposed to fix one revision earlier, recurring in its sibling. I12 is the invariant that
justified dropping the `wc -l` bound, so that argument only held if I12 were enforced.
*Resolution*: **Accepted.** 8j decomposed into 8j.1-8j.4 with fixtures `8j-read`, `8j-phase`,
`8j-digest`, `8j-step`.

**P7 [Major] The `8j` deletion fixture could not red-prove the single-source property** (Test F5)
A hardcoded-literal implementation reds identically on deletion. Only *changing* the stem
separates the two implementations. The plan made exactly this argument for `8i` and did not carry
it to `8j`.
*Resolution*: **Accepted.** New fixture `8h-stem` changes the stem in the fixture `SKILL.md` only.

**P8 [Major] The digest-side stem equality had no fixture home** (Test F6)
`$FIX` carries no digest, so `check-rule-sync.sh:206`'s `[ -f "$DIGEST" ]` guard means check #7
never executes in any fixture test; and C7's assertions all compare against a hardcoded literal, so
none observes `SKILL.md`.
*Resolution*: **Accepted.** `$FIX` gains a generated digest — which also brings check #7 under
fixture coverage for the first time — and fixture `8j-digest` mutates the stem in the fixture
`SKILL.md`.

**P9 [Major] The fixture repair silently converts two existing tests into multi-trip fixtures** (Test F7)
`tests/check-rule-sync.bats:189` and `:196` append with `>>`, which after the repair lands *after*
the terminator, tripping 8h.3 and 8h.4. Both still pass on their substrings, but become
undocumented multi-trip fixtures. (`:203` appends to `$FIX/SKILL.md` and was verified safe.)
*Resolution*: **Accepted.** Both switch to a `setup()` helper that inserts before the terminator,
and C5 states the constraint explicitly.

**P10 [Major] The fenced decoy's ID and blast radius were both wrong** (Test F3, Test F8)
A fixed `### Step 1-9` decoy is inert in two of three fixture files under a filename-bound reading
of 8d; and the claimed blast radius named `8e-sub`/`8e-perm`, which the expert walked and showed
keep passing (their asserted 8e substring is present either way). The correct radius is the two
pass tests and `8d`.
*Resolution*: **Accepted.** The decoy is per-file `### Step <N>-9`; I14 is narrowed so `<N>` binds
8c and 8h only while 8d/8e use the generic ID pattern; the blast-radius sentence is corrected; and
a `decoy-off` matrix row is added so the I15 ablation run has a recorded expectation. This was a
"red-proves" claim written before execution — the exact thing the plan's own Testing strategy
forbids, and the reason the matrix is now marked provisional.

**P11 [Major] [convergent: functionality+testing] `8e-sub`'s and `fence`'s mutation targets were unpinned** (Func F4, Test F2)
Both collide with 8g if they happen to touch the `core` step, and the natural implementer choice —
the first ID — is the colliding one.
*Resolution*: **Accepted.** `8e-sub` substitutes the last ID; `fence` relocates the last step. The
matrix also records that the `8g` fixture is stronger than claimed: `<N>-9` exists only inside the
fenced decoy, so it exercises "resolves to a *counted* heading" as well as membership.

**P12 [Minor] 8i's "clause region" was undefined and the ambiguity invisible** (Func F5)
`SKILL.md` today contains zero backticked colon-suffixed tokens, so whole-file and region-scoped
extraction are indistinguishable and every test would pass either way — until the first unrelated
`` `paths:` ``-style token injects a phantom key and fires 8i on all three *good* files.
*Resolution*: **Accepted.** The region is the canonical declaration line only, and negative fixture
`8i-outside` is the sole assertion distinguishing a region-scoped extractor from a whole-file one.

**P13 [Minor] C7's uniqueness assertion had no mutation that reds it** (Test F9)
Moving the `echo` reds the position assertion; the count assertion stays green.
*Resolution*: **Accepted.** Duplicating the `echo` is named as the uniqueness mutation, with the
"record it as defence-in-depth, explicitly not mutation-proven" fallback (the I16 idiom) stated as
the acceptable alternative.

**P14 [Minor] C6's fixture 3 asserted the same thing as fixture 1** (Test F13)
With one arm and one message, adding a second path pins no second branch.
*Resolution*: **Accepted.** Fixture 3 now asserts the specific unmanaged-skill sentence with
`grep -qF`, matching `tests/install.bats:266`'s verbatim-pinning idiom.

## Round 3 — Recurring Issue Check

Each expert produced a complete R1-R46 (+RS/RT) block. Reproduced below are the entries that carry
a finding or a status change; runs of consecutive `[N/A — …]` entries for rules with no surface in
this change (R4-R9, R13-R15, R22-R24, R26, R28, R30, R32-R33, R36, R38-R39, RS1-RS2, RT4) are
collapsed rather than repeated verbatim across three experts for a third time. This is stated
rather than glossed: the collapse is a summary, not a verbatim preservation.

### Functionality expert (round 3)

- R2: [Finding F1] — I13/I28 make `SKILL.md` the single source of the stems, the right direction,
  but the linter cannot avoid holding the two role literals and the plan claims otherwise.
- R3: [Checked — no issue] — C7 now propagates the full presence/position/uniqueness triple from
  8h to the digest, not just the emission; the remaining asymmetry is stated rather than implicit.
- R12: [Findings F2, F3] — 8h.1 has no isolating member; 8h.2/8h.3's guard condition is undefined.
- R16, R17, R19, R20, R21, R25, R27, R29, R31, R34, R35, R37, R40, R42, R43, R44, R45, R46:
  [Checked — no issue] — with R29 re-verifying every r3 citation opened (`phase-3-review.md:430`,
  `tests/install.bats:285-295`, `check-rule-sync.sh:204-212`/`:224-240`/`:45-50`,
  `settings.json:165-166`/`:200`, `generate-triangulate-rule-digest.sh:50-54`,
  `retrospect/pipeline.md:118`, `folding.md:91`, `tests/check-rule-sync.bats:61-64`/`:100`/`:247`,
  `tests/block-sensitive-files.bats:6-18`/`:70`/`:81`/`:91`/`:96`/`:105`, `install.sh:231-236`,
  commit `82449bb`), and R46 confirming the indented-fence counts and the 7/5/9 no-regression.
- R38: [Finding F1] — an empty extracted stem is the one fail-open-shaped path left; 8h.4's
  containment test degenerates to "matches everything" rather than failing cleanly.
- R41: [Findings F1, F2] — 8j declares an extraction whose input form the clause shape does not
  provide; 8h.1 is declared red-proven by a fixture that cannot prove it.

### Security expert (round 3)

- R1, R3: [Finding F15] — the `$HOME` interpolation is repeated across three arms and C6 adds a
  fourth; the fix is one normalized variable, not four patched arms.
- R2: [Checked — resolved] — I13/I28 close the r2 containment gap.
- R12: [Finding F17] — 8a's gate range covers one member (8h) whose stated justification does not
  apply to it.
- R10, R16, R17, R18, R20, R21, R25, R27, R29, R31, R34, R35, R37, R40, R43, R44, R45, R46, RS3,
  RS4, RS6: [Checked — no issue] — R20 verifying C7's `echo` does not disturb the row-count guard
  at `generate-triangulate-rule-digest.sh:45-48`; R29 noting the CommonMark claims remain
  `citation unverified` as spec references while every impact claim rests on executed output;
  R43 confirming C6 moves the boundary restrictively and the repo copy is not matched; R46
  confirming the `^[[:space:]]*` anchor closes the indented-fence scope gap with a balanced EOF
  state on all three files.
- R38: [Finding F15] — the `$HOME`-shape and `$HOME`-unset paths are both fail-open supersessions
  of a path-authorization guard.
- R41: [Findings F15, F16] — C6 declares "the installed copy is guarded" with a backing path that
  disappears on a trailing-slash `$HOME`; I8d declares decoy resistance covering three enumerated
  forms rather than the class.
- R42: [Findings F15, F16] — two member-set gaps: SC4 enumerated 2 of 3 pre-existing hook
  bypasses, and I8d's normalization enumerated 3 of the reader-invisible-character class. The
  primary phase-file member set was re-verified correct.
- RS5: [Finding F15] — `$HOME` is an environment-supplied parameter consumed into a
  security-control pattern with no normalization or floor.

### Testing expert (round 3)

- R2: [Findings F5, F6] — the phase-side stem derivation is unproven and the digest-side
  comparison still uses a literal in the tests.
- R3: [Finding F4] — the 8h decomposition was not propagated to 8j, its sibling in the same table.
- R12: [Finding F4] — 8j's property set is the enum; three of four members have no fixture.
- R19: [Finding F7] — the repair changes the meaning of `>>` for two existing tests without
  recording it.
- R16, R17, R18, R20, R25, R27, R29, R31, R32, R34, R35, R37, R40, R43, R44, R45: [Checked — no
  issue] — R29 recording that I15's "12 indented fences (phase-2 10, phase-1 2)" measured exactly,
  and R32 that the staged dual-hook run is this change's boot-smoke analogue and was executed.
- R38: [Findings F5, F12] — an unproven derivation a hardcoded literal satisfies, and the
  empty-stem cascade.
- R41: [Findings F4, F5, F6, F9] — I12, I13, I28 and C7's uniqueness assertion are each declared
  with no mutation that reds them.
- R42: [Finding F4] — the executed-member-set concern now fires on 8j's property set, which the
  matrix treated as one member.
- R46: [Finding F8] — fence-scope resolution is regression-free (7/5/9) but the decoy that keeps it
  honest is portable under only one reading of 8d's pattern.
- RT1: [Checked — resolved] — the repaired fixture matches the real files on every axis the checks
  read; F8 concerns the decoy's ID, not its presence.
- RT2: [Checked — no issue] — every recommendation is a bats assertion or a one-line spec change
  using helpers already in `tests/`; I9 and VE4 remain correctly classified untestable.
- RT3: [Checked — resolved] — with the note that `8h-stem` must mutate the hoisted variable's
  source, not a retyped literal.
- RT5, RT8, RT9: [Checked — no issue] — RT8 recording that the r2 analysis of C7's staleness half
  (attribution adequate by construction despite a generic message) still holds; RT9 that the
  staged layout now matches what `install.sh` produces.
- RT6: [Findings F4, F6] — 8j's remaining properties and the digest-stem comparison are new
  surface with no test diff.
- RT7: [Findings F4, F5, F6, F9] — each a declared invariant with no mutation that reds it; F5 the
  sharpest, since its fixture reds identically under the implementation it is meant to exclude.

### Regressions found in round 3

None beyond P9. Explicitly checked and clear: removing the trailing `---` leaves fence balance even
(28/22/32) with the terminator outside the final fence; 8h.4 has no false-positive surface on the
real files; the front matter, both terminators and the C3 clause remain inert to checks
#3/#4/#5/#6; the three exit-2 tests still short-circuit at the preflight;
`tests/triangulate-rule-digest.bats:22-33`'s staged single-row source yields a digest whose last
line is the terminator, so C7's fresh-digest assertions are satisfiable there.

---

## END-OF-REVIEW
