# Merged panel rubric — R1

Four panellists, shown only `sketches/R1-reimplemented-helper.ts` and a neutral
statement of the defect. None saw the rule set. Clusters kept at >=3/4 support;
the merge was performed by an agent shown only the four panel outputs.

R1's entire text: *"`grep -r` for existing helpers (rate limiters, validators,
encoders, formatters) before accepting new implementations."*

# Merged rubric — R1 (reimplemented retry helper)

## Mechanism

**Q1.** `callWithRetries` is deleted outright — not renamed, not left in the file unused or exported, not kept as a private alias that still contains a loop; the identifier returns zero hits in the tree after the change. (4/4)

**Q2.** `chargeInvoice`'s retry behaviour originates from the single exported `withRetry` in `src/lib/http/retry.ts`, and no second retry implementation exists — no billing-local wrapper containing a loop/`catch`/timer, no copied backoff expression, no second shared helper coexisting with `withRetry`. (4/4)

**Q3.** `withRetry`'s existing defaults (`attempts: 3`, `baseMs: 200`, jitter-on) are unchanged in value and in the condition selecting them; any modification is additive, with the absent-argument branch reproducing the pre-change code path — checkable by reading the diff, not by trusting the PR description. (4/4)

**Q4.** The six pre-existing call sites have executable evidence of no regression: their tests run unchanged and pass, and at least one asserts call count and delay schedule so that altering the defaults would break it — "I did not change the defaults" is not evidence. (3/4)

## Accounting for the divergence

**Q5.** The change text (PR body or code comment) enumerates every behavioural difference between the deleted loop and `withRetry` and states the chosen resolution for each; no difference is left unclassified. (4/4)

**Q6.** The jitter delta is decided explicitly rather than inherited — `withRetry` randomises delays over [0.5×, 1.5×), the billing loop was deterministic — with the winning side and its reason recorded for a payment endpoint. (4/4)

**Q7.** The backoff-shape divergence is named — helper exponential `baseMs * 2**i`, billing linear `200 * attempt` — including the fact that the two schedules coincide only at exactly 3 attempts (200/400) and diverge from the 4th on (800 vs 600), so "behaviour preserved" is scoped to `attempts === 3`. (3/4)

**Q8.** The rise in worst-case inter-attempt wall time from a fixed 600 ms to ~900 ms is stated and checked against the deadline of whatever calls `chargeInvoice`; that timeout is named with its specific value, or its absence is recorded. (4/4)

**Q9.** The `throw new Error("unreachable")` sentinel is gone from all surviving code, and the value propagated after exhaustion is the last attempt's original error with its identity, type, and stack intact (non-`Error` throwables included); any wrapper is a named `Error` subclass setting `cause`. (4/4)

**Q10.** `attempts` reaching `withRetry` is guaranteed `>= 1` so the `throw lastErr` path cannot throw `undefined` — validated at the boundary if the value can come from config or environment, otherwise a literal `>= 1`. (4/4)

## Idempotency and retry safety

**Q11.** The non-idempotent `POST /invoices/:id/charge` carries an idempotency key (or a cited server-side dedupe guarantee), so a retry cannot double-charge. (4/4)

**Q12.** The key is computed once, outside the retried closure, is byte-identical across all attempts of one logical charge, and is distinct across separate logical charges — not regenerated per attempt from `Date.now()`, a counter, a UUID call inside `fn`, or a random value. (4/4)

**Q13.** Retries are restricted to failure classes safe to repeat (transport failures, timeouts, 5xx, 429); a non-retryable 4xx (declined card, validation, auth) consumes exactly one request and no delay. (4/4)

**Q14.** The "server committed the charge, response lost in transit" case is addressed explicitly — a timed-out or connection-reset attempt is classified as unknown-outcome rather than failed — via a cited provider guarantee, a retry predicate limited to provably pre-send failures, or retry removed from this path. (4/4)

**Q15.** Total time inside `chargeInvoice` is bounded by an enforced deadline, and each individual attempt carries its own timeout/abort so a hung socket cannot stall the loop past that bound. (3/4)

**Q16.** Caller cancellation propagates: once the caller aborts, no further attempt is issued and no sleep continues; if no cancellation token exists on this path, that absence is stated. (4/4)

**Q17.** No timer is left pending after the final attempt, a thrown error, or an abort — the sleep resolves or is cleared, and the event loop is not held open by a retry that already returned. (3/4)

## Observability

**Q18.** Each retry attempt emits a structured log line or metric carrying at least the attempt index, the outcome (error class or HTTP status), and the operation identity, so a retry storm on a money-moving call is diagnosable from telemetry. (4/4)

**Q19.** Those logs and metrics contain no full request or response bodies, no card or payment-instrument data, no authorization headers, and no customer PII. (3/4)

## Evidence

**Q20.** Every new test is red-proved by executing the mutation it claims to catch — the specific mutation and the observed failure are recorded; reasoning about what the test would do is not accepted, and the oracle used is not one that merely hits a default/floor value the pre-fix loop also satisfies. (4/4)

**Q21.** Delay assertions run on fake/injected timers with an injected or seeded random source; no test sleeps in real time and no timing assertion is loose enough to pass under a different schedule. (4/4)

**Q22.** A test asserts the invocation count is exactly 3 on persistent retryable failure and exactly 1 when the first attempt succeeds. (3/4)

**Q23.** A test asserts the delay sequence actually applied to the charge path (values and ordering, or the [0.5×, 1.5×) bounds with random stubbed), so a silent revert to a different backoff shape fails. (4/4)

**Q24.** A test asserts a non-retryable failure (e.g. 402/422) produces exactly one request, zero delay, and propagates unchanged. (4/4)

**Q25.** A test asserts the idempotency key is identical across all requests produced by one `chargeInvoice` call, read from the captured outbound requests. (4/4)

**Q26.** A test asserts the value escaping after exhaustion is the original error by identity/type, and that no error whose message is `"unreachable"` can escape. (3/4)

**Q27.** Typecheck and lint pass with no new warnings, no `any`, no non-null assertion, and the `catch` binding typed `unknown` and narrowed by an explicit predicate before any property is read. (3/4)

## Scope and recurrence

**Q28.** A repository-wide search for the same shape (timer or sleep inside a `catch`, attempt counter) is run with its command and full output recorded; any other ad-hoc retry loop found is fixed in this change or logged with file and line as an explicit follow-up. (3/4)

**Q29.** The cause — the author did not find `withRetry` — is addressed by a concrete mechanism: export from the module index or conventional import path, naming it the sole retry primitive at its export site, or a lint/hook/CI guard rejecting new hand-rolled retry loops. A comment in `retry.ts` alone does not satisfy this. (4/4)

## Consensus diagnosis

All four panellists agree the visible defect — a duplicated retry loop whose divergences (jitter, backoff shape, the `"unreachable"` sentinel) were never stated — is not the dangerous one: both the local loop and `withRetry` retry a non-idempotent `POST /invoices/:id/charge` on every error class, so collapsing them into one helper produces a single copy of an unchanged double-charge exposure. As R1_c.txt puts it: "It does **not** fix the actual hazard. Both the old and new code retry a non-idempotent charge on every error class. Deduplicating them yields one copy of the same double-charge exposure — a tidier diff and an unchanged risk. A fix that stops at deduplication has resolved the stated problem and left the dangerous one in place." — echoed by R1_d.txt's section heading "IDEMPOTENCY — the failure mode that makes this a billing bug rather than a duplication bug" and R1_b.txt item 15, "the fix is not correct if it only deduplicates."

## Dropped

- `chargeInvoice`'s exported name, signature, generic return type unchanged; no `any`/cast/non-null assertion introduced to typecheck — a, c (2/4).
- Import direction `integrations/billing → lib/http` only, verified not to create a cycle; `lib/http` gains no import from `integrations/` — a, c (2/4).
- Six call sites enumerated by an actual recorded repository search rather than trusting the "six" in the description — a, c (2/4).
- `429`/`Retry-After` is honoured or the decision to override it is stated — b, c (2/4).
- Retry exhaustion distinguishable in logs/metrics from a first-attempt failure; surfaced error carries attempt count and elapsed time — a, d (2/4).
- Tests assert observable behaviour only, with no spy/module mock asserting `withRetry` was called — a, d (2/4); contradicted by c32, which proposes the helper being observed as invoked as the distinguishing oracle.
- Jitter must be retained in production; `{ jitter: false }` to stabilize a test is rejected as reinstating the synchronized-retry storm — b, d (2/4); contradicted by c6 and a35, which permit `jitter: false`.
- A test reproducing the double-charge directly (server accepts, first attempt times out, retry fires, exactly one charge exists) — c, d (2/4).
- Unbounded backoff cap (`maxDelayMs`) / retry amplification bounded by a shared budget or circuit breaker — b, d (2/4).
- Loss of configurability named (`callWithRetries` hardcodes 3 and 200 ms with no override) — b, c (2/4).
- Change description records the user-visible behaviour shift for latency attribution; post-deploy verification window and rollback trigger stated before merge — a, d (2/4).
- `attempts` and `baseMs` pinned explicitly at the billing call site, and the coupling to a shared default another team can retune is named — c (1/4).
- `attempts: 3` semantics pinned as 3 total invocations, not silently 4 — b (1/4).
- Verified that `billingApi.post` does not itself retry internally (stacked layers = 9 requests) — b (1/4).
- Request body/headers not consumed or mutated by the first attempt (single-use body/stream semantics) — c (1/4).
- The `sleep` dependency `withRetry` uses is importable from the billing module's build target — c (1/4).
- Intermediate non-final errors not silently discarded where billing alerting depends on them — c (1/4).
- Retry does not silently disappear from the charge path as an unremarked side effect of deleting `callWithRetries` — a (1/4).
- A test proving concurrent failing calls do not align their retry instants — b (1/4).
- The idempotency question is asked of the other six `withRetry` call sites and recorded as a separate finding — b (1/4).
- `withRetry`'s exported surface is not widened beyond what the new site needs — b (1/4).
- Full test suite run, not only the new tests, and green — a (1/4).
- Removal leaves no orphaned imports, no unused `sleep` import in billing, no dead exports — d (1/4).