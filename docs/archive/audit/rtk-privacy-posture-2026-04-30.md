# RTK (Rust Token Killer) — Privacy Posture Audit
Date: 2026-04-30
Subject: rtk 0.38.0 (homebrew install)
Auditor: trial-integration session, this repo
Trigger: PR #40 followup — analytics privacy posture was deferred at merge time

## Scope

Investigate what data RTK persists, where, for how long, and whether anything is transmitted off-machine.

## Method

1. Filesystem scan for `rtk`-owned paths under `$HOME`.
2. SQLite inspection of any database files (schema + sample rows).
3. Static-string analysis of the `rtk` binary for HTTP endpoints, telemetry markers, and SaaS integrations.
4. `rtk telemetry status` and `rtk telemetry --help` review.
5. Cross-check against the documented data controller (`contact@rtk-ai.app`, `https://github.com/rtk-ai/rtk/blob/main/docs/TELEMETRY.md`).

No dynamic instrumentation (strace, packet capture) was used; this is a static + config-level audit only.

## Findings

### F1. Local data store inventory

| Path | Size | Content |
|---|---:|---|
| `~/.config/rtk/config.toml` | ~1 KB | Settings (tracking on, telemetry off, retention 90d). |
| `~/.config/rtk/filters.toml` | <1 KB | User filter overrides (template comment only by default). |
| `~/.local/share/rtk/.hook_warn_last` | 0 B | Empty marker. |
| `~/.local/share/rtk/history.db` | ~32 KB | SQLite — command tracking. **Most data lives here.** |

Total ~33 KB of state at audit time (after a small trial workload).

### F2. `history.db` schema and data sensitivity

```sql
CREATE TABLE commands (
  id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  original_cmd TEXT NOT NULL,    -- full command line, plain text
  rtk_cmd TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  saved_tokens INTEGER NOT NULL,
  savings_pct REAL NOT NULL,
  exec_time_ms INTEGER DEFAULT 0,
  project_path TEXT DEFAULT ''   -- absolute filesystem path
);

CREATE TABLE parse_failures (
  id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  raw_command TEXT NOT NULL,
  error_message TEXT NOT NULL,
  fallback_succeeded INTEGER NOT NULL DEFAULT 0
);
```

**Threat-model note**: `original_cmd` and `raw_command` are the **complete command line, including arguments**. Risk surfaces:

- Any secret passed as a CLI argument is captured (e.g., `aws ... --secret-access-key abc`, `curl -H 'Authorization: Bearer xyz'`). This is the same threat shape as `~/.bash_history`.
- Regex / search patterns leak content of interest (e.g., a grep for an email-format regex run against a docs directory was captured verbatim).
- `project_path` aggregates across all projects RTK was run in. A single audit reads identifies the operator's project portfolio.
- 90-day default retention amplifies the window of exposure.

The bar to read this data is local disk access — equivalent to `~/.bash_history`. Disk encryption + non-shared user account remain the operative controls.

### F3. Telemetry posture (v0.38.0)

`rtk telemetry status` output at audit time:

```
consent:       no
consent date:  <iso8601>
enabled:       no
device hash:   (no salt file)

Data controller: RTK AI Labs, contact@rtk-ai.app
Details: https://github.com/rtk-ai/rtk/blob/main/docs/TELEMETRY.md
```

Configuration default in `~/.config/rtk/config.toml`:

```toml
[telemetry]
enabled = false
consent_given = false
```

**Critical finding**: the binary contains the literal string `"no telemetry endpoint configured"`. Static-string scan of the binary turned up no remote analytics endpoints (no posthog, sentry, datadog, amplitude, or other SaaS markers). The only HTTPS URLs in the binary are documentation links (github.com docs) and unrelated content (homebrew bottles, clap-rs bug tracker referenced by error messages).

**Conclusion**: at v0.38.0, even if a user explicitly opts in via `rtk telemetry enable`, no collection endpoint is configured — there is nowhere for data to go. Future versions could add an endpoint; this must be re-checked on every RTK upgrade.

If telemetry is later enabled and an endpoint is configured, the binary's own help text states it would collect: `command names (not arguments), token savings, OS, version`. Frequency: once per day. Anonymous via a device-salt mechanism. GDPR-compliance tooling exists: `rtk telemetry forget` (delete local salt + history), `RTK_TELEMETRY_DISABLED=1` env var (override regardless of config).

### F4. Network behavior

- No phone-home detected on install (homebrew bottle download is the install-time network call; runtime calls are zero on benign commands).
- The hook runtime (`rtk hook claude`) reads stdin, writes stdout, queries `history.db` — no observed outbound network from string analysis.
- Disclaimer: this is static analysis. A dynamic check (`strace -e trace=connect rtk hook claude < input.json`) at upgrade time would tighten this.

### F5. Cross-project data mixing

`history.db` is a single file at `~/.local/share/rtk/history.db` and aggregates commands run from any project directory. The `project_path` column records the absolute working-directory path at execution time. Side effect: an audit reads every project the user has worked in via RTK, ordered by recency.

### F6. Uninstall residue

`brew uninstall rtk` removes the binary but does NOT remove `~/.config/rtk/` or `~/.local/share/rtk/`. The user must manually `rm -rf` those (or run `rtk telemetry forget` before uninstall, which clears the DB but not the config dir).

## Risk assessment summary

| Risk | Severity | Notes |
|---|:---:|---|
| Network exfiltration (current version) | 🟢 NEGLIGIBLE | No endpoint configured, telemetry off, no remote URLs in binary. |
| Local plaintext command history | 🟡 LOW | Equivalent to `~/.bash_history`. 90-day retention. |
| Cross-project visibility in single DB | 🟡 LOW | Aggregated locally. No exfil but visible to any process reading the file. |
| **Secret-in-CLI-arg capture** | 🟠 MEDIUM | Any secret on CLI lands in `history.db`. Bash-history-class problem. |
| Persistence after uninstall | 🟢 LOW | Two directories left behind unless manually removed. |
| Re-evaluation on RTK upgrade | 🟡 LOW | Endpoint may be added in a future version. Rerun the strings/telemetry-status check at each `brew upgrade rtk`. |

## Mitigations applied in this PR

1. **Shorten retention from 90 days to 14 days** in `~/.config/rtk/config.toml`. Trade-off: `rtk gain` analytics become less complete, but exposure window drops to ~1 sprint. The trial workload showed ~33 KB of state in two days; 14 days is a modest cap.
2. **Document the audit findings** at `docs/archive/audit/rtk-privacy-posture-2026-04-30.md` (this file).
3. **Update `CLAUDE.md`** RTK section with the audit summary + re-audit triggers + mitigation pointers.

## Recommended ongoing hygiene

1. **Avoid passing secrets as CLI args**. Use `--from-env`, `--from-file`, or a credential helper instead. (Same advice as for `~/.bash_history`.)
2. **Backup-exclude** `~/.local/share/rtk/history.db` if using auto-backup tools that ship to off-machine destinations.
3. **Re-audit on every `brew upgrade rtk`**:
   - `strings $(which rtk) | grep -E '^https?://' | grep -v 'github.com\|homebrew' ` should remain empty.
   - `rtk telemetry status` should show `enabled: no`, `device hash: (no salt file)` unless intentionally enabled.
   - If a new endpoint surfaces, evaluate before continuing use.
4. **Defense in depth**: export `RTK_TELEMETRY_DISABLED=1` in `~/.bashrc` so even an accidental opt-in is overridden.
5. **Periodic purge**: `rtk telemetry forget` to clear the DB at session end if working on highly sensitive material.

## Decision

Adoption confirmed for this repo's profile (single-user dev machine, encrypted disk presumed, secrets handled via env / file references). The `history.db` plaintext capture is the only material risk and is bounded by retention + disk-access posture, both addressable.

If the threat model changes (shared machine, sensitive customer data on CLI, strict compliance regime), re-evaluate.
