# Code Review: Linux/cross-platform notify hooks + install.sh settings.json merge
Date: 2026-06-14
Review round: 1 (Phase 3 standalone — uncommitted changes on main)

## Scope
Cherry-picked from the closed PR #79 (masa-san-jp/claude-code-config Linux fork):
- `hooks/notify.sh`, `hooks/stop-notify.sh` — macOS-only → cross-platform (macOS afplay/osascript + Linux paplay/aplay + notify-send).
- `install.sh` — `settings.json` overwrite → merge (preserve user top-level keys; template owns permissions/hooks).
- `README.md`, `tests/install.bats`, `tests/notify.bats` updates.

Project context: config-only repo, test infra = bats. No CI/CD beyond bats.

## Findings & Resolution

### F1 [Major] notify hooks abort under `set -e` when no sound file resolves
- `_resolve_linux_sound` returned non-zero on no match; `sound="$(...)"` then aborted the hook before notifying. Reproduced empirically (exit 1, no notification).
- **Fixed**: resolver now `return 0` in both hooks. Regression test: `notify.bats` "a failing notify-send/paplay does not abort the hook".

### F2 [Major] install.sh aborts on empty/non-object live settings.json
- `jq '*'` errors on null/array operands; an empty or non-object live file aborted the whole install.
- **Fixed**: merge gated on `jq -e 'type == "object"'`; empty/garbage files are backed up and replaced. Tests: "empty live settings.json…", "non-object live settings.json (array)…".

### S2 [Low] / F3 [Minor] deep-merge leaked unmanaged hook events; docs inaccurate
- `jq '.[0] * .[1]'` deep-merges, so user-only `permissions` sub-keys and unmanaged hook events (e.g. `PostToolUse`) survived — contradicting the documented "template wins".
- **Fixed**: merge expression now `.[1] as $t | (.[0] * .[1]) | .permissions = $t.permissions | .hooks = $t.hooks` — wholesale-replaces those two template-owned keys. README/comment corrected. Verified: stale `allow` sub-key and unmanaged `PostToolUse` both dropped; mcpServers/extra keys preserved. Test: "merge replaces hooks wholesale".

### S1 [Low] backup file permissions
- **Fixed**: backups `chmod 600` (may carry mcpServers env secrets).

### S3 [Info] osascript interpolation is a latent injection sink
- No current vuln (all notify args are static literals; no `$INPUT`-derived data reaches osascript/notify-send). **Mitigated**: added a `_notify` caller contract comment in both hooks.

### T1 [Major] notify hooks untested
- **Fixed**: added `tests/notify.bats` (8 tests: macOS path, Linux path, unknown-type no-op, max_tokens urgency, hang regression ×2, fail-robustness).

### T2 [Major] notify-send foreground call hangs the hook
- Observed exit 124 on this host (synchronous D-Bus call with no servicing daemon).
- **Fixed**: notify-send backgrounded (`&`) in both hooks. Verified on real host (exit 0, no hang) + bats hang-regression tests.

### T3 [Major] merge error/replace branches untested
- **Addressed**: the empty/non-object branches (the realistic data-loss-risk paths) are now covered with backup-preserved + exit-0 assertions. The residual `jq` merge-failure `else` branch is defensive (unreachable with two valid objects) and left as a safety net.

### S4 [Info], T4–T6 — no action (no defect).

## Accepted (Anti-Deferral)
### F4 [Minor] Timestamped backups accumulate, not auto-pruned — Accepted
- **Anti-Deferral check**: acceptable risk.
- **Worst case**: small (~KB) text files pile up at `~/.claude/` root, one per install run with an existing object settings.json.
- **Likelihood**: low-moderate (re-runs only).
- **Cost to fix**: ~5 lines adding `rm`-based prune-keep-last-N — introduces a destructive op into the installer, higher risk than the benign clutter it removes. Files sit at the `~/.claude/` root (not under `skills/`), so they are NOT loaded as shadow skills.
- **Sign-off**: documented in README ("Backups are not auto-pruned — purge old ones periodically"). Accepted.

## Verification
- `bats tests/notify.bats` → 8/8 pass. `bats tests/install.bats` → 8/8 pass.
- Real-host smoke: both hooks exit 0 without hanging.
- jq merge invariants verified end-to-end against the real template.
- `bash -n` clean on all three scripts.

All Critical/Major findings resolved.
