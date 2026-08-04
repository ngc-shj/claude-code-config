# Merged panel rubric — RT8 fixture (F3)

Majority rubric merged from the four round-6 panellists (kept: ≥3/4 support;
merge performed by an agent shown only the four panel outputs, never the rule
set). Used as the blind-scoring rubric for round 7. Floor-mapped subset,
pre-registered before any round-7 output was read: Q5 Q6 Q8 Q9 Q11.

Q1. Does every denial-path (403) test assert that the destructive repository call did not execute — e.g. `expect(deleteDoc).not.toHaveBeenCalled()` — in addition to asserting the response status? (4/4)

Q2. Is the negative side-effect assertion applied to every denial path the handler has (401 unauthenticated, 404 not-found, 403 non-owner / all denial branches), not only the 403 path? (4/4)

Q3. Does the negative assertion cover every mutating collaborator reachable on the route (cascade deletes, audit writes, cache invalidation), not only `deleteDoc`? (3/4)

Q4. Is mock/spy call state reset between tests (`clearMocks` / `mockClear` in `beforeEach`), so a zero-call assertion reflects only the test under inspection rather than inherited state? (4/4)

Q5. Does at least one authorized-path test assert the delete spy WAS called with the expected id/arguments, as a positive control? (4/4)

Q6. Does the fix guarantee that broken mock wiring (wrong module path, renamed export, spy never wired) cannot leave the suite green — via the positive control and/or an executed wiring-break mutation that makes the suite fail? (4/4)

Q7. Is the handler's returned promise awaited (with any fire-and-forget/unawaited delete flushed) before the side-effect assertion runs, without `sleep`/timer padding? (3/4)

Q8. Is a red-proof mutation actually executed — not reasoned about — for each denial path, in which the handler performs the delete yet still returns the denial status (the exact defect being closed), and does the corresponding test go red? (4/4)

Q9. Under that mutation, is the observed failure on the side-effect (call-count/spy) assertion rather than the status assertion — i.e. the pre-existing status-only assertion is shown insufficient? (4/4)

Q10. Do the tests pass in any execution order and when run singly in isolation, with no dependence on another test's state? (3/4)

Q11. Is the full suite green after the change, with all mutations reverted and no `.only`/`.skip` left on the touched tests? (4/4)

Dropped clusters:
- D1: fix is test-only, handler source unchanged (A14, B8) — 2/4
- D2: negative assertion must be call-count form, not `not.toHaveBeenCalledWith(arg)` which passes on a different id (B3, C1) — 2/4
- D3: denial fixture provably reaches the guard (record exists, `findById` called exactly once, pre-guard validation passes) (B5, C6) — 2/4
- D4: guard ordering pinned (401 asserts `findById` not called; combined-condition requests assert one deterministic status, no existence leak) (B4, D10) — 2/4
- D5: assert only at the repository boundary — guard not mocked, no private handler internals or call-ordering assertions (A3, C9/C14) — 2/4
- D6: test names state the side-effect invariant, not just the status code (C10, D12) — 2/4
- D7: suite green on the unmodified handler before the change — no false red (A13, B13) — 2/4
- D8: denial tests assert response body/error code, not just status (C5) — 1/4
- D9: assertion-deletion mutation shows each new negative assertion is load-bearing (B16) — 1/4
- D10: delete-call-removed mutation turns the authorized-path test red (A9) — 1/4
- D11: broken-fixture mutation fails loudly rather than passing via coincidental zero count (C13) — 1/4
- D12: positive path asserts `toHaveBeenCalledTimes(1)` so a double-delete is visible (D5) — 1/4
- D13: adequacy argued from the mutation matrix, not coverage numbers (A15) — 1/4
- D14: `check-vacuous-denial.sh` reports no findings on the changed test file (B18) — 1/4