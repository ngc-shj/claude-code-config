# Plan Review: extract-ollama-host-resolver
Date: 2026-03-27
Review round: 1

## Changes from Previous Round
Initial review

## Functionality Findings

### F1 [Major] resolve-ollama-host.sh must not read stdin
- **Problem**: `resolve-ollama-host.sh` has no explicit constraint against reading stdin. If sourced before `INPUT=$(cat)` in `commit-msg-check.sh`, any stdin consumption would destroy the hook's input.
- **Impact**: `commit-msg-check.sh` would receive empty `INPUT` and approve all commits silently.
- **Recommended action**: Add constraint to plan: "resolve-ollama-host.sh must not read stdin (no `cat`, no `read` from stdin)".

### F2 [Major] Cache write is not atomic
- **Problem**: Concurrent hook invocations could read a partially-written cache file.
- **Impact**: Invalid OLLAMA_HOST value (empty or truncated URL) causing curl failures.
- **Recommended action**: Use `mktemp` + `mv` for atomic cache writes.

### F3 [Minor] set -e interaction with source
- **Problem**: If `resolve-ollama-host.sh` has unhandled errors during probing, `set -e` in the parent script would cause it to exit.
- **Recommended action**: Ensure all error-producing commands in resolve-ollama-host.sh use `|| true`.

## Security Findings

### S1 [Minor] JSON injection in commit-msg-check.sh $REVIEW variable
- **Problem**: `$REVIEW` is interpolated directly into JSON string (L50) without escaping.
- **Recommended action**: Use `jq --arg` to safely build JSON. Out of scope for this refactoring but good to fix opportunistically.

### S2 [Minor] Cache file symlink attack and value validation
- **Problem**: No symlink check before cache write; no URL format validation when reading cache.
- **Recommended action**: Check `[[ -L "$cache_file" ]]` before write; validate cached value matches `^https?://[a-zA-Z0-9._-]+(:[0-9]+)?$`.

### S3 [Minor] Path traversal in pre-review.sh git diff parsing
- **Problem**: File paths from `git diff` output are used directly in `cat`/`head` without validation.
- **Recommended action**: Add path validation check. Out of scope for this refactoring.

## Testing Findings

### T1 [Critical] Cache file path not overridable — test isolation impossible
- **Problem**: Hardcoded cache path `/tmp/.ollama-host-cache-$(id -u)` prevents test isolation. Parallel bats tests would interfere.
- **Impact**: False positives/negatives in cache-related tests.
- **Recommended action**: Make cache path configurable via env var (e.g., `OLLAMA_HOST_CACHE_FILE`) for test injection.

### T2 [Major] No mechanism to verify probe order
- **Problem**: Mock curl has no way to record which hosts were probed or in what order.
- **Recommended action**: Extend mock curl to log connection URLs; verify probe order and short-circuit behavior in tests.

### T3 [Major] No tests for commit-msg-check.sh
- **Problem**: `commit-msg-check.sh` has no tests, yet its host resolution is being changed.
- **Recommended action**: Add basic smoke tests for `commit-msg-check.sh` covering the source + OLLAMA_HOST integration.

### T4 [Minor] Manual-only install.sh verification
- **Problem**: Path resolution via `BASH_SOURCE[0]` after install is only verified manually.
- **Recommended action**: Add automated test simulating installed layout.

### T5 [Minor] Fallback test needs curl call count assertion
- **Problem**: Without counting curl invocations, fallback test can't distinguish "all hosts failed" from "first host succeeded".
- **Recommended action**: Combine with T2's mock curl logging to assert call count.

## Adjacent Findings
None
