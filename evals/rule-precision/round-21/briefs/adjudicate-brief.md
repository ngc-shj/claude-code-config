# Adjudication brief

You are deciding, for each of 79 claims about one change, whether the claim is
an accurate report of a genuine defect. You are not reviewing the change and you
are not proposing fixes.

## Materials

- The change: `/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F11-exports.diff`
  Read it in full, first.
- The claims: `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-21/new-claims.tsv`

Read nothing else in that repository. How many reviewers made a given claim is
deliberately withheld; popularity is not evidence.

## The standing assumption — read this twice

Judge the diff as a real pull request into a real, working codebase. Everything
the diff does not show **exists and is correct**: the object-store client, the
auth middleware, the job scheduler, the migration runner, the rest of the test
suite. The diff is the change, not the whole system.

So a claim whose entire content is "X is not present in the diff" is NOT a
defect unless the diff itself makes the problem visible — for example, the diff
adds a call to something it also defines incorrectly, or the diff's own logic is
wrong on its own terms.

## Verdicts

For each claim, exactly one:

- `real` — the claim is accurate about the code the diff shows, AND it names
  something that should be changed before this merges.
- `wrong` — the claim misreads the code: it describes behaviour the diff does
  not have, cites a symbol or path the diff does not contain, or its stated
  mechanism does not follow from the code.
- `not-a-defect` — the claim is accurate as far as it goes but is not a defect
  in this change: it depends on code the diff does not show, it is a preference
  or a style call, or it asks for work beyond the change's scope.

And a reason tag, one word, only for the last two:
`misreads-code` | `outside-diff` | `preference` | `scope`

Judge each claim on its own. Do not let one claim's verdict pull another's.
Severity is not your concern — a real but minor defect is still `real`.

## Output

Tab-separated, header row, one row per claim, in the order given:

```
cluster_id	verdict	reason
R21-API-01	real
R21-API-07	not-a-defect	outside-diff
```

79 rows. Count them before you finish. Write the file to the output path given
in your instructions, then reply with the single word DONE.
