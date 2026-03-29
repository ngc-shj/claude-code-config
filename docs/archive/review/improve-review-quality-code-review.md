# Code Review: improve-review-quality
Date: 2026-03-29T04:45:00Z
Review round: 1

## Changes from Previous Round
Initial review

## Functionality Findings

### F-01 [Major]: SHARED_UTILS prepended after budget calculation — potential context overflow
- File: hooks/pre-review.sh:62,102
- Problem: SHARED_UTILS is prepended to CONTENT after FILE_BUDGET is calculated, potentially exceeding MAX_INPUT_CHARS
- Impact: Ollama request exceeds context limit silently
- Fix: Move scanner call before budget calculation; subtract SHARED_UTILS length

### F-02 [Major]: Quality Warnings from merge-findings have no orchestrator-side handling in SKILL.md
- File: hooks/ollama-utils.sh:97, skills/multi-agent-review/SKILL.md (Step 1-5, 1-6, 3-4, 3-5)
- Problem: ollama-utils.sh appends `## Quality Warnings` but SKILL.md never instructs the orchestrator to check or act on it
- Impact: Quality gate is dead logic; vague findings pass through unchecked
- Fix: Add instruction in Step 1-6 and Step 3-5 to check Quality Warnings and return flagged findings to experts
- Also flagged by: Testing expert (F-03)

### F-03 [Major]: Plan pre-screening checks R1 without providing inventory to LLM
- File: hooks/pre-review.sh:22-41, skills/multi-agent-review/SKILL.md (Step 1-3)
- Problem: Plan mode asks LLM to check for shared utility reimplementation but provides no inventory
- Impact: R1 check at plan phase is structurally unreliable
- Fix: Add scan-shared-utils.sh invocation in plan mode, similar to code mode

### F-04 [Minor]: Elixir absent from fallback language detection
- File: hooks/scan-shared-utils.sh:26-34
- Problem: Primary detection (mix.exs) works, but fallback misses Elixir
- Fix: Add Elixir fallback detection line

### F-05 [Minor]: settings.json allow rule format inconsistency
- File: settings.json:143
- Problem: Cosmetic inconsistency with ollama-utils.sh rule format
- Fix: No action needed — functionally correct

## Security Findings

### S-01 [Minor]: eval in scan-shared-utils.sh — replaceable with array-based find
- File: hooks/scan-shared-utils.sh:146
- Problem: eval used for find command construction; currently safe but fragile for future extensions
- Fix: Replace eval with array-based find call

### S-02 [Minor]: settings.json allow rule permits arbitrary path argument
- File: settings.json:143
- Problem: Wildcard allows scan-shared-utils.sh to scan arbitrary directories
- Fix: Remove wildcard or restrict to no-argument invocation

### S-03 [Minor]: LLM prompt injection via file content in pre-review.sh
- File: hooks/pre-review.sh:93-108
- Problem: File content injected into LLM prompt without delimiters
- Impact: Low — pre-review is informational, not a gate
- Fix: Add XML delimiters around user content (risk reduction, not elimination)

### S-04 [Minor]: /tmp fixed path in SKILL.md instruction
- File: skills/multi-agent-review/SKILL.md:259
- Problem: Fixed /tmp/shared-utils-inventory.txt path is predictable (symlink attack)
- Fix: Use mktemp

## Testing Findings

### T-01 [Minor]: scan-shared-utils.sh export pattern may produce false positives for R1
- File: hooks/scan-shared-utils.sh:147-155
- Problem: Pattern-based scan lists internal helpers as shared utilities, potentially causing false R1 findings
- Fix: Add disclaimer note to inventory output

### T-02 [Minor]: head -200 truncation in pre-review.sh is silent
- File: hooks/pre-review.sh:102
- Problem: Truncation of scanner output is not communicated to LLM; later sections (event dispatch) may be lost
- Fix: Add truncation warning when line count exceeds limit

## Adjacent Findings
None

## Resolution Status

### F-01 [Major] SHARED_UTILS budget overflow
- Action: Moved scanner call before budget calculation; subtracted SHARED_UTILS_LEN
- Modified file: hooks/pre-review.sh

### F-02 [Major] Quality Warnings orchestrator handling
- Action: Added Quality gate check step in Step 1-6 and Step 3-5; added ## Quality Warnings to review templates
- Modified file: skills/multi-agent-review/SKILL.md

### F-03 [Major] Plan mode missing inventory
- Action: Added scan-shared-utils.sh invocation in plan mode; updated system prompt to reference inventory
- Modified file: hooks/pre-review.sh

### F-04 [Minor] Elixir fallback detection
- Action: Added Elixir fallback line in detect_languages
- Modified file: hooks/scan-shared-utils.sh

### S-01 [Minor] eval in scan-shared-utils.sh
- Action: Replaced eval with array-based find call
- Modified file: hooks/scan-shared-utils.sh

### S-02 [Minor] settings.json wildcard argument
- Action: Removed wildcard — now allows only no-argument invocation
- Modified file: settings.json

### S-04 [Minor] /tmp fixed path
- Action: Changed to mktemp in SKILL.md instruction
- Modified file: skills/multi-agent-review/SKILL.md

### T-01 [Minor] False positive risk in scan output
- Action: Added NOTE disclaimer at top of inventory output
- Modified file: hooks/scan-shared-utils.sh

### T-02 [Minor] Silent truncation
- Action: Added truncation warning when scanner output exceeds 200 lines
- Modified file: hooks/pre-review.sh

### Skipped
- F-05 [Minor]: Cosmetic format inconsistency — functionally correct, no action
- S-03 [Minor]: Prompt injection via file content — current design (informational, not gate) provides sufficient mitigation
