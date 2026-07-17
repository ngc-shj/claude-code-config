# Code Review: pre-pr-gate-cache

Date: 2026-07-17
Review round: 1

## Changes from Previous Round

Initial review. Pre-pass: local LLM pre-screening raised one Minor
(unguarded `(cd && bash script)` under `set -e` in run_direct) — fixed in
de398b7 before expert launch. Ollama seed analyzers returned "No findings"
for all three perspectives; every expert performed independent verification
per the seed-trust advisory. Merge note: the three experts' json indexes
share no file/line overlap (mechanical join empty), so the prose merge is a
straight concatenation — Ollama merge-findings skipped as adding nothing
over the json-join skeleton.

## Functionality Findings

**F1 — Minor — `check-pre-pr.sh run <extra-arg>` silently dispatched to
run_direct, discarding extras (violates locked C4 "no other args in v1" /
I4-2)**
- hooks/check-pre-pr.sh:248 (dispatch). Verified empirically: `run extra-arg`
  exited 0 with the no-op note instead of usage + exit 2.
- **Resolution: Fixed.** Dispatch now requires `[ $# -eq 1 ]`; extras fall
  through to usage + exit 2. T14b added and green.

**F2 — Minor — phase-3-review.md safety-net paragraph said "Step 3-7 direct
run" but the gate invocation lives in Step 3-6**
- **Resolution: Fixed.** Wording corrected to "Step 3-6 direct run above".
  (The plan's own prose used "Phase 3-7" — historical artifact, left as-is;
  the shipped skill doc is what readers follow.)

## Security Findings

**F1 — Major — dash-prefixed untracked filenames parsed as sha256sum
options, silently excluded from the fingerprint (cache-poisoning path;
violates F4/I1-2)**
- hooks/check-pre-pr.sh:98-100. Verified empirically by the expert: an
  untracked file named `--help` made sha256sum print its help text (exit 0)
  instead of hashing the file; content changes to such files no longer
  invalidated the cache — a stale full-gate skip reachable by anyone with
  ordinary worktree write access. escalate: false (same trust boundary as
  editing scripts/pre-pr.sh itself; consequence is stale skip, not code
  execution).
- **Resolution: Fixed.** `xargs -0 -r sha256sum --` (explicit end-of-options)
  with an in-code comment. T3b added (content change in `--help` → miss) and
  red-proven against a no-`--` throwaway copy (stale skip reproduced → T3b
  assertion red). Plan C6 updated.

**F2 — Minor — TOCTOU window between cache_fresh's -L/-O validation and the
`head` read — Accepted**
- hooks/check-pre-pr.sh:148-152. A same-user actor can swap in a symlink
  between the checks and the read.
- **Anti-Deferral check**: acceptable risk.
- **Justification**:
  - Worst case: the read follows a symlink to an attacker-chosen file; the
    content is then regex-gated (`^[0-9a-f]{64} [0-9]+$`) and must ALSO
    byte-match the freshly computed fingerprint to cause a skip — an actor
    who can arrange that already has `.git/` write access and can fabricate
    a matching cache entry directly, or edit `scripts/pre-pr.sh` itself
    (the plan's documented trust boundary; no new capability is added).
  - Likelihood: low — requires a hostile same-user process racing a
    millisecond window for a result it can obtain without the race.
  - Cost to fix: an O_NOFOLLOW-style read is not expressible in POSIX
    shell/coreutils without adding a python/perl dependency to a hook that
    must stay dependency-light; the expert's own recommendation classifies
    the fix as "likely overkill".
- **Orchestrator sign-off**: acceptable-risk exception satisfied (three
  values stated; defense-in-depth layers — regex gate + fingerprint match —
  bound the blast radius to what the trust boundary already grants).

**F3 — non-issue (recorded)** — `mv` onto a symlinked cache path replaces
the symlink (rename semantics), it does not write through to the target.
Verified; closes that line of inquiry.

## Testing Findings

**F1 — Major — T9's claimed red-proof does not distinguish the de398b7
if-guard from raw errexit propagation**
- tests/check-pre-pr.bats T9. Expert reconstructed the pre-de398b7
  implementation and showed the wrapper exit code coincides with the
  script's own under BOTH implementations (errexit terminates with the
  failing command's status), across seven exit codes.
- **Resolution: Fixed (documentation) / production change rejected with
  reasoning.** The two implementations are observationally equivalent for
  the exit-status contract — a test cannot (and need not) separate
  observationally identical behaviors, and adding production output purely
  to make the guard testable would be over-engineering. What WAS wrong is
  the plan's claim that T9 red-proves "the de398b7 class": the mutation T9
  actually turns red on is a pipe/capture inserted into the exec path (the
  genuine R44 class). Plan T9 row rewritten to state the red-proof scope
  precisely and to document the errexit-equivalence limitation. The guard
  stays: it protects future code placed after the exec.

**F2 — Minor [Adjacent] — `run-count-$$` fixture path shared across all
@test cases in one bats invocation (latent parallel-run collision)**
- **Resolution: Fixed.** Counter now derives from the per-test-unique
  `$(basename "$TMPREPO")` at all 16 sites, including teardown cleanup.

**F3 — non-issue (recorded)** — T16's "no cache file recorded" is correctly
a documented consequence, not an assertion; verified consistent with plan.

## Adjacent Findings

- Testing F2 (fixture hygiene) — routed to orchestrator, fixed same round.

## Quality Warnings

None. All findings carried file:line + reproduced evidence (empirical
verification transcripts in each expert's session).

## Recurring Issue Check

### Functionality expert
- R1: pass (retro-state.sh patterns correctly reused — verified against
  source); R3: pass (forbidden raw-invocation pattern absent from phase
  docs, grep-verified); R34: pass; R41: pass (`run` capability genuinely
  wired at both call sites; F1 was validation completeness, not an unbacked
  path); R42: pass (member-set re-verified via the plan's rg — exactly the
  3-row table); R43: pass (malformed/negative/oversized TTL all fall back
  fail-safe, verified empirically); R44: pass (exit 47 propagated unchanged;
  no pipe in either exec path); all other rules n/a for this diff.

### Security expert
- R31: n/a; R43: held (every cache-miss path falls through to a full run —
  T2-T5, T7, T8a/T8b, T12, T18 green); R44: held (guarded if in run mode,
  direct `if (...) > file; then` in hook mode, no intermediate filter);
  RS1: n/a (fingerprint comparison is not a secret comparison); RS3: gap
  found → Security F1 (the git-paths→sha256sum-argv boundary lacked `--`),
  fixed this round; RS5: satisfied (TTL floored, normalized, capped, T18/
  T18b/T19/T19b green); RS6: no new sink (jq -Rs escaping unchanged);
  others n/a.

### Testing expert
- R44: investigated directly — implementation correct; the TEST's claimed
  coverage was overstated → Testing F1, resolved as documentation fix with
  scope-precise wording; RT7: T16 and T18/T18b mutation-tested by the
  expert and confirmed genuinely red-capable; T9's red-proof rescoped (see
  Testing F1); other R/RT rules: covered by the Phase 2 self-check baseline
  per round framing (incremental verification, no rote re-run).

## Environment Verification Report

N/A — no environment constraints declared in Phase 1 (all acceptance paths
verifiable-local; full bats suite + targeted red-proofs executed locally:
`bats tests/` 756/756 pre-fix baseline, `bats tests/check-pre-pr.bats`
50/50 post-fix).

## Resolution Status

| Finding | Severity | Status |
|---------|----------|--------|
| Sec F1 (sha256sum option-parse fingerprint gap) | Major | Fixed + T3b red-proven |
| Test F1 (T9 red-proof overstated) | Major | Fixed (plan claim rescoped); production change rejected with test-evidence reasoning |
| Func F1 (run extra-arg) | Minor | Fixed + T14b |
| Func F2 (Step 3-7 → 3-6 wording) | Minor | Fixed |
| Sec F2 (TOCTOU on cache read) | Minor | Accepted — Anti-Deferral quantification above |
| Test F2 (counter uniqueness) | Minor | Fixed (basename-derived) |
| Pre-screen Minor (set -e guard) | Minor | Fixed in de398b7 (before expert launch) |

---

# Round 2 (fix verification)

- Functionality: **No findings.** All five round-1 fixes verified (empirical
  dispatch edge cases; sha256sum output-format compatibility confirmed — old
  cache entries not spuriously invalidated; R43 comparison: both production
  changes narrow, never widen).
- Security: round-1 F1 fix verified (option-parsing class closed, xargs
  batch-split safe, T3b sound); TOCTOU disposition accepted. **One Minor
  residual**: `sha256sum -- -` still reads stdin (`--` ends option parsing,
  not the stdin operand convention) — an untracked root-level file literally
  named `-` stayed fingerprint-invisible.
  **Resolution: Fixed.** Pipeline replaced with a null-delimited read loop
  hashing `./$f` (unambiguous for every spelling, per-file failure aborts
  non-zero → full run). T3c added; red-proven against an `xargs -- `-form
  mutant (stale skip reproduced → T3c red). Plan C1 pipeline spec + C6
  updated. Suite 51/51 green.
- Testing: round-1 dispositions accepted (incl. fixed-as-documentation for
  T9, with agreement that no observable-divergence test is required).
  **One Minor**: the rescoped T9 claim was itself wrong — a pipe in the exec
  path is masked by the wrapper's own `set -o pipefail` (stays green);
  mutation-verified red cases are exit-status swallowing (`|| true`) and
  status flattening.
  **Resolution: Fixed.** Plan T9 row replaced with the expert's
  mutation-verified wording. Process lesson recorded to orchestrator memory:
  red-proof claims must be mutation-executed before being written.

---

# Round 3 (final fix verification)

- Security: **No findings.** The `-` operand class is closed — adversarial
  filename sweep (bare `-`, `--help`, newline-embedded, leading-space,
  backslash, dangling/hostile symlinks, fifo absence) found no residual
  fingerprint-invisible spelling. R43: every delta narrows or holds.
  Recording instruction honored: the round-2 "format compatibility" claim
  applies to the round-1→2 fix only — see the format-change note below.
- Functionality: **1 Minor (resolved, no code change).** The read-loop fix
  changes hash-input lines to `<hash>  ./name`, so fingerprints differ
  across the round-2→3 upgrade for trees with ≥1 untracked file: any
  pre-upgrade cache entry misses exactly once (full run, re-record) —
  fail-safe, self-healing, unreleased branch. Recorded as deviation D3 with
  the scope note that C1's "same tree → same hash" is a same-code-version
  property. Stripping the prefix to restore byte-compatibility was rejected:
  the prefixed operand IS the disambiguation.
- Testing: **1 Minor (fixed).** The reworded T3b rationale attributed its
  red to dropping `./` alone — mutation testing shows drop-`./`-only stays
  green (retained `--` masks it; T3c catches that mutant); T3b's verified
  red mutant is removing BOTH `--` and `./`. Plan row and test comment
  replaced with the expert's mutation-verified matrix wording. (Recurrence
  #3 of the unexecuted-red-proof-claim class — the memory rule now
  explicitly covers rationale re-attributions during rewording, not just
  new rows.)

## Resolution Status (cumulative through round 3)

All Critical/Major findings: fixed and red-proven. Open items: none.
Accepted risks: Security F2 TOCTOU (round 1, Anti-Deferral quantified).
Deviations: D1-D3 in pre-pr-gate-cache-deviation.md.
Suite: 51/51 green (bats tests/check-pre-pr.bats).

---

# Round 4 (final confirmation)

Documentation-only round-diff (d209179). **All three experts: No findings.**
- Functionality: D3 disposition verified accurate; zero production change
  confirmed mechanically; loop closed from this perspective.
- Security: recording instruction implemented correctly; T3b re-attribution
  security-consistent; no gate/fingerprint/cache/protocol surface changed.
- Testing: every red-proof statement in the touched documentation now
  traces to an executed mutant; RT7 clean.

Termination condition met at round 4. Final gates: full bats suite 759/759
(0 failures), no migration tool (n/a), scripts/pre-pr.sh absent in this
repo (wrapper no-op verified, exit 0).

---

# Round 5 (external security review, relayed by the operator)

Three findings against `origin/main...HEAD`; all three reproduced locally
before any change (clean-filter diff = 0 bytes on real content change;
`.gate-state` absent from `ls-files --others --exclude-standard`;
`sha256sum` on a symlink to /dev/zero → timeout 124).

**F1 [High] — clean/textconv filters hide tracked-content changes from
`git diff HEAD` → stale cache hit on a changed tree.**
- **Resolution: Fixed.** `git diff` removed from the fingerprint entirely.
  Tracked paths are hashed from real worktree state (bytes + exec bit +
  type + symlink target) via the new lstat-first `_hash_path`. T23 asserts
  a clean-filtered tracked file's content change invalidates while the
  filtered diff is verifiably empty.

**F2 [High] — ignored files a gate reads are excluded from the fingerprint
→ gate bypass (.env, generated gate state, scanner DBs, deps, env).**
- **Resolution: Fixed — cache is now OPT-IN (all three remedies the
  reviewer offered, combined).** Default TTL is 0 (gate always runs).
  Enabling requires an explicit assertion that the gate's inputs are
  covered: exported PRE_PR_CACHE_TTL (operator opt-in), or a declaration —
  `scripts/pre-pr.cache-paths` file / exported PRE_PR_CACHE_EXTRA_PATHS,
  whose entries (which may be ignored files) become fingerprint inputs and
  whose presence (even empty = "tree only") enables the default 3600.
  Malformed TTL now falls back to unset (declaration-dependent), not to
  3600. T20 (default-off), T21 (declaration enables), T22 (declared
  ignored file's change invalidates), T19 reworked.

**F3 [Medium] — untracked symlink to /dev/zero hangs the hook up to the
1800 s timeout.**
- **Resolution: Fixed.** `_hash_path` is lstat-first: symlinks contribute
  their target string and are never followed; fifo/socket/device are never
  opened; regular files above PRE_PR_CACHE_MAX_FILE_BYTES (default
  100 MiB) abort fingerprinting (no fingerprint → full run, bounding
  worst-case latency). T24 (timeout-guarded no-hang + retarget
  invalidates), T25 (exec-bit flip invalidates — shrinks the old
  permission-bit blind spot), T26 (tracked delete invalidates), T27
  (size cap → never cached).

**Non-security note** — trailing blank line at EOF of the deviation log:
fixed.

Red-proof note: T20-T27 are red against the pre-round-5 implementation by
construction — each encodes one of the reproduced bypass/DoS scenarios
(the reproductions WERE the red observations, run before the fix).

Contract amendments recorded as deviation D4 (C1 fingerprint composition,
C2 opt-in TTL resolution). Suite after fixes: 59/59 green
(bats tests/check-pre-pr.bats).

---

# Round 6 (adversarial verification of the round-5 fixes, Security expert)

- (a) All three original attack reproductions re-run against the fixed
  hook: clean-filter change → runs; declared ignored change → runs;
  symlink to /dev/zero → completes instantly. Fixed.
- (b) **New Major found and fixed same round**: the fingerprint listing
  grammar was non-injective — `L`/`D`/`O` records interpolated unescaped
  paths/symlink targets into a newline-delimited format, so a symlink
  target embedding `"\nL ./c\td"` forged a record and collided two
  distinct worktree states into one fingerprint (stale skip; proven
  end-to-end by the expert, fingerprints byte-identical).
  **Resolution: Fixed.** All records NUL-framed (type tag + every field
  NUL-terminated; NUL is unconstructible in git paths and readlink
  output → injective), streamed directly into sha256sum (bash command
  substitution drops NULs and would collapse the framing — documented
  in-code). T28 added and red-proven against the newline-grammar
  implementation (stale skip reproduced → red). escalate: false (requires
  worktree write access — inside the documented trust boundary — and the
  cache is opt-in).
- (b-adjacent) **Minor (fixed)**: declaration entries are literal paths,
  not globs — a `secrets/*.env` entry silently under-covered its targets.
  Now documented in the helper header, and a nonexistent entry containing
  glob metacharacters emits a stderr warning. T29 added.
- Other adversarial checks clean: declaration path traversal (adds inputs
  only, same-trust), opt-in not forgeable below the gate-script trust
  level, `_declared_extra_paths_z` fail-safe under set -euo pipefail,
  TTL-gated fingerprint skip correct in both directions, size cap / exec
  bit / delete markers correct.
- (c) R43: every round-5/6 delta narrows or holds; the opt-in flip is a
  hard narrowing of the default.
- (d) Injectivity: DISPROVEN for the newline grammar (the Major above);
  HOLDS for the NUL-framed grammar (`F` sub-grammar was already injective
  via sha256sum self-escaping; now uniform).

Suite after round 6: 61/61 (bats tests/check-pre-pr.bats).
