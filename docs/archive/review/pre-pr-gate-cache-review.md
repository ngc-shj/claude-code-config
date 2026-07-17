# Plan Review: pre-pr-gate-cache

Date: 2026-07-16
Review round: 1-5 (consolidated; rounds 2-5 appended below)

## Changes from Previous Round

Initial review. (Pre-review pass: local LLM pre-screening raised one Major —
rejected as factually wrong (`git diff HEAD` IS worktree-vs-HEAD and covers
staged + unstaged) — and two Minors, both applied before expert review:
`LC_ALL=C git diff --no-ext-diff HEAD` normalization and an explicit
untracked-file hash pipeline.)

## Functionality Findings

**F1 — Major — Direct-mode (`run`) silently no-ops on repo-root resolution
failure, with no distinct signal from a real pass**
- Problem: C4's exit-status contract had no bucket for "repo root could not
  be resolved" — it fell through the same path as "no scripts/pre-pr.sh,
  no-op" and exited 0. Hook mode approving on unresolved root is correct (it
  is a safety net around an unrelated tool call); direct mode IS the gate
  execution Phase 2-4/3-7 rely on, so a silent exit-0 reads as "gate passed"
  at call sites that check only exit status.
- Impact: misconfigured invocation environment → phases report success while
  the real gate never ran.
- Recommended action: distinct stderr note + exit 2. Add bats case.
- **Resolution: Fixed in plan.** C4 now specifies stderr
  `could not resolve repo root — gate not run` + exit 2; C6 gained T15.

**F2 — Minor [Adjacent → Testing] — no C6 case for direct-mode
repo-root-resolution failure**
- **Resolution: Fixed in plan.** T15 added.

## Security Findings

**F1 — Minor — Cache-file trust check omitted ownership validation present in
repo precedent (retro-state.sh `_trusted_file`)**
- **Resolution: Fixed in plan.** C2 read validation now requires `-O`
  (current-user ownership); foreign-owned file = miss. T8c documents the
  bats testability limit (foreign-owned fixture needs root).

**F2 — Minor — PRE_PR_CACHE_TTL has no upper bound**
- **Resolution: Fixed in plan.** Effective TTL capped at 86400 s (24 h).

**F3 — Minor — Fingerprint blind spot on permission-only (mode-bit) changes
not called out as security-relevant**
- **Resolution: Fixed in plan.** Considerations prose now names
  permission-bit changes to `scripts/pre-pr.sh` / gate-inspected files, and
  notes the capped TTL bounds the window to ≤24 h.

**F4 — Minor [Adjacent → Functionality] — same-operator trust assumption
across parallel invocations was implicit**
- **Resolution: Fixed in plan.** Stated explicitly under Considerations.

## Testing Findings

**F1 — Minor — T8 bundled malformed-cache and symlinked-cache fixtures into
one matrix row**
- **Resolution: Fixed in plan.** Split into T8a (malformed) / T8b (symlink);
  T8c added to make the ownership-check testability gap explicit rather than
  silent.

**F2 — Minor — no row red-proving cache_record's silent no-op when the cache
path becomes unresolvable mid-run**
- **Resolution: Fixed in plan.** T16 added (passing fixture deletes `.git`
  during its run → exit 0, nothing recorded, no crash). Deterministic and
  cheap — within the 30-minute rule, so applied rather than deferred.

**F3 — Minor — N3 stderr breadcrumb had no acceptance test**
- **Resolution: Fixed in plan.** T1 now also asserts the breadcrumb
  substring, mirroring the existing SKIP_PRE_PR_GATE breadcrumb test.

**F4 — Minor [Adjacent → Functionality] — C5 phase-doc migration had no bats
acceptance row despite the existing doc-drift test precedent**
- **Resolution: Fixed in plan.** T17 added (wrapper invocation present, raw
  `bash scripts/pre-pr.sh` absent from executable snippets); C5 documents
  that the existing "skill docs reference scripts/pre-pr.sh literally" test
  stays green via remaining prose references.

## Adjacent Findings

- Functionality F2 → Testing (test-matrix gap): accepted by orchestrator,
  T15 added.
- Security F4 → Functionality (implicit trust assumption): accepted, prose
  added.
- Testing F4 → Functionality (C5 acceptance row): accepted, T17 added.

## Quality Warnings

None. merge-findings quality gate reported no VAGUE / NO-EVIDENCE /
UNTESTED-CLAIM flags.

## Recurring Issue Check

### Functionality expert
- R1: checked-ok — build-codebase-fingerprint.sh solves an unrelated problem
  (symbol-usage frequency, not content-addressed state); retro-state.sh
  atomic-write precedent correctly mirrored; no reusable fingerprint/cache
  helper exists.
- R2-R24: n/a
- R25: checked-ok — cache read/write pair symmetric by construction (same
  functions, both entry modes)
- R26-R40: n/a
- R41: checked-ok — `run` capability fully backed; F1 was a failure-branch
  gap, not an unbacked capability
- R42: checked-ok — member-set recomputed independently
  (`rg -n 'pre-pr\.sh' hooks/ skills/ tests/`): exactly the 3 execution
  sites in C5; phase-2:66 confirmed grep-not-exec
- R43: n/a — cache only narrows re-execution
- R44: checked-ok — gate unpiped in both modes

### Security expert
- R1-R16: n/a
- R17: checked-ok — cache functions have exactly one call path per mode
- R18-R30: n/a
- R31: checked-ok — cache writes non-destructive, atomic, .git-scoped
- R32-R37: n/a
- R38: checked-ok — N1 fail-safe direction invariant-tagged (I1-1, I2-2)
- R39-R41: n/a
- R42: checked-ok — member-set cross-check found no omitted execution member
- R43: checked-ok — cache narrows re-execution, not acceptance criteria;
  strictly narrower than the pre-existing SKIP_PRE_PR_GATE=1 bypass
- R44: checked-ok — I4-1 + C2 forbidden pattern ban piping the gate
- RS1: n/a
- RS2: n/a
- RS3: n/a — env var validated by regex; ceiling added per F2
- RS4: n/a — cache holds only hash + epoch
- RS5: checked-ok — local same-actor knob, no transport party
- RS6: n/a

### Testing expert
- R1-R20: n/a
- R21: checked-ok — full bats suite re-run required before commit
- R22-R41: n/a
- R42: finding (Adjacent F4) — resolved via T17
- R43: checked-ok — fail-safe direction exercised by the refuses-to-fire set
- R44: checked-ok — T9 red-proves exit-status propagation
- RT1: n/a — no mocks; real git repos and scripts
- RT2: checked-ok — all matrix rows mechanically assertable with the
  existing harness + `run_direct` helper
- RT3: n/a
- RT4: n/a
- RT5: checked-ok — fixtures invoke the real hook script
- RT6: checked-ok — new functions covered via the matrix
- RT7: checked-ok — fires/refuses-to-fire pairing explicit
- RT8: checked-ok — run-count is the guarded-mutation-absence assertion
- RT9: n/a

---

# Rounds 2-5 (incremental)

## Round 2

Changes: Round-1 fixes applied (C4 exit-2 unresolved-root path, C2 ownership
check + TTL cap, prose additions, T8 split, T15/T16/T17, T1 breadcrumb).

Findings and resolution:
- Functionality F3 (Minor): phase-doc failure-tail message misleading for
  exit-2 never-ran outcomes → **Fixed**: C5 tail message made outcome-neutral.
- Functionality (non-finding note): F6 requirement lacked the cap mention →
  **Fixed** (intra-plan drift closed).
- Security F5 (Minor): I2-2 enumeration omitted foreign-owned → **Fixed**.
- Testing F1 (Major): T16 entry mode unspecified; assertions vacuous
  (hook mode exits 0 on every path; deleted .git makes "no cache file"
  unfalsifiable) → **Fixed**: T16 pinned to run mode, exit-0 + passthrough
  assertions carry the RT7 red-proof; vacuous assertion demoted to
  documented consequence.
- Testing F2 (Minor): .git-deletion fixture subject to git upward discovery
  → **Fixed**: setup() exports GIT_CEILING_DIRECTORIES.
- Testing F3 (Major): TTL cap added in round 2 with no test row → **Fixed**:
  T18 (cap fires) added; T19 (malformed TTL) added.
- Testing F4 (Minor): T17 "fenced snippets" mechanism unspecified →
  **Fixed**: whole-file grep chosen; C5 forbidden pattern widened to
  snippets AND prose with a prose-wording constraint.
- Testing F5 ([Adjacent → Functionality]): N1 ("parse the TTL" failure →
  run) contradicted C2 (malformed → default 3600) → **Resolved** by
  Functionality direction: malformed TTL = tuning-knob failure → default
  3600 (capped); N1 reworded; T19 assertion made deterministic.

## Round 3

Changes: Round-2 fixes applied (see above).

Findings and resolution:
- Functionality F4 (Minor): `^[0-9]+$` admits leading-zero values (`08`)
  that crash bash base-8 arithmetic under set -e → **Fixed**: C2 mandates
  `TTL=$((10#$TTL))` normalization; T19b red-proves.
- Functionality F5 (Minor) + Security F6 (Minor) — perspective convergence:
  malformed-TTL fallback was silent; a mistyped disable intent
  (PRE_PR_CACHE_TTL=O for 0) silently re-enabled the default skip window →
  **Fixed**: C2 specifies a stderr note; T19 asserts its substring.
- Testing F1 (Minor): cap guard had fires case only — T18 could not
  distinguish cap-at-86400 from fallback-to-3600 → **Fixed**: T18b added
  (stamp between default and cap → must skip).
- Testing F2 (Minor): forbidden-pattern regex missed variant spellings →
  **Fixed**: widened to `bash [^ ]*scripts/pre-pr\.sh` at all three sites
  (T17, C5 pattern, C5 derivation rg).
- Testing F3 (Minor): run_direct could hang on mode-dispatch regression
  (fall-through to hook mode's `INPUT=$(cat)`) → **Fixed**: specified
  `bash "$SCRIPT" run </dev/null`.
- Security: item-3 fail-direction assessment recorded — malformed TTL →
  default 3600 accepted (R38/R43 sign-off with worst case / likelihood /
  cost quantification in the expert output).

## Round 4

Changes: Round-3 fixes applied (see above).

Findings and resolution:
- Security: **No findings** (base-8 fix verified as narrow-direction;
  overflow edge traced — bash intmax_t wrap lands on miss or capped value,
  never crash/unbounded skip; T18b accepted as within the signed-off cap).
- Functionality F6 (Minor): widened C5 derivation regex gained an
  undispositioned hit at hooks/check-pre-pr.sh:18 (header comment) →
  **Fixed**: dispositioned in C5 non-members note.
- Testing F1 (Minor): 1-second expiry margins in T18/T19b flake on backward
  clock steps → **Fixed**: T5 → now-7200, T18 → now-90000, T19b → now-100
  (red-capability preserved; flake direction was false-red only).
- Testing F2 (Minor): RT7 ledger omitted T18b/T19b; stale pre-widening
  pattern spelling in C5 interplay sentence → **Fixed**: ledger extended,
  spelling updated.

## Round 5 (final)

Changes: Round-4 fixes applied (see above).

Result: **all three experts return "No findings".**
- Functionality: derived-set and dispositioned-set reconcile exactly
  (3 members + 3 non-members); TTL domain fully partitioned and tested
  across five classes; full-plan closing sweep clean.
- Security: no gate-weakening across all rounds; skip chain integrity
  predicates unchanged; one recorded observation (T18's widened margin
  loosens the test-pinned cap bound to [50000, 90000) — accepted as
  deliberate backward-clock tolerance, normative cap remains 86400).
- Testing: every guard paired (fires + refuses-to-fire), every red-proof's
  mutation named, all timing fixtures flake only toward false-red; RT2
  clean; T8c remains the sole documented untestable case.

Termination condition met at round 5 of 10.
