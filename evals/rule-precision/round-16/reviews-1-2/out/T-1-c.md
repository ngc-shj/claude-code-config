Routing: matched R38 (async state machine / non-terminal state), R3 (incomplete pattern
propagation — flagged-instance enumeration), R51 (decision bound to a name), R5 (read-then-write
across transactions). Extracted those rows plus `rule-details/R3.md` and `rule-details/R38.md`,
the Finding Floor and the Remedy Floor. No full-file fallback was needed.

Findings below exclude everything in the already-reported titles list. Two entries are
corrections to titles that are wrong or incomplete about the code, and are labelled as such.

### Major: the dispatch lock's TTL is shorter than the section it guards, so it stops excluding after the first slow batch
File: `app/webhooks/delivery.py` — `_acquire_lock` / `run_worker`
What is wrong: the lock is expired at 60s (`redis_client.expire(LOCK_KEY, 60)`) but the section it
protects is `asyncio.gather(*[deliver(client, d) for d in batch])`, and a single `deliver` can run
up to `MAX_ATTEMPTS`(5) × `REQUEST_TIMEOUT`(30s) plus 2+4+8+16s of blocking `time.sleep` ≈ 180s —
and because that sleep is synchronous the gather is serialised, so a `BATCH_SIZE`(100) batch holds
the section for hours while its key has been gone since second 60.
What breaks in production: from the first batch containing one slow endpoint onward the lock
excludes nobody — a second worker enters the "single dispatcher" section, and when the first worker
finally reaches its `finally: await redis_client.delete(LOCK_KEY)` it deletes the *second* worker's
key, so the number of concurrent dispatchers grows with the number of processes and no operator
signal reports it.
Correction to the reported titles: "the dispatch lock is non-atomic to acquire, released without
ownership, and can wedge with no TTL" is wrong on its last clause. A TTL *is* set on the normal
path; the crash window between `set` and `expire` is the only no-TTL path. The live defect is the
opposite one — the TTL is present and too short for what it guards.
Fix: replace the get/set/expire triple with one `await redis_client.set(LOCK_KEY, token, nx=True,
ex=LOCK_TTL_SECONDS)` where `token = uuid4().hex` is generated per acquisition and returned to the
caller; release only through a Lua compare-and-delete on that token (never a bare `delete`); and
make the hold time bounded by construction — take the retry wait out of process (on a non-2xx or
transport error, `_finish(..., "pending", attempt, ...)` with `next_attempt_at = now +
backoff_for(attempt)` and return) so one pass over a batch is at most one request per delivery,
then set `LOCK_TTL_SECONDS` above the measured p99 of that pass and renew it from a watchdog task
while the pass runs. Preserve, do not delete, the behaviours that made the defect visible: the lock
must still serialise dispatch (deleting the lock entirely is not the fix) and the retry schedule
must still be 2/4/8/16s, now stored rather than slept. Boundary and tie: `LOCK_TTL_SECONDS` must be
strictly greater than the maximum pass duration; if a renewal and the expiry land in the same
second, the compare-and-delete must treat "key missing or token mismatch" as *lock already lost*,
log a named error and abandon the pass rather than continue holding claimed rows. Pair the deny
side with the allow side: assert that a worker holding a valid token completes a full batch and
that a second worker's `_acquire_lock` returns `False` for the whole of it. Red-prove each clause
separately, by running it: (i) hold the section for `LOCK_TTL_SECONDS + 1` with the watchdog
removed and assert the second worker acquires — reddens the renewal clause; (ii) revert the release
to a bare `delete` and assert the ownership test fails — reddens the CAS clause; (iii) make the
retry path sleep in-process again and assert the measured pass duration exceeds the TTL — reddens
the bounded-hold clause. Fail loudly where the check cannot run: a redis error inside
`_acquire_lock` must raise a named `LockUnavailable` that the worker logs and answers by sleeping,
never by treating an unreachable redis as "lock free".

### Major: `deliver` dereferences `session.get(...)` without a None check — the same unchecked-get pattern already reported at `_finish`, missed at this second site
File: `app/webhooks/delivery.py` — `deliver`, `endpoint = session.get(m.WebhookEndpoint, delivery.endpoint_id)`
What is wrong: the reported finding "`_finish` dereferences a row that may not exist" names one of
the two sites; `deliver` performs the identical lookup-then-dereference (`endpoint.signing_secret`,
`endpoint.url` inside `send_once`) with no existence branch, and the resulting `AttributeError` is
not an `httpx.HTTPError`, so it slips past the only `except` in the retry loop.
What breaks in production: a customer deleting an endpoint while a batch is in flight (the
migration's `ON DELETE CASCADE` removes the delivery rows out from under the already-claimed
in-memory batch) turns the next `deliver` into an escaping `AttributeError` that takes down the
whole gather, leaving every other delivery in the batch stranded in `in_flight`.
Fix: in `deliver`, branch on the lookup — `if endpoint is None: _finish(delivery.id,
"failed_permanent", delivery.attempts, None, "endpoint no longer exists"); return` — and give
`_finish` the matching guard (`if row is None: log.warning("delivery %s vanished before finish",
delivery_id); return`) so the terminal write of a deleted row is a named no-op rather than an
`AttributeError`. Do not implement this by widening the `except httpx.HTTPError` to
`except Exception`: that would also swallow the serialisation and signing defects and is the fix
that deletes what made them visible. Boundary and tie: an endpoint row that exists but has
`active = False` at delivery time is the case sitting exactly on this boundary — `enqueue_for_event`
checks `active` only at enqueue, so state the decision explicitly and implement it in the same
branch (skip and `_finish(..., "failed_permanent", ..., "endpoint deactivated")`), otherwise a
customer's deactivation does not stop deliveries already queued. Pair the deny side with the allow
side: pin that an existing, active endpoint still reaches `send_once` and still transitions to
`delivered`, so a fix that marks everything `failed_permanent` cannot pass. Red-prove each clause
separately, by running it: (i) delete the endpoint row before `deliver` and assert the delivery ends
`failed_permanent` with that detail — remove the None branch and it reddens with `AttributeError`;
(ii) delete the delivery row before `_finish` and assert one WARNING and no exception — remove that
guard and it reddens; (iii) set `active = False` and assert the deactivated outcome — drop the
`active` re-check and it reddens. Fail loudly where the check cannot run: if `session.get` itself
raises (database unavailable), the delivery must stay `in_flight` and the error must be logged with
the delivery id — it must never be spelled the same as "endpoint absent" and marked terminal.

### Major: an escaping exception does not merely abort one batch, it terminates the delivery worker for good
File: `app/webhooks/delivery.py` — `run_worker`, the `while True` body
What is wrong: the reported title "one failing delivery aborts the batch and can leave `batch`
unbound" stops one level too low — there is no `try` around the loop body, so an exception from
`_claim_batch`, from the `gather`, or the `NameError` on `if not batch` propagates out of
`while True` and out of `run_worker` itself.
What breaks in production: one transient database blip or one deleted endpoint ends webhook
delivery entirely until someone restarts the process, and because the `finally` releases the lock
on the way out, a monitor watching the lock key sees a healthy idle system rather than a dead one.
Fix: wrap the loop body in `try/except Exception as exc: log.exception("dispatch pass failed"); await
asyncio.sleep(poll_interval); continue`, initialise `batch: list[m.WebhookDelivery] = []` before the
`try` so the post-`finally` test can never raise `NameError`, and on the way out of a failed pass
return the rows this pass claimed to `pending` (`UPDATE webhook_deliveries SET status='pending'
WHERE id IN (claimed_ids) AND status='in_flight'`) so an aborted pass does not manufacture the
`in_flight` wedge. Preserve what made the failure visible: the exception must still be logged at
`exception` level with its traceback — swallowing it into a `warning` re-creates the reported
enqueue-swallow defect one layer down. Boundary and tie: `asyncio.CancelledError` sits on the
boundary of "exception" and must be re-raised, not caught, or the worker becomes unstoppable at
shutdown; a pass that fails *after* some deliveries already reached a terminal status must requeue
only rows still `in_flight`, which the `AND status='in_flight'` predicate is what pins. Pair the
deny side with the allow side: assert that a pass raising an error is followed by a *further*
successful pass that delivers a pending row — a fix that merely logs and exits would otherwise
satisfy the error-handling assertion. Red-prove each clause separately, by running it: (i) make
`_claim_batch` raise and assert the worker performs a subsequent pass — remove the `except` and it
reddens; (ii) return an empty batch with the initialiser deleted and assert `NameError` — reddens
the initialiser clause; (iii) raise from `gather` mid-batch and assert the claimed rows are back to
`pending` — remove the requeue and they stay `in_flight`. Fail loudly where the check cannot run: if
the requeue itself fails, log the claimed ids explicitly so the stranded rows are recoverable by
hand.

### Major: the migration indexes the deliveries table twice and leaves the endpoint lookup that runs on every event unindexed
File: `migrations/0042_webhook_delivery.sql` — `CREATE TABLE webhook_endpoints` (no index on `org_id`)
What is wrong: `enqueue_for_event` filters `WHERE org_id = ? AND active IS TRUE` on
`webhook_endpoints` for every `invoice.paid` / `invoice.payment_failed` / `subscription.updated`
event, and Postgres does not create an index for the referencing side of a foreign key, so the
migration ships two indexes for `webhook_deliveries` and none for the table on the hot path.
What breaks in production: every paid invoice sequentially scans `webhook_endpoints`, inline in the
request that called `dispatch` (the enqueue is awaited before `dispatch` returns), and the same
missing index makes each `DELETE FROM organizations` cascade scan the table as well.
Fix: add `CREATE INDEX idx_webhook_endpoints_org_active ON webhook_endpoints (org_id) WHERE active;`
to migration 0042, and keep `enqueue_for_event`'s predicate literally `active.is_(True)` so the
partial index matches. It must NOT be `CREATE UNIQUE INDEX` — a uniqueness constraint on `org_id`
here would reproduce, on the endpoints table, exactly the reported defect of
`idx_webhook_deliveries_event` (one endpoint per org, silently). Preserve the listing route's
behaviour: `list_webhook_endpoints` does not filter on `active` and must keep returning inactive
endpoints, so this partial index is deliberately not the index that serves it. Boundary and tie: an
org with zero endpoints must still complete `enqueue_for_event` and commit the event (the `for`
comprehension yields `[]`, `add_all([])` is a no-op, `dispatch` returns the event id); rows with
`active = false` are outside the index by construction — say so, since a later query that drops the
`active` predicate silently loses the index. Pair the deny side with the allow side: assert both
that the enqueue query's plan is an Index Scan under a seeded table and that an org with a
deactivated endpoint still gets zero deliveries rather than an error. Red-prove each clause
separately, by running it: (i) seed enough rows for the planner to choose, `EXPLAIN` the enqueue
query and assert `Index Scan` — drop the index and it reddens to `Seq Scan`; (ii) rewrite the
predicate to `active == True` without the partial-index-matching form and assert the plan reddens;
(iii) insert two endpoints for one org and assert both receive a delivery — make the index UNIQUE
and the insert reddens. Fail loudly where the check cannot run: do not write `CREATE INDEX IF NOT
EXISTS` — a name collision must abort the migration rather than leave the schema silently
un-indexed.

### Minor: `updated_at` never advances on the `pending → in_flight` transition, so the only column a stuck-delivery sweeper could use dates the wrong event
File: `app/webhooks/models.py` — `WebhookDelivery.updated_at`; `app/webhooks/delivery.py` — `_claim_batch`
What is wrong: the column has `default=_now` but no `onupdate`, the migration adds no trigger, and
`_claim_batch` writes `row.status = "in_flight"` without touching `updated_at`, so a claimed row's
`updated_at` still records its creation.
What breaks in production: the reaper that the reported `in_flight`-wedge finding calls for has no
correct age to threshold on — a row claimed a minute ago and a row created hours ago are
indistinguishable, so the sweeper either reclaims live deliveries or never reclaims wedged ones.
Fix: declare `updated_at = Column(DateTime(timezone=True), default=_now, onupdate=_now)` and set
`row.updated_at = datetime.now(timezone.utc)` explicitly in `_claim_batch`, or add a
`BEFORE UPDATE` trigger in the migration so writes that bypass the ORM are covered too.

### Minor: `event_id` is the customer-facing dedup key but is an unconstrained integer, while its sibling column in the same table carries a foreign key
File: `migrations/0042_webhook_delivery.sql` — `event_id BIGINT NOT NULL`
What is wrong: `endpoint_id` is declared `REFERENCES webhook_endpoints (id) ON DELETE CASCADE` and
`event_id` — the value `docs/webhooks.md` tells customers to deduplicate on — has no referential
constraint of any kind, in the same `CREATE TABLE`.
What breaks in production: a delivery can carry an `event_id` that matches no event row, and
nothing can join deliveries back to the events table for reconciliation after an incident.
This one rests on a table the change does not show, so it ranks as a question rather than an
assertion: is the events table in the same database and non-partitioned? If it is, the missing
`REFERENCES` is an inconsistency inside one statement and should be added; if it is partitioned or
lives elsewhere, the constraint is unavailable and the answer closes this.

### Minor: `webhook_deliveries` accumulates a full copy of every event payload forever, with no pruning path and no index that could support one
File: `migrations/0042_webhook_delivery.sql` — `CREATE TABLE webhook_deliveries`
What is wrong: every delivery row stores the whole event `payload` as JSONB plus `response_body`,
one row per event per endpoint, and neither the migration nor `app/webhooks/delivery.py` contains
any delete, partition or expiry path.
What breaks in production: the table grows as events × endpoints without bound, and the eventual
cleanup has only `idx_webhook_deliveries_status` to work with — no index on `created_at` — so the
first purge is a full-table scan on the largest table in the schema.
