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
given, and part of its measured advantage is definitional. Re-deriving the
correct remedy independently — from someone or something that has not seen the
rule — is the single change that would settle how much of that effect is real.
It is the first item in the audit's "what follows".
