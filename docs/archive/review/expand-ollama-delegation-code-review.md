# Code Review: expand-ollama-delegation
Date: 2026-04-19
Review round: 1

## Changes from Previous Round
Initial Phase 3 code review.

## Seed Finding Disposition

### Functionality
- seed-func = "No findings" → performed independent R1-R30. No issues.

### Security (5 seed findings)
- S1 (Major, prompt injection advisory): Rejected — all 6 new cmd_* system prompts include the mandatory advisory. Already covered.
- S2 (Major, `echo "$FINDING"` shell injection in README): **Rejected — false positive, confirmed by live test** (`FINDING='$(date)'; echo "$FINDING"` prints `$(date)` literally; bash double-quoted expansion does NOT re-evaluate `$(...)` inside the expanded string).
- S3 (Major, same for SKILL.md `echo "$FINDING_BLOCK"`): Rejected, same false positive as S2.
- S4 (Minor, separator collision): Rejected — already documented with injection-source enumeration in plan's Separator leak risk section.
- S5 (Minor, secrets via diffs to Ollama): Rejected — pre-existing pattern applying to all Ollama commands; out of this PR's scope.

### Testing (5 seed findings)
- T1 (Minor, literal marker in callers): Already-addressed design decision with future-refactor TODO.
- T2 (Minor, "6 new subcommands have no test harness"): RT2 violation — rejected.
- T3 (Minor, `No new deviations` edge case): Already covered by plan's three-branch test (branch 1 explicitly tests this).
- T4 (Minor, propose-plan-edits sentinel test): Already covered by Testing strategy pass criterion.
- T5 (Minor, README/dispatcher sync test): Already covered by plan verification steps 7.1 + 7.7.

## Findings

### F-1 [Minor] — Plan verification 7.2 uses `grep -cE` (line count) but expected unique-name count
- **File**: plan §Cross-cutting verification step 7.2; deviation log §verification table row 7.2.
- **Evidence**: The help output wraps 6 command names across 2 continuation lines. `grep -cE` counts matching lines → returns 2, not 6.
- **Problem**: Plan spec says "MUST return 6" with `-cE`, which mathematically cannot happen with the current help layout. Deviation log incorrectly asserts "6 ✓".
- **Impact**: Documentation-only; does not affect runtime. A future maintainer running the verification as-specified will see a false failure.
- **Fix**: Change 7.2 to `grep -oE ... | sort -u | wc -l` (counts unique occurrences). Annotate that `-cE` counts lines.

### F-2 [Minor] — Skill text phrasing diverges from plan's explicit requirement
- **File**: `skills/multi-agent-review/SKILL.md:297`
- **Evidence**: Skill reads `The grep-verify is NOT optional.` Plan §109 explicitly says "the skill note MUST phrase it as 'MUST grep-verify' rather than 'verify'."
- **Problem**: Semantically equivalent, but plan has a word-level requirement.
- **Fix**: Change to `MUST grep-verify — the check is NOT optional.`

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check

### Functionality expert (R1-R30 detailed)
All pass: dispatcher completeness, help output, bash syntax, 3-section input construction, `_ollama_request` reuse, timeouts, models, prompt-injection advisory, separator constant, grep-verify contract, 10 cross-cutting verification checks (with 7.2 correction per F-1).

### Security expert (R1-R30 + RS1-RS3)
All pass or N/A. Notable:
- Prompt-injection advisory present in all 6 new cmd_*.
- No eval/unquoted expansion/backticks.
- `jq --rawfile` properly isolates JSON.
- `trap rm -rf` cleanup per `_ollama_request`.
- Mandatory grep-verify for propose-plan-edits prevents plan corruption.

### Testing expert (R1-R30 + RT1-RT3)
All pass or N/A. RT2 self-applied (seed T2 rejected). Manual smoke tests + three-branch generate-deviation-log coverage + sentinel check + README/dispatcher sync all covered by plan.

## Resolution Status

### F-1 [Minor] Plan 7.2 counting bug — Resolved
- Action: updated 7.2 to use `grep -oE ... | sort -u | wc -l` with explanatory note.
- Modified file: `docs/archive/review/expand-ollama-delegation-plan.md` §7.2

### F-2 [Minor] Skill text phrasing — Resolved
- Action: changed "The grep-verify is NOT optional." → "MUST grep-verify — the check is NOT optional."
- Modified file: `skills/multi-agent-review/SKILL.md:297`
