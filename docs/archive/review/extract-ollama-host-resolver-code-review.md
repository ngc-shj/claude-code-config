# Code Review: extract-ollama-host-resolver
Date: 2026-03-27
Review round: 1

## Changes from Previous Round
Initial review

## Functionality Findings

### F1 [Major] Symlink check after stat — RESOLVED
- **File**: resolve-ollama-host.sh:17-23
- **Problem**: stat called before symlink check, following symlink target unnecessarily
- **Fix**: Moved symlink check (`! [ -L ]`) before stat call

### F2 [Major] mktemp silent degradation — ACCEPTED
- **Problem**: mktemp failure causes repeated probes on every call
- **Decision**: Acceptable degradation; cache is an optimization, not a requirement

### F3 [Minor] commit-msg-check.sh heredoc parsing — SKIPPED
- **Problem**: Existing issue unrelated to this refactoring

### F4 [Minor] id -u subshell per call — SKIPPED
- **Problem**: Negligible performance impact

## Security Findings

### S1 [Minor] TOCTOU race on cache — ACCEPTED
- **Problem**: Theoretical race between symlink check and cat
- **Decision**: Acceptable for personal developer tool

### S2 [Major] Prompt injection in commit-msg-check.sh — SKIPPED
- **Problem**: Pre-existing issue in commit-msg-check.sh, not introduced by this change
- **Decision**: Out of scope for this refactoring

### S3 [Minor] JSON injection in $REVIEW — SKIPPED
- **Problem**: Pre-existing issue, out of scope

## Testing Findings

### M-1 [Major] Export test false-positive — RESOLVED
- **File**: tests/resolve-ollama-host.bats
- **Problem**: Test pre-exported OLLAMA_HOST, masking whether script actually exports
- **Fix**: Test now lets script resolve via probe, then verifies export in subprocess

### M-2 [Major] touch -d macOS incompatible — RESOLVED
- **File**: tests/resolve-ollama-host.bats
- **Problem**: `touch -d "10 minutes ago"` is GNU-only
- **Fix**: Added `set_mtime_ago()` helper with GNU fallback to python3

### m-1 [Minor] local variable style — RESOLVED
- **Fix**: Removed unnecessary `local` declarations in test blocks

### m-2 [Minor] Unused mock path — RESOLVED
- **Fix**: Simplified setup_curl_mock to single implementation using CURL_SUCCEED_HOSTS

### m-3 [Minor] No CI/CD — SKIPPED
- **Decision**: Out of scope

## Adjacent Findings
None

## Resolution Status

### F1 [Major] Symlink check ordering
- Action: Restructured cache read to check symlink before calling stat
- Modified file: hooks/resolve-ollama-host.sh:15-23

### M-1 [Major] Export test false-positive
- Action: Rewrote test to use probe-based resolution instead of pre-exported value
- Modified file: tests/resolve-ollama-host.bats

### M-2 [Major] touch -d incompatibility
- Action: Added cross-platform set_mtime_ago() helper function
- Modified file: tests/resolve-ollama-host.bats
