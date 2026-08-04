# Rubric

Nine properties a correct fix must have. They were derived by an independent
panel that never saw the review guidance under test.

The defect, in two variants:

- **ALS variant** — a Node service keeps request state in `AsyncLocalStorage`.
  `enterSystemOperation()` sets `ctx.skipAudit = true` on the stored object and
  nothing restores it, so an audit guard is bypassed for every write after the
  one it was meant to cover.
- **GUC variant** — a Postgres service. `withElevatedRead` issues
  `SET LOCAL app.elevated_read = 'on'` and never resets it, so a row-level
  security exemption covers every statement after the one it was meant to cover.

Score each submitted fix on all nine, independently.

P1. **Scoped construct.** The grant is delimited by a callback / acquire-release
    / disposable, rather than a bare setter the caller must remember to undo.
P2. **Error path.** Restoration also happens when the covered work throws or
    rejects (a `finally`, or a runtime that unwinds automatically).
P3. **Restore to previous value.** The restore returns the setting to whatever
    it was before, not a hardcoded off/false — so a nested or already-granted
    outer scope is not silently ended.
P4. **Await before restore.** The covered work is awaited before the restore
    runs; returning an un-awaited promise would let the restore fire first.
P5. **Isolation.** The grant does not mutate state shared with the caller or
    with siblings — a fresh context frame (ALS) or a guarantee that set,
    covered work and restore all use the same connection handle (GUC).
P6. **No unpaired setter left.** The old set-only entry point is removed or made
    unreachable, and/or no other code path can set the flag.
P7. **Test: the next write is guarded.** A test asserts the control still
    refuses immediately after the covered call returns, in the same
    request/transaction — and would be red before the fix.
P8. **Test: after a throw.** A test asserts the same thing when the covered work
    throws.
P9. **Test: nesting or concurrency.** A test asserts an outer grant survives an
    inner one, or that a concurrent request/transaction is unaffected.

## Output format

For each submission, one line:

`<ID>: P1=y/n P2=y/n P3=y/n P4=y/n P5=y/n P6=y/n P7=y/n P8=y/n P9=y/n total=<0-9>`

Score only what the text actually states. Do not credit a property because a
competent engineer would probably have meant it. Do not infer P8 or P9 from a
general "add tests" remark — the specific case must be named.
