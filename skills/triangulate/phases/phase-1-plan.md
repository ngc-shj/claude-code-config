## Phase 1: Plan Creation, Review & Commit

### Step 1-1: Determine Plan Name and Branch Name

Generate name candidates using local LLM (zero Claude tokens):

```bash
# Generate plan name slug from task description
PLAN_SLUG=$(echo "[one-line task summary]" | bash ~/.claude/hooks/llm-commands.sh generate-slug)
```

If Ollama is unavailable or the result is unsatisfactory, generate the slug yourself as fallback.

Determine the branch prefix (`feature/`, `fix/`, `refactor/`, `docs/`) from the task type, then confirm with the user:

```
Plan name: [plan-name]
Branch name: [prefix]/[plan-name]
Save to: ./docs/archive/review/[plan-name]-plan.md
```

Naming guidelines:
- **Plan name**: Short descriptive slug in kebab-case (e.g., `add-user-auth`, `fix-login-bug`)
- **Branch name**: Prefix + slug in kebab-case (e.g., `feature/add-user-auth`, `fix/login-bug`, `refactor/extract-utils`)

### Step 1-2: Create the Plan

Use Claude Code's built-in plan creation feature to create a plan and save it to `./docs/archive/review/[plan-name]-plan.md`.

Ensure the following sections are included for review expert agents to evaluate. Add missing sections as needed:

- **Project context**: Declare so experts can tailor recommendations:
  - Type: `config-only` / `library` / `CLI tool` / `web app` / `service` / `mixed`
  - Test infrastructure: `none` / `unit tests only` / `unit + integration` / `+E2E` / `+CI/CD`
  - **Verification environment constraints**: enumerate runtime / manual-test environment limits that block end-to-end verification. Examples (illustrative, not exhaustive — declare any limit that prevents a contract's manual-test path from running): paid-tier-only platform APIs a free developer account cannot exercise, external services unavailable in local dev, hardware-attestation paths that require physical devices, cross-tenant isolation tests that require multiple billing accounts, region-pinned services that require a specific cloud region. Phase 1 reviewers MUST cross-reference each contract's manual-test plan against this list and explicitly classify each path as `verifiable-local` / `verifiable-CI` / `blocked-deferred`. A `blocked-deferred` path requires an Anti-Deferral cost-justification recorded against the constraint entry — silent omission is not acceptable. Phase 3 cites these entries by ID from its Environment Verification Report.
  - When type is `config-only` or test infrastructure is `none`, experts MUST NOT raise Major/Critical findings recommending the addition of automated tests — such recommendations are downgraded to Minor informational notes only. This prevents repeated friction from over-engineered test suggestions in repos that have no automated test framework.
- **Objective**: What to achieve
- **Requirements**: Functional and non-functional requirements
- **Technical approach**: Technologies, architecture, and design decisions
  - **Concurrency / isolation-level design requires a plan-stage real-DB probe**: when the design depends on a transaction isolation level, a lock, an advisory lock, `SELECT … FOR UPDATE`, `SERIALIZABLE`/`REPEATABLE READ` semantics, or any concurrency-control primitive, the plan MUST NOT lock the contract on the strength of reading the ORM/driver code alone. Intermediate layers silently alter the effective behavior — a connection pooler or query proxy (e.g. Prisma's proxy / Accelerate, PgBouncer in transaction mode, a serverless data API) can **drop or downgrade the `isolationLevel`** the code appears to request, so the primitive the code "obviously" uses is not the primitive that runs. Reading the code cannot see this; only executing against the real stack can. **Required probe**: before locking the concurrency contract, run a small script against the *actual* deployment stack (same pooler/proxy/driver as production, not a bare local connection) that (a) opens the transaction the design specifies and introspects the effective isolation level the engine reports (`SHOW transaction_isolation` / `current_setting('transaction_isolation')` / engine equivalent), and (b) reproduces the contested race with two concurrent writers and confirms the primitive actually serializes them. Record the probe command and its observed output in the plan under this contract. A concurrency design that a real-DB probe would refute (e.g. a `SERIALIZABLE` mis-design, or an `isolationLevel` the proxy discards) is exactly the class Phase-1 review is meant to catch before implementation — G1 caught a `Serializable` mis-design pre-implementation this way; the isolation-drop-by-proxy case is the same category and only the probe surfaces it.
- **Contracts** (contract-first; replaces "implementation steps" by default):
  - **Numbering**: every contract is assigned a stable ID — `C1`, `C2`, ..., `Cn` — at the time it is locked. IDs do not get reused if a contract is later removed; renumbering invalidates back-references in subsequent rounds and review artifacts. Findings, deviation log entries, manual-test references, and Phase 3 review comments cite contracts by ID, not by paraphrase.
  - **Function/module signatures**: name, parameter types, return type, error type — no body
  - **Invariants**: properties that must hold across the change. Classify each invariant as **app-enforced** (a runtime check; absence = bug surfaces at request time, only when the offending code path executes) or **schema-enforced** (the storage engine / type system rejects violating writes regardless of which caller attempts them; absence = silent corruption possible from a forgotten code path, an ad-hoc admin query, or a future migration). Schema-enforced invariants are stronger because they survive new callers, late-arriving migrations, and out-of-band writes; prefer them when the storage layer can express the constraint (CHECK constraints, partial unique indexes, triggers, NOT NULL with default, sum types in the schema). App-enforced examples: "every write to table X passes through helper Y", "no nested transaction on raw client", "rate-limit middleware applied to every new route". Schema-enforced examples: "deleted rows cannot be re-inserted with the same primary key" (partial unique index over a tombstone column), "state transitions follow the documented graph" (CHECK constraint over the state column referencing the transition source). When an app-enforced invariant has a viable schema-enforced equivalent, the plan MUST state why the weaker form was chosen — otherwise reviewers should request the stronger form. **Member-set derivation for universally-quantified invariants (R42)**: when an invariant is universally quantified over a class — "rate-limit middleware applied to *every* new route", "*no* permanent delete without step-up", "*all* destructive routes carry a guard" — the plan MUST attach the code-derived member-set: the `grep` command over the primitive that *defines* the class, and the resulting list of members the control will be applied to. A prompt- or external-review-supplied list is an unverified hint, not the member-set; any list-vs-code delta is recorded as a finding. Include indirect members (cascade-via-parent, raw SQL, aliased wrappers) the defining-primitive grep misses. The contract cannot transition to `locked` until this member-set is present (mirrors the Consumer-flow-walkthrough lock refusal below).
  - **Forbidden patterns**: grep-able regex or literal strings that MUST NOT appear in the diff. Phase 2-4 contract conformance grep keys off this list. Format each entry as: `pattern: <regex or literal> — reason: <one-line>`
  - **Acceptance criteria**: observable post-conditions per contract
  - **Consumer-flow walkthrough** (mandatory before any contract that defines an API response shape, persisted-state shape, message payload, event payload, or any other shape consumed by code outside the producer transitions to `locked`): a contract that "looks complete" from the producer side can still be unconsumable — the producer-side shape is correct and the consumer-side cannot make use of it because a field the consumer needs is absent (e.g., the consumer needs `entryId` to construct downstream URLs or to compute associated data; the locked shape only carries `attachmentIds`). To prevent this class of mid-implementation shape change:
    1. Identify every consumer call site for the contract — client component, sibling route handler, audit/event handler, integration test, retry queue, any code that READS the contract's output.
    2. For each consumer, write a one- to two-sentence walkthrough naming exactly which fields the consumer reads and what operation it performs on each. Format: `Consumer X (path: <file/route/component>) reads { fieldA, fieldB, fieldC } and uses fieldB to <derive Y / construct Z URL / verify signature against W>.`
    3. If any consumer needs a field NOT in the locked shape, the contract is incomplete — extend it BEFORE the contract transitions to `locked` in the Go/No-Go gate. Do not defer to Phase 2 with a "we'll see during implementation" note; mid-implementation shape changes cascade through every other contract that references the changed field.
    4. Persist the walkthroughs in the plan's Acceptance section under the contract ID, so Phase 2 sub-agents can verify their implementation matches the locked consumer expectation, and so Phase 3 reviewers can cross-check the walkthrough against the actual consumer code.

    Plan reviewers MUST refuse to lock such a contract until every consumer walkthrough is present. The walkthrough catches the class of bug where the producer-side spec is internally consistent but the consumer-side cannot make use of it — a class that field-presence and forbidden-pattern grep cannot catch because both sides individually look correct.
  - **(Opt-in) Implementation sketch**: pseudo-code is permitted ONLY for genuinely novel algorithms whose correctness depends on body-level reasoning. The default is no body. Reviewers MUST NOT review pseudo-code as if it were code — flag pseudo-code-driven review loops (the "untreatable plan loop" pattern) and pivot to contract review
- **Go/No-Go Gate** (mandatory tail section of every plan):
  - Lists every contract by ID with a binary status: `locked` or `pending`.
  - The plan does NOT transition to Phase 2 until every contract reads `locked` and all plan-review rounds have closed. A contract flips back to `pending` if a later round materially changes its signature, invariants, forbidden-pattern list, or acceptance criteria.
  - Format:
    ```
    ## Go/No-Go Gate
    | ID  | Subject                                    | Status |
    |-----|--------------------------------------------|--------|
    | C1  | <one-line subject>                         | locked |
    | C2  | <one-line subject>                         | locked |
    | ... |                                            |        |
    ```
  - Rationale: when contracts are paraphrased across rounds, drift accumulates and the plan loops on its own pseudo-code instead of converging. The gate forces explicit acknowledgement that every contract is in its final form before implementation begins, and gives Phase 2 / Phase 3 a stable reference surface for cross-checks.
- **Testing strategy**: How to test
- **Considerations & constraints**: Known risks, constraints, and out-of-scope items.
  - **Scope contract** (mandatory when the work belongs to a larger ongoing initiative, shares code with adjacent in-flight PRs, or is a slice of a multi-PR plan): enumerate out-of-scope items as ID'd entries (`SC1`, `SC2`, ..., `SCn`) — same identifier style as Contracts. Each entry names what is deliberately deferred AND the contract / PR / future-issue that owns it. Deviation log entries and Phase 3 review comments cite scope-out items by ID rather than paraphrase. Rationale: a `Skipped — out of scope` deviation entry that cites `SC1` is auditable against the locked plan; one that says "this was out of scope" is unverifiable later. The Scope contract makes "what we are NOT doing in this PR" first-class evidence, on par with the Contracts list of what we ARE doing, and prevents the failure mode where scope-out is invented after the fact to justify a skip.
- **User operation scenarios**: Concrete usage scenarios with specific sites/forms/workflows to surface edge cases (e.g., form structure variations, input field conflicts, fallback paths)

### Step 1-3: Local LLM Pre-screening (Optional)

Before launching Claude sub-agents, run a quick pre-screening pass using local LLM to catch obvious issues and reduce API cost.
The script reads the plan file directly and calls Ollama via curl — no Claude tokens consumed.

```bash
PLAN_FILE=./docs/archive/review/[plan-name]-plan.md bash ~/.claude/hooks/pre-review.sh plan
```

If the output contains issues, fix them in the plan before proceeding to expert review.
If Ollama is unavailable, the script outputs a warning and exits gracefully — proceed to Step 1-4.

Save the local LLM output for reference in Step 1-4 (to avoid duplicate findings).

### Step 1-4: Plan Review by Three Expert Agents (Claude Sub-agents)

Launch three sub-agents in parallel with the following roles (fall back to sequential inline execution if unavailable).

| Agent | Role | Evaluation perspective | Out of scope |
|-------|------|----------------------|-------------|
| Functionality expert | Senior Software Engineer | Requirements coverage, architecture, feasibility, edge cases, error handling | Security vulnerabilities, test design/coverage |
| Security expert | Security Engineer | Threat model, auth/authz, data protection, OWASP Top 10, injection, auth bypass, business logic vulnerabilities (OWASP A04) | Functional correctness (non-security), test strategy |
| Testing expert | QA Engineer | Test strategy, coverage, testability, CI/CD integration, test quality | Implementation correctness, security analysis |

**[Adjacent] tag obligation**: When an expert encounters an issue outside their scope but with potential impact, they MUST flag it using the format: `[Adjacent] Severity: Problem — this may overlap with [other expert]'s scope`. This is mandatory, not optional.

Instruction template for each sub-agent:

**Round 1 (full review):**
```
You are a [role name].
Evaluate the following plan from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Project context:
[Project type and test infrastructure declared in the plan, e.g., "config-only repo, no CI/CD"]

Plan contents:
[Plan file contents]

Local LLM pre-screening results (already addressed — do not re-report these):
[Local LLM output, or "None" if skipped]

Requirements:
- Only raise specific and actionable findings within your scope
- If you encounter an issue outside your scope but with potential impact, flag it as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria (see below)
- For each finding, specify "Severity", "Problem", "Impact", and "Recommended action"
- Do not duplicate issues already caught by local LLM pre-screening
- **Project context obligation**: If the project context above is `config-only` or test infrastructure is `none`, do NOT raise Major/Critical findings recommending the addition of automated tests, CI/CD, or test framework setup. Such recommendations are downgraded to Minor informational notes only. Recommending the introduction of a unit-test framework or CI pipeline for a config-only repo that has none is over-engineering and wastes review rounds.
- If there are no findings, explicitly state "No findings"

Plan-specific obligations:
- Account for all downstream invariants of schema changes. When adding a new enum value, constant, or type, search for tests that enumerate all values of that type and check what invariants they enforce. Common patterns to check:
  - i18n key coverage tests (every enum value needs a translation key)
  - Exhaustive switch/if-else statements
  - Group membership arrays (audit action groups, permission groups)
  - OpenAPI spec generation
- The plan MUST list all files that need updating, not just the direct schema/constant files
- Verify the plan accounts for existing shared utilities (see "Codebase Awareness Obligations" in Common Rules)
- When the plan involves event dispatch (webhooks, notifications, etc.) or audit log changes, explicitly check:
  - Fire-and-forget async dispatch (any async work launched without awaiting/joining its completion) must not run inside a DB transaction scope — async context inheritance can cause the transaction to close before the dispatched work completes, producing runtime errors (R9)
  - Module dependency graph must not form circular imports — if A imports B and B imports A, module initialization order may produce undefined references (R10)
  - Display/UI grouping (e.g., audit log filter categories) and subscription/delivery grouping (e.g., webhook event filters) are separate concerns — reusing one for the other risks scope leakage or update gaps (R11)
  - Every action value passed to the logging/audit function must be registered in the corresponding action group definition, i18n labels, UI label maps, and tests (R12)
  - Delivery failure events must not trigger re-delivery — verify the design includes a suppression mechanism to prevent infinite dispatch loops (R13)
- When the plan involves new DB roles or permission grants, explicitly check:
  - Grants must cover all implicit operations the application code performs — e.g., conflict-resolution clauses on writes may require read permission in addition to write, foreign-key validation may require read permission on the referenced table, row-level-security modes may add further requirements beyond the explicit statement (R14)
- When the plan involves database migrations, explicitly check:
  - Database names, role names, hostnames, and other environment-dependent values must use dynamic resolution (e.g., `current_database()`, environment variables, or templating) — not hardcoded values that will fail in CI or other environments (R15)
- **Consumer-flow walkthrough enforcement** (Functionality expert obligation): for every contract that defines an API response shape, persisted-state shape, message payload, event payload, or any other shape consumed by code outside the producer, verify the contract has a per-consumer walkthrough as defined in Step 1-2 (Contracts → Consumer-flow walkthrough). For each consumer named in the walkthrough, verify the listed fields actually appear in the locked shape AND that any operation the consumer performs (URL construction, AAD computation, signature verification, idempotency-key derivation, etc.) is satisfiable from those fields alone. Missing walkthrough OR a walkthrough whose required fields are absent from the locked shape → Major finding; refuse to lock the contract until corrected. A contract that "looks complete on the producer side" but cannot be consumed downstream is the class of bug this check exists to surface.
- **Member-set derivation cross-check (R42)** (all experts): for every invariant universally quantified over a class ("every/all/each X must Y", "no Z without W"), verify the plan attached a code-derived member-set per Step 1-2 (Invariants → Member-set derivation). Recompute it: `grep -rlE '<defining primitive>' <code roots>` → set A; the plan's applied-member list → set B; any member in `A \ B` is a finding (a member of the class that the control was not applied to). Confirm the derivation includes indirect members (cascade-via-parent, raw SQL, aliased wrappers) the symbol grep alone misses. Treat a plan that anchored its member-set on a prompt/external list rather than code as the finding itself. Security-relevant control + missed member ⇒ Critical (fail-open); refuse to lock the contract until the member-set is code-derived and complete. **Trigger is not limited to plan-declared invariants (R42 trigger (b))**: the class-invariant may arrive from a source other than the plan text — a security-review finding phrased as a single instance ("*this* route lacks the guard"), a CI failure, or a one-line user remark. Whenever such a single-instance signal implies a control that *ought* to hold universally, treat it as declaring the class and run this same member-set cross-check — do not wait for the plan to have spelled out "every/all/each". The seed instance is one member, never the set.
- **ORM type-shape spot-check** (Functionality expert obligation): when a contract or pseudo-code sketch references an ORM/query-builder write operation, verify the input type used matches the operation. ORMs commonly expose multiple input shapes that LOOK interchangeable but are not — illustrative examples (not exhaustive, not language-specific): single-row vs. bulk write methods often require different input types (relation-form vs. unchecked-form); update vs. upsert vs. create may diverge on which fields are nullable; method overloads selected by argument count change which fields are required. A pseudo-code snippet that compiles in the author's head but type-fails on the actual ORM contract leaks into Phase 2 as a guaranteed deviation. When a contract crosses an ORM boundary, the contract MUST name the input type explicitly (not just the method), and the plan reviewer MUST verify the named type exists in the ORM's surface for the chosen method. Treat undocumented input types as a Major finding — pseudo-code that the ORM will not accept is not a contract.
- When the plan or existing docs cite an external standard (RFC, NIST SP, OWASP ASVS, OWASP cheat sheet, IETF BCP, W3C, FIPS, ISO/IEC), apply R29 (External spec citation accuracy) — see the table-row procedure for the four-step verification. Hallucinated or wrong-section citations are Major findings regardless of whether they affect runtime behavior, and Critical when they drive a security decision. Specifically check:
  - Standards with known renumbering between revisions (e.g., NIST SP 800-63B Rev 3 vs Rev 4; OWASP ASVS 4.0.3 vs 5.0)
  - Quoted phrases in backticks or quotes — must appear verbatim in the source
  - URL anchors — many headings auto-generate anchors that differ from the visible heading text; the link target must resolve to the cited section, not a similarly-named one
  - **Inverse anchor mismatch**: link text says one section while the `href` resolves to a different live anchor (e.g., the link reads "§4.2.3" but the URL fragment is `#section-4-3-2`). Casual review reads only the link text and misses the discrepancy. Verify both surfaces match.

Severity criteria for [role name]:
  [Populate with the full table for this expert from "Severity Classification Reference" in Common Rules. Do NOT use a reference — copy the actual table here.]

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true — e.g., multi-step auth flow, complex trust boundary, chained vulnerabilities]
```

**Round 2+ (incremental review):**
```
You are a [role name].
Review the changes made since the last round from a [perspective] perspective.

Scope: [In-scope items for this expert]
Out of scope: [Out-of-scope items for this expert]

Changes since last round:
[Diff or description of changes]

Previous findings and their resolution:
[Previous findings with status: resolved/new/continuing]

Requirements:
- Verify that previous fixes are correct and complete
- Check if fixes introduced regression or new issues in surrounding context
- Report any previously overlooked issues within your scope
- Flag out-of-scope issues with potential impact as: [Adjacent] Severity: Problem — this may overlap with [other expert]'s scope
- Classify each finding by severity using YOUR expert-specific criteria
- If there are no findings, explicitly state "No findings"

All obligations from Round 1 remain in effect (Plan-specific obligations, severity criteria, etc.).

For Security expert only — append to each Critical finding:
  escalate: true/false
  escalate_reason: [reason if true]
```

### Step 1-5: Save Review Results and Deduplicate

First, save each agent's raw output to temporary files, then use local LLM for deduplication (zero Claude tokens):

```bash
# Per-run temp directory so parallel /triangulate sessions do not
# collide. tri-tmpdir.sh create produces a mode-0700 dir under TMPDIR
# (falling back to /tmp); no umask modification is needed — other local
# users cannot traverse the directory regardless of interior file modes.
TRI_DIR=$(bash ~/.claude/hooks/tri-tmpdir.sh create)
: "${TRI_DIR:?tri-tmpdir create failed; cannot continue plan-review merge}"
echo "TRI_DIR=$TRI_DIR"
# ORCHESTRATOR OBLIGATION: after each expert sub-agent returns, save the
# sub-agent's raw output to the corresponding file using the Write tool,
# substituting the LITERAL absolute path captured from the TRI_DIR= value
# (do NOT pass the string "$TRI_DIR" — Write tool does no shell expansion):
#   Write "<literal TRI_DIR>/func-findings.txt" ← Functionality expert output
#   Write "<literal TRI_DIR>/sec-findings.txt"  ← Security expert output
#   Write "<literal TRI_DIR>/test-findings.txt" ← Testing expert output
cat "$TRI_DIR/func-findings.txt" "$TRI_DIR/sec-findings.txt" "$TRI_DIR/test-findings.txt" \
  | bash ~/.claude/hooks/llm-commands.sh merge-findings
bash ~/.claude/hooks/tri-tmpdir.sh cleanup "$TRI_DIR"
```

**Failure handling**: `merge-findings` enforces an internal **600 s** timeout via curl
`--max-time` (see `cmd_merge_findings` in `hooks/llm-commands.sh`). Ollama is a soft
dependency — when unavailable or when the call exceeds that budget, the helper returns
empty stdout with a stderr warning, and the orchestrator MUST deduplicate manually as
fallback. Do NOT wrap the call in an additional outer `timeout` shorter than 600 s; that
would kill legitimately-long large-model runs (gpt-oss:120b on a 50-finding aggregate
routinely sits in the 90-300 s range). Manual fallback:
- Merge findings that describe the same underlying issue from different perspectives
- Keep the most comprehensive description and note all perspectives that flagged it

**Preserve Recurring Issue Check sections (mandatory)**: Each expert's `## Recurring Issue Check` block (R1-R42 + expert-specific RS*/RT*) MUST be preserved verbatim in the merged review file under a top-level `## Recurring Issue Check` section, organized by expert. Do NOT deduplicate these — they are evidence that each check was performed. If an expert's output is missing the Recurring Issue Check section, return the output to the expert for revision before saving the merged file.

Save to `./docs/archive/review/[plan-name]-review.md` (create `./docs/archive/review/` if it doesn't exist).

```markdown
# Plan Review: [plan-name]
Date: [ISO 8601 format]
Review round: [nth]

## Changes from Previous Round
[For first round: "Initial review", for subsequent rounds: describe changes]

## Functionality Findings
[Functionality expert output — deduplicated]

## Security Findings
[Security expert output — deduplicated]

## Testing Findings
[Testing expert output — deduplicated]

## Adjacent Findings
[Adjacent-tagged findings from all experts — preserved for routing]

## Quality Warnings
[Findings flagged by merge-findings quality gate: VAGUE, NO-EVIDENCE, UNTESTED-CLAIM]

## Recurring Issue Check
### Functionality expert
- R1: [status]
- R2: [status]
- ... (R1-R42)

### Security expert
- R1: [status]
- ... (R1-R42)
- RS1: [status]
- RS2: [status]
- RS3: [status]
- RS4: [status]
- RS5: [status]

### Testing expert
- R1: [status]
- ... (R1-R42)
- RT1: [status]
- RT2: [status]
- RT3: [status]
- RT4: [status]
- RT5: [status]
- RT6: [status]
- RT7: [status]
```

Round 2+: optionally draft the "Changes from Previous Round" paragraph via Ollama:

```bash
{ git log <prev-round-commit>..HEAD --oneline
  echo '=== OLLAMA-INPUT-SEPARATOR ==='
  cat "$TRI_DIR"/*-findings.txt  # or equivalent new-findings aggregate
} | bash ~/.claude/hooks/llm-commands.sh summarize-round-changes
```

The orchestrator reviews the 1-3 sentence output and places it under the `## Changes from Previous Round` heading.

### Step 1-6: Validity Assessment and Plan Update

**Quality gate check (mandatory)**: Before assessing findings, check the `## Quality Warnings` section of the merged output. For each flagged finding (`[VAGUE]`, `[NO-EVIDENCE]`, `[UNTESTED-CLAIM]`), return it to the originating expert with the specific flag and request revision. Do not proceed with those findings until the expert provides a revised version with the required evidence or specificity.

The main agent scrutinizes each finding:
- **Critical/Major finding**: Must be reflected in the plan file
- **Minor finding**: Reflect if straightforward, otherwise record reason and skip, explain to user
- **Unnecessary finding**: Record reason and skip, explain to user

**Optional local-LLM helper for plan-edit drafts**: when a finding requires a plan edit, draft the anchor + insertion pair via Ollama. Setup: orchestrator MUST set `$FINDING_BLOCK` to the finding text before invoking (e.g., via a heredoc). An empty `$FINDING_BLOCK` produces a degenerate output.

```bash
{ cat "./docs/archive/review/[plan-name]-plan.md"
  echo '=== OLLAMA-INPUT-SEPARATOR ==='
  echo "$FINDING_BLOCK"
} | bash ~/.claude/hooks/llm-commands.sh propose-plan-edits
```

**MANDATORY** before applying the drafted ANCHOR/INSERT pair via the Edit tool:
```bash
grep -cF "$ANCHOR" "./docs/archive/review/[plan-name]-plan.md"
```
MUST return exactly 1. Branch:
- Exactly 1 → apply the INSERT via Edit tool with `old_string="$ANCHOR"`.
- 0 → anchor hallucinated or paraphrased. Apply the intended insertion manually by locating the relevant plan section. Record the mismatch and manual-apply decision in the deviation log.
- ≥2 → anchor ambiguous. Pick the correct occurrence by context, apply manually, record the reason in the deviation log.

MUST grep-verify — the check is NOT optional.

**Anti-Deferral enforcement (mandatory)**: Any finding marked Skipped / Accepted / Out of scope / Pre-existing MUST be recorded using the mandatory format defined in "Anti-Deferral Rules" below. Entries missing the Anti-Deferral check are invalid — fix the entry before proceeding to the next round.

Return to Step 1-4 until all agents return "No findings", or the maximum of **10 rounds** is reached.

If the loop limit is reached with unresolved findings:
```
=== Review Loop Limit Reached (10 rounds) ===
Remaining findings: [list with severity]
Decision needed: Continue manually or accept current state?
```
Consult the user before proceeding.

### Step 1-7: Branch Creation and Commit

Once plan review is complete, create a branch and commit.

```bash
# Create new branch from main
git checkout main
git checkout -b [branch-name]

# Commit
git add ./docs/archive/review/[plan-name]-plan.md
git add ./docs/archive/review/[plan-name]-review.md

git commit -m "plan: [plan-name] - plan creation and review complete"
```

Report to user:
```
=== Phase 1 Complete ===
Plan: ./docs/archive/review/[plan-name]-plan.md
Branch: [branch-name]
Review rounds: [n]
Next step: Proceeding to Phase 2 (Coding)
```

---
