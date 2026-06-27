# Code Review: triangulate-rt8-vacuous-denial-and-swift-rt6
Date: 2026-06-27
Review round: 1 (initial — converged)

## Changes from Previous Round
Initial review of the uncommitted branch diff (3 experts: functionality / security / testing). Source: review-mining sweep that added RT8 + `check-vacuous-denial.sh`, Swift support in `check-new-code-untested.sh` (RT6), four existing-rule sub-clauses (RT5/R42/R39/R40), and bats tests.

## Functionality Findings
- **F1 (Minor) — FIXED.** RT8 rule row in `common-rules.md` claimed the hook matches the denial status "on a `status`/`statusCode`" receiver, but `DENIAL_STATUS_RE` matches the magic number on any receiver. Corrected the row to "on any receiver" and "the file declares a mutation-verb spy" (the spy check is file-wide, the prior wording "references" implied block-scope).
- **F2 (Minor) — FIXED.** Swift comment claimed test files "under `Tests/`" are recognized, but `TEST_FILE_RE`'s directory clause was lowercase-only (`tests?`), so SwiftPM's capital-`Tests/` layout was missed — a Swift test/helper under `Tests/` not ending `Tests.swift` would be misclassified as production source and could trigger a false RT6 finding. Broadened the clause to `[Tt]ests?` / `[Ss]pecs?` (also unifies the prior `spec|specs` split). Verified no FP regression on the real corpus (0 findings on the reviewed window).
- Verified clean: awk paren-balance walker is structurally identical to the trusted RT4 model; `MUTATION_VERB_RE` correctly kept grep-flavor (no `\y` rewrite); mixed GET+POST block correctly flagged (POST defeats read-only suppression); Swift awk-classifier and sed name-extractor agree on capture group; no leftover `RT1-RT7` strings anywhere.

## Security Findings
- **No findings (Go).** The new hook is a near-byte-identical clone of the trusted `check-race-vacuous-guard.sh`; every safety measure preserved (`set -u`, `mktemp -d` + EXIT trap, `git rev-parse --show-toplevel` + `cd`, ref validation, `IFS= read -r`, `_safe_fname` flattening, quoted `"$f"` everywhere). No shell/command injection (diff content is matched BY constant regexes, never used AS a regex or command); no tmpdir escape. RS4 PII grep: zero hits (synthetic fixtures only). RT8 security-severity guidance sound. No Critical → no escalation.

## Testing Findings
- **T1 (Major) — FIXED.** Read-handler suppression (GET/HEAD/OPTIONS without a mutating verb) was untested — the most regression-prone branch. Added a suppression test AND a negative control (same fixture with POST fires), so the two together pin the GET/POST discrimination in both directions.
- **T2 (Major) — FIXED.** Verb-suffix mock name (`mockBridgeCodeCreate`) — the primary real-world motivation for the regex complexity — was untested. Added a test asserting it fires with `Total findings: 1`.
- **T3 (Major) — FIXED.** The `.deleteMany(` method-call spy shape was untested. Added a test (PUT 429 block with a `.deleteMany(` call, no negative assertion).
- **T4 (Minor) — FIXED.** Multiple-findings-per-file accumulation untested. Added a two-vacuous-block fixture asserting `Total findings: 2`.
- **T5 (Minor / RT7) — FIXED.** The "fires Major" test asserted on `*"RT8"*`, which the header prints on every run (vacuous). Replaced with the discriminating substring `denial-path block at` (unique to a finding line).
- **T6 (Minor) — FIXED.** RT6 Swift "fires" test did not cover `public var`/`public let`. Added `sharedToken`/`buildID` to the fixture with assertions.

## Adjacent Findings
None.

## Quality Warnings
None — Ollama merge unavailable; deduplicated manually. All findings carried file:line evidence and concrete fixes.

## Recurring Issue Check (consolidated)
- R1 (reuse): PASS — the new hook reuses the established RT4-hook structure; the Swift addition reuses the existing per-language classifier/extractor pattern.
- R3 (propagation): PASS — `RT1-RT7`→`RT1-RT8` applied to both sibling sites (common-rules summary line + phase-2-coding scope line); grep confirms no miss. F2 was an R3-class propagation gap (doc claim vs code) — now consistent.
- R20 (doc/comment matches code): F1 + F2 were both doc-vs-code drift; both fixed.
- RT1 (mock-reality): PASS — bats fixtures' assertion shapes match the hook's greps.
- RT6 (new exports tested): the hooks themselves ship with bats coverage (RT6 19 tests, RT8 12 tests).
- RT7 (new gate red-capable): the RT8 hook was mutation-tested against a real corpus (fires on stripped-guard real files, silent on reviewed code); the new bats suppression + negative-control pair proves both branches red-capable.
- Others: N/A (no DB / migrations / UI / async-state / serialization changes — this is a detection-hook + rule-text change set).

## Environment Verification Report
N/A — config-only repo, no Phase 1 environment constraints declared. Verification was empirical: bats suites (RT6 19 + RT8 12, all green), real-corpus FP/TP validation, and `install.sh` sync confirmed.

## Resolution Status
All findings (F1, F2, T1–T6) resolved in the same round. No Critical/Major security findings. Both hooks: bats green, 0 FP on the reviewed corpus window, real TPs on older code. Re-synced to `~/.claude` via `install.sh`. Round 1 converged — no Round 2 needed (no security-boundary code touched; all fixes are doc-precision + test-coverage additions, which are inline-minor and outside the R35 Tier-2 closed list).
