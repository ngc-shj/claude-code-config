# F11 generation prompt

Committed before F11 exists. The agent given this text is told nothing about the
arms, the Finding Floor, the hypothesis, or that anything will be measured — the
round asks whether clause 1 suppresses findings about code outside the change,
and an author who knew that would have a live reason to choose how much such
code the diff leans on.

F10 was commissioned the same way (`../round-16/README.md`): domain, file shape,
line budget, and an instruction not to label or count what it introduces.

---

## The task

Write a unified diff for one pull request into an existing, mature production
codebase. Output **only** the diff, to the path you are given. No commentary, no
summary, no list of what it contains, before or after.

## Shape

- **Domain**: a scheduled export pipeline for a B2B analytics product — a
  customer configures a recurring export of their data to their own object
  storage, and a worker builds the file and uploads it.
- **Language and stack**: Go 1.22, standard library plus `database/sql`; a
  small internal `storage` package for the object-store client already exists
  and you may call it.
- **Size**: 7 to 9 files, 400 to 500 added lines. Comparable to a real feature
  PR, not a toy.
- **Composition**: config/API surface, the worker, a data model, a SQL
  migration, a docs page, and tests. The proportions are yours.

## What makes it usable

- It must read as a change a competent engineer submitted on a normal day —
  under time pressure, not incompetent.
- The surrounding system exists and is not shown: the auth middleware, the job
  scheduler, the object-store client, the rest of the test suite. Write as if
  they are there and correct, because they are.
- Include a docs page that describes the feature's behaviour in prose.
- Include tests that the author believed were adequate.

## What not to do

- **Do not label, count, mark, or comment on any problem the change contains.**
  No `// BUG`, no "note that this is wrong", no summary of weak points.
- Do not write a deliberately terrible diff, and do not write a flawless one.
  Write the PR you would actually send.
- Do not mention this prompt, reviewing, evaluation, or defects anywhere in the
  output.

## Output

The diff alone, at the path given in your instructions, in `git diff` format
with `---`/`+++` headers and `@@` hunks, applying against a tree that does not
yet contain these files.
