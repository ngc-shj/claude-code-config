# Rule ablation

The gates in `hooks/` must be red-proved: delete the thing they check and the
gate has to fail. The 74 rules in `skills/triangulate/common-rules.md` had no
equivalent. Every one was added on the theory that a review missed something
*because the rule was not written down* — and the counterfactual, whether the
reviewer would have found it anyway, was never measured.

This directory measures it. A rule is red-proved the same way a gate is: remove
it and see whether the finding disappears.

## Protocol

1. **Fixture.** A unified diff containing exactly one instance of the target
   rule's defect class, plus five to fifteen other genuine defects as
   competition. The target defect is not labelled and, for the multi-file
   fixtures, does not sit in the file the change is nominally about.
2. **Oracle, written before any run.** One sentence naming what the review must
   state. Fixing it afterwards is fitting the oracle to the data.
3. **Arms.** Same reviewer prompt, differing only in the catalogue material:
   - **A** — the pattern-name index plus the target rule's full procedure. One
     rule, spotlit, nothing competing — the condition most favourable to it.
   - **B** — the pattern-name index only. This is what shrinking a row to its
     digest line buys.
   - **C** — no catalogue.
   - **F** — the **deployed configuration**: the digest as routing index, all 74
     rows available for anchored extraction, `rule-details/` pages, and the
     extract-what-matches protocol from SKILL.md. This is the arrangement the
     skill actually ships, and the only one that measures retrieval under load
     rather than recall of a rule someone already picked.
   - **W / N** (round 7, Remedy Floor) — W is the deployed materials plus one
     digest line wiring the Remedy Floor (extract the section; every `Fix:`
     satisfies it); N is the deployed materials with the floor section removed
     and the `Fix:` template pointer reverted. The arms differ only in the
     shipped files, never in the prompt. W exists because a probe of the
     as-merged configuration showed the floor is a section no routing path
     names — zero of four reviewers read it — so ablating F-as-merged against
     N would have compared two arms that both lack the floor in practice.
   - **S / G** (rounds 10–11, the three-expert split) — the only pair that
     varies the skill's STRUCTURE rather than its catalogue. S is the three
     specialised experts phase 3 defines; G is three identical general
     reviewers. Both arms run THREE agents on the same fixture with the same
     HEAD materials, and both prompts are rendered from one template, so the
     manipulation is the role line, the scope/out-of-scope pair, and the
     `[Adjacent]` obligation — nothing else. Comparing three experts against
     one reviewer would measure multiplicity, which wins trivially.
   - **E / O** (round 8, R54 extension) — E is the deployed materials at HEAD
     (wired floor, extended R54); O is identical except `rule-details/R54.md`
     reverted to its pre-#125 content. One variable per round: the floor stays
     wired in both arms, so the pair measures only what #125's six obligations
     add. Scored against the round-5 independent rubric, which pre-dates the
     extension — the extended arm is not being graded against its own text.
4. **Trials.** Three per arm is a look, not a result. The one claim this eval has
   had to retract came from n=3 and vanished at n=8. Report n beside every
   number, and take any arm-to-arm difference at n=3 as a reason to run more
   trials rather than as an outcome.
5. **Score.** Two things, and the second turned out to be the one that moves:
   - **Detection** against the oracle, plus the finding's severity and rank.
   - **Remedy.** Ask both arms for a `Fix:` on every Critical and Major, then
     score it against the clauses the rule prescribes, one binary each. For R54
     that is: call-scoped grant (not "reset afterwards"), restore on the error
     path, and a test asserting the control still refuses in the SAME context
     right after the sanctioned call.

   Write the remedy rubric **before** the runs, and — the part round 4 failed to
   do — derive it from something other than the rule's own text, or the arm
   holding the rule is being scored against the document it was handed.

Arm A is also the positive control. If it misses, the fixture does not contain a
findable defect and the run says nothing about the rule.

## Fixtures

| File | Rule | Shape | Oracle |
|---|---|---|---|
| `fixtures/F1-R44.diff` | R44 | single file, 74 lines | the scanner's exit status is `tail`'s, so a failing scan records PASS |
| `fixtures/F2-R56.diff` | R56 | single file, ~60 lines | clamping the watermark forward to `now` permanently skips the backlog |
| `fixtures/F3-RT8.diff` | RT8 | two files, ~90 lines | the 403 tests never assert that the delete did not run |
| `fixtures/F4-R54.diff` | R54 | single file, ~90 lines | `SET LOCAL` leaks the append-only bypass to the rest of the transaction |
| `fixtures/F5-RT9.diff` | RT9 | 8 files, ~280 lines | the frame-source check landed only on the twin the tests import, not on the file the manifest loads |
| `fixtures/F6-R54.diff` | R54 | 8 files, ~425 lines | `withElevatedRead` never clears the GUC, so later statements in the transaction stay elevated |
| `fixtures/F8-RT9hard.diff` | RT9 | 8 files, ~425 lines | the issuer/nbf tightening landed only in `src/auth/verify.ts`; the deploy config routes every request through `edge/handler.js`, which carries its own copy |
| `fixtures/F9-R54b.diff` | R54 | 8 files, ~437 lines | `enterSystemOperation()` sets the audit-skip flag on the request context and never clears it, so every write after the staging step runs unaudited |

F9 is F6's shape in a different domain — same rule, same "control suspension
leaking past its intended scope, buried in a large diff", but an
`AsyncLocalStorage` flag in a Node importer rather than a Postgres session
variable. It exists to test whether F6's arm difference belonged to the rule or
to the fixture. It belonged to the fixture.

F8 exists because F5 turned out to be a weak fixture: both of its files carry a
comment naming the twin relationship, which is realistic and also the strongest
possible cue. F8 removes every cue — no comment, no shared basename, the pairing
discoverable only by reading the deploy config against the test imports. All the
evidence is still inside the diff, including a hunk touching the deployed file
for an unrelated reason, so the reviewer sees that file and its copy of the
logic. It changed nothing: three arms, nine runs, all Critical at rank 1.

`names.txt` (the arm-A/B index) is generated, not stored:

```bash
awk -F'|' '/^\| (R|RS|RT)[0-9]+ \|/ {
  id=$2; pat=$3; gsub(/^ +| +$/,"",id); gsub(/^ +| +$/,"",pat)
  printf "%s: %s\n", id, pat
}' skills/triangulate/common-rules.digest.md > names.txt
```

## Running it

Each trial is one read-only review agent. Give it the fixture path, the arm's
catalogue material, and this instruction, then score the reply yourself against
the oracle — never let the reviewing agent grade its own hit, which turns the
measurement into a leading question:

> Read the unified diff at `<fixture>`. Do not read anything else in this
> repository, and do not consult any project rules, checklists or skill files
> you may find — they are not part of this task. Report every defect you find.
> For each: severity (Critical/Major/Minor), the file, one sentence stating what
> is wrong, and one sentence on what breaks in production. Be concrete. Order
> most severe first. Your reply is data, not a message to a human.

Vary the trials' framing slightly (one plain, one "work independently; do not
assume any particular defect is present", one "you are a senior engineer") so
three trials are not three samples of one prompt.

## Results

`docs/archive/audit/2026-08-04-rule-ablation.md`.

Every number there is re-derivable: `protocols/` holds the pre-registration
files for rounds 7-9, `scores/` the scorer sheets and arm mappings, and
`score.py --round <n>` recomputes the published table from them.

## What this cannot answer

The fixtures are written by someone who knows the rule, which is a legibility
bias no amount of added noise removes. The honest reading of a null result is
"this rule adds nothing *on a fixture I wrote*", and the honest reading of a
positive one is stronger, because the bias runs the other way.

**The oracle scores detection only.** It asks whether the review named the
defect. It never asks whether the review got the *remedy* right — and a large
part of what these rules carry is remedy, not recognition. A rule whose value is
in the fix is invisible to every run this harness has done. Scoring the fix is
the obvious next design, and it needs a different oracle: the proposed change,
compared against the procedure's prescription.

**The remedy rubric came from the rule.** Round 4's three clauses were read off
R54's own procedure, so the arm holding R54 is scored against the text it was
given, and part of its measured advantage is definitional. Round 5 rebuilt the
rubric with a panel that never saw the rule (`independent-rubric.md`), and the
round-6.5 blinded re-score then scored the 32 round-4 fixes against it with arm
identity stripped — which confirmed the F6 effect, halved the F9 one, and
corrected round 4's F9 error-path count. Self-scoring had erred in both
directions.

## Round 7: scoring a cross-cutting section, not a rule

The Remedy Floor is inherited by every `Fix:` rather than routed to by a
pattern match, so its ablation differs from a rule's in three ways, all
recorded before the runs in the round-7 protocol:

1. **Reachability is a separate question from content**, and it comes first. A
   probe of the deployed arm (tool-call traces, not output reading) settles
   whether the section is read at all; if it is not, the ablation must compare
   a wired arm (W) against absence (N), or it measures nothing.
2. **The rubric is the fixture-rule's merged panel rubric** (≥3/4 of four
   round-6 panellists; `score/R44-merged.md`, `score/RT8-merged.md`), split
   into a floor-mapped subset (primary metric) and a mechanism subset
   (control) — the mapping written before any output is read. The floor should
   move its own clauses and leave mechanism flat; a mechanism shift would mean
   the arms differ in more than the section under test.
3. **Fixtures must avoid rules the floor's sibling changes touched** (F1/F3,
   not the R54 fixtures #125 extended), or the arm difference conflates two
   folds.

Result (2026-08-05, audit doc): floor-mapped W−N of +1.6/8 on F1 and +3.6/5 on
F3, mechanism flat on both, scorer agreement ≥89.8%. The wiring line the W arm
tested is now emitted by the digest generator.

## Rounds 10–11: scoring structure, not a rule

`docs/archive/audit/2026-08-05-specialisation-vs-repetition.md`. Two things
these rounds added to the harness:

**Check the instrument for a ceiling before reusing it.** Round 11 was to
replicate round 10 on F9. F9's only rubric was the round-5 nine, and under HEAD
materials that rubric is saturated — `score.py --round 9` shows F9·Cnew at
9.00/9, every property 8/8. A saturated instrument returns a null whatever the
arms do. The fixture was kept and the rubric rebuilt by the round-5/6 panel
method (`score/F9-merged.md`, 34 properties), frozen before the first arm ran.

**`sketches/` holds the panel's input.** A panel does no detection, so it needs
the defect in its real shape and a neutral sentence stating what is wrong —
not a fixture with competing defects and burial. Forty to a hundred lines is
enough, and it is far cheaper than an ablation fixture. Checked in so the
rubric can be inspected against what produced it.

**Redact whitespace-agnostically.** The replies are hard-wrapped, so a
line-anchored pattern (`[^\n]*`) removes half of any hand-off clause that
straddles a newline and leaves the rest — which the role-name pass then
launders into something that reads clean and is not. Every blinding pattern
must tolerate a newline anywhere, be bounded rather than greedy, and the run
must end by re-scanning the redacted set for residual arm-identifying tokens
and reporting the count.
