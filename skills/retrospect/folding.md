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
   - Keep the row to a short routing summary. If the procedure is large, put its full
     normative text in `skills/triangulate/rule-details/<ID>.md` and add
     `**Mandatory full procedure**: rule-details/<ID>.md` to the row. The detail heading
     and full-row ID/pattern must match the compact row; check-rule-sync rejects missing,
     orphaned, or mismatched detail files.
   - Extended obligations remain appropriate for shared procedures spanning multiple
     rules. Append covered IDs to the "full procedures on ..." pointer sentence.
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
   phase-3). Two constraints the phase manifest imposes on that edit:
   - Inserted text must land **above** the file's `## END-OF-PHASE-<N>` terminator, which
     has to stay the last non-empty line. Appending with `>>` puts it after.
   - Adding a `### Step <N>-<M>` heading obliges updating `steps:` and `step_ids:` in the
     same file's front matter, and `core:` if the new step is the non-substitutable one.
   `check-rule-sync.sh` catches both, so a miss reds `bats tests/` rather than shipping —
   but knowing it here saves the round trip.
7. Regenerate `skills/triangulate/common-rules.digest.md` with
   `bash hooks/generate-triangulate-rule-digest.sh`; never edit the digest directly.

## 3. Detection hook (only when mechanically detectable)

Ask first: can a regex/AST scan over a diff decide this with low false positives? If not,
skip — a noisy hook is worse than none. Record the answer either way: a lesson folded
without a hook should say in the retrospective doc why it is not mechanically decidable,
so the next round does not re-litigate it.

1. Author `hooks/check-<slug>.sh` modeled on the existing `check-*.sh` hooks: header
   comment stating the rule ID, detection logic, severity, and usage
   (`bash check-<slug>.sh [base-ref]`); `set -u`; operate on `git diff <base>...HEAD`;
   graceful exit 0 outside a git repo or when tools are missing; project-specific
   extension via `EXTRA_*` env vars, never hardcoded project identifiers.
   **When the hook CLASSIFIES code** (is this a real test/guard/caller?), text/regex
   matching is false-green-able by construction (comments, labels, strings) — climb the
   binding ladder to the rung the stated guarantee needs: text < AST node existence <
   import-symbol binding < execution binding < framework binding. AST classifiers bind
   identifiers to import-origin symbols (never name text), verify matched nodes execute
   (not merely exist), allowlist accepted variant forms (never denylist known-bad),
   derive case coverage from the language grammar of the targeted construct (one fixture
   per production), and fail the gate closed on classifier error — no text fallback.
   Reserve plain grep for fail-LOUD uses (literal counts whose drift breaks CI visibly).
   See RT7 rule-details shape (f).
2. Author `tests/check-<slug>.bats` per repo conventions (jq-built inputs or fixture
   trees in `$BATS_TEST_TMPDIR`; red fixtures DERIVED from the hook's check list — one per
   check, each proven able to fail).
3. Reference the hook from the rule's table row as
   `**Mechanical detection**: bash ~/.claude/hooks/check-<slug>.sh [base-ref] …`.
4. Wire it into the triangulate phase-2 pre-step list
   (`skills/triangulate/phases/phase-2-coding.md`, Step 2-5 pre-steps) when it should run
   every implementation round.
5. If model-invocable, add `Bash(bash ~/.claude/hooks/check-<slug>.sh *)` to
   `settings.json` `permissions.allow`. A hook that executes caller-supplied argv is the
   exception — a `*`-suffixed entry there launders the deny/ask lists, whose patterns are
   anchored on the leading command token and cannot see past a wrapper. Argue such a hook
   in explicitly or leave it out.
6. If the hook belongs to the RT-family of test-quality detectors, register it in
   `skills/test-gen/SKILL.md`'s post-generation block as well — that closes the
   generate→verify loop, since test-gen is the skill that writes the tests these hooks
   later catch in review. Update the scope caveat beside that block in the same edit: it
   states which frameworks each hook covers, and a hook with different coverage makes the
   existing sentence false in both directions.

## 4. Gates (mandatory, in order)

```bash
bash ~/.claude/hooks/check-rule-sync.sh        # must exit 0 — all sync points consistent
bats tests/                                    # full suite green, including new tests
```

A rule-sync failure means the edit map above was applied incompletely — fix the named
sync point; never silence the linter. Judge each gate by its OWN exit status (R44): run
it unpiped, or redirect output to a file and inspect afterwards — piping a gate through
`head`/`tail`/`grep` reports the pipe tail's status and masks a real failure as green.

A zero exit is only half the verdict (R50 clause ii): "examined nothing" and "found
nothing wrong" are the same status. Quote the count alongside it — the number of tests
the suite actually ran, and the new tests among them by name. A `bats tests/` that
collected fewer files than the directory holds, or a run whose new cases never appear in
the output, is a green that verified nothing.
