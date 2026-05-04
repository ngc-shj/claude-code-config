## Phase 1: Plan Creation, Review & Commit

### Step 1-1: Determine Plan Name and Branch Name

Generate name candidates using local LLM (zero Claude tokens):

```bash
# Generate plan name slug from task description
PLAN_SLUG=$(echo "[one-line task summary]" | bash ~/.claude/hooks/ollama-utils.sh generate-slug)
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
  - When type is `config-only` or test infrastructure is `none`, experts MUST NOT raise Major/Critical findings recommending the addition of automated tests — such recommendations are downgraded to Minor informational notes only. This prevents repeated friction from over-engineered test suggestions in repos that have no automated test framework.
- **Objective**: What to achieve
- **Requirements**: Functional and non-functional requirements
- **Technical approach**: Technologies, architecture, and design decisions
- **Contracts** (contract-first; replaces "implementation steps" by default):
  - **Numbering**: every contract is assigned a stable ID — `C1`, `C2`, ..., `Cn` — at the time it is locked. IDs do not get reused if a contract is later removed; renumbering invalidates back-references in subsequent rounds and review artifacts. Findings, deviation log entries, manual-test references, and Phase 3 review comments cite contracts by ID, not by paraphrase.
  - **Function/module signatures**: name, parameter types, return type, error type — no body
  - **Invariants**: properties that must hold across the change (e.g., "every write to table X passes through helper Y", "no nested transaction on raw client", "rate-limit middleware applied to every new route")
  - **Forbidden patterns**: grep-able regex or literal strings that MUST NOT appear in the diff. Phase 2-4 contract conformance grep keys off this list. Format each entry as: `pattern: <regex or literal> — reason: <one-line>`
  - **Acceptance criteria**: observable post-conditions per contract
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
- **Considerations & constraints**: Known risks, constraints, and out-of-scope items
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
  | timeout 60 bash ~/.claude/hooks/ollama-utils.sh merge-findings
bash ~/.claude/hooks/tri-tmpdir.sh cleanup "$TRI_DIR"
```

**Timeout policy**: the `merge-findings` call is wrapped in `timeout 60`. Ollama is a soft
dependency; the skill MUST remain executable when it hangs or is unavailable. If `timeout`
fires (exit code 124) OR Ollama is unavailable, deduplicate manually as fallback:
- Merge findings that describe the same underlying issue from different perspectives
- Keep the most comprehensive description and note all perspectives that flagged it

**Preserve Recurring Issue Check sections (mandatory)**: Each expert's `## Recurring Issue Check` block (R1-R36 + expert-specific RS*/RT*) MUST be preserved verbatim in the merged review file under a top-level `## Recurring Issue Check` section, organized by expert. Do NOT deduplicate these — they are evidence that each check was performed. If an expert's output is missing the Recurring Issue Check section, return the output to the expert for revision before saving the merged file.

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
- ... (R1-R36)

### Security expert
- R1: [status]
- ... (R1-R36)
- RS1: [status]
- RS2: [status]
- RS3: [status]
- RS4: [status]

### Testing expert
- R1: [status]
- ... (R1-R36)
- RT1: [status]
- RT2: [status]
- RT3: [status]
- RT4: [status]
```

Round 2+: optionally draft the "Changes from Previous Round" paragraph via Ollama:

```bash
{ git log <prev-round-commit>..HEAD --oneline
  echo '=== OLLAMA-INPUT-SEPARATOR ==='
  cat "$TRI_DIR"/*-findings.txt  # or equivalent new-findings aggregate
} | bash ~/.claude/hooks/ollama-utils.sh summarize-round-changes
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
} | bash ~/.claude/hooks/ollama-utils.sh propose-plan-edits
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
