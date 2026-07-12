# Code Review: retro-artifacts-fold
Date: 2026-07-12
Review rounds: 3 (converged — all findings resolved)

Scope: retrospect artifacts-mining fold — new rule R44, extensions to R21/R38/R40/R41,
cross-ports (test-gen obligation 13, retrospect folding.md gates note, phase-2
exit-status note), retrospective doc `docs/archive/audit/retro-artifacts-lessons-2026-07-12.md`.
Reviewed as the uncommitted working tree vs main by three expert sub-agents
(functionality / security / testing). Ollama seeds: all three returned `No findings`
(sentinel intact); experts performed independent full checks per the empty-seed rule.

## Round 1 — initial review

| ID | Expert | Severity | Finding | Resolution |
|----|--------|----------|---------|------------|
| F1 / F-T2 | Func + Test (converged) | Major | R21 carve-out intro said "Two mandatory controls, both required" while enumerating three after the fold added control 3 | Fixed: "Three mandatory controls, all required:" |
| Sec F-1 | Security | Major | New R38 Part 2 item 6 fail-direction ("malformed timer value → expired/due now") lexically covered access-restrictive timers (lockout / rate-limit / re-auth grace) where that direction is fail-open — citable against R43's interval class | Fixed: scope sentence restricts the direction to visibility/suppression timers; explicit INVERSION for access-restriction timers (fail toward the restrictive state); mirrored in the R38 row pointer and the retrospective doc lesson 6 |
| F-T1 | Testing | Major | Self-contained-rules enumeration (common-rules.md pointer sentence) was an unguarded sync point — empirically revert-proven: linter stayed green without ", and R44" | Fixed by removing the sync obligation: sentence now reads "All other rules are self-contained in the table row above." |
| F2 | Func | Minor | R44 template "Checked" wording narrower than the rule's compliant patterns | Fixed: "…from the gate's own exit status (unpiped, or captured before any filter)" |
| F3 | Func | Minor | R38 row gave no cue that the malformed-timer facet lives in Extended obligations | Fixed: Reviewer-action pointer appended to the row |

Round 1 clean-pass evidence (recorded by the experts): no unescaped pipe in the new R44
table row (field count matches sibling rows); shell/git technical claims verified
factually correct; no stale `R1-R43` outside archives; RS4 sweep over all added lines
clean (no emails, handles, IPs, host/user paths, URLs, external repo names); all fold
edits additive (no obligation weakened); the one imported excerpt quoted inertly.

## Round 2 — fix verification + incremental

All Round 1 findings verified RESOLVED by all three experts (fixes re-read from files,
not from the fix description). New findings, all Minor:

| ID | Expert | Severity | Finding | Resolution |
|----|--------|----------|---------|------------|
| F-T3 | Testing | Minor | Residual "full procedures on …" ID list is the same unguarded-sync-point class (lower frequency, confusion-only) | Fixed: check 6 added to hooks/check-rule-sync.sh (Extended-obligations header set vs pointer-sentence set), with drift + pass bats fixtures |
| F-T4 | Testing | Minor | R38 item 6 restrictive branch stated the fail direction but omitted the symmetric fixture obligation | Fixed: restriction-holds fixture obligation appended |
| F-N1 | Func | Minor | retrospect folding.md sync-map still instructed updating the deleted enumeration line | Fixed: instruction now points at the "full procedures on …" pointer sentence and notes the check-6 guard |

Security Round 2: F-1 resolved with direction-correctness analysis (state-based
"restrictive" phrasing handles lockout / rate-limit / grace uniformly); no obligation
weakened by any fix; line-334 rewording verified lossless against the actual
Extended-obligations header set; no data leakage in fix-round + lines. No new findings.

## Round 3 — focused verification (testing expert)

Scope note: Round 2's new findings were all Minor; the F-T4/F-N1 fixes are inline-minor
wording within prior fix scope with no security-boundary touch (tightening-only
conditions), but the F-T3 fix changes hook behavior, so a Round 3 was run with the
testing expert (owner perspective of the linter/RT7 surface). Functionality/security
Round 3 skipped under the tightening-only rationale for their surfaces.

- F-T3 RESOLVED: check-6 logic reviewed; RT7 red-proof beyond the shipped fixtures on
  scratch copies (pointer-side removal of ", R40" → exit 1 with check-6 drift;
  header-side injection of a fake in-range header → exit 1, provably check 6 not
  check 5); bats 17/17 for the linter suite; live repo green. Both new bats tests
  assert the specific drift message, not just exit status.
- F-T4 / F-N1 RESOLVED (text verified concrete and accurate).
- F-T5 (Info, non-blocking): check-6 awk scan ran to EOF; a future bold `**Rn:**` line
  after the section would be miscounted (fail-safe direction — false DRIFT).
  Applied directly per tightening-only (inline change, fail-safe): `/^## /{flag=0}`
  terminator added; section verifiably ends at the next h2 heading.

## Recurring Issue Check (Round 1, per expert — summarized status)

### Functionality expert
- R2/R3 (range propagation): Checked — R44 bump propagated to all range-string sites; no stale R1-R43 outside archives. R18-analog: Finding F1. R20: Checked — no mangled adjacent text. R29: Checked — pipeline exit-status, PIPESTATUS/pipefail, checkout/restore claims factually correct. R30: Checked — no autolink candidates in the new doc. R42: Checked — sync-point class derived by repo-wide range-string grep, not from the touched list. R44: Checked — rule-sync gate observed unpiped (exit 0). All other R rules: N/A (markdown-only diff).

### Security expert
- RS1: Checked — no secrets. RS2/RS3/RS6: N/A — no runtime boundary. RS4: Checked — multi-pattern grep over all added lines, zero hits. RS5: Checked — mined content treated as data; single excerpt quoted inertly with untrusted labeling. R21: Checked — additive edit only. R22: Checked — adversarial-consumer reading produced F-1. R31: Checked — no destructive ops; quoted literals verified non-matching against the deny-hook regexes. R43: Checked — every edit additive vs pre-diff text. R44: Checked — no piped gate status judged. All other R rules: N/A.

### Testing expert
- R3: Checked — one propagation gap (F-T1), one count miss (F-T2). RT2: Checked — new obligations concretely testable. RT5: Checked — bats live-repo test invokes the real linter. RT7: Checked — every guarded sync edit revert-tested red (3 empirical samples); unguarded member → F-T1; R44's deliberate no-hook status assessed sound (diff-based hooks structurally cannot observe gate invocation; a PreToolUse pipe-pattern hook fails the noise test). RT9: Checked — edits target repo source, not installed copies. RT1/RT3/RT4/RT6/RT8: N/A. R42: Checked — sync-point class derived from the range-string primitive; A\B empty after fixes.

## Environment Verification Report
N/A — no environment constraints declared (config-only repo). Gates verified-local:
`bash hooks/check-rule-sync.sh` exit 0 (`OK: R1-R44 / RS1-RS6 / RT1-RT9`), `bats tests/`
exit 0 (726/726), both observed unpiped per R44.

## Resolution Status

### F1/F-T2 [Major] R21 control count
- Action: intro line updated to three controls
- Modified file: skills/triangulate/common-rules.md (destructive verification carve-out intro)

### Sec F-1 [Major] R38 item 6 fail-direction scope
- Action: visibility-vs-access-restriction scope split + inversion added to item 6, row pointer, and retrospective doc lesson 6
- Modified files: skills/triangulate/common-rules.md; docs/archive/audit/retro-artifacts-lessons-2026-07-12.md

### F-T1 [Major] Unguarded self-contained enumeration
- Action: enumeration removed ("All other rules are self-contained in the table row above.")
- Modified file: skills/triangulate/common-rules.md

### F2/F3 [Minor] Template wording / row pointer
- Action: template Checked-slot broadened; R38 row Reviewer-action pointer appended
- Modified file: skills/triangulate/common-rules.md

### F-T3 [Minor] Residual pointer list unguarded
- Action: check 6 added (header set vs pointer set, conditional skip for minimal fixtures), drift fixture + range-form pass fixture added; red-proven per RT7 (shipped fixture + two live-shaped scratch mutations)
- Modified files: hooks/check-rule-sync.sh; tests/check-rule-sync.bats

### F-T4 [Minor] Restrictive-branch fixture obligation
- Action: symmetric restriction-holds fixture obligation appended to R38 item 6
- Modified file: skills/triangulate/common-rules.md

### F-N1 [Minor] folding.md sync-map staleness
- Action: instruction rewritten to target the guarded pointer sentence
- Modified file: skills/retrospect/folding.md

### F-T5 [Info] check-6 awk EOF scan
- Action: `/^## /` terminator added (applied directly — tightening-only, fail-safe direction)
- Modified file: hooks/check-rule-sync.sh

## Tightening-only skip — Round 3
Findings applied directly (no Round 4 review):
- [F-T5] [Info] check-6 awk section terminator — hooks/check-rule-sync.sh — applied; gates re-run green (rule-sync exit 0, bats 726/726)
Justification: finding scoped within Round 2 fix range, inline and fail-safe (false-DRIFT direction only), no security-boundary touch.
