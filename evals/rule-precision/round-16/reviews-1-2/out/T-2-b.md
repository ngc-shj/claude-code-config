# Review — F10-webhooks.diff (second pass: what the prior reviewers missed)

Routing: digest read whole-file (ended at `## END-OF-DIGEST`); rows extracted for
R1/R2/R6/R41/R47/R49/RT1/RT5/RT6/RT7 plus `rule-details/RT1.md` and
`rule-details/R47.md`; Finding Floor and Remedy Floor extracted once. No fallback to
the full rules file was needed.

Findings already in `titles-2.md` are not repeated. Where a finding below shares a
remedy with one already reported, that is stated so the two are not fixed twice.

---

### Major: an endpoint can never be disabled, deleted, or have its secret rotated — `active` is a filter with no writer (R41)
File: `app/api/routes/settings.py` — `create_webhook_endpoint`, `list_webhook_endpoints`, `list_deliveries`; `app/webhooks/delivery.py` — `enqueue_for_event` (`m.WebhookEndpoint.active.is_(True)`)
What is wrong: `active` is declared in the model, defaulted `TRUE` in the DDL, hardcoded `True` at the one creation site and read by `enqueue_for_event`, but the diff adds no route that ever writes it and no `DELETE` route — and since `webhook_endpoints` is created by this same migration, no pre-existing code can write it either, so the declared kill switch has never had a false value to filter.
What breaks in production: a customer who loses control of their endpoint host, or who loses the signing secret the docs say "cannot be read back afterwards", has no way to stop us POSTing their event payloads or to re-establish verification — the only remediation is a DBA `UPDATE`, and the org-level `webhooks_enabled` column is no fallback because nothing reads it either (already reported).
Fix: add three org-scoped routes in `settings.py`, each loading the row with `.filter(WebhookEndpoint.id == endpoint_id, WebhookEndpoint.org_id == user.org_id).with_for_update().one_or_none()` and returning **404** (never 403) when no row matches, so cross-tenant probing cannot confirm existence:
`PATCH /webhook-endpoints/{id}` taking `{"active": bool}`; `DELETE /webhook-endpoints/{id}`; `POST /webhook-endpoints/{id}/rotate-secret`, which writes `new_signing_secret()` and returns it in that response only.
*Allow side pinned with the deny side*: a test must assert that after deactivating endpoint A, `enqueue_for_event` writes **zero** rows for A **and still writes one row for the same org's active endpoint B** — a remedy that only stops deliveries is satisfied by breaking the feature.
*Red-prove each clause separately, by execution*: (i) delete the `active.is_(True)` predicate in `enqueue_for_event` → only the deactivate test reds; (ii) delete the `org_id` predicate from the PATCH lookup → only the cross-tenant-deactivate test reds; (iii) make rotate return the pre-rotation secret → only the rotation test reds.
*Fail loudly when the check cannot run*: an unresolvable `endpoint_id` is 404, a body missing `active` is 422, and a rotate whose commit fails must raise — it must never return 200 with the old secret, because the caller would store a secret we did not persist.
*Preserve*: deactivation and deletion must not remove delivery history — `list_deliveries` must still return past attempts for a deactivated endpoint (deleting the rows is how the audit trail disappears), and `new_signing_secret` must keep its `whsec_` prefix contract that the create response and the docs already publish.
*Boundary and tie*: state in the handler that the flip takes effect **at enqueue time**, so deliveries already persisted as `pending` at the instant of deactivation still fire; if that is not wanted, add `WHERE endpoints.active` to the `_claim_batch` join instead and say so — pick one. Two concurrent PATCHes on the same row are serialised by the `FOR UPDATE`, last writer wins.

### Major: a raising in-process subscriber silently cancels the webhook enqueue, because the diff puts the enqueue after the subscriber loop
File: `app/events/dispatcher.py` — `dispatch`, the `+` block after `for subscriber in SUBSCRIBERS.get(...)`
What is wrong: the new `enqueue_for_event` call is placed after the unguarded `await subscriber(envelope)` loop, so any subscriber raising propagates out of `dispatch` *after* the event row has already been committed but *before* any delivery row is written — the diff's own `try/except` around the enqueue cannot help, because the enqueue is never reached.
What breaks in production: one unrelated in-process subscriber bug drops every outbound webhook for that event type with no delivery row, no `failed_permanent`, and nothing in the deliveries listing to show a customer that an event they are documented to receive at-least-once was never even queued.
Fix: move the `enqueue_for_event` call to immediately after `session.flush()` **inside** the existing `with session_scope()` block and have it accept the caller's session rather than opening its own, so the delivery rows and the `Event` row commit or roll back together; the subscriber loop then runs after, and its exceptions can no longer affect delivery. This is the same edit as the already-reported "enqueue is outside the event's transaction" finding — do it **once**, not twice, and note that with it the `except Exception: log.warning(...)` must be removed rather than kept, since a failed enqueue must now roll the event back rather than be swallowed (also already reported).
*Allow side pinned with the deny side*: assert that a dispatch whose subscriber raises leaves **zero** committed `Event` rows and **zero** delivery rows, **and** that a normal dispatch with a working subscriber still commits one event and one delivery per subscribed endpoint — a fix that aborts on any subscriber error would otherwise pass.
*Red-prove each clause separately*: (i) move the enqueue back below the subscriber loop → the raising-subscriber test reds on the missing delivery row; (ii) move the enqueue outside the `session_scope` block → the rollback test reds on an orphan `Event` row; (iii) restore the bare `except Exception` → the "enqueue failure rolls back the event" test reds.
*Fail loudly*: an `enqueue_for_event` that cannot resolve any endpoint for a subscribed org must still return 0 and let `dispatch` commit — but a database error inside it must propagate, not be logged; "wrote nothing because there are no endpoints" and "wrote nothing because the insert failed" must not be spelled the same way.
*Preserve*: subscribers must still run and must still receive the envelope — do not fix ordering by dropping the subscriber loop or by moving it inside the transaction (it awaits arbitrary code and would hold the DB transaction open).
*Boundary and tie*: name what happens for an event type in `WEBHOOK_EVENT_TYPES` with zero matching endpoints — the event commits, no delivery row exists, and that is a success, not a swallowed failure.

### Major: `deliver` dereferences `session.get(...)` without a None check — the same pattern the reviewers flagged only in `_finish`
File: `app/webhooks/delivery.py` — `deliver`, `endpoint = session.get(m.WebhookEndpoint, delivery.endpoint_id)`
What is wrong: the reviewers reported the unchecked `session.get` in `_finish`; the identical unchecked lookup in `deliver` was not reported, and here a `None` produces `AttributeError` inside `send_once` (`endpoint.signing_secret`), which is **not** an `httpx.HTTPError` and so escapes the retry loop's only `except`.
What breaks in production: deleting a webhook endpoint (or any org, via the `ON DELETE CASCADE` on `organizations`) while a claimed delivery is in flight raises out of `asyncio.gather`, kills the worker — already reported as unrecoverable — and leaves that row and every other row in the batch parked in `in_flight` with no reaper.
Fix: guard the lookup at its use site and terminate the delivery rather than the worker:
```python
with session_scope() as session:
    endpoint = session.get(m.WebhookEndpoint, delivery.endpoint_id)
    missing = endpoint is None
if missing:
    _finish(delivery.id, "failed_permanent", delivery.attempts, None, "endpoint deleted")
    return
```
(the `_finish` call is outside the `with` so it does not nest a second session inside the first). Apply the same guard to `_finish`'s own `session.get` — that one is already reported, but the two must land together or the crash simply moves one frame.
*Allow side pinned with the deny side*: assert that a delivery whose endpoint still exists is **still POSTed** (the `MockTransport` handler records exactly one request), and that one whose endpoint row was deleted terminates as `failed_permanent` — a fix that returns early for both makes the feature deliver nothing while every "no crash" assertion stays green.
*Red-prove each clause separately*: (i) remove the `is None` guard → the deleted-endpoint test reds with `AttributeError`; (ii) replace the `_finish(...)` call with a bare `return` → the "row does not stay `in_flight`" assertion reds; (iii) delete the guard in `_finish` instead → only the `_finish` test reds.
*Fail loudly*: the terminal row records a named reason (`"endpoint deleted"`) in `response_body` with `response_status` NULL, so "we never tried" is distinguishable in the deliveries listing from "the customer returned an empty 200".
*Preserve*: the retry loop, the attempt counter, and the existing `httpx.HTTPError` handling for endpoints that do exist must be untouched — do not widen the `except` to bare `Exception` as the fix, which would hide this class of bug rather than handle it.
*Boundary and tie*: the endpoint deleted **between** `_claim_batch` and the POST is the same case, so the check must sit at use time and not at claim time; if two workers hold the same delivery (possible today, since the lock is non-atomic — already reported), `_finish` is last-writer-wins and both write the same terminal status, which is safe.

### Major: the migration indexes the claim query only — neither customer-facing query nor either cascade path has an index
File: `migrations/0042_webhook_delivery.sql` — the two `CREATE INDEX` statements
What is wrong: `webhook_deliveries` gets an index on `status` and a unique one on `event_id`, but `list_deliveries` filters `endpoint_id` and orders by `created_at`, `list_webhook_endpoints` and `enqueue_for_event` filter `webhook_endpoints.org_id`, and both `ON DELETE CASCADE` references (`organizations → webhook_endpoints`, `webhook_endpoints → webhook_deliveries`) need those same columns indexed — Postgres does not create indexes for referencing FK columns, and this migration creates the whole table, so no pre-existing index can cover them.
What breaks in production: `webhook_deliveries` grows by one row per event per endpoint, so the deliveries listing becomes a sequential scan plus a full sort of the largest table in the database on every page view, `enqueue_for_event` scans `webhook_endpoints` on every dispatched event, and deleting an organization (offboarding, GDPR erasure) scans `webhook_deliveries` once per endpoint and locks the table for the duration.
Fix: add to the same migration, inside the existing transaction (safe here because both tables are created in it — if these are ever split into a follow-up migration against populated tables, they must become `CREATE INDEX CONCURRENTLY` outside any `BEGIN`):
```sql
CREATE INDEX idx_webhook_endpoints_org ON webhook_endpoints (org_id);
CREATE INDEX idx_webhook_deliveries_endpoint_created
    ON webhook_deliveries (endpoint_id, created_at DESC, id DESC);
```
The trailing `id DESC` also supplies the total order the already-reported R57 finding needs for `list_deliveries`, so that fix and this one are one index, not two.
*Allow side pinned with the deny side*: `EXPLAIN (ANALYZE)` must show an Index Scan for the deliveries listing **and** must still show the existing plan for `_claim_batch` — adding indexes can flip the planner off `idx_webhook_deliveries_status`, so measure the claim query before and after, not only the new one.
*Red-prove each clause separately*: on a seeded table (≥100k deliveries across ≥100 endpoints), drop each index alone and observe the plan flip to `Seq Scan` on exactly one query — (i) `idx_webhook_deliveries_endpoint_created` → the listing; (ii) `idx_webhook_endpoints_org` → `enqueue_for_event`; (iii) both → the `DELETE FROM organizations` cascade timing.
*Fail loudly*: do not write `IF NOT EXISTS`. A re-run against a database that already has these indexes must abort the migration rather than report success, so a partially applied 0042 cannot be mistaken for a complete one.
*Preserve*: keep `idx_webhook_deliveries_status` (or replace it with the composite the claim query actually needs, per the already-reported claim-index finding) — do not drop the index the worker depends on while adding the ones the API needs.
*Boundary and tie*: `created_at DESC, id DESC` fixes the order for rows sharing a timestamp, so a page boundary cut through equal `created_at` values neither repeats nor skips a delivery.

### Major: `test_send_once_posts_the_signed_payload` asserts a property of its own fixture, which is why the missing dedup key looked present (RT1 (c)/(d))
File: `tests/webhooks/test_delivery.py` — `FakeDelivery.payload`, and the assertion `json.loads(captured["body"])["type"] == "invoice.paid"`
What is wrong: `FakeDelivery.payload` is hand-authored to contain `id` and `type`, fields that a real `WebhookDelivery.payload` — which is `envelope.payload`, copied verbatim by `enqueue_for_event` — does not carry, so the test's only body assertion is true because the fixture put the value there, and the header assertions (`startswith("sha256=")`, `.isdigit()`) are true under any secret and any bytes.
What breaks in production: this is a correction to the already-reported "the delivered payload carries no event id or type" — that defect is not merely unreported by the tests, it is actively masked, so the suite will stay green after the fix for the R40 body/MAC mismatch is applied wrongly, and no test in the diff can distinguish "we signed the transmitted bytes" from "we signed something else".
Fix: replace `FakeEndpoint`/`FakeDelivery` with real `m.WebhookEndpoint(...)` and `m.WebhookDelivery(...)` instances (both are plain declarative models and construct without a session), so a field the model does not define raises instead of being invented by the double, and assert against independently computed values rather than against `signing.sign`'s own output:
```python
body = captured["body"]
assert body == signing.serialize(delivery.payload).encode()      # bytes on the wire == bytes signed
expected = hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
assert captured["headers"][signing.SIGNATURE_HEADER] == "sha256=" + expected
```
Both assertions must be computed in the test, not obtained from `sign`/`verify`, and the payload fixture must be built from what `dispatch` passes (`{"invoice_id": 918, "amount_cents": 4200}` — no `id`, no `type`) so it cannot smuggle in fields production never sends. Expect the first assertion to be **red until the already-reported R40 defect is fixed**; that is the test doing its job, not a broken test.
*Allow side pinned with the deny side*: a correctly signed delivery must verify (allow) **and** a single mutated payload byte must fail verification (deny) — a test that only checks rejection passes against a `verify` that returns `False` unconditionally.
*Red-prove each clause separately, by execution*: (i) drop `sort_keys=True` from `serialize` → the body assertion reds; (ii) flip one byte of `SECRET` before signing → the signature assertion reds; (iii) delete `TIMESTAMP_HEADER` from `send_once`'s headers → the timestamp assertion reds. Three mutations, three different assertions.
*Fail loudly when the check cannot run*: these are `@pytest.mark.asyncio` tests and the diff adds no `pytest-asyncio` configuration — set `asyncio_mode = auto` (or register the marker) together with `--strict-markers` so a missing plugin errors the run; an async test that is silently skipped is "examined nothing" spelled exactly like "found nothing".
*Preserve*: keep `test_send_once_propagates_connection_errors` and the backoff table — the fix must add contact with production bytes, not replace the coverage that exists.
*Boundary and tie*: pin the ordering case explicitly with a two-key payload whose insertion order differs from sorted order (`{"b": 2, "a": 1}`), so the serialization the signature commits to is fixed by an assertion rather than by whichever dict order the interpreter happened to produce.

---

### Minor: the delivery status vocabulary exists in three places and the one named constant is dead (R2)
File: `app/webhooks/models.py` — `STATUSES`; `app/webhooks/delivery.py` — the `"pending"` / `"in_flight"` / `"delivered"` / `"failed_permanent"` literals; `migrations/0042_webhook_delivery.sql` — the `CHECK (status IN (...))` list
What is wrong: `STATUSES` is defined and never referenced by any of the four writers or the one reader, which is the mechanism behind the already-reported CHECK-constraint mismatch — three independent spellings of one enum with nothing tying them together.
What breaks in production: the next status added or renamed drifts again in exactly the same way, because nothing fails when the three lists disagree.
Fix: make `STATUSES` the single source — use it in the model column (`Enum(*STATUSES, name="webhook_delivery_status")` or a `CheckConstraint` built from it), have `delivery.py` reference named members instead of literals, and add a test that asserts the DDL's `CHECK` list equals `STATUSES` (red-proved by removing one member from either side).

### Minor: `parsed.scheme.startswith("http")` judges the notation, not the scheme (R47)
File: `app/api/routes/settings.py` — `create_webhook_endpoint`, `if not parsed.scheme.startswith("http")`
What is wrong: a prefix match accepts any scheme beginning with those four characters (`httpx://`, `http+unix://`), where the interpreter that actually decides the meaning is `httpx`'s transport layer, not this string test — separate from the already-reported point that the host is unrestricted.
What breaks in production: such an endpoint is accepted with a 201 and then fails at every delivery with `httpx.UnsupportedProtocol` (an `httpx.HTTPError`, so it is retried), burning all five attempts and up to 30s of blocking backoff per event before it is recorded as `failed_permanent`.
Fix: `if parsed.scheme not in {"https"}` — an equality test against the exact set the docs already promise ("Only `https://` URLs are accepted"), which also removes the plaintext-`http` gap in the same edit.

### Minor: `webhook_deliveries.event_id` is the one reference column in the migration with no foreign key
File: `migrations/0042_webhook_delivery.sql` — `event_id BIGINT NOT NULL`
What is wrong: both other reference columns in this migration carry `REFERENCES ... ON DELETE CASCADE`, but `event_id` — which the docs publish as the customer's deduplication key — has no constraint, so a delivery can point at an event row that never existed or has been purged.
What breaks in production: event retention or a bad insert leaves delivery rows referencing nothing, and nothing detects it.
Fix: add `REFERENCES events (id) ON DELETE CASCADE` if deliveries should die with their event, or state in the migration why the decoupling is deliberate; if the events table is partitioned or purged on a schedule, say so in a comment on the column rather than leaving the omission unexplained.

### Minor: the deliveries listing exposes no timestamp for the attempt it is listing
File: `app/webhooks/models.py` — `WebhookDelivery.to_dict`
What is wrong: `to_dict` returns `next_attempt_at` but neither `created_at` nor `updated_at`, while the route orders by `created_at` — the client receives rows sorted by a field it cannot see.
What breaks in production: a customer debugging a missed webhook cannot tell when we attempted the delivery, and for a `delivered` row the only timestamp returned (`next_attempt_at`) is a stale value that has no meaning.
Fix: add `"created_at": self.created_at.isoformat()` and `"updated_at": self.updated_at.isoformat()` to `WebhookDelivery.to_dict`, and keep `next_attempt_at` only for non-terminal statuses.
