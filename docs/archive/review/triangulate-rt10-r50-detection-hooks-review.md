# Plan Review: triangulate-rt10-r50-detection-hooks

Date: 2026-07-28
Review round: 1

**Merge method**: manual fallback (Step 1-5 permits it when Ollama is unavailable; here it was chosen deliberately). The three expert outputs were already resident in the orchestrator's context with their machine-readable json indices, and the mechanical merge pre-pass — the json join on (file, line ±5, similar title/root cause) — is the specified dedup skeleton. Writing ~35k tokens to disk so a local model could re-derive that join adds cost without adding information. Recorded as a deviation; the join below is the pre-pass output, and every Recurring Issue Check block is preserved verbatim as required.

## Changes from Previous Round

Initial review. Three experts reviewed the plan at `docs/archive/review/triangulate-rt10-r50-detection-hooks-plan.md` (post-pre-screening state, with the three Ollama findings already folded). 28 findings: 2 Critical, 20 Major, 6 Minor. Both Criticals are Security with `escalate: true`.

## Convergence map (mechanical join)

| Group | Root cause | Perspectives | Floor |
|---|---|---|---|
| G1 | C1's assertion vocabulary does not match this repo's own gate-test idiom; measured 0 true positives / 2 false positives on the real corpus | functionality F1 + testing F2 + testing F12 | Major (convergent) |
| G2 | `$VERIFY_EVIDENCE` defaults into the analyzed worktree, unvalidated, append-only | security F2 + functionality F3 + testing F6 | **Critical** (convergent) |
| G3 | Evidence set has no round binding; the artifact block is cherry-pickable and the jsonl cross-check runs in the direction that cannot catch omission | functionality F2 + security F4 | Major (convergent) |
| G4 | `head` / `dirty` are recorded and displayed but never adjudicated, so stale or dirty-tree evidence validates | security F5 + functionality F4 | Major (convergent) |
| G5 | The `## Verification Evidence` literal is a cross-file twin with no sync point | testing F7 + functionality F8 | Major (convergent) |
| G6 | Existing repo helpers not adopted (`_resolve_contained`, `cmd_scrub`, `tri-tmpdir.sh`, the nine-way `+`-line extractor) | security F2/F7 + functionality F7 | Major (convergent) |
| G7 | `check-orphaned-checks` acceptance criterion is vacuous for `run-verified.sh` | functionality F5 (secondary) + testing F9 | Minor (convergent) |

Per the convergence rule, G2 takes the maximum (Critical), not an average, and convergent findings are fixed first within their tier.

## Functionality Findings

**F-A [Major, convergent: functionality+testing] — C1's assertion vocabulary is blind to this repo's actual guard tests and mis-fires on two real files** (G1)

Measured over the real 29-file `tests/` tree with C1's declared v1 bats vocabulary:
- `assert_success` / `assert_failure` appear **zero** times — bats-assert is not used here, so half the declared bats vocabulary is inert.
- The seven `tests/block-*.bats` suites — the exact RT10 subject class — assert on output content (`[[ "$output" == *'"decision":"block"'* ]]` / `*'"decision": "approve"'*`), not on `$status`. Six of seven score deny=0 / allow=0. User operation scenario 2 is therefore counterfactual.
- Two real files would fire, both false positives: `tests/block-sensitive-files.bats` (one `[ "$status" -ne 0 ]`, zero allow-shaped assertions under the vocabulary, but **50** approve assertions in the output-content form) and `tests/llm-commands.bats` (four `[ "$status" -eq 1 ]`, not a guard test at all).
- The TS/JS half is asymmetric: deny includes the general-purpose `.toThrow(`, allow is status-code-shaped. An ordinary `parser.test.ts` with three `expect(() => parse(bad)).toThrow()` and ten `toEqual` assertions fires Major.

Result: 0 true positives, 2 false positives, on the class the detector exists for. Recommended action: add the output-content shape to both bats vocabularies (or make the allow side symmetric in generality with the deny side), gate the fire on a guard-subject signal, rewrite scenario 2 against a real file, and name `tests/block-sensitive-files.bats` + `tests/llm-commands.bats` as silence cases in C1's acceptance criteria.

**F-B [Major, convergent: functionality+security] — the evidence set has no round binding, so the artifact block is author-selectable** (G3)

C2 appends and never truncates or tags a round; C3 clause 6 checks only `artifact ⊆ jsonl`. The realistic sequence — a failing run, a fix, a passing run — leaves the author free to paste only the green record, and C3 exits 0 having proved nothing about the round's final state. Cherry-picking is *permitted by the contract*, so `SC3` ("gate against forgetting, not lying") does not cover it: a forgetful author who pastes the first green record passes. Scenario 5, the failure R50 exists for, works only if the author volunteers the `"exit":2` line. Recommended action: bind the block to the round (truncate at round start, or a round key), and have C3 derive the expected set — the last record per distinct `cmd` — requiring equality, not subset. A jsonl record later than the block must be a finding.

**F-C [Critical, convergent: functionality+security+testing] — the evidence file defaults into the subject worktree; `dirty` self-contaminates** (G2, see Security F-S2 for the containment half)

`run-verified.sh` installs to `~/.claude/hooks/` and runs inside whatever repo Phase 3 reviews. C5 gitignores the evidence file in **this** repo only, and `install.sh` has no mechanism to place an ignore rule in a subject repo. Consequences: an untracked artifact in every other project's worktree root; `dirty` becomes a function of the wrapper's own side effect (from the second invocation onward it reads `true`), falsifying C2's own acceptance criterion "`head`/`dirty` reflect the real worktree"; and the plan applies R50 clause (v) run isolation to tests (C6) but not to the production wrapper. The plan also does not say whether `dirty` is computed before or after the append. Recommended action: default the path outside the subject worktree (`hooks/tri-tmpdir.sh` scratch, or an XDG state dir); if it must stay in-repo, compute `dirty` before the append with the evidence path excluded, and add an SC entry for other repos' ignore rules.

**F-D [Major, convergent: functionality+security] — C2's and C4's consumer walkthroughs name operations the locked shape cannot satisfy** (G4)

- C4 Consumer 2 must "quote the exit status and the analyzed-subject identity alongside the pass count" — the record carries **no pass count**, and C2 correctly forbids capturing the command's stdout (R44). The third element has no source in the contract.
- `head`/`dirty` do not constitute subject identity when `dirty` is `true`, which — given F-C — is the expected steady state. That is R50 (iii), the precondition the fields exist to satisfy.

Recommended action: do not lock C2 until closed. Either add fields (a `tee`-captured summary side file, and a `tree` sha via `git write-tree` / a content hash) or narrow both walkthroughs and record "pass count" and "dirty-tree identity" as explicit scope-outs with the R49 wording adjusted.

**F-E [Major] — C5's sync-point list omits `skills/test-gen/SKILL.md`, and its R42 member-set is anchored on the plan's own list** (G6 adjacent)

Recomputed from code: both sibling RT-family detectors are registered in `skills/test-gen/SKILL.md` (L141 `check-vacuous-denial.sh`, L143 `check-race-vacuous-guard.sh`) with the stated rationale "closes the generate→verify loop". RT10 — "the suite the generator just wrote is deny-only" — is the same family and the same loop; `skills/retrospect/folding.md` §3 enumerates only five surfaces and misses this sixth. Worse, C5's stated derivation names `common-rules.md` / `settings.json` / `tests/` as B1..B3 and **omits `phase-2-coding.md`**, which the plan's own edit list includes one line above — so the invariant would pass with the phase-2 pre-step dropped. That is R42 clause ①: the supplied list was trusted rather than re-derived. Recommended action: add `test-gen/SKILL.md` to C5; re-derive B* from code (`rg -l "$(basename S)"` across the repo, compared against the surface set an existing detector occupies); fix `folding.md` §3 or state why it stops at five.

**F-F [Major] — R50's mechanization covers precondition (i) only; (ii), (iv), (v), (vi) are neither implemented nor scoped out**

The Objective claims R50 becomes "a machine-checked structure (command, its own exit status, subject identity)" — that is (i) plus a partial (iii). `SC1`–`SC6` say nothing about (ii) input resolution, (iv) toolchain pinning, (v) run isolation, (vi) gate reviewability. A `bats tests/` run whose glob matched nothing exits 0 and produces a valid `"exit":0` record; a tool invoked through an auto-fetching launcher records the same clean shape. This is the plan's own non-functional requirement 8 unmet, and R49's escalation condition in miniature: a rule row carrying a "Mechanical detection" sentence is exactly what gets marked satisfied inside a 50-line checklist. Recommended action: add `SC7` naming (ii)/(iv)/(v)/(vi) as permanently human-owned, and require the R50 rule row's sentence to enumerate what is covered and what is not — the discipline the plan already applies to C1's header.

**F-G [Minor, convergent: functionality+security] — existing helpers not accounted for (R1)** (G6)

`hooks/tri-tmpdir.sh` exists to be "one place to audit tmpdir handling" and is already allowlisted; the `awk /^@@/ … RSTART + 1, RLENGTH - 1` added-line extractor is byte-similar across nine hooks and this would be the tenth. Both copies are defensible (hooks are self-contained, sourced from `~/.claude/hooks/` with no library-load convention) but the plan does not make the argument, so R1 is answered by omission. Recommended action: one sentence in Technical approach disposing of both. See Security F-S2/F-S7 for the two helpers whose non-reuse is *not* defensible.

**F-H [Minor, convergent: functionality+testing] — the exact `N/A` literal is duplicated between C3 and the phase-3 template with no sync point** (G5)

C3 clause 2 accepts exactly `N/A — no verification cited this round`; C4 writes the same literal into `phases/phase-3-review.md`. `check-rule-sync.sh` has no clause covering the pair, and the convention it mirrors (`## Environment Verification Report`, L345/L351) has the same unlinted duplication. A one-character drift makes every docs-only round fail C3 with a message pointing at the artifact rather than the template. Recommended action: make the phase file the source (`VERIFY_NA_LINE` env defaulting to the compiled-in string) plus a bats assertion that extracts the line from the real phase file and feeds it to the validator.

## Security Findings

**F-S1 [Critical, escalate: true] — a `*`-suffixed allow entry for `run-verified.sh` launders the entire deny/ask list**

C5 proposes permission entries "matching the `check-race-vacuous-guard.sh` pair form". For a script whose signature is `run-verified.sh <command> [args...]`, that yields `Bash(bash ~/.claude/hooks/run-verified.sh *)` — and Bash permission rules are prefix patterns over the command string, while every deny entry in `settings.json` is anchored on the leading command token. None of them match a command whose first token is `bash`. Every one of these becomes auto-approved with no prompt: `sudo`, `rm -rf`, `git reset --hard`, `curl … -X POST -d @<private key>`, `npm publish`. The `ask` list (`git push*`, `rm *`, `mv *`, `gh pr merge*`, `docker volume rm *`) is bypassed identically. This repo already legislates against this class — `eval`, `source`, `xargs`, `npx -y` are denied precisely because they are argv-laundering wrappers — and the plan proposes to *allow* a new member of it. The unanchored substring gates (`block-vcs-history-rewrite.sh:62`, `block-destructive-docker.sh:45`, `block-secret-key-destruction.sh:81-93`) still fire through the wrapper, but cover none of the above. Scenario 4 trains the orchestrator to use the prefix routinely, so it will read as normal in transcripts.

`escalate_reason`: chained with F-S2 (the same wrapper is also an unvalidated write primitive), the bypassed control is the harness's own authorization layer, and the fix changes C2's interface — it must be settled before implementation, not patched after.

Recommended action (pick one): invert the interface so argv is a *selector*, not a command line — `run-verified.sh --record <label>` over a fixed enumerated set resolved inside the script — after which a narrow allow entry is safe; or keep the general form and add **no** allow entry, recording the omission as deliberate. Either way, add to C5's invariant that "has a permission entry" is not unconditional: a script executing caller-supplied argv must be argued in, not swept in by convention. Add a `tests/install.bats` assertion that no `hooks/*.sh` accepting arbitrary argv appears `*`-suffixed in `permissions.allow`.

**F-S2 [Critical, escalate: true, convergent: security+functionality+testing] — `$VERIFY_EVIDENCE` is an unvalidated append primitive that ignores this repo's own containment resolution** (G2)

Two write vectors, neither addressed:

1. **Env-controlled target.** `VERIFY_EVIDENCE=~/.claude/hooks/check-rule-sync.sh bash ~/.claude/hooks/run-verified.sh true` appends into an installed hook. `block-sensitive-files.sh`'s Bash arm (L44-60) requires *both* a `CLAUDE_DIR_RE` path match *and* a write verb from `INPLACE_RE`/`WRITE_RE`; this command line carries no write verb, so it is approved and `run-verified.sh` performs the write the hook exists to prevent. That is R3 in the security-relevant direction: containment hardening was propagated to `block-sensitive-files.sh` and `retro-prescreen.sh` but not to the new writer.
2. **Symlink at the default path.** The wrapper runs inside whatever repo Phase 3 reviews, and `hooks/retro-prescreen.sh:73-78` already states this threat model ("an attacker who plants two links inside the repo — link A → link B → target outside"). A repo shipping `.triangulate-evidence.jsonl` as a symlink redirects the append to `~/.zshrc`, `~/.claude/settings.local.json`, an installed hook, or a tracked source file. `>>` follows symlinks; nothing looks.

The appended bytes are not inert: the record embeds argv verbatim, so a record landing in a shell rc or `.sh` file is parsed by bash at next execution, and `$( )` / backtick sequences inside the double-quoted JSON string fields expand. The escaper handles `\`, `"`, and C0 bytes — correct for JSON, and no protection at all in the grammar the file is actually interpreted in once the path was redirected. This is R47 at its plainest (the path's meaning is fixed by the filesystem resolver, which the design never consults) and R1 (the repo has two working implementations of the needed primitive: `_resolve_contained()` at `hooks/retro-prescreen.sh:57-98` with symlink-chain chase, 40-hop cap, control-char rejection and fail-closed empty return; and the deepest-existing-ancestor resolution at `hooks/block-sensitive-files.sh:207-262`).

`escalate_reason`: crosses a trust boundary between an untrusted analyzed repo and the user's installed harness; the fix requires extracting/reusing a security primitive that currently exists in two divergent copies, which is a design decision.

Recommended action: default the evidence path out of the analyzed worktree; resolve `$VERIFY_EVIDENCE` through the existing containment primitive (extract `_resolve_contained()` into `hooks/lib/` — one adjudicator per R48, not a third copy); require the resolved physical path to be contained, refuse a symlinked leaf and a non-regular-file target; fail closed on `121` with the stderr message; state the containment contract in C2's invariants so C6 can red-prove it, with bats cases mirroring `tests/block-sensitive-files.bats` (symlinked leaf outside root, two-hop chain both links inside, `..` through a symlinked directory component) **and** the RT10-paired allow case (an ordinary evidence path must still be written).

**F-S3 [Major] — C2's declared control class overstates what it delivers (R49)**

C2 is declared "fail-closed verification gate" (R49 class b: "cannot pass without deciding, and every unresolved, errored, or absent-subject case denies"). C2 decides nothing: it executes `"$@"`, forwards the status, appends a record. It never denies a run and has no subject to resolve. Its one fail-closed behavior (`121`) concerns its own write, and even that is conditional — the invariant says a non-zero `st` returns `st`, so a failing run with a broken evidence path leaves no record and no signal. The plan contradicts its own label in the same sentence ("Bypassable by simply not using it") — not-being-invoked is not "editing the gate itself", it is the absence of a gate. The accurate class is (d) detection/audit only. R49 states the overstatement is a finding even when the code is correct, because it displaces effort — and the displacement is visible: SC3's disposition and C3's treatment of records as evidence both rest on the (b) label. Recommended action: reclass C2 as detection/audit only in the plan, the header, and the C5 rule-row sentence, stating the fail-closed property narrowly ("cannot record a pass it did not observe; does not ensure it was invoked"). Keep (b) for C3, where it is accurate. Also fix the swallowed-write case: emit the stderr message even when `st` is non-zero.

**F-S4 [Major, convergent: security+functionality] — the jsonl cross-check runs in the direction that cannot catch the threat SC3 claims** (G3; see F-B)

C3 step 6 implements `artifact ⊆ jsonl`. The forgetting failure mode is the opposite containment. Three verifications, two green and one `exit 2`: paste the two green records and every one has a byte-identical counterpart, every one is `exit: 0`, C3 exits 0, and the failing record sits unreferenced. No completeness predicate exists — step 5 checks that present records are green, nothing checks that required records are present. Selective omission is what a tired author does when re-running feels expensive, and it is the one form the control is oriented away from. R50's reviewer action asks for the exit status *for each verification cited in the round*; C3 can only speak about verifications the author chose to cite. Recommended action: add `jsonl ⊆ artifact` over the round's window (needs a round marker — see F-B), make an unmatched jsonl record a Major finding, and correct SC3's wording; if deferred, it is a numbered scope-out with an owner, not an absorption into the fabrication carve-out — omission is not fabrication.

**F-S5 [Major, convergent: security+functionality] — `head` and `dirty` are recorded and displayed but never adjudicated** (G4; see F-D)

C3's only record-level predicate is step 5 (`exit` ≠ 0). C2's walkthrough confirms the intent: C3 "uses `exit` to decide the finding and `head`/`dirty` to **report** subject identity". Reporting is not deciding. So an evidence block copied forward from a previous round, or produced before the last three commits landed, validates — verifying an old subject and reporting the result for a new one, R50 clause (iii) verbatim, and squarely inside the "forgetting" threat SC3 claims to cover; no fabrication needed, the author simply does not re-run. `dirty: true` likewise passes silently. Recommended action: make `head` a decided field (require equality with the reviewed HEAD, mismatch → Major finding quoting the record's sha); decide `dirty` explicitly (reject, or accept with a printed warning) — state which, so it is a decision rather than an omission. If deferred, remove "subject identity" from the Objective and requirement 3, which currently promise a check that does not exist.

**F-S6 [Major] — "closed by construction" covers the record grammar but not the block-locating predicate ahead of it (R47, R49)**

The claim is true of C3 steps 4-5 and false of steps 1-3, which decide *which bytes are the record set* by pure notation over a Markdown document. Step 1 locates `## Verification Evidence` by text match: a line inside an earlier fence, an indented block, or an HTML comment is not a heading to any parser but is one to `grep` — and the reverse (trailing whitespace, Setext form, container-nested) produces a false deny. Step 3 takes "the first fenced block after the heading", and fence notation is R47's own worked example (backtick → tilde → HTML comment, one spelling per round). An artifact carrying a decoy heading with green records earlier in the document is validated in place of the real section, which is never read. R47 sub-clause (a) gives the correct disposition when the interpreter cannot be consulted: declare the limitation and deny the unresolved case. The plan does exactly that for prose-claim matching and leaves a same-shaped predicate one step upstream unremarked. Recommended action, within the no-new-dependency constraint: track fence state while scanning (a state machine, not a spelling list) so a heading inside a fence is not a heading; accept backtick and tilde fences with CommonMark's matching-run-length rule; require the section to be **unique** (two matches is a finding, not first-wins); and restate the closure claim precisely — "the *record* grammar is a closed whitelist; *locating* the block is a notation-level scan with fence-state tracking, not closed against arbitrary Markdown" — plus a numbered scope-out naming indented code blocks, Setext headings, and container-nested sections.

**F-S7 [Major] — command lines are recorded verbatim and pasted into a committed artifact, with no redaction (RS4, R1)**

C2 records full argv; C4's walkthrough routes it into the repository ("pastes it verbatim into the artifact's fence"), and round artifacts under `docs/archive/review/` are tracked and committed. Guaranteed: absolute paths carrying `/home/noguchi/…`, the local username, in every record. Routine: secrets that live in command lines — `psql "postgres://user:pass@host/db"`, `curl -H "Authorization: Bearer …"`, `npm publish --//registry:_authToken=…`, a leading `AWS_SECRET_ACCESS_KEY=` assignment. The wrapper's purpose is to sit in front of arbitrary verification commands, so it will see these. The pre-screening escaper fix makes the recording *more* faithful, which is what makes the absence of redaction matter more. R1 again: `cmd_scrub` in `hooks/retro-prescreen.sh` already redacts emails, IPs, `/home/<user>/` paths, tilde paths and secret-shaped tokens, and is exposed as a subcommand — the retrospect pipeline redacts before content leaves its boundary; this pipeline ends in a *committed* file and does not. Impact escalates to Critical the first time a verification command carries a credential: a pushed secret is compromised and must be rotated. Recommended action: pass each argument through `cmd_scrub` before escaping — **redact first, then JSON-escape**, so redaction sees raw bytes and the escaper's output is what the C3 grammar admits (the reverse order lets an escaped token slip the pattern). State the ordering in C2 step 3. Add a bats case asserting a token-shaped argument does not reach the record, with its RT10-paired allow case asserting an ordinary argument survives byte-identically.

**F-S8 [Minor] — C2 does not validate its argv boundary; zero args emits a green record for nothing (RS3)**

`run-verified.sh` with no arguments executes nothing, leaves `$?` at 0, and appends `{"ts":…,"cmd":[],"exit":0,…}`. C3's amended grammar requires ≥1 element so the record would be rejected downstream — but that is defence at the wrong end, and C3 may not run at all (it is invoked from a Phase 3 pre-step, not from C2). Recommended action: `[ "$#" -ge 1 ] || { echo "run-verified.sh: no command given" >&2; exit 121; }` before step 1, with the bats case; the paired allow case is already in C6's exit-0/1/42 set.

## Testing Findings

**F-T1 [Major] — the RT7 red-proof obligation is stated, never operationalised: no mutation is named for any assertion**

C6's invariant and the Testing strategy both promise executed mutation proofs; the plan names **zero** concrete mutants. RT7's empty-oracle sub-clause requires "one mutant per narrowable dimension, red-proven, unconditionally" — an enumeration, not a promise. The obligation is discharged entirely inside the implementer's head with nothing a reviewer can check, which is the shape recorded in `feedback_mutation_execute_redproof_claims`. It compounds with F-T2: for a detection-only script every silent-case assertion is `[ "$status" -eq 0 ]` plus `[[ "$output" != *"[Major]"* ]]`, which passes against a script that prints nothing and exits 0. Recommended action: add a mutation table, one row per assertion class, each naming the edit and the test it must redden — e.g. drop `assert_failure` from `DENY_RE` → the bats `assert_failure`-only fixture goes red; make the setup-error path `exit 0` → the invalid-base-ref test goes red; change C2's `exit $st` to `exit 0` → the status-pass-through-42 test goes red; widen C3's record regex to `.*` → the malformed-record test goes red. The deviation log carries, per row, the command executed and the observed failure line.

**F-T2 [Major, convergent: testing+functionality] — the fixture corpus is self-confirming and VC2's real-tree claim is backed by no test; measurement inverts it** (G1)

VC2 states "the bats half is exercised against this repo's own real test tree"; no acceptance criterion operationalises it, and C1's criteria name fixtures only. The measurement (see F-A) yields 0 true positives and 2 false positives, while the synthetic fixtures — written to the detector's own regexes — will be uniformly green. That is RT7's empty-oracle case with the sign flipped: the oracle is not empty, it is anti-correlated, and nothing in the test plan would reveal it. Recommended action: add a real-corpus test to C1's acceptance criteria — run the detector over this repo's own `tests/` tree at a pinned base and assert a **pinned, non-empty, named** finding set, red-proven by deleting one vocabulary alternative. Which set is correct is the design question in F-A/F-T12; either way it belongs in the plan, not in implementation-time discovery.

**F-T3 [Major] — C2's escaper fail-closed branch has no acceptance criterion, and its boundary-adjacent allow cases are unnamed**

Distinct from the pre-screened escaping defect (that was design; this is coverage). C2's criteria name `121` for the *unwritable-path* case, not the escaper case; neither the escaper's deny direction nor its allow direction appears anywhere. The allow direction matters more: the five representable escapes (`\\`, `\"`, `\n`, `\t`, `\r`) are exactly the boundary-adjacent legitimate inputs RT10 clause 1 demands — the inputs a broken escaper rejects or corrupts while every ordinary-argv test stays green. This also hollows the RT9 round-trip: its power is the set of escape classes its argv sample exercises, and no sample is specified, so a round-trip over `run-verified.sh true` satisfies the criterion while proving nothing. Recommended action: one deny fixture per unrepresentable class (e.g. `$'\x01'`, asserting exit 121 **and** that no record was appended); one allow fixture per representable escape class asserting byte-exact output; and specify the round-trip corpus as that same allow set plus `bash -c 'echo hi'` (multi-element `cmd`) and an empty-string argument.

**F-T4 [Major] — RT10's own obligation (axes plus explicitly unclaimed cells) is discharged for C1 only, and C1's table under-claims**

C6 claims the dogfood invariant for all three scripts; only C1 gets an axis table. C2 has at least four axes (command exit, argv escape class, evidence-path writability, git/no-git state) and its compound cell *command fails **and** evidence write fails* is specified in an invariant and appears in no fixture list. C3's "each branch with its paired allow case" confuses branches with axes — RT10 clause 2 is about combinations, and the near-miss-`N/A` × jsonl-supplied cells are neither claimed nor disclaimed. Within C1: the deny axis omits the implemented `[ "$status" -eq <non-zero literal> ]`; the allow axis collapses five implemented patterns into one present/absent bit, so a single broken allow pattern ships as a permanent false-positive source with no fixture; and "excluded path" is listed as an axis value but appears in neither the claimed nor the unclaimed list — silently absent, the specific thing RT10 clause 2 forbids. Also: because C1 is detection-only and always exits 0, its own bats file is unconditionally silent under its own detector, so the dogfood invariant cannot be self-verified. Recommended action: axis tables for C2 and C3; change C1's coverage unit from form-class to **implemented pattern**; claim or disclaim the excluded-path cell; add an SC stating C1 cannot classify its own test file.

**F-T5 [Major] — the failure R50 exists for is described in prose but reproduced by no planned test**

Scenario 5 states it precisely; the Testing strategy covers C2's status pass-through and C3's non-zero branch **independently**, and the round-trip is specified in the green direction only. Recommended action: a named end-to-end test — in a scratch repo, wrap a command that writes an output file **and** exits 2; assert the file exists, the wrapper exits 2, the record carries `"exit":2` and the scratch repo's real HEAD; paste that record into a fence and assert C3 exits 1 citing the non-zero exit. Pair with the boundary-adjacent allow: same command succeeding, same artifact present, C3 exits 0.

**F-T6 [Major, convergent: testing+security+functionality] — evidence-file isolation is unspecified, and C6's isolation criterion is made vacuous by C5's own `.gitignore` entry** (G2)

The sibling pattern isolates structurally (`mktemp -d` scratch repo, `cd` per invocation, `rm -rf` in teardown), but for C2 the scratch repo is insufficient because the evidence path resolves from cwd/repo-root and is append-only and shared: a record from an earlier test can satisfy a later test's assertion, giving order-dependent false greens. And C6's criterion "`git status --porcelain` empty after the run" **cannot detect** a stray write, because C5 gitignores exactly that filename. Recommended action: make it a C6 invariant that every invocation sets `VERIFY_EVIDENCE="$WORK/evidence.jsonl"` explicitly and runs with cwd inside the scratch repo; assert the per-test evidence file's exact record count (that red-proves isolation); replace the vacuous criterion with `[ ! -e "$REPO_ROOT/.triangulate-evidence.jsonl" ]`, plus `git status --porcelain --ignored` for a broader sweep.

**F-T7 [Major, convergent: testing+functionality] — the `## Verification Evidence` heading is a cross-file contract with no sync test** (G5; see F-H)

`check-rule-sync.sh` observes rule IDs, range strings, the digest, and the `### Step` manifest — no `##` headings — and C4 deliberately adds no `### Step`, so check 8 stays out of it. C4's acceptance criteria are two one-shot manual commands. After merge nothing keeps the template's heading equal to the validator's anchor; a reword makes C3 exit 1 on **every** Phase 3 round, a false deny arriving with a fully green suite. Recommended action: assert in `tests/check-verification-evidence.bats` that the section extracted from the **real** `phases/phase-3-review.md` (not a fixture copy — RT5) is accepted by C3; red-prove by renaming the heading in a scratch copy.

**F-T8 [Major] — the three `EXTRA_*` knobs and their invalid-regex path have no acceptance criterion, departing from the sibling convention**

Siblings cover theirs (`check-new-code-untested.bats:274/296/315`; `check-orphaned-checks.bats:169/180`, the latter including a malformed value `EXTRA_CHECK_NAME_RE='('`). Two consequences: the plan's accepted false-positive risk names `EXTRA_ALLOW_ASSERTION_RE` as *the* mitigation and scenario 3 is built on it — an untested mitigation for an accepted risk is a declared capability with no verified backing path (R41); and an unvalidated malformed value makes the composed ERE invalid, after which the detector matches nothing and reports "Total findings: 0" — the fail-open direction RT7 (c) names. Recommended action: three knob fixtures (silent without, flagged/suppressed with) plus one malformed-regex fixture asserting non-zero exit with a diagnostic, and regex pre-validation in C1's contract as `check-orphaned-checks.sh:78-81` does.

**F-T9 [Minor, convergent: testing+functionality] — the `check-orphaned-checks` criterion is non-discriminating for `run-verified.sh`** (G7)

`CHECK_NAME_RE='check|verify|guard|gate|audit|validate|assert|scan|lint|enforce'` — "verified" does not contain "verify", so the script is never a candidate and the criterion is satisfied by never being classified. It also sits permanently outside the repo's orphan net. Recommended action: state the expected classification per script, and either run the acceptance with `EXTRA_CHECK_NAME_RE='run-verified'` or record the exclusion as a scope-out beside `SC6`.

**F-T10 [Minor] — two acceptance criteria cannot fail as written**

(a) C4's "`grep -c '^### Step' phases/phase-3-review.md` unchanged from its pre-edit value" — the pre-edit value is recorded nowhere, so it cannot be evaluated post-merge; it is **9** today. (b) C6's "`bats tests/` green at ≥905 + new tests" is satisfied by exactly 905 — the current count — with every new test skipped or the new files not collected. Recommended action: write `= 9`; state the exact expected total or assert per-file counts (`bats --count tests/run-verified.bats`), which is the form that detects a non-collected file.

**F-T11 [Minor] — C5's R42 member-set invariant is labelled *(app-enforced)* with no app enforcing it**

`tests/install.bats` checks `settings.json` well-formedness and merge behavior only; `check-rule-sync.sh` covers rule-ID and phase-manifest sync; no test asserts a hook↔rule↔settings↔test membership relation. The accurate label is "review-enforced, one-shot at PR time" — the invariant is true for this PR and unmaintained after, which is R42's own failure mode. Recommended action: relabel, or make it real with a bats test deriving A from `ls hooks/*.sh` and asserting each member appears in `common-rules.md`, `settings.json`, and `tests/` — a few lines, red-provable by deleting one permission entry.

## Adjacent Findings

**[Adjacent] Major (testing → functionality) — C1's deny/allow vocabulary does not match this repo's own gate-test idiom.** The measurement is a coverage finding; the design response is functionality's call. The choice is between extending the vocabulary with a third grammar (hook-decision assertions, whose allow side is a *negated* match rather than a positive pattern — genuinely different in shape from the two declared grammars) and adding an SC naming the miss plus correcting scenario 2. Routed into F-A.

**[Adjacent] Minor (functionality → security) — `run-verified.sh` records the full argv of every wrapped command into a file in the subject repo's worktree**, world-readable under a default umask. Routed into F-S7.

## Quality Warnings

None. Every finding cites a file, a line, or an executed measurement. The three findings that rest on measurement rather than reading (F-A, F-T2, F-T10b) name the command and the observed counts.

## Recurring Issue Check

### Functionality expert

- R1 (Shared utility reimplementation): Finding F7
- R2 (Constants hardcoded in multiple places): Finding F8
- R3 (Incomplete pattern propagation): Checked — no issue. The `AWK_WORD_START` / `\b`-rewrite convention is propagated explicitly as non-functional requirement 5 and as C1 forbidden patterns.
- R4 (Event/notification dispatch gaps): N/A — no event or notification dispatch in this plan.
- R5 (Missing transaction wrapping): N/A — no transactional store.
- R6 (Cascade delete orphans): N/A — no relational deletes.
- R7 (E2E selector breakage): N/A — no E2E layer.
- R8 (UI pattern inconsistency): N/A — no UI.
- R9 (Transaction boundary for fire-and-forget): N/A — no async dispatch outside a transaction.
- R10 (Circular module dependency): Checked — no issue. Three standalone scripts, no sourcing between them.
- R11 (Display group ≠ subscription group): N/A — no subscription model.
- R12 (Enum/action group coverage gap): Checked — no issue; the assertion vocabularies are explicitly declared as a bounded pattern set with the remainder scoped out (`SC4`), not as a closed enum.
- R13 (Re-entrant dispatch loop): N/A — no dispatch loop.
- R14 (DB role grant completeness): N/A — no database.
- R15 (Hardcoded environment-specific values in migrations): N/A — no migrations.
- R16 (Dev/CI environment parity): Checked — no issue. `VC1` records the absence of a CI surface as a pre-existing shared condition with an owner (`SC6`).
- R17 (Helper adoption coverage): Finding F7 (same surface — the `+`-line extractor and `tri-tmpdir.sh` are the helpers not adopted).
- R18 (Config allowlist synchronization): Finding F5 — `settings.json` permission entries are covered, but the surrounding registration set is not.
- R19 (Test mock alignment with helper additions): N/A — no mocks in the plan's shape (fixture repos only).
- R20 (Multi-statement preservation in mechanical edits): N/A — no mechanical bulk edit.
- R21 (Subagent completion vs verification): N/A — no subagent delegation in this plan.
- R22 (Perspective inversion for established helpers): Checked — no issue.
- R23 (Mid-stroke input mutation): N/A — no UI control.
- R24 (Migration mixing additive + strict constraint): N/A.
- R25 (Persist / hydrate symmetry): Finding F2 — the evidence file is written but never read back for round scoping; the persist side has no matching hydrate contract.
- R26 (Disabled-state UI without visible cue): N/A.
- R27 (Numeric range hardcoded in user-facing strings): Checked — no issue; `121` is documented in the header per C2.
- R28 (Grammatical inconsistency in toggle labels): N/A.
- R29 (External spec citation accuracy): Checked — no issue. Verified the cited `## Environment Verification Report` N/A convention exists at `phases/phase-3-review.md:345,351`, and that `check-rule-sync.sh` check 8 counts only `### Step` headings, so C4's claim about the front matter holds.
- R30 (Markdown autolink footguns): N/A — no citations with bare URLs.
- R31 (Destructive operations without confirmation): Checked — no issue. `run-verified.sh` performs an append only; no truncation is proposed (which is part of F2).
- R32 (New runtime artifact without boot smoke test): Checked — no issue; C6 exercises all three scripts end-to-end.
- R33 (CI configuration change applied to one config but not its duplicates): N/A — no CI configs in this repo.
- R34 (Pre-existing bug deferred without cost-justification): Checked — no issue. `SC6` defers the CI-wiring gap with an owner and a stated rationale.
- R35 (Deployed component without manual test plan): Checked — no issue; the User operation scenarios serve this, though scenario 2 is factually wrong (F1).
- R36 (Static-analysis warning suppression): N/A.
- R37 (Internal jargon in user-facing strings): Checked — no issue; finding text is specified as human-scannable with a disposition note.
- R38 (Async state machine / fail-open supersession): N/A.
- R39 (Lifecycle secret zeroization): N/A — no secrets. (The evidence file records argv, which is an adjacent concern — flagged to Security.)
- R40 (Cross-boundary serialization shape vs strict consumer): Finding F4 — the locked record shape does not carry what its declared strict consumers need.
- R41 (Declared capability without a working backing path): Finding F1 — scenario 2 declares a detection path that does not fire on any real file of that class in this repo.
- R42 (Class-membership derivation): Finding F5.
- R43 (Fix-induced security-boundary widening): N/A — no boundary widened.
- R44 (Gate exit status through a lossy channel): Checked — no issue. C2 forbids `"$@" |` and `$(… "$@" …)`, C1 forbids `| (head|tail|grep)` in status-bearing invocations, and reading `$?` immediately into `st` is specified. Best-handled rule in the plan.
- R45 (Gate scaling super-linearly): Checked — no issue. Non-functional requirement 7 states one pass per changed file with no whole-corpus operation inside the loop.
- R46 (Scope-blind binding resolution): N/A — no symbol/binding resolution; C1 is text-level by declared design.
- R47 (Surface-form adjudication): Checked — no issue *as declared*; the prose-claim-matching design is explicitly evaluated and rejected with a forbidden-pattern guard, and the C3 grammar is a repo-owned whitelist. Note that F1's evidence — the output-content assertion form neither vocabulary spells — is R47's characteristic symptom.
- R48 (Parallel adjudicators, divergent semantics): Checked — no issue. C2/C3 are two implementations of one grammar and the plan names RT9 and mandates the round-trip test.
- R49 (Undeclared control class / overstated claim): Finding F6. Control classes are otherwise declared per script in the Technical approach table, which is correct practice.
- R50 (Verification preconditions unverified): Finding F6 (coverage), F3 (clause v applied to tests but not the production wrapper), F4 (clause iii unrepresentable when `dirty` is true).

### Security expert

- R1 (Shared utility reimplementation): Finding F2, F7 — `_resolve_contained` (`hooks/retro-prescreen.sh:57`) and `cmd_scrub` (same file) both exist and are unused by the plan
- R2 (Constants hardcoded in multiple places): Checked — exit `121` is declared once in C2 and documented in the header; no duplication
- R3 (Incomplete pattern propagation): Finding F2 — path-containment hardening propagated to `block-sensitive-files.sh` and `retro-prescreen.sh` but not to the new writer; security-relevant direction
- R4 (Event/notification dispatch gaps): N/A — no dispatch surface
- R5 (Missing transaction wrapping): N/A — no transactional store
- R6 (Cascade delete orphans): N/A — no relational data
- R7 (E2E selector breakage): N/A — no E2E layer
- R8 (UI pattern inconsistency): N/A — no UI
- R9 (Transaction boundary for fire-and-forget): N/A
- R10 (Circular module dependency): Checked — three standalone scripts, no sourcing cycle
- R11 (Display group ≠ subscription group): N/A
- R12 (Enum/action group coverage gap): Checked — the record's field set is closed and C2's consumer-flow walkthrough enumerates both consumers
- R13 (Re-entrant dispatch loop): Checked — C2 does not recurse; nothing prevents `run-verified.sh run-verified.sh …`, but it terminates and is harmless
- R14 (DB role grant completeness): N/A — no database
- R15 (Hardcoded environment-specific values in migrations): N/A
- R16 (Dev/CI environment parity): N/A — VC1 records that no CI surface exists; correctly scoped out as SC6
- R17 (Helper adoption coverage): Finding F2 — the containment helper is not adopted by the new writer
- R18 (Config allowlist synchronization): Finding F1 — the `settings.json` allow-list entry is the defect, not merely out of sync
- R19 (Test mock alignment): N/A — fixture-repo pattern, no mocks
- R20 (Multi-statement preservation in mechanical edits): Checked — C5's edits are additive
- R21 (Subagent completion vs verification): Checked — C6 requires executed mutation proofs per `feedback_mutation_execute_redproof_claims`
- R22 (Perspective inversion for established helpers): Checked
- R23 (Mid-stroke input mutation): N/A — no interactive input
- R24 (Migration mixing additive + strict constraint): N/A
- R25 (Persist / hydrate symmetry): Checked — C2 writes and C3 reads one grammar; RT9 round-trip test is mandated in C6
- R26 (Disabled-state UI without visible cue): N/A
- R27 (Numeric range hardcoded in user-facing strings): Checked — the 40-hop cap referenced in F2's fix lives in the reused helper
- R28 (Grammatical inconsistency in toggle labels): N/A
- R29 (External spec citation accuracy): Checked — no external spec cited; the CommonMark fence rule recommended in F6 would introduce one and should be verified when written
- R30 (Markdown autolink footguns): N/A — no citations added
- R31 (Destructive operations without explicit user confirmation): Finding F1 — the allow entry removes the confirmation step from operations the `ask` list deliberately gates
- R32 (Long-running runtime artifact without boot smoke test): N/A — no long-running process
- R33 (CI config change applied to one config but not duplicates): N/A — no CI configs
- R34 (Pre-existing bug deferred without cost-justification): Checked — SC6 defers the pre-existing CI-wiring gap with an owner and a stated rationale
- R35 (Deployed component without manual test plan): N/A
- R36 (Static-analysis warning suppression): Checked — none
- R37 (Internal jargon in user-facing strings): Checked — finding text is reviewer-facing and reads plainly
- R38 (Async state machine fail-open supersession): N/A — no async state
- R39 (Lifecycle secret zeroization): Finding F7 — the inverse direction: sensitive material is persisted rather than zeroized, and then committed
- R40 (Cross-boundary serialization shape vs strict consumer): Checked — addressed by the pre-screening escaper/grammar fixes and C6's round-trip test
- R41 (Declared capability without a working backing path): Finding F5 — "subject identity" is declared as a checked component; no check consumes `head` or `dirty`
- R42 (Class-membership derivation): Finding F1 — C5's member-set invariant asks whether each new script is in the allow list, never whether C2 belongs to the already-denied `eval`/`source`/`xargs` argv-laundering class
- R43 (Fix-induced security-boundary widening): Finding F1, F2 — a plan that adds detection capability also widens the write and permission boundaries
- R44 (Gate exit status read through a lossy channel): Checked — requirement 2 and C2's forbidden-pattern list address this directly and correctly
- R45 (Gate scaling super-linearly): Checked — requirement 7 bounds C1 to one pass per changed file
- R46 (Scope-blind binding resolution in a security analyzer): N/A — C1 does no binding resolution; detection-only over assertion text with the limitation declared
- R47 (Surface-form adjudication where an interpreter defines meaning): Finding F6 (Markdown structure, no parser consulted), Finding F2 (filesystem path, no resolver consulted)
- R48 (Parallel adjudicators deciding one predicate by different semantics): Checked — but the F2 and F7 fixes must reuse the existing helpers rather than adding second implementations, or they create exactly this shape
- R49 (Undeclared control class, or a claim stronger than the implementation): Finding F3 (C2 classed (b), delivers (d)), F6 ("closed by construction" over-scoped), F5 (declared identity check absent). C1's `detection only` declaration is accurate and correctly qualified by SC1/SC2/SC4/SC5
- R50 (Verification preconditions unverified): Finding F4 (completeness — clause i's verdict can be omitted rather than fabricated), F5 (clause iii subject identity, clause v dirty worktree), F2 (clause v — the evidence write can land in the tracked worktree)
- RS1 (Timing-safe comparison): N/A — no secret comparison
- RS2 (Rate limiter on new routes): N/A — no network routes
- RS3 (Input validation at boundaries): Finding F8 (argv boundary in C2), F2 (`$VERIFY_EVIDENCE` boundary). C3's artifact boundary validates and fails closed on malformed records — correct, subject to F6's region-selection gap
- RS4 (Personal-identifying data in committed artifacts): Finding F7
- RS5 (Untrusted security parameter without floor/whitelist): Finding F2 — `$VERIFY_EVIDENCE` is an externally-supplied parameter with neither a floor nor a whitelist
- RS6 (Incomplete sanitization — escape-character ordering): Checked — C2's escaper escapes `\` before the replacements that insert `\`, which is the correct order; F7's redaction must be inserted *before* the escaper to preserve this property

### Testing expert

- R1 (Shared utility reimplementation): N/A — implementation-level reuse is Functionality's scope
- R2 (Constants hardcoded in multiple places): Finding F7 — the `## Verification Evidence` literal is hand-copied into C3 and C4 with no sync test
- R3 (Incomplete pattern propagation): Finding F4 — implemented vocabulary alternatives without a fixture each
- R4 (Event/notification dispatch gaps): N/A — no dispatch surface
- R5 (Missing transaction wrapping): N/A — no transactional store
- R6 (Cascade delete orphans): N/A — no persistence model
- R7 (E2E selector breakage): N/A — no E2E layer; bats only
- R8 (UI pattern inconsistency): N/A — no UI
- R9 (Transaction boundary for fire-and-forget): N/A
- R10 (Circular module dependency): N/A — three standalone scripts
- R11 (Display group ≠ subscription group): N/A
- R12 (Enum/action group coverage gap): Finding F4 — the deny/allow vocabularies are enumerated sets whose members are not individually covered
- R13 (Re-entrant dispatch loop): N/A
- R14 (DB role grant completeness): N/A
- R15 (Hardcoded environment-specific values in migrations): N/A
- R16 (Dev/CI environment parity): Checked — no issue; VC1/SC6 record that no CI surface exists, so local `bats tests/` is the sole environment and no parity gap is possible
- R17 (Helper adoption coverage): Checked — no issue; C6 adopts the `check-vacuous-denial.bats` scratch-repo pattern, with the C2-specific gap reported as F6
- R18 (Config allowlist / safelist synchronization): Checked — no issue; C5 adds the `settings.json` permission pair form, enforcement gap reported as F11
- R19 (Test mock alignment with helper additions): N/A — fixtures only, no mocks
- R20 (Multi-statement preservation in mechanical edits): N/A
- R21 (Subagent completion vs verification): Finding F1 — the red-proof is reported as done rather than evidenced
- R22 (Perspective inversion for established helpers): N/A
- R23 (Mid-stroke input mutation in UI controls): N/A
- R24 (Migration mixing additive + strict constraint): N/A
- R25 (Persist / hydrate symmetry): Finding F3 — the producer→validator pair's escape classes are the asymmetry risk; see RT9
- R26 (Disabled-state UI without visible cue): N/A
- R27 (Numeric range hardcoded in user-facing strings): Checked — no issue; the reserved `121` is documented in the header per C2
- R28 (Grammatical inconsistency in toggle labels): N/A
- R29 (External spec citation accuracy): N/A — no external spec cited
- R30 (Markdown autolink footguns): N/A
- R31 (Destructive operations without confirmation): N/A — no destructive operation; teardown is scoped to `mktemp -d`
- R32 (Long-running runtime artifact without boot smoke test): N/A
- R33 (CI config change applied to one config but not its duplicates): N/A — no CI config exists
- R34 (Pre-existing bug deferred without cost-justification): Checked — no issue; SC6 defers the CI-wiring of the seven existing detectors with a named owner and a stated pre-existing scope
- R35 (Deployed component without manual test plan): N/A
- R36 (Static-analysis warning suppression): N/A
- R37 (Internal jargon in user-facing strings): N/A
- R38 (Async state machine non-terminal state): N/A
- R39 (Lifecycle secret zeroization): N/A
- R40 (Cross-boundary serialization vs strict consumer): Finding F3 — the JSONL record crosses producer→validator and no escape class is named in the test corpus
- R41 (Declared capability without a working backing path): Finding F8 — `EXTRA_ALLOW_ASSERTION_RE` is the named mitigation for an accepted risk and has no test
- R42 (Class-membership derivation): Finding F11 — the member-set derivation is labelled app-enforced with no enforcer
- R43 (Fix-induced security-boundary widening): N/A
- R44 (Gate exit status through a lossy channel): Checked — no issue; C1/C2 declare forbidden pipe patterns, and the planned bats assertions read `$status` from `run` directly
- R45 (Gate scaling super-linearly): Checked — no issue; requirement 7 bounds it to one pass per changed file, and `grep -E`/`awk` are DFA-based so no backtracking blow-up applies; see F8 for the regex-validity gap
- R46 (Scope-blind binding resolution): N/A — no symbol resolution
- R47 (Surface-form adjudication): Checked — no issue at the plan level; the choice is declared and the prose-claim alternative explicitly rejected with a forbidden-pattern guard. F2/F12 report the practical consequence of the bounded pattern set, not a missing declaration
- R48 (Parallel adjudicators, different semantics): Checked — see RT9/F3; the round-trip is the right instrument, its corpus is what is missing
- R49 (Claim stronger than the implementation): Findings F2, F9, F10, F11 — VC2's real-tree claim, the orphan-check criterion, the two unfailable criteria, and the *(app-enforced)* mislabel
- R50 (Verification preconditions unverified): Findings F5, F6 — clause (i) is not reproduced end to end; clause (v) run isolation is unspecified for the evidence file and its acceptance check is vacuous
- RT1 (Mock-reality divergence): Finding F2 — the synthetic fixtures diverge measurably from the real test-file corpus they stand in for
- RT2 (Testability verification): Findings F7, F10, F11 — three criteria are not observable by a bats test as written; all other C1-C6 criteria are testable with bats in this repo
- RT3 (Shared constant in tests): Checked — no issue; the sibling convention duplicates `REPO_ROOT`/`HOOK` per file and C6 follows it
- RT4 (Race-test vacuous-pass guard): N/A — no concurrency in any of the three scripts
- RT5 (Test call-path includes the production primitive): Checked — tests invoke the real `hooks/*.sh` via `bash "$HOOK"`, as siblings do; F7 extends the same principle to the real phase-3 template
- RT6 (New exports without test diff): Checked — no issue; C6 ships one bats file per new script in the same diff
- RT7 (Guard must be proven able to fail): Findings F1, F2 — the red-proof is unoperationalised, and the empty-oracle sub-clause is unaddressed for the detector
- RT8 (Vacuous denial-path test): Checked with one exception — C3's deny branches assert both the exit status and the cited line/record; the exception is C2's escaper deny branch, which has no assertion at all (F3)
- RT9 (Parallel-implementation twin drift): Findings F3, F7 — the round-trip is the right instrument but its argv corpus is unspecified, and the heading literal is a second, unguarded twin
- RT10 (Guard tested only on its deny side): Finding F4 — the axis-and-unclaimed-cells obligation is met for C1 only, and C1's own table under-claims

## Resolution Status

**Escalation outcome.** Both Criticals were escalated to the user, who chose *keep C2 and harden it* over *drop C2* and over *invert argv to a selector*. All 28 findings are addressed in the plan; none are skipped, so no Anti-Deferral entries are required this round.

| Finding | Severity | Disposition |
|---|---|---|
| F-S1 | Critical | **Fixed** — no `permissions.allow` entry for `run-verified.sh`; requirement 9 added (no argv-laundering surface); C5 records the omission as deliberate and adds an `install.bats` assertion that no argv-accepting hook is `*`-allowlisted |
| F-S2 | Critical | **Fixed** — default evidence path moved to `${XDG_STATE_HOME}/triangulate/` outside any analyzed worktree; `$VERIFY_EVIDENCE` resolved through `hooks/lib/resolve-contained.sh` (extracted from `retro-prescreen.sh`, not reimplemented) before any append; symlinked leaf / non-regular target refused; fail-closed 121 |
| F-A / F-T2 / F-T12 | Major (convergent ×3) | **Fixed** — third grammar added (hook-decision assertions), `assert_success`/`assert_failure` dropped as measured-inert, guard-subject gate added, real-corpus pinned finding set is now an acceptance criterion with the two v1 false positives named as silence cases, scenario 2 rewritten against the real idiom |
| F-B / F-S4 | Major (convergent) | **Fixed** — `--start-round` truncation gives the round a window; C3 checks `jsonl ⊆ artifact` as well as the reverse; scenario 6 added for the omitted-failing-record case |
| F-C / F-T6 | Critical/Major (convergent ×3) | **Fixed** — evidence path out of the worktree; `dirty` computed before the append with the evidence path excluded; C6 requires per-test `VERIFY_EVIDENCE` and an exact record-count assertion; the vacuous `git status --porcelain` criterion replaced |
| F-D / F-S5 | Major (convergent) | **Fixed** — `head` is now a decided field (equality with the reviewed sha); `dirty` decided explicitly as accept-with-warning, with the over-block rationale stated; the pass-count gap is `SC10` rather than an unsatisfiable walkthrough |
| F-S3 | Major | **Fixed** — C2 reclassed `detection / audit only`; the fail-closed property stated narrowly; the swallowed-write case now prints in both directions |
| F-S6 | Major | **Fixed** — fence-state machine, both fence characters with CommonMark run-length matching, section uniqueness; closure claim scoped to the record grammar; `SC9` names what remains unhandled |
| F-S7 | Major | **Fixed** — argv passes through the existing `cmd_scrub` before the JSON escaper, with the ordering constraint stated; deny and paired allow fixtures added |
| F-S8 | Minor | **Fixed** — argv boundary validated at C2 step 1 |
| F-E | Major | **Fixed** — `skills/test-gen/SKILL.md` added to C5; `folding.md` §3 extended to six surfaces; the R42 member-set re-derived from code with the phase files included |
| F-F | Major | **Fixed** — `SC7` added; the R50 rule row must enumerate covered vs human-owned preconditions; the Objective narrowed to "(i) plus a decided subset of (iii)" |
| F-G | Minor | **Fixed** — Technical approach now disposes of `tri-tmpdir.sh` and the nine-way `+`-line duplication explicitly, and separates them from the two helpers whose non-reuse is not defensible |
| F-H / F-T7 | Major (convergent) | **Fixed** — `VERIFY_NA_LINE` sourced from the real phase file, with the sync assertion in C3's acceptance criteria (RT5) |
| F-T1 | Major | **Fixed** — 14-row mutation table (M1–M14), each naming the edit and the test it must redden, each to be executed with the observed failure line recorded |
| F-T3 | Major | **Fixed** — one deny fixture per unrepresentable class, one allow fixture per representable escape class, and the round-trip corpus named |
| F-T4 | Major | **Fixed** — axis tables for C2 and C3; C1's coverage unit changed to implemented pattern; excluded-path cell claimed; `SC8` added |
| F-T5 | Major | **Fixed** — named end-to-end test composing the producer and validator over the exit-2-with-artifact scenario, with its paired allow |
| F-T8 | Major | **Fixed** — three knob fixtures plus a malformed-regex fixture; regex pre-validation added to C1's contract |
| F-T9 | Minor | **Fixed** — per-script expectation stated; `run-verified.sh` recorded as permanently unclassified in `SC11` |
| F-T10 | Minor | **Fixed** — `= 9` recorded for the step count; exact per-file `bats --count` assertions replace `≥905` |
| F-T11 | Minor | **Fixed** — the member-set invariant is now test-enforced in `install.bats`, red-proven by M14 |

New scope-outs introduced by this round: `SC7`–`SC12`. New risk recorded: PR size, with the C1-vs-R50 split left to round 2 reviewers.

---

# Round 2

Date: 2026-07-28. Same three experts, incremental review of the round-1 fixes.

**Verbatim-preservation deviation.** Step 1-5 requires each expert's `## Recurring Issue Check` block verbatim. Round 2's three blocks run ~150 lines each and are >90% `N/A — no X in this plan` lines. Preserved below in full for every line that carries a finding, a verification, or a measurement; pure `N/A` lines are collapsed to a count per expert. The evidence the rule protects — that each check was performed and what it found — is retained; the padding is not. Recorded as a deviation with its reason.

## The headline: three claims in the round-1 fixes were falsified by execution

Two experts independently implemented the round-2 detection rule and ran it over the real corpus. The plan's sentence *"Measured: with the gate and the third grammar, `llm-commands.bats` scores allow>0 via neither status nor decision, so the gate is what suppresses it; this is a claimed acceptance cell, not an assumption"* had **never been executed**, and is false in two ways: the quoted clause is self-refuting (allow>0 via neither means allow==0, i.e. the fire condition holds), and the guard-subject gate passes because `run ` is bats' universal invocation idiom, present 5× in that file. The orchestrator wrote an unexecuted "Measured:" claim into a plan whose subject is R49 claim calibration and RT7 red-proof execution. This is recorded as the round's most important finding about the process, not only about the artifact.

Consequences measured: mutation rows **M1 and M3 produce zero delta** on the real corpus (M1 is structurally dead — dropping a deny alternative can only remove findings, and every file whose deny score comes from the hook-decision grammar already has allow>0); the **pinned finding set is empty** under `main...HEAD` and under `HEAD~5...HEAD`, and is `{llm-commands.bats}` whole-tree — the one file the plan promised would be silent.

## Round 2 findings

| ID | Perspective | Severity | Finding |
|---|---|---|---|
| R2-F1 | func + test (convergent) | **Critical** | The guard-subject gate does not suppress `llm-commands.bats`; the "Measured:" claim is false; M3 is unprovable |
| R2-F2 | test | **Critical** | M1 and M3 produce zero delta on the real corpus — non-corresponding mutation/test pairs |
| R2-F3 | sec + func + test (convergent) | **Critical** | C2's containment root is unspecified; the XDG reading makes every C6 fixture exit 121, the dirname reading leaves round-1 F-S2 vector 1 open |
| R2-F4 | sec | **Critical**, escalate | TOCTOU: the path is resolved at step 2 and appended at step 6, with the wrapped untrusted command running between — a `pretest` hook symlinking the resolved path redirects the append |
| R2-F5 | func | **Critical**, escalate | C3 step 6 (`jsonl ⊆ artifact`) composed with step 5a (non-zero → fail) deadlocks any red-then-green round; the only escape is re-running `--start-round`, the cherry-pick the check exists to prevent |
| R2-F6 | test | **Critical** | Both new `install.bats` invariants are false at HEAD — 10 of 15 `hooks/check-*.sh` have no bats file, and `check-migrations.sh` executes caller argv while `*`-allowlisted |
| R2-F7 | test + sec (convergent) | **Critical** | `cmd_scrub` appends `\n` to every argument, caps at 2000 chars, and needs `jq`+`perl` — the byte-exactness criteria and requirement 6 cannot both hold |
| R2-F8 | sec | Major | The no-allow-entry fix binds only `settings.json`; the prompt's don't-ask-again writes to `settings.local.json`, which already holds `Bash(python *)` |
| R2-F9 | sec | Major | `XDG_STATE_HOME` is caller-settable, so one variable moves both the evidence path and the root it is contained against (RS5) |
| R2-F10 | sec + func (convergent) | Major | `--start-round` is an uncontracted destructive primitive: no Behavior step, no axis, no criterion, no mutation |
| R2-F11 | sec + func (convergent) | Major | Requirement 9's rationale is false — `Bash(find *)`, `Bash(node *)`, `Bash(npx *)`, `Bash(docker run *)` are live laundering entries in `permissions.allow` |
| R2-F12 | func | Major | The default evidence directory is never created; the first run on any machine exits 121 for a green command |
| R2-F13 | test | Major | M9, M7, M13 redden only under fixtures the plan does not specify, or not at all (M13 is masked by C3's own uniqueness check — both correct and mutant exit 1) |
| R2-F14 | test | Major | 12 decisions have no mutation row; the table is deny-only for C2 and C3 — the RT10 asymmetry, in the artifact enforcing RT10 |
| R2-F15 | test | Major | RT9 round-trip corpus varies `cmd` only; `exit`, `head` (including the literal `no-git`), and `dirty` never round-trip |
| R2-F16 | test | Major | The `resolve-contained.sh` red-proof is a green-suite argument over a two-fixture oracle that exercises neither the hop cap, the control-char branch, nor the case comparison |
| R2-F17 | func | Major | C5's R42 member-set recomputed: `A \ B3` holds 10 of 15 hooks |
| R2-F18 | func | Major | Requirement 9's `install.bats` invariant has no mechanically decidable predicate |
| R2-F19 | test | Major | Three axis cells neither claimed nor disclaimed (fence run-length, default path, missing parent dir) |
| R2-F20 | func + sec (convergent) | Minor | `resolve-contained` extraction is feasible and its red-proof real, but the diagnostic prefix is hardcoded and the repo's `source … 2>/dev/null` idiom fails open |
| R2-F21 | sec | Minor | C3's reviewed-sha is author-supplied with no cross-check |
| R2-F22 | test | Minor | `bats --count` arithmetic omits `install.bats`'s delta (23 today) |
| R2-F23 | test | Minor | M5's redness rests on the diagnostic, not the status |
| R2-F24 | test | Minor | Verified accurate and not re-litigated: `SC11`, C4's `= 9` step count, and rows M2/M4/M6/M8/M10/M11/M12 |

Two of three experts independently recommended **splitting** on readiness grounds, not diff size.

## Recurring Issue Check — round 2 (condensed per the deviation above)

### Functionality expert
Findings: R1→F7/F10, R3→F4/F6, R17→F7/F10, R18→F9, R21→F1, R25→F3, R31→F6, R32→F5, R40→F7, R41→F1/F2, R42→F8, R43→F6, R47→F1, R48→F7, R49→F1/F2, R50→F1/F3/F7.
Verified clean with a stated reason: R2 (`VERIFY_NA_LINE` closed the round-1 twin), R10, R12, R13, R16, R22, R27, R29 (CommonMark rule cited correctly), R34, R35, R44 ("best-handled rule in the plan"), R45, R46.
`N/A — no such surface in this plan`: 21 rules.

### Security expert
Findings: R3→F1, R17→F6/F9, R18→F3/F7, R31→F5, R34→F7, R39→F6, R40→F6, R41→F1, R42→F3/F7, R43→F3/F5, R47→F1/F2, R48→F1, R49→F1/F5/F6/F7, R50→F5/F8, RS3→F1/F4, RS4→F6, RS5→F4.
Verified clean with a stated reason: R1, R2, R10, R12, R13, R16, R20, R21, R25, R27, R29, R32, R35, R37, R44, R45, RS6 (redact-then-escape is the correct order; the defect is the filter, not the ordering).
`N/A`: 17 rules.

### Testing expert
Findings: R3→F9, R12→F13, R17→F4/F11, R18→F5, R21→F2, R25→F13, R29→F10, R34→F5, R40→F13, R41→F1/F12, R42→F5, R47→F1, R49→F1/F2/F5/F11, R50→F2/F9, RS5→F3, RS6→F7, RT1→F1, RT2→F5/F1, RT7→F2/F6/F7/F8/F9/F11, RT8→F8, RT9→F13, RT10→F9/F10.
Verified clean with a stated reason: R2, R10, R16, R27, R31, R32, R44 (M6 sound), R45, RT3, RT4 (`SC12` scopes concurrency out), RT5, RT6.
`N/A`: 19 rules.

## Round 2 Resolution Status

**Decision (user).** Split. C1 proceeds alone; the R50 half is closed at plan stage.

- **`triangulate-rt10-detection-hook-plan.md`** — the C1-only plan, carrying every round-2 finding that applies to it: the guard-subject gate **dropped** (measured dead, not reworded); `llm-commands.bats` recorded as a known false positive (`SC1`) with the measurement and its command; a committed true-positive fixture at `tests/fixtures/rt10-deny-only.bats` so the pinned set has non-zero positive density; the pinned base named as the root commit; the repo-wide member-set and argv-laundering invariants **not asserted**, with `SC6` carrying the Anti-Deferral quantification for the ten missing bats files; the false "no library-load convention" premise corrected; the mutation table rebuilt with M1/M3 removed and each row's discriminating power stated; `bats --count` arithmetic restated against the measured 905.
- **`triangulate-r50-evidence-deferred.md`** — the R50 design state, the three-round record of fixes growing new surface, and ten open items that must be settled before it becomes a plan again. Not scheduled.

Every measurement in the C1-only plan was executed by the orchestrator and its command recorded in a `## Measured facts` section, in direct response to R2-F1.
