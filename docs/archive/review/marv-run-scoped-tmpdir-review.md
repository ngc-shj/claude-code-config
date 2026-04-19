# Plan Review: marv-run-scoped-tmpdir
Date: 2026-04-19
Review round: 1

## Changes from Previous Round
Initial review.

## Findings (merged)

| # | Severity | Problem | Impact | Recommended action | Flagged by |
|---|---|---|---|---|---|
| F1 | Major | Step 1-5 "After" snippet promises "make the save step explicit" but the shown block still only contains `cat ... \| merge-findings`. Sub-agent outputs are saved via the Write tool (not shell redirect), and the plan never shows the orchestrator-level save instruction in the skill text. | Future maintainer reading Step 1-5 cannot determine from the skill text alone what writes the findings files. Same gap exists for Step 3-4. | Add an explicit orchestrator instruction in both Step 1-5 and Step 3-4: "The orchestrator saves each sub-agent's raw output to `"$MARV_DIR/<role>-findings.txt"` using the Write tool (substituting the literal absolute path captured from the `MARV_DIR=` line)." | Functionality |
| F2 | Minor | `mktemp -d -t marv-XXXXXX` has different semantics on GNU coreutils vs BSD/macOS. GNU replaces the `X`s in the supplied template; BSD treats the argument as a prefix and appends its own random suffix. Functional outcome is equivalent (mode 0700 unique dir) but the name differs. | None — path uniqueness and mode are preserved on both. Plan's portability claim is imprecise. | Use portable form: `mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"` (positional template, no `-t`) which is identical on both platforms. | Functionality |
| F3 | Minor | Same as F1 from variable-persistence angle: the Write-tool save calls must use the literal absolute path too. Plan mentions Write-tool permission handling but not the substitute-literal-path obligation. | Orchestrator might write to literal string `$MARV_DIR/...`, failing silently or creating a file named `$MARV_DIR`. | Strengthen the "Persisting MARV_DIR across Bash invocations" paragraph to cover Write-tool calls, not just Bash-tool calls. | Functionality |
| F4 | Minor | `rm -rf "$MARV_DIR"` at Step 3-9 has no guard against empty `$MARV_DIR` (e.g., if Step 3-2b was skipped or its output was not captured). | On GNU coreutils, `rm -rf ""` safely errors out, but behavior is not portable. | Guard: `[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"`. Apply at both Step 1-5 end and Step 3-9. | Functionality |
| T1 | Minor | No smoke-test step for the abort-orphan scenario (plan's user-operation scenario #4). | Documented behavior not verified; future regression would be undetected. | Add a one-line smoke test: `D=$(mktemp -d -t marv-XXXXXX); stat -c '%a %n' "$D"; rm -rf "$D"` → expect `700`. (Simulates abort by checking dir mode before explicit cleanup.) | Testing |
| T2 | Minor | Step 3-3 template-substitution failure falls back to "Seed unavailable" per the plan's Risks section, but the dry-run checklist doesn't call out `## Seed Finding Disposition` as the observable signal. | Template-substitution regression would go unnoticed since sub-agents gracefully fall back. | Add to dry run: "verify each sub-agent's `## Seed Finding Disposition` section contains actual `Verified`/`Rejected` entries, not the fallback `Seed unavailable — no dispositions to record.`" | Testing |
| T3 | Minor | "At any point during the run" wording in dry-run is not testable (skill is narrative; tester cannot interpose mid-execution). | Ambiguous verification step. | Reword to a concrete post-run check: "after Step 3-9 and Step 1-5 completion, `ls /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt /tmp/seed-*.txt` MUST return `No such file or directory` for each path." | Testing |

## Adjacent Findings
None.

## Quality Warnings
None.

## Recurring Issue Check

### Functionality expert
R1-R30: All N/A or Checked. Notable:
- R3: propagation enumeration confirmed (all 4 call sites + out-of-scope sites documented with rationale).
- R17: no new helper introduced; migrating to existing `mktemp` primitive.
- R20: surgical edits, no risk of splitting multi-statement constructs.
- R30: backticked inline code; no GitHub autolink footguns.

### Security expert
R1-R30, RS1-RS3: All Pass.
- `mkdtemp(3)` atomic with `O_EXCL`; no TOCTOU.
- Mode-0700 directory blocks traversal regardless of interior file modes.
- `TMPDIR` override preserves mode-0700.
- CSPRNG-sourced suffix; not attacker-controllable.
- No FD leak, no symlink attack, no cleanup race.

### Testing expert
R1-R30, RT1-RT3: All Pass/N/A. RT2 self-applied — all findings are manual shell-step or manual-observation items; no test-framework recommendations.

## Round 1 Dispositions

| # | Disposition | Action |
|---|---|---|
| F1 | Accepted — reflected in plan | Make the Write-tool save instruction explicit in Step 1-5 and Step 3-4 rewrites. |
| F2 | Accepted — reflected in plan | Switch to portable positional template `mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"` in both Step 1-5 and Step 3-2b snippets and in Implementation checklist. |
| F3 | Accepted — reflected in plan | Extend the "Persisting MARV_DIR across Bash invocations" paragraph to cover Write-tool calls. |
| F4 | Accepted — reflected in plan | Add `[ -n "${MARV_DIR:-}" ] &&` guard on `rm -rf` at Step 1-5 end and Step 3-9. |
| T1 | Accepted — reflected in plan | Add abort-orphan smoke test step to Testing strategy. |
| T2 | Accepted — reflected in plan | Add `## Seed Finding Disposition` verification to dry-run checklist. |
| T3 | Accepted — reflected in plan | Reword dry-run file-existence check to a concrete post-run `ls` invocation. |

---

# Plan Review: marv-run-scoped-tmpdir — Round 2
Date: 2026-04-19
Review round: 2

## Changes from Previous Round
F1-F4, T1-T3 reflected in plan.

## Round 2 Findings

| # | Severity | Status | Detail |
|---|---|---|---|
| F1-F4 | — | Resolved | Functionality expert confirmed Write-tool obligation blocks, portable `mktemp`, extended persistence paragraph, empty-var guard. |
| F5 | Minor (new) | Resolved | Implementation §7.3 grep still referenced the old `-t` form; updated to match the portable positional template. |
| S1 | — | — | Security expert: no findings across F1/F3 Write-tool additions, F2 TMPDIR expansion, F4 guard, T1-T3 test additions. |
| T1-T3 | — | Resolved | Testing expert confirmed abort-orphan test, Seed Disposition observability, concrete post-run `ls`. |

## Quality Warnings
None.

## Recurring Issue Check (Round 2)

### Functionality expert
R1-R30 Pass/N/A. F5 root cause noted as downstream-artifact consistency (R3 variant — the verification grep was not updated when the Technical approach changed).

### Security expert
R1-R30 + RS1-RS3 Pass. TOCTOU (RS1), symlink attack (RS2), info leak (RS3) all evaluated and cleared. Double-cleanup path (Step 1-5 end + Step 3-9) confirmed.

### Testing expert
R1-R30 + RT1-RT3 Pass. RT2 self-applied — all new items are manual shell commands or manual observation points.

## Round 2 Termination
All findings resolved. Proceeding to Phase 1 Step 1-7 (branch + commit).
