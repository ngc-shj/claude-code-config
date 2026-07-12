# Code Review: retrospect-mining-system

Date: 2026-07-12
Review round: 1 (implementation diff `9b211bf...HEAD`)
Result: CONVERGED — 10 findings, all resolved with red-capable regression tests.

## Reviewers

Three expert sub-agents (functionality, security, testing) plus a user security pass over
`origin/main...HEAD` + uncommitted diff. Full suite: **724 bats green**.

## Findings and resolutions

| ID | Severity | Area | Summary | Resolution |
|----|----------|------|---------|------------|
| S1 / F2 | Major | security+func | Two-hop symlink chain escapes repo containment | Full-chain resolution (≤40 hops); mutation-verified |
| — | High | security (user) | Artifacts raw text sent to remote LLM ungated | Shared `_raw_llm_egress_ok` gate + `allow_remote_llm`; mutation-verified |
| F1 | Major | func | Correction-marker filter dead vs array-shaped content | Content normalized before `test` |
| T1 | Major | testing | S3 loopback-gate negative tests vacuous | Isolated S3 (reachable remote, no consent); mutation-verified |
| F3 | Minor | func | Malformed timestamp poisons all-source `due` | Per-source try/catch |
| — | Medium | func (user) | `catch $now+1` silences a bad-snooze source forever | Corrected to `catch $now` (expired) |
| F4 | Minor | func | github comment bodies shredded per-line | `@base64` per comment |
| S2 | Minor | security | scrub misses IPv6 | IPv6 pass added |
| T2 | Minor | testing | HIGH-WATER-spoof test omits contamination assert | `.high_water` assertion added |
| T3 | Minor | testing | count==limit asserts only warning | 200-candidate assertion added |
| T4 | Minor | testing | flip-fixture / clobber-prone `$output` reuse | `$DOC`/`$ERR`/`$due` saves |

## Verified clean (adversarial + code, security expert)

Scrub allowlist scoping (email/IP/home/secret still fire inside allowlisted `~/.claude/…`
tokens); JSON injection (filenames/PR-titles jq-encoded, `--json` sole machine interface);
transcripts privacy (raw content never on stdout/stderr, deferred=counts-only cursor
preserved); egress gate rejects `127.0.0.1.evil.com` / `localhost.evil.com` / link-local;
trust boundary (regular+non-symlink+user-owned, atomic writes, corrupt quarantine, single
owner — grep-confirmed no config/state reads outside retro-state.sh); closed source set at
the single owner + redundant depth; `_validate_hw` single chokepoint for both writers;
scout curl hardened; read-only mining sub-agents with git-clean assertion.

## Deviation log

All impl-stage fixes recorded in `retrospect-mining-system-deviation.md` (D1–D7).

## Recurring Issue Check

All three experts ran the full R1-R43 / RS1-RS6 / RT1-RT9 checklist. Post-fix state: R42
(scrub-consumer set + high_water-writer set + egress-gate set all complete and shared),
RS4 (deterministic scrub + egress gate before any committed artifact), RT7/RT8 (every new
guard — containment, egress, S3, drift classes — proven red-capable, security gates
mutation-verified). No unresolved findings.
