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

**`Extends` is not a smaller `Novel` — it has its own edit set, and §2 below does not
cover it.** §2 is written for *adding* a rule: its steps append a row, append a template
line, bump a range string. Widening an EXISTING rule leaves every one of those in place
and stale, and `check-rule-sync.sh` mostly cannot see it. The linter compares rule IDs,
and the row's pattern against a `rule-details/<ID>.md` heading — and nothing else. It
never compares the pattern name carried in the Recurring Issue Check template line or in
the digest's own row, never the `N/A` / `Checked` wording, and never whether a phase
file's manual check still mirrors the row. That blind spot is not hypothetical: it is how a run has shipped a
widened row whose Recurring Issue Check line still let a reviewer answer `N/A` on exactly
the case the widening added, and a widened rule whose `rule-details/<ID>.md` still
prescribed the superseded procedure.

For each `Extends-<id>`, walk this list and record the outcome of every item, including
"unchanged, because …":

1. **The row's pattern name.** Does it still describe the widened trigger? A reviewer
   routes from the digest's pattern-name column and never opens the row otherwise.
2. **The row's severity cell.** Does the added mechanism reach a severity the cell does
   not offer? Widening the body without the cell leaves the new case rated by the old
   ceiling.
3. **The Recurring Issue Check template line** — BOTH branches. The `N/A` escape must no
   longer be answerable for a diff the widening now covers, and the `Checked` branch must
   name what the widening obliges. Closing only the `N/A` side is the common half-fix.
4. **`rule-details/<ID>.md`**, when the row points to one. The mandatory full procedure is
   what a reviewer executes; a widened row over an un-widened procedure is a claim
   stronger than the implementation (R49).
5. **Extended obligations**, when the row points there — the section title as well as its
   steps, since the title is what a reader matches against the row.
6. **Phase-file manual checks that mirror the row** (`phases/phase-1-plan.md`,
   `phase-2-coding.md`, `phase-3-review.md`). Grep the phase files for the rule ID: a
   check written against the narrow trigger passes on the mechanism the widening added.
7. **Cross-ports of the same text into other skills** (Pass 3). If the wording changed
   here, the copy there is now drift.
8. **Sibling rules that cite this one.** Grep for the ID: a cross-reference written
   against the old scope may now point at the wrong rule, or need the new clause named.
9. **The row's `**Mechanical detection**` paragraph and the hook it names.** Does the
   coverage/limitations sentence still bound what the widened row claims? A hook that was
   an honest partial detector for the narrow rule becomes an R49 overstatement the moment
   the rule grows past it: the reviewer runs it, gets a clean run, and reads that against
   the *new* claim. Either widen the hook, or say explicitly which part of the widened
   obligation it does not see. This item exists because a round shipped a widened RT10
   whose coverage sentence still read "It covers neither RT10 clause", which by then was
   both stale and wrong in the dangerous direction.

Then run §2 step 1's FIRST TWO bullets (the table row, and the `rule-details/<ID>.md`
pointer and identity) and §2 step 7 (digest regeneration). Any phase-file edit item 6
produces is additionally subject to §2 step 6's two constraints — text lands above the
`## END-OF-PHASE-<N>` terminator, and a new `### Step` heading obliges the front-matter
update. §2's remaining items — step 1's *new* template line, the RS/RT bracket bump and
range-string bullets, and the range strings in steps 2-5 — apply only when an ID was
ADDED.

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
bash hooks/check-rule-sync.sh skills/triangulate   # must exit 0 — all sync points consistent
bats tests/                                        # full suite green, including new tests
```

**Pass the skill directory explicitly, and run the repo's copy of the hook.** With no
directory argument the linter resolves its target relative to its own location, so the
installed hook invoked bare lints `~/.claude/skills/triangulate` — the *installed* copy,
which does not contain the edits just made. It prints the same
`OK: R1-R… consistent` line either way. That is the R50 shape this file's own gate
instruction used to have: a green whose subject was the wrong tree. Prove the subject
before trusting the status — e.g. grep the regenerated digest in the repo for a string
from this round's edit and confirm the installed digest lacks it.

This command is deliberately NOT in `settings.json`'s allow list, so it prompts once per
round. A `Bash(bash hooks/check-rule-sync.sh *)` entry would be cwd-relative and would
auto-approve executing whatever `hooks/check-rule-sync.sh` happens to exist in any
repository the session is opened in — a wider grant than the gate is worth. The installed
form accepts the same argument (`bash ~/.claude/hooks/check-rule-sync.sh skills/triangulate`)
and is already allow-listed, but it runs the INSTALLED linter against repo content, so it
is only equivalent while `install.sh` is current; prefer the repo copy and accept the
prompt.

A rule-sync failure means the edit map above was applied incompletely — fix the named
sync point; never silence the linter. Judge each gate by its OWN exit status (R44): run
it unpiped, or redirect output to a file and inspect afterwards — piping a gate through
`head`/`tail`/`grep` reports the pipe tail's status and masks a real failure as green.

A zero exit is only half the verdict (R50 clause ii): "examined nothing" and "found
nothing wrong" are the same status. Quote the count alongside it — the number of tests
the suite actually ran, and the new tests among them by name. A `bats tests/` that
collected fewer files than the directory holds, or a run whose new cases never appear in
the output, is a green that verified nothing.
