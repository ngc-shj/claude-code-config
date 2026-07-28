# Plan: Mechanical detection hooks for RT10 and R50

Date: 2026-07-28
Status: Phase 1 — plan review, round 2 (round 1 findings folded)

## Project context

- **Type**: `mixed` — shell tooling (`hooks/`) plus markdown config (`skills/`, `rules/`), installed into `~/.claude/` by `install.sh`.
- **Test infrastructure**: `unit tests only` — `bats tests/` (905 tests at `3014e77`, measured: 905 `@test` declarations across `tests/*.bats`). **No CI/CD**: no `.github/workflows/`, no `scripts/pre-pr.sh`. The authoritative gate is a local `bats tests/` run.
- **Verification environment constraints**:
  - `VC1` — no CI surface exists, so "wired into the authoritative gate" (RT7 shape b) can only mean *a bats test invokes it*. A detector referenced solely from skill prose is what `check-orphaned-checks.sh` classifies as Minor. Pre-existing condition shared by all seven sibling detectors; not fixed here (`SC6`).
  - `VC2` — C1's **TS/JS** half cannot be exercised against real production code inside this repo (no TS/JS sources here); it is fixture-covered only, and it carries the higher false-positive risk of the two halves because its deny vocabulary (`.toThrow(`) is general-purpose while its allow vocabulary is status-shaped. C1's **bats** half IS exercised against this repo's real `tests/` tree, and that exercise is a pinned acceptance criterion (C1), not a claim.

## Objective

Convert the two most mechanically-checkable of the five rules folded in `3014e77` from human-review-only into detector hooks, so they survive the `N/A` boilerplate pressure of a 50-line Recurring Issue Check:

- **RT10** — flag a changed test file whose guard assertions are entirely deny-shaped, with no allow-shaped counterpart.
- **R50 precondition (i) only, plus a decided subset of (iii)** — make a round's verification evidence a machine-checked structure carrying each command's own exit status and its subject sha. Preconditions (ii), (iv), (v), (vi) are **not** mechanized (`SC7`), and every artifact that names this mechanism must say so.

## Requirements

**Functional**

1. RT10 detector runs over `base-ref...HEAD`, per changed test file, emitting human-scannable findings; it must not re-flag files the diff did not touch.
2. R50 evidence producer runs a command, passes its output through unchanged, records the command's **own** exit status (never a pipeline aggregate — R44), and exits with that same status.
3. R50 evidence gate validates the round artifact's evidence block structurally and fails closed on absent / malformed / non-zero-exit / stale-subject / incomplete records.
4. Every new script ships a bats test that is red-provable, with the mutation named in the plan and executed before the PR opens (RT7).

**Non-functional**

5. Bash 3.2-compatible (macOS stock) — no associative arrays, no `\b`/`\<` in awk ERE; follow the `AWK_WORD_START` convention in `check-vacuous-denial.sh`.
6. No new runtime dependency: no `jq`, no `python3`, no node. Text processing via `awk`/`sed`/`grep` only.
7. Complexity bounded against the full changed-file set (R45): one pass per changed file, no whole-corpus operation inside a per-file loop.
8. Every claim written into a header comment, rule row, or commit message is calibrated to what the implementation proves (R49) — "closes", "all", "every" require the closure argument beside them.
9. **No new argv-laundering surface.** A hook that executes caller-supplied argv must not receive a `*`-suffixed `permissions.allow` entry, because `settings.json`'s deny/ask patterns are anchored on the leading command token and cannot see past a wrapper.

## Technical approach

Three scripts plus one extracted library, following the established detector shape (`set -u`, `mktemp -d` + `trap`, git-toplevel resolution, base-ref validity check that exits non-zero, diff `+`-line scoping, `EXTRA_*` env knobs, a header comment carrying detection algorithm / severity / out-of-scope / usage):

| Script | Role | Control class (R49) |
|---|---|---|
| `hooks/check-deny-only-guard.sh` | RT10 detector | **detection only** — emits findings, exit 0 always (non-zero only for setup errors) |
| `hooks/run-verified.sh` | R50 evidence recorder | **detection / audit only** — it records, it does not decide. It cannot record a pass it did not observe; it does **not** ensure it was invoked. Not-being-invoked is the absence of a gate, not a bypass of one |
| `hooks/check-verification-evidence.sh` | R50 evidence gate | **fail-closed verification gate** over the artifact's *structure and record content*; explicitly **not** a boundary against a fabricating author (`SC3`) |
| `hooks/lib/resolve-contained.sh` | path containment, extracted | supporting library — one adjudicator for "is this path allowed" (R48) |

**Adjudication authority (R47)**

- RT10: no external interpreter decides "is this test deny-only". The honest classification is a **bounded pattern set over three declared grammars**, and the plan fixes the covered vocabulary explicitly, states the uncovered remainder as scope-out, and pins a real-corpus expectation so the bound is measured rather than assumed.
- R50 record grammar: a grammar this repo owns on both ends, so the record validator is a **whitelist** — one anchored shape, anything else rejected — closed by construction over its input.
- R50 block *location*: **not** closed. Steps 1-3 of C3 decide which bytes are the record set by notation over Markdown, and no parser is available under requirement 6. The design climbs as far as the constraint permits (fence-state machine, both fence characters with CommonMark run-length matching, uniqueness requirement) and declares the remainder (`SC9`). The closure claim in every header and rule row is scoped to the record grammar, never to the locator.
- Path decisions: delegated to physical resolution via the extracted `_resolve_contained` (symlink-chain chase with hop cap, control-char rejection, containment case-match, fail-closed empty return) — never to string inspection.
- Deliberately rejected: parsing the round artifact's prose for claim phrases ("tests pass", "N passed", "build green"). Surface-form adjudication of an input whose meaning no interpreter fixes — evaluated and dropped, with a forbidden-pattern guard so it cannot return.

**Reuse (R1)**. `hooks/tri-tmpdir.sh` is skill-facing (invoked from phase files, not from hooks) and the `awk /^@@/ … RSTART + 1, RLENGTH - 1` added-line extractor is duplicated across nine hooks; this would be the tenth. Both copies are deliberate — hooks are self-contained and sourced from `~/.claude/hooks/` with no library-load convention — and that is the disposition, not an omission. The two helpers whose non-reuse is **not** defensible are `_resolve_contained()` (`hooks/retro-prescreen.sh:57-98`) and `cmd_scrub` (same file): both are security primitives, and a second implementation of either would be R48's two-adjudicators shape. `_resolve_contained` is therefore extracted to `hooks/lib/resolve-contained.sh` and sourced by both its original caller and C2; `cmd_scrub` is invoked as the existing subcommand.

**Granularity (RT10)**: file-level, not block-level. RT10's claim is about a guard's test *suite*, so the unit is the file. Cost: a file holding one covered and one deny-only guard stays silent (`SC5`).

## Contracts

### C1 — `hooks/check-deny-only-guard.sh` (RT10 detector)

- **Signature**: `bash check-deny-only-guard.sh [base-ref]` → stdout findings, exit 0; exit 1 on setup error (not a git repo, invalid base-ref, malformed `EXTRA_*` regex).
- **Control class**: `detection only`. Known miss classes: `SC1`, `SC2`, `SC4`, `SC5`, `SC8`. The header comment carries that list — an unqualified "detects deny-only tests" would be an R49 overstatement.
- **Detection**:
  1. Changed-file set: `git diff --name-only <base>...HEAD`, filtered to test files. The three-dot form is deliberate and matches every sibling: it diffs against the merge base, so commits landing on `main` after the branch point are not misreported as this branch's changes. Jest/Vitest: extension `ts|tsx|js|jsx|mjs|cjs` AND the sibling `TEST_PATH_RE`. Bats: extension `bats`.
  2. **Three declared grammars.** Round 1 measured the two-grammar v1 over the real `tests/` tree and found it inverted — silent on all seven `tests/block-*.bats` suites (the RT10 subject class), firing on two non-targets. The third grammar is the reason: this repo's gate suites assert on the hook's emitted decision, not on `$status`, and their allow side is a *positive match on a different string*, not a negated deny.

     | Grammar | Deny-shaped | Allow-shaped |
     |---|---|---|
     | Jest/Vitest | `.toBe/toEqual/toStrictEqual(403\|429\|503)`, `rejects.`, `.toThrow(` | `.toBe/toEqual/toStrictEqual(200\|201\|204)`, `resolves.`, `.not.toThrow(` |
     | bats status | `[ "$status" -ne 0 ]`, `[ "$status" -eq <non-zero literal> ]` | `[ "$status" -eq 0 ]` |
     | hook decision | `"decision":"block"` / `"decision": "block"` | `"decision":"approve"` / `"decision": "approve"` |

     `assert_success` / `assert_failure` are **excluded**: measured zero occurrences in `tests/`, and bats-assert is not a dependency here. Adding an inert alternative would be a pattern nobody can red-prove.
  3. **Guard-subject gate.** Fire only when the file's deny assertions belong to a guard-shaped subject: the file must contain at least one deny-shaped assertion AND at least one invocation of a subject under test (`run ` in bats, a call expression inside `expect(...)` in JS). This is what keeps `tests/llm-commands.bats` — four `[ "$status" -eq 1 ]` on a CLI's error paths, happy paths asserted via `result=$(...)` — from firing. Measured: with the gate and the third grammar, `llm-commands.bats` scores allow>0 via neither status nor decision, so the gate is what suppresses it; this is a claimed acceptance cell, not an assumption.
  4. Fire Major when: ≥1 deny-shaped assertion whose line is in the diff `+` set, AND **zero** allow-shaped assertions file-wide across all three grammars (comment-stripped: `sed 's://.*$::'` for JS, `#`-stripping for bats), AND the guard-subject gate passes.
  5. Silent otherwise.
  6. `EXTRA_*` values are validated as regexes before use (as `check-orphaned-checks.sh:78-81` does); a malformed value exits 1 with a diagnostic rather than composing an invalid ERE that silently matches nothing (RT7 shape c — the fail-open direction).
- **Invariants**:
  - *(app-enforced)* A file with zero deny-shaped assertions never produces a finding.
  - *(app-enforced)* A finding cites a deny-assertion line in the diff `+` set; an untouched deny-only file adjacent to the diff produces nothing.
  - *(app-enforced)* Setup failure exits non-zero. A diff-based guard whose base ref errors and exits 0 is the fail-open shape RT7 (c) names.
  - *(app-enforced)* Real-corpus behavior is pinned: over this repo's own `tests/` tree at a pinned base, the finding set equals a named list recorded in C1's acceptance criteria. `tests/block-sensitive-files.bats` and `tests/llm-commands.bats` are named **silence** cases — both fired under v1 and both are false positives.
- **Forbidden patterns**:
  - `pattern: \| *(head|tail|grep)` in any status-bearing invocation — reason: R44.
  - `pattern: declare -A` — reason: bash 3.2 (requirement 5).
  - `pattern: \\b|\\<` inside an awk ERE string — reason: BSD awk silently matches nothing (requirement 5).
  - `pattern: assert_(success|failure)` — reason: measured absent from this repo; an inert alternative cannot be red-proven.
- **Acceptance criteria**:
  1. `bats tests/check-deny-only-guard.bats` green.
  2. One fixture per **implemented pattern alternative** in all three grammars, both directions — not one per form-class. A single broken allow pattern must red a test, not ship as a permanent false-positive source.
  3. Real-corpus assertion: running the detector over this repo's `tests/` tree at a pinned base yields exactly the named finding set, and `block-sensitive-files.bats` / `llm-commands.bats` are absent from it. Red-proven by deleting one vocabulary alternative.
  4. Three `EXTRA_*` knob fixtures (silent without the knob, flagged/suppressed with it) plus one malformed-regex fixture asserting exit 1 with a diagnostic.
  5. The excluded-path axis cell is claimed by a fixture.
- **Env knobs**: `EXTRA_DENY_ASSERTION_RE`, `EXTRA_ALLOW_ASSERTION_RE`, `EXTRA_EXCLUDE_PATH_RE`.

### C2 — `hooks/run-verified.sh` (R50 evidence recorder)

- **Signature**: `bash run-verified.sh <command> [args...]` → the command's stdout/stderr pass through unmodified; exit status is the command's own.
- **Control class**: `detection / audit only`. It records; it never denies a run and has no subject to resolve. Stated in the header in those words. The one fail-closed property is narrow and about its **own** write: it cannot record a pass it did not observe.
- **No `permissions.allow` entry** (requirement 9). `settings.json` deny/ask patterns are anchored on the leading command token, so a `*`-suffixed allow entry for a script whose argv *is* a command line would auto-approve `sudo`, `rm -rf`, `git reset --hard`, `curl … -X POST -d @<key>`, `npm publish` — the same argv-laundering class this repo already denies for `eval`, `source`, `xargs`, `npx -y`. Each invocation prompts, which is the correct treatment. C5 records the omission as deliberate.
- **Behavior**:
  1. `[ "$#" -ge 1 ] || { echo "run-verified.sh: no command given" >&2; exit 121; }` — validate at the argv boundary (RS3), not in a downstream consumer that may not run.
  2. Resolve the evidence path **before** executing anything. Default: `${XDG_STATE_HOME:-$HOME/.local/state}/triangulate/evidence.jsonl` — outside any analyzed worktree, so a reviewed repo cannot plant a symlink at the default location and cannot be polluted by the wrapper. `$VERIFY_EVIDENCE`, when set, is resolved through `hooks/lib/resolve-contained.sh` against the evidence root: the resolved physical path must be contained, must not be a symlinked leaf, and must not name an existing non-regular file. Rejection → exit `121` with a stderr message naming the path. String inspection is not sufficient here — the filesystem resolver decides (R47).
  3. Compute `head` and `dirty` **before** executing, and compute `dirty` with the evidence path excluded, so the wrapper's own append cannot make the tree read dirty.
  4. Execute `"$@"` directly — no pipe, no command substitution. Read `$?` immediately into `st`.
  5. Redact **then** escape, in that order. Each argument passes through the existing `cmd_scrub` filter (emails, IPs, `/home/<user>/` paths, tilde paths, secret-shaped tokens), and only then through the JSON escaper: `\` → `\\`, `"` → `\"`, newline → `\n`, tab → `\t`, CR → `\r`. Escaping first would let an already-escaped token slip the redaction pattern. Any remaining C0 byte cannot be represented, and the wrapper MUST NOT write a record it cannot represent: exit `121` naming the offending argument index.
  6. Append exactly one record line:
     `{"ts":"<ISO-8601 UTC>","cmd":[<scrubbed, escaped argv>],"exit":<int>,"head":"<sha or no-git>","dirty":<true|false>}`
     `cmd` is an array, one element per argument — joining with spaces would destroy argument boundaries.
  7. Exit `st`. When the evidence write failed: emit the stderr message **in both directions** — with `st` = 0 exit `121`, with `st` non-zero exit `st` (the underlying failure is the more important signal) but still print, so a silently unrecorded run is impossible.
- **Round binding**: the orchestrator truncates `$VERIFY_EVIDENCE` at the start of each Phase 3 round (`run-verified.sh --start-round`, a distinct subcommand that takes no command line). Without a round boundary the file is an unbounded history from which any green subset can be pasted, and C3's completeness check has no window to compute over.
- **Invariants**:
  - *(app-enforced)* The recorded `exit` equals the command's own status, for success, failure, and when the *caller* pipes the wrapper's stdout.
  - *(app-enforced)* No record is written when argv is empty, when an argument is unrepresentable, or when the path fails containment.
  - *(app-enforced)* The evidence path never resolves inside the analyzed worktree unless the caller explicitly set it there (R50 clause v).
  - *(schema-enforced by C3)* Each emitted line matches the C3 record grammar exactly.
- **Forbidden patterns**:
  - `pattern: "\$@" *\|` — reason: R44.
  - `pattern: \$\(.*"\$@".*\)` — reason: capturing the command swallows its output and changes its status semantics.
  - `pattern: ^\s*[A-Z_]*EVIDENCE[A-Z_]*=.*>>` before the containment call — reason: the append must never precede resolution.
- **Acceptance criteria**: `tests/run-verified.bats` covers the axis table below, including status pass-through for exit 0 / 1 / 42, byte-identical output pass-through, `head`/`dirty` against a scratch repo's real state, the empty-argv case, one deny fixture per unrepresentable class (e.g. `$'\x01'` → exit 121 **and** no record appended), one allow fixture per representable escape class asserting byte-exact output, a scrub deny case (a token-shaped argument does not reach the record) with its paired allow case (an ordinary argument survives byte-identically), and the containment cases mirroring `tests/block-sensitive-files.bats` — symlinked leaf pointing outside the root, two-hop chain with both links inside, `..` through a symlinked directory component — each paired with the allow case that an ordinary evidence path is still written.
- **Consumer-flow walkthrough**: Consumer 1 — `hooks/check-verification-evidence.sh` reads `{ cmd, exit, head, dirty }`; it **decides** on `exit` and on `head` (equality with the reviewed sha), decides or warns on `dirty` per C3 step 5b, and displays `cmd`; `ts` is displayed, never parsed. Consumer 2 — the Phase 3 orchestrator reads the record set and pastes it verbatim into the artifact fence; it performs no field-level operation. **The record deliberately carries no pass count**: capturing the command's stdout would violate R44, so the "pass count" half of R50's reviewer action is served by the command output the reviewer already sees in the transcript, not by this record. That limitation is stated in `SC10` and in C4's section text, so no consumer is promised a field the shape lacks.

### C3 — `hooks/check-verification-evidence.sh` (R50 evidence gate)

- **Signature**: `bash check-verification-evidence.sh <artifact.md> <reviewed-sha> [evidence.jsonl]` → stdout findings; exit 0 only when the block is present, well-formed, complete, current, and all-green; exit 1 otherwise.
- **Control class**: `fail-closed verification gate` over artifact structure and record content. **Not** a boundary against a fabricating author (`SC3`). The header says so in those words.
- **Behavior**:
  1. Locate the `## Verification Evidence` heading while tracking fence state, so a heading inside a fenced block is not a heading. Both fence characters are recognised, closed per CommonMark's matching-run-length rule. The section must be **unique**: two matches is a finding, not first-wins. Absent → exit 1.
  2. The line after the heading may be exactly the N/A literal (see `VERIFY_NA_LINE` below); in that case exit 0.
  3. Otherwise extract the first fenced block after the heading. Missing fence → exit 1.
  4. Validate every non-blank line against the anchored record grammar. The grammar admits every byte sequence C2's escaper can emit — `\\`, `\"`, `\n`, `\t`, `\r` inside string fields, and a `cmd` array of ≥1 element. A non-matching line → exit 1, citing it. An empty `cmd` array → exit 1.
  5. Per record: (a) `exit` ≠ 0 → Major finding, exit 1. (b) `head` ≠ `<reviewed-sha>` → Major finding quoting both shas, exit 1 — a block carried forward from an earlier round verifies a subject that is not the one under review (R50 iii). (c) `dirty` = true → **accepted with a printed warning**, not rejected: a mid-round verification against an uncommitted tree is normal, and rejecting it would be the over-block RT10 warns about. This is a decision, recorded as one.
  6. When `evidence.jsonl` is supplied, check **both** directions over the round window: `artifact ⊆ jsonl` (no invented records) and `jsonl ⊆ artifact` (no omitted records). The second is the direction that catches the actual threat — three runs, one failing, only the green ones pasted — and the first alone cannot see it. An unmatched jsonl record → Major finding, exit 1. When the file is absent, print that provenance was not cross-checked; never silently skip.
- **N/A literal**: read from `VERIFY_NA_LINE`, defaulting to the compiled-in string. `tests/check-verification-evidence.bats` extracts the literal from the **real** `skills/triangulate/phases/phase-3-review.md` and feeds it to the validator, so a reword in the template reds at the source rather than failing every future round (RT5 — the test call-path reaches the shipping artifact, not a fixture copy).
- **Invariants**:
  - *(app-enforced)* Every failure direction exits non-zero: no heading, duplicate heading, empty fence, malformed line, empty `cmd`, non-zero `exit`, sha mismatch, unmatched jsonl record in either direction.
  - *(app-enforced)* The N/A escape is exact-match only.
  - *(app-enforced)* The locator's limits are declared, not implied closed (`SC9`).
- **Forbidden patterns**:
  - `pattern: (tests? pass|passed|green|全て通|問題なし)` — reason: R47. Prose-claim matching was evaluated and rejected; its presence means the rejected design came back.
- **Acceptance criteria**: `tests/check-verification-evidence.bats` covers the axis table below — every numbered branch with its paired allow case, the decoy-heading-inside-a-fence case, both fence characters, the duplicate-heading case, the near-miss N/A line, the sha-mismatch case with its matching-sha pair, the `dirty` warning path, both jsonl directions, and the producer→validator round-trip (RT9) over the argv corpus named in C2's acceptance criteria plus `bash -c 'echo hi'` (multi-element `cmd`) and an empty-string argument.

### C4 — `## Verification Evidence` artifact section (Phase 3 template)

- **Shape**: a new `## Verification Evidence` section in the Step 3-4 merged-artifact template of `skills/triangulate/phases/phase-3-review.md`, holding either the exact N/A line or a fenced block of C2 records. The section text states what the block does **not** carry (a pass count — `SC10`) and that the locator is not closed (`SC9`).
- **Invariants**:
  - *(app-enforced)* No new `### Step` heading, so `steps:`/`step_ids:` are unchanged and `check-rule-sync.sh` check 8 stays green.
  - *(app-enforced)* Step 3-6's verification commands are shown invoked through `run-verified.sh`, and Step 3-1 shows `--start-round`.
- **Acceptance criteria**: `bash hooks/check-rule-sync.sh` exits 0 after the edit; `grep -c '^### Step' skills/triangulate/phases/phase-3-review.md` **= 9** (the pre-edit value, recorded here so the criterion is evaluable post-merge).
- **Consumer-flow walkthrough**: Consumer 1 — C3 reads the heading, the optional N/A line, and the fenced record lines. Consumer 2 — the Phase 3 reviewer reads the block for the exit status and subject sha; the pass count comes from the command output in the transcript, per `SC10`. Both consumers' needs are satisfiable from the locked shape.

### C5 — Rule-row and phase wiring

- **Edits**:
  - `common-rules.md`: a `**Mechanical detection**:` sentence on the RT10 row (naming `check-deny-only-guard.sh`, its file-level granularity, its three grammars, and `SC1`/`SC2`/`SC4`/`SC5`/`SC8`) and on the R50 row (naming both R50 scripts, stating that only precondition (i) and a decided subset of (iii) are covered, listing (ii)/(iv)/(v)/(vi) as human-owned per `SC7`, and naming the fabrication limit `SC3`).
  - `phases/phase-2-coding.md`: one `**Pre-step: mechanical RT10 deny-only-guard check**` paragraph.
  - `phases/phase-3-review.md`: C4's section, `--start-round` at Step 3-1, wrapper usage at Step 3-6, and a pre-step invoking `check-verification-evidence.sh`.
  - `skills/test-gen/SKILL.md`: add `check-deny-only-guard.sh` alongside the RT8/RT4 detectors at L141-143 — both siblings are registered there with the stated rationale "closes the generate→verify loop", and RT10 ("the suite the generator just wrote is deny-only") is the same family and the same loop.
  - `skills/retrospect/folding.md` §3: extend the detection-hook authoring map from five surfaces to six, adding `test-gen/SKILL.md`. §3's omission is why round 1 had to recompute the set from code.
  - `settings.json`: permission entries for `check-deny-only-guard.sh` and `check-verification-evidence.sh` in the sibling pair form. **None for `run-verified.sh`** — see C2 and requirement 9.
  - `hooks/lib/resolve-contained.sh`: extracted from `hooks/retro-prescreen.sh:57-98`, with the original caller switched to source it. Behavior-preserving; `tests/retro-prescreen.bats` must stay green unchanged, which is the extraction's red-proof.
  - `.gitignore`: not needed — the evidence file defaults outside the worktree (C2 step 2).
  - Regenerate `common-rules.digest.md`: row *procedure* text does not alter the digest's three columns, so the regeneration is a no-op assertion that `check-rule-sync.sh` check 7 proves.
- **Invariants**:
  - *(test-enforced, R42 member-set)* Every `hooks/check-*.sh` is named in a `**Mechanical detection**` sentence in `common-rules.md`, has a `settings.json` permission entry, and has a `tests/<name>.bats`. Derivation is from code, not from this list: set A = `ls hooks/check-*.sh`; B1..B4 = basenames referenced in `common-rules.md`, `settings.json`, `tests/`, and the phase files; `A \ Bn` empty for each n. `run-verified.sh` is outside A by construction (it is not a `check-*` detector) and its exclusion from `settings.json` is asserted positively, not by omission.
  - *(test-enforced)* No `hooks/*.sh` that executes caller-supplied argv appears `*`-suffixed in `permissions.allow` (requirement 9).
- **Acceptance criteria**: `bash hooks/check-rule-sync.sh` exits 0. `bash hooks/check-orphaned-checks.sh main` reports `check-deny-only-guard.sh` and `check-verification-evidence.sh` at Minor-or-silent; `run-verified.sh` is **expected to be unclassified** — its basename matches none of that hook's `CHECK_NAME_RE` alternatives ("verified" does not contain "verify"), so the criterion is stated per script rather than as a single sweep that one member satisfies by never being considered. The exclusion is recorded in `SC11`.

### C6 — Tests

- **Shape**: `tests/check-deny-only-guard.bats`, `tests/run-verified.bats`, `tests/check-verification-evidence.bats`, plus assertions added to `tests/install.bats` (the argv-laundering and member-set invariants), following the fixture-repo pattern in `tests/check-vacuous-denial.bats`.
- **Mutation table (RT7)** — each row names the edit and the test it must redden. Every row is **executed** and its observed failure line recorded in the deviation log before the PR opens; per `feedback_mutation_execute_redproof_claims`, a red-proof reasoned about rather than run is not a red-proof.

  | # | Mutation | Test that must go red |
  |---|---|---|
  | M1 | Drop the hook-decision grammar from the deny vocabulary | real-corpus pinned finding set |
  | M2 | Drop the hook-decision grammar from the allow vocabulary | `block-sensitive-files.bats` silence case |
  | M3 | Remove the guard-subject gate | `llm-commands.bats` silence case |
  | M4 | Make C1's invalid-base-ref path `exit 0` | setup-error case |
  | M5 | Drop `EXTRA_*` regex pre-validation | malformed-regex case |
  | M6 | Change C2's `exit $st` to `exit 0` | status pass-through 42 |
  | M7 | Swap C2's redact/escape order | scrub deny case |
  | M8 | Skip C2's containment call | symlinked-leaf case |
  | M9 | Compute `dirty` after the append | `dirty` reflects real worktree |
  | M10 | Widen C3's record grammar to `.*` | malformed-record case |
  | M11 | Drop C3's `head` equality check | sha-mismatch case |
  | M12 | Drop C3's `jsonl ⊆ artifact` direction | omitted-failing-record case |
  | M13 | Ignore fence state in C3's locator | decoy-heading-inside-a-fence case |
  | M14 | Remove one `settings.json` permission entry | member-set invariant in `install.bats` |

- **Invariants**:
  - *(app-enforced, RT10 — dogfood)* Every deny fixture has a paired allow fixture adjacent to the boundary. A suite for these three scripts that is itself deny-only would be self-refuting.
  - *(app-enforced, R50 v)* No test mutates the tracked worktree. Fixtures are built in `mktemp -d` scratch repos. **Every `run-verified.sh` invocation sets `VERIFY_EVIDENCE="$WORK/evidence.jsonl"` explicitly and runs with cwd inside the scratch repo**, and each test asserts its own evidence file's exact record count — an append-only shared file would otherwise let an earlier test's record satisfy a later test's assertion, giving order-dependent false greens.
  - *(app-enforced)* Isolation is checked by `[ ! -e "$REPO_ROOT/.triangulate-evidence.jsonl" ]` and `git status --porcelain --ignored` after the suite. A plain `git status --porcelain` check would have been vacuous had the file been gitignored.
- **End-to-end test for R50's motivating failure**: in a scratch repo, wrap a command that writes an output file **and** exits 2; assert the file exists, the wrapper exits 2, and the record carries `"exit":2` plus the scratch repo's real HEAD. Paste that record into a `## Verification Evidence` fence and assert C3 exits 1 citing the non-zero exit. Paired allow: the same command succeeding, same artifact present, C3 exits 0. Neither half alone reproduces the failure — the composition is the test.
- **Acceptance criteria**: `bats tests/` reports **exactly** the pre-change 905 plus the new files' own counts, asserted per file with `bats --count tests/<file>.bats` — a `≥905` criterion is satisfied by 905 with every new file uncollected. `git status --porcelain` empty after the run.

## Go/No-Go Gate

| ID | Subject | Status |
|-----|---------------------------------------------------|---------|
| C1 | `check-deny-only-guard.sh` (RT10 detector) | pending |
| C2 | `run-verified.sh` (R50 evidence recorder) | pending |
| C3 | `check-verification-evidence.sh` (R50 evidence gate) | pending |
| C4 | `## Verification Evidence` artifact section | pending |
| C5 | Rule-row and phase wiring, `resolve-contained.sh` extraction | pending |
| C6 | Tests | pending |

## Testing strategy

Framework: bats, fixture repos under `mktemp -d`. Every contract enumerates axes and takes fixtures from the cross-product's boundary cells, with unclaimed cells named (RT10 clause 2, applied to ourselves).

**C1 axes** — grammar (Jest/Vitest, bats status, hook decision) × deny form (each implemented alternative, none) × allow form (each implemented alternative, absent) × diff position (deny line in `+` set, untouched) × file classification (test path, non-test path, excluded path) × guard-subject gate (passes, fails) × expectation (flag, silent). Claimed: every implemented alternative in both directions, both diff positions, all three file classifications, both gate outcomes, plus the two real-corpus silence cases. Unclaimed and named: mixed files holding one covered and one deny-only guard (`SC5`); grammars beyond the three (`SC4`); C1's own bats file, which is unconditionally silent under its own detector because a detection-only script always exits 0 (`SC8`).

**C2 axes** — command exit (0, non-zero) × argv escape class (plain, each representable escape, unrepresentable) × evidence path (default, contained override, symlinked leaf, two-hop chain, `..` through a symlinked dir, unwritable) × worktree state (git clean, git dirty, no-git) × argc (0, 1, many). Claimed: each single-axis boundary plus the compound cells that carry distinct behavior — *command fails **and** evidence write fails* (exit `st`, message still printed), *unrepresentable argument **and** successful command* (exit 121, no record). Unclaimed and named: concurrent invocations against one evidence file (`SC12`).

**C3 axes** — heading (absent, present, duplicated, inside a fence) × N/A line (exact, near-miss, absent) × fence (backtick, tilde, absent, mismatched run length) × record (valid, malformed, empty `cmd`) × `exit` (0, non-zero) × `head` (matches, differs) × `dirty` (false, true) × jsonl (absent, supplied-matching, supplied-with-extra, supplied-with-missing). Claimed: each branch with its paired allow case, plus the near-miss-N/A × jsonl-supplied cell. Unclaimed and named: indented code blocks, Setext headings, container-nested sections (`SC9`).

## Considerations & constraints

- **Scope contract**:
  - `SC1` — "boundary-adjacent" (RT10 clause 1) is not mechanically checkable. Owner: human review, permanently.
  - `SC2` — axis-combination coverage (RT10 clause 2) is not mechanically checked. Owner: human review, permanently.
  - `SC3` — evidence provenance. A hand-authored block can carry fabricated exit statuses; the jsonl cross-check raises cost but is a local file the author can write. This control is a gate against *forgetting* (including omission, now checked in both directions) — not against *lying*. Owner: out of scope, no follow-up planned; tamper-evidence needs a trust anchor this repo lacks.
  - `SC4` — grammars beyond Jest/Vitest, bats status, and hook decision (pytest, Go, RSpec). Owner: v2.
  - `SC5` — file-level granularity: a file holding both a covered guard and a deny-only guard stays silent. Owner: v2.
  - `SC6` — no CI surface exists, so the new scripts are reachable only from bats tests and skill prose (`VC1`). Making the seven existing detectors CI-wired predates this PR. Owner: separate plan.
  - `SC7` — **R50 preconditions (ii) input resolution, (iv) toolchain pinning, (v) run isolation, (vi) gate reviewability are not mechanized.** Only (i) and a decided subset of (iii) are. A `bats tests/` run whose glob matched nothing exits 0 and produces a valid `"exit":0` record; a tool invoked through an auto-fetching launcher records the same clean shape. Owner: human review, permanently. The R50 rule row must enumerate this, or a reader inside a 50-line checklist will read "Mechanical detection" as "covered".
  - `SC8` — C1 cannot classify its own test file (detection-only scripts always exit 0, so its bats file is unconditionally silent under its own detector). The dogfood invariant for C1 is human-reviewed. Owner: human review, permanently.
  - `SC9` — C3's block locator is not closed against arbitrary Markdown: indented code blocks, Setext headings, and container-nested sections are unhandled. Fence state, both fence characters, and section uniqueness are handled. Owner: human review; revisit if a Markdown parser ever becomes available under requirement 6.
  - `SC10` — the evidence record carries no pass count, because capturing the wrapped command's stdout would violate R44. R50's reviewer action gets the exit status and subject sha from the record and the pass count from the transcript. Owner: human review, permanently.
  - `SC11` — `run-verified.sh` sits outside `check-orphaned-checks.sh`'s candidate set (its basename matches no alternative in that hook's `CHECK_NAME_RE`), so it is permanently outside the repo's orphan net. Owner: accepted; the alternative is renaming the script to satisfy a detector, which is worse.
  - `SC12` — concurrent `run-verified.sh` invocations against one evidence file are not serialized. Owner: accepted; Phase 3 verification is sequential by construction.
- **Risk — C1 false positives**: a project keeping rejection tests in one file and acceptance tests in a sibling will flag. Mitigation: `EXTRA_ALLOW_ASSERTION_RE`, now covered by an acceptance criterion rather than named as an untested capability. Accepted: this is a *report*, not a block, so the cost is a reviewer sentence.
- **Risk — twin drift between C2 and C3** (RT9): mitigated by the round-trip test over a named argv corpus. Without the corpus the round-trip would pass over `run-verified.sh true` and prove nothing.
- **Risk — PR size.** Round 1 grew this from three scripts to three scripts plus a library extraction, two `install.bats` invariants, and six wiring surfaces. Splitting C1 (RT10) into its own PR and keeping C2/C3/C4 for a second is viable: C1 shares no code with the R50 half, and the extraction of `resolve-contained.sh` belongs with the R50 half. Round 2 reviewers should judge whether the combined diff is reviewable; the default is to keep them together because the two rule rows and `folding.md` §3 change once rather than twice.
- **Dependency**: none on PR #114 — merged at `3014e77`; `main` carries R47–R50/RT10.

## User operation scenarios

1. **Phase 2 round, TS project**: a path-containment validator lands with three rejection cases. `check-deny-only-guard.sh main` flags the file Major; the developer adds the boundary-adjacent allow case (the benign path that merely resembles a traversal); silent.
2. **Phase 2 round, this repo**: a new `block-*.sh` gate lands with `tests/block-*.bats` asserting `[[ "$output" == *'"decision":"block"'* ]]` and no approve assertion — the idiom this repo actually uses, and the one v1's vocabulary missed. Flagged; the fix is the paired approve case proving the gate still permits the legitimate write. (`tests/block-sensitive-files.bats`, which already has 50 approve assertions, stays silent — a pinned acceptance case.)
3. **False positive**: a project splits `validator.reject.test.ts` and `validator.accept.test.ts`. The reject file flags; the reviewer records the disposition or sets `EXTRA_ALLOW_ASSERTION_RE`.
4. **Phase 3 round**: at Step 3-1 the orchestrator runs `run-verified.sh --start-round`; verification commands then run as `bash hooks/run-verified.sh bats tests/`, output unchanged, exit status the command's own, one record each. At Step 3-4 the records are pasted into `## Verification Evidence`; `check-verification-evidence.sh <artifact> <sha> <jsonl>` validates the block before the round is reported complete.
5. **The failure R50 exists for**: a type-check exits non-zero but still emits its declaration file. The author writes "declarations generated — verification complete". The record carries `"exit":2`, and C3 exits 1 on it.
6. **The failure round 1 found**: the author re-runs after a fix and pastes only the green record. The jsonl still holds the `"exit":2` line, `jsonl ⊆ artifact` fails, and C3 exits 1 naming the omitted record.
7. **Stale block**: an evidence block is carried forward from the previous round. Every record is green, but `head` does not equal the reviewed sha, and C3 exits 1 quoting both.
8. **Round with nothing to verify**: a docs-only round writes the exact N/A line; C3 exits 0.
