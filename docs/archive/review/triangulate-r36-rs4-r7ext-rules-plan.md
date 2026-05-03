# Plan: Add R36, RS4, R7-extension to triangulate/common-rules.md

## Project context

- **Type**: `config-only` (this repo tracks `~/.claude/` configuration: settings.json, hooks, skills, rules)
- **Test infrastructure**: `unit tests only` — `tests/` directory holds shell-based hook tests; no CI/CD pipeline runs in this repo. Validation is via `install.sh` + manual verification.
- **Deployment model**: this repo is the source of truth; `install.sh` copies files into `~/.claude/`. Skill files live at `skills/triangulate/` (not symlinked — copied).
- **Out-of-scope test recommendations**: per phase-1-plan.md project-context guidance, experts MUST NOT raise Major/Critical findings recommending the addition of automated tests, CI/CD, or test framework setup for skill markdown changes. The skill itself is loaded by Claude Code at runtime; correctness is validated by review and runtime usage, not by an automated test suite.

## Objective

Incorporate three feedback patterns from the passwd-sso project's MEMORY into the global triangulate skill so that future plan/code reviews automatically check for these recurring issues.

## Requirements

### Functional

1. **R36 (NEW)** — Static-analysis warning suppression as substitute for fix.
   - Added as a new row in the "All experts must check" table (R1-R35 currently).
   - Severity: **Major (default); Critical when the suppressed warning is in a security category** (per Round-1 finding S4 — matches R29 escalation pattern).
   - Body covers four handling categories: (a) dead code → delete; (b) rule violation in legitimate code → restructure to satisfy the rule; (c) duplicate of an existing helper → reuse the helper; (d) upstream type-stub gap or known linter false-positive → suppression IS acceptable when accompanied by a written justification (named upstream issue, version, or incompatibility) per Round-1 finding T5.
   - Verbatim row body: see "Verbatim rule bodies — R36" section below.

2. **RS4 (NEW)** — Personal/identifying data in committed artifacts.
   - Added as a new row in the "Security expert must additionally check" table (RS1-RS3 currently).
   - Severity: **Major** (privacy / data hygiene).
   - Three input vectors (per Round-1 finding S1): (1) developer-typed data, (2) tool-output paste (query results, error traces, logs), (3) autolink-adjacent leakage (overlap with R30).
   - Scope of personal-identifying data (per Round-1 finding S2): real emails, personal handles (Slack/Discord/GitHub), internal usernames, IP addresses (incl. RFC 1918 ranges), internal hostnames, internal URLs in error messages, named-individual references in commit bodies.
   - RS4/R30 dual-fire handling (per Round-1 finding S3): when a single token matches both, record under RS4 (Major, primary) AND note R30 as secondary; do not double-count severity.
   - Detection boundary (per Round-1 finding T4): email regex grep-able with scope exclusions; handles/IPs/internal hostnames human-review only; `.gitignore`'d files out of scope.
   - Verbatim row body: see "Verbatim rule bodies — RS4" section below.

3. **R7 EXTENSION** — Phantom-match traps in a11y test assertions.
   - Augments the existing R7 row body. Existing R7 covers "selector breakage when changed/deleted"; extension adds two phantom-match cases:
     - **Selector-side**: accessible-name regex matches aria-label of unintended chrome elements.
     - **Assertion-side**: OR-fallback combining a11y attribute assertion with styling-class assertion silently passes when implementation drops the a11y attribute but keeps the style class.
   - Both cases are **human-review-required** (per Round-1 finding T3) — no mechanical grep reliably detects accessible-name false matches or OR-fallback assertion patterns. R7 body must explicitly mark them as human-review patterns (alignment: matches R28 phrasing).
   - **Security angle** (per Round-1 finding S5): phantom-match on security-critical UI flows (consent dialog, MFA confirmation, permission grant, signature display) breaks accessibility for assistive-tech users and may mask UX-security regressions.
   - Severity: stays Major (existing R7 severity).
   - The Recurring Issue Check template entry for R7 must reflect the extension scope.
   - Verbatim row body: see "Verbatim rule bodies — R7 extension" section below.

### Non-functional

- **No language/framework/repo-specific identifiers**. Per user feedback `feedback_no_lang_repo_specifics`, skill text must abstract principles. Concrete examples are allowed but MUST be marked `(illustrative — adapt to your project's stack)` or equivalent.
   - Specifically: do NOT use Prisma, Next.js, Playwright, React Testing Library, eslint, TypeScript identifiers as if they were normative. Mention them only as one example among several.
   - **R7 extension wording (addresses Ollama finding 2)**: describe the underlying mechanism, not a specific selector API. Example acceptable phrasing: "Selector-side phantom match: an accessible-name regex matches aria-label content of unintended chrome elements (banner close buttons that embed the same feature label in their aria-label) — name-based selectors traverse the accessible-name including aria-label across most a11y testing primitives." NOT acceptable: "`getByRole({name: regex})` is broken because…" — that names one library's API as if it were the universal API.
- **Backwards compatibility of rule numbering**: R1-R35 IDs must remain stable. R36 appends to the table. RS4 appends to the RS table.
- **Recurring Issue Check template must be updated** to include R36 (lines 437-475 of common-rules.md). RS rules don't appear in that template currently — RS4 should also NOT appear unless we extend the template separately, which is out of scope.

## Technical approach

### Edit targets

1. **`skills/triangulate/common-rules.md`** (primary):
   - **Edit 1**: Replace existing R7 row body. Use the verbatim text from "Verbatim rule bodies — R7 extension" below.
   - **Edit 2**: Insert new R36 row after R35 row. Use the verbatim text from "Verbatim rule bodies — R36" below.
   - **Edit 3**: Insert new RS4 row after RS3 row. Use the verbatim text from "Verbatim rule bodies — RS4" below.
   - **Edit 4**: In the Recurring Issue Check template (lines 437-475), append exactly:
     ```
     - R36 (Static-analysis warning suppression): [N/A — no lint/type warnings touched / Checked — no issue / Finding F-XX]
     ```
     after the existing R35 line.
   - **Edit 5**: In the footer line below the table, replace:
     - **Before** (verbatim): `See "Extended obligations" below for full procedures on R17-R22 and R31-R35. R23-R30 are self-contained in the table row above.`
     - **After** (verbatim): `See "Extended obligations" below for full procedures on R17-R22 and R31-R35. R23-R30 and R36 are self-contained in the table row above.`
   - **Edit 6**: In the Recurring Issue Check template, update the existing R7 entry:
     - **Before** (verbatim): `- R7 (E2E selector breakage): [Checked — no issue / Finding F-XX]`
     - **After** (verbatim): `- R7 (E2E selector breakage + phantom-match traps): [Checked — no issue / Finding F-XX]`

2. **`skills/triangulate/SKILL.md`** (per Round-1 finding T1):
   - Lines 22 and 24 contain `R1-R35` references that are normative (describe Common Rules contents). Apply text replacement `R1-R35` → `R1-R36` at both lines.

3. **`skills/triangulate/phases/phase-1-plan.md`**:
   - Apply text replacement `R1-R35` → `R1-R36` for any occurrence found by the step-6 grep.
   - Plan-specific obligations list does NOT need a new bullet for R36 (per Round-1 finding F3) — R36 applies during code review of suppression sites, not during plan review.
   - Severity criteria table needs no change (severity definitions are general).

4. **`skills/triangulate/phases/phase-2-coding.md`**:
   - In Step 2-4 lint command block, append one sentence after the existing "Pre-existing warnings on touched files count: they must also be cleared." line: `Suppression comments / underscore-prefix renames are NOT an acceptable resolution — see R36 (root cause must be fixed).`

5. **`skills/triangulate/phases/phase-3-review.md`**:
   - Apply text replacement `R1-R35` → `R1-R36` for any occurrence found by the step-6 grep.

### Diff scope summary

| File | LOC delta (estimate) |
|---|---|
| `skills/triangulate/common-rules.md` | +~50 / -~3 |
| `skills/triangulate/SKILL.md` | +0 / -0 (R-range update — 2 lines) |
| `skills/triangulate/phases/phase-1-plan.md` | +0 / -0 (R-range update if found) |
| `skills/triangulate/phases/phase-2-coding.md` | +1 |
| `skills/triangulate/phases/phase-3-review.md` | +0 / -0 (R-range update if found) |

### Deployment

After editing source-of-truth files in this repo, run:
```bash
./install.sh
```
to copy them into `~/.claude/skills/triangulate/`. Verify with `diff -q` that source and installed copies match.

## Verbatim rule bodies

The Phase 2 implementer must paste these verbatim into the corresponding markdown table rows in `skills/triangulate/common-rules.md`. Verbatim text incorporates all Round-1 findings.

### Verbatim rule bodies — R7 extension

Replace the entire R7 row with:

```
| R7 | E2E selector breakage + phantom-match traps | **(1) Selector/attribute deletion**: when routes, CSS classes, exports, aria-label, id, data-testid, or data-slot are changed/deleted, check E2E tests for broken references. **(2) Phantom-match traps** (human-review required at parent level AND per sub-clause below — no mechanical grep reliably detects accessible-name false matches or OR-fallback assertion patterns; this is a human-review pattern, similar to R28): **selector-side (human-review)** — name-based selectors that traverse the accessible-name (which by spec includes `aria-label`) can match unintended chrome elements such as banner close buttons that embed the same feature label in their `aria-label`. The classic symptom is a "test times out waiting for dialog content" failure, but the actual cause is that the selector matched the banner's close button and dismissed it instead of opening the dialog. Mitigation: prefer visible-text-only selectors over name-regex selectors; avoid first-match tie-breakers; assert unique-match (illustrative — `expect(locator).toHaveCount(1)` or scope to a region) rather than relying on `.first()`. **assertion-side (human-review)** — combining an a11y attribute assertion with a styling-class assertion via OR (illustrative pseudo-syntax: `expect(el).toHaveAttribute("aria-current","page") OR expect(el).toHaveClass("variant-secondary")` — concrete syntax varies by framework) silently passes when implementation drops the a11y attribute but keeps the styling class; screen readers stop announcing the state change but the test stays green. Mitigation: a11y assertions query the literal a11y attribute only; never combine via OR with class assertions. Before claiming "the existing component already emits `aria-X`", grep the codebase to verify the attribute exists; if it does not, the implementation must ADD the attribute, not the test merely ASSERT it. **Security angle**: phantom-match on security-critical UI flows (consent dialog, MFA confirmation, permission grant, key-fingerprint or signature display) breaks accessibility for assistive-tech users AND may mask UX-security regressions where the test passes but the user cannot complete the security-critical flow. | Major |
```

### Verbatim rule bodies — R36

Insert after the R35 row:

```
| R36 | Static-analysis warning suppression as substitute for fix | Suppressing static-analysis warnings (lint, type checker, security scanner) via comment pragmas or rename-tricks is not an acceptable resolution. Suppression mechanisms vary by tool (illustrative, not exhaustive — searched as separate literal tokens, not a single combined regex, to keep table cells from breaking): `eslint-disable`, `@ts-ignore`, `# type: ignore`, `# noqa`, `@SuppressWarnings`, `//nolint:`, `#[allow(...)]`. Rename-tricks include underscore-prefix renames that mark variables as "intentionally unused" when the code is actually dead. The warning must be addressed at root cause via one of four categories: **(a) dead code** → delete entirely; **(b) rule violation in legitimate code** → restructure to satisfy the rule; **(c) duplicate of an existing helper** → reuse the helper instead of writing new code that requires suppression; **(d) upstream type-stub gap or known linter false-positive** → suppression IS acceptable when accompanied by a written justification placed adjacent to the suppression comment, naming the specific upstream issue, version, or incompatibility (illustrative comment: `// @ts-ignore — upstream issue typescript-eslint/typescript-eslint#1234, fixed in v8`). Bare suppression without a named, grep-able justification is the violation; suppression with a documented justification is acceptable. Detection: enumerate the suppression markers above, run a separate grep for each one across the diff (`git diff --name-only main...HEAD`), and review every hit. **Severity escalation** (matches R29 mechanic): Major by default; **Critical** when the suppressed warning is in a security category — illustrative examples (not exhaustive): SAST injection warnings (SQLi/XSS/command), path-traversal warnings, SSRF warnings, timing-attack warnings, hardcoded-secret detector hits, deserialization-vulnerability warnings, cryptographic-API misuse / weak-cipher detector hits, dead-code warnings on auth/authz branches that may be reachable via alternate code paths. Suppressing a security warning is materially equivalent to disabling the security control. | Major (Critical when the suppressed warning is in a security category) |
```

### Verbatim rule bodies — RS4

Insert after the RS3 row in the "Security expert must additionally check" table:

```
| RS4 | Personal-identifying data in committed artifacts | Personal-identifying data must NOT appear in any committed artifact (docs, plans, manual-test scripts, commit bodies, PR descriptions, deviation logs, review logs). **Three input vectors trigger the rule**: (1) **developer-typed data** — real personal email, real handle/username of named individuals, internal usernames typed directly into the artifact; (2) **tool-output paste** — query results, error traces, log lines, command output pasted verbatim into committed text often carry email addresses, user IDs, IP addresses, internal hostnames; never echo tool-returned identifier output verbatim into commit-bound text; (3) **autolink-adjacent leakage** (overlaps with R30) — bare `@<handle>` mentions create notifications visible to the named individual; bare `#<num>` issue/PR back-references leak the existence of the new artifact to watchers of the referenced item. **Scope of personal-identifying data**: real email addresses, real personal handles (Slack/Discord/GitHub), internal usernames, IP addresses (incl. RFC 1918 internal ranges), internal hostnames (illustrative: `db-prod-01.internal`), internal URLs in error messages, named-individual references in commit bodies. **Mitigation**: replace with placeholders (illustrative: `<test-user-email>`, `<reviewer-handle>`, `<internal-hostname>`); add a Pre-conditions section in manual-test artifacts instructing the operator to substitute locally. **Detection boundary**: email regex grep is reliable (illustrative: `grep -rnE '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' $(git diff --name-only HEAD)`) — apply scope exclusions: Co-Authored-By trailers in commit messages (intentional attribution), public maintainer addresses in vendor docs / SECURITY.md / package metadata, RFC 2606 reserved domains (`example.com`, `example.org`, `example.net`, `invalid`, `localhost`), placeholder syntax (`<...@...>`). Personal handles, IP addresses, internal hostnames, and internal URLs require **human review** (project-specific format, not reliably grep-able). Files matched by `.gitignore` are out of scope; only files appearing in `git diff --name-only HEAD` are in scope. **RS4 vs R30 dual-fire**: when a single token matches both rules (e.g., a bare `@<name>` that is both a personal handle AND a GitHub-flavored-Markdown autolink trigger), record the finding under RS4 (Major, primary classification) AND note R30 as the secondary classification for the autolink-suppression mechanic — do not double-count severity. | Major |
```

## Implementation steps

1. **RS table sanity-check** (run before any common-rules.md edit; addresses Ollama finding 3 + Round-1 spec). Confirm:
   - The "Security expert must additionally check:" header exists.
   - The RS table has exactly 4 columns: `# | Pattern | What to check | Severity`.
   - RS3 is the last existing row.
   Verification command:
   ```bash
   awk '/^\*\*Security expert must additionally check:\*\*/,/^\*\*Testing expert must additionally check:\*\*/' \
       skills/triangulate/common-rules.md
   ```
   The output must show RS1, RS2, RS3 rows with the 4-column layout. If the layout differs, the insertion procedure must be revised (do NOT mechanically insert).

2. **Edit common-rules.md** — apply Edits 1-6 from the "Edit targets" section using the verbatim rule bodies above:
   1. Edit 1 (R7 row replacement).
   2. Edit 2 (insert R36 row after R35).
   3. Edit 3 (insert RS4 row after RS3).
   4. Edit 4 (append R36 line in Recurring Issue Check template).
   5. Edit 5 (footer line "R23-R30 and R36 are self-contained").
   6. Edit 6 (R7 entry in Recurring Issue Check template — mention phantom-match traps).

3. **Edit SKILL.md** (Round-1 finding T1):
   - Apply text replacement `R1-R35` → `R1-R36` at lines 22 and 24.

4. **Edit phase-2-coding.md**:
   - In Step 2-4 lint command block, append the sentence specified in "Edit targets / phase-2-coding.md".

5. **Edit phase-1-plan.md and phase-3-review.md**:
   - Apply text replacement `R1-R35` → `R1-R36` for any occurrences found by step 6 grep.

6. **Verify range-update completeness across the full skill tree** (addresses Ollama finding 1):
   ```bash
   grep -rn -E 'R1[ -]?(-|to|through)[ -]?R35\b' skills/triangulate/
   ```
   Should return zero hits after edits. Run this before `install.sh` to catch any stale reference in any markdown file under the skill — including SKILL.md and any auxiliary markdown.

7. **Run install.sh**:
   ```bash
   ./install.sh
   ```

8. **Verify deployment**:
   ```bash
   for f in common-rules.md SKILL.md phases/phase-1-plan.md phases/phase-2-coding.md phases/phase-3-review.md; do
     diff -q "skills/triangulate/$f" "$HOME/.claude/skills/triangulate/$f"
   done
   ```
   All five must report "identical" (no output) — diff -q prints filenames only when they differ.

## Testing strategy

This is a `config-only` repo with no CI for skill markdown. Validation is:

1. **Syntactic**: ensure markdown tables render correctly. Verify with a markdown preview or by re-reading the file. Specifically:
   - R36 row column count matches sibling rows (4 columns).
   - RS4 row column count matches sibling rows (4 columns).
   - R7 extension does not break the row's column count.

2. **Semantic** (no automated test — review-driven):
   - Three-expert plan review (Phase 1 Step 1-4, this file's Phase 1).
   - Three-expert code review on the implementation diff (Phase 3).

3. **Range consistency**: `grep -rn -E 'R1[ -]?(-|to|through)[ -]?R35\b' skills/triangulate/` returns zero hits.

4. **Deployment parity**: `diff -q` confirms all 5 source-of-truth files match the `~/.claude/skills/` copies.

## Considerations & constraints

### Risk: rule-text drift after merge

Once R36 / RS4 / R7-ext are in place, future PRs that update common-rules.md may inadvertently re-narrow R7 or rewrite R36 / RS4 in a way that loses the principles. Mitigation: keep the principles tied to a memo location (this plan file lives in `docs/archive/review/`, gitted alongside the repo) so future maintainers can recover the intent.

### Risk: false-positive R36 findings

R36 may fire on legitimate suppression cases (generated-code blocks, upstream type-stub gaps). Mitigation incorporated into the R36 verbatim body as **category (d)**: suppression accompanied by a written justification (named upstream issue, version, or incompatibility) is acceptable. Bare suppression without a grep-able named justification is the violation.

### Risk: false-positive RS4 findings

Mitigation: the RS4 verbatim body explicitly lists scope exclusions:
- Co-Authored-By trailers in commit messages (intentional attribution).
- RFC 2606 reserved domains (`example.com`, `example.org`, `example.net`, `invalid`, `localhost`).
- Placeholder syntax (`<test-user-email>` etc.).
- Public maintainer emails listed in vendor docs / SECURITY.md / package metadata.
- `.gitignore`'d files (only `git diff --name-only HEAD` files are in scope).

### Risk: R7 selector-side trap is library-specific

Mitigation incorporated into the R7 verbatim body: describes the underlying mechanism ("name-based selectors traverse the accessible-name (which by spec includes `aria-label`)") rather than naming a specific framework's API. Concrete syntax examples are marked illustrative.

### Risk: R7 phantom-match cannot be detected by grep

Mitigation incorporated into the R7 verbatim body: explicitly marked as a human-review pattern (alignment: matches R28 phrasing). Reviewers know not to skip the check just because grep does not find the pattern.

### Out of scope

- Adding an "Extended obligations" subsection for R36 (R36 is self-contained, like R23-R30).
- Adding RS4 to the Recurring Issue Check template (RS rules are NOT currently in that template; extending the template format is a separate refactor).
- Updating other skills (pr-create, security-scan, simplify) with the same patterns — out of this PR's scope. The user signaled "triangulate など" (etc.); follow-up PRs will address other skills.
- Migrating other passwd-sso feedback memories not in the approved 3-item list. The other ~26 memories are already covered or are workflow/project-specific.

## User operation scenarios

**Scenario 1: Future PR introduces lint suppressions**
- A developer's PR contains `// eslint-disable-next-line` over a function. Code review (Phase 3) loads common-rules.md, applies R36, flags Major: "Lint suppression added at file:line — categorize as (a) dead code (delete), (b) rule violation (restructure), or (c) duplicate of helper (reuse). Bare suppression is not acceptable. If a written justification is present, include the spec/issue/incompatibility name in the comment."
- The PR is sent back for one of the three resolutions.

**Scenario 2: Future PR commits a manual-test file with a real email**
- A developer's PR adds `docs/archive/review/some-feature-manual-test.md` with `WHERE email = 'firstname.lastname@example.com'` (illustrative — the real PR would contain a real address that this rule prevents from leaking). Code review (Phase 3) loads common-rules.md, applies RS4, flags Major: "Personal email at file:line — replace with placeholder `<test-user-email>` and add a Pre-conditions section instructing the operator to substitute locally."
- The PR is sent back for replacement.

**Scenario 3: Future PR adds an a11y E2E assertion using OR-fallback**
- A developer's PR contains a test that asserts `expect(el).toHaveAttribute("aria-current","page") OR expect(el).toHaveClass("variant-secondary")`. Code review (Phase 3) loads common-rules.md, applies R7 extension (assertion-side trap), flags Major: "OR-fallback assertion at file:line silently passes when impl drops the aria attribute but keeps the styling class. Assertion must query the literal a11y attribute only; never combine with class assertion via OR. If the codebase did not previously emit the a11y attribute, the implementation must ADD it — not the test ASSERT it."
- The PR is sent back for split assertion.
