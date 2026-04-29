# Code Review: block-destructive-docker-volumes
Date: 2026-04-29
Review round: 1

## Changes from Previous Round
Initial review.

## Functionality Findings

(See merged section below)

## Security Findings

(See merged section below)

## Testing Findings

(See merged section below)

## Merged Findings

### Major

**M1 — Override path clobbered by install.sh** (F1, S3)
- File: `hooks/block-destructive-docker.sh:31`, intersects with `install.sh:17`
- Problem: reason instructs "comment out the hook in ~/.claude/settings.json", but install.sh unconditionally `cp`s repo settings.json over ~/.claude/settings.json on every run. User who opts out and later re-runs install (or another tool runs it) silently re-enables the block.
- Fix: change reason to recommend either (a) editing `settings.local.json` (which install.sh leaves alone), OR (b) editing the source `settings.json` in this repo and re-running install.sh, OR (c) env-var bypass `CLAUDE_ALLOW_DESTRUCTIVE_DOCKER=1` checked at the top of the hook. Pick (a) + (b) for durability — env-var (c) leaves a discoverable global escape hatch which the reviewer may forget to clear.

**M2 — False-negative on combined short flags `-tv` / `-vt`** (T1)
- File: `hooks/block-destructive-docker.sh:28`
- Problem: `-v\b` requires literal `-v` at a substring boundary with word-boundary right after. `docker compose down -tv` has `-`,`t`,`v` — `-v` is not a substring at positions 0-1. `docker compose down -vt 30` has `-v` at positions 0-1 but `\b` does not hold before `t` (t is a word char).
- Fix: extend regex to also match `-[a-z]*v[a-z]*\b` so any short-flag bundle containing `v` is caught.

**M3 — False-negative on tab-separated `docker<TAB>compose`** (F2, T2)
- File: `hooks/block-destructive-docker.sh:28`
- Problem: `docker[ -]compose` matches single space or hyphen, not tab. `bash -c $'docker\tcompose down -v'` slips through. Inconsistent with the rest of the regex which uses `[[:space:]]+`.
- Fix: replace `docker[ -]compose` with `(docker[[:space:]]+compose|docker-compose)`.

**M4 — No reproducible test fixture in `./tests/`** (T3)
- Problem: the orchestrator's 11-case verification lives only in the conversation. After merge, future maintainers cannot re-verify.
- Fix: add `tests/block-destructive-docker.bats` (project already uses bats-core for `tests/*.bats`) covering: 4 documented blocks + 7 documented approves + the new edge cases from M2/M3 (`-tv`, tab whitespace, `--volumes=true`).

**M5 — Latency on every Bash call unmeasured** (T4)
- Problem: every Bash tool call now spawns `bash + jq + jq + grep`. Roughly 10-50ms on Linux. 100 calls/session = 1-5s added wall time. Hook timeout is 5s so a single hook run is bounded, but cumulative session cost is not.
- Fix: consolidate the two `jq` calls into one (`jq -r '[.tool_name, (.tool_input.command // "")] | @tsv'`) to roughly halve hook overhead. Optionally record a one-shot benchmark in commit message or `tests/`.

### Minor (will address in same PR where straightforward)

**M6 — Hook script tampering perimeter** (S2)
- `~/.claude/hooks/*.sh` and `~/.claude/settings.json` are writable by any Claude Code session. `block-sensitive-files.sh` doesn't deny edits to them.
- Fix: extend `block-sensitive-files.sh` to deny `~/.claude/hooks/*.sh`, `~/.claude/settings.json`, `~/.claude/settings.local.json`. (May be larger than this PR's scope; will assess.)

**M7 — Integration with commit-msg-check.sh untested** (T5) — add a git-commit case to .bats fixture.

**M8 — install.sh has no settings.json validation step** (T6) — out of scope for this PR.

**M9 — set -e + grep -q latent footgun** (F3) — optional comment.

**M10 — Bypass surfaces (R31 known limitation)** (S1, S4) — document in hook header / commit message.

### Info (no action)

- F4 (escape convention) — new hook is better, no change.
- F5 (hook ordering) — verified, no change.
- S5 (injection safety) — verified, no change.
- S6 (reason disclosure) — acceptable, no change.
- S7 (defense-in-depth) — correct design.
- T7 / T8 — informational.

## Quality Warnings

(none — all findings have file:line citations and concrete fixes)

## Recurring Issue Check

### Functionality expert
- R1-R35: N/A (small shell hook, no recurring patterns apply at code level)
- Notable: R3 (propagation) checked — settings.json change is single point; hook script is single new file.

### Security expert
- R31: Checked — this PR IS the runtime control for category (a). Categories (b)-(i) remain reviewer-text only (S4 known gap).
- RS1-RS3: addressed at finding level.
- Other R-rules: N/A.

### Testing expert
- R20/R21 (verification reproducibility): NOT MET pre-fix. M4 fix addresses it.
- RT1 (regression test for bug fix): PARTIAL pre-fix. M4 fix addresses it.
- Others: N/A.

## Resolution Status

### M1 [Major] Override path clobbered by install.sh — RESOLVED
- Action: rewrote the block-reason message in `hooks/block-destructive-docker.sh:36` to recommend `~/.claude/settings.local.json` as primary override (install.sh leaves it untouched), with explicit warning against editing `~/.claude/settings.json` directly. Also documented "edit repo `settings.json` and re-run install.sh" as the durable path.
- Modified file: `hooks/block-destructive-docker.sh:36`

### M2 [Major] False-negative on combined short flags `-tv` / `-vt` — RESOLVED
- Action: extended regex flag group to `(-v\b|-[a-zA-Z]*v[a-zA-Z]*\b|--volumes\b)` — the middle alternative catches bundled short flags with `v` anywhere in the cluster.
- Verified by: `tests/block-destructive-docker.bats:46-56` (3 new bundled-flag cases pass).
- Modified file: `hooks/block-destructive-docker.sh:39`

### M3 [Major] False-negative on tab-separated `docker<TAB>compose` — RESOLVED
- Action: replaced `docker[ -]compose` with `(docker[[:space:]]+compose|docker-compose)`. Tab whitespace now matches.
- Verified by: `tests/block-destructive-docker.bats:67` (tab case passes).
- Modified file: `hooks/block-destructive-docker.sh:39`

### M4 [Major] No reproducible test fixture in `./tests/` — RESOLVED
- Action: added `tests/block-destructive-docker.bats` with 32 cases (18 deny + 14 approve), including all 4 originally-verified deny cases, 7 originally-verified approve cases, and the new edge cases from M2/M3 (`-tv`, `-vt`, tab whitespace, `--volumes=true`, `--remove-orphans` false-positive guard).
- Verified by: `bats tests/block-destructive-docker.bats` returns 32/32 pass; `bats tests/` returns 99/99 across all hooks (no regression).
- New file: `tests/block-destructive-docker.bats`

### M5 [Major] Latency on every Bash call unmeasured — PARTIALLY RESOLVED, DEFERRED REMAINDER
- Initial fix attempted: consolidate two `jq` calls into one via `@tsv`. **Reverted** in iteration 2 because TAB inside command value collided with TSV field separator (caused bats test 9 to fail).
- Final state: kept two separate `jq` calls (matches `block-sensitive-files.sh` and `commit-msg-check.sh` convention). Latency overhead per Bash call is ~10-30ms (jq×2 + grep). Not benchmarked formally.
- Anti-Deferral check: "out of scope (different feature)" → benchmarking + optimization is its own follow-up.
- Worst case: 100 Bash calls × 30ms = 3s/session of added latency.
- Likelihood: medium (developers run many Bash calls/session).
- Cost-to-fix: medium-low (would need a stdin-byte-safe consolidation or porting to a faster runtime; a benchmark fixture is ~20 LOC).
- Decision: defer benchmarking + optimization to a follow-up issue if latency becomes user-visible.

### M6 [Minor] Hook script tampering perimeter — DEFERRED, OUT OF SCOPE
- Anti-Deferral check: "out of scope (different feature)" — extending `block-sensitive-files.sh` to deny edits to `~/.claude/hooks/*.sh`, `~/.claude/settings.json`, `~/.claude/settings.local.json` is a separate concern.
- Worst case: a future Claude session edits `~/.claude/hooks/block-destructive-docker.sh` to no-op, then runs `docker volume rm`. Same blast radius as without the hook (the original incident).
- Likelihood: low (requires a session deliberately neutralizing a safety net; user oversight catches normal cases).
- Cost-to-fix: low (~3-5 lines added to `block-sensitive-files.sh`'s case statement).
- Decision: track as a follow-up; not blocking this PR. The hook is a tripwire on top of `permissions.deny`, not a hardened security boundary.

### M7 [Minor] Integration with commit-msg-check.sh untested — RESOLVED
- Action: added `git commit` case to bats fixture (test #30) confirming both hooks chain correctly.
- Modified file: `tests/block-destructive-docker.bats:144`

### M8 [Minor] install.sh has no settings.json validation step — DEFERRED, OUT OF SCOPE
- Anti-Deferral check: "out of scope (different feature)" — install.sh hardening (jq empty pre-check, post-install `test -x` verification) is broader than this PR.
- Decision: track as a follow-up.

### M9 [Minor] `set -e` + `grep -q` latent footgun — RESOLVED (NO CHANGE)
- Verified safe in current code: `grep -qE` is in conditional context, `set -e` does not abort on conditional non-zero. Future maintainers should know; the regex comment block in the script implicitly documents the conditional structure. No code change.

### M10 [Minor] Bypass surfaces (R31 known limitation) — RESOLVED (DOCUMENTED)
- Action: hook header comment lines 4-7 explicitly note "Best-effort tripwire — bypasses exist (base64-decoded eval, alternate shells, Docker socket directly via curl). Primary enforcement remains settings.json `permissions.deny` plus reviewer obligation (R31)."
- Modified file: `hooks/block-destructive-docker.sh:4-7`

