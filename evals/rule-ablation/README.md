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
   - **A** — the pattern-name index plus the target rule's full procedure.
   - **B** — the pattern-name index only (the rule's name is present, its
     procedure is not). This is what shrinking a row to its digest line buys.
   - **C** — no catalogue.
   Single-file fixtures were run with a two-arm form (A: the rule alone; C: no
   catalogue), which is the condition *most* favourable to the rule.
4. **Trials.** Three per arm. Reviews are non-deterministic; one run measures
   nothing.
5. **Score.** Detection against the oracle, and the finding's severity and rank
   in the emitted list. Rank matters: a Major at position 6 of 16 is a different
   outcome from a Critical at position 1, because the fix loop treats them
   differently.

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
