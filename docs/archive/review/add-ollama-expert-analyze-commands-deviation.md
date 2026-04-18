# Coding Deviation Log: add-ollama-expert-analyze-commands
Created: 2026-04-19

## Deviations from Plan

### D1: Strengthened sentinel-emission instruction in `cmd_analyze_*` system prompts
- **Plan description**: "the system prompt MUST instruct the model to emit the literal line `## END-OF-ANALYSIS` as the last line of output, unconditionally — whether findings are present, `No findings` was produced, or no findings exist." (plan §System-prompt design principles)
- **Actual implementation**: The first smoke test on the real diff showed `gpt-oss:120b` emitted valid findings for `analyze-security` but omitted the sentinel (3 findings, 3339 bytes, no `## END-OF-ANALYSIS` line). Root cause: the original prompt phrased the requirement passively ("After all findings, output..."), which the model treated as optional. The prompt was strengthened to:
  - Label the requirement "MANDATORY FINAL LINE" and mark it "UNCONDITIONAL"
  - State the consequence of omission ("your output is invalid and will be discarded")
  - Add concrete structural examples for both "findings present" and "No findings" cases
- **Reason**: Strict superset of the plan's specification, not a reversal. The plan required sentinel emission; the implementation found a model-compliance gap and closed it with more emphatic prompting. Re-test after strengthening: 3/3 seeds emit the sentinel.
- **Impact scope**: All three `cmd_analyze_*` functions in `hooks/ollama-utils.sh`. No impact on skill text or caller contracts. No re-verification of unrelated paths required.

### D2: README.md updated with the three new subcommands
- **Plan description**: Implementation step 6: "Verify README.md does NOT need updating... if none are referenced, no README change is required."
- **Actual implementation**: Verification check found `README.md:140,143,146,149` already lists the existing 4 subcommands (`generate-slug`, `summarize-diff`, `merge-findings`, `classify-changes`) with example pipelines. Per the plan's own conditional ("if any current subcommand is listed, then new ones must also be added for consistency"), the three new `analyze-*` subcommands were added in the same section with a brief note on their purpose (seed generation for multi-agent-review Phase 3).
- **Reason**: Follows the plan's explicit conditional logic. Not a reversal — the plan anticipated both branches.
- **Impact scope**: `README.md` only. No code behavior change.

### D3: No deviations in Step 3-3 template content vs plan Round 1 template specification
- **Plan description**: Three-way conditional + Seed trust advisory + Verification contract + Seed Finding Disposition section.
- **Actual implementation**: Inserted verbatim (prose rewording only for fit within the existing `Target code:` block replacement).
- **Reason**: None — this is not a deviation, documented for audit completeness.
- **Impact scope**: n/a

### D4: Codebase Awareness Obligations paragraph scope
- **Plan description**: "a short paragraph ... clarifying that 'Ollama seed findings are starting evidence; sub-agents retain full responsibility for codebase-wide investigation.'"
- **Actual implementation**: Added the intended paragraph, plus one additional sentence clarifying that an empty `No findings` seed does NOT discharge the expert from performing the full R1-R28 Recurring Issue Check. This strengthens the guarantee targeted by Round 1 finding F3 and Round 2 finding T6.
- **Reason**: Strict superset; reinforces existing R1-R28 obligation in a location where it cannot be overlooked.
- **Impact scope**: `Codebase Awareness Obligations` section only. No behavior change — expresses existing obligations.
