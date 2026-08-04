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

R54 has been extended with the six (see `rule-details/R54.md`). That extension
was owed its own ablation, and got it: round 8 (audit doc) compared extended
against pre-extension R54 with everything else held fixed, blind-scored against
this rubric — which pre-dates the extension, so scoring the extended arm
against it is not self-scoring. The extension's properties went 4.12/5 and
5.00/5 with it versus 0.25/5 and 1.75/5 without; P9, the clause this file said
mattered most, went 16/16 vs 0/16; the original three clauses stayed saturated
in both arms. One clause under-transmits: P5's connection-handle wording
reached 1/8 on the GUC fixture even when carried.

## The blinded re-score (run 2026-08-05)

The 32 round-4 `Fix:` texts, arm identity stripped, shuffled, scored by three
agents blind to provenance, majority vote per property (agreement 94.6–99.6%).
It confirmed the F6 effect (6.25 vs 4.40 mean, plus three arm-C detection
misses), halved the F9 one (7.25 vs 6.75), and corrected round 4's self-scored
claim that F9 arm C lost the error path 7 times in 8 — blind, that cell is
8/8, because the `AsyncLocalStorage` idiom restores on throw by construction.
P9 (nesting/concurrency) is 0/29 across all arms: the panel's sharpest warning
holds blind. Full tables: the audit doc, round 6.5.
