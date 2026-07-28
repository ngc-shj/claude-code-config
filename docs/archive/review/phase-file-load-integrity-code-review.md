# Code Review: phase-file-load-integrity
Date: 2026-07-28
Review round: 1 (Phase 3)

## Changes from Previous Round

Initial code review. Phase 2 had already run a self-R-check with the same three roles, so this
round was scoped as incremental verification: confirm those eight fixes, then find what they
missed. Ollama seeds (Step 3-2) were skipped — the diff is large and every expert had the full
plan, deviation log and repo. Merge method: mechanical json-index join, as in Phase 1 (same
deviation, D6).

**Result: 9 findings — 2 Major (convergent), 7 Minor from functionality/security, plus 16 from
testing of which 5 Major. All fixed in-round except one, corrected-not-fixed with reasoning.**

## The convergent Major

**Func F1 == Sec S1 — the obligations were ungated.** Check 8 guaranteed the *metadata* (front
matter accurate, terminator unique and last, stems derived from `SKILL.md`) and verified almost
nothing about the three numbered obligations that turn that metadata into protection. Both
reviewers executed it independently:

- delete the "re-read on a missing terminator" and "reconcile against `step_ids`/`core`" sentences
  → linter prints `OK`;
- rename the terminator literals inside the protocol while leaving the declaration line intact →
  linter prints `OK`, and every reader is now told to look for a marker no file contains.

This is requirement F4's own shape — metadata nobody checks — in the one place the whole design
leans on. Per "Perspective Convergence as a Severity Signal" the floor is Major and it was fixed
first.

*Resolution*: **Fixed.** A `**Truncation protocol**` block is now bounded and asserted to name the
`Read` tool, both declared stems, and every declared manifest key; and no `END-OF-*` literal
anywhere in `SKILL.md` may name an undeclared stem (the phase-transition sentence repeats the
terminator and would otherwise go stale silently). The whole-file `Read` grep it replaced was
honest by accident — the fixture now mentions `Read` outside the block on purpose, so the scoping
is what the fixture proves.

## Functionality Findings

- **F2 [Minor] 8j.1's `Read` check was whole-file.** Backticking the bare `Read` in the Entry Point
  table — a plausible formatting edit — would have made it permanently vacuous. *Fixed with F1.*
- **F3 [Minor] The declaration line's parse contract was undocumented where it is authored**, and
  rewording it produced a diagnosis that contradicted the line ("declares no stem" for a line that
  declares one). *Fixed*: an HTML comment in `SKILL.md` states the line is machine-parsed by shape,
  and both stem-missing messages now carry the expected shape.
- **F4 [Minor] `skills/retrospect/folding.md` was not extended.** Its numbered sync-point list is
  the documented fold procedure, and two invariants this branch introduces were absent: inserted
  text must land above the terminator, and a new `### Step` obliges a front-matter update. *Fixed*:
  one bullet under item 6.
- **F5 [Minor] `phase-2-coding.md`'s `core:` deviates from the locked C1 literal** with no
  deviation entry. The shipped text is more accurate against Step 2-5's body and only the leading
  ID is bound. *Fixed*: recorded as D13.
- **F6 [Minor] The reconciliation left no trace.** *Fixed*: each phase's completion-report template
  gained a `Steps executed:` line. This does not make I9 verifiable — an agent can write it
  untruthfully — but it makes the omission visible in the committed artifact, which is the cheapest
  available narrowing of the gap this branch exists to close.

## Security Findings

- **S1** — see the convergent Major above.
- **S2 [Minor] The counted heading set was narrower than the readable set** (executed). Closing 0-3
  leading spaces left a tab-indented heading, one at 4 spaces inside a list item, and a blockquoted
  one uncounted — all still instructions a reader acts on, none of which would appear in
  `step_ids`, so the reconciliation would walk an under-declared manifest. *Fixed*: widening the
  counted anchor would start counting `### Step`-shaped lines inside legitimate indented code
  blocks, so a loose fail-closed scan refuses anything the strict anchor missed — the same
  strict-count / loose-refuse split 8h already uses. Verified no false positive on the real files
  (21 step headings, all column 0, all outside fences).
- **S3 [Minor] SC4(b)'s deferral was mis-costed and cited the wrong examples** (executed). The
  in-tree `..` form it named actually blocks; the forms that evade are `//`, `/./`, a dot inside the
  `$HOME` segment, `$HOME/.claude/../.claude/…`, a relative path, and a symlink alias. The cost is
  one canonicalization reusing `retro-prescreen.sh`'s `_containment_check` shape, not "normalizing
  every arm", and the likelihood assessment predates C6 making this hook the sole control over
  `~/.claude/{hooks,rules,skills}/**`.
  *Resolution*: **corrected, not fixed.** SC4(b) is rewritten with the executed forms, the real
  cost, and the post-C6 likelihood. The fix itself stays deferred, with that stated plainly: adding
  path canonicalization to a security hook this late would land without the review depth the rest
  of the branch received, and a deferral whose examples are wrong is the actual defect — a
  follow-up scoped to the old list would have closed nothing. Owner: next branch, before further
  work depends on this hook.
- Verified clean by execution: **R43** — every predicate the branch moves is restrictive;
  `settings.local.json`, `~/.claude/projects/*/memory/`, `~/.claude/todos/`, plugin hooks and every
  repo path still approve, and `install.sh` is unaffected (it writes via `cp` from Bash while the
  hook is wired to `Edit|Write|MultiEdit`). All five Phase 2 fixes re-probed, no regressions.

## Testing Findings

The testing reviewer enumerated **40 `drift` call sites from the code** rather than from any
written check list, ablated each, and found **5 with no red-proof** — plus five more implementation
choices and case-arm patterns. This is the highest-value result of the round, and the reason is
worth stating: three of the five are **pre-existing** clauses this branch did not touch, and they
survived every prior pass because each pass verified the set that was written down.

| Finding | Clause | Status |
|---|---|---|
| T1 Major | check 7 digest staleness — the generator's `cmp`, its exit 1, and the consuming clause were a chain no test could redden. This branch built the fixture digest that would make it provable, then regenerated it after every mutation. | **Fixed** — a fixture corrupts the digest only, so nothing co-fires |
| T2 Major | the `ALL_FILES` extra-phase sweep added by this branch | **Fixed** — two well-formed `phase-4` fixtures reaching checks 3 and 5, which the stray-file fixture never did |
| T3 Major | check 4's whole-family-absent branch — with the drift neutralised, deleting every `- RTn:` line exits **0** | **Fixed** |
| T4 Major | both of check 6's asymmetry branches (headers without pointer; pointer without headers) | **Fixed** — two fixtures |
| T5 Major | three literal-tilde arms (`CLAUDE.md`, `RTK.md`, `model-routing.md`), two added by this branch | **Fixed** — three fixtures; the code's member set was re-derived from `install.sh` and the fixture set was not |
| T6 Minor | `${HOME:?}` fail direction | **Fixed** — unset-`HOME` fixture asserting non-zero status and no approve |
| T7 Minor | the fence *balance counter* is a third anchor; only the scan toggle and heading anchor were proven | **Fixed** |
| T8 Minor | "digest generator is missing" | **Fixed** |
| T9/T10 Minor | one duplicate fixture; one test bundling two paths | **Fixed** — the duplicate now pins the message branch instead; the bundle split in two |
| T11 Minor | two exit-2 tests asserted status without identity, though three paths produce exit 2 | **Fixed** — `run -2 --separate-stderr` plus a stderr match |
| T12 Minor | three rationale comments no longer described the file, including one that would have kept T1 invisible | **Fixed** |
| T13 Minor | fixture/reality divergence on check 6's pointer-sentence grammar and the letter-suffixed step-ID branch | **Deferred** — see below |
| T14 Minor | nothing asserted the *installed* copy keeps its front matter and terminator | **Fixed** — `tests/install.bats` now stages `skills/triangulate/` and asserts both, plus the digest terminator |
| T15 Minor | README documents the hook as env/credential/lock/`.git` only | **Fixed** — the `~/.claude/` perimeter documented, including what stays editable and why |
| T16 Minor | recorded suite count stale | **Fixed** |

**T13, deferred with reasoning**: adding a letter-suffixed step ID (`1-3a`) to the base fixture
changes the step count and ID list every other fixture asserts against, rippling through roughly a
dozen expectations for one untested branch that no phase file currently exercises. The compound
pointer-sentence form is the cheaper half and is genuinely untested in the drift direction.
`TODO(phase-file-load-integrity): fixture the suffixed step-ID branch and check 6's compound pointer grammar`.

## Adjacent Findings

- `[Adjacent] Minor` (security) — `phase-3-review.md:59` declares a fourth terminator stem,
  `END-OF-ANALYSIS`, outside the declaration line the linter calls the single author of stems.
  Accepted as out of scope: it terminates *generated* Ollama output, not a skill file, and it
  predates this design. It does make the "single author" claim narrower than it reads; noted here
  rather than silently.
- `[Adjacent] Minor` (security) — this session lists `~/.claude/skills/triangulate` as an
  additional working directory, which C6 now blocks for `Edit`/`Write`. That is the intent (S7),
  the block message names both escapes, and the repo copy is where edits belong. Flagged for the
  user to confirm no workflow depended on editing the installed copy.
- `[Adjacent] Minor` (testing) — `tests/install.bats` skipped `skills/` deliberately for speed;
  this branch makes that skip load-bearing. Closed by T14 rather than left as an adjacency.

## Quality Warnings

None. Every finding in this round carries a file:line and an executed probe; the two Majors and
eight of the Minors were established by running the mutation, not by reading.

## Environment Verification Report

Per the plan's `Verification environment constraints`:

- `VE1` (no CI; every gate must be reachable from `bats tests/`) — **verified-local**.
  `bats tests/` → **866 tests, 0 failures**. `bash hooks/check-rule-sync.sh` → exit 0.
  The installed-layout path is covered hermetically (`stage_installed_layout`, zero-argument
  invocation) and by `tests/install.bats`'s new staged-`HOME` case; no test touches live `~/.claude`.
- `VE2` (Ollama soft dependency) — **not exercised**; untouched by this change.
- `VE3` (I9: the reader honours the instruction) — **blocked-deferred**, as predicted in Phase 1.
  Anti-Deferral justification unchanged (a model-replay harness with a nondeterministic oracle).
  What this round narrowed: the instruction can no longer *disappear* without the gate reddening,
  and its omission now leaves a visible hole in the completion report. The residue is a reader that
  reads the instruction and ignores it.
- `VE4` (step *content* is not gated) — **blocked-deferred** by declaration. Emptying a step body
  or rewriting it to permit inline self-review leaves every check green. Human diff review and I9
  cover it; no check is claimed that does not exist.

## Recurring Issue Check

All three reviewers produced a complete R1-R46 (+RS/RT) block. Reproduced below are the entries
carrying a finding or a status change; runs of consecutive `[N/A]` entries for rules with no
surface in a config-only shell/markdown change (R4-R9, R11, R13-R15, R23-R26, R28, R31-R33, R36,
R38-R39, RS1-RS2, RT4) are collapsed. Stated rather than glossed: the collapse is a summary, not a
verbatim preservation.

### Functionality expert

- R41 **Fail** → F1: SKILL.md declares three obligations; only the `Read` half had any backing
  check, and that one was scope-broken (F2).
- R42 **Partial**: I7's directory sweep is real and fixtured and `ALL_FILES` was reconciled with it,
  but 8j's clause set was derived from the plan's four sub-checks rather than from requirement F3's
  three obligations — which is how F1 survived Phase 2.
- R1, R2, R3, R16-R21, R27, R29, R30, R34, R37, R40, R43, R44, R45, R46: pass. R29 confirms the
  CommonMark 0-3-space rule cited in the linter is correct; R3 confirms the `$HOME` normalization
  and the `install.sh` write-set derivation were applied to all arms, not only the new one.
- Implementation Checklist cross-check: all 11 files present in the diff, no omissions.
- Contract conformance: all three Forbidden-pattern match sets empty.

### Security expert

- R2 → S1: the terminator literal appears three times in `SKILL.md` with only the stem pinned.
- R3, R34, R42, RS3 → S3: the containment-canonicalization pattern landed in three hooks on `main`
  and not in this one; SC4(b)'s cost half is wrong by roughly an order of magnitude.
- R41 → S1: the declared protocol's backing check covered the metadata, not the obligation.
- R43 **pass, verified by execution** — every moved predicate is restrictive and no legitimate write
  is broken (7-path approve matrix run).
- R12, R16-R18, R21, R29, R35, R44, R45, RS4, RS5, RS6: pass. R44 confirms no `exit` inside check 8,
  so real drift cannot be reported as exit-2. RS5 confirms `STEM_*` and `SKILL_KEYS` are constrained
  by regex before reaching `awk -v` / `grep`.

### Testing expert

- RT7 **principal result** → T1-T8: 5 of 40 `drift` clauses plus the `ALL_FILES` sweep, the balance
  anchor, `${HOME:?}` and three literal-tilde arms had no red-proof. All fixed and re-ablated.
- RT8 → T10, T11: one bundled test, two status-only exit-2 assertions. Fixed.
- RT1 → T13: two axes of fixture/reality divergence. One fixed, one deferred with a TODO.
- RT9 **pass** — `stage_installed_layout` remains a faithful `cp -r` twin of `install.sh:233-235`;
  the gap was one level up (T14) and is closed.
- R19 → T14/T15: `tests/install.bats` was the only other tree referencing a changed hook; its skip
  of `skills/` became load-bearing and is now closed.
- R34 → T3, T4, T8: five pre-existing unproven clauses in files in the diff, each a one-line fixture,
  so deferral was not cost-justified. All fixed.
- R41 → T1-T4, T8. R42 → T5 (the code's member set was re-derived; the fixture set was not).
- R1, R10, R12, R16-R18, R20, R21, R29, R30, R35, R37, R40, R43, R44, R45, R46, RT2, RT3, RT5, RT6:
  pass. R44 notes the reviewer discarded a first full-suite run that had been piped to `tail` and
  re-ran it unpiped — the same discipline the rule asks of the code.

## Resolution Status

Every finding above is either fixed in-round or carries an explicit disposition. Two entries use
the Anti-Deferral format:

### S3 [Minor] SC4(b) path-canonicalization bypass — Accepted (corrected, fix deferred)
- **Anti-Deferral check**: acceptable risk, quantified.
- **Justification**:
  - Worst case: an agent that constructs a `~/.claude/**` path with `//`, `/./`, an intermediate
    `..`, a relative prefix or a symlink alias edits an installed harness file that `install.sh`
    would silently revert. No credential or privileged operation is exposed; the hook is
    defence-in-depth over a convention.
  - Likelihood: low. No workflow in this repo constructs such paths; the tool reports absolute
    canonical paths in normal operation. Raised from "low" by C6 making this hook the sole control
    over `hooks/lib/` and `rules/common/`, which is why the entry is rewritten rather than left.
  - Cost to fix: one canonicalization above the `case` reusing `retro-prescreen.sh`'s
    `_containment_check` shape, plus six deny fixtures and four re-asserted approves. Small in
    lines; the cost that decides the deferral is not lines but review depth — this is a security
    hook and the change would land after this branch's reviewers have finished.
- **Orchestrator sign-off**: acceptable-risk exception satisfied with all three values stated. The
  corrected entry, with the executed evading forms, is in the plan under SC4(b). Owner: next
  branch, before further work depends on this hook.

### T13 [Minor] Suffixed step-ID and compound pointer-sentence fixtures — Out of scope (tracked)
- **Anti-Deferral check**: out of scope (different feature), with a grep-able TODO.
- **Justification**: adding `1-3a` to the base fixture changes the step count and ID list that
  roughly a dozen other fixtures assert against, for a branch no phase file currently exercises.
  Tracked as `TODO(phase-file-load-integrity): fixture the suffixed step-ID branch and check 6's
  compound pointer grammar` in this file and in the deviation log.
- **Orchestrator sign-off**: TODO marker present and grep-able; no silent drop.

---

## END-OF-CODE-REVIEW
