# Code Review: add-ollama-expert-analyze-commands
Date: 2026-04-19
Review round: 1

## Changes from Previous Round
Initial Phase 3 code review.

## Seed Finding Disposition (Phase 3 Round 1)

### Functionality expert
- Seed 1 `[Major] hooks/ollama-utils.sh:131 — awk leading-whitespace`: Rejected. The sed step pre-processes leading-whitespace cases before awk. Operational path unaffected.
- Seed 2 `[Major] SKILL.md:515 — grep tolerance`: Rejected. Actual SKILL.md line 507 already uses `sed '/^[[:space:]]*$/d' | tail -1 | grep -q '^## END-OF-ANALYSIS$'`, which is the hardened form. The normalize pipeline guarantees canonical output.
- Seed 3 `[Minor] sed start-of-line`: Rejected. Standalone sentinel bypasses sed (no preceding char) and is handled directly by awk.

### Security expert
- Seed S2 `/tmp world-readable seed files`: Rejected — already covered by Phase 1 Round 1/Round 2 disposition (accepted as-is with TODO(mktemp-migration) marker). No new attacker/vector identified.

### Testing expert
- Seed 1 (test harness for normalize): Rejected — RT2 policy violation (automated test framework recommendation in config-only repo).
- Seed 2 (test harness for truncation loop): Partially verified — the underlying concern about trailing-blank-line handling surfaced T1 (see Findings).
- Seed 3 (consolidate sentinel validation into shared helper): Rejected — the two checks serve different purposes at different pipeline stages (output normalization vs. post-write validation); consolidation would reduce clarity.
- Seed 4 (rename `cmd_analyze_testing` to `cmd_analyze_teststrategy`): Rejected — breaks the existing naming convention (role-name suffix) and creates inconsistency with `functionality`/`security`.

## Findings

### F1 [Major] — `_ollama_analyze_normalize` causes SIGPIPE to upstream `_ollama_request` when response exceeds pipe buffer
- **File**: `hooks/ollama-utils.sh:128-131` (original implementation) and lines ~169/211/251 (each `cmd_analyze_*`)
- **Evidence**: Reproduced experimentally — `bash -c 'set -euo pipefail; (echo findings; echo sentinel; for i in $(seq 1 5000); do echo sentinel; done) | awk "/^sentinel$/{print;exit}{print}"` exits 141.
- **Problem**: awk's `exit` on first sentinel closes the pipe. Upstream `printf '%s\n' "$response"` receives SIGPIPE while still writing subsequent bytes (only when response > ~64KB pipe buffer). Under `set -o pipefail` this propagates as exit 141 and fails the `analyze-*` invocation even though the captured output is already valid.
- **Impact**: On large Ollama responses with sentinel appearing before the last ~64KB (e.g., the observed model-loop case where the sentinel was followed by ~800 sentinel repetitions), `cmd_analyze_*` exits non-zero and downstream `bash ~/.claude/hooks/ollama-utils.sh analyze-*` fails, breaking the Step 3-2 pipeline.
- **Fix**: Rewrote `_ollama_analyze_normalize` to drain all stdin (emit first sentinel, silently `next` over subsequent lines) instead of calling `exit`. No more SIGPIPE. Deployed in commit `<to follow>`.

### F2 [Minor] — Pre-existing stale `R1-R13` reference in `cmd_merge_findings` system prompt (pre-existing-in-changed-file rule)
- **File**: `hooks/ollama-utils.sh:106`
- **Evidence**: The skill's Recurring Issue Check now covers R1-R28 (since commit 704122e), but `cmd_merge_findings`'s system prompt still says "listing R1-R13". Because `hooks/ollama-utils.sh` is in the diff, the pre-existing-in-changed-file rule places this in scope.
- **Problem**: Misleading documentation. Functional behavior is unaffected (merge-findings copies sections verbatim).
- **Impact**: Confusing to future maintainers.
- **Fix**: Updated `R1-R13` → `R1-R28`.

### T1 [Minor] — Truncation-detection test checklist missing "trailing blank line valid case"
- **File**: `docs/archive/review/add-ollama-expert-analyze-commands-plan.md` § Testing strategy
- **Evidence**: SKILL.md Step 3-2 loop uses `sed '/^[[:space:]]*$/d' | tail -1` which is a hardening beyond the plan's original `tail -1`. The plan's truncation-detection test only covers the "no sentinel at all" case; a file like `printf '...\n## END-OF-ANALYSIS\n\n'` (valid sentinel + trailing blank line) is the case that specifically exercises the hardening but is not listed.
- **Problem**: Manual test checklist does not verify the hardening. Future regression (e.g., the `sed` filter being removed) would not be caught.
- **Impact**: Manual-test gap only; code is correct.
- **Fix**: Added a second case to the Truncation-detection test in the plan's Testing strategy, covering the trailing-blank-line-valid scenario with a MUST-NOT-warn assertion.

### T2 [Minor] — Token-reduction measurement numbers not recorded in the review artifact
- **File**: `docs/archive/review/add-ollama-expert-analyze-commands-deviation.md`
- **Evidence**: Plan Testing strategy §"Token-reduction measurement" requires recording `git diff | wc -c` baseline and `wc -c /tmp/seed-*.txt` numbers to demonstrate empirical support for the token-saving claim. The deviation log recorded smoke-test observations but not the numerical measurement.
- **Problem**: The empirical evidence for the ≤30% target is not traceable from the review artifact.
- **Impact**: Traceability gap; future reviewers cannot verify the claim was measured.
- **Fix**: Added deviation log entry D5 with baseline (65155 bytes), per-seed sizes (1393/710/1462 bytes), and total (3565 bytes = 5.5% of baseline).

## Adjacent Findings
None.

## Quality Warnings
None (all findings include concrete file/line references, evidence, and specific fixes).

## Recurring Issue Check

### Functionality expert
- R1-R28: all Pass or N/A; most patterns do not apply to a hooks+skill-text Plan. Key checks:
  - R3 (pattern propagation): sentinel `## END-OF-ANALYSIS` consistent across 3 cmd_ prompts + Step 3-2 + Step 3-3 template
  - R17 (helper reuse): `_ollama_request` used by all 3 new cmd_analyze_* functions; `_ollama_analyze_normalize` is properly shared
  - R21 (subagent completion vs verification): verification contract explicit in Step 3-3; this review exercised it

### Security expert
- R1-R28, RS1-RS3: all Pass or N/A
- RS3 specifically verified: diff content flows through `jq --rawfile` (JSON-escaped); `sed`/`awk` in normalize operate on model output with fixed literal patterns; no injection surface

### Testing expert
- R1-R28, RT1-RT3: all Pass or N/A
- RT2 self-applied: 3 of 4 seed findings rejected as policy-violation test-framework recommendations
- RT1: Ollama smoke tests use live calls, not mocks

## Resolution Status

### F1 [Major] SIGPIPE in normalize pipeline — Resolved
- Action: Rewrote `_ollama_analyze_normalize` to drain stdin via `next` instead of `exit`. Removed the `local s=${PIPESTATUS[1]}` salvage attempt (dead code).
- Modified file: `hooks/ollama-utils.sh:123-144`

### F2 [Minor] Stale R1-R13 reference — Resolved
- Action: Updated `cmd_merge_findings` system prompt text `R1-R13` → `R1-R28`.
- Modified file: `hooks/ollama-utils.sh:106`

### T1 [Minor] Trailing-blank-line test case — Resolved
- Action: Added a second case to the Truncation-detection test in the plan's Testing strategy.
- Modified file: `docs/archive/review/add-ollama-expert-analyze-commands-plan.md` § Testing strategy

### T2 [Minor] Measurement numbers missing — Resolved
- Action: Added D5 to the deviation log with baseline/seed sizes and percentage.
- Modified file: `docs/archive/review/add-ollama-expert-analyze-commands-deviation.md`
