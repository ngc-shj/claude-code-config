# Code Review: retro-2026-07-27 (artifacts-source fold)
Date: 2026-07-27
Review round: 1

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

## Environment Verification Report
N/A — no environment constraints declared (config-only repo; bats is the full harness and
runs locally).

## Gates
- `bash ~/.claude/hooks/check-rule-sync.sh` → exit 0 (`R1-R46 / RS1-RS6 / RT1-RT9
  consistent across all sync points`)
- `bats tests/` → exit 0, 799/799 passing (main baseline: 790/791, with the symlink test
  failing)

Both statuses read from the command's own exit code, unpiped (R44).
