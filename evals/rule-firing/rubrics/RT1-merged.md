# Merged panel rubric — RT1

Four panellists, shown only `sketches/RT1-mock-shape.ts` and a neutral statement
of the defect. None saw the rule set. Clusters kept at >=3/4 support; the merge
was performed by an agent shown only the four panel outputs.

RT1's entire text: *"Mock return values must match actual API response shapes."*

# Merged rubric — RT1 (mock shape / idempotency oracle)

**Q1.** The value the database double resolves to carries all nine `TeamPolicy` fields (`teamId`, `requireMfa`, `sessionIdleTimeoutMinutes`, `sessionAbsoluteTimeoutMinutes`, `passwordHistoryCount`, `inheritTenantCidrs`, `teamAllowedCidrs`, `updatedAt`, `updatedBy`) — none omitted, none extra. (4/4)

**Q2.** Completeness is enforced by the compiler, not by a reader counting fields: the fixture/factory is bound to `TeamPolicy` by an explicit annotation, `satisfies TeamPolicy`, or an annotated factory return type, so omitting a field is a `tsc` error. (4/4)

**Q3.** No escape hatch defeats Q2 at the fixture or mock site: no `as TeamPolicy`, `as unknown as`, `as any`, bare `any`, `Partial<>`/`Pick<>`/`Omit<>`, non-null assertion, `@ts-ignore`/`@ts-expect-error`, or eslint-disable. (4/4)

**Q4.** The double is behavioral, not constant: its return value is computed from the arguments it receives (`where`/`create`/`update`), and no argument-independent `mockResolvedValue` (or equivalent) stands in for this call anywhere in the fixed test. (4/4)

**Q5.** The double holds state across calls within a single test — it applies the write and returns what was stored — so the second `PUT`'s response is a function of the first `PUT`'s effect rather than of the fixture literal. (4/4)

**Q6.** The double distinguishes the create path from the update path on the same key: absent key creates and fills unmentioned fields with schema defaults; present key merges the `update` payload over the stored row without re-applying defaults or resetting omitted fields. (4/4)

**Q7.** At least one assertion compares a response against an independently written expected value (literal, or factory plus the explicit overrides under test) — not only first-vs-second, and not the same expression that was fed to the double. A first-vs-second comparison may remain only in addition. (4/4)

**Q8.** The comparison is whole-object and exact on the key set — `toStrictEqual` (or equivalent) against the complete nine-key expected object, not `toEqual` and not a per-field subset, because `toEqual` treats a present-but-`undefined` key as absent. (4/4)

**Q9.** No loose matcher or snapshot stands in for the shape: no `toMatchObject`, `expect.objectContaining`, `expect.any(...)` for a predictable field, `toMatchSnapshot`, or `toMatchInlineSnapshot`. (4/4)

**Q10.** The expected value is in post-`Response.json` wire shape: `updatedAt` is compared as the ISO string `JSON.stringify` produces, not as a `Date`. (4/4)

**Q11.** Fixture values are chosen against the schema defaults and against each type's zero value (not `30`/`480`/`5`/`true`/`[]`, no `0`/`false`/`""`/empty array), so "route substituted a default" and "field dropped" are distinguishable from "route returned the persisted value". (4/4)

**Q12.** Exactly one definition of the complete row exists — a shared factory taking per-test overrides over a complete base; the nine fields are not re-listed or copy-pasted across call sites. (4/4)

**Q13.** The fix is a class fix, not an instance fix: the suite/repository is searched for other partial-shape fixtures of `TeamPolicy` (or any model stubbed the same way), all are repaired or deleted, and the search performed is part of the evidence rather than an assumption. (4/4)

**Q14.** Schema drift is caught mechanically: adding a tenth NOT NULL column to `TeamPolicy` breaks the build at the factory rather than silently yielding a stale nine-of-ten stub. (4/4)

**Q15.** The typecheck command actually runs over the test files (in the verification run / CI) — a `satisfies` clause in a repo whose CI runs only the test runner is documentation, not a gate. (4/4)

**Q16.** Executed mutation: the route returns a projection of `saved` dropping any one of the nine fields → the test fails. (4/4)

**Q17.** Executed mutation: the route ignores the request body on update (`update: {}`) → the test fails. This is the mutation the original test cannot detect. (4/4)

**Q18.** Executed mutation: the write is made non-idempotent (second identical `PUT` yields a different stored row/response) → the idempotency assertion fails. (4/4)

**Q19.** No decorative assertion: removing any single assertion the fix adds leaves at least one of the mutations undetected. (4/4)

**Q20.** Every mutation is actually executed and its verbatim failure output recorded; no "this test red-proves X" claim is written from reading the code, and mutations are reverted with the suite re-run green. (4/4)

**Q21.** Any time value the double writes comes from a frozen or injected clock — no wall-clock `new Date()`/`Date.now()` at call time, no `sleep`, no tolerance window. (3/4)

**Q22.** The double's store and call history are reset in `beforeEach` (or constructed per test), so test order cannot change the outcome — required precisely because Q5 makes it stateful. (3/4)

**Q23.** Handling of the write-stamp fields is explicit: the test states and asserts which fields must be identical across the two `PUT`s and which may change, and equality is never obtained by silently deleting, omitting, `pick`/`omit`-ing, or destructuring away a field. (3/4)

**Q24.** The completeness claim and the idempotency claim are separate `it` blocks, and each name states the semantics actually asserted (including "same state modulo `updatedAt`" if that is what is pinned). (3/4)

**Q25.** The suite contains a differential case in which a second `PUT` carries a *different* body and is asserted to produce a *different* response, so overwrite semantics are exercised and the equality assertion is shown capable of being false. (3/4)

**Q26.** The idempotency test is not deleted, `skip`ped, `todo`ed, or renamed into a weaker claim, and no pre-existing assertion is loosened to accommodate the new fixture. (3/4)

**Q27.** Each mutation's red originates in the intended assertion — not in a compile error, a crash during double setup, request construction, JSON parse, an unhandled rejection, or a hang. (3/4)

**Q28.** The full suite is run and observed green both before (baseline) and after the change, with the commands and results shown. (3/4)

**Q29.** The double rejects what the real engine would reject — an unknown key in `create`/`update`, or a value whose type contradicts `TeamPolicy`; it is not made permissive. (3/4)

**Q30.** The route's unvalidated `update: body` / `create: { teamId, ...body }` pass-through of caller-supplied `teamId`/`updatedBy`/`updatedAt` is not absorbed into the expected value: either the route validates and a test pins that, or the finding is reported explicitly. (3/4)

## Consensus diagnosis

The panellists agreed the named shape defect (four of nine columns) is stacked on a second, more serious one: the assertion has no oracle, because a constant `mockResolvedValue` plus an echoing `PUT` makes the two compared responses equal by construction, so padding the fixture to nine fields fixes nothing. In `RT1_c.txt`: "`mockUpsert.mockResolvedValue(policyData)` returns one frozen constant regardless of arguments, and `PUT` is a pure echo of that constant. The assertion is therefore `f(c) === f(c)` for fixed `c` — an identity, true under every possible implementation of the route. Completing the fixture to nine fields converts a tautology over 4 fields into a tautology over 9. The assertion never had contact with idempotency: idempotency is a property of repeated writes against *state*, and there is no state in this test."

## Dropped

- Subject under test is not doubled — `PUT` imported and invoked unmodified with a real `Request` whose body the production `req.json()` parses (a, b).
- `mockUpsert` is asserted on directly: called twice, `where.teamId === params.teamId`, body as the `update` payload (b, d) — contested by c25/d24, which prefer outcome over call-spying.
- Production types and the Prisma schema are unchanged; no field made optional or nullable to let a short fixture compile (a, d).
- The fake's semantics are pinned against a real ORM/database (integration test or recorded decision to narrow the claim instead) (a, c) — contradicted by d39's hermetic-only requirement.
- The mock is typed from Prisma's own method type (`jest.MockedFunction<typeof prisma.teamPolicy.upsert>` / `mockDeep`) so the resolved value is checked against the real return type (c, d).
- Each `Response` body is consumed exactly once (a, d).
- Behavior-preserving refactors (rename, key reorder, `upsert` → `findUnique` + write) leave the test green; no over-specification of the call shape (c, d).
- Executed mutation: the route ignores `params.teamId` (hardcodes a key or takes `body.teamId`) → fails (a, b).
- The failure message names the missing field/column, so the next engineer cannot "fix" it by loosening the assertion (a, c).
- Executed mutation: the route returns the request body instead of the persisted row (c).
- Executed mutation: the response swaps two same-typed fields (`sessionIdleTimeoutMinutes` ↔ `sessionAbsoluteTimeoutMinutes`) (d).
- Executed mutation: the route re-applies create defaults on the update path (d).
- Gap proof: the *original* test is shown green under a route mutated to drop `passwordHistoryCount` (c).
- A runtime guard asserts the fixture's key set equals the schema's, sourced from Prisma DMMF / a Zod schema / a reflected generated type — never a second hand-maintained list (c).
- The three fail-open modes of the typecheck guard (optional/nullable new column, widened alias, stale generated types / `skipLibCheck`) are each stated and closed (c).
- Adding a column and adding it to the shared factory is one enforced step, recorded where the next schema change will be read (c).
- The fake returns a fresh object per call so a route mutating `saved` cannot alias both responses into agreement (d).
- Deliberate simplifications of the double carry a comment saying so (a).
- `first.status` and `second.status` are asserted to be 200, so a JSON error body cannot satisfy the equality (a).
- The test stays hermetic and bounded: no network, no real database, no timers left running (d).
- Fields absent from the request body are asserted to retain their persisted value rather than reverting to the schema default (a).
- Simply appending five fields to the existing `policyData` constant while leaving the first-vs-second assertion is explicitly not a fix (b).