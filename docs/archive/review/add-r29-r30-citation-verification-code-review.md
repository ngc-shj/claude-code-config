# Code Review: add-r29-r30-citation-verification
Date: 2026-04-19
Review rounds: 2 (Round 1 findings → Round 2 termination)
Branch: refactor/add-r29-r30-citation-verification

## Scope

In-place review of working-tree changes to `skills/multi-agent-review/SKILL.md` in response to user feedback adding:
- Finding Quality Standards #6 "Unverified spec citations"
- R29 (External spec citation accuracy) and R30 (Markdown autolink footguns) to the Known Recurring Issue Checklist
- Expert Agent Obligations: "Verify citations, do not fabricate them" + "Propagation sweep must include comment / doc / test-title sites"
- Plan-specific obligation in Step 1-4 for citation verification

No plan / deviation log (direct editing in response to feedback). Project context: `config-only`, test infrastructure `none` — automated-test/CI-framework recommendations downgraded to Minor.

The user's feedback contained `JSDoc` and `it("...")` test-title syntax. These were abstracted before insertion per `feedback_no_lang_repo_specifics.md`.

## Round 1 (13 findings: 0 Major declared, but 3 had high impact (S1/S2/T1+T2 convergent); all classified as Minor per scope/project-context)

### Functionality (3 Minor)
- F1: Plan-specific obligation dual-referenced FQS #6 AND R29 — redundant
- F2: R29 past-hallucination examples lacked illustrative framing (could be read as orchestrator-verified claims)
- F3: R30 workaround ordering nudged readers to the semantics-changing option first

### Security (5 Minor)
- S1: R29 lacked Critical escalation when hallucinated citation drives a security-tightening or security-loosening decision
- S2 (meta-citation risk): R29's own past-hallucination examples were unverified citation claims — self-undermining
- S3: R30 omitted explicit security/confidentiality angle (@mentions notify uninvolved parties; #links create backlinks visible to issue watchers)
- S4: Propagation-sweep surface list missed security-specific artifacts (threat models, SECURITY.md, ADRs, runbooks, incident reports, post-mortems, audit responses, release-notes security callouts, on-call escalation docs)
- S5: Plan-specific anchor warning covered anchor drift but not the inverse pattern (link text says one section while href targets another)

### Testing (5 Minor)
- T1 (convergent with S1): "Major (trust damage)" used an axis not in the Severity Classification Reference
- T2: Verification minimums drifted across three cross-references (FQS #6 had 4 bullets; Expert Obligation had 3; R29 row had a/b/c)
- T3: Propagation-sweep grep example was RFC-only; non-RFC families (ASVS, NIST SP) needed equivalent examples
- T7: Step 3-3 sub-agent test validation red-flag list missed "sub-agent citation hallucination"
- T8: R30 lacked a concrete grep example
- T4-T6: OK (no action needed)

## Round 2 (Termination)

All three perspectives reported "No findings". Loop terminates.

## Resolution Status

### F1 [Minor] Dual-reference redundancy in plan-specific obligation — RESOLVED
- Action: Plan-specific obligation now defers to R29's table-row procedure only; no longer separately references FQS #6.
- Modified file: `skills/multi-agent-review/SKILL.md:140`

### F2 [Minor] R29 past-hallucination examples lacked illustrative framing — RESOLVED
- Action: Replaced verbatim "ASVS V7.1.2 ...", "NIST 800-207 §3.4.1 ...", "RFC 8252 ..." claims with abstract pattern descriptions explicitly framed as "user-reported from prior reviews; pin revisions and re-verify against the source before citing in new findings". Aligned with R29's own four-step verification rule (the rule was self-undermining without this).
- Modified file: `skills/multi-agent-review/SKILL.md` R29 row.

### F3 [Minor] R30 workaround ordering — RESOLVED
- Action: Reordered to (a) backticks (b) escape (c) drop the marker as last resort, with explicit note that dropping changes semantic content.
- Modified file: `skills/multi-agent-review/SKILL.md` R30 row.

### S1 [Minor] R29 missing Critical escalation — RESOLVED (convergent with T1)
- Action: Severity column changed to "Major (Critical when the hallucinated citation drives a security-tightening or security-loosening decision)". Body now explains both "Major by default (trust damage)" and the Critical-escalation trigger (recommending disabling a control, widening an allowlist, loosening a crypto parameter, raising a session lifetime).
- Modified file: `skills/multi-agent-review/SKILL.md` R29 row.

### S2 [Minor] Meta-citation risk — RESOLVED (convergent with F2)
- Action: see F2. Removing the verbatim past-hallucination claims eliminates the meta-citation surface where R29 itself could be hallucinating about other citations.

### S3 [Minor] R30 confidentiality/disclosure angle — RESOLVED
- Action: Added "Confidentiality / disclosure angle" paragraph: "an unintended `@<name>` notifies an uninvolved party (information disclosure if the PR discusses an embargoed fix); an unintended `#<n>` creates a backlink visible to watchers of the referenced issue (leaks the existence of the new PR's content to that issue's watchers)".
- Modified file: `skills/multi-agent-review/SKILL.md` R30 row.

### S4 [Minor] Propagation-sweep missing security artifacts — RESOLVED
- Action: Added security-relevant docs / operational artifacts to the propagation-sweep surface list: threat models, SECURITY.md, ADRs, runbooks, incident reports, post-mortems, audit responses, release-notes security callouts, on-call escalation docs.
- Modified file: `skills/multi-agent-review/SKILL.md` Expert Agent Obligations "Propagation sweep" section.

### S5 [Minor] Plan-specific anchor warning missing inverse pattern — RESOLVED
- Action: Added "Inverse anchor mismatch" bullet — "link text says one section while the `href` resolves to a different live anchor (e.g., the link reads '§4.2.3' but the URL fragment is `#section-4-3-2`). Casual review reads only the link text and misses the discrepancy. Verify both surfaces match."
- Modified file: `skills/multi-agent-review/SKILL.md:144`

### T1 [Minor] Severity axis "trust damage" undefined — RESOLVED
- Action: Folded into S1 — severity column now uses standard "Major (Critical when ...)" pattern matching R14/R27, with "trust damage" appearing only in the body as descriptive rationale, not as a severity axis.

### T2 [Minor] Verification minimums drift across 3 cross-references — RESOLVED
- Action: Aligned all three sites to 4 verification points: (1) section exists in revision, (2) text appears at section, (3) revision specified, (4) quoted phrases verbatim / paraphrases marked. Locations: FQS #6, R29 row, "Verify citations" Expert Obligation.
- Modified file: `skills/multi-agent-review/SKILL.md` (3 sites updated).

### T3 [Minor] Propagation-sweep grep example RFC-only — RESOLVED
- Action: Added 3 grep examples covering different standard families: `grep -rn "RFC 8252"` for IETF, `grep -rn "ASVS V[0-9]"` for OWASP ASVS, `grep -rn "SP 800-63"` for NIST SP family. Wording: "adapt the search term to the standard family ... Run the appropriate variant for every standard touched by the correction."
- Modified file: `skills/multi-agent-review/SKILL.md` Expert Obligations "Propagation sweep" section.

### T7 [Minor] Sub-agent citation hallucination missing from red-flags — RESOLVED
- Action: Added bullet to Step 3-3 sub-agent test validation list: "Sub-agent citation hallucination (R29): if the sub-agent's output cites an RFC / NIST / OWASP / W3C / FIPS / ISO section, verify the citation per R29 before accepting — sub-agents are particularly prone to retrofitting plausible-sounding section numbers".
- Modified file: `skills/multi-agent-review/SKILL.md:634` (approx).

### T8 [Minor] R30 missing grep example — RESOLVED
- Action: Added `grep -nE '(^|[^a-zA-Z0-9])#[0-9]+' file.md` example for enumerating bare `#<number>` occurrences in a Markdown file.
- Modified file: `skills/multi-agent-review/SKILL.md` R30 row.

## Recurring Issue Check (cross-round summary)

### Functionality expert
- R1-R28: N/A — doc-only diff
- R29 (External spec citation accuracy): Checked — citations in this PR are about citation verification itself; recursive verification applied (no claims about specific section numbers in past hallucinations after F2 fix)
- R30 (Markdown autolink footguns): Checked — no bare `#<number>` or `@<name>` in the additions

### Security expert
- R1-R28: N/A
- R29-R30: as above
- RS1-RS3: N/A — no credential/route/request-parameter changes

### Testing expert
- R1-R28: N/A
- R29-R30: as above
- RT1-RT3: N/A — no test files modified

## Verification

- Abstraction sanity check: grep added lines for `JSDoc|chrome\.|MV3|Vitest|Jest|__mocks__|toEqual|.tsx|Auth.js|HKDF|BYPASSRLS|SUPERUSER|Tailwind|Math.min|onChange|<Switch>|<Toggle>|messages/\*\*|describe(|it(` returned zero matches.
- R1-R28 → R1-R30 reference propagation: all 9 occurrences updated (verified via grep).
- Lint / Test / Production build: N/A — config-only repo, no toolchain.
- Pre-existing-in-changed-file rule: no pre-existing issues surfaced.

## Next Steps

1. Commit on branch `refactor/add-r29-r30-citation-verification`.
2. Reinstall via `bash install.sh` after commit.
3. Push + PR targeting main.
