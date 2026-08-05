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
10. **The row's size, and whether it has an inspector at all.**
   `check-rule-sync.sh` check 9 measures every row: past the byte ceiling it must carry a
   `rule-details/<ID>.md` pointer, and the rows that do not are declared in
   `skills/triangulate/rule-row-baseline.txt` with an `inspector` / `no-inspector`
   annotation. The ratchet runs both ways, so the file can only shrink. Two consequences
   for an `Extends`:
   - If the widened row crosses the ceiling, **extract the procedure** into
     `rule-details/<ID>.md` and leave the row a routing summary. Adding a line to the
     baseline instead is how the debt grew in the first place; do that only with a stated
     reason in the retrospective doc. Note the ceiling asks about extraction, not about
     brevity for its own sake — a summary that must name sub-clauses and describe a
     detector legitimately costs more than one that need not, and trimming substance to
     get under a number is the wrong response to this gate.
   - If the target is listed `no-inspector`, **§3's gate applies before the prose does**.
     A rule that has absorbed several rounds of text without ever acquiring a detector is
     not one more paragraph short of working.
   - **Coverage bound on that column, and it is narrow**: the baseline lists only the rows
     over the ceiling with their procedure still inline, so the annotation answers for
     about a sixth of the rule set and is SILENT for every other rule — including every
     rule whose procedure has been extracted. Absence from the file is not evidence of a
     detector. For any target not listed, determine it directly, remembering that an
     extracted rule names its detector in the detail page rather than in the row:

     ```bash
     grep -l '\*\*Mechanical detection' skills/triangulate/common-rules.md \
       skills/triangulate/rule-details/<ID>.md 2>/dev/null
     ```

     Across the whole set 16 rules of 74 have a detector anywhere. Assume `no-inspector`
     and check, rather than reading silence as coverage.

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

**Naming a class is not the same act as installing its inspector**, and this skill's
default output — more rule text — is the shape that confuses the two. The observed
failure is a review that identified the same dominant class every round, wrote a fresh
paragraph about it every round, and only stopped producing instances of it in the round
that produced a checker. Prose is not a control: code passes through lint, type-check,
test and build, and the documents written *about* the code pass through nothing, so a
rule that exists only as text is enforced solely by the attention of whoever remembers to
apply it — which is exactly the thing that failed.

So a **repeat** `Extends` — one targeting a rule that `rule-row-baseline.txt` annotates
`no-inspector` — does not discharge on prose. Take one of three exits, and name which in
the retrospective doc:

- **Author the detector** (§3.1 below). Even a partial one, with its coverage bound
  stated in the row. Then flip the rule's annotation in the baseline; check 9 fails if
  the annotation and the row disagree, so this is not a step that can be forgotten.
- **Install the obligation somewhere a machine already looks** — a gate block in a phase
  file, a required field in a template, a linter clause — rather than a paragraph a
  reader is trusted to recall.
- **Record the class as undecidable**, naming the specific step no scan can perform.
  "Hard to detect" is not that; "the defect is in whether the cited fact *reaches* the
  conclusion, which is an inference and not a property of any string" is. An undecidable
  class is a legitimate outcome — it is the *unexamined* third round of prose that is not.

The exit is per fold, not per rule: a class recorded undecidable once does not have to be
re-argued, but a fold that adds prose to it anyway must say what the new paragraph does
that the previous ones did not.

**Ablate before folding, and score the REMEDY.** A gate here is red-proved — delete what
it checks and it must fail. A rule had no equivalent until `evals/rule-ablation/` (110
runs, eight fixtures, `docs/archive/audit/2026-08-04-rule-ablation.md`). What it found,
in the order it found it:

- **Detection is not where the rules pay.** Across six fixtures and three rounds, no
  detection difference survived replication. Two headline claims were written up with
  their n stated and both dissolved on retest.
- **The remedy is — where the mechanism is unfamiliar.** Blind-rescored against the
  independent nine-property rubric (round 6.5, scorer agreement ≥94.6%), the deployed
  configuration beat no-catalogue clearly on the buried, unfamiliar-mechanism fixture
  (6.25 vs 4.40 mean, plus 3/8 outright detection misses without the rules) and
  marginally where the platform idiom already encodes the fix (7.25 vs 6.75). The
  round-4 self-scored version of this claim (16/16 vs 0/16) overstated it — self-scoring
  erred in both directions, which is why the re-score is part of the standard.
- **What no rule teaches, no reviewer produces — and taught, they produce it.** The
  panel's nine-property rubric has properties every arm scored 0 on across 29
  blind-scored runs (nesting/concurrency — the one a naive fix uniquely fails). After
  the rule was extended to teach them, the same property went 16/16 with the extension
  and 0/16 without, on both fixtures, with the rule's original clauses saturated in
  both arms (round 8, n=8/cell, blind). A rule transmits exactly what it states —
  no more, and at full rate when it states it plainly. The residual: a clause whose
  wording fits one platform idiom under-transmits on the other, so write cross-platform
  clauses in per-variant words — round 9 reworded the clause into named variants and it
  saturated (8/8) with nothing regressing. Round 9 also added a standing caution:
  **compare arms within one batch.** A blind-scored baseline moved 1/8→5/8 across
  batches on byte-identical materials; a stored cross-batch number is context, never
  the control arm.
- **A section nothing routes to is dead wiring.** The Remedy Floor merged as prose no
  routing path named; a probe of the deployed protocol showed zero of four reviewers
  read it. Wired by one digest line, it moved exactly its own clauses (floor-mapped
  subset 6.75 vs 5.12 and 3.88 vs 0.25 on two fixtures, n=8/cell, blind) while the
  mechanism control stayed flat. A fold into `common-rules.md` is not folded until the
  loading protocol names it — and its ablation must probe reachability FIRST, or W-vs-N
  compares two arms that both lack the content.

**Measure firing before folding.** `evals/rule-firing/measure.py` counts, per rule,
how often it produced a finding across every review artifact the sibling repos have
accumulated — one command, no fixtures, no agents. The 2026-08-05 run found the median
rule fires in 0.50% of the reviews where it existed, 48 of 74 fire in under 1%, and
eight have never fired at all despite being checked 96–270 times each. Run it before
adding a rule: a catalogue whose median row fires twice a year should make "a reviewer
once missed this" a weak argument for growing it, and the tool will also say whether the
rule you are about to extend is one anybody routes to.

So a fold may not rest on "the round would have missed this". It should rest on "the round
would have fixed it wrong", and it carries the burden either way: a fixture holding the
defect, the correct remedy written down FIRST, runs with and without the rule, and **n
beside every number**. A single round is a look, not a result — write the claim only after
it replicates.

Three standing cautions:

- **Do not shrink a row to its digest name to save bytes.** The name-only arm measured
  exactly that move and scored identically to carrying nothing. Whatever the rules buy,
  the procedure buys it.
- **Write the remedy rubric independently of the rule.** Round 4 scored the rule against
  its own text; round 5 rebuilt the rubric with a panel that had never seen it. That
  panel confirmed all three of the rule's clauses AND demanded six more the rule never
  taught — including the one that matters most, since a naive save/restore passes both
  tests the rule asks for and fails only the concurrency case it does not. **A panel of
  this kind is the cheapest audit of a rule this repo has**: it costs ten read-only
  agents and it tells you what the rule is missing, which no amount of mining more
  review artifacts will.
- **A null is the WEAKER reading.** The fixtures are written by someone who knows the
  target rule, so the bias runs toward legibility: "no difference on a diff I constructed"
  is a much softer statement than "no difference".

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
bash hooks/check-rule-sync.sh skills/triangulate   # repo-local, both halves
bats tests/                                        # full suite green
```

**Run the repo's own linter against the repo's own tree — both halves matter.**
`check-rule-sync.sh` defaults its subject to `<dir of the script>/../skills/triangulate`,
so `bash ~/.claude/hooks/check-rule-sync.sh` with no argument <!-- rule-sync-example -->
checks the INSTALLED copy under `~/.claude/`. A fold edits the repository source and the installed copy is stale
until `install.sh` runs, so that form reports on the pre-fold tree and cannot fail for the
reason the gate claims (R50 clause iii). The same staleness argument applies to the SCRIPT,
not only to its subject: a fold that changes the linter itself — adding a check, teaching it
a new sync point — would run the pre-fold linter against post-fold rules and pass because
the new check does not exist in the copy being executed. Invoke both from the repo.

**This invocation prompts, deliberately.** `settings.json` allowlists the linter only at its
installed absolute path, because that copy sits under `~/.claude/hooks/` where
`block-sensitive-files.sh` keeps a session from rewriting it. A relative-path allow entry would be
cwd-independent and this file is `install.sh`-merged into the GLOBAL `~/.claude/settings.json`, so
`Bash(bash hooks/check-rule-sync.sh *)` would pre-approve executing whatever any repository ships
at that path — laundering the deny and ask lists in every project on the machine. One permission
prompt per fold is the correct price; do not "fix" it by adding the entry.

Then read the `Subject:` line the linter prints and confirm it is the tree you edited. That
is the check, not the ID range: a fold consisting only of `Extends` items adds no rule ID, so
the stale-subject run and the correct run print a byte-identical `R1-R<n>` range and comparing
it discriminates nothing. When the fold DOES add an ID, confirm the printed maximum matches it
as a second, cheaper signal.
A rule-sync failure means the edit map above was applied incompletely — fix the named
sync point; never silence the linter. Judge each gate by its OWN exit status (R44): run
it unpiped, or redirect output to a file and inspect afterwards — piping a gate through
`head`/`tail`/`grep` reports the pipe tail's status and masks a real failure as green.

A zero exit is only half the verdict (R50 clause ii): "examined nothing" and "found
nothing wrong" are the same status. Quote the count alongside it — the number of tests
the suite actually ran, and the new tests among them by name. A `bats tests/` that
collected fewer files than the directory holds, or a run whose new cases never appear in
the output, is a green that verified nothing.
