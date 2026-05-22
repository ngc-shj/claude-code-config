# Code Review: resolve-ollama-host-gx10-mdns

Date: 2026-05-22
Review round: 1
Scope: uncommitted changes to `hooks/resolve-ollama-host.sh` and `tests/resolve-ollama-host.bats`
Plan: ad-hoc (no formal plan file — small refactor to replace hardcoded `gx10-a9c0` with mDNS-based dynamic discovery filtered by `gx10-*` prefix, with localhost fallback)

## Changes from Previous Round
Initial review.

## Functionality Findings

### F1 [Major]: Unbounded probe fan-out can stall hook for minutes
- File: `hooks/resolve-ollama-host.sh:41-47`
- Evidence: With a stub avahi emitting 50 gx10-* hosts, the script issues 101 curl probes (50 bare + 50 `.local` + localhost). Each curl uses `--max-time 2`, so worst-case wall time is ~202 s.
- Problem: No upper bound on candidate count. The function is sourced by `commit-msg-check.sh` (runs on every commit) and `pre-review.sh`. A LAN advertising many `gx10-*` Workstation records can stall the user's commit by minutes per 5-min cache window.
- Impact: Hooks appear hung; user may abort and lose commit-msg review.
- Fix: Cap to N=3 via `| head -n 3` in `_discover_gx10_hosts`.

### F2 [Minor]: Duplicate probe when avahi field 7 lacks `.local` suffix
- File: `hooks/resolve-ollama-host.sh:43`
- Evidence: For `h="gx10-bare"`, `${h%.local}` is a no-op, so both candidates collapse to `http://gx10-bare:11434`.
- Impact: Wasted 1-2 s per such host.
- Fix: Branch on suffix presence — emit single candidate when no `.local`.

### F3 [Minor]: Localhost-duplication edge case — DEFERRED (mitigated by F1 cap)

## Security Findings

### S1 [Minor]: SSRF probe to attacker-controlled gx10-* host on shared LAN — DEFERRED
- File: `hooks/resolve-ollama-host.sh:14-16, 47-48`
- Attacker: anyone with mDNS broadcast reach on a network the user joins (cafe Wi-Fi, conference LAN, guest VLAN).
- Attack vector: `avahi-publish -a gx10-evil 192.0.2.1`; hook probes `http://gx10-evil:11434/api/version` and caches it for 5 min.
- Impact: bounded — request body empty, response discarded. Leaks client IP, User-Agent, timing; cache poisons subsequent commits in the window.
- Initially proposed fix: probe `localhost` first. Withdrawn after user confirmed that gx10 is the intended primary inference host at home (probe order is a real behavior change, not a transparent security tightening).
- escalate: false

### S2 [Minor]: mDNS query info disclosure on untrusted networks — DEFERRED
Opt-in env flag is a behavior change beyond this PR's scope. Worst case: passive LAN observer learns "this laptop expects a gx10-* peer" — marginal additional info beyond what avahi-daemon already broadcasts. Likelihood: low (user mostly on home network per `reference_ollama_network.md`). Cost to fix: ~20 LOC + doc + new env contract. Tracked as TODO(resolve-ollama-host-gx10-mdns): consider `OLLAMA_DISCOVER=0` opt-out.

## Testing Findings

### T1 [Major]: Missing-binary branch is silently skipped on most Linux hosts
- File: `tests/resolve-ollama-host.bats:161-177`
- Evidence: `PATH=$BATS_TEST_TMPDIR:/usr/bin:/bin` keeps system `avahi-browse` reachable; the `skip` clause fires on the dev machine and any CI with `avahi-utils` pre-installed.
- Impact: Zero coverage for the `command -v avahi-browse || return 0` short-circuit. Regression (removing the guard) would not fail any test.
- Fix: Shadow `command` with a bash function inside the test that returns 1 for `command -v avahi-browse`, falling through to `builtin command` otherwise. Drop the skip.

### T2 [Minor]: `discovery: only gx10-*` test does not assert absence of extra probes
- File: `tests/resolve-ollama-host.bats:179-188`
- Fix: Add `[ "${#lines[@]}" -eq 3 ]` so a regression broadening the awk filter would fail.

### T3 [Minor]: Multi-host test asserts count but not behavior under partial reachability
- File: `tests/resolve-ollama-host.bats:190-197`
- Fix: Add a companion test setting `CURL_SUCCEED_HOSTS="gx10-bar"` and asserting the resolver returns `http://gx10-bar:11434` — this exercises the interleaved candidate ordering meaningfully.

### T4 [Minor]: Missing coverage for malformed avahi lines and non-`.local` hostnames
- File: `tests/resolve-ollama-host.bats`
- Fix: Add tests feeding (a) an unresolved `+` status line (should be ignored) and (b) a `gx10-bare` hostname without `.local` (validates F2 dedup).

### T5 [Minor]: Mock ignores avahi-browse args — DEFERRED (informational; no current production divergence)

## Adjacent Findings
T4 mentions non-`.local` duplicate behavior also visible in F2 (same root cause; merged into F2 fix).

## Quality Warnings
None.

## Recurring Issue Check

### Functionality expert
- R1 (typo / field index): clean
- R3 (shell quoting): clean
- R6 (cross-platform / macOS): graceful fallback via `command -v`
- R8 (timeout / hang safety): aggregate unbounded — F1
- R12 (set -e / pipefail safety): verified — process-substitution isolation
- R19 (cache race): unchanged, atomic mktemp+mv preserved

### Security expert
- R3 (propagation to tests): clean
- R29 (citation accuracy): RFC 6762/6763 cited; RFC 1035 §2.3.1 LDH constraint marked `citation unverified — please confirm`
- RS1/RS2: N/A
- RS3 (input validation at boundary): acceptable — awk `^gx10-` regex on LDH-constrained avahi output
- RS4 (PII): improvement — hardcoded user-machine name removed from production code
- R34 (sibling files with same class of bug): clean

### Testing expert
- RT1 (vacuous assertions): T2, T3
- RT2 (mock shape mismatch): clean — avahi mock matches awk filter
- RT3 (test isolation): clean — setup() unsets state
- RT4 (skip hides coverage): T1
- RT5 (production not exercised): T1, T3

## Resolution Status

### F1 [Major] Unbounded probe fan-out — Fixed
- Action: Cap `_discover_gx10_hosts` output to 3 hosts via `head -n 3`.
- Modified file: `hooks/resolve-ollama-host.sh`

### F2 [Minor] Duplicate probe on non-`.local` suffix — Fixed
- Action: Branch on suffix presence in the while-read loop.
- Modified file: `hooks/resolve-ollama-host.sh`

### F3 [Minor] Localhost-duplication edge case — Skipped (Accepted)
- **Anti-Deferral check**: acceptable risk
- **Justification**:
  - Worst case: cache stores a `gx10-*` alias that resolves to 127.0.0.1 instead of `localhost`. No security or functional impact — still resolves to the same socket.
  - Likelihood: low — requires `/etc/hosts` to map a `gx10-*` name to 127.0.0.1, which is non-default.
  - Cost to fix: ~5 LOC dedup, but with F1 cap (N≤3) the exposure window is trivial. Mitigated downstream.
- **Orchestrator sign-off**: F1 cap acts as the de-facto mitigation; explicit dedup adds code without measurable benefit.

### S1 [Minor] SSRF on shared LAN — Skipped (Accepted)
- **Anti-Deferral check**: acceptable risk
- **Justification**:
  - Worst case: cache stores an attacker-supplied URL for 5 minutes; hook re-probes the attacker on each commit-msg invocation within that window. No request body, response discarded — leaked data limited to client IP, User-Agent, timing.
  - Likelihood: low — requires (a) user on a shared LAN where a `gx10-*` hostname does not legitimately exist, and (b) attacker can publish mDNS records on that LAN. User's primary environment is home (single-tenant) and work (SSH tunnel to localhost, no LAN mDNS dependency).
  - Cost to fix: low LOC-wise, but probe-order reordering is a behavioral change that demotes the user's gx10 box (primary GPU inference host) from default to fallback. Verified with the user; reordering rejected.
- **Orchestrator sign-off**: user-approved deferral. Re-evaluate if user adds an opt-out env var (`OLLAMA_DISCOVER=0`) in a future PR.

### S2 [Minor] mDNS info disclosure — Skipped (Accepted)
- **Anti-Deferral check**: acceptable risk
- **Justification**:
  - Worst case: passive LAN observer learns the client expects a `gx10-*` peer.
  - Likelihood: low — user is primarily on home network per memory; mDNS broadcast is already implicit in `avahi-daemon` presence.
  - Cost to fix: ~20 LOC + new env contract (`OLLAMA_DISCOVER=0`) + docs. Behavior change beyond scope of this PR.
- **Orchestrator sign-off**: tracked as TODO(resolve-ollama-host-gx10-mdns) for future hardening.

### T1 [Major] Missing-binary branch silently skipped — Fixed
- Action: Replace skip-based test with `command()` shell-function override that deterministically forces the missing-binary branch.
- Modified file: `tests/resolve-ollama-host.bats`

### T2 [Minor] Filter test missing length assertion — Fixed
- Action: Add `[ "${#lines[@]}" -eq 3 ]`.
- Modified file: `tests/resolve-ollama-host.bats`

### T3 [Minor] Multi-host ordering not exercised — Fixed
- Action: Add companion test `discovery: second discovered host wins when first is unreachable`.
- Modified file: `tests/resolve-ollama-host.bats`

### T4 [Minor] Malformed / non-`.local` coverage gap — Fixed
- Action: Add tests for unresolved `+` avahi lines and for `gx10-bare` (no `.local`) hostnames.
- Modified file: `tests/resolve-ollama-host.bats`

### T5 [Minor] Mock ignores avahi-browse args — Skipped (Accepted)
- **Anti-Deferral check**: acceptable risk
- **Justification**:
  - Worst case: future production change adds an avahi-browse flag the mock does not validate; mock would silently emit unchanged output.
  - Likelihood: low — no immediate refactor planned.
  - Cost to fix: ~10 LOC of arg-aware mock logic; speculative until a production change requires it.
- **Orchestrator sign-off**: informational, no current divergence.
