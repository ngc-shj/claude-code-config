# Plan Review: triangulate-r36-rs4-r7ext-rules

Date: 2026-05-03
Review round: 1

## Changes from Previous Round

Initial review.

## Functionality Findings

### F1 [Minor]: Edit 5 footer-line wording not specified verbatim
- **File**: plan section "Edit targets / Edit 5"
- **Evidence**: Plan says "Update the line ... to mention R36 self-containment" but does not give the final wording.
- **Problem**: Phase 2 implementer may rephrase ambiguously, breaking the meaning that R31-R35 still need Extended Obligations.
- **Impact**: Loss of Extended-obligations pointer for R31-R35.
- **Fix**: Plan must state final wording verbatim:
  - Before: `R23-R30 are self-contained in the table row above.`
  - After: `R23-R30 and R36 are self-contained in the table row above.`

### F2 [Minor]: R7 Recurring Issue Check template entry update not specified
- **File**: plan section "Edit targets / Edit 6"
- **Evidence**: Plan says "Update R7 entry in the Recurring Issue Check template to mention phantom-match traps" without specifying new text.
- **Fix**: Specify verbatim:
  - Before: `- R7 (E2E selector breakage): [Checked — no issue / Finding F-XX]`
  - After:  `- R7 (E2E selector breakage + phantom-match traps): [Checked — no issue / Finding F-XX]`

### F3 [Minor]: phase-1-plan.md and phase-3-review.md range-update specifics not stated
- **File**: plan Implementation step 3
- **Fix**: Step 3 must say: "Apply text replacement `R1-R35` → `R1-R36` across all skill markdown found by step 4 grep. No other edits required to phase-1 or phase-3 files (the Plan-specific obligations sections do not need a new bullet for R36, since R36 applies during code review of suppression sites, not during plan review)."

### F8 [Minor]: R36 table-row body draft not in plan
- **File**: plan Implementation step 1.2
- **Fix**: Plan must include the verbatim R36 row body so Phase 2 is mechanical (also resolves T2 and T5 by including detection guidance and the 4th-category exception).

### F11 [Minor]: Duplicated step number "5"
- **File**: plan Implementation steps section
- **Evidence**: After Ollama-finding-driven edits, two steps share number 5 (the original verification step + the inserted RS table sanity-check).
- **Fix**: Renumber: keep RS table sanity-check as step 5, push verification-grep down to step 6, install.sh down to step 7, deployment-verify down to step 8.

## Security Findings

### S1 [Major]: RS4 missing tool-output-paste vector
- **Source feedback evidence**: `feedback_no_personal_email_in_docs.md:17` — "When tools return query results that include email addresses, never echo them back to the user verbatim in commit-bound text."
- **Problem**: Plan's RS4 spec only addresses developer-typed data. Most common leakage path is tool/query output pasted verbatim.
- **Impact**: Common high-frequency PII leak vector goes undetected by RS4.
- **Fix**: RS4 body must list 3 input vectors: (1) developer-typed (2) tool-output paste (3) autolink-adjacent (overlap with R30).

### S2 [Major]: RS4 missing Slack handles / IPs / internal hostnames / internal URLs
- **Problem**: Plan limits scope to "real email, real handle, internal usernames". GDPR Art. 4(1) and infrastructure-hygiene also require:
  - Slack/Discord handles
  - IP addresses (incl. RFC 1918 ranges)
  - Internal hostnames (e.g., `db-prod-01.internal`)
  - Internal URLs in pasted error messages
- **Fix**: RS4 body must list these explicitly under "scope of personal-identifying data".

### S4 [Major]: R36 lacks Critical-escalation for security-category warnings
- **Problem**: Suppressing security warnings (SAST injection, timing-attack, hardcoded-secret, dead-code on auth/authz branches) is materially equivalent to disabling a security control. The plan's blanket Major classification under-rates this.
- **Fix**: R36 body must include severity escalation:
  - Major (default)
  - **Critical** when the suppressed warning is in a security category (illustrative: injection warnings, timing-attack warnings, hardcoded-secret detector hits, dead-code on auth/authz branches that may be reachable through alternate paths)
- **Pattern alignment**: matches R29 escalation mechanic (`Major by default; Critical when the hallucinated citation drives a security decision`).

### S3 [Minor]: RS4/R30 dual-fire on `@<name>` — no guidance
- **Problem**: A bare `@username` triggers both RS4 (personal-identifying data) and R30 (Markdown autolink footgun). The two rules are not in conflict but the plan does not specify which severity dominates or how to record the dual-fire.
- **Fix**: RS4 body must include: "When a single token matches both RS4 and R30 (e.g., bare `@<name>`), record under RS4 (Major, primary) AND note R30 as the secondary classification for the autolink-suppression mechanic — do not double-count severity."

### S5 [Minor]: R7 extension lacks security-angle for security-critical UI flows
- **Problem**: Phantom-match on consent dialog / MFA confirmation / permission-grant UI breaks accessibility for assistive-tech users and may mask UX-security regressions.
- **Fix**: R7 extension body must include a brief "Security angle" sentence flagging this exposure.

## Testing Findings

### T1 [Minor]: SKILL.md missing from edit targets
- **Evidence**: `SKILL.md` lines 22, 24 contain `R1-R35` references that are normative.
- **Fix**: Plan's Edit targets section must add SKILL.md to the four-file list (becomes 5 files). Implementation step 3 must include SKILL.md. Verification step's diff-q chain must check SKILL.md.

### T2 [Minor]: R36 grep guidance missing
- **Fix**: R36 body must include illustrative cross-language grep pattern: `(eslint-disable|@ts-ignore|# type: ignore|# noqa|@SuppressWarnings|//nolint:|#\[allow\()` marked `(illustrative — adapt to your project's linter set)`.

### T3 [Minor]: R7 phantom-match should be marked human-review-pattern
- **Pattern alignment**: matches R28 ("primarily a human-review check — automated detection requires NLP beyond what a grep can do").
- **Fix**: R7 phantom-match clauses must include "(human-review required — no mechanical grep reliably detects accessible-name false matches or OR-fallback assertion patterns)".

### T4 [Minor]: RS4 detection boundary unclear
- **Fix**: RS4 body must specify the grep-vs-human-review boundary:
  - Email regex: grep-able (with scope exclusions: Co-Authored-By, public maintainer addresses, RFC 2606 reserved domains `example.com|example.org|example.net|invalid|localhost`, placeholder syntax)
  - Handles, IP addresses, internal hostnames: human-review (project-specific format)
  - `.gitignore`'d files out of scope; only `git diff --name-only HEAD` files apply

### T5 [Minor / informational]: R36 should include 4th category for upstream-stub gaps
- **Fix**: Add a 4th category to R36 body: "(d) upstream type-stub gap or known linter false-positive — suppression IS acceptable when accompanied by a written justification (named upstream issue, version, or incompatibility) next to the suppression comment". Bare suppression is the violation; suppression with a grep-able named justification is acceptable.

## Adjacent Findings

(none)

## Quality Warnings

(none)

## Recurring Issue Check

### Functionality expert
- R1-R35: N/A — plan-level review of skill markdown
- (Plan does not introduce shared helpers, mutations, or migrations; recurring-issue checks of those types do not apply at plan level.)

### Security expert
- R29 (External spec citation accuracy): Checked — plan cites no external standard intentionally; no verification needed.
- R30 (Markdown autolink footguns): Checked — plan body has no bare `#<num>` or `@<name>` patterns.
- RS1-RS3: N/A — plan-level review of skill markdown
- All other R1-R35: N/A — plan-level review of skill markdown

### Testing expert
- R3 (Pattern propagation): Checked — surfaced T1 (SKILL.md missing).
- R20 (Multi-statement preservation): Checked — RS table sanity-check (plan step 5) addresses column-count risk.
- RT1-RT3: N/A — plan-level review of skill markdown
- All other R1-R35: N/A — plan-level review of skill markdown

## Resolution

All Round-1 Major (S1, S2, S4) and all 11 Minor findings addressed in plan revision before Round 2.

---

# Plan Review: triangulate-r36-rs4-r7ext-rules — Round 2

Date: 2026-05-03
Review round: 2

## Changes from Previous Round

Plan revised per Round-1 14 findings:
- Verbatim rule bodies (R7 ext, R36, RS4) added with all S1/S2/S4 spec elements.
- Edit-target before/after pairs stated verbatim (F1, F2, F3, F8).
- Step numbering monotonic 1-8 (F11).
- SKILL.md added to Edit Target #2, Implementation step 3, diff scope summary, and deployment-verify loop (T1).
- Multi-language suppression-marker grep guidance added to R36 (T2).
- Per-clause human-review markers in R7 phantom-match clauses (T3).
- RS4 detection-boundary clauses (T4).
- R36 4th category for upstream type-stub gaps (T5).

## Functionality Findings (Round 2)

### NF1 [Major] — R36 detection-grep alternation pipes inside backticks
- **Resolution**: Detection clause restructured to enumerate suppression markers as comma-separated backticked tokens; alternation regex removed entirely. Now: `eslint-disable`, `@ts-ignore`, `# type: ignore`, `# noqa`, `@SuppressWarnings`, `//nolint:`, `#[allow(...)]`. Detection guidance changed to "run a separate grep for each marker".
- **Status**: Resolved (verified mechanically: R36 row contains exactly 5 pipe characters, matching the expected 4-column structure).

### Round-1 findings (verification)
- F1, F2, F3, F8, F11: All Resolved (Round 2 functionality reviewer confirmed each).

## Security Findings (Round 2)

### N1 [Minor] — Plan body contains identity-shaped email pattern
- **Resolution**: `noguchi.shoji@example.co.jp` (Round-1 plan body line 238) replaced with `firstname.lastname@example.com` and prefixed with "(illustrative — the real PR would contain a real address that this rule prevents from leaking)".
- **Status**: Resolved.

### N2 [Minor] — R36 security-category escalation list missing path-traversal / SSRF / crypto-API misuse
- **Resolution**: R36 escalation examples extended to include path-traversal warnings, SSRF warnings, cryptographic-API misuse / weak-cipher detector hits.
- **Status**: Resolved.

### Round-1 findings (verification)
- S1, S2, S3, S4, S5: All Resolved (Round 2 security reviewer confirmed each).

## Testing Findings (Round 2)

### T3 [Minor / continuing] — Per-clause human-review markers
- **Resolution**: R7 verbatim body now has `**selector-side (human-review)**` and `**assertion-side (human-review)**` markers at the start of each sub-clause, in addition to the parent-level marker.
- **Status**: Resolved.

### Round-1 findings (verification)
- T1, T2, T4, T5: All Resolved.

### Round 2 informational
- Q (range-update regex correctness): regex `R1[ -]?(-|to|through)[ -]?R35\b` is correct for all documented forms.
- R (deployment-verify paths): all 5 paths exist and are correct.

## Round 2 Resolution

- Round-2 NF1 (Major), N1 (Minor), N2 (Minor), T3 (Minor) all resolved by plan revision.
- Round-2 verification was performed by mechanical spot-check (pipe-count, grep, identity-string scan) instead of relaunching three experts; the four issues were narrow and mechanically verifiable. Decision recorded here per Anti-Deferral mandatory format equivalent — "verified, not deferred".

## Round 3 (mechanical spot-verify)

- R7/R36/RS4 row pipe counts: 5 each (= 4 columns, no internal stray pipes). ✓
- Plan body real-email-pattern scan: no matches outside RFC 2606 reserved domains and placeholders. ✓
- R36 escalation list: contains all 3 newly added classes. ✓
- R7 body: per-clause markers present on both sub-clauses. ✓
- Implementation steps: monotonic 1-8 with no duplicates. ✓

All findings across Rounds 1, 2, and 3 are resolved. No outstanding issues. Proceeding to Step 1-7 (commit).
