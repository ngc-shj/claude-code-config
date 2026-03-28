# Code Review: allow-plan-file-edits
Date: 2026-03-28
Review rounds: 2

## Changes from Previous Round
Round 2: Moved Write(~/.claude/plans/*) from allow to ask per S1.

## Functionality Findings
No findings.

## Security Findings

### S1 [Major]: Write permission in allow enables confirmation-free plan file overwrite
- **File:** settings.json:145
- **Problem:** `Write(~/.claude/plans/*)` in `allow` enables confirmation-free creation/overwrite of plan files, which could be exploited via prompt injection or malicious MCP server
- **Impact:** Plan file tampering without user awareness
- **Recommended fix:** Move `Write(~/.claude/plans/*)` from `allow` to `ask`

### S2 [Minor]: `~` path expansion undocumented for Read/Edit/Write matchers
- **File:** settings.json:143-145
- **Problem:** Tilde expansion behavior for non-Bash tool matchers is not explicitly documented
- **Recommended fix:** Verify via testing; existing Bash hooks use same pattern successfully

### S3 [Minor]: block-sensitive-files.sh cannot prevent arbitrary new plan file creation via Write
- **File:** settings.json:172-181
- **Problem:** Hook passes non-sensitive filenames unconditionally
- **Recommended fix:** Mitigated by S1 fix (Write to ask)

## Testing Findings

### T1 [Major]: No automated test for settings.json allow entries
- **File:** settings.json:143-145
- **Problem:** Typos or syntax errors in allow entries are not caught until runtime
- **Recommended fix:** Add bats test validating allow entries with jq

### T2 [Major]: No E2E verification that permission prompts are suppressed
- **File:** settings.json:143-145
- **Problem:** Plan's testing strategy is manual-only
- **Recommended fix:** Add smoke test or jq-based validation

### T3 [Minor]: Wildcard pattern subdirectory behavior untested
- **File:** settings.json:143-145
- **Problem:** `*` may not match subdirectory files
- **Recommended fix:** Acceptable for current flat directory usage

## Adjacent Findings
None.

## Resolution Status

### S1 [Major] Write permission in allow
- **Action:** Moved `Write(~/.claude/plans/*)` from `allow` to `ask`
- **Modified file:** settings.json:144,148
- **Status:** Resolved

### S2 [Minor] ~ path expansion
- **Action:** Skipped — existing Bash hook entries use identical `~` notation and work correctly
- **Status:** Accepted

### S3 [Minor] block-sensitive-files.sh Write bypass
- **Action:** Mitigated by S1 fix
- **Status:** Resolved

### T1 [Major] No automated test for allow entries
- **Action:** Skipped — config-only repo without CI; jq assertion tests are over-engineering for this scope
- **Status:** Accepted

### T2 [Major] No E2E verification
- **Action:** Skipped — depends on Claude Code runtime, not automatable
- **Status:** Accepted

### T3 [Minor] Subdirectory wildcard
- **Action:** Skipped — flat directory structure, no subdirectories in use
- **Status:** Accepted
