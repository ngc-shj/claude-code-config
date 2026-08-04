# The independent remedy rubric

Round 4 scored each arm's proposed fix against clauses read off R54's own text,
so the arm holding R54 was scored against the document it had been handed. This
is the fix for that: a rubric produced by a panel that never saw R54.

## Method

Ten agents, five per defect variant. Each was given only the defective code and a
neutral statement of what is wrong, and asked to *enumerate every property a
correct fix must have* — mechanism, failure modes, and evidence. None was asked
to review anything, none saw the rule set, and each had the whole task to itself,
so nothing here is an artifact of attention dilution.

Variants: the `AsyncLocalStorage` audit-skip flag (F9) and the Postgres
`SET LOCAL` RLS exemption (F6).

Convergence was high. Nine properties reached majority in both panels; most were
unanimous.

## The rubric

| | Property | In R54 before this? |
|---|---|---|
| P1 | Grant delimited by a scoped construct, not a bare setter | yes |
| P2 | Restoration also happens on the throw/reject path | yes |
| P3 | Restore the **previous value**, not a hardcoded off/false | **no** |
| P4 | **Await** the covered work before restoring | **no** |
| P5 | Do not mutate caller-shared state — fresh frame, or same connection handle throughout | **no** |
| P6 | No unpaired setter survives; nothing else can set the flag | partly |
| P7 | Test: the control still refuses immediately after the call, same context | yes |
| P8 | Test: the same, when the covered work throws | **no** |
| P9 | Test: nesting, or a concurrent request/transaction unaffected | **no** |

## What this settles, and what it costs

**It vindicates the rubric round 4 used.** P1, P2 and P7 are R54's three clauses,
and a panel that had never read R54 required all three. They are not an artifact
of scoring the rule against itself.

**It also convicts R54.** Six further properties are demanded unanimously and the
rule taught none of them. One panellist stated the consequence exactly: a naive
`try/finally` on the shared object satisfies the return-path and throw-path tests
and fails only the concurrency one — so the two tests R54 does ask for certify
precisely the wrong fix.

So round 4's headline was wrong in the direction I had not guarded against. The
correct statement is not "the rules produce a complete fix and their absence does
not". It is:

> Carrying the rules reliably produces **the three properties the rule contains**.
> A correct fix needs about nine. Neither arm produced those.

R54 has been extended with the six (see `rule-details/R54.md`). That extension is
itself a fold made under this eval's own standard — direct evidence that reviewers
holding the rule fixed it wrong — and it is owed its own ablation before anyone
claims it works.

## Not yet run

The blinded re-score. `score/rubric.md` holds the nine properties in the form a
scorer needs; the remaining work is to strip arm identity from the 32 round-4
`Fix:` texts, shuffle them, and have agents that do not know which arm produced
what score each against all nine. Doing that by hand would reintroduce exactly
the bias this round exists to remove, so it is left set up rather than half-done.
