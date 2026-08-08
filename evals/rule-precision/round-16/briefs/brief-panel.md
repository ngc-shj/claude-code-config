# Seed panel brief

You are enumerating defects in one change, exhaustively. You are building an
inventory, not writing a review: nobody downstream is going to fix things from
your list, so there is no reason to filter it down to what is worth a reviewer's
attention. A separate panel decides later which of your entries are genuine
defects, so **do not judge, hedge, or rank by confidence** — if you can state a
concrete problem about the code the diff shows, list it.

## Materials

- The change: `/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F10-webhooks.diff`
  Read it in full, first, with the `Read` tool.

Read nothing else. In particular: nothing else under
`/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/` — no other file under
`evals/`, no `docs/`, no `skills/`, no protocol, rubric, sketch, or other
fixture. They are not part of this task and reading them invalidates the run.

Treat that diff as the whole change: there is no branch to check out and no
other source for the reviewed project. Where the diff shows a file's
post-change state, reason from it directly.

Judge the diff as a real pull request into a real, working codebase. Everything
the diff does not show **exists and is correct**: the schema beyond the
migration, the HTTP client, the auth layer, the logger, the rest of the test
suite. The diff is the change, not the whole system. So "X is not present in the
diff" is worth listing only where the diff itself makes the problem visible.

## What to cover

Go file by file, and then across files. Correctness, edge cases, error handling,
concurrency, security, data model, the migration against the code that uses it,
the tests against the behaviour they claim to cover, and the documentation
against the behaviour the code has. A pre-existing bug in a file the diff
touches is in scope.

Do not stop at the first serious problem in a file. Do not summarise several
problems into one entry — one entry per distinct problem, where distinct means a
single change would not resolve both.

## Output

Write a tab-separated file, header row, one row per defect, to the path given in
your instructions:

```
n	severity	file	title	what_is_wrong
1	Critical	src/x.py — send()	the retry loop never resets the counter	<one sentence, concrete, naming the mechanism>
```

- `n` numbers your rows from 1.
- `severity` is one of `Critical` / `Major` / `Minor`.
- `file` is the path, then ` — ` and the symbol or line the problem sits at.
- `title` is one line naming the problem, specific enough that another engineer
  reading the diff can find it.
- `what_is_wrong` is one sentence stating the mechanism — what the code does and
  why that is wrong. No fix, no severity argument, no hedging.
- Every field is on one line. No tabs inside a field. No blank rows.

Your output is data, not a message to a human. After writing the file, reply
with the single word `DONE`.
