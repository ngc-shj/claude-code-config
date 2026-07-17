# Plan: pre-pr-gate-cache

Date: 2026-07-16
Branch: feature/pre-pr-gate-cache

## Project context

- Type: `config-only` repo content-wise, but the deliverables are executable
  shell hooks — treat as `CLI tool` (shell scripts + markdown skill docs).
- Test infrastructure: bats unit tests under `tests/` (no CI/CD pipeline).
- Verification environment constraints: none. All acceptance paths are
  `verifiable-local` (bats + manual hook invocation with synthetic JSON stdin).
  No paid services, no external network, no special hardware.

## Objective

`scripts/pre-pr.sh` (the project-local pre-PR aggregate gate) can currently be
executed up to three times against an identical source state within one
workflow:

1. Direct invocation by the /triangulate skill (Phase 2-4 item 3b, Phase 3-7)
2. `git push` — via the `check-pre-pr.sh` PreToolUse hook
3. `gh pr create` — via the same hook again

Each run is a full lint/test/build aggregate that routinely takes minutes.
Introduce a pass-cache: when the source state is byte-identical to the state
that last passed, skip re-execution. When anything changed, run as before.

## Requirements

Functional:

- F1: A successful `scripts/pre-pr.sh` run records a fingerprint of the source
  state that passed.
- F2: The PreToolUse gate (`git push` / `gh pr create`) skips execution and
  approves when the current fingerprint equals the recorded one and the record
  is within TTL.
- F3: Direct invocations from the /triangulate skill go through the same cache
  (both benefit from and populate it), so the push/PR-create that follows a
  passing direct run does not re-execute the script.
- F4: Any source change — tracked (staged or unstaged), untracked non-ignored
  file added/modified/removed, or new commit — invalidates the cache
  (fingerprint mismatch).
- F5: Failures are never cached. A blocked push retried on identical source
  re-runs the script (the user may have fixed the environment, not the tree).
- F6: Cache behavior is controllable: `PRE_PR_CACHE_TTL` (seconds; default
  3600; capped at 86400; `0` disables both skip and record).

Non-functional:

- N1: Fail-safe direction is "run the script". Any failure to compute the
  fingerprint or read the cache results in a normal full run, never a skip.
  (The cache is an optimization; a broken cache must not widen the gate —
  R43 direction.) An unparseable `PRE_PR_CACHE_TTL` is NOT a cache-integrity
  failure: it is a tuning knob and resolves to the default 3600 (capped) —
  a valid cached pass may still skip under the default. Cache-integrity
  failures run; tuning-knob parse failures merely lose the tuning.
- N2: Zero behavior change for repos without `scripts/pre-pr.sh`.
- N3: The skip decision is observable: a stderr breadcrumb states that the
  cached pass was used and its age.
- N4: Exit-status integrity (R44): in direct-invocation mode the wrapper
  propagates `scripts/pre-pr.sh`'s own exit status, never a pipeline
  aggregate's.

## Technical approach

Everything lives in `hooks/check-pre-pr.sh` (single file, shared functions for
both entry modes — this guarantees hook mode and direct mode compute identical
fingerprints and use identical cache paths). No new helper file: the logic is
~60 lines and has exactly one consumer.

- **Fingerprint** = SHA-256 over the concatenation of:
  1. `git rev-parse HEAD` (committed state)
  2. `LC_ALL=C git diff --no-ext-diff HEAD` — worktree vs HEAD, which covers
     both staged and unstaged tracked changes (`--no-ext-diff` disables
     external diff drivers so output is content-deterministic). Note: index
     content that differs from BOTH worktree and HEAD is deliberately not
     hashed — pre-pr.sh validates the worktree, and committing that index
     changes HEAD, which is a fingerprint miss anyway.
  3. per-file SHA-256 of every untracked, non-ignored file, deterministic
     pipeline (Phase 3 revision — paths are `./`-prefixed via a
     null-delimited read loop so dash-prefixed names are not parsed as
     options and a file named `-` is not read as stdin):
     `git ls-files --others --exclude-standard -z | LC_ALL=C sort -z | (cd root && while IFS= read -r -d '' f; do sha256sum -- "./$f" || exit 1; done)`
  Any git failure (not a repo, unborn HEAD, unreadable file → non-zero from
  the pipeline under `set -o pipefail`) → no fingerprint → full run (N1).
- **Cache file** = `$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass`,
  one line: `<sha256-hex> <epoch-seconds>`. Worktree-safe (`--git-dir` is
  per-worktree), never committed (lives inside the git dir), one file per
  repo/worktree, overwritten atomically (mktemp in the same dir + mv —
  mirrors the retro-state.sh precedent).
- **Read validation**: regular non-symlink file owned by the current user
  (`-O`, mirroring retro-state.sh's `_trusted_file` convention), line matches
  `^[0-9a-f]{64} [0-9]+$`; timestamp not in the future; age ≤ TTL. Anything
  else is a miss.
- **Record rule (mutation guard)**: fingerprint is computed BEFORE the run and
  recomputed AFTER a successful run; the cache is written only when the two
  are equal. pre-pr aggregate scripts commonly run formatters/codegen that
  mutate the worktree (documented in phase-2-coding.md "Worktree-drift note");
  a mutated tree was not itself validated, so it must not be recorded.
- **TTL**: guards against out-of-tree drift the fingerprint cannot see
  (dependency reinstall, toolchain upgrade). Default 3600 s.
- **Existing escape hatch unchanged**: `SKIP_PRE_PR_GATE=1` still bypasses the
  whole gate and takes precedence (checked before any cache logic).

### Entry modes

- **Hook mode** (default, stdin = PreToolUse JSON): current behavior, plus
  cache check before running and cache record after a passing run.
- **Direct mode** (`check-pre-pr.sh run`): CLI entry for the /triangulate
  skill's Phase 2-4 / Phase 3-7 direct invocations. Resolves the repo root
  with the same precedence as hook mode (`CLAUDE_PROJECT_DIR`, then
  `git rev-parse --show-toplevel`). On cache hit prints the skip breadcrumb
  and exits 0. On miss executes `bash scripts/pre-pr.sh` with output streaming
  straight through (no capture, no pipe — R44), records on success, and exits
  with the script's own status. Absent/non-executable script → note + exit 0
  (mirrors hook-mode no-op).

## Contracts

### C1 — `compute_fingerprint`

- Signature: `compute_fingerprint <repo_root>` → stdout: 64-char lowercase hex
  on success (exit 0); empty stdout + exit non-zero on any failure.
- Inputs hashed: HEAD sha, `git diff HEAD` bytes, sorted
  `<sha256>  <path>` lines for untracked non-ignored files.
- Invariants:
  - I1-1 (app-enforced): any git/hash sub-step failure yields exit non-zero —
    callers treat that as "no fingerprint → full run". No partial hash is ever
    emitted. (Schema-level enforcement is not expressible in shell; the bats
    red-proof in C6 is the compensating control.)
  - I1-2 (app-enforced): output depends only on repo content (HEAD, tracked
    diff, untracked file bytes) — not on cwd, locale, or time.
- Acceptance: same tree → same hash across hook mode and direct mode; touching
  one byte in a tracked file, staging a change, committing, or adding an
  untracked file each produce a different hash.

### C2 — cache read/write (`cache_path`, `cache_fresh`, `cache_record`)

- Signatures:
  - `cache_path <repo_root>` → stdout: absolute path inside the worktree's git
    dir; exit non-zero when git dir cannot be resolved.
  - `cache_fresh <repo_root> <fingerprint>` → exit 0 iff a valid cache entry
    matches the fingerprint and `0 <= now - stamp <= TTL`; exit 1 otherwise
    (missing, malformed, symlink, foreign-owned, mismatched, expired,
    future-dated, TTL=0).
  - `cache_record <repo_root> <fingerprint>` → writes `<fp> <now>` atomically;
    silently no-ops on failure (recording is best-effort; a failed record only
    costs a future re-run — fail in the safe direction). No-op when TTL=0.
- TTL resolution: `PRE_PR_CACHE_TTL` if it matches `^[0-9]+$`, else 3600
  (malformed value = lost tuning, not lost integrity — see N1; must not
  crash under `set -euo pipefail`, T19). A regex-accepted value MUST be
  base-10-normalized immediately (`TTL=$((10#$TTL))`) before any arithmetic:
  `^[0-9]+$` admits leading-zero values like `08`, which raise
  "value too great for base" in bash `[[ -gt ]]`/`$(( ))` contexts and would
  abort the hook under `set -e` (T19b red-proves this). The fallback is observable: a
  malformed value emits one stderr note —
  `check-pre-pr: PRE_PR_CACHE_TTL='<value>' is not a non-negative integer; using default 3600`
  — so a mistyped disable intent (`PRE_PR_CACHE_TTL=O` for `0`) is not
  silently dropped (mirrors the SKIP_PRE_PR_GATE breadcrumb principle:
  bypass/tuning events are observable). Effective TTL is capped at 86400
  (24 h): an oversized value accidentally exported in a shell profile must
  not silently turn one pass into an indefinite skip (review finding,
  Security F2; cap red-proven by T18).
- Invariants:
  - I2-1 (app-enforced): `cache_record` is called from exactly two sites —
    hook mode after observed exit-0 with pre==post fingerprint, direct mode
    ditto. No other write path exists.
  - I2-2 (app-enforced): a malformed, symlinked, or foreign-owned cache file
    is a miss, never an error that blocks the tool call (fail-open on cache
    infra, fail-safe on gate outcome: the script runs).
- Forbidden patterns:
  - pattern: `cache_record` appearing on any failure path — reason: F5,
    failures must never be cached.
  - pattern: `pre-pr\.sh[^\n]*\|` (gate stdout piped onward in the exec path)
    — reason: R44, the judged status must be the gate's own.
- Acceptance: see C6 test matrix.

### C3 — hook-mode cache integration

- Behavior delta, in order, after the existing `-x $SCRIPT` check:
  1. `fp=$(compute_fingerprint "$REPO_ROOT")` — on failure run as today.
  2. `cache_fresh` hit → stderr breadcrumb
     `check-pre-pr: scripts/pre-pr.sh already passed for identical source state (<age>s ago; PRE_PR_CACHE_TTL=0 to force) — skipping` →
     `{"decision": "approve"}`.
  3. Miss → run exactly as today; on success recompute fingerprint, record iff
     pre==post; approve. On failure block exactly as today (reason format
     unchanged).
- Invariants:
  - I3-1 (app-enforced): `SKIP_PRE_PR_GATE=1` check stays ahead of all cache
    logic (existing bypass precedence unchanged).
  - I3-2: the block path is byte-identical to current behavior (no cache
    interaction on failure).
- Consumer-flow walkthrough:
  - Consumer "Claude Code harness" (PreToolUse protocol) reads
    `{ decision, reason }` from stdout and uses `decision` to allow/deny the
    Bash call and `reason` as the transcript message. Both fields present on
    every path today; the new skip path emits the same `{"decision": "approve"}`
    shape. No new fields required.
  - Consumer "operator" (stderr) reads the breadcrumb line to understand why
    no run happened and how to force one (`PRE_PR_CACHE_TTL=0`). The
    breadcrumb names both — satisfiable from the message alone.
- Acceptance: push → pass → push again with clean tree does not execute
  pre-pr.sh a second time (observed via execution-counter fixture); any tree
  change in between re-executes.

### C4 — direct mode (`check-pre-pr.sh run`)

- Signature: `check-pre-pr.sh run` (no other args in v1). Exit status: 0 on
  cache hit, absent script, or passing run; 2 on usage error or unresolved
  repo root; otherwise `scripts/pre-pr.sh`'s own non-zero status.
- Behavior: repo-root resolution identical to hook mode
  (`CLAUDE_PROJECT_DIR`, then `git rev-parse --show-toplevel`) — but unlike
  hook mode, an UNRESOLVED repo root is an error, not a no-op: stderr
  `check-pre-pr: could not resolve repo root — gate not run` + exit 2. Hook
  mode is a safety net around an unrelated tool call, so approving there is
  correct; direct mode IS the gate execution the /triangulate phases rely
  on, and a silent exit-0 would read as "gate passed" at call sites that
  check only the exit status (review finding, Functionality F1).
  `SKIP_PRE_PR_GATE=1` honored with the same stderr breadcrumb; cache hit →
  skip message + exit 0;
  miss → `(cd "$REPO_ROOT" && bash scripts/pre-pr.sh </dev/null)` with stdout
  and stderr passed through untouched, then record-iff-pre==post on exit 0.
- Invariants:
  - I4-1 (app-enforced, R44): the mode's exit status on a run is captured from
    the `bash scripts/pre-pr.sh` invocation itself; no pipe, no `tee`, no
    filter between the script and the status test.
  - I4-2: unknown first argument → usage message on stderr + exit 2 (never
    silently treated as hook mode; hook mode is stdin-driven and takes no
    args).
- Consumer-flow walkthrough:
  - Consumer "/triangulate Phase 2-4 item 3b"
    (skills/triangulate/phases/phase-2-coding.md) reads the exit status to
    gate phase completion (`|| { echo "..."; exit 1; }`) and the streamed
    output to fix failures. Both are provided: status is the script's own,
    output is unbuffered passthrough.
  - Consumer "/triangulate Phase 3-7"
    (skills/triangulate/phases/phase-3-review.md) — same two fields, same
    usage.
  - Consumer "human operator running it ad hoc" reads stdout/stderr and `$?`.
    Same surface.
- Acceptance: failing script → same non-zero exit code out of the wrapper;
  passing run populates the cache such that a subsequent hook-mode push skips
  (the cross-pattern dedup that motivates this plan).

### C5 — /triangulate phase-doc call-site migration (R42 member-set)

Member-set derivation for the class "sites that EXECUTE scripts/pre-pr.sh
inside this config" — derived from code, not from the prompt:

```
rg -n 'bash ([^ ]*scripts/pre-pr\.sh|"\$SCRIPT")' hooks/ skills/
```

| # | Site | Disposition |
|---|------|-------------|
| 1 | hooks/check-pre-pr.sh:122 (hook exec) | cache-aware via C3 |
| 2 | skills/triangulate/phases/phase-2-coding.md:209 | rewrite to `bash ~/.claude/hooks/check-pre-pr.sh run` (C4) |
| 3 | skills/triangulate/phases/phase-3-review.md:404 | rewrite to `bash ~/.claude/hooks/check-pre-pr.sh run` (C4) |

Non-members (read, not execute): phase-2-coding.md:66 greps the script's text
for gate parity; check-orphaned-checks.sh matches the basename;
hooks/check-pre-pr.sh:18 is the hook's own header comment describing its
behavior, not an execution (its wording is updated anyway when the hook
gains cache logic). Unchanged.

- Both rewritten snippets keep their `[ -x scripts/pre-pr.sh ]` guard shape
  semantics via the wrapper's internal absent-script no-op, and keep an
  `|| { echo ...; exit 1; }` tail whose message is outcome-neutral —
  `"pre-PR gate did not pass — see output above; fix before proceeding"` —
  because the wrapper can exit 2 for "gate never ran" (unresolved repo root),
  where a "script failed" message would misstate what happened (exit status
  is the wrapper's = the script's own on real runs, per I4-1). The
  surrounding prose gains one sentence: identical-source re-runs are skipped
  by the pass-cache; `PRE_PR_CACHE_TTL=0` forces a run.
- The phase-3 "Push-time safety net" paragraph (phase-3-review.md:493-495)
  gains one clause noting the hook skips when the direct run already passed
  on an identical tree.
- Forbidden pattern: `bash [^ ]*scripts/pre-pr\.sh` ANYWHERE in
  `skills/triangulate/phases/*.md` — snippets AND prose — reason: raw
  invocations bypass cache population and re-introduce the triple run. The
  variant-tolerant regex also catches `bash ./scripts/...`, quoted and
  `$VAR/`-prefixed spellings, and the whole-file scope keeps T17's
  plain-grep mechanism sound (no fence-aware parsing needed). Rewritten
  prose refers to "a raw invocation of the script" or backticks the bare
  path without the `bash ` prefix. (The phase-2:66 grep line references the
  path as a filename argument to `grep`, not `bash`; the pattern anchors on
  `bash ` and does not match it.)
- Existing-test interplay: `tests/check-pre-pr.bats` "skill docs reference
  scripts/pre-pr.sh literally" requires the literal path to keep appearing in
  both phase docs. The rewritten sections retain prose/comment references to
  `scripts/pre-pr.sh`, so that test stays green; T17 (C6) adds the inverse
  assertion (no `bash [^ ]*scripts/pre-pr\.sh` invocation spelling remains —
  the variant-tolerant pattern, same as the C5 forbidden pattern above).

### C6 — bats coverage (extend tests/check-pre-pr.bats)

Fixture: pre-pr.sh test scripts append a line to `$TMPREPO/run-count` so
"executed vs skipped" is asserted by line count, not by output text.

| # | Scenario | Asserts |
|---|----------|---------|
| T1 | pass → identical tree → push again | approve, run-count stays 1 (cache hit), AND stderr breadcrumb substring `already passed for identical source state` present (N3 acceptance; mirrors the existing SKIP_PRE_PR_GATE breadcrumb test) |
| T2 | pass → modify tracked file → push | run-count 2 (fingerprint miss) |
| T3 | pass → add untracked file → push | run-count 2 |
| T3b | pass with dash-prefixed untracked file (`--help`) → change its content → push | run-count 2 (Phase 3 finding: without the `./` prefix, dash-named files are parsed as sha256sum options and silently drop out of the fingerprint, violating F4/I1-2) |
| T3c | pass with untracked file literally named `-` → change its content → push | run-count 2 (Phase 3 residual: `sha256sum -- -` still reads stdin — `--` ends option parsing but not the stdin operand convention; the `./` prefix closes the class) |
| T4 | pass → commit → push | run-count 2 (HEAD changed) |
| T5 | pass → backdate cache stamp to `now - 7200` (well beyond default TTL 3600) | run-count 2 (expired; wide margin tolerates backward clock steps) |
| T6 | PRE_PR_CACHE_TTL=0 → two passing pushes | run-count 2 (cache disabled, no skip, no record) |
| T7 | failing script → same tree → push again | block twice, run-count 2 (failures not cached) |
| T8a | malformed cache file content | run-count increments (miss), no crash |
| T8b | symlinked cache file | run-count increments (miss), no crash |
| T8c | cache file owned by another user | (documented as covered-by-code-review: `-O` check; not mechanically testable in unprivileged bats — creating a foreign-owned file requires root. Noted here so the gap is explicit, not silent) |
| T9 | `run` mode: failing script | wrapper exit == script exit (non-zero). R44 red-proof scope (Phase 3, mutation-verified): the mutations T9 turns red on are exit-status swallowing (`\|\| true` on the exec) and status flattening (non-zero mapped to a constant). A pipe inserted into the exec path is masked by the wrapper's own `set -o pipefail` (red only if pipefail is also removed); the static forbidden-pattern grep is the operative guard against pipes. It can NOT distinguish the explicit if-guard from raw errexit propagation — both exit with the script's own status; the guard exists for future code placed after the exec |
| T10 | `run` mode pass → hook-mode push | push approves with run-count 1 (cross-pattern dedup — the headline acceptance) |
| T11 | self-mutating script (touches a file during run) → push again | run-count 2 (pre≠post → not recorded) |
| T12 | future-dated cache stamp | run-count increments (miss) |
| T13 | `run` mode, no scripts/pre-pr.sh | exit 0, note printed |
| T14 | `run` mode, unknown arg | exit 2, usage on stderr |
| T14b | `run` mode with an extra argument (`run extra-arg`) | exit 2, usage on stderr (Phase 3 finding: I4-2's "no other args" is enforced, not silently discarded) |
| T15 | `run` mode outside any git repo, no CLAUDE_PROJECT_DIR | exit 2, stderr `could not resolve repo root` (C4 unresolved-root contract) |
| T16 | `run` mode (pinned — NOT hook mode): passing script deletes `.git` during its run | wrapper exit 0 AND the script's pass-through output present. The exit-0 assertion carries the RT7 red-proof: an unguarded post-run `compute_fingerprint`/`cache_record` under `set -euo pipefail` aborts the wrapper non-zero. ("No cache file recorded" is documented as a consequence, not asserted — the deleted `.git` makes it vacuous. Hook mode is NOT a valid home for this test: the hook exits 0 on every path, which would make the assertion vacuous.) |
| T17 | skill-doc contract: phase-2/phase-3 docs invoke `check-pre-pr.sh run`; whole-file `! grep -E 'bash [^ ]*scripts/pre-pr\.sh'` on both phase docs (variant-tolerant: also catches `bash ./scripts/...`, quoted and `$VAR/`-prefixed spellings; mechanism: plain whole-file grep, NOT fence-aware parsing) | extends the existing "skill docs reference scripts/pre-pr.sh literally" doc-drift test (which stays green via remaining prose references). C5 constraint making the whole-file grep sound: the rewritten phase-doc prose must not contain any `bash …scripts/pre-pr.sh` invocation spelling — refer to "raw invocation of the script" or backtick the bare path instead |
| T18 | `PRE_PR_CACHE_TTL=999999999`, cache stamp aged `now - 90000` (past the 86400 cap with a 3600 s backward-clock-step tolerance) → push | run-count increments (cap enforced ⇒ miss); reverting the cap turns this red (would skip: 90000 < 999999999) |
| T18b | `PRE_PR_CACHE_TTL=999999999`, cache stamp aged `now - 50000` (between default 3600 and cap 86400) → push | run-count stays 1 (skip): distinguishes "cap at 86400" from a spec-violating "oversized value → fall back to 3600" (red) or "treat as invalid/zero" (red). Refuses-to-fire complement of T18 |
| T19 | `PRE_PR_CACHE_TTL=abc` (malformed) with a fresh matching cache entry → push | no crash, skip occurs (resolves to default 3600 per N1/C2 — malformed tuning knob ≠ integrity failure), AND stderr note `is not a non-negative integer; using default` present |
| T19b | `PRE_PR_CACHE_TTL=08` (regex-accepted, base-8 trap) with a matching cache entry stamped `now - 100` → push | no crash (base-10 normalization applied), runs (age ≥100 > TTL 8 ⇒ miss; wide margin tolerates backward clock steps); an implementation skipping normalization in arithmetic contexts aborts under `set -e` and goes red |

RT7 proof-of-failure: T1/T10 prove the skip fires (guard can pass); T2-T5,
T7, T8a/T8b, T11, T12 prove the skip refuses to fire (guard can fail). T9
red-proves exit-status propagation by mutation (failing fixture). T16
red-proves the record path's fail-safe no-op via the run-mode exit-0
assertion. T18 red-proves the TTL cap (drop the cap → test goes red by
skipping); T18b proves the cap refuses to over-fire (values between default
and cap honored — red under fallback-to-3600 or treat-as-invalid). T19
proves TTL parsing cannot crash the hook and the fallback note is emitted;
T19b red-proves base-10 normalization via the `set -e` arithmetic abort.

Fixture hardening: `setup()` exports
`GIT_CEILING_DIRECTORIES="$(dirname "$TMPREPO")"` so git's upward repository
discovery can never escape the test tmp dir (matters for T16, where `.git`
is deleted mid-run and an outer repo would otherwise be discovered and
polluted; hardens every other test for free).

## Go/No-Go Gate

| ID | Subject | Status |
|----|---------|--------|
| C1 | compute_fingerprint (content-addressed source state) | locked |
| C2 | cache read/write with TTL + trust checks | locked |
| C3 | hook-mode cache integration | locked |
| C4 | direct mode `run` for skill call sites | locked |
| C5 | phase-doc call-site migration (R42 member-set) | locked |
| C6 | bats coverage incl. RT7 red-proofs | locked |

All contracts locked after plan-review round 5 (all experts: No findings).

## Testing strategy

- All C6 scenarios in `tests/check-pre-pr.bats` (existing harness: tmp git
  repo per test, JSON stdin via `run_hook`). New helper `run_direct` for C4,
  specified as `bash "$SCRIPT" run </dev/null` — stdin closed so a
  mode-dispatch regression falling through to hook mode's `INPUT=$(cat)`
  fails red immediately instead of hanging the bats suite.
- Full existing check-pre-pr.bats suite must stay green (regression bar: the
  no-cache paths are byte-compatible).
- Run: `bats tests/check-pre-pr.bats` locally; then the repo's full
  `bats tests/` before commit.

## Considerations & constraints

- The cache lowers the gate only for byte-identical trees that already passed
  once in the same repo/worktree within TTL. It is strictly narrower than the
  pre-existing `SKIP_PRE_PR_GATE=1` bypass.
- A cache file is attacker-writable only by an actor who can already write
  `.git/` — who could equally edit `scripts/pre-pr.sh` itself; no new trust
  boundary is crossed. Symlink/regular-file validation is still performed
  (repo convention, retro-state.sh precedent).
- `git diff HEAD` does not reflect ignored files or file-permission-only
  changes on some platforms — including permission-bit changes to
  `scripts/pre-pr.sh` itself or to files a gate inspects for mode-bit checks
  (e.g. "secrets file must be 0600"); TTL is the backstop for environment
  drift the fingerprint cannot see, and it bounds this window to 24 h at
  most (capped TTL).
- Trust assumption, stated explicitly: the cache is keyed on fingerprint +
  TTL only, with no binding to which invocation path or session recorded it.
  Any process operating inside the repo's trust boundary (same user, same
  worktree) is treated as the same operator — a `run`-mode pass in one
  terminal legitimately satisfies a push in another. This is the intended
  cross-pattern dedup, not an oversight.

### Scope contract

| ID | Deferred item | Owner / rationale |
|----|---------------|-------------------|
| SC1 | Raw `bash scripts/pre-pr.sh` runs typed manually by a human do not populate the cache | Accepted limitation; documented in the C5 prose note. The wrapper is the documented path. |
| SC2 | Out-of-tree state (node_modules, toolchain versions) is not fingerprinted | TTL (default 1 h) is the mitigation; hashing dependency trees is out of scope. |
| SC3 | rtk command-rewrite interplay | No change needed: the hook already substring-matches through the `rtk ` prefix; cache logic is downstream of the match. |
| SC4 | Submodule content changes not directly fingerprinted | `git diff HEAD` covers submodule pointer changes; intra-submodule dirt is out of scope v1. |

## User operation scenarios

- S1 (headline): /triangulate Phase 2-4 runs the aggregate via `run` mode
  (4 min). It passes. Phase 3 pushes: hook computes the same fingerprint,
  skips (<1 s), breadcrumb explains why. `gh pr create` follows: skip again.
  One execution instead of three.
- S2: Same flow, but review feedback changes one file between push and
  `gh pr create` → fingerprint miss → full run at PR-create. Correct: the
  changed tree was never validated.
- S3: pre-pr.sh fails at push (block). User fixes nothing, retries push →
  full run again (failures uncached) → blocks again with fresh output.
- S4: pre-pr.sh is a formatter-running aggregate that reformats a file during
  its run → pre≠post → nothing cached → next push runs it again on the now-
  stable tree, passes, caches. Second-order convergence, no false skip.
- S5: User suspects a stale skip (e.g. node_modules changed):
  `PRE_PR_CACHE_TTL=0 git push ...` forces a run for that invocation.

## Implementation Checklist

Impact analysis (Step 2-1) results:

- Files to modify:
  1. `hooks/check-pre-pr.sh` — C1 (compute_fingerprint), C2 (cache_path /
     cache_fresh / cache_record), C3 (hook-mode integration), C4 (`run`
     mode). Header comment updated (incl. line 18 raw-invocation wording,
     per C5 non-members note).
  2. `skills/triangulate/phases/phase-2-coding.md` (~line 208-210) — C5
     rewrite to wrapper invocation + one-sentence cache note.
  3. `skills/triangulate/phases/phase-3-review.md` (~line 403-405) — C5
     rewrite; ~line 493-495 safety-net paragraph gains the skip clause.
  4. `tests/check-pre-pr.bats` — C6 rows T1-T19b, `run_direct` helper,
     `GIT_CEILING_DIRECTORIES` in setup(), extended skill-doc contract test.
- Symbol-collision check: `compute_fingerprint` / `cache_fresh` /
  `cache_record` / `claude-pre-pr-pass` appear nowhere in hooks/ or tests/
  (clean namespace).
- Reuse (R1): atomic write pattern (mktemp + mv) mirrors retro-state.sh
  `_write_state`; trust checks mirror retro-state.sh `_trusted_file`
  (regular, non-symlink, `-O`). build-codebase-fingerprint.sh is unrelated
  (symbol-frequency, not content hash) — do not reuse.
- Existing tests impacted: "skill docs reference scripts/pre-pr.sh
  literally" (stays green via prose references — verified in review R4);
  all existing pass/block tests exercise the fingerprint-failure → full-run
  path for free (unborn-HEAD tmp repos).
- CI gate parity (Step 2-1 item 7): no `.github/workflows` — no CI gates to
  diff; this repo's local gate is `bats tests/`. No deferred-parity entries.
- This repo has no `scripts/pre-pr.sh` of its own — the hook's no-op path
  covers it; nothing to run at Phase 2-4 item 3b.
