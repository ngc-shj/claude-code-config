# Review — F10-webhooks.diff (second pass)

Routing: digest matched R1, R3, R34, R41, R47, R49, R57, RS3, RT4, RT6, RT7; triggered rows
extracted by anchored `rg`, plus the Finding Floor and Remedy Floor sections. No fallback to the
full rules file was needed.

Everything on the reported-titles list is treated as covered. What follows is what it misses, plus
two places where it is wrong or understated about the code.

## New findings

### Major: `deliver` dereferences the endpoint row it never confirmed exists — the second, unreported site of the same pattern
File: `app/webhooks/delivery.py` — `deliver`, `endpoint = session.get(m.WebhookEndpoint, delivery.endpoint_id)`
What is wrong: the reported list flags the unchecked `session.get` in `_finish` only, but `deliver`
has the identical unchecked lookup, and `endpoint` is then passed straight into `send_once`, which
reads `endpoint.signing_secret` and `endpoint.url`.
What breaks in production: an endpoint deleted between enqueue and claim (the `ON DELETE CASCADE`
in the migration deletes its deliveries, but a delivery already claimed into the in-process batch is
held in memory) makes `send_once` raise `AttributeError`, which `except httpx.HTTPError` does not
catch and `asyncio.gather` re-raises out of `run_worker`, so the other up-to-99 deliveries in the
same batch are abandoned mid-flight and left `in_flight` forever.
Fix: inside the `session_scope` in `deliver`, branch on the lookup result before leaving the block —
`if endpoint is None: _finish(delivery.id, "failed_permanent", delivery.attempts, None, "endpoint
deleted"); return`, and treat `endpoint.active is False` the same way with detail `"endpoint
disabled"`; copy `url` and `signing_secret` into locals in the same block and pass those to
`send_once`, so the guard composes with (and does not substitute for) the already-reported
detached-instance defect. Boundary and tie: "row absent" and "row present but inactive" both fall on
the terminal side (`failed_permanent`, distinguishable by `detail`), and two deliveries for the same
endpoint racing the same delete both take the absent branch and both terminate — no row is left in a
half state. Allow side that must still succeed: a delivery whose endpoint exists and is active still
issues exactly one POST and still reaches `_finish(..., "delivered", ...)`. Red-prove each clause
separately by execution: (a) delete the endpoint row, run `deliver` on a claimed delivery, assert
status `failed_permanent` and detail `"endpoint deleted"` — red before the fix with an escaping
`AttributeError`; (b) set `active=False`, assert detail `"endpoint disabled"` — red if only the
`None` branch is added; (c) leave the endpoint intact, assert one captured request and status
`delivered` — red if the guard returns early unconditionally. Fail loudly where the check cannot
run: a failure of the lookup itself (session/DB error) must raise a named exception and leave the
row claimable for the reaper, never be spelled the same as "endpoint deleted" — "could not look up"
and "not there" must not share a status. Do not fix by deleting what made this visible: do not widen
`except httpx.HTTPError` to `except Exception`, which would swallow this class everywhere, and do
not drop the `session.get` in favour of trusting `delivery.endpoint_id`.

### Major: the migration indexes neither of the two query shapes the change adds
File: `migrations/0042_webhook_delivery.sql` — `CREATE INDEX idx_webhook_deliveries_status` / `CREATE UNIQUE INDEX idx_webhook_deliveries_event` (and the absent index on `webhook_endpoints`)
What is wrong: the reported list covers only the claim query's index; the change also adds
`enqueue_for_event`'s `WHERE org_id = ? AND active` over `webhook_endpoints` and `list_deliveries`'s
`WHERE endpoint_id = ? ORDER BY created_at DESC` over `webhook_deliveries`, and neither table has an
index that serves them — both FK columns (`webhook_endpoints.org_id`, `webhook_deliveries.endpoint_id`)
are unindexed, which Postgres does not create automatically.
What breaks in production: every dispatched `invoice.paid` seq-scans `webhook_endpoints`, every call
to the new deliveries route seq-scans the highest-volume table the feature creates (one row per
event per endpoint, each carrying a full JSONB payload and an unbounded response body), and
`DELETE FROM organizations` / `DELETE FROM webhook_endpoints` each seq-scan the child table to
enforce `ON DELETE CASCADE`.
Fix: in the same migration, before `COMMIT`, add `CREATE INDEX idx_webhook_endpoints_org ON
webhook_endpoints (org_id, active);` and `CREATE INDEX idx_webhook_deliveries_endpoint ON
webhook_deliveries (endpoint_id, created_at DESC, id DESC);`, and change `list_deliveries`'s
`order_by` to `(created_at.desc(), id.desc())` so the query's sort matches the index exactly —
without that the index is not used for the ordering and the fix is cosmetic. Boundary and tie: the
trailing `id DESC` is what gives the listing a total order, so a page cut falling inside a group of
rows sharing one `created_at` neither skips nor repeats a row; this composes with the already-
reported non-unique-ordering finding rather than replacing it. Allow side that must still succeed:
the fan-out insert in `enqueue_for_event` still commits within its current latency budget despite two
more indexes to maintain on `webhook_deliveries`, and the existing claim query still plans over
`idx_webhook_deliveries_status` — pin both. Red-prove each clause separately by execution, against a
real Postgres with the migration applied and a seeded table: (a) `EXPLAIN` the deliveries listing and
assert `Index Scan using idx_webhook_deliveries_endpoint` — red before the index (`Seq Scan`); (b)
`EXPLAIN` the endpoint lookup and assert `Index Scan using idx_webhook_endpoints_org` — red before
that index; (c) assert both index names are present in `pg_indexes` after migrating — red if the
migration lines are reverted. Fail loudly where the check cannot run: if the test cannot reach a real
Postgres it must fail naming "database unavailable" rather than skip, because a skipped plan check
reads identically to a passing one. Do not fix by deleting what made this visible: keep
`idx_webhook_deliveries_status` (the claim query still needs it) and do not "fix" the listing by
dropping its `ORDER BY`.

### Minor (question): nothing in the change starts `run_worker`
File: `app/webhooks/delivery.py` — `run_worker`
What is wrong: `run_worker` is the only thing that ever moves a delivery out of `pending`, and no
call site, process entrypoint, CLI command, or startup hook for it appears anywhere in the change —
the dispatcher only enqueues.
What breaks in production: if no supervisor entry exists outside this change, every row inserted by
`enqueue_for_event` stays `pending` forever and no customer receives anything, while the API and the
docs report the feature as live.
Question that closes this: name the process definition that invokes `run_worker` (a worker entry in
the deployment manifest, a `__main__`, or a startup task registration). If one exists outside the
diff, this is closed with no code change; if it does not, it becomes a Critical R41 finding — a
declared capability whose backing path was never wired.

### Minor (question): the two async tests are the only coverage of `send_once`, and nothing in the change guarantees they execute
File: `tests/webhooks/test_delivery.py` — `@pytest.mark.asyncio` on `test_send_once_posts_the_signed_payload` and `test_send_once_propagates_connection_errors`
What is wrong: the change introduces `@pytest.mark.asyncio` without adding the plugin dependency or
any `asyncio_mode` / marker-strictness configuration, and an unregistered `asyncio` marker makes
pytest treat the coroutine as never-awaited — a warning and a non-failing outcome, not a failure.
What breaks in production: the only two tests that exercise the real `send_once` call path would
report green without running, so the signing and transport path ships with the four synchronous
signing tests as its entire real coverage.
Question that closes this: is `pytest-asyncio` already a dev dependency with `asyncio_mode` set for
this repo? If yes this is closed; if no, add it and set `--strict-markers` (or
`filterwarnings = error`) in the pytest configuration so an unregistered marker or an un-awaited
coroutine is a hard error rather than a warning — that setting is worth adding either way, since it
is what makes the difference between "ran and passed" and "was never run" observable.

### Minor: `STATUSES` is declared and referenced by nothing
File: `app/webhooks/models.py` — `STATUSES = ("pending", "in_flight", "delivered", "failed_permanent")`
What is wrong: the tuple is never used — not by the `status` column, not by `_claim_batch` or
`_finish`, not by the migration — so the four-state contract it states is enforced in neither Python
nor (correctly) the DDL, which is exactly how the migration's `CHECK` came to list `'failed'`
instead.
What breaks in production: nothing today, but the constant reads as the source of truth for the
state set while being inert, so the next status added will drift from the `CHECK` the same way.
Fix: either bind it — `status = Column(String(20), nullable=False, default="pending")` plus
`CheckConstraint(status.in_(STATUSES))` — or delete it; a constant that no code consults is not a
contract.

### Minor: the URL scheme check is a prefix match, not a scheme allowlist
File: `app/api/routes/settings.py` — `create_webhook_endpoint`, `if not parsed.scheme.startswith("http")`
What is wrong: `startswith("http")` admits any scheme whose spelling begins with those four
characters, and it admits plain `http://`, which `docs/webhooks.md` states is not accepted ("Only
`https://` URLs are accepted") — this is separate from the reported SSRF finding, which is about
which hosts are reachable, not which schemes are.
What breaks in production: signed payloads are delivered in cleartext to `http://` endpoints that the
documentation promises were rejected at registration, so the signature protects integrity while the
payload itself is readable on the wire.
Fix: replace the prefix test with membership in an explicit set — `if parsed.scheme not in
{"https"}` — and state the boundary: `https` is accepted, everything else including `http` is
rejected with 422. If plaintext `http` is intentionally allowed for sandbox tenants, the doc is the
artifact that must change, and the allowance must be a named condition rather than a side effect of
`startswith`.

## Corrections to the reported list

### Correction (understated): `UNIQUE (event_id)` does not merely block the second endpoint — it drops the whole fan-out silently
File: `migrations/0042_webhook_delivery.sql` — `CREATE UNIQUE INDEX idx_webhook_deliveries_event`; `app/webhooks/delivery.py` — `enqueue_for_event`
The list records this as "fan-out to a second endpoint impossible". The code makes it worse:
`enqueue_for_event` builds every row and calls `session.add_all(rows)` in one `session_scope`, so the
unique violation aborts the entire transaction — the first endpoint's row is rolled back too. The
dispatcher's `except Exception` then turns that into a `log.warning`, so an organization with two
active endpoints receives zero webhooks for every event, with a 200 response and no error surfaced
anywhere a customer or an on-call engineer would look.
Fix: replace the index with `CREATE UNIQUE INDEX idx_webhook_deliveries_endpoint_event ON
webhook_deliveries (endpoint_id, event_id);`, which is the constraint the docs' "deduplicate on
`event_id`" actually needs — one row per endpoint per event. Boundary and tie: two concurrent
`dispatch` calls for the same `event_id` and the same endpoint collide on exactly one row, and the
loser must be handled as "already enqueued" (an idempotent no-op), not as a failure. Allow side that
must still succeed: an organization with N active endpoints gets N rows for one event — assert
`enqueue_for_event` returns N and that N rows exist. Red-prove each clause separately by execution:
(a) two endpoints, one event, assert two rows — red before the fix (zero rows, plus a swallowed
`IntegrityError`); (b) the same event enqueued twice for one endpoint, assert one row and no
exception escaping — red if the unique index is dropped rather than re-keyed; (c) the dispatcher's
`except Exception` must not be the thing that makes (a) pass — assert no `log.warning` was emitted.
Fail loudly where the check cannot run: the enqueue path must distinguish "already enqueued"
(idempotent success) from "could not enqueue" (a real failure that must not be swallowed into a log
line). Do not fix by deleting what made this visible: do not simply drop the unique index, which
would restore fan-out while losing the at-least-once deduplication the docs promise.

### Correction (incorrect as stated): the create handler does not return 201 before the transaction commits
File: `app/api/routes/settings.py` — `create_webhook_endpoint`
The list contains "the create handler returns 201 before the transaction commits". As written, the
`return` expression is *evaluated* before the commit, but the function does not return until
`session_scope.__exit__` has run; a commit failure propagates out of the `with` statement and
discards the return value, so the client receives a 500 and not a 201. The observable defect the
title describes does not exist on this code path. What is true and worth keeping is narrower: the
response body is built from flushed-but-uncommitted state, so any value the database assigns at
commit time rather than at flush time (a trigger-populated column, a server-side default other than
the `BIGSERIAL` id) would be reported wrong. That is not currently reachable given the columns
`to_dict` returns, so it is not a finding today. Note this correction depends on `session_scope`
behaving as a standard commit-on-exit context manager, which the change does not contain — if it
swallows commit errors, the original finding stands and the defect is in `session_scope`.
