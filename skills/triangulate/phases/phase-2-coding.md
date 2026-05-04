## Phase 2: Coding

### Step 2-1: Review the Plan and Analyze Impact (Mandatory)

Read `./docs/archive/review/[plan-name]-plan.md` and understand the implementation steps.

Before writing any code, perform the following impact analysis:

1. **Enumerate all code paths**: grep for the target identifiers (e.g., function names, API endpoint paths, message types, and file name patterns) to identify every location that will need changes
2. **Check for duplicate implementations**: Verify there are no parallel implementations of the same feature (e.g., `.js` and `.ts` versions, direct and message-based paths, primary and fallback paths)
3. **Read related type definitions and constants**: Confirm actual enum values, type shapes, and constant definitions before using them in implementation
4. **Inventory reusable code**: Run the shared utility scanner, then supplement with manual search:
   ```bash
   INVENTORY=$(mktemp /tmp/shared-utils-inventory.XXXXXX)
   bash ~/.claude/hooks/scan-shared-utils.sh > "$INVENTORY"
   ```
   Review the output and add any additional findings:
   - Shared helper functions (e.g., rate limiters, encoders/decoders, URL builders)
   - Shared constants and validation schemas (e.g., constants modules, validation config)
   - Existing patterns for event dispatch, error handling, and DB transactions
   - Record each as: `[file:line] [function/constant name] — [what it does]`
5. **Append checklist to plan**: Record the results as a checklist in `./docs/archive/review/[plan-name]-plan.md` under a new "## Implementation Checklist" section, listing:
   - Every file and location that must be modified
   - Every shared utility that must be reused (from step 4)
   - Every pattern that must be followed consistently across all sites

This step prevents: using wrong constant values, missing fallback code paths, leaving stale duplicate implementations untouched, and reimplementing logic that already exists in shared modules.

6. **Storage-backend schema verification** (when tests involve raw queries, role/permission assertions, or storage-engine specifics):
   - **Read the actual migration/DDL** — not just the ORM/abstraction-layer schema. Migrations encode constraints (conditional non-null via predicate constraints, triggers, default-permission grants) that an ORM-level schema may not surface.
   - **Query the live storage engine** for the exact permission/privilege set before writing assertion tests, using whatever catalog/introspection mechanism the engine provides. The mechanism varies — SQL engines expose `information_schema` views or vendor commands like `SHOW GRANTS`; document/key-value stores expose connection-status or admin commands; cloud-managed storage exposes IAM-policy queries. The list is illustrative, not exhaustive — for any other engine, consult its documentation for the equivalent introspection surface. Do not infer from documentation alone — verify against the running instance.
   - **Verify every required column** for every write statement by reading the schema definition, not guessing. Conditional required-column constraints (e.g., a predicate constraint that requires column X only in certain states) are typically invisible to the ORM.
   - **Do not rely on privileged-role side-effects** in test assertions. A privileged/admin role in local dev may implicitly hold permissions that a minimal CI role does not (e.g., implicit access to referenced tables through foreign-key checks). Test assertions must match migration-defined grants only.

### Step 2-2: Implementation (Delegate to Sonnet Sub-agents)

Split the plan's "Implementation steps" into independent batches and delegate to Sonnet sub-agents:

1. **Task splitting**: Group implementation steps into batches that can be executed independently
2. **Sonnet delegation**: Launch Sonnet sub-agent(s) for each batch with:
   - The full plan for context
   - The specific steps to implement
   - Any outputs from previous batches (for dependencies)
   - **The shared utility inventory from Step 2-1** (list of existing helpers, constants, and patterns that MUST be reused — sub-agents are prohibited from reimplementing these)
3. **Review**: After each batch completes, verify the output before proceeding to the next batch. Specifically check:
   - Did the sub-agent reuse existing shared utilities, or did it create new ones?
   - Did the sub-agent follow existing patterns, or did it invent a parallel approach?
   - If new helper functions were created, are they genuinely new, or do they duplicate existing code?
   - **Cross-batch symbol deduplication**: grep for any new symbol (constant, function, type) introduced by this batch to verify no other batch already defined the same symbol in a different file. Parallel sub-agents cannot see each other's output, so duplicate definitions across batches are expected — catch and merge them before proceeding.
   - **Dev/CI environment parity check** (when integration tests involve DB roles, row-level/permission policies, or privilege assertions):
     - Privileged-role behavior: Local dev often uses a high-privilege/admin role. CI may use the same role name but with different effective privileges due to default-privilege scope, role ownership, or row-level-security bypass settings. Tests must not depend on implicit grants that exist only for the privileged role.
     - Bypass modes: Roles with row-level-security bypass capability always skip RLS regardless of session settings. Tests that verify "RLS blocks the table owner" must use a role without bypass capability.
     - Container init timing: Container initialization scripts often run BEFORE migrations. Dynamic queries against catalog/introspection tables run during init will find nothing because schema objects do not exist yet. Use prospective/default-privilege mechanisms for grants/revokes that should apply to objects created later.
     - Test setup file conflicts: Unit-test setup files may override connection strings or set mocks that break integration tests. Integration tests need their own setup file that connects to the real service.

If sub-agents are unavailable, implement directly as fallback.

Recording rules during implementation:
- Sections implemented as planned: No recording needed
- **Sections that deviate from the plan**: Append to the deviation log with reasons (see Step 2-3)

### Step 2-3: Deviation Log Management

**Timing**: Run deviation check after each commit, not just at the end of implementation. If a commit message describes changes that differ from the plan, update the deviation log immediately. This prevents accumulation of unrecorded deviations that are harder to trace later.

After each commit (and at implementation end), generate a deviation log delta via local LLM:

```bash
# Three-section input: plan + existing deviation log + current diff.
# Create an empty existing-log placeholder on first run.
DEV_LOG="./docs/archive/review/[plan-name]-deviation.md"
[ -f "$DEV_LOG" ] || echo '# Coding Deviation Log: [plan-name]' > "$DEV_LOG"
{ cat "./docs/archive/review/[plan-name]-plan.md"; \
  echo "=== OLLAMA-INPUT-SEPARATOR ==="; \
  cat "$DEV_LOG"; \
  echo "=== OLLAMA-INPUT-SEPARATOR ==="; \
  git diff main...HEAD; } \
  | bash ~/.claude/hooks/ollama-utils.sh generate-deviation-log \
  > "${DEV_LOG}.append"
```

REVIEW GATE (do NOT delete the .append file before orchestrator reviews):
- Read `${DEV_LOG}.append`.
- If it contains exactly `No new deviations` (or is empty), discard.
- Otherwise APPEND (not replace) to `$DEV_LOG`:
  ```bash
  cat "${DEV_LOG}.append" >> "$DEV_LOG"
  ```
  IMPORTANT: never overwrite the full `$DEV_LOG` with Ollama output — the command emits ONLY delta entries; prior entries MUST be preserved.
- Only after the append (or decision to discard), remove the temp file:
  ```bash
  rm -f "${DEV_LOG}.append"
  ```

If Ollama is unavailable, record deviations directly.

### Step 2-4: Implementation Completion Check

Before reporting completion, check migrations, E2E impact, and run ALL three verification steps:

```bash
# Check for pending migrations
bash ~/.claude/hooks/check-migrations.sh

# E2E test impact check (if E2E tests exist in the project)
# When the diff deletes or renames routes, CSS selectors, component exports,
# data-testid/aria-label/id/data-slot attributes, grep E2E test files to verify
# no test references the old value. Fix broken E2E references before proceeding.

# Allowlist/safelist update check:
# When using privileged wrappers (e.g., elevated DB access, admin-only APIs, security escape hatches)
# in a new file, verify whether the project has an allowlist or safelist that gates their usage.
# If so, add the new file to the allowlist. CI or pre-push hooks may enforce this.

# Run ALL three checks:
# 1. Lint (in the same strict mode CI uses — e.g., zero-warning gate).
# Pre-existing warnings on touched files count: they must also be cleared.
# Suppression comments / underscore-prefix renames are NOT an acceptable resolution — see R36 (root cause must be fixed).
[lint command]

# 2. Tests
[test command]

# 3. Production build
[build command]

# 4. R35 mechanical gate (manual-test artifact for production-deployed components).
# This was previously a manual review obligation; it is now a runnable gate.
# Match the diff's changed files against the R35 deployment-artifact list. If
# any match, presence of [plan-name]-manual-test.md becomes a Phase 2 completion
# gate. The pattern list mirrors common-rules.md "Mechanical fire trigger"
# under R35 — keep them in lockstep.
R35_HITS=$(git diff --name-only main...HEAD | grep -E '(^|/)(Dockerfile|.*-compose\.ya?ml|.*\.tf|Chart\.yaml|templates/|.*\.idp\.ya?ml)$|/(deployment|statefulset|daemonset|cronjob|job|pod)\.ya?ml$|kustomization\.ya?ml$|cloudformation/|cdk/' || true)
if [ -n "$R35_HITS" ]; then
  test -f "./docs/archive/review/[plan-name]-manual-test.md" \
    || { echo "R35 gate: deployment-artifact diff detected but [plan-name]-manual-test.md missing"; exit 1; }
fi
# The grep above is a starting filter, not exhaustive. Cross-check the diff
# against the full R35 Tier-1 / Tier-2 list in common-rules.md; auth/authz/
# crypto/session/IdP/mesh/webhook-signing changes are Tier-2 and the artifact
# MUST include the Adversarial scenarios section.

# 5. Contract conformance grep (item 4 from PR-A).
# For each forbidden-pattern declared in the plan's "Contracts → Forbidden
# patterns" section, grep the staged diff. The match set MUST be empty.
# "Existing code already does this" is NOT a valid justification — contract
# violations introduced into new code are findings regardless of precedent
# in the surrounding codebase.
#   for pattern in <forbidden patterns from plan>; do
#     hits=$(git diff main...HEAD | grep -nE "$pattern" || true)
#     [ -z "$hits" ] || { echo "Contract violation: $pattern"; echo "$hits"; exit 1; }
#   done

# Optional: draft the commit body via Ollama (subject line still hand-written).
# git diff --cached | bash ~/.claude/hooks/ollama-utils.sh generate-commit-body

##### MANUAL CHECKS (not runnable commands — review obligations) #####

# MANUAL CHECK — Translation-constant drift (R27): if the diff touches
# translation or other user-facing string files, scan for numeric literals
# that duplicate validation constants and replace with interpolation
# placeholders sourced from the canonical constants.

# MANUAL CHECK — Persisted-state symmetry (R25): if the diff adds a field
# to any persisted state that crosses process / session / restart boundaries,
# verify BOTH the persist path AND the hydrate path appear in the diff,
# AND that at least one test performs: persist → cross a true process /
# worker / container boundary → hydrate → assert field equality.

# MANUAL CHECK — Migration split (R24): if the diff introduces a required
# (non-null without default) column/field on a table/type with existing
# callers, verify the change is split into additive + backfill and
# strict-constraint flip migrations, not combined into one, AND that a
# test exercises the intermediate state (after step 1, before step 2) with
# concurrent writers including at least one caller not yet updated.

##### END MANUAL CHECKS #####
```

All must pass. Fix any failures before proceeding.

**IMPORTANT**: Fix ALL errors found by lint/test/build — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes." We are building the whole project, not just a diff.

**Real-environment test obligation (integration tests)**:
When the implementation includes tests that require external services (database, Redis, message queue, etc.), the developer MUST run those tests locally against the real service BEFORE pushing to CI.
- Unit tests only verify mocked behavior — they CANNOT catch:
  - Database CHECK/NOT NULL constraint violations
  - FK cascade deletion order issues
  - Permission/privilege mismatches between database roles
  - Column name discrepancies between test SQL and actual schema
- Run the project's integration test command with a live service before every push
- If the local service is not running, start it first (e.g., `docker compose up -d db`)
- A CI failure that could have been caught locally is a **process failure**, not a code failure

**Clean-state verification before re-run (mandatory after integration-test failure)**:
A failed integration test can leave dirty state (rows, locks, queue messages) that
cascades into unrelated tests on the next run, producing a flood of false failures
that mask the original bug. Before re-running, verify the test environment is in
a clean baseline:
- For DB-backed tests: assert the affected tenant's primary tables are empty,
  OR run the project's documented reset command (`make db-reset`,
  `pnpm test:db-reset`, etc.). If the project has no reset command, document
  the manual TRUNCATE / equivalent steps used.
- For queue/cache-backed tests: drain or flush the affected namespace.
- Re-running on dirty state is a **process failure** equivalent to skipping the
  failure: it converts a single root-cause bug into N collateral failures and
  consumes triage time that should be spent on the actual cause.

### Step 2-5: Self-R-Check (Mini Sub-agent Pass)

Before declaring Phase 2 complete, run a focused R-check pass with the same three sub-agents used in Phase 3, but with a narrowed prompt that targets ONLY the Recurring Issue Checklist (R1-R36 + RS*/RT*). Phase 3's Round 1 historically surfaces a large number of findings because Phase 2 has not yet run any R-check — pulling the first R-check into Phase 2 lets Phase 3 act as incremental verification rather than first-pass discovery.

Setup (per-run temp dir, same pattern as Step 1-5 / Step 3-2b):

```bash
TRI_DIR=$(bash ~/.claude/hooks/tri-tmpdir.sh create)
: "${TRI_DIR:?tri-tmpdir create failed; cannot continue self-R-check}"
echo "TRI_DIR=$TRI_DIR"
# ORCHESTRATOR OBLIGATION: after each mini sub-agent returns, save its raw
# output to the corresponding file using the Write tool, substituting the
# LITERAL absolute path captured from TRI_DIR= above:
#   Write "<literal TRI_DIR>/self-rcheck-func.txt"
#   Write "<literal TRI_DIR>/self-rcheck-sec.txt"
#   Write "<literal TRI_DIR>/self-rcheck-test.txt"
```

Mini-prompt template (launch three sub-agents in parallel):

```
You are a [role name] performing a focused self-check of the Phase 2 implementation
against the Recurring Issue Checklist ONLY.

Scope (rules to check):
- Functionality expert: R1-R36
- Security expert: R1-R36 + RS1-RS4
- Testing expert: R1-R36 + RT1-RT3 (plus RT4 if defined in common-rules.md)

Out of scope: novel findings outside the Recurring Issue Checklist — those are Phase 3's
responsibility, not this self-check.

Inputs:
- Diff: `git diff main...HEAD`
- Plan contracts (verbatim from the plan's Contracts section, including Forbidden patterns):
  [paste]

Requirements:
- For each rule, run the targeted grep / read pattern specified in common-rules.md
  ("Known Recurring Issue Checklist" row + "Extended obligations" procedure where
  one exists). Do NOT read full files unless the targeted check is inconclusive.
- Report rules that fire with: rule ID, file:line, evidence (grep hit), severity.
- Conclude with one line listing rule IDs that were checked-and-clean.
- If nothing fires, output exactly: `No findings`.
```

Merge and act on findings:

```bash
cat "$TRI_DIR/self-rcheck-func.txt" "$TRI_DIR/self-rcheck-sec.txt" "$TRI_DIR/self-rcheck-test.txt" \
  | timeout 60 bash ~/.claude/hooks/ollama-utils.sh merge-findings
bash ~/.claude/hooks/tri-tmpdir.sh cleanup "$TRI_DIR"
```

If `timeout` fires (exit code 124) or Ollama is unavailable, deduplicate manually.

Disposition rules:
- **Critical / Major fires**: fix in Phase 2 before proceeding. Do not defer to Phase 3.
- **Minor fires**: fix if straightforward; otherwise record an Anti-Deferral entry in the deviation log and carry to Phase 3.
- **No findings across all three**: Phase 2 is complete. Phase 3 Round 1 will operate as incremental verification on top of this baseline.

Report to user when implementation is done:
```
=== Phase 2 Complete ===
Files implemented: [n]
Lint: [pass/fail]
Tests: [pass/fail]
Build: [pass/fail]
R35 gate: [N/A — no deployment-artifact change / pass — manual-test.md present]
Contract conformance: [pass — all forbidden patterns absent / fail — see findings]
Self-R-check: [N rules fired, all resolved / clean]
Deviations from plan: [yes/no] (log: ./docs/archive/review/[plan-name]-deviation.md)
Next step: Proceeding to Phase 3 (Code Review)
```

---
