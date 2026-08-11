# Review brief

The change under review is the unified diff at
`/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F11-exports.diff`.

Treat that diff as the whole change: there is no branch to check out and no
other source for the reviewed project. Where the diff shows a file's
post-change state, reason from it directly.

## Your role

You are a code reviewer. Review the change.

Nothing in the change is out of scope for you: correctness, architecture, edge
cases, error handling, security, and tests are all yours to report on.

## Catalogue materials — read these, they are part of the task

The reviewing catalogue lives in `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/cat-W`. Use it exactly as its
`SKILL.md` prescribes:

1. Read `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/cat-W/common-rules.digest.md` whole-file with the `Read` tool
   (not `cat`/`head`). Its last line is `## END-OF-DIGEST`; if that is not the
   last line you received, the read was partial — re-read.
2. Match its pattern names against the diff. Use anchored `rg` queries to
   extract only the triggered rows from `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/cat-W/common-rules.md`, plus
   the `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/cat-W/rule-details/<ID>.md` page for any selected row that
   points to one.
3. Extract the Remedy Floor once:
   `awk '/^### Remedy Floor/,/^### Anti-Deferral/' /tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/cat-W/common-rules.md`
   Every `Fix:` you write for a Critical or Major finding must satisfy it.
4. Do not read all of `common-rules.md` unless routing is inconclusive; if you
   fall back to that, record the reason in your output.
5. Follow any further extraction the digest itself instructs you to perform.

Read nothing else. In particular: nothing under
`/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/` except the fixture
named above — no other file under `evals/`, no `docs/`, no protocol, rubric,
sketch, or other fixture. They are not part of this task and reading them
invalidates the run.

## Obligations — apply to every finding

- Only specific and actionable findings. Vague findings are prohibited.
- Classify each finding Critical / Major / Minor, using severity criteria
  appropriate to the impact.
- For each finding give: the file, the symbol or line, the severity, one
  sentence stating what is wrong, and one sentence on what breaks in
  production.
- **Every Critical and Major finding carries a `Fix:`** — the change you
  propose, concrete enough that another engineer could implement it without
  asking you a question, and satisfying the Remedy Floor.
- **Cross-cutting verification**: for each changed pattern, check whether the
  same pattern appears elsewhere in the diff without the equivalent change, and
  report any missed location.
- **Codebase awareness**: before writing a recommendation, check whether the
  change already contains a helper or shared path that the new code
  reimplements, and include the evidence.
- A pre-existing bug in a file that appears in the diff is IN SCOPE.
- Order findings most severe first.
- If you have no findings, state `No findings`.

## Output

Write your complete review to the output path given in your instructions, using
`Write`. Use this shape:

```
### <Severity>: <one-line title>
File: <path> — <symbol or line>
What is wrong: <one sentence>
What breaks in production: <one sentence>
Fix: <the concrete change; required for Critical and Major>
```

Your review is data, not a message to a human. After writing the file, run
`wc -l <your output path>` and reply with `DONE <n>` where <n> is that count.
Do not reply before the file exists.
