# Code Review: marv-run-scoped-tmpdir
Date: 2026-04-19
Review round: 1

## Changes from Previous Round
Initial Phase 3 code review.

## Seed Finding Disposition (Phase 3 Round 1)

### Functionality expert
- seed2-func = "No findings" → independent R1-R30 check performed; all 6 edit sites verified, all 5 cross-cutting greps pass.

### Security expert
- Seed 1 (`TMPDIR` attacker control): Rejected. `TMPDIR` is user-controlled; the "attacker" would be the user themselves. `${TMPDIR:-/tmp}` is standard defensive practice.
- Seed 2 (Write-tool substitution failure → files in CWD): Rejected as security; [Adjacent] to Functionality. User already has full CWD access, no confidentiality/integrity boundary crossed. Obligation already documented in-snippet.
- Seed 3 (empty `MARV_DIR` → write to `/`): Rejected as security; [Adjacent] to Functionality. `mktemp` failure aborts the block; any remaining empty-var case produces EPERM or clear error, not exploitable.

### Testing expert
- Seed 1 (add test script `run-marv-tmpdir-tests.sh`): Rejected — RT2 violation. A new shell test script creates test infrastructure in a config-only repo with none. Manual smoke-test commands in the plan doc are the correct form.
- Seed 2 (add pre-launch prompt-grep for `$MARV_DIR` substitution): Rejected — already covered by the existing Seed Finding Disposition observability mechanism (fallback to "Seed unavailable" surfaces substitution failures post-dispatch). The Write tool / Bash tool provides no mechanism to inspect a rendered prompt before dispatch.

## Findings

### T-1 [Minor] — Bare `#4` in `marv-run-scoped-tmpdir-review.md:16` auto-links on GitHub (R30)
- **File**: `docs/archive/review/marv-run-scoped-tmpdir-review.md:16`
- **Evidence**: `| T1 | Minor | No smoke-test step for the abort-orphan scenario (plan's user-operation scenario #4). | ...`
- **Problem**: The bare `#4` in `scenario #4` renders as an auto-link to issue/PR `#4` on GitHub-flavored Markdown surfaces. GitHub-hosted repos notify watchers of the referenced issue when a new link appears.
- **Impact**: Information-disclosure to watchers of the linked issue; backlinks clutter the referenced issue.
- **Fix**: Wrap in backticks: `` scenario `#4` `` (preserves original phrasing).

## Adjacent Findings
[Adjacent → Functionality] Orchestrator variable substitution obligation (covers Seed 2 & 3 from Security): if orchestrator fails to substitute literal `MARV_DIR` before Write/Bash tool calls, files will be misdirected (CWD instead of temp dir). Not a security boundary crossing but a robustness concern. SKILL.md already documents the obligation in the Step 1-5 and Step 3-4 comment blocks; Functionality expert may assess whether an explicit pre-write guard is warranted. Functionality expert's Round 1 output already confirmed the obligation prose is clear — no additional action recommended.

## Quality Warnings
None.

## Recurring Issue Check

### Functionality expert
R1-R30 all N/A or Pass. Notable:
- R3 (propagation): all 6 edit sites + 5 grep checks pass.
- R20 (surgical edits): no multi-statement construct split.
- R27 (cross-cutting): Step 1-5, Step 3-4, Step 3-9 all updated consistently.
- R28 (checklist cross-check): all 6 edit sites in Implementation Checklist appear in diff.

### Security expert
R1-R30 + RS1-RS3 all Pass/N/A. No new injection surface, no privilege escalation, no auth changes. `mktemp -d` atomic with O_EXCL covers TOCTOU. Mode 0700 covers confidentiality.

### Testing expert
R1-R30 + RT1-RT3 all N/A or Pass, EXCEPT R30 which flagged T-1 above. RT2 self-applied — Seed 1 (test script addition) rejected on this basis.

## Resolution Status

### T-1 [Minor] Bare `#4` in review.md — Resolved
- Action: wrapped `#4` in backticks → `` `#4` ``.
- Modified file: `docs/archive/review/marv-run-scoped-tmpdir-review.md:16`

---

# Code Review: marv-run-scoped-tmpdir — Round 2
Date: 2026-04-19
Review round: 2

## Changes from Previous Round
Round 1 T-1 (R30 bare `#4`) committed in `a7f9d75`.

## Round 2 Findings

| # | Severity | Status | Detail |
|---|---|---|---|
| T-1 | Minor | Resolved | Functionality/Security confirmed no regression. Testing confirmed the `#4` in review.md:16 is correctly wrapped. |
| T-2 | Minor (new) | Resolved | Testing expert's R30 sweep across all plan docs found a second bare `#4` in `code-review.md:27` ("issue/PR `#4` on"), inside the Problem prose of T-1 itself. Meta-irony: the finding that documents the autolink hazard was itself vulnerable to it. Fixed in this round. |

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check (Round 2)

### Functionality expert
R1-R30 all Pass/N/A. Commit is documentation-only; no behavior change, no regression.

### Security expert
R1-R30 + RS1-RS3 all Pass/N/A. No new executable surface.

### Testing expert
R30 is now clean across all plan docs (verified with `grep -nE '(^|[^a-zA-Z0-9\`])#[0-9]+([^\`]|$)'`). RT2 self-applied.

## Round 2 Termination
All findings resolved (T-1 from Round 1, T-2 discovered and fixed in Round 2). No new findings from Functionality or Security. Proceeding to Phase 3 Step 3-9 final commit.

## Resolution Status (consolidated)

### T-1 [Minor] Bare `#4` in review.md:16 — Resolved (Round 1)
- Action: wrapped `#4` in backticks.
- Modified file: `docs/archive/review/marv-run-scoped-tmpdir-review.md:16`

### T-2 [Minor, Round 2] Bare `#4` in code-review.md:27 Problem prose — Resolved
- Action: wrapped the remaining bare `#4` (in the phrase "issue/PR `#4` on") in backticks.
- Modified file: `docs/archive/review/marv-run-scoped-tmpdir-code-review.md:27`

---

# Code Review: marv-run-scoped-tmpdir — Round 3
Date: 2026-04-19
Review round: 3

## Changes from Previous Round
Round 2 T-2 fix (wrap recursive bare `#4` in T-2's own description prose) committed in `3163a16`.

## Round 3 Findings
All three experts return "No findings". T-1 and T-2 confirmed resolved. Backtick-span-aware R30 sweep across all 4 plan docs returns zero output.

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check (Round 3)
All R1-R30 + RS/RT Pass or N/A. R30 clean verified programmatically (Python strips backtick spans before grep; no bare `#N` remains).

## Round 3 Termination
All findings resolved (T-1 Round 1, T-2 Round 2). Loop complete. Proceeding to Phase 3 Step 3-9 final commit.

---

# Code Review: marv-run-scoped-tmpdir — Round 4 (post scope-expansion)
Date: 2026-04-19
Review round: 4

## Changes from Previous Round
User-requested scope expansion:
- D2 (commit `4203907`): added `: "${MARV_DIR:?...}"` guards at 4 skill sites.
- D4 (commit `9a59267`): extracted tmpdir lifecycle to new `hooks/marv-tmpdir.sh`; SKILL.md refactored to call the helper at Step 1-5, Step 3-2b, Step 3-9. `settings.json` updated with allow rule for the new hook.

Seed findings from a fresh Ollama pass against the expanded diff.

## Seed Finding Disposition

### Functionality
- F-M1 (Major): "Step 1-5 missing `echo "MARV_DIR=$MARV_DIR"`, orchestrator cannot capture path" → **Verified — adopted as F3** (genuine gap; Step 3-2b had the echo, Step 1-5 did not).
- F-M2 (Minor): "TMPDIR differs between create and cleanup → prefix check may reject valid path" → **Verified — adopted as F4 (Anti-Deferred)** (real edge case but rare and fails loud, not silent).

### Security
- S-M1 (Major): "`..` path traversal bypasses prefix check → `rm -rf "/tmp/marv-foo/../../etc"` nukes `/etc`" → **Verified — adopted as S1** (reproduced; pure-lexical prefix check is exploitable; fixed with multi-layer safety).

### Testing
- T-M1 (Minor): "symlink handling in cleanup" → **Partially verified — rolled into S1 fix** (symlink rejection added alongside `..` rejection).
- T-M2 (Minor): "no manual step verifying orchestrator captures MARV_DIR" → **Verified — addressed by F3 fix** (Step 1-5 now echoes the path; Step 3-2b already did).
- T-M3 (Minor): "Implementation checklist still references old `mktemp -d -t marv-XXXXXX` grep" → **Rejected — already covered by D5** (deviation log records the update; plan grep was refined post-F2 fix).
- T-M4 (Minor): "no reproducible test for cleanup error handling" → **Verified — adopted as T3** (added explicit `..`/symlink/non-marv smoke tests).

## Round 4 Findings

### F3 [Major] — Step 1-5 snippet missing `echo "MARV_DIR=$MARV_DIR"` — Resolved
- **File**: `skills/multi-agent-review/SKILL.md` Step 1-5 (line ~190).
- **Evidence**: `grep -n 'echo "MARV_DIR=' skills/multi-agent-review/SKILL.md` before fix returned only 1 match (Step 3-2b); Step 1-5 had no echo.
- **Problem**: In Phase 1 plan review, Step 1-5 creates `MARV_DIR`, then the orchestrator launches 3 Agent sub-agents and uses Write tool to save each output to `$MARV_DIR/<role>-findings.txt` before the final cat + merge. The orchestrator's Bash tool call only prints command stdout; `MARV_DIR=$(...)` assignment produces no stdout. Without an explicit `echo`, Claude cannot capture the path for later Write/Bash invocations.
- **Impact**: Phase 1 Step 1-5 merge would silently fail — `cat $MARV_DIR/func-findings.txt` in a fresh Bash shell sees `$MARV_DIR` as unset; the `:?` guard catches it, but only after the sub-agents already ran and their outputs were written to... wherever the orchestrator guessed.
- **Fix**: Added `echo "MARV_DIR=$MARV_DIR"` immediately after the `:?` guard in Step 1-5 (matching the existing Step 3-2b convention).

### S1 [Major] `..` path traversal bypasses cleanup prefix check — Resolved
- **File**: `hooks/marv-tmpdir.sh` `cmd_cleanup`.
- **Evidence**: `D="/tmp/marv-foo/../../etc"; case "$D" in "/tmp/marv-"*) echo match;; esac` prints `match`. A subsequent `rm -rf "$D"` resolves the `..` at the kernel level and deletes `/etc` (for any user with write access).
- **Problem**: The purely-lexical prefix check `"${dir#"$expected_prefix"}" = "$dir"` matches strings starting with `/tmp/marv-` but does not prevent `..` from walking up the filesystem at `rm -rf` time. A corrupted `$MARV_DIR` (orchestrator bug, hallucination, or deliberate adversarial input if any escape-hatch existed) could destroy arbitrary user-writable directories.
- **Impact**: Potential for catastrophic data loss (`rm -rf /home/user/code`, `rm -rf /etc` for root-adjacent users, etc.). Even absent a malicious actor, a future refactor bug could trigger it.
- **Fix**: Added 3 pre-rm safety layers in order: (1) reject any path containing `..`, (2) reject any symlink, (3) reject paths not matching `${TMPDIR:-/tmp}/marv-` prefix. All reject with specific stderr message + exit 1. Verified: `.. ` attack rejected, symlink rejected, non-marv path rejected, legit path succeeds, empty path no-op.

### F4 [Minor] TMPDIR changes between create and cleanup — Accepted
- **Anti-Deferral check**: acceptable risk.
- **Justification**:
  - Worst case: a valid `marv-*` directory created under TMPDIR=A gets a cleanup call while TMPDIR=B; the prefix check rejects it and cleanup aborts. User sees a specific stderr message (`refusing to cleanup path outside ${B}/marv-*: <path>`) and can `rm -rf <path>` manually.
  - Likelihood: low. `TMPDIR` is typically stable for a shell session; changing it between `/multi-agent-review` phases requires explicit user action.
  - Cost to fix: medium (~30-60 min). Options include storing the creation prefix in a metadata file, or accepting both `$TMPDIR/marv-` and `/tmp/marv-`. Either adds complexity without a real user-visible benefit for the dominant case.
- **Orchestrator sign-off**: Accepted as quantified low-probability risk that fails loud, not silent.

### T3 [Minor] Cleanup error-handling test coverage — Resolved
- **Fix**: Added 4 smoke-test steps to the plan's Testing strategy covering `..`, symlink, non-marv-prefix, and legit-path paths through `cmd_cleanup`.

## Adjacent Findings
None. S1's severity was initially flagged as Security but the fix lives in the hook; since the hook was touched by this PR, S1 is resolved in-scope rather than routed.

## Quality Warnings
None.

## Recurring Issue Check

### Functionality expert
R1-R30 Pass/N/A. Notable:
- R3 (propagation): `echo "MARV_DIR=$MARV_DIR"` now consistent between Step 1-5 (line 194) and Step 3-2b (line 525).
- R17 (helper reuse): new helper `marv-tmpdir.sh` is the DRY target.
- R20 (surgical edits): 3 hooks changes are additive safety layers; no existing logic moved.

### Security expert
R1-R30 + RS1-RS3 Pass. Notable:
- RS3 (input validation at boundaries): `cmd_cleanup` now validates input through 3 safety layers before `rm -rf`.
- R29 (spec citation accuracy): no specs cited; N/A.

### Testing expert
R1-R30 + RT1-RT3 Pass/N/A.
- RT2 self-applied: seed T-M4 (test infrastructure) accepted only because it's manual shell commands in the Testing strategy, not a test framework.
- R30 (Markdown autolink): no new bare `#N`/`@name`/SHA-shaped hex introduced.

## Round 4 Termination (pending Round 5 verification)
All 4 new findings addressed. Round 5 will verify:
- Step 1-5 echo present
- Hook rejects `..`, symlinks, non-marv
- settings.json allow rule synced
- All 5 cross-cutting greps still pass

## Resolution Status

### F3 [Major] — Resolved
- Action: added `echo "MARV_DIR=$MARV_DIR"` after the `:?` guard in Step 1-5.
- Modified file: `skills/multi-agent-review/SKILL.md`

### S1 [Major] — Resolved
- Action: added 3 pre-rm safety layers to `cmd_cleanup` (reject `..`, reject symlinks, reject non-marv prefix). Verified experimentally.
- Modified file: `hooks/marv-tmpdir.sh`

### F4 [Minor] — Accepted with Anti-Deferral
- Action: documented in this review as quantified acceptable risk.
- No code change.

### T3 [Minor] — Resolved
- Action: added cleanup error-handling smoke tests to the plan's Testing strategy.
- Modified file: `docs/archive/review/marv-run-scoped-tmpdir-plan.md`

---

# Code Review: marv-run-scoped-tmpdir — Round 5
Date: 2026-04-19
Review round: 5

## Changes from Previous Round
Round 4 findings (F3 Major, S1 Major, F4 Minor, T3 Minor) all verified resolved. Round 5 surfaced 2 Low-severity security findings (defense-in-depth) which are addressed in this round.

## Round 5 Findings

### S2 [Minor] TOCTOU symlink-swap window between `[ -L ]` check and `rm -rf` — Resolved
- **File**: `hooks/marv-tmpdir.sh` `cmd_cleanup`
- **Evidence**: the original fix checked `[ -L "$dir" ]` once, then did the prefix check, then `rm -rf`. Between the `[ -L ]` and the `rm -rf`, a same-user attacker could unlink the dir and replace it with a symlink (sticky-bit `/tmp` permits directory owner to do this). `rm -rf` does NOT follow top-level symlinks, so this would delete the symlink itself — low practical impact — but a second `-L` check closes the window entirely.
- **Problem**: TOCTOU race; described by Round 5 security expert as `escalate: false` with mitigating factors (requires same-user access = self-attack, `rm -rf` does not follow top-level symlinks).
- **Fix**: Added a second `[ -L "$dir" ]` check immediately before `rm -rf` with a `pre-rm` error message. Comment in the hook explains the threat model and why it's defense-in-depth.

### S3 [Minor] settings.json allow rule uses wildcard that could match concatenated commands — Resolved
- **File**: `settings.json`
- **Evidence**: Round 5 security expert noted `Bash(bash ~/.claude/hooks/marv-tmpdir.sh *)` uses `*` which matches any suffix, and the behavior when a `;` is present in the command depends on Claude Code's allow-rule matcher implementation.
- **Problem**: If Claude Code's matcher accepts `bash ~/.claude/hooks/marv-tmpdir.sh create; rm -rf ~` as matching the wildcard rule, an adversarial prompt could exfiltrate via this path. The hook's own `case` dispatcher rejects unknown first arguments, which is the actual safety net.
- **Fix**: Replaced the single wildcard rule with two narrower rules:
  - `Bash(bash ~/.claude/hooks/marv-tmpdir.sh create)` (no args expected)
  - `Bash(bash ~/.claude/hooks/marv-tmpdir.sh cleanup *)` (path arg only)
  This mirrors the hook's own subcommand structure and removes ambiguity about what the wildcard can match.

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check (Round 5)
R1-R30 + RS1-RS3 + RT1-RT3 all Pass/N/A. No new patterns introduced.

## Round 5 Termination
All findings from Rounds 1-5 resolved or formally accepted. Loop complete.

## Resolution Status

### S2 [Minor] TOCTOU defense-in-depth — Resolved
- Action: second `[ -L "$dir" ]` check added immediately before `rm -rf`.
- Modified file: `hooks/marv-tmpdir.sh`

### S3 [Minor] settings.json allow-rule narrowing — Resolved
- Action: split the wildcard rule into `create` (no args) and `cleanup *` (path only).
- Modified file: `settings.json`
- Meta-note: T-1's Fix line demonstrates proper backtick wrapping; T-2's Problem line failed to apply it consistently to its own prose describing the same pattern. Recording this meta-observation for future reviewers: when a finding describes an autolink trigger, grep the Finding's own Evidence/Problem/Fix prose for the same trigger before committing.
