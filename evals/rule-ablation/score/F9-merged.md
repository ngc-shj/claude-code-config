# Merged panel rubric — R54 fixture (F9), audit-skip flag

Majority rubric merged from four panellists (kept: ≥3/4 support; merge performed
by an agent shown only the four panel outputs, never the rule set, never the
fixture diff, never any review output). Panellists saw only
`../sketches/F9-audit-skip.md`. Method: rounds 5 and 6.

Built for round 11 because F9's other rubric — the round-5 nine
(`../independent-rubric.md`) — is **saturated** under HEAD materials
(`score.py --round 9`: F9·Cnew is 9.00/9, every property 8/8). A ceiling cannot
show a difference in either direction. This rubric was frozen before the first
round-11 arm agent ran.

## Pre-registered subset — `untaught`, the primary metric for round 11

Each property is tagged by whether the catalogue materials **both arms carry**
state it: R54's row plus `rule-details/R54.md`, the Remedy Floor's five clauses,
and the cross-cutting/codebase-awareness obligations that appear in both arms'
prompts.

- **`untaught` (primary): Q8 Q10 Q14 Q18 Q19 Q22 Q25 Q26 Q31 Q32 Q33 Q34** —
  nothing in the materials asks for these, so this is the only place an effect
  of *who is reading* can appear.
- **`taught` (control): the other 22** — expected saturated in both arms. Not
  saturated ⇒ the arms differ in more than the prompt ⇒ the primary comparison
  is void.

`protocols/round-11.md` defined the split as "corresponds to one of the round-5
nine". Applying it turned up two classes the wording did not anticipate, and
both are resolved here, before any arm output existed:

1. R54 teaches clause (d) — a failed restore must abort and must not mask the
   callback's error — which is **not** among the round-5 nine. Q16 is therefore
   `taught`.
2. The Remedy Floor and the shared cross-cutting obligations teach properties
   R54 does not (Q15, Q17, Q20, Q24, Q28). They are `taught` too: the point of
   the split is "the materials transmit this to both arms equally", not "R54
   specifically says it".

Doubtful cases were resolved toward `taught`, which shrinks the primary subset
and makes a null on it the cleaner statement. The borderline ones are Q9, Q11,
Q12, Q13, Q17, Q20, Q21. Every property's per-arm rate is published, so any
reader can re-bucket them.

**`untaught` is untaught by the triangulate catalogue.** Both arms run as agents
in this repository, so both inherit `CLAUDE.md` and the always-loaded
`rules/common/*.md`, which do state some general testing discipline (Q26, Q32,
Q33). That is equal across arms and so cannot bias the comparison, but it means
a saturated `untaught` property is not evidence that a reviewer invented it.

## The rubric

Q1. Does the fix make the `skipAudit` exemption apply only to a bounded region of execution — with a definite end in the source — rather than a durable field set on the request context, so that any write executed after that region sees no exemption? (4/4)

Q2. Is the exemption expressed as a callback-scoped API (e.g. `runAsSystemOperation(fn)`) that makes entering and leaving one call, rather than a paired enter/exit whose closing a caller can forget? (3/4)

Q3. Is the set-only `enterSystemOperation()` removed, unexported, or made unreachable from application code, so no exported API can set `skipAudit` without also supplying the region it applies to? (4/4)

Q4. Does the exemption end on the throw path as well as the normal-return path — via `finally`, or via `storage.run` unwinding — so a `prisma.importStaging.createMany` rejection inside the chunk loop leaves the context unexempted? (4/4)

Q5. Is the scope async-correct — does it await the callback's promise so every awaited `createMany` in `stageRows`' chunk loop is still inside the exemption, rather than ending when the body returns a still-pending promise? (4/4)

Q6. Does the exit restore `skipAudit` to the value it held on entry, rather than unconditionally assigning `false` or deleting it, so an inner system-operation scope exiting does not re-enable auditing for a still-open outer one? (4/4)

Q7. Does the scope avoid mutating the `RequestContext` object held by the outer store — establishing a fresh store (e.g. `storage.run({ ...currentContext(), skipAudit: true }, fn)`) — so a sibling async branch of the same request running outside the scope does not see `skipAudit` true at its write time? (4/4)

Q8. If a copied or child context is used, does it carry `requestId`, `actorId`, and `orgId` forward unchanged, so `currentContext()` reads inside the exempt region (and in code it calls, e.g. `ctx.orgId` in `applyBatch`) are identical to the parent's? (3/4)

Q9. Does the skip state live only on the per-request async context — no module-level variable, static, singleton, or global/config flag — so one request's exemption can never skip another concurrent request's writes? (4/4)

Q10. Is the exemption non-one-shot — `assertAudited` neither clears nor consumes the flag — so all N `createMany` calls in a multi-chunk staging loop are exempted rather than only the first? (3/4)

Q11. Is `RequestContext.skipAudit` made unwritable from outside the context module (removed from the public shape, `readonly`, or key-hidden) so that `ctx.skipAudit = true` at a call site is a compile error, with no cast used to defeat it? (3/4)

Q12. Does `assertAudited` keep both existing branches unchanged — the early return for non-mutating actions, and the `UnauditedWriteError` throw for a mutating action with no `actorId` and no active exemption — without narrowing `MUTATIONS` or downgrading the throw to a log? (4/4)

Q13. Does the exempt region cover exactly `stageRows`' staging writes and nothing more, leaving `applyBatch`'s `membership.upsert`, the `importStaging.deleteMany` in `runImport`, and the route handler's `orgActivity.create` all on the audited path? (4/4)

Q14. Does the fix explicitly state the disposition of the `importStaging.deleteMany({ where: { batchId } })` in `runImport` — either wrapped in its own system-operation scope or left to the audited path — rather than leaving its new behaviour incidental to the scoping? (3/4)

Q15. Do the staging `importStaging.createMany` writes still pass the guard without an audit record after the fix, rather than the leak being "solved" by making them throw `UnauditedWriteError` or require an actor? (4/4)

Q16. Do errors raised inside the exempt region still propagate unchanged out of `stageRows` and `runImport` — the scoping wrapper does not catch, convert, or swallow them, and a throwing restore does not mask the original error? (4/4)

Q17. Are the observable return values unchanged — `stageRows` still resolving to the staged count and `runImport` still returning an `ImportSummary` with the same `staged`, `applied`, `rejected`, and `batchId`? (4/4)

Q18. Is `contextSnapshot()` prevented from exposing an ended exemption — a snapshot taken after the region shows `skipAudit` cleared, and no snapshot taken inside the region can be reused to re-derive the exemption later? (3/4)

Q19. Does the skip path in `assertAudited` remain observable in production — the log line retained at a level that is actually kept, carrying at minimum model, action, and `requestId` — so a future leak is visible from logs rather than silent? (4/4)

Q20. Are the other call sites named in the exemption API's doc comment — the nightly reconciler and the schema backfill — enumerated and migrated to the scoped form, or explicitly shown not to exist, rather than left unexamined alongside `src/import/bulk.ts`? (4/4)

Q21. Is search evidence shown (not merely asserted) that no assignment to `skipAudit` and no call to the removed unscoped setter remains anywhere outside the single scoping function? (4/4)

Q22. Are the doc comments in `request.ts` updated to describe the bounded contract (the exemption ends when the region ends) instead of continuing to describe an announce-once durable flag? (3/4)

Q23. Is there a test that fails on the pre-fix code and passes on the post-fix code, asserting that a `membership.upsert` following `stageRows` in the same request context is guarded (throws `UnauditedWriteError` with no actor, or is recorded as an audited write)? (4/4)

Q24. Was that pre-fix failure produced by actually running the test against the unfixed code (or against the fix with the restore/scoping deleted), with the observed failure output shown rather than reasoned about? (4/4)

Q25. Do the tests assert the guard's observable outcome — the thrown `UnauditedWriteError` or the emitted audited/skipped record — rather than reading `ctx.skipAudit` directly? (4/4)

Q26. Is each new test's key assertion load-bearing — deleting it makes the test fail rather than pass vacuously — demonstrated rather than claimed? (3/4)

Q27. Is there a separate test that injects a failure into one of the `createMany` chunk writes and then asserts a subsequent mutating write in the same request is still guarded? (4/4)

Q28. Is there a test pinning the non-regression direction — that the staging `createMany` writes themselves still skip the guard — so the fix is not vacuously passing by never exempting anything? (4/4)

Q29. Is there a nesting test: an inner system-operation scope entered inside an outer one, asserting that the inner scope's exit leaves the outer scope's remaining writes still skipping? (4/4)

Q30. Is there a concurrency test under a single `runWithContext` that interleaves the exempt region with an unrelated mutating write and asserts the concurrent non-exempt write is still guarded? (3/4)

Q31. Is there a test covering the `orgActivity.create` performed by the route handler after `runImport` returns, at the handler layer or an equivalent reproducing its context? (3/4)

Q32. Are the concurrency and throw-path tests deterministic — interleaving via awaited or controlled promises, with no `sleep`, timers, or wall-clock waits? (3/4)

Q33. Do the tests exercise the real `AsyncLocalStorage`-backed context established by `runWithContext` and the real `assertAudited`, with neither the context module nor the guard mocked or stubbed? (3/4)

Q34. Was the full existing test suite run and green after the fix, with any test that previously passed only because of the leak identified and updated deliberately rather than deleted or skipped? (4/4)

## Dropped clusters

- D1: Restoration must be to the exact prior shape including absence, so `delete` vs `= false` is indistinguishable to consumers (A, B) — 2/4
- D2: The clearing must survive an early `return` from inside the region, not only fallthrough (B, D) — 2/4
- D3: Writes forked inside the region but not awaited within it are impossible by construction or explicitly handled (B, D) — 2/4
- D4: `assertAudited` must read the exemption from the currently active context at call time, not a captured or cached value (C, D) — 2/4
- D5: A model/action allowlist inside `assertAudited` (e.g. exempting `importStaging` by name) must not be the sole mechanism (A, C) — 2/4
- D6: The scope must wrap `stageRows`' whole body so writes added there in future are covered, rather than each `createMany` individually (A, C) — 2/4
- D7: The red-proof oracle must not coincide with a default or sentinel — a "does not throw" assertion is green before and after (B, C) — 2/4
- D8: A cross-request isolation test with two contexts in flight simultaneously, asserting one request's exemption never exempts the other's write (A, C) — 2/4
- D9: A negative-control test — a no-actor mutating write still throws `UnauditedWriteError`, and a non-mutating `findMany` still passes (B, C) — 2/4
- D10: Each new test is named for the single behaviour it pins, starts from fresh state, and shares no mutable module state (A, C) — 2/4
- D11: The exemption check must short-circuit before the `actorId` check in `assertAudited` (B) — 1/4
- D12: The failure direction of the new path is fail-closed — a bypassed or throwing scope yields "audited", never "skipped" (D) — 1/4
- D13: `currentContext()` still throws `"no request context"` when the scoping helper runs outside any context (A) — 1/4
- D14: Stale `ctx` locals captured by `applyBatch`/`runImport` must not observe or retain the exempt variant (B) — 1/4
- D15: The skip log must identify which scope authorized the skip (a reason/label), beyond model/action/requestId (D) — 1/4
- D16: The exemption must not be activatable from untrusted request input (header, body, query) (B) — 1/4
- D17: The Prisma middleware must be unchanged, or its change shown to still call `assertAudited` for every mutating model/action (B) — 1/4
- D18: The `rejected` counting path in `applyBatch` (the `continue` on a malformed email) must be unaffected (B) — 1/4
- D19: Exactly one place decides a write is exempt — no context flag plus guard-side special case that can disagree (C) — 1/4
- D20: If the skip is removed for staging instead, staging writes must produce real audit records with a real `actorId` (D) — 1/4
- D21: A test covering whichever behaviour was chosen for the post-import `deleteMany` (D) — 1/4
- D22: A sequential-request test: a write in a second `runWithContext` is not skipped because of the first (D) — 1/4
- D23: No test-only escape hatch — the guard is not disabled and no `skipAudit` is set in test setup (A) — 1/4
- D24: The correctness argument must not rely on the route handler, middleware, or a wrapper resetting `skipAudit` between requests (A) — 1/4
- D25: A reviewer must be able to name the exact set of exempted statements from the fix alone, without tracing across function boundaries (B) — 1/4

## What the panel demanded and R54 carries

34 majority properties against a rule whose row plus `rule-details/` page teach
about nineteen of them. That ratio — roughly half — is the best any rule has
posted here; R44/RT8/R56/RT9 carried a quarter to a third (round 6) and the two
one-line rules carried a thirtieth (`docs/archive/audit/2026-08-05-panel-audit-oneliners.md`).
R54 is the rule this eval has extended twice, which is why.
