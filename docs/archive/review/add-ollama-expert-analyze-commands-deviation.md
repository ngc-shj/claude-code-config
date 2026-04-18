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

### D5: Token-reduction measurement recorded (addresses Phase 3 Round 1 finding T2)
- **Plan description**: Testing strategy §"Token-reduction measurement" requires recording `git diff main...HEAD | wc -c` baseline and `wc -c /tmp/seed-*.txt` post-sizes, asserting total seed size ≤30% of baseline, and keeping the numbers "in the review artifact as evidence that the token-saving claim is empirically supported."
- **Actual measurement** (taken during Phase 3 Step 3-2b, committed-state diff):
  - Baseline: `git diff main...HEAD | wc -c` = **65155 bytes**
  - Seed sizes: `/tmp/seed-func.txt` = 1393 B, `/tmp/seed-sec.txt` = 710 B, `/tmp/seed-test.txt` = 1462 B
  - Total seed: **3565 bytes** = **5.5%** of baseline (target ≤30%; actual 5.5%)
- **Impact scope**: Numbers-only record. No code change. Demonstrates the token-reduction claim empirically.

### D6: SIGPIPE-safe rewrite of `_ollama_analyze_normalize` (addresses Phase 3 Round 1 finding F1)
- **Plan description**: The plan specified the sentinel normalization only abstractly ("split inline sentinels, dedupe repeats, stop at first"). The first implementation used `awk '... exit'` which exits on the first sentinel.
- **Actual implementation**: Under `set -o pipefail`, awk's early `exit` caused the upstream `_ollama_request`'s `printf` to receive SIGPIPE when the response exceeded the pipe buffer (~64KB), propagating exit 141 and failing the `analyze-*` invocation. Reproduced experimentally. Fix: rewrote the awk filter to consume all stdin (emit the first sentinel, silently `next` over subsequent lines) instead of calling `exit`. This eliminates SIGPIPE entirely. Verified no regression on normal / No-findings / trailing-repeats / normal-large inputs.
- **Reason**: Root-cause fix for a real failure mode observed during Phase 3 smoke testing.
- **Impact scope**: `_ollama_analyze_normalize` only. No change to caller contracts. Pipeline always exits 0 on well-formed sentinel input regardless of upstream pipe-buffer behavior.

### D7: Stale R1-R13 reference in `cmd_merge_findings` system prompt updated to R1-R28 (addresses Phase 3 Round 1 finding F2)
- **Plan description**: The plan did not mandate a change to `cmd_merge_findings`; the finding applied the Pre-existing-in-changed-file rule since `hooks/ollama-utils.sh` is in the diff.
- **Actual implementation**: Updated line 106 of `cmd_merge_findings`'s system prompt: `R1-R13` → `R1-R28`. Pre-existing documentation drift that became in-scope by the file-touching rule.
- **Reason**: Anti-Deferral / Pre-existing-in-changed-file obligation — bug in a changed file must be flagged and fixed.
- **Impact scope**: `cmd_merge_findings` system prompt only. Functional behavior unchanged (merge-findings copies the R-check sections verbatim regardless).

### D4: Codebase Awareness Obligations paragraph scope
- **Plan description**: "a short paragraph ... clarifying that 'Ollama seed findings are starting evidence; sub-agents retain full responsibility for codebase-wide investigation.'"
- **Actual implementation**: Added the intended paragraph, plus one additional sentence clarifying that an empty `No findings` seed does NOT discharge the expert from performing the full R1-R28 Recurring Issue Check. This strengthens the guarantee targeted by Round 1 finding F3 and Round 2 finding T6.
- **Reason**: Strict superset; reinforces existing R1-R28 obligation in a location where it cannot be overlooked.
- **Impact scope**: `Codebase Awareness Obligations` section only. No behavior change — expresses existing obligations.
