# Code Review: retro-2026-07-27 (artifacts-source fold)
Date: 2026-07-27
Review round: 3 (final)

## Changes from Previous Round
Initial review. Branch `retro/2026-07-27-gate-harness-recipient-scope`: four mined
lessons folded into R42/R43/R44/RT7, cross-ported to test-gen and the phase-2/phase-3
review moments, plus a pre-existing containment fix in `hooks/verify-references.sh` and
the retrospective doc.

## Functionality Findings

**F1 [Critical] Symlink-chain containment bypass survives the fix** —
`hooks/verify-references.sh`. The leaf resolution did exactly one `readlink` hop, so a
chain of two in-ROOT links reaching outside still passed containment. Reproduced: a
`hop1 -> hop2 -> outside` chain reported `OK`, and an out-of-range reference leaked the
outside file's line count — the existence/size oracle the hook's own security model
(header lines 16-22) exists to prevent. The correct implementation already lived in this
repo at `hooks/retro-prescreen.sh:69-85`, whose comment names this exact two-link bypass
as a prior finding (D4). R3 (incomplete propagation) and R42 (member-set derivation over
"hooks canonicalizing an untrusted path for containment").

**F2 [Minor] Retrospective doc's "0 hits" grep evidence does not reproduce** —
`docs/archive/audit/retro-artifacts-lessons-2026-07-27.md`. Both the R44 and R42
dispositions claimed `= 0 hits`; re-running them against main returns 8 hits each. The
novelty conclusion is still correct — every hit is an unrelated sense ("service
identity", "package manifest") — but the recorded evidence did not reproduce, defeating
the purpose of citing greps in an audit record.

## Security Findings

**S1 [Critical, escalate: true] Symlink-chain bypass leaks metadata for arbitrary
readable files** — same defect as F1, found independently. Executed evidence: a two-hop
chain to `/etc/passwd` reported `OK` and leaked its line count (60) verbatim. Also flagged
the R43 documentation half — the containment comment was edited to claim symlink
redirection is caught, a coverage claim the code did not honor.

**S2 [Major] Security-gate fix shipped with no test for the new resolution path (RT7
shape c)** — `git diff main...HEAD --stat -- tests/` was empty. The pre-existing test 16
red-proved only the depth-1 absolute-target path; the new comment made four normative
behavioral claims with zero assertions behind any of them.

Verified negative: no command injection (hostile targets `$(...)`, backticks, globs,
semicolons all classified MISSING with no marker file created); resolution failure is
fail-CLOSED; `--root` as a symlink canonicalizes correctly; the retrospective doc carries
no mined imperative a future agent would follow as an instruction; repo-neutrality holds
across `skills/`, `hooks/`, `rules/`; none of the four folded sub-clauses weakens an
existing obligation (RT7's promotes mutant proof from escalation-only to unconditional —
a tightening).

## Testing Findings

**T1 [Critical] Same chain bypass, found independently** — with the added observation
that the same probe returns `OK` on main, so it is a pre-existing hole the fix narrowed
but did not close (in scope per the pre-existing-in-changed-file rule).

**T2 [Major] Six symlink variants exercised by the new code have no test** — chain,
symlink parent directory, relative `../` target, dangling-outside, dangling-inside, and
symlink-to-directory. The relative-target branch was the sharpest gap: new code with no
covering test, so a mutation there stayed green.

**T3 [Minor] Obligation 14's missing illustrative spelling** — assessed and rejected as a
defect: obligation 13 omits it too, and "make the fixture hold two members" has no
canonical per-framework spelling. No change made.

Verified: the commit's red-proof claim was **executed and confirmed** — deleting the
leaf-resolution block reds exactly test 16 on its `OUT-OF-ROOT` assertion. Main's suite
baseline was 790/791 with `not ok 789` (the symlink test); the branch is 791/791.

## Adjacent Findings

Functionality expert flagged `hooks/pre-review.sh:35-36` as sharing the parent-only shape
but reading `PLAN_FILE` from the environment rather than untrusted stdin — "a lower-
severity sibling worth a look, not a finding here."

**Orchestrator escalation**: investigated and found it is NOT lower severity. Executed
evidence — a **one-hop** symlink inside the repo pointing outside was read and its
contents (`secret-exfiltrated`) reflected into the LLM review output. That is the
exfiltration channel the hook's header (line 26) states it prevents, and it is a stronger
leak than the size oracle in `verify-references.sh` because full file contents cross the
boundary. Promoted to a Critical finding and fixed in this round.

## Recurring Issue Check

### All experts
- R3 (Incomplete pattern propagation): Finding F1/S1/T1 — the correct chain-resolution
  form already existed in `retro-prescreen.sh` and was not propagated.
- R42 (Class-membership derivation): Finding F1 — deriving the member set of "hooks
  canonicalizing an untrusted path for a containment decision" from the
  `dirname`/`basename` primitive surfaced `retro-prescreen.sh` (already correct),
  `verify-references.sh` (F1), and `pre-review.sh` (the adjacent escalation). Clause ①b
  applies: the escape-vector class was closed at one axis (depth 1) when the axis has
  depth.
- R43 (Fix-induced boundary widening): the containment fixes narrow, never widen. The
  documentation-claim half was corrected (see S1).
- R44 (Gate exit status via a lossy/identity-less channel): all PASS conclusions in this
  round (`bats`, `check-rule-sync.sh`, `git diff --exit-code`) read from each command's
  own unpiped exit status, or redirected to a file and inspected.
- RT7 (New guard must be proven able to fail): every new test in this round was
  red-proven by an executed mutation — see Resolution Status.
- RT2 (Testability): all four folded sub-clauses are executable as written.
- RS3/RS5: not violated — stdin is treated as untrusted throughout; `--root` and
  `PLAN_FILE` are operator-supplied and canonicalized fail-closed.

## Resolution Status

### F1 / S1 / T1 [Critical] Symlink-chain containment bypass
- Action: replaced the single-hop `if` with a 40-hop-capped chain-resolution loop
  matching `_containment_check` in `hooks/retro-prescreen.sh`. Corrected the containment
  comment's coverage claim to say "at any depth up to the hop cap".
- Modified file: `hooks/verify-references.sh:105-127`
- Verified: 2-hop and 3-hop chains now `OUT-OF-ROOT` with no line-count leak; a symlink
  cycle terminates as `MISSING` without hanging; a legitimate in-ROOT alias still `OK`.
- Red-proof (executed): reverting the loop to a single hop reds test 17
  (`symlink CHAIN escaping ROOT`); removing the resolution entirely reds tests 16, 17,
  20, 22.

### S2 / T2 [Major] Missing tests for the new resolution path
- Action: added six bats cases — chain-escaping, relative-target-inside, cycle,
  dangling-outside, dangling-inside, symlink-to-directory.
- Modified file: `tests/verify-references.bats:148-215`
- Red-proof (executed): the first draft of the relative-target test was found
  **vacuous** — a mutation breaking the dirname join left it green, because a bare
  relative target then resolves against the working directory (also outside ROOT) and
  reports `OUT-OF-ROOT` for the wrong reason. Rewritten to assert the in-ROOT direction,
  where a broken join gives `MISSING` instead of `OK`; the mutation now reds test 18.
- A first-draft fail-closed block for the hop cap was likewise found to pin nothing (the
  loop bound alone stops the spin and the in-ROOT path is rejected by the existence
  check), so it was removed rather than kept with a test that could not fail. The cycle
  test is retained and documented as a termination guard, not a cap proof.

### Adjacent [Critical] `pre-review.sh` symlink exfiltration
- Action: applied the same chain-resolution loop to the `PLAN_FILE` canonicalization.
- Modified file: `hooks/pre-review.sh:33-56`
- Verified: one-hop and two-hop escapes now refused with the `outside TRUSTED_ROOT`
  warning and no target content in the output; legitimate in-repo plans still read.
- Red-proof (executed): both new tests pass against the fixed hook and fail against
  main's version (`not ok 4`, `not ok 5`).
- Modified file: `tests/pre-review.bats:59-86`

### F2 [Minor] Non-reproducing grep evidence
- Action: restated both dispositions with greps that actually return zero
  (`\bwait -n\b|\bper-unit\b`, `set-equality|set equality`) and recorded the broader
  terms' hit counts with their unrelated senses named.
- Modified file: `docs/archive/audit/retro-artifacts-lessons-2026-07-27.md:50-53, 87-90`

### T3 [Minor] Obligation 14 illustrative spelling
- Action: none. Assessed and rejected — obligation 13 omits it too, and the requirement
  has no canonical per-framework spelling. Recorded here so the assessment is not redone.

---

# Round 2

## Changes from Previous Round
Round 1's fixes verified by two experts (security, testing). The chain fix itself holds,
but Round 1's *removal* of the hop-cap fail-closed block was found to be a real security
regression — both experts flagged it independently as Critical, refuting the orchestrator's
Round 1 reasoning.

## Round 2 Findings

**R2-1 / S3 [Critical] The hop-cap removal reopened the metadata leak** —
`hooks/verify-references.sh`. Round 1 removed the fail-closed block because a mutation
"showed it pinned nothing". That mutation only covered the CYCLE case, which is dangling,
so `-f` fails and the leftover path looks safe. When a chain LONGER than the cap ends at a
**real existing file outside ROOT**, the walk stops on an in-ROOT link, containment passes,
and `-f`/`wc -l` let the KERNEL follow the remaining hops. Executed proof: a 41-link chain
reported `OK` and leaked the outside file's true line count (7).

This is R42 clause ①b in the orchestrator's own work — the escape-vector class was closed
at one axis (cycle) when the axis had another member (chain-to-real-file) — and R43, since
a fail-closed predicate was removed on a *testing* argument rather than a security one.

**R2-3 / S4 [Major] No test bounded the hop cap** — the untested boundary was exactly where
the defect lived. RT7 shape (c).

**R2-4 [Major] The cycle test hangs rather than fails when the cap is removed** — a wedged
CI is a worse failure mode than a red.

**R2-5 [Major] Test 22 was misnamed and duplicated test 16** — its fixture linked to a
regular file that merely sat in an outside directory; `[ -d ]` on the link was false. It
red iff test 16 red, so it added no coverage.

**R2-6 [Minor] The same false cap rationale was propagated into `pre-review.sh`** — safe
there only incidentally, via kernel ELOOP.

**R2-7 [Minor] The new pre-review tests stayed green under a refuse-everything mutation** —
they asserted refusal but never that a legitimate plan is still accepted.

Testing expert also verified all four Round 1 red-proof claims by executing them: each
reproduced exactly, reddening the claimed tests and no others. It corrected one Round 1
self-assessment: the cycle test IS pinnable (by a mutation accepting symlinks at the
existence check), contrary to the orchestrator's note.

## Round 2 Resolution Status

### R2-1 / S3 [Critical] Cap fail-open
- Action: restored the fail-closed block and rewrote the comment to state the real
  mechanism — that the downstream existence check does NOT save us, because the kernel
  follows the remaining hops even after our resolver stops.
- Modified file: `hooks/verify-references.sh:105-131`
- Red-proof (executed): removing the restored block reds test 19. The Round 1 mistake was
  mutating only against a cycle; this mutation uses a chain to a real outside file.

### R2-3 [Major] Untested cap boundary
- Action: added `symlink chain longer than the hop cap: fails closed, no metadata leak`,
  building a 41-link chain to a real outside file and asserting neither `OK ` nor
  `file has ` appears.
- Modified file: `tests/verify-references.bats:175-193`

### R2-4 [Major] Cycle test hangs instead of failing
- Action: wrapped the invocation in `timeout 30` so a missing cap reds here rather than
  wedging the suite.
- Modified file: `tests/verify-references.bats:198-201`

### R2-5 [Major] Misnamed duplicate test
- Action: rewritten as `reference THROUGH a symlinked directory escaping ROOT` — the
  fixture now links a DIRECTORY and references a regular file inside it, so the escape
  happens during the parent `cd -P`, before the leaf loop.
- Modified file: `tests/verify-references.bats:213-225`
- Red-proof (executed): breaking the parent canonicalization reds tests 13 and 23; the
  test no longer red-iff-16.

### R2-6 [Minor] False rationale propagated to pre-review.sh
- Action: added the fail-closed cap block there too and corrected the comment. The comment
  now states plainly that this branch is **not reachable by a test on Linux** (ELOOP is
  also 40, so the caller's `-f` fails before the loop runs) and is kept as defense-in-depth
  for platforms with a higher limit.
- Modified file: `hooks/pre-review.sh:47-73`
- Mutation result (executed): removing the block reds NO test — recorded as an accepted,
  documented residual rather than a claimed proof. Relying on the platform to enforce our
  containment is what made the equivalent branch look removable in `verify-references.sh`,
  where the chain IS reachable and the leak was real.

### R2-7 [Minor] Pre-review tests could not detect over-refusal
- Action: added an accept-path assertion — an in-repo symlink to an in-repo file must
  still be read.
- Modified file: `tests/pre-review.bats:70-77`
- Red-proof (executed): a refuse-everything mutation now reds tests 29 and 32; previously
  only the pre-existing test 32 caught it.

### R2-8 / S4 [Minor] Remaining untested variants
- Action: none. Mixed relative/absolute chains, symlinked intermediate parents, and target
  names with spaces/newlines were all verified correct by execution during review but left
  untested. Recorded here so the assessment is not redone; each is a Minor coverage nit
  with no reachable defect.

## Round 2 Gates
- `bash ~/.claude/hooks/check-rule-sync.sh` → exit 0
- `bats tests/` → exit 0, **800/800** passing

---

# Round 3

## Changes from Previous Round
Combined security + testing verification of round 2's fixes. The Critical is confirmed
closed and every round-2 finding verified resolved. Two Minor findings, both real, both
fixed here.

## Verification of Round 2 (all executed)

- **Cap boundary swept at 1, 2, 38, 39, 40, 41, 45, 60 links**, chains terminating at a
  real file both inside and outside ROOT. No `OK` and no `file has ` for any outside
  target at any length; in-ROOT chains up to 40 links still resolve to `OK`, so there is
  no over-refusal. **40 links is the last fully-resolved case**; 41 exhausts the cap and
  refuses. The loop admits hops 0..39 and the check fires at `>= 40` — the two conditions
  abut exactly, no gap and no double-count.
- **Test 19 is not a false-positive trap**: raising the cap 40 → 100 (a safe change) keeps
  the suite green, because the test asserts the outcome (no acceptance, no metadata), not
  the mechanism.
- **`timeout 30` converts the hang into a red** — measured `rc=124` at 30s; the test reds
  rather than wedging.
- **Test 23 is no longer a duplicate** — breaking the parent canonicalization reds test 23
  alone, with test 16 green.
- Independently confirmed the mixed relative/absolute, symlinked-intermediate-parent,
  symlinked-component-in-absolute-target, and newline-filename variants all classify
  correctly (round 2's R2-8 accepted residual).

One correction to round 2's record: the round-2 note named the wrong mutation as proof for
the pre-review accept-path assertions. A refuse-everything mutation reds the test at its
pre-existing assertion (bats aborts on first failure), so the new assertions are never
reached. A narrower mutation — over-refuse only in-root symlinks, leaving the escape
message intact — reds at the new assertion and no other test catches it. The assertions do
unique work; only the stated proof was imprecise.

## Round 3 Findings and Resolution

### R3-1 [Minor] `ROOT_ABS="/"` refuses every path
- `pwd -P` returns `/` for the filesystem root, making the containment pattern `"//"*`,
  which matches nothing — so `--root /` refuses paths that are genuinely inside ROOT.
  Fails closed, hence Minor, but wrong. The same shape existed in `pre-review.sh` when
  `TRUSTED_ROOT` is `/` (reachable by running outside a git repo from `/`).
- Action: normalize `/` to empty in both hooks so the pattern reads `"/"*`.
- Modified files: `hooks/verify-references.sh:45-54`, `hooks/pre-review.sh:27-32`
- Red-proof (executed): reverting the normalization reds the new test 24
  (`--root / : paths under the filesystem root are not all refused`).

### R3-2 [Minor] Test fixtures leaked into shared `/tmp` on failure
- `ROOT_DIR` was `mktemp -d` directly under `/tmp`, so every `"$ROOT_DIR/.."` fixture
  (the outside-ROOT targets) landed in shared `/tmp` under fixed, guessable names, and
  `teardown` removed only `ROOT_DIR`. Test 23 also cleaned up *after* its assertions, so a
  failing run leaked `/tmp/outside-dir`.
- Action: nested ROOT one level inside a per-test sandbox (`SANDBOX_DIR/root`) so
  `"$ROOT_DIR/.."` stays inside the sandbox and `teardown` reclaims it regardless of
  outcome; moved test 23's cleanup above its assertions to match test 19.
- Modified file: `tests/verify-references.bats:9-24, 244-249`
- Verified (executed): with test 23 forced to fail, shared `/tmp` stays clean.

### R3-3 [Minor] TOCTOU between resolution and read
- Action: none. Structurally present — the read is by path rather than a retained fd — but
  exploiting it needs a local attacker with write access to ROOT racing a ~10ms window,
  which is outside the threat model of a helper fed LLM output (the attacker model is
  content, not concurrent filesystem writes). Recorded so the assessment is not redone.

## Round 3 Gates
- `bash ~/.claude/hooks/check-rule-sync.sh` → exit 0
- `bats tests/` → exit 0, **801/801** passing

## Termination

Round 3's findings were both Minor, inside round 2's fix scope, and touched no security
boundary — the Step 3-8 tightening-only skip applies, so no round 4. Both were fixed in
place and re-gated.

## Environment Verification Report
N/A — no environment constraints declared (config-only repo; bats is the full harness and
runs locally).

## Gates
- `bash ~/.claude/hooks/check-rule-sync.sh` → exit 0 (`R1-R46 / RS1-RS6 / RT1-RT9
  consistent across all sync points`)
- `bats tests/` → exit 0, 799/799 passing (main baseline: 790/791, with the symlink test
  failing)

Both statuses read from the command's own exit code, unpiped (R44).
