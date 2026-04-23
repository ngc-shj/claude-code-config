---
name: simplify
description: "Review changed code for reuse, quality, and efficiency, then fix any issues found. Use this skill when: asked to simplify or clean up code; asked to find duplication or refactoring opportunities; asked to improve code quality of recent changes."
---

# Simplify Skill

Reviews changed or specified code for simplification opportunities: duplication, complexity hotspots, and efficiency improvements.

---

## Step 1: Determine Scope

Determine what to analyze based on user instructions:

| User instruction | Scope |
|-----------------|-------|
| No specific target | Current branch diff vs main |
| Specific file(s) mentioned | Those files only |
| "Whole codebase" / "everything" | Full project scan |

```bash
git diff main...HEAD --stat  # Understand what changed
```

## Step 2: Local LLM Pre-analysis (Zero Claude Tokens)

First, inventory existing shared utilities to inform reuse proposals:

```bash
bash ~/.claude/hooks/scan-shared-utils.sh
```

Then run pre-screening to identify complexity hotspots and duplication:

```bash
bash ~/.claude/hooks/pre-review.sh code
```

The local LLM will analyze changes focusing on:
- Complexity hotspots (long functions, deep nesting)
- Repeated code patterns
- Unused imports or dead code
- Simplification opportunities

Also pre-screen reuse candidates against the shared utility inventory so Sonnet enters Step 3 with filtered matches instead of re-deriving them:

```bash
{ bash ~/.claude/hooks/scan-shared-utils.sh
  echo '=== OLLAMA-INPUT-SEPARATOR ==='
  git diff main...HEAD
} | bash ~/.claude/hooks/ollama-utils.sh score-utility-match
```

The output is a set of `[High|Medium|Low] path:line — Proposal — Candidate` blocks (or `No matches`). Feed these into the Step 3 sub-agent prompt as seed candidates; the sub-agent still performs verification and may discard low-confidence matches.

If Ollama is unavailable, proceed to Step 3 without pre-analysis.

Save the output for reference in Step 3.

## Analysis Obligations (applies to Step 3 sub-agent and any direct analysis)

These obligations MUST be applied during deep analysis, in addition to the basic simplification categories (duplication / complexity / reuse / verbosity). They exist because pattern-surface searches consistently miss systemic issues — each rule below was derived from real cases where a narrower approach shipped silent debt.

### Inverted search: start from helpers, not patterns

When a shared helper exists, searching for the *pattern it replaces* misses call sites whose syntax happens to differ. Always run BOTH searches:

1. **Pattern search** (the obvious angle): grep for the literal value, configuration key, or syntactic shape that the helper supersedes.
2. **Inverted search** (the stronger angle): enumerate every call site of the underlying primitive (the function, API, or operation that the helper wraps) and for each, check whether it uses the established helper. If not, document why (legitimate exemption) or migrate it.

Why this matters: a literal pattern search only finds adoption gaps that share the same spelling. Inverting from the primitive surfaces gaps that the helper *should* cover but the original code expressed differently (different identifier, different equivalent value, different call shape). The pattern-only view ships those as silent debt.

Apply this to every helper extracted in the current session — once a helper is created, immediately invert the search to confirm adoption coverage.

### Meta-pattern generalization step

After fixing N specific findings in a session, step back and ask: "each finding is an instance of what broader meta-pattern?" Then search for other instances of that same meta-pattern.

Generic themes to consider (adapt the surface syntax to the project's language and frameworks):
- Sequential async/blocking calls inside a loop that could be parallelized or batched.
- Manual record/object reshape repeated across files that could be a single transform helper.
- Module-level cache/registry without a size bound or eviction policy.
- Small allowlist collection queried repeatedly via linear scan that could be a hash-set lookup.
- Duplicate inline validation/schema definitions for the same shape.
- Double cast through an intermediate type used to bypass type checks.

Most findings don't replicate by accident — the codebase has systemic habits that produce them. Fixing one instance without searching for siblings leaves the habit alive.

### O(n) / O(n²) hidden in loops

Search for hot paths where work that should be O(1) or O(n) is performed inside an iteration:

- A linear-lookup function (find / search / contains) called inside an outer loop or per-item map.
- Repeated containment checks on the same collection across many requests, renders, or events.
- Nested loops where the inner loop iterates a list that could be indexed once into a hash map.

Fix pattern: build an index (hash map / dictionary) once outside the loop, then look up inside. When the caller re-runs frequently (e.g., per render in a UI framework, per request in a service), memoize the index appropriately. When the helper is reused across call sites, offer a bulk variant that computes all keys in one pass alongside the per-item variant.

### Parallel-implementation drift check

When the repo has parallel implementations of the same logic in separate trees (separate package, CLI vs library, server vs worker, frontend vs backend mirror), treat each pair as a drift risk surface.

Minimum action: add a mirror-comment block on each side pointing to its counterpart, with explicit wording that any format change requires updating both. Stronger action: shared fixtures, a shared module, or extraction to a published package.

Also confirm: additions on one side (a new constant, a new helper, a new branch in a switch) must land on the other side in the same PR.

## Step 3: Sonnet Deep Analysis (Sub-agent)

Launch a Sonnet sub-agent to explore the codebase and generate concrete proposals:

```
You are a senior engineer specializing in code simplification.

Local LLM pre-analysis (for reference — do not re-report):
[Local LLM output, or "None"]

Seed reuse candidates (from score-utility-match — verify before recommending, discard Low-confidence if not justified):
[score-utility-match output, or "None"]

Shared utility inventory (existing reusable code — check before proposing new abstractions):
[scan-shared-utils.sh output, or "None"]

Changed files:
[File list from git diff --stat]

Task:
1. Read each changed file and its surrounding context
2. Search the codebase for similar patterns or existing utilities that could be reused — cross-reference the shared utility inventory above
3. Identify concrete simplification opportunities:
   - Duplicate logic that can be extracted into a shared function
   - Complex conditionals that can be simplified
   - Code that reimplements existing utility functions
   - Overly verbose patterns that have simpler alternatives
   - Apply ALL rules in the "Analysis Obligations" section above: inverted search from helpers (not just pattern search), meta-pattern generalization across findings, O(n²) hot paths inside loops, and the parallel-implementation drift check. Each obligation may surface proposals that the basic categories miss.
4. For each opportunity, provide:
   - File and line number
   - Category: duplication / complexity / reuse / verbosity
   - Before: current code snippet
   - After: proposed simplified code
   - Estimated impact: LOC reduction, readability improvement
   - Evidence: for reuse proposals, include the path and line of the existing utility being recommended

Output format: numbered list of proposals with before/after code blocks.
Proposals that recommend reuse without specifying the existing utility's location will be rejected.
If no simplification opportunities found, state "No simplification opportunities found."
```

If sub-agents are unavailable, perform the analysis directly.

## Step 4: Review and Apply

Present Sonnet's proposals to the user as a numbered list.

For each proposal, the user can:
- **Accept**: Apply the change (delegate mechanical refactoring to Sonnet if available)
- **Skip**: Leave the code as-is
- **Modify**: Adjust the proposal before applying

### "Defer to another PR" is a dead phrase

When the analysis finds an actionable issue with under-30-minute fix cost, the default is: fix it in this session. "Out of scope for this PR" is acceptable ONLY when:
1. The fix requires a separate architectural decision (e.g., monorepo restructure), OR
2. The file/area is genuinely untouched by the current changes AND fixing it would expand the diff meaningfully.

Neither applies to the vast majority of findings. Before writing "deferred for future PR", ask: "is the fix under 30 minutes?" If yes, fix it. This rule applies equally to the main agent's proposal triage and to any sub-agent output — a "defer" recommendation without meeting one of the two conditions above must be rewritten as an accepted proposal.

**Security carve-out**: when the proposal touches auth, crypto, input validation, permission grants, or other security-sensitive surfaces, even sub-30-minute fixes require completing the R3 propagation check (trace all affected paths, confirm no propagation gap) before applying. The 30-minute threshold collapses fix cost into "just do it" reasoning, which is dangerous when a single small change can introduce a vulnerability — security-adjacent edits must clear the impact-analysis bar in the same session, but never get rushed past it. (This is the same obligation as the R21 security carve-out in the triangulate skill.)

After applying accepted changes, check migrations and run ALL three verification steps:

```bash
# Check for pending migrations
bash ~/.claude/hooks/check-migrations.sh

# Run ALL three checks:
# 1. Lint
[lint command]

# 2. Tests
[test command]

# 3. Production build
[build command]
```

All must pass. Fix any failures before proceeding.

**IMPORTANT**: Tests and build alone are insufficient. Lint catches unused imports, style violations, and other issues that neither tests nor builds detect. The production build catches issues that only surface during full compilation/bundling — module resolution failures, type errors in non-test code, and bundler/packager-specific failures — that test runs do not exercise. All three must pass.

**IMPORTANT**: Fix ALL errors found by lint/test/build — including pre-existing errors in files not touched by the current task. Never dismiss failures as "unrelated to our changes." We are building the whole project, not just a diff.

**Manual verification (mandatory when refactoring affects runtime behavior)**:
When the refactoring changes **any** of the following, lint/test/build alone are insufficient — mocked tests may pass even when runtime behavior is broken (e.g., mock shape not updated to match the new API, or permissions insufficient for the new query pattern):
- API call patterns (e.g., single-record fetch → batch fetch, sync → async)
- Database queries (e.g., adding JOIN, changing WHERE conditions, switching query methods)
- Event dispatch (e.g., adding or removing event emission, changing payload shape)
- Worker/background job logic (e.g., changing job payload, queue routing, retry behavior)

In such cases:
1. Start the dev server (and workers/background processes if applicable)
2. Exercise the affected code path at least once through the running application
3. Verify no runtime errors in server logs

Do not commit until manual verification passes or the user explicitly waives it. If the user waives manual verification, record the waiver reason in the commit message or deviation log.

Report:
```
=== Simplify Complete ===
Proposals: [total]
Accepted: [n]
Skipped: [n]
Lint: [pass/fail]
Tests: [pass/fail]
Build: [pass/fail]
```
