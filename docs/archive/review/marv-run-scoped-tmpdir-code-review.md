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
- **Problem**: The bare `#4` in `scenario #4` renders as an auto-link to issue/PR #4 on GitHub-flavored Markdown surfaces. GitHub-hosted repos notify watchers of the referenced issue when a new link appears.
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
