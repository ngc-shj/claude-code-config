# Plan: extract-ollama-host-resolver

## Objective

Extract the duplicated Ollama host resolution logic from three hook scripts into a single shared file (`resolve-ollama-host.sh`), enabling automatic detection of the reachable Ollama server across different network environments.

## Requirements

### Functional
- Auto-detect the reachable Ollama host by probing in order: `gx10-a9c0`, `gx10-a9c0.local`, `localhost`
- Honor the `OLLAMA_HOST` environment variable when set (skip auto-detection)
- Cache the resolved host for 5 minutes (cache path configurable via `_OLLAMA_HOST_CACHE` env var, default `/tmp/.ollama-host-cache-$(id -u)`)
- Cache writes must be atomic (`mktemp` + `mv`) to prevent corruption from concurrent invocations
- Fall back to `gx10-a9c0` if no host is reachable
- Export `OLLAMA_HOST` so downstream subprocesses inherit it
- All three hook scripts (`ollama-utils.sh`, `pre-review.sh`, `commit-msg-check.sh`) must source the shared file instead of defining their own host

### Non-functional
- No change in behavior when `OLLAMA_HOST` is already set
- Auto-detection probe adds at most 1 second per unreachable host (connect-timeout)
- Existing tests must continue to pass (they set `OLLAMA_HOST` explicitly)

## Technical Approach

1. Create `hooks/resolve-ollama-host.sh` — a sourceable script that defines `_resolve_ollama_host()` and sets/exports `OLLAMA_HOST`
2. Replace the `OLLAMA_HOST=...` line in each hook with `source resolve-ollama-host.sh`
3. Use `$(dirname "${BASH_SOURCE[0]}")` for relative path resolution so the source works regardless of working directory
4. Side effects of sourcing: sets and exports `OLLAMA_HOST`, may create/update cache file
5. Cross-platform cache age check: try GNU `stat -c %Y` first, fall back to `stat -f %m` (macOS/BSD)
6. `resolve-ollama-host.sh` must NOT read stdin — it is sourced before `INPUT=$(cat)` in `commit-msg-check.sh`
7. All error-producing commands in `resolve-ollama-host.sh` must use `|| true` to be safe under `set -e`
8. Before writing cache, check that the path is not a symlink (`[[ -L ... ]]`)

## Implementation Steps

1. Create `hooks/resolve-ollama-host.sh` with `_resolve_ollama_host()` function and `OLLAMA_HOST` export
2. Update `hooks/ollama-utils.sh`: replace `OLLAMA_HOST="${OLLAMA_HOST:-http://gx10-a9c0:11434}"` with source line
3. Update `hooks/pre-review.sh`: replace `OLLAMA_HOST="${OLLAMA_HOST:-http://gx10-a9c0:11434}"` with source line
4. Update `hooks/commit-msg-check.sh`: add source line before `INPUT=$(cat)`, replace hardcoded URL with `$OLLAMA_HOST`
5. Add tests for `resolve-ollama-host.sh` in `tests/resolve-ollama-host.bats`
6. Run all tests and verify they pass

## Testing Strategy

- Unit tests for `resolve-ollama-host.sh` (using bats, mock curl via PATH override):
  - `OLLAMA_HOST` env var set: returns it directly, no probing
  - Cache file exists and fresh: returns cached value
  - Cache file stale/missing: probes hosts in order (mock curl logs URLs to verify order)
  - All hosts unreachable: returns fallback (assert curl call count = 3)
  - Idempotent: sourcing twice does not re-probe when `OLLAMA_HOST` is already set
  - Cache path overridable via `_OLLAMA_HOST_CACHE` for test isolation
- Existing `ollama-utils.bats` tests must pass unchanged (they set `OLLAMA_HOST` explicitly)
- Manual verification: run `install.sh` and confirm hooks work from `~/.claude/hooks/`

## Considerations & Constraints

- `ollama-utils.sh` has a dispatcher at the bottom (`case "$CMD"`), so it cannot be sourced by other scripts — hence the separate `resolve-ollama-host.sh` file
- `stat -c %Y` (GNU) vs `stat -f %m` (macOS): need cross-platform approach for cache age check
- The `commit-msg-check.sh` hook reads stdin early (`INPUT=$(cat)`), so the source line must come before the `cat` call
- `install.sh` already deploys all `hooks/*.sh` files, so no changes needed there
- `resolve-ollama-host.sh` must never read stdin (no `cat`, no `read` from fd 0)
- All commands that may fail (curl, stat) must be guarded with `|| true` for `set -e` safety
