# Folding — turning a dispositioned lesson into rules, hooks, and tests

Load at Step 5. Input: the `Novel` / `Extends-<id>` items from the Step 3 disposition.
Output: consistent edits across every rule sync point, plus (when the lesson is
mechanically detectable) a detection hook with its bats suite.

## 0. Scrub gate (before any text lands in a committed file)

Every text block derived from mined content — lesson wording, rule-row text, retrospective
prose, PR body fragments — passes the shared deterministic scrub first:

```bash
printf '%s' "<block>" | bash ~/.claude/hooks/retro-prescreen.sh scrub
```

The scrub's allowlist keeps repo-canonical `~/.claude/hooks/`, `~/.claude/skills/`,
`~/.claude/rules/` command references intact while redacting emails, IPs, `/home/<user>`
and other user-specific paths, and secret-shaped strings. If the scrub changes the block,
review the output — a redaction marker inside rule text means the source wording leaked
something that must be rephrased, not merely masked.

## 1. New rule ID assignment

Derive the next free ID from the tables in `skills/triangulate/common-rules.md`
(all-expert rules → `R<n+1>`; security-only → `RS<n+1>`; testing-only → `RT<n+1>`).
`Extends-<id>` items modify the existing row/obligation instead of taking a new ID.

## 2. Sync-point edit map (ALL points, in this order)

Editing tool: Edit/Write ONLY (self-trigger caution, pipeline.md). After each point,
the text must be repo-neutral.

1. `skills/triangulate/common-rules.md`
   - Table row in the correct table (`| R<n> | <pattern name> | <check> | <severity> |`).
   - If the procedure exceeds a table cell: an "Extended obligations" subsection, and the
     row references it. Update the "self-contained in the table row" enumeration line if
     the rule is listed there.
   - Recurring Issue Check template: add the `- R<n> (<name>): [status …]` line (R rules
     only; RS/RT ride the bracket line).
   - Bracket line: bump `Security adds RS1-RS<max>` / `Testing adds RT1-RT<max>`.
   - Every `R1-R<n>` / `RS1-RS<n>` / `RT1-RT<n>` range string in this file.
2. `skills/triangulate/SKILL.md` — range strings.
3. `skills/triangulate/phases/phase-1-plan.md` — range strings; the per-expert
   `- RS<n>: [status]` / `- RT<n>: [status]` template lines.
4. `skills/triangulate/phases/phase-2-coding.md` — range strings (expert scope lines).
5. `skills/triangulate/phases/phase-3-review.md` — same as phase-1.
6. When the rule warrants review-time procedure text, add it to the phase file that owns
   the moment it fires (plan review → phase-1; implementation → phase-2; code review →
   phase-3).

## 3. Detection hook (only when mechanically detectable)

Ask first: can a regex/AST scan over a diff decide this with low false positives? If not,
skip — a noisy hook is worse than none.

1. Author `hooks/check-<slug>.sh` modeled on the existing `check-*.sh` hooks: header
   comment stating the rule ID, detection logic, severity, and usage
   (`bash check-<slug>.sh [base-ref]`); `set -u`; operate on `git diff <base>...HEAD`;
   graceful exit 0 outside a git repo or when tools are missing; project-specific
   extension via `EXTRA_*` env vars, never hardcoded project identifiers.
2. Author `tests/check-<slug>.bats` per repo conventions (jq-built inputs or fixture
   trees in `$BATS_TEST_TMPDIR`; red fixtures DERIVED from the hook's check list — one per
   check, each proven able to fail).
3. Reference the hook from the rule's table row as
   `**Mechanical detection**: bash ~/.claude/hooks/check-<slug>.sh [base-ref] …`.
4. Wire it into the triangulate phase-2 pre-step list
   (`skills/triangulate/phases/phase-2-coding.md`, Step 2-5 pre-steps) when it should run
   every implementation round.
5. If model-invocable, add `Bash(bash ~/.claude/hooks/check-<slug>.sh *)` to
   `settings.json` `permissions.allow`.

## 4. Gates (mandatory, in order)

```bash
bash ~/.claude/hooks/check-rule-sync.sh        # must exit 0 — all sync points consistent
bats tests/                                    # full suite green, including new tests
```

A rule-sync failure means the edit map above was applied incompletely — fix the named
sync point; never silence the linter.
