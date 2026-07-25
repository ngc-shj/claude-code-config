# RTK — Rust Token Killer

Token-optimized CLI proxy (60-90% savings on dev operations), registered as
the first `PreToolUse` Bash hook in `settings.json`. It rewrites common dev
commands (`git status` → `rtk git status`, `pytest` → `rtk pytest`) so Claude
sees filtered output instead of raw stdout. The rewrite is transparent — no
action needed for normal use; read on when debugging it or auditing privacy.

## Meta commands (always invoke `rtk` directly)

```bash
rtk gain              # Token savings analytics
rtk gain --history    # Command usage history with savings
rtk discover          # Analyze Claude Code history for missed opportunities
rtk proxy <cmd>       # Run a command raw, bypassing the filter
```

## Installation check

```bash
rtk --version         # Expect: rtk X.Y.Z
rtk gain              # Must not be "command not found"
which rtk             # Verify the binary
```

⚠️ **Name collision**: if `rtk gain` fails, you may have reachingforthejack/rtk
(Rust Type Kit) installed instead.

## Interaction with this repo's hooks

- The rewrite runs BEFORE the `block-*` deny hooks, so `tool_input.command`
  reads `rtk <verb>...`. The R31 destructive-op regexes match the preserved
  substring (`git push --force`, `docker volume rm`), so those blocks still fire.
- `commit-msg-check.sh` accepts an `rtk`-prefixed `git commit ...`, keeping
  LLM-based commit message review working after the rewrite.
- Bypass once with `rtk proxy <cmd>`; disable globally by removing the hook
  entry from `~/.claude/settings.local.json`.

## Privacy posture

Audited 2026-04-30 against rtk 0.38.0. Full report:
[`docs/archive/audit/rtk-privacy-posture-2026-04-30.md`](../docs/archive/audit/rtk-privacy-posture-2026-04-30.md).

- **Network exfiltration: negligible.** Telemetry is off by default and the
  v0.38.0 binary carries no collection endpoint (literal string: `no telemetry
  endpoint configured`). No posthog/sentry/datadog/amplitude markers — only docs URLs.
- **Local plaintext history**: every command's full text, arguments, and absolute
  project path lands in `~/.local/share/rtk/history.db` (SQLite). Default retention
  is 90 days; this repo ships 14.
- **Threat model**: same shape as `~/.bash_history`. Disk encryption and a
  non-shared account are the operative controls. Avoid passing secrets as CLI
  args — use env vars or `--from-file`.

Re-audit on every `brew upgrade rtk`:

- `strings $(which rtk) | grep -E '^https?://' | grep -v 'github.com\|homebrew'` should stay empty.
- `rtk telemetry status` should report `enabled: no` and `device hash: (no salt file)`.
- Evaluate any new endpoint URL or unfamiliar SaaS marker before continuing use.

Defense-in-depth: export `RTK_TELEMETRY_DISABLED=1` in `~/.bashrc` to override
an accidental opt-in regardless of config. Purge periodically with
`rtk telemetry forget`.
