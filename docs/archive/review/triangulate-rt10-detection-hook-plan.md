# Plan: Mechanical detection hook for RT10

Date: 2026-07-28
Status: Phase 1 — plan review, round 4 (round 3 findings folded)

**Split rationale.** Rounds 1-2 reviewed RT10 and R50 together. The R50 half accumulated two new Criticals and three locked-contract redecisions, with each round's fix growing new surface — append became a truncation primitive, containment introduced TOCTOU, redaction introduced a dependency and a byte-transparency contradiction. That is the signature R47 and R42 clause ①b name: stop patching, change the mechanism. Its design state and ten open questions are preserved in `triangulate-r50-evidence-deferred.md`; nothing from it is implemented here.

## Project context

- **Type**: `mixed` — shell tooling (`hooks/`) plus markdown config (`skills/`, `rules/`), installed into `~/.claude/` by `install.sh`.
- **Test infrastructure**: `unit tests only` — `bats tests/`. Measured: **905** `@test` across 29 `tests/*.bats`, of which `tests/install.bats` holds **23**. **No CI/CD**; the authoritative gate is a local `bats tests/` run.
- **Verification environment constraints**:
  - `VC1` — no CI surface, so "wired into the authoritative gate" (RT7 shape b) can only mean *a bats test invokes it*. Shared by every `hooks/check-*.sh` in the repo (15 of them; see `SC5`).
  - `VC2` — no TS/JS sources exist in this repo, so the Jest/Vitest grammar cannot be exercised against production code *here*. It **is** exercised against a real 1022-file corpus on this machine (M-5); that corpus is not part of this repo, so the measurement is reproducible only where it exists, and the committed tests cover the grammar by fixture.

## Objective

Give RT10 a mechanical detector: flag a changed test file whose guard assertions are entirely deny-shaped, with no allow-shaped counterpart anywhere in the file.

## Requirements

1. Runs over `base-ref...HEAD`, per changed test file; never re-flags files the diff did not touch.
2. Ships a bats test that is red-provable, with each mutation named here and **executed** before the PR opens (RT7 + `feedback_mutation_execute_redproof_claims`).
3. Bash 3.2-compatible — no associative arrays, no `\b`/`\<` in awk ERE; follow the `AWK_WORD_START` convention in `check-vacuous-denial.sh`.
4. No new runtime dependency: `awk`/`sed`/`grep` only.
5. Complexity bounded against the full changed-file set (R45): one pass per changed file.
6. Every claim in a header comment, rule row, commit message, or **this plan** is calibrated to what the implementation proves (R49). **Any sentence beginning "Measured:" names the command that produced it and is reproducible.** Rounds 2 and 3 each falsified an unexecuted claim in this plan's own text — round 2 the guard-subject gate's suppression claim, round 3 mutation M5's discrimination rationale. Every number below was executed by the author of this revision.
7. **No untrusted string reaches a command as an operand in option position.** Filenames come from `git diff` over a repository under review and are attacker-controlled.

## Technical approach

One script, following the established detector shape (`set -u`, `mktemp -d` + `trap`, git-toplevel resolution, base-ref validity check exiting non-zero, diff `+`-line scoping, `EXTRA_*` knobs, a header carrying algorithm / severity / out-of-scope / usage).

| Script | Role | Control class (R49) |
|---|---|---|
| `hooks/check-deny-only-guard.sh` | RT10 detector | **detection only** — emits findings, exit 0 always; non-zero only for setup errors (not a git repo, invalid base-ref, malformed `EXTRA_*`) |

**Adjudication authority (R47).** No interpreter decides "is this test deny-only". The classification is a **bounded pattern set over three declared grammars**, and the bound is *measured* (M-2, M-5), not asserted. `SC1`–`SC7` name the remainder.

**Symmetric polarity.** Round 3 measured the round-2 grammar's central defect: its deny vocabulary carried general-purpose alternatives while its allow vocabulary was HTTP-status-shaped, so a file with 127 assertions and one `rejects.` fired. Two corrections, both measured (M-5, M-6):

- **The allow side is general, symmetric with the deny side.** For Jest/Vitest, an allow-shaped line is any line containing `expect(` that is not deny-shaped. This is what RT10 actually claims — "its tests exercise *only* rejected inputs" — so a file whose assertions are overwhelmingly non-deny must not fire.
- **Polarity is scored, not spelled.** A deny token under `.not.` is an allow assertion; an approve token under `!=` is a deny assertion. Matching the token without its operator is the R47 symptom one level down: the meaning is fixed by the surrounding test expression, which a bare substring never consults.

**No guard-subject gate.** Round 2 measured it dead (`run ` is bats' universal invocation idiom, present 5× in the very file it was meant to suppress). Dropped rather than reworded. Its purpose — suppressing false positives — is served by the symmetric allow side instead, which is measurably effective where the gate was not.

**Granularity.** File-level. Cost: a file holding one covered and one deny-only guard stays silent (`SC4`).

**Reuse (R1).** `hooks/tri-tmpdir.sh` is skill-facing (invoked from phase files, not hooks); the `awk /^@@/ … RSTART + 1, RLENGTH - 1` added-line extractor is three lines inside a longer awk program, present in exactly 9 hooks, and this is the tenth — extracting three lines would not reduce the surface. Note the repo *does* have a library-load convention (`hooks/lib/ast-signature.sh` is sourced by `check-propagation.sh:64`; `install.sh:117-138` provisions `hooks/lib/`), so the disposition rests on the size of the duplication, not on its absence.

## Measured facts

Every number was produced by the command shown, at `3014e77`, clean worktree.

**M-1 — corpus size.** `ls tests/*.bats | wc -l` → **29**. `bats --count tests/` → **905** (cross-checked: `grep -h '^@test' tests/*.bats | wc -l` → 905). `grep -c '^@test' tests/install.bats` → **23**.

**M-2 — the bats rule over the whole tree.** Three grammars, `#`-stripped, file-level, polarity-scored, every line treated as added: **exactly one** fire — `tests/llm-commands.bats deny=4 allow=0`. All seven `tests/block-*.bats` are silent (`block-sensitive-files.bats`: deny=47 allow=22). Re-measured with the polarity correction (`!= …approve` scored deny and excluded from allow): **unchanged**, still exactly that one file. The polarity fix is therefore behavior-preserving on this corpus and closes a latent silence (a suite asserting blocking *only* via `!= approve` would otherwise score deny=0/allow=1 and never fire).

**M-3 — the one bats fire is a false positive.** `tests/llm-commands.bats` lines 214/224/230/236 assert a CLI's usage-error exit; its happy paths use `result=$(...)` with `[[ "$result" == … ]]`, which no declared grammar sees. Recorded as `SC1`.

**M-4 — fixture collection.** Verified by execution, not by `--help`: a scratch tree with `tests/one.bats` and `tests/fixtures/x.bats` gives `bats --count tests/` → 1 and `bats --count -r tests/` → 3. Recursion is opt-in, and no `-r` appears anywhere in this repo (`CLAUDE.md:34`, `skills/retrospect/folding.md:98`, `pipeline.md:119` all invoke `bats tests/`).

**M-5 — the Jest/Vitest grammar over a real corpus.** 1022 `*.test.ts|tsx|spec.ts` files under `~/ghq/github.com/ngc-shj/passwd-sso/src`:

| Allow vocabulary | Files fired |
|---|---|
| status-shaped only (the round-2 rule) | **130** |
| general (any non-deny `expect(` line) | **1** |
| general + polarity scoring | **1** (same file) |

The single fire is `src/lib/url-helpers.server.test.ts`: two assertions, both `expect(() => fetchApi(...)).toThrow(…)`, no allow assertion anywhere — a genuine deny-only suite, which is precisely RT10's subject. A 130 → 1 reduction with the true positive retained is the measurement that justifies the symmetric allow side.

**M-6 — option injection through an unguarded filename operand.** In a scratch repo containing `-rf.bats`, a `.bats` file holding `1e touch /tmp/SED_INJECT_PROOF`, and a file literally named `s:#.*$::`:

```
sed 's:#.*$::' "-rf.bats"     → exit 0, /tmp/SED_INJECT_PROOF created   (arbitrary command execution)
sed 's:#.*$::' "./-rf.bats"   → exit 0, no marker                        (guard holds)
sed 's://.*$::' "-rf.bats"    → exit 2, no marker
```

`sed` parses `-rf.bats` as `-r` plus `-f .bats`, reads its script from the repository under review, and GNU sed's `e` command executes it. The shipped sibling `check-vacuous-denial.sh:216` survives only because its expression `s://.*$::` contains `/` and therefore cannot exist as a filename — an accident of delimiter choice, not a control. The bats expression has no `/`, so the accident does not transfer. This is why requirement 7 exists.

## Contracts

### C1 — `hooks/check-deny-only-guard.sh`

- **Signature**: `bash check-deny-only-guard.sh [base-ref]` → stdout findings, exit 0; exit 1 on setup error.
- **Control class**: `detection only`. Published limitation list is `SC1`–`SC7` (the header comment and the rule-row sentence must both enumerate all seven; round 3 caught them listing five).
- **Detection**:
  1. Changed-file set: `git diff --name-only --diff-filter=AM <base>...HEAD`. The three-dot form diffs against the merge base, so commits landing on `main` after the branch point are not misreported. `--diff-filter=AM` matches every sibling and keeps deleted/renamed paths — which no longer exist — out of the read loop. Jest/Vitest: extension `ts|tsx|js|jsx|mjs|cjs` AND the sibling `TEST_PATH_RE`. Bats: extension `bats`.
  2. **Operand guarding (requirement 7).** Every filename derived from `git diff` is passed as `"./$f"` at every operand position — `sed`, `grep`, `awk`. `./` is used rather than `--` because BSD `sed` does not honour `--` uniformly. M-6 is the red-proof.
  3. **Three grammars, polarity-scored.** A line is classified once: deny-shaped if it carries a deny token *not* under a negating operator; allow-shaped if it carries an allow token, or (Jest/Vitest only) contains `expect(` without a deny token, or carries a deny token *under* a negating operator.

     | Grammar | Deny token | Allow token | Negating operator |
     |---|---|---|---|
     | Jest/Vitest | `.toBe/toEqual/toStrictEqual(403\|429\|503)`, `rejects.`, `.toThrow(` | any other `expect(` line | `.not.`, `.resolves.` |
     | bats status | `[ "$status" -ne 0 ]`, `[ "$status" -eq <non-zero literal> ]` | `[ "$status" -eq 0 ]` | — |
     | hook decision | `"decision":"block"` / `"decision": "block"` | `"decision":"approve"` / `"decision": "approve"` | `!=` (flips approve to deny) |

     `assert_success` / `assert_failure` are **excluded**: measured zero occurrences, and bats-assert is not a dependency. An inert alternative cannot be red-proven. The Jest/Vitest allow side is deliberately general rather than an enumeration — M-5 measures the enumerated form at 130 false positives per 1022 files and the general form at 1, and generality also dissolves the `.not.toThrow(` ⊂ `.toThrow(` substring problem, since polarity is scored before membership.
  4. Comment stripping before matching: `sed 's://.*$::'` for JS, `sed 's:#.*$::'` for bats. **Known over-strip**: a `//` inside a string literal truncates the line, which can delete an allow match — measured at 2 files in the M-5 corpus, 0 induced fires, and disproportionately likely on URL arguments, which are exactly the boundary-adjacent allow case for a URL/path validator. Recorded as `SC8`; the JS lexer that distinguishes a comment from a string is not consulted, and requirement 4 forbids adding one.
  5. Fire Major when: ≥1 deny-shaped line whose number is in the diff `+` set, AND **zero** allow-shaped lines file-wide across all three grammars.
  6. `EXTRA_*` values are validated **in the engine that consumes them**. Round 3 measured that a `grep -E` probe is insufficient: `awk -v` performs escape processing on the value first, so `\[ *"\$status"…` silently becomes a bracket expression matching any of those characters, and `\[unterminated` is grep-valid but awk-fatal — the fatal case leaves `flagged=""` and the script reports `Total findings: 0` at exit 0, which is RT7 shape (c). Patterns reaching awk are probed with `awk -v re="$V" 'BEGIN{ if ("" ~ re) exit 0 }' </dev/null`; grep-only patterns keep the `grep -E` probe (`check-orphaned-checks.sh:78-81`). A malformed value exits 1 with a diagnostic naming the variable.
- **Invariants**:
  - *(app-enforced)* A file with zero deny-shaped lines never produces a finding.
  - *(app-enforced)* A finding cites a deny line in the diff `+` set; an untouched deny-only file adjacent to the diff produces nothing.
  - *(app-enforced)* Setup failure exits non-zero. **The base-ref validity check is an argument-injection boundary, not only an RT7 shape (c) concern**: `git rev-parse --quiet --verify` rejects option-shaped arguments, and round 3 measured that `git diff "--output=/tmp/x...HEAD"` otherwise exits 0 and creates the file. The check must precede the first `git diff`.
  - *(app-enforced)* No untrusted filename is passed unguarded (clause 2).
  - *(app-enforced)* Real-corpus behavior is pinned: with `BASE=$(git rev-list --max-parents=0 HEAD)` — the root commit `c786905`, verified to contain no `tests/` files, so every current `tests/*.bats` line is a pure addition (0 removed lines across all 29) — the finding set over `tests/*.bats` is exactly `{tests/llm-commands.bats}`. **Precondition**: `tests/fixtures/rt10-deny-only.bats` must be committed before this assertion can pass, because `git diff <root>...HEAD` sees committed content only; the test states this and the fixture set is obtained by running with `EXTRA_EXCLUDE_PATH_RE` unset and post-filtering, since the signature provides no path-scoping argument.
  - *(app-enforced)* **Non-hermetic by design**: a future PR that adds a deny-only `tests/*.bats` reds this test, which is the dogfooding intent. The test name says so, so the first occurrence does not read as a broken detector.
- **Forbidden patterns**:
  - `pattern: (sed|grep|awk)[^|]*"\$f"` without a `./` or `--` guard — reason: requirement 7 / M-6.
  - `pattern: \| *(head|tail|grep)` in any status-bearing invocation — reason: R44.
  - `pattern: declare -A` — reason: bash 3.2.
  - `pattern: \\b|\\<` inside an awk ERE string — reason: BSD awk silently matches nothing.
  - `pattern: assert_(success|failure)` — reason: measured absent; an inert alternative cannot be red-proven.
- **Acceptance criteria** (each labelled by who enforces it):
  1. *(test)* `bats tests/check-deny-only-guard.bats` green.
  2. *(review)* One fixture per implemented pattern alternative in all three grammars, both polarities. Not observable by a bats assertion — mapping fixtures to regex branches needs a linter this repo does not have. Labelled review-enforced rather than implied test-enforced.
  3. *(test)* The pinned real-corpus assertion above.
  4. *(test)* A committed fixture at `tests/fixtures/rt10-deny-only.bats` using the **hook-decision deny** form with **no allow-shaped line of any grammar** — `[ "$status" -eq 0 ]` is the trap, since the repo's `block-*.bats` suites never pair it with their decision assertions. Every `@test` body opens with `skip "fixture for check-deny-only-guard.bats"` so the file is green if anyone ever runs `bats -r`; the detector reads it textually and never executes it. Its purpose is a **live mutation target for the decision-deny alternative plus non-zero fire density in the pinned set** — not a "genuine true positive", which it is not: it is synthetic and authored to the detector's own regex.
  5. *(test)* Three `EXTRA_*` knob fixtures (silent without, flagged/suppressed with) plus a malformed-value fixture using a **grep-valid, awk-fatal** value (`\[unterminated`), asserting exit 1 and the diagnostic. A grep-invalid value like `(` cannot discriminate, since either engine rejects it.
  6. *(test)* Hostile-filename fixture: a scratch repo containing `-rf.bats`, a `.bats` sed script, and a file named `s:#.*$::`; assert no marker file is created **and** that an ordinary `tests/foo.bats` in the same run is still read and classified (the RT10-paired allow case for this guard).
  7. *(test)* An invalid-base-ref fixture, an untouched-file silence fixture, a commented-out-allow fixture and its paired commented-out-deny fixture, and an excluded-path fixture. Round 3 found these named in mutation rows but created by no criterion.
  8. *(review)* Suite arithmetic: `bats tests/` = 905 + `bats --count tests/check-deny-only-guard.bats`. Not assertable from inside the suite (re-entrancy); a two-command manual check.
- **Env knobs**: `EXTRA_DENY_ASSERTION_RE`, `EXTRA_ALLOW_ASSERTION_RE`, `EXTRA_EXCLUDE_PATH_RE`.

### C2 — Wiring

- **Edits**: `common-rules.md` RT10 row gains a `**Mechanical detection**` sentence naming the script, file-level granularity, the three grammars, and `SC1`–`SC7`; `phases/phase-2-coding.md` gains one pre-step paragraph; `skills/test-gen/SKILL.md` gains the script beside the RT8/RT4 detectors at L141-143 **and its adjacent scope caveat at L146 is updated** — it currently says "both hooks are Jest/Vitest TS/JS only" and "a clean hook run on a non-JS project means *not checked*", which a third hook covering bats makes false in both directions; `skills/retrospect/folding.md` §3 extends its authoring map from five surfaces to six; `settings.json` gains a permission entry; the digest is regenerated (a no-op the linter's check 7 proves).
- **Invariants**:
  - *(review-enforced)* The script is registered in all four surfaces. **Not labelled test-enforced**: `check-rule-sync.sh` never reads `settings.json` (measured: zero matches), and `tests/install.bats` asserts only well-formedness and merge behavior, so no existing test can observe a missing permission entry. Note also that the "sibling pair form" is not a convention — `check-vacuous-denial.sh` has no `settings.json` entry at all.
  - **Not asserted**: the repo-wide form. Measured false at HEAD in all four directions — of 15 `hooks/check-*.sh`, 10 lack `tests/<name>.bats`, 3 lack a `settings.json` entry, 8 are named only in `rule-details/*.md`, 2 are absent from the phase files. See `SC6`.
  - **Not asserted**: the argv-laundering invariant. No mechanically decidable predicate exists; it belongs with the R50 work that introduces an argv-executing script, and is item 8 of the deferred plan.
- **Acceptance criteria**: *(test)* `bash hooks/check-rule-sync.sh` exits 0. *(review)* `check-orphaned-checks.sh` reports the new script **Minor** — the expected classification, since `VC1`/`SC5` mean no gate surface exists; "Minor-or-silent, never Major" was measured unfalsifiable (vacuous at `main`==HEAD, and Minor for all 15 siblings under the root base).

### C3 — Tests

- **Shape**: `tests/check-deny-only-guard.bats` plus `tests/fixtures/rt10-deny-only.bats`, following the scratch-repo pattern in `tests/check-vacuous-denial.bats` (verified: all git work in `mktemp -d`, torn down in `teardown()`, nothing written to the tracked worktree). C1.3's pinned test is the one exception — it reads the real repo, but read-only.
- **Mutation table (RT7)** — every row is **executed** and its observed failure line recorded in the deviation log before the PR opens. Rows are paired with the criterion that creates their target.

  | # | Mutation | Test that must go red | Discrimination |
  |---|---|---|---|
  | M1 | Drop the hook-decision **allow** alternatives | pinned set (C1.3) | measured: all seven `block-*.bats` fire |
  | M2 | Drop `[ "$status" -eq <non-zero> ]` from deny | primary: the bats-status deny fixture (C1.2); secondary: pinned set goes empty | measured; the secondary target dies if `SC1` is ever closed, so the fixture is primary |
  | M3 | Drop `"decision":"block"` from deny | the committed fixture (C1.4) | measured: fixture goes deny=0, silent |
  | M4 | Make the base-ref check `exit 0` | invalid-base-ref fixture (C1.7) | |
  | M4b | Move the base-ref check below the first `git diff` | option-shaped base-ref fixture: assert no file is written and exit 1 | measured: `git diff "--output=…"` otherwise creates the file |
  | M5 | Drop `EXTRA_*` validation | malformed-value fixture (C1.5) | **corrected**: round 3 executed this — the script exits 0 and prints `Total findings: 0`, so the *status* assertion reds. The diagnostic assertion additionally distinguishes our message from grep's own stderr. The round-3 plan's rationale ("status alone stays green") was false. |
  | M6 | Ignore diff `+`-line scoping | untouched-file silence fixture (C1.7) | inert against the pinned test by construction — the root base already treats every line as added |
  | M7 | Drop comment stripping | commented-out-allow fixture (C1.7) | zero real-corpus delta; fixture-only |
  | M7b | Strip comments on the deny side only | commented-out-deny fixture (C1.7) | the paired direction: a commented-out deny must not create a finding |
  | M8 | Drop each implemented alternative in turn — 13 total across the three grammars | that alternative's fixture, both polarities (C1.2) | expanded from one row to thirteen; round 3 measured that the corpus uses exactly one spelling of each decision pair (`"decision":"block"` 185 / spaced 0; `"decision": "approve"` 204 / unspaced 0), so the unused spellings are red-provable only by fixture |
  | M9 | Score a `.not.`-negated deny token as deny | JS polarity fixture (C1.2) | |
  | M10 | Score a `!=`-negated approve token as allow | bats polarity fixture (C1.2) | closes the latent silence M-2 identifies |
  | M11 | Pass `"$f"` unguarded to `sed` | hostile-filename fixture (C1.6) | measured (M-6) |
  | M12 | Validate `EXTRA_*` with `grep -E` only | the awk-fatal value in C1.5 | measured: grep accepts `\[unterminated`, awk aborts |

  Dropped from the round-3 table: the `settings.json` row, whose target test does not exist and which no contract creates (see C2's review-enforced label).
- **Invariants**: *(app-enforced, RT10 dogfood)* every deny fixture has a boundary-adjacent allow pair. *(app-enforced)* no test mutates the tracked worktree.

## Go/No-Go Gate

| ID | Subject | Status |
|-----|---------------------------------------------------|---------|
| C1 | `check-deny-only-guard.sh` | pending |
| C2 | Wiring | pending |
| C3 | Tests, fixture, and the 14-row mutation table | pending |

## Testing strategy

**Axes** — grammar (Jest/Vitest, bats status, hook decision) × deny form (each alternative, none) × allow form (each alternative, general `expect(`, absent) × polarity (plain, negated) × comment state (live, commented-out) × side (deny, allow) × diff position (in `+` set, untouched) × file classification (test path, non-test path, excluded path) × filename shape (ordinary, option-shaped) × expectation (flag, silent).

**Claimed**: every implemented alternative in both polarities; both comment states **crossed with both sides**; both diff positions **on the deny side**; all three file classifications for Jest/Vitest; both filename shapes; the pinned real-corpus set.

**Unclaimed and named**:
- *Allow-side diff position* — the fire condition scopes only the deny side to the `+` set; allow is file-wide. A diff that deletes a file's only allow assertion while leaving deny lines untouched produces no fire, which is the canonical RT10 regression the rule row itself describes. Recorded as `SC9`; closing it needs allow-side diff scoping, which would also fire on every file whose allow assertions predate the diff.
- *File classification × bats* — the bats filter is extension-only, so a "non-test path" `.bats` file is unreachable; that cell exists only for Jest/Vitest.
- Mixed files (`SC4`); grammars beyond the three (`SC3`); this suite's own file (`SC7`); `//` inside string literals (`SC8`).

## Considerations & constraints

- **Scope contract** — each entry carries the mandatory Anti-Deferral triple (`common-rules.md:191-195`):
  - `SC1` — `tests/llm-commands.bats` is a **known false positive** (M-3), pinned as an expected fire so a vocabulary change that silences it also reds. *Worst case*: one reviewer sentence per occurrence. *Likelihood*: certain — it is measured today. *Cost to fix*: unbounded; suppression needs per-assertion subject binding, which has no form under requirement 4. Owner: accepted permanently.
  - `SC2` — RT10 clause 1 (boundary-adjacency) and clause 2 (axis combinations) are not mechanically checkable. *Worst case*: a paired allow fixture that is distant rather than adjacent passes unnoticed. *Likelihood*: high. *Cost to fix*: no known mechanical form. Owner: human review, permanently.
  - `SC3` — grammars beyond the three (pytest, Go, RSpec, bats-assert). *Worst case*: silence on those frameworks, read as "passed" rather than "not checked" — which is why C2 updates `test-gen/SKILL.md`'s caveat. *Likelihood*: certain for those projects. *Cost to fix*: one grammar row plus fixtures each, ≈2h. Owner: v2. `TODO(rt10-v2): add pytest/Go/RSpec grammars`.
  - `SC4` — file-level granularity. *Worst case*: a mixed file's deny-only guard ships uncaught. *Likelihood*: moderate — measured 0 occurrences in this repo's 29 files. *Cost to fix*: block segmentation, ≈1d. Owner: v2. `TODO(rt10-v2): block-level segmentation`.
  - `SC5` — no CI surface, so the script is reachable only from bats tests and skill prose. *Worst case*: the detector silently stops being run. *Likelihood*: low here (the phase-2 pre-step is prose an orchestrator follows). *Cost to fix*: introducing CI to this repo. Owner: separate plan. `TODO(repo-ci): wire the 15 check-*.sh detectors to a gate surface`.
  - `SC6` — the repo-wide hook↔rule↔settings↔test membership invariant is **not** asserted, being measurably false at HEAD (10 missing bats files, 3 missing permission entries, 8 rule-surface misses, 2 phase-file misses). *Worst case*: ten existing detectors already report PASS by never running — the state CLAUDE.md warns about, true ten times over today. *Likelihood*: certain, present. *Cost to fix*: the 3 permission entries are 6 JSON lines and the 2 phase mentions are 2 sentences — **both are under the 30-minute rule and are done in this PR**; the 10 bats files are ≈1d and are what is deferred. Owner: separate plan. `TODO(hook-test-backfill): 10 detectors without bats coverage`.
  - `SC7` — this detector cannot classify its own test file (detection-only scripts exit 0, so the file scores allow>0). *Worst case*: the dogfood invariant is review-enforced. *Likelihood*: certain. *Cost to fix*: none available. Owner: human review, permanently.
  - `SC8` — `//` inside a string literal is over-stripped (measured: 2 files in the M-5 corpus, 0 induced fires). *Worst case*: a URL-carrying allow assertion is deleted, producing a false fire on exactly the boundary-adjacent case. *Likelihood*: low but structurally biased toward URL/path validators. *Cost to fix*: a JS string-aware scanner, which requirement 4 forbids. Owner: accepted; revisit if requirement 4 relaxes.
  - `SC9` — allow-side lines are not diff-scoped, so deleting a file's only allow assertion produces no fire. *Worst case*: the canonical RT10 regression is invisible. *Likelihood*: moderate. *Cost to fix*: allow-side diff scoping plus a fixture, ≈2h, but it changes the fire condition materially and needs its own measurement. Owner: v2. `TODO(rt10-v2): allow-side diff scoping`.
- **Risk — remaining false positives**: measured at 1 in 1022 JS files (M-5) and 1 in 29 bats files (M-2). Mitigation for project-specific idioms: `EXTRA_ALLOW_ASSERTION_RE`, covered by C1.5.
- **Dependency**: none. `main` carries RT10 at `3014e77`.

## User operation scenarios

1. **Phase 2, TS project**: a validator lands with three rejection cases and no other assertions. Flagged Major. The developer adds the boundary-adjacent allow case — `expect(resolve('safe.txt')).toBe('/root/safe.txt')` — and the file goes silent, because the general allow rule counts any non-deny `expect(` line. Under the round-2 status-shaped vocabulary this remedy did **not** work and the file stayed Major forever; M-5 is the measurement that changed it.
2. **Phase 2, this repo**: a new `block-*.sh` gate lands with `tests/block-*.bats` asserting `[[ "$output" == *'"decision":"block"'* ]]` and no approve assertion. Flagged; the fix is the paired approve case. `tests/block-sensitive-files.bats`, with 22 approve assertions, stays silent (M-2).
3. **Known false positive**: `tests/llm-commands.bats` flags; the disposition is recorded once and pinned (`SC1`).
4. **Hostile repository under review**: a repo containing `-rf.bats` is analyzed. The `./` operand guard means sed reads that file rather than a script the repo supplied (M-6).
