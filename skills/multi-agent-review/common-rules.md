## Common Rules

### Loop Progress Report

Report at the start of each review loop:
```
=== [Phase name] Review Loop [round n/10] ===
Previous findings: Critical [x] / Major [y] / Minor [z]
Resolved: [n] / New: [n] / Continuing: [n]
```

### Ensure docs/archive/review Directory

Create `./docs/archive/review/` before starting review if it doesn't exist:
```bash
mkdir -p ./docs/archive/review
```

### When Sub-agents Are Unavailable

Process the three perspectives sequentially inline.
Explain to the user that evaluation objectivity may be reduced.

### No Commits to main

All commits must be made on the `[branch-name]` branch.
If accidentally on main, create a new branch before continuing work.

### Sub-agent Model Selection

| Expert | Default model | Escalation |
|--------|--------------|------------|
| Functionality expert | Sonnet | — |
| Security expert | Sonnet | Opus (when `escalate: true` is flagged) |
| Testing expert | Sonnet | — |

**Escalation mechanism** (Security expert only):
1. **Detection**: After Security expert (Sonnet) returns findings, check each Critical finding for `escalate: true` flag. As a safety net, the orchestrator should also independently assess whether any Critical finding warrants escalation, even if `escalate: false` is reported
2. **Re-run**: If any `escalate: true` is present, re-launch Security expert with `model: "opus"`, passing the same input (Round 1: full plan/code; Round 2+: current round's diff and previous findings) plus the Sonnet findings as additional context
3. **Merge**: Opus findings are merged with Sonnet findings (not replaced). Findings are considered "overlapping" when they share the same root cause (same file, same vulnerability type). Opus takes precedence for overlapping Critical findings; Sonnet's non-overlapping Major/Minor findings are preserved

### Handling [Adjacent] Findings

Processing rules for `[Adjacent]`-tagged findings:
1. **During deduplication** (Step 1-5 / Step 3-4): `[Adjacent]` findings are preserved and NOT merged with the originating expert's findings
2. **During fix assessment** (Step 1-6 / Step 3-5): The main orchestrator routes each `[Adjacent]` finding to the appropriate expert's scope for evaluation
3. **If the appropriate expert already reported the same issue**: merge and keep the more comprehensive description
4. **If the appropriate expert did not report it**: treat it as a new finding from that expert's perspective
5. **If the routing target is unclear or unavailable**: the main orchestrator evaluates the finding directly

### Codebase Awareness Obligations

Every expert agent MUST perform codebase-wide investigation before writing findings. Reviewing only the changed files is insufficient — you must understand how the changes fit into the whole system.

**Before-review investigation (mandatory for all experts):**

1. **Discover shared utilities**: Search (`grep -r`, `Glob`) for existing helper functions, shared modules, and utility files related to the feature under review. Common locations: `lib/`, `utils/`, `shared/`, `common/`, `helpers/`.
2. **Find parallel implementations**: Search for similar logic elsewhere in the codebase. If the new code reimplements something that already exists, flag it as a finding (Major severity minimum).
3. **Trace the full pattern**: When the change touches a pattern (e.g., event dispatch, rate limiting, validation), search for ALL other places that use the same pattern. List them explicitly.
4. **Check constant/enum consumers**: When constants, enums, or types are added or changed, search for all consumers (switch statements, if-else chains, array membership checks, i18n keys, test assertions).

**Evidence requirement**: Every finding that references existing code must include the file path and line number where the evidence was found. Findings without evidence are rejected.

**Ollama seed findings are starting evidence, not authoritative.** When an expert consumes Ollama-generated seed findings (Step 3-3 Round 1 template), the expert retains full responsibility for codebase-wide investigation. Adopting a seed finding without independent verification is a quality-gate failure. Conversely, an empty or `No findings` seed does NOT discharge the expert from performing the full R1-R30 Recurring Issue Check — the seed analyzer has a narrower context window and less domain awareness than the expert sub-agent.

**Anti-pattern: "Missing the forest"**
The following are language-agnostic examples of costly misses from past reviews:
- Rate limiter reimplemented 3 times in separate files when a shared helper already existed
- Encoding/decoding function copied locally instead of importing from the existing shared module
- Event/notification dispatch added in 2 of 6 mutation sites, missed the other 4 (required 3 review rounds)
- Validation constants hardcoded in UI, API schema, AND test mocks instead of imported from a shared constants module
- URL construction helper duplicated in 4 files instead of calling the centralized one

### Finding Quality Standards

**Prohibited finding types:**

1. **Vague recommendations**: "Consider adding tests" or "Error handling could be improved" — must specify WHICH function, WHAT test case, and HOW to handle the error
2. **Untested testability claims**: Before recommending "add a test for X", verify that X is actually testable in the project's test infrastructure. Some surfaces (third-party framework internals, generated code, environment-bound configuration) are not unit-testable; recommending tests for them is unactionable.
3. **Architecture misunderstandings**: Before flagging crypto, auth, or complex domain logic, read the surrounding code to understand the design intent. False alarms — such as flagging a key-derivation output as a "password hash", or treating a per-message authentication tag as a long-term secret — waste review rounds.
4. **Cargo-cult security findings**: Flagging standard library usage as "insecure" without a concrete attack vector. Every security finding must describe: attacker, attack vector, preconditions, and impact
5. **Heuristic-only security restrictions**: Recommending removal of a configuration (e.g., a security-policy directive, an allowed origin, an allowed redirect URI) based on "generally this shouldn't be in production" without verifying the actual use case. Security findings that restrict functionality MUST cite the relevant specification (RFC, OWASP, vendor docs) and explain why the specific use case does not apply. Example of a prohibited pattern: recommending removal of an entry from a security allowlist on a generic heuristic, without checking whether a specification or supported client flow requires that entry
6. **Unverified spec citations**: Before citing an external spec (RFC, NIST SP, OWASP ASVS, OWASP cheat sheet, IETF BCP, ISO/IEC, FIPS, W3C, etc.) in a finding OR in plan/code being reviewed, the expert MUST verify:
   - The section number exists in the cited revision of that document
   - The claimed requirement text or paraphrase actually appears at that section
   - The revision/version is specified when the standard has been revised (e.g., "NIST SP 800-63B-4 §2.3.3" — not bare "NIST SP 800-63B §2.3.3", because section numbers renumber between revisions)
   - Quoted phrases (`"..."`) exist verbatim in the source; paraphrases are marked as such

   Hallucinated citations are worse than no citation — they move a heuristic claim into an authoritative-looking frame that readers will trust without checking. Findings that include unverified citations are returned to the expert for revision. When the expert cannot verify (no network access, paywalled doc), state that explicitly ("citation unverified — please confirm") rather than emitting a confident reference.

**Finding ID convention (mandatory):**

All experts MUST use this ID scheme. The orchestrator rejects any review that mixes prefixes (e.g., `F-01` and `F1` in the same review) or introduces new prefixes for round 2+ findings.

- Functionality expert: `F1, F2, F3, ...`
- Security expert: `S1, S2, S3, ...`
- Testing expert: `T1, T2, T3, ...`
- Round 2+ new findings continue numbering from the previous round and append `(new in round N)` — e.g., `S4 (new in round 2)`. Do NOT introduce new prefixes like `N1`, `M-1`, or `m-1` for round 2 findings.
- [Adjacent] findings keep the originating expert's prefix and append `-A`: e.g., `F3-A`. The routing target expert is named in the finding body, not encoded in the ID.
- IDs are stable across rounds: once a finding is `F2` in round 1, it stays `F2` through resolution.

**Required finding format (code review):**
```
[Finding ID] [Severity]: [Problem title]
- File: [path:line]
- Evidence: [grep output, code snippet, or specific observation]
- Problem: [Concrete description — what is wrong and why]
- Impact: [What breaks, what data is at risk, what users experience]
- Fix: [Specific code change or approach — not "consider improving"]
```

Findings that omit Evidence or provide a vague Fix are returned to the expert for revision.

### Anti-Deferral Rules

**"Out of scope" and "pre-existing" are not free passes.**

1. **Pre-existing issues in changed files**: If a file is already being modified and contains a pre-existing bug, it MUST be flagged (severity based on impact, not on who introduced it). The CLAUDE.md rule "Fix ALL errors" applies. A file is "changed" if it appears in `git diff main...HEAD` for any reason — even a one-line edit puts the entire file in scope.
2. **Out-of-scope finding obligations**: When marking a finding as "out of scope", the expert MUST:
   - State which expert's scope it belongs to (use [Adjacent] tag)
   - Provide enough detail for the other expert to evaluate it
   - Never use "out of scope" to avoid investigating a finding
3. **"Acceptable risk" requires quantification**: Do not accept risks with hand-waving like "acceptable for personal tool" or "low probability." State: what is the worst case, what is the likelihood, and what is the cost to fix. If cost-to-fix is low, fix it.
   - **30-minute rule**: If the estimated implementation cost is under 30 minutes, deferral to a future phase or PR is not allowed. Fix it now. This prevents accumulation of "easy but skipped" items that individually seem harmless but collectively degrade quality. Exception: security-sensitive fixes (auth, crypto, input validation) must complete impact analysis before applying, even if the fix itself appears small — rushing a security change without tracing all affected paths can introduce new vulnerabilities.
4. **Deferred findings must be tracked**: Any finding deferred to a future PR must be recorded in the review log with a clear reason and an explicit "TODO" marker that can be grepped.

**Mandatory format for Skipped / Accepted / Out-of-scope findings (enforcement):**

When the orchestrator records a finding as `Skipped`, `Accepted`, `Out of scope`, or `Pre-existing` in Resolution Status, the entry MUST follow this format. Resolution Status entries that omit the Anti-Deferral check are invalid and must be returned for revision before commit.

```markdown
### [Finding ID] [Severity] [Title] — [Skipped|Accepted|Out of scope|Pre-existing]
- **Anti-Deferral check**: [which exception applies — one of the four below]
- **Justification**:
  - If "pre-existing in changed file" → NOT ALLOWED. Must fix, or escalate to user with explicit user approval recorded here. Cite the diff line that proves the file is in scope.
  - If "pre-existing in unchanged file" → Provide [Adjacent] routing: name the expert who should evaluate it, and the file:line. Do not silently drop.
  - If "acceptable risk" → State three values explicitly:
    - Worst case: [concrete impact]
    - Likelihood: [low/medium/high with reason]
    - Cost to fix: [LOC, time, or risk of regression]
    Phrases like "acceptable for personal tool", "low probability", "negligible", "edge case" without these three values are PROHIBITED.
  - If "out of scope (different feature)" → Cite the plan/issue that tracks it, OR create a TODO marker (`TODO(plan-name): ...`) that can be grepped.
- **Orchestrator sign-off**: [explicit confirmation that one of the four exceptions above is satisfied]
```

Examples of REJECTED skip entries (from past reviews — do not repeat):
- "Acceptable degradation; cache is an optimization, not a requirement" → missing worst case / likelihood / cost
- "Acceptable for personal developer tool" → forbidden phrase, no quantification
- "Pre-existing issue in [file already in this diff], not introduced by this change" → the file IS in the diff, so it is in scope; must fix or escalate
- "Out of scope for this refactoring" → no [Adjacent] routing, no other expert assignment, no TODO marker

### Expert Agent Obligations

**Do not override test-verified behavior with general heuristics**
When a finding recommends changing a configuration or behavior that was previously tested and confirmed working (e.g., during implementation or E2E testing), the burden of proof is on the finding. The expert MUST:
- Cite a specific specification (RFC, OWASP rule, language spec) — not "generally you shouldn't do X"
- Explain why the tested scenario does not apply, with a concrete counter-example
- If unable to provide spec-level evidence, downgrade to an informational note, not a finding

Illustrative scenario: a security review recommends removing a configuration entry (e.g., a localhost entry from a security policy / redirect allowlist) from production based on a generic "this should not appear in production" heuristic. If a tested authentication or callback flow requires that entry per the relevant specification (e.g., a native-app OAuth flow that mandates localhost callbacks), accepting the finding breaks verified behavior. The orchestrator must demand spec-level evidence and re-run the affected flow before applying any fix that reverses a previously-tested configuration.

**Do not modify production code to simplify test setup**
When a production API provides both a safe variant (e.g., parameterized queries, tagged templates, structured builders) and an unsafe escape hatch, never switch from safe to unsafe solely to simplify test setup. If the safe API is harder to mock, adapt the test infrastructure (mock shape, test helper, or fixture) to match the safe API — not the other way around. The test must prove the production code works correctly, not that the test is easy to write. This obligation applies equally to the functionality expert (correctness) and the testing expert (test quality).

**Do not fabricate technical justifications**
When comparing design options, each technical argument must be independently valid. If the true differentiator is implementation cost, state that explicitly — never present cost preference as an architectural constraint. Experts must challenge any argument that conflates "harder to implement" with "technically incompatible."

**Do not blindly follow existing patterns**
When implementation follows an existing codebase pattern, each expert MUST explicitly evaluate: "Is the existing pattern correct, or is it a latent bug we are propagating?" In particular:

- If a field stores UUIDs, writing non-UUID values (e.g., sentinel strings like `"bulk"`) must be flagged regardless of existing code
- If a value is stored by one endpoint and read by another, verify the value is valid for both the write schema and the read query

**Verify type definitions before proposing value changes**
Before changing any value in a function call or object literal, read the type/schema definition of the target field. Common mistakes:

- Optional vs nullable: optional fields may not accept explicit null (e.g., `undefined` ≠ `null` in languages that distinguish them)
- Schema validators may reject values that the language's type system accepts (e.g., a UUID-format validator rejects arbitrary strings even if the static type is `string`)

This applies to both the Plan phase (pseudocode) and the Code Review phase (actual code).

**Verify citations, do not fabricate them**
When a finding, recommendation, or deferral justification references an external standard (RFC, NIST SP, OWASP ASVS, OWASP cheat sheet, IETF BCP, ISO/IEC, FIPS, W3C), the expert's default state is that the citation is unverified. To elevate it to a cited authority, the expert MUST have confirmed all four (matching the Finding Quality Standards "Unverified spec citations" rule):

1. The section number exists in the cited revision.
2. The paraphrase or quote actually appears at that section.
3. The revision is specified when the standard has been revised (e.g., "SP 800-63B-4 §2.3.3", not bare "SP 800-63B §2.3.3").
4. Quoted phrases (in backticks or quotes) appear verbatim in the source; paraphrases are explicitly marked as such.

If verification is not possible in the current environment (no network, paywalled), either:
- Cite the standard without a specific section number, and flag the claim as `citation unverified — please confirm before action`
- Rely on an orthogonal argument (attack vector, spec-free reasoning) instead of appealing to authority

Retrofitting a number after the claim is written ("I need a spec reference — §4.2.3 sounds right") is the exact failure mode that produces hallucinations. The section number must come out of verification, not recall.

**Propagation sweep must include comment / doc / test-title sites**
When a citation correction is applied, the R3 propagation sweep must grep not only the primary doc but also every place where the same standard might be cited:

- Source-code comments and structured doc-comment blocks referencing the same standard
- Test case names / descriptions that embed section numbers (e.g., a test description string referencing `... (RFC 8252 §8.3)`)
- Commit messages and PR bodies that cite the standard
- Allowlist/safelist rationale that cites the standard
- Security-relevant docs and operational artifacts where citations carry decision weight: threat models, `SECURITY.md`, ADRs (architecture decision records), runbooks, incident reports, post-mortems, audit responses, release-notes security callouts, on-call escalation docs

Citation drift inside comments, test names, and operational docs is the form of hallucination that most often survives review because the R3 scan often targets only the primary doc. A single grep by the bare standard name is the cheap catch-all — adapt the search term to the standard family (e.g., `grep -rn "RFC 8252"` for an IETF citation; `grep -rn "ASVS V[0-9]"` for an OWASP ASVS chapter reference; `grep -rn "SP 800-63"` for a NIST SP family). Run the appropriate variant for every standard touched by the correction.

**Check runtime environment constraints against security-relevant minimum values**
When the plan proposes a minimum value for a security-relevant interval (token TTL, session idle timeout, auto-lock, retention window, grace period, re-authentication interval), the expert MUST check the value against the actual runtime constraints of the deployment target, not just the spec-mandated range:

- Background-task dormancy / suspension windows (e.g., background service worker or worker thread suspension; mobile app backgrounding; serverless cold-start)
- Timer / alarm granularity floors provided by the runtime
- Network round-trip jitter for refresh / renewal flows

Security values smaller than the sum of these jitters are "compliant on paper but broken in practice" — a session set to auto-lock after 5 minutes in a runtime whose background work is suspended every 5 minutes will either never fire (fail-open) or always fire prematurely (fail-closed). **Fail-open is the materially worse direction** for the listed examples: an auto-lock that never fires leaves a privileged surface open, while one that always fires is an annoying false positive but preserves the security property. When both directions are possible, flag based on the worse direction.

**Flag as Major even if the value is within the spec-mandated range** — this obligation applies specifically to security-relevant interval minimums against runtime jitter; it is not a general license to override spec compliance elsewhere.

Concrete trigger: any security-relevant minimum interval at or below the deployment runtime's dormancy window. Decision procedure for borderline values (note: the "dormancy window" is a distribution with a tail — battery saver, thermal throttling, nested suspension, network disconnection can extend it substantially — use the p99 or documented worst case, NOT the median):
- If the proposed value ≤ 1× the worst observed dormancy window → Major (fail-open likely)
- If the proposed value is between 1× and 3× the worst observed dormancy window → Minor + require an empirical test against the actual runtime (real wall-clock, NOT fake timers / simulated time), demonstrating the interval fires correctly under dormancy
- If the proposed value ≥ 3× the worst observed dormancy window → no finding on this axis, UNLESS the runtime's tail is known to be unbounded (user-controlled battery-saver, OS-level thermal suspension with no cap) — in that case fall back to the mid-band test requirement

Interaction with R21 (Subagent completion vs verification): R21's security-relevant test-path re-run obligation focuses on code diffs; this obligation focuses on value/constant choices. Both apply independently — changing a security-relevant interval invokes this rule AND, if touched by a subagent, R21 as well.

### Known Recurring Issue Checklist

These issues have been found repeatedly in past reviews. Every expert MUST explicitly check for these patterns and report their findings (even if "not applicable" — this confirms the check was performed).

**All experts must check:**

| # | Pattern | What to grep/check | Severity if missed |
|---|---------|--------------------|--------------------|
| R1 | Shared utility reimplementation | `grep -r` for existing helpers (rate limiters, validators, encoders, formatters) before accepting new implementations | Major |
| R2 | Constants hardcoded in multiple places | Search for literal values that should be shared constants (validation limits, enum values, config defaults) | Major |
| R3 | Incomplete pattern propagation | When a pattern is changed in one file, search for ALL other files using the same pattern. **Flagged-instance enumeration obligation**: when a user or reviewer flags a single instance of an anti-pattern, the reviewer MUST enumerate every other instance of the same anti-pattern in the same response — not only fix the flagged one. "Fix what was pointed out and nothing else" defers the other instances to the next review round and wastes rounds on avoidable repetition | Critical if security-relevant, Major otherwise |
| R4 | Event/notification dispatch gaps | When mutations are added, verify ALL similar mutation sites dispatch the corresponding event | Major |
| R5 | Missing transaction wrapping | A read query (e.g., listing rows) followed by a separate write query (update/delete) without wrapping both in a DB transaction — the row set may change between read and write (TOCTOU race). Note: unit tests with mocked DB calls pass vacuously because the mock returns a stable result; only integration tests under concurrent load expose the race | Major |
| R6 | Cascade delete orphans | DB cascade deletes that don't clean up external storage (blob store, file system, cache) | Major |
| R7 | E2E selector breakage | When routes, CSS classes, exports, aria-label, id, data-testid, or data-slot are changed/deleted, check E2E tests for broken references | Major |
| R8 | UI pattern inconsistency | When adding/restyling list, card, or form components, verify style patterns match existing same-category components | Minor |
| R9 | Transaction boundary for fire-and-forget | Async dispatch launched without awaiting/joining its completion inside a DB transaction scope inherits the transaction's async context — the transaction may close before the dispatched work completes, causing runtime errors. Move fire-and-forget calls outside the transaction | Critical |
| R10 | Circular module dependency | A imports B and B imports A — module initialization order may produce `undefined`. Refactor to unidirectional dependency or use lazy imports on both sides | Major |
| R11 | Display group ≠ subscription group | UI display grouping (e.g., audit log filters) and event subscription grouping (e.g., webhook topics) serve different purposes. Reusing one for the other causes scope leakage or update gaps when new features are added | Major |
| R12 | Enum/action group coverage gap | Every action value used in logging/audit calls must be registered in the corresponding group definition, i18n labels, UI label maps, and tests. Search all call sites and cross-check against group arrays | Major |
| R13 | Re-entrant dispatch loop | Event delivery failure → audit log → triggers new event delivery → infinite loop. Delivery-failure actions must be on a dispatch suppression list | Critical |
| R14 | DB role grant completeness | When creating a new DB role, verify grants cover all implicit operations the application code performs — not just the literal statement. Examples: conflict-resolution clauses on writes may require read permission in addition to write; foreign-key validation may require read permission on the referenced table; row-level-security modes may add further requirements. Note: insufficient grants cause functional failures (Major); over-privileged grants that bypass security boundaries or expose unauthorized data are Critical | Major (Critical if over-privilege direction) |
| R15 | Hardcoded environment-specific values in migrations | Database names, role names, hostnames, and other environment-dependent values must not be hardcoded in migration SQL. Use dynamic resolution (e.g., `current_database()`, environment variables, or templating) so migrations work across dev, CI, staging, and production. Note: hardcoded values also persist in git history, potentially leaking production infrastructure topology | Major |
| R16 | Dev/CI environment parity | When tests assert database privileges, row-level/permission policies, or role-specific operations, verify the assertion holds in both local dev (often a high-privilege owner role) and CI (minimal roles created by setup scripts). Common divergences: implicit grants held only by privileged/admin roles, row-level-security bypass on privileged roles, default-privilege scope, and the order in which container-init scripts run relative to migrations | Major |
| R17 | Helper adoption coverage | When the PR introduces a new shared helper, enumerate every call site of the underlying primitive the helper wraps and verify each either uses the helper or has a concrete skip reason — do not rely on pattern-surface search alone (see Extended obligations below) | Major |
| R18 | Config allowlist / safelist synchronization | When privileged operations (elevated DB access, admin-only APIs, escape hatches) move into or out of files, verify any project-defined allowlist/safelist that gates their usage is updated in both directions — add new users, AND remove (or narrow) entries ONLY when the privileged call provably moved into a shared helper that itself appears on the allowlist (never just because the literal call disappeared from one file). Removing an entry without confirming the new call site is itself gated widens blast radius | Major |
| R19 | Test mock alignment with helper additions | When a new export is added to a module whose mocks are declared elsewhere (in-test mock factories, manual mock files, test fixtures), enumerate every mock declaration for that module and confirm the new export is represented AND covered by at least one assertion — otherwise tests either fail at import time or pass vacuously because the new symbol is `undefined`/no-op when invoked. **Exact-shape assertion obligation**: when a reviewed struct / interface / payload gains a new field, grep for exact-shape equality assertions on that type and update them. "Exact-shape" means assertions that fail when a new field appears — identify these by searching the test files for the framework's strict/deep equality primitives (common spellings across frameworks: `deepEqual`/`deepStrictEqual`, `assertEqual`/`assert_equal`, `toEqual`/`toStrictEqual`/`toBe`, `should.eql`, `==` on records in typed languages). Partial-match assertions ("matches"/"contains"/"includes") are NOT a substitute, they let the shape test stale silently when fields are added | Major |
| R20 | Multi-statement preservation in mechanical edits | When code is inserted mechanically (by scripts or sub-agents) into structured constructs such as multi-line import lists, switch/case blocks, or chained builders, verify the insertion did not split an unrelated existing construct. Concrete reviewer actions: (a) grep for the project's block-opening token immediately followed by another block-opening token with no matching closer in between (the exact regex depends on the project's syntax); (b) run the project's parser/linter — most syntax-aware tools surface the broken structure as a parse error, often with a more useful location than a textual grep | Major |
| R21 | Subagent completion vs verification | A subagent's "completed successfully" report states intent, not outcome. Before accepting: (a) re-run the project's full test command yourself (not just the agent's summary or a subset of tests it picked), (b) spot-check at least one modified file, (c) for large changes (rule of thumb: 50+ files) additionally re-run lint AND tests AND production build AND any project-defined pre-PR/CI hooks. When the subagent touched auth, crypto, input validation, permission grants, or other security-sensitive surfaces, re-run the security-relevant test path explicitly AND complete the R3 propagation check (trace all affected paths, confirm no propagation gap) even if the change appears small | Critical (silent regression risk) |
| R22 | Perspective inversion for established helpers | Supplements R17. Every review that touches a shared helper must check BOTH perspectives: forward (does the PR migrate consumers?) and inverted (does the PR leave any syntactically-different equivalent pattern untouched?) | Major |
| R23 | Mid-stroke input mutation in UI controls | UI input handlers that apply range/clamp/validation on every keystroke prevent users from typing valid multi-character values (e.g., a value of "15" on the way to "150" gets rejected or rewritten the moment it is below the minimum). Keystroke-level handlers should strip only obviously-invalid characters; range/min/max enforcement must run at commit time (blur, submit, save). Check: grep change/input handlers for clamp/min/max/parse calls that operate on raw user input before commit. **Security angle**: for security-relevant numeric inputs (token lifetime, session timeout, rate limit thresholds), mid-stroke clamp silently coerces the user-entered value into something they did not intend — verify the committed value equals what the user entered at blur/submit, not the clamped intermediate | Major |
| R24 | Single migration mixing additive + strict constraint | Adding a new required column/field (non-null without a default) and updating all consumers in a single migration creates a type-error window for every consumer that has not yet been migrated. Split into (1) additive nullable/defaulted + backfill, (2) flip to the strict constraint after all callers are updated. The two steps may share a PR but MUST be separate migrations. Applies equally to typed schema changes in any storage backend that generates typed clients. **Security angle**: when the new field governs authorization/tenancy/identity (e.g., `tenant_id`, `role`, `owner_id`), the mid-migration window is an authz-bypass window — a request hitting a half-migrated instance can read/write rows whose access would be denied under the final schema. **Testing obligation**: verify the intermediate state (after step 1, before step 2) with CONCURRENT writers including at least one caller that has NOT yet been updated to use the new field — a serial test or a test where all callers have been updated passes vacuously; the authz-bypass window manifests only when interleaved pre-migration and post-migration requests hit the half-migrated state simultaneously | Major |
| R25 | Persist / hydrate symmetry | When a new field is added to state that crosses process / session / restart boundaries (browser or session storage, DB, file, cache, keychain, secure enclave), both the persist path AND the hydrate path must be updated. Write-only adds cause silent data loss on restart — hard to reproduce in tests that do not cross the boundary. Check: pair save/persist functions with their load/hydrate counterparts and confirm the new field appears on both sides. **Security angle**: for auth tokens, revocation lists, encryption material, consent flags, and audit-trail fields, write-only adds are not "data loss" but silent security downgrade — on restart the system reverts to a pre-policy state (un-revoked tokens appear valid again, consent appears never granted, encryption material missing). Name such fields explicitly when flagging. **Testing obligation**: a round-trip test that crosses a TRUE process / worker / container boundary (new process, cold worker, restarted container) — NOT a same-process in-memory reinstantiation or cache clear — is required. The test must: persist the field → cross the boundary → hydrate → assert the field equals what was persisted. Tests that mock both persist and hydrate in the same process, or that only reinstantiate the in-memory state, cannot catch the symmetry gap | Major |
| R26 | Disabled-state UI without visible cue | When a UI control gains a logical disabled/readonly state, a visual indication of that state must be present too — the logical attribute alone leaves users believing the control is broken or unresponsive. Applies to any styling system (utility classes, component variants, style tokens): every control that sets a disabled/readonly attribute needs a paired visual style rule for that state. Check: grep for controls with disabled/readonly attributes and verify each one has a paired disabled-state style rule (class, variant, style prop, or CSS pseudo-state) — an attribute without a paired style is a finding | Minor |
| R27 | Numeric range hardcoded in user-facing strings | Translation or UI strings that embed numeric limits (e.g., "between 5 and 1440 minutes", "max 100 items") drift from the validation constants over time. Use interpolation placeholders and pass the value from the canonical constant at the call site. Check: in the diff's translation/UI-string files, grep for numeric literals that duplicate MIN/MAX validation constants — any match is a finding. Excluded from this check: numbers that are domain-literal, not limits (e.g., year literals like `2026`, HTTP status codes like `404`, version numbers like `1.0`). **Severity escalation**: Minor by default; escalate to Major when the drifting constant governs ANY security or privacy policy boundary — auth credentials, rate limits, password policy, session/token lifetime, MFA grace period, lockout threshold, key rotation interval, consent flag, data retention window, audit threshold, or any other policy value with security or privacy implications. User-facing text that claims a looser limit than the tightened policy actively encourages users to attempt disallowed values, erodes trust in the UI when the limit is hit, and creates audit-log discrepancies | Minor (Major when constant governs any security or privacy policy boundary) |
| R28 | Grammatical inconsistency in toggle/switch labels | Toggle/switch controls across the app should use a single grammatical form for their labels (e.g., all verb-form "Enable X" vs all noun-form "X enabled"). Mixed forms make it ambiguous whether the label describes the control's ON state or its OFF state. Enumerate adjacent toggle/switch labels in the affected feature area and verify form consistency. Note: this is primarily a human-review check — automated detection requires NLP beyond what a grep can do; the review action is to list the labels and judge visually | Minor |
| R29 | External spec citation accuracy | When citing an RFC / NIST / OWASP / W3C / FIPS / ISO document, verify all four: (1) the cited section exists in the cited revision, (2) the quoted/paraphrased text actually appears at that section, (3) the revision is disambiguated when the standard has been revised and section numbers have shifted, (4) quoted phrases (in backticks or quotes) appear verbatim in the source; paraphrases are explicitly marked as such. Sources of drift commonly seen: NIST SP 800-63B Rev 3 → Rev 4 renumbered reauthentication sections AND changed AAL2 values; OWASP ASVS 4.0.3 → 5.0 renumbered chapters. **Illustrative past-hallucination patterns** (user-reported from prior reviews; pin revisions and re-verify against the source before citing in new findings): confidently citing a section number where the named topic actually lives elsewhere; quoting wording that does not appear verbatim in the source; omitting the revision when section numbers have shifted between revisions. **Severity**: Major by default (trust damage to future readers — they act on wrong info because the citation looks authoritative). **Escalate to Critical** when the hallucinated citation directly drives a security decision (recommending disabling a control, widening an allowlist, loosening a crypto parameter, raising a session lifetime) — in that case the wrong "authority" causes immediate security regression, not just trust erosion. See "Verify citations, do not fabricate them" in Expert Agent Obligations | Major (Critical when the hallucinated citation drives a security-tightening or security-loosening decision) |
| R30 | Markdown autolink footguns in citations | When writing citations in PR bodies, commit messages, or Markdown docs hosted on GitHub-flavored Markdown surfaces, avoid constructs that auto-link unintentionally: bare `#<number>` becomes a PR/issue link; bare `@<name>` becomes a user mention; bare commit-SHA-shaped hex becomes a commit link. **Confidentiality / disclosure angle**: an unintended `@<name>` notifies an uninvolved party (information disclosure if the PR discusses an embargoed fix); an unintended `#<n>` creates a backlink visible to watchers of the referenced issue (leaks the existence of the new PR's content to that issue's watchers). Workarounds (preferred order — preserve original phrasing): (a) wrap in backticks (`` `#6` ``); (b) escape (`\#6`); (c) only as a last resort, drop the `#` ("tenet 6" instead of `"tenet \#6"`) because dropping the marker changes the document's semantic content. Check (grep example): `grep -nE '(^|[^a-zA-Z0-9])#[0-9]+' file.md` to enumerate bare `#<number>` occurrences in a Markdown file. Applies to both the doc being reviewed and the review output itself. Scope: GitHub-hosted repos and any tool that renders GitHub-flavored Markdown identically; for repos hosted on other platforms with different autolink rules, adjust accordingly | Minor |

See "Extended obligations (R17-R22)" below for full procedures on R17-R22. R23-R28 are self-contained in the table row above.

**Security expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RS1 | Timing-safe comparison | Any credential/token/hash comparison using `===` or `!==` instead of `timingSafeEqual` | Critical |
| RS2 | Rate limiter on new routes | Every new API endpoint must have rate limiting (check if shared rate limiter exists) | Major |
| RS3 | Input validation at boundaries | New request parameters must be validated/sanitized at the schema level, not deep in business logic | Major |

**Testing expert must additionally check:**

| # | Pattern | What to check | Severity |
|---|---------|---------------|----------|
| RT1 | Mock-reality divergence | Mock return values must match actual API response shapes | Critical |
| RT2 | Testability verification | Before recommending "add test for X", confirm X is testable with the project's test infrastructure | — (reject finding if untestable) |
| RT3 | Shared constant in tests | Test assertions using hardcoded values that should import from shared constants | Major |

### Extended obligations (R17-R22)

These obligations extend the checklist above with full procedures. Each maps to a row in the table and MUST be applied by every expert (unless scoped otherwise).

**R17: Helper adoption coverage**

When the PR introduces a new shared helper, the reviewer MUST verify adoption coverage across the codebase — not just the sites the PR changed.

Procedure:
1. Identify the underlying primitive the helper wraps (the function, API, or operation that existed before the helper was extracted).
2. Enumerate every call site of that primitive.
3. For each call site, determine whether it uses the new helper. For non-users, require the PR to either migrate OR document a concrete skip reason (a specific reason why the helper does not apply to that call site).

Finding this gap after merge leaks as latent duplication — callers keep the pre-helper pattern alive.

**R18: Config allowlist / safelist synchronization**

When the PR changes which files use privileged operations (e.g., elevated DB access, admin-only APIs, security escape hatches that the project gates with an allowlist), the reviewer MUST verify the corresponding allowlist/safelist files have been updated in both directions:

- **Add** new files that now use the privilege.
- **Remove (or narrow)** entries for files that no longer need it BECAUSE the privileged call moved into a shared helper. This removal is valid only when (a) the helper itself appears on the allowlist (or is otherwise gated), and (b) all call sites of the helper are themselves on the allowlist/safelist or behind an equivalent higher-privilege gate. Removing an entry merely because the literal call disappeared from one file — without confirming the new call site is gated — widens blast radius and must be flagged.

How to discover the allowlist for the project: search the repo for scripts referenced by pre-commit/pre-push/CI hooks that enumerate file paths and check for forbidden imports or calls. A missing update typically fails the project's pre-PR verification.

**R19: Test mock alignment with helper additions**

When the PR adds a new exported function to a module whose mocks are declared elsewhere, those mock declarations MUST be updated to include the new export. Otherwise tests either fail at import time or pass vacuously — the new symbol resolves to `undefined`/no-op when invoked under the mock, masking real failures.

Procedure when a helper is added to a mockable module:
1. Identify every place the module is mocked (search the codebase for the module's import path or name appearing in a mocking call, manual mock file, or test fixture).
2. For each, confirm the mock either re-exports the real module's surface (delegating to the original implementation) or explicitly lists the new export.
3. Confirm at least one test asserts on the result of calling the new export through the mock — a mock declaration with no asserting test is the same vacuous-pass failure mode as omitting the export entirely.

This applies regardless of test framework — every framework that supports module mocks has the same exposure.

**Exact-shape assertion obligation** (companion to the above): when a reviewed struct / interface / payload gains a new field, grep the test files for exact-shape equality assertions on that type and update them. "Exact-shape" means assertions that will fail when a new field appears — identify by the framework's strict/deep equality primitives (common spellings across frameworks, illustrative only: `deepEqual` / `deepStrictEqual`, `assertEqual` / `assert_equal` / `assertEquals` / `assert_eq!`, `toEqual` / `toStrictEqual` / `toBe`, `should.eql`, `==` on records in typed languages). Partial-match assertions ("matches", "contains", "includes", "matchObject") are NOT a substitute — they let the shape test stale silently when fields are added. Update or replace the stale exact-shape assertions in the same PR.

**R20: Multi-statement preservation in mechanical edits**

When using scripts or subagents to insert code mechanically into structured constructs (multi-line import lists, switch/case blocks, chained builder calls, table-driven configs), verify the insertion did not split an unrelated adjacent construct.

Common failure mode: an insertion point computed from a single anchor line lands *inside* a previous multi-line construct instead of between two top-level constructs, producing invalid syntax.

Reviewer action: after a mechanical edit, grep for syntactic markers of broken structure (e.g., a construct opener immediately followed by a different construct's contents with no closer in between). When detected, fix the script's insertion point or manually repair the affected location.

**R21: Subagent completion vs verification**

A subagent's "completed successfully" report states intent, not outcome. Before accepting the result:

1. Re-run the project's full test command yourself (not just the agent's summary or whatever subset of tests it chose to run). "Full test command" means the same target the project documents/uses for pre-PR verification — typically the `test` script in the package manifest, the project's `Makefile` test target, or the command listed in the project README.
2. Spot-check at least one modified file to confirm the change matches the described migration.
3. If the agent modified many files (rule of thumb: 50+), additionally re-run lint AND tests AND production build AND any project-defined pre-PR/CI hooks — subagents have been observed to produce partial migrations that pass unit tests but fail full project verification (e.g., missing dependency updates, missed cross-cutting refactors).

**Security carve-out (parallel obligation, applies in addition to steps 1-3 above)**: when the subagent touched auth, crypto, input validation, permission grants, or other security-sensitive surfaces, re-run the security-relevant test path explicitly even if the change appears small AND complete the R3 propagation check (trace all affected paths, confirm no propagation gap) before accepting. A single-line edit in this category can introduce a vulnerability that unit tests do not exercise.

**R22: Perspective inversion for established helpers**

Supplements R17. During code review, whenever the PR introduces or uses a shared helper, reviewers MUST explicitly check two perspectives:

1. **Forward**: "Does the PR migrate consumers to the helper where the helper applies?"
2. **Inverted**: "Does the PR leave any equivalent pattern untouched because the syntactic search didn't match?"

The inverted perspective catches cases where the pre-helper code expressed the same intent with a different spelling (different identifier, different equivalent literal, different equivalent call shape). A pattern-only forward search misses these — only enumerating from the underlying primitive surfaces them.

Each expert must include a "Recurring Issue Check" section in their output:
```
## Recurring Issue Check
- R1 (Shared utility reimplementation): [Checked — no issue / Finding F-XX]
- R2 (Constants hardcoded): [Checked — no issue / Finding F-XX]
- R3 (Pattern propagation + Flagged-instance enumeration): [Checked — no issue / Finding F-XX]
- R4 (Event dispatch gaps): [N/A — no mutations / Finding F-XX]
- R5 (Missing transactions): [N/A — no multi-step DB ops / Finding F-XX]
- R6 (Cascade delete orphans): [N/A — no deletes / Finding F-XX]
- R7 (E2E selector breakage): [Checked — no issue / Finding F-XX]
- R8 (UI pattern inconsistency): [Checked — no issue / Finding F-XX]
- R9 (Transaction boundary for fire-and-forget): [N/A — no async dispatch in tx / Finding F-XX]
- R10 (Circular module dependency): [Checked — no issue / Finding F-XX]
- R11 (Display group ≠ subscription group): [N/A — no event grouping / Finding F-XX]
- R12 (Enum/action group coverage gap): [N/A — no audit actions / Finding F-XX]
- R13 (Re-entrant dispatch loop): [N/A — no event dispatch / Finding F-XX]
- R14 (DB role grant completeness): [N/A — no new DB roles / Finding F-XX]
- R15 (Hardcoded env values in migrations): [N/A — no migrations / Finding F-XX]
- R16 (Dev/CI environment parity): [N/A — no DB role/privilege tests / Finding F-XX]
- R17 (Helper adoption coverage): [N/A — no new helper / Checked — no issue / Finding F-XX]
- R18 (Allowlist/safelist sync): [N/A — no privileged-op changes / Checked — no issue / Finding F-XX]
- R19 (Test mock alignment + Exact-shape assertion obligation): [N/A — no new exports in mocked modules / Checked — no issue / Finding F-XX]
- R20 (Multi-statement preservation in mechanical edits): [N/A — no mechanical insertions / Checked — no issue / Finding F-XX]
- R21 (Subagent completion vs verification): [N/A — no subagent-driven changes / Checked — tests+build re-run / Finding F-XX]
- R22 (Perspective inversion for helpers): [N/A — no helper introduced or used / Checked — both perspectives / Finding F-XX]
- R23 (Mid-stroke input mutation): [N/A — no UI input handler changes / Checked — no issue / Finding F-XX]
- R24 (Migration additive+strict split): [N/A — no schema/migration changes / Checked — no issue / Finding F-XX]
- R25 (Persist/hydrate symmetry): [N/A — no persisted-state field additions / Checked — both sides updated / Finding F-XX]
- R26 (Disabled-state visible cue): [N/A — no UI disabled-state changes / Checked — no issue / Finding F-XX]
- R27 (Numeric range in user-facing strings): [N/A — no translation/UI-string changes / Checked — no issue / Finding F-XX]
- R28 (Toggle label grammatical consistency): [N/A — no toggle/switch changes / Checked — no issue / Finding F-XX]
- R29 (External spec citation accuracy): [N/A — no spec citations / Checked — citations verified / Finding F-XX]
- R30 (Markdown autolink footguns): [N/A — no Markdown citations / Checked — no issue / Finding F-XX]
- [Expert-specific checks as applicable]
```

### Severity Classification Reference

Each expert uses their own severity criteria. When populating `[Expert-specific severity definitions]` in prompt templates, use the definitions below.

**Functionality expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | Requirements not met, data corruption, infinite loop/deadlock | Must fix immediately |
| Major | Logic error, unhandled edge case, architecture violation | Must fix |
| Minor | Naming, code structure, readability | Fix if straightforward, otherwise user decides |

**Security expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | RCE, auth bypass, SQLi/XSS, sensitive data exposure | Must fix immediately |
| Major | Insufficient access control, crypto misuse, SSRF | Must fix |
| Minor | Missing headers, excessive logging | Fix if straightforward, otherwise user decides |
| Conditional | Deprecated algorithms — Minor by default; escalate to Critical if used for authentication credentials, password hashing, or data integrity verification | Depends on context |

**Testing expert:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | No tests for critical path, false-positive tests (always pass) | Must fix immediately |
| Major | Insufficient coverage, flaky tests, mock inconsistency | Must fix |
| Minor | Test naming, assertion order, test redundancy | Fix if straightforward, otherwise user decides |
