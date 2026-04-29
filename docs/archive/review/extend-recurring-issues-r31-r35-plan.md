# Plan: Extend Recurring Issue Checklist with R31-R35

## Project context

- **Type**: config-only (Claude Code skill / rules content for reviewer behavior)
- **Test infrastructure**: none (skill markdown has no automated tests; correctness is judged by reviewers using the skill)

## Scope decision (after Round 1-3 review)

After 3 rounds of triangulate review, the original "5 lessons-learned text additions" objective grew into a security-infrastructure project (PreToolUse hook, fixtures, declared-grep machinery). Round 3 surfaced that the orchestrator had misunderstood Claude Code's hook protocol, creating Critical findings that were artifacts of scope creep, not of the underlying lessons.

**Scope-back decision**: keep the original intent. R31-R35 are reviewer-agent obligations expressed as rules text in `common-rules.md`, structurally identical to R1-R30. Anything beyond text-and-cross-references is deferred to follow-up plans.

| Round 1-3 idea | Decision | Reason |
|---|---|---|
| R31 PreToolUse hook (`r31-destructive-guard.sh`) + settings.json entry | **DEFERRED** to follow-up plan | Pattern-matching pre-execution control is best-effort tripwire (S13/S15/S16); proper design needs its own review cycle. R31 as reviewer-text is sufficient for the lessons-learned intent. |
| R31 positive fixture (9 categories) + negative fixture | **DEFERRED** | Fixtures are infrastructure for the runtime hook; without the hook, there is nothing to fixture. |
| R34 PR-author-declared bug-class grep (Round 2 T16) | **DEFERRED** | R34 stays as reviewer-driven enumeration like R3, not as a process-procedure rule. |
| Split-into-two-PRs mechanism (Round 2) | **DROPPED** | Scope-back removes the size pressure that motivated the split. |
| R32 "ready signal" PR-author declaration | **KEPT as guidance** | R32 body suggests the author declares a ready signal but does not mandate a PR-format change. |

## Objective (scoped)

Add five new recurring-issue rows (R31-R35) to `skills/triangulate/common-rules.md`, matching the structural shape of R1-R30. Update the existing R1-R30 references in 4 skill files to R1-R35 so the new rules are actually invoked.

The five lessons:

1. **R31** — Destructive operations executed without explicit user confirmation. 9 reviewer-facing categories (a)-(i): data-volume / shared-schema / security-state-table / VCS-history / secret-key-material / authorization-state / audit-observability / recovery-path / supply-chain-and-artifact-integrity. Severity Critical for categories (c), (e), (f), (g), (h), (i); Major for (a), (b), (d). Reviewer obligation: when an expert sub-agent or orchestrator is about to execute a destructive op, it must surface that intent to the user explicitly with the matched category cited.
2. **R32** — New long-running runtime artifacts merged without a real boot smoke test. Companion to R21: R21 covers test/lint/build re-run; R32 covers running the artifact in its real shape until it logs a ready signal. The PR author is expected to declare a "ready signal" (log line, port-bound message, or status endpoint return) so the reviewer's pass/fail is mechanical (grep on the declared signal). Includes a security note: when the artifact handles auth/sensitive data, the boot log must show secrets/identity/TLS material loaded successfully.
3. **R33** — CI configuration changes applied to one config but not the other duplicates of the same gate. Detection by SEMANTIC equivalence (does this path execute the same test command/security gate?), not text-grep — so reusable-workflow includes and matrix expansions are covered. Severity Major default; escalates to Critical when the drifting gate is a security control (SAST/SCA/secret-scan/image-scan/signature-verify/SBOM/license-policy).
4. **R34** — Pre-existing bugs noticed in adjacent files, deferred without applying the existing Anti-Deferral cost-justification. Cross-references the existing `Anti-Deferral Rules` section without restating the 30-min rule. Inherits the Anti-Deferral security carve-out via a closed list of security-sensitive surfaces. Detection: enumerate sibling files in the same directory or imports of the same module and scan for the same class of bug being fixed.
5. **R35** — Production-deployed components merged without a manual test plan. Tiered severity: Tier-1 Major (services, daemons, infrastructure, UI surfaces); Tier-2 Critical (auth flows, authorization changes, cryptographic-material changes, session lifecycle changes, identity-broker/federation trust changes, key custody changes, zero-trust/service-mesh policy changes, webhook signing-key rotation). Mechanical fire trigger: diff matches the deployment-artifact list (Dockerfile, *-compose.yml, Kubernetes manifests, Helm, Terraform, Pulumi, Ansible, cloud-init, systemd units, CloudFormation/CDK, OAuth provider config, IAM/RBAC config, TLS material, IdP metadata, mesh policy CRDs, webhook signing-key config). Required artifact path: `./docs/archive/review/[plan-name]-manual-test.md` with min sections (Pre-conditions / Steps / Expected result / Rollback / Tier-2: Adversarial scenarios).

## Requirements

### Functional

1. Insert R31-R35 rows in the "All experts must check" table after R30.
2. Replace the existing pointer line `See "Extended obligations (R17-R22)" below ... R23-R28 are self-contained` with a version covering R31-R35.
3. Rename `### Extended obligations (R17-R22)` heading to `### Extended obligations` (drop the inline range; sub-headings communicate which rules have extended obligations).
4. Append Extended obligations for R31, R32, R33, R34, R35 after the R22 subsection (R33 promoted from self-contained because its procedure is non-trivial).
5. Append `(see also R32 — runtime-shape boot test companion)` to the R21 row's description.
6. Append R31-R35 entries to the `Recurring Issue Check` output template.
7. Replace `R1-R30` literals with `R1-R35` in 4 files (12 occurrences total): `common-rules.md:64`, `SKILL.md:22, 24`, `phases/phase-1-plan.md:187, 218, 222, 229`, `phases/phase-3-review.md:104, 117, 285, 289, 296`.
8. Sync the four edited skill files to `~/.claude/skills/triangulate/`.
9. R34 closed list is aligned with R35 Tier-2 (Round 3 S18): R34 carve-out engages for any class that R35 Tier-2 names — auth flows, authorization changes, cryptographic-material handling, session lifecycle, identity-broker/federation trust, key custody, zero-trust/mesh policy, webhook signing-key rotation, plus secrets handling, audit logging, rate-limiting / authentication-failure paths, input validation.

### Non-functional

1. Each new rule follows the table-row + Extended-obligations shape of R17-R22.
2. Every example is illustrative, not framework-mandatory. Specifics that carry security teeth (e.g., naming `audit_log` as a security-state table) remain concrete because abstraction would lose intent.
3. Cross-references use the existing format (`see R3`, `companion to R21`).

### Out of scope

- R31 PreToolUse hook implementation. Tracked as a follow-up plan, see `## Deferred follow-up`.
- R31 synthetic fixtures.
- R34 PR-author-declared bug-class grep machinery.
- `phases/phase-2-coding.md` (no `R1-R30` literal there).
- `~/.claude/hooks/pre-review.sh` and Ollama merge prompts (do not enumerate R-numbers).

## Edit locations (8)

| # | Location | Change |
|---|----------|--------|
| 1 | `skills/triangulate/common-rules.md` table after R30 row | Insert 5 rows (R31-R35) |
| 2 | `skills/triangulate/common-rules.md` "See Extended obligations" pointer line | Replace with: `See "Extended obligations" below for full procedures on R17-R22 and R31-R35. R23-R30 are self-contained in the table row above.` |
| 3a | `skills/triangulate/common-rules.md` `### Extended obligations (R17-R22)` heading | Rename to `### Extended obligations` |
| 3b | After R22 Extended obligations subsection | Append Extended obligations for R31, R32, R33, R34, R35 |
| 3c | R21 row description (Round 2 F10) | Append `(see also R32 — runtime-shape boot test companion)` |
| 4 | `skills/triangulate/common-rules.md` Recurring Issue Check template | Append 5 lines (R31-R35) |
| 5 | `skills/triangulate/common-rules.md:64` | Replace `R1-R30` with `R1-R35` |
| 6 | `skills/triangulate/SKILL.md:22, 24` | Replace `R1-R30` with `R1-R35` (2 occurrences) |
| 7 | `skills/triangulate/phases/phase-1-plan.md:187, 218, 222, 229` | Replace `R1-R30` with `R1-R35` (4 occurrences) |
| 8 | `skills/triangulate/phases/phase-3-review.md:104, 117, 285, 289, 296` | Replace `R1-R30` with `R1-R35` (5 occurrences) |
| post | Sync 4 modified files to `~/.claude/skills/triangulate/` | `cp` from repo to user-config |

Cross-reference scan (verified):
- `grep -rn "R17-R22\|Extended obligations"` → 3 self-references inside `common-rules.md` only.
- `grep -rn "R1-R30"` → 12 occurrences across the 4 files listed above.

## Implementation steps

1. Read `common-rules.md` lines 225-380 to confirm insertion anchors.
2. Draft R31-R35 table rows + Extended obligations bodies (compact, structurally matched to R17-R22 style).
3. Apply edit 1 (table rows).
4. Apply edit 2 (pointer line).
5. Apply edit 3a (heading rename).
6. Apply edit 3b (Extended obligations append).
7. Apply edit 3c (R21 row append).
8. Apply edit 4 (template append).
9. Apply edit 5 (`common-rules.md:64`).
10. Apply edits 6, 7, 8 (R1-R30 → R1-R35 in 3 other files).
11. Verify (see Testing strategy).
12. Sync to `~/.claude/skills/triangulate/`.
13. Commit only when user explicitly approves.

## Testing strategy

The repo has no automated test framework. Verification is reproducible-shell-based.

1. **Structural verification (Round 2 T13/T14, Round 3 T20 scoped)**:
   - Recurring-issue table column-count uniformity (scoped to rule rows, excludes RS/RT and severity tables): `grep -E '^\| R[0-9]+ ' skills/triangulate/common-rules.md | awk -F'|' '{print NF}' | sort -u` — must return a single value.
   - Extended-obligations heading-row mapping: every `**RNN:` heading in `### Extended obligations` has a matching `| RNN |` table row, except R23-R30 which are table-only by design.
2. **Cross-reference verification**: `grep -n "Anti-Deferral Rules" common-rules.md` (R34 ref), `grep -n "companion to R21" common-rules.md` (R32 ref), `grep -n "see also R32" common-rules.md` (R21 reverse ref).
3. **Recurring Issue Check template self-consistency (Round 1 M9 / Round 2 T14)**:
   - Forward: `grep -cE '^\| R(31|32|33|34|35) ' common-rules.md` returns 5.
   - Paired R-token diff: extract R-tokens from rule rows (`grep -oE '^\| R[0-9]+' common-rules.md | grep -oE 'R[0-9]+' | sort -u`) and from the Recurring Issue Check template lines (`grep -oE '^- R[0-9]+ ' common-rules.md | grep -oE 'R[0-9]+' | sort -u`); `diff` must produce no output.
4. **R1-R30 → R1-R35 propagation check**: `grep -rn 'R1-R30' skills/triangulate/` returns no results after edits.
5. **File-size tracked metric (Round 1 M10 / Round 2 T19 baseline)**:
   - Pre-edit baseline (commit `d44c0e1`, recorded 2026-04-29): `common-rules.md` 410 lines / 52139 bytes.
   - 20% growth flag threshold: 492 lines / 62567 bytes.
   - Estimated post-edit: ~480 lines / ~57000 bytes (within budget).
6. **Dogfood**: this plan was reviewed via `/triangulate` Phase 1 (Rounds 1-3). Findings that survived the scope-back are applied. Round 1 M5 + Round 2 S2/S10 + Round 3 S18 inform R34's closed list and security carve-out wording.

## Considerations & constraints

### Known risks

| Risk | Mitigation |
|------|-----------|
| R34's "same class of bug" detection remains reviewer-judgment | Scoped-back plan accepts this. R34 is no weaker than R3 (which is also enumeration-by-judgment) and parallels existing reviewer-driven rules. The PR-author-declared grep machinery (Round 2 T16) is deferred. |
| R31's runtime prong is absent | The reviewer-facing prong (orchestrator surfaces destructive intent to user before executing) is the documented contract. The `PreToolUse` hook is deferred to a separate plan; until then, R31 relies on reviewer-agent discipline, exactly like R1-R30. |
| R31 reviewer obligation may be ignored if the orchestrator does not re-read common-rules.md before each tool call | Same risk applies to all R-rules; the existing `loading protocol` in `SKILL.md` already mandates reading `common-rules.md` when a phase file references an R-rule. R31 inherits this. |
| File size grows toward the 20% flag | Estimated within budget (~70 new lines vs 82-line threshold). If hit, split is straightforward (R31-R32 in PR1, R33-R35 in PR2) but not pre-required. |
| R34 closed list / R35 Tier-2 alignment regresses if R35 Tier-2 grows in a future PR | Document the alignment as an explicit invariant in R34's body so future R35 expansions trigger an R34 update too. |

## Deferred follow-up (not in this plan)

The following are explicitly NOT in this plan and require separate plans:

1. **R31 PreToolUse hook**: a `~/.claude/hooks/r31-destructive-guard.sh` script + `settings.json` PreToolUse entry. Round 3 surfaced design issues (correct hook protocol = JSON on stdin via jq, JSON on stdout; Bash matcher already occupied; script-injection safe parsing required; bypass via Write→Bash chain; obfuscation acknowledgment). The follow-up plan would address all of these. The runtime hook is a security control, not a documentation lesson, and warrants its own review cycle.
2. **R31 synthetic positive + negative fixtures**: meaningful only when (1) is implemented.
3. **R34 PR-author-declared bug-class grep**: a process change to the PR template; outside the skill's runtime scope.
