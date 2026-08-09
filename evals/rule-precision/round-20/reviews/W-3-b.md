# Review — F10-webhooks.diff

Routing: digest matched R1, R3, R4, R9, R11, R29, R38, R40, R41, R47, R49, R55,
R57, RS1, RS2, RS3, RS4, RT1, RT5, RT6, RT7, RT8. Triggered rows plus
`rule-details/{R3,R40,R47,R49,RS3,RT5}.md`, Finding Floor and Remedy Floor
extracted as prescribed. No fallback to the full rules file was needed.

---

### Critical: deliveries endpoint has no tenancy filter
File: `app/api/routes/settings.py` — `list_deliveries`
What is wrong: the query filters only on `WebhookDelivery.endpoint_id` and never
joins to `WebhookEndpoint.org_id`, while the sibling route added three lines
above (`list_webhook_endpoints`) does filter `WebhookEndpoint.org_id == user.org_id`
— the tenancy pattern was propagated to one of the two new read routes (R3,
security-relevant).
What breaks in production: any authenticated user can enumerate `endpoint_id`
and read every other organization's delivery history, and `docs/webhooks.md`
states the route "returns the most recent attempts for an endpoint belonging to
your organization", so operators will believe the boundary exists (R49).
Fix: change the query to
`session.query(m.WebhookDelivery).join(m.WebhookEndpoint, m.WebhookEndpoint.id == m.WebhookDelivery.endpoint_id).filter(m.WebhookEndpoint.org_id == user.org_id, m.WebhookDelivery.endpoint_id == endpoint_id)`,
and raise `HTTPException(404)` when the endpoint id resolves to no row for this
org — 404 rather than 403 so the response does not confirm that a foreign
endpoint id exists. Boundary and tie: an id that exists but belongs to another
org and an id that does not exist must produce byte-identical 404 bodies; an id
owned by the caller's org returns its rows even when the caller is not the user
who created the endpoint (org-scoped, not user-scoped). Allow side pinned: a
test that creates an endpoint for org A and asserts user A still receives its
delivery rows with the same body as before this fix — the fix must not degrade
into "deny everything", and the existing per-endpoint listing behaviour must be
preserved. Red-prove by executing two separate mutations: (i) delete the
`org_id` predicate and observe the cross-tenant test go red on the row count;
(ii) delete the `endpoint_id` predicate and observe the same-org test go red
because it now sees a second endpoint's rows. If `user.org_id` is absent or
`None`, raise rather than falling through to an unfiltered query, so "could not
determine the tenant" is not spelled the same as "no rows".

---

### Critical: signing secrets are generated from a non-cryptographic PRNG
File: `app/webhooks/signing.py` — `new_signing_secret`
What is wrong: the secret is built from `random.choice(_ALPHABET)`, which draws
from the module-global Mersenne Twister — a generator whose internal state is
recoverable from observed output and which is not a CSPRNG.
What breaks in production: an attacker who obtains any secret material derived
from the same process-global generator (or who can force enough endpoint
creations to observe its output) can predict subsequently issued signing
secrets and forge webhook payloads that every customer's verifier accepts as
genuine.
Fix: replace the body with `secrets.token_urlsafe(SECRET_BYTES)` prefixed by
`SECRET_PREFIX`, importing `secrets` and dropping the now-unused `random`,
`string` and `_ALPHABET`. Preserve what made the feature usable: the returned
value must keep the `whsec_` prefix and remain URL-safe ASCII so existing stored
secrets and customer parsers still work. Because `token_urlsafe(32)` returns 43
characters, update `test_new_signing_secret_has_prefix_and_length` to assert
`len(secret) >= len(SECRET_PREFIX) + 32` rather than deleting the assertion —
the length check is what makes a truncated-secret regression visible. Boundary
and tie: state that `SECRET_BYTES` now means bytes of entropy, not output
characters, and that two secrets generated in the same microsecond must differ.
Red-prove with two separate executed mutations: (i) restore `random.choice` and
run a test that calls `random.seed(0)` before generating two secrets and asserts
they are not the seeded-reproducible pair — it must go red; (ii) shorten the
argument to `token_urlsafe(4)` and observe the length assertion go red. If
`secrets` cannot supply entropy the call raises — do not catch it and fall back
to `random`; a secret that could not be generated must abort endpoint creation
with a 500, never return a weak one.

---

### Critical: signature comparison is not constant time
File: `app/webhooks/signing.py` — `verify`, `return expected == signature`
What is wrong: the recomputed HMAC is compared with Python's `==`, which
short-circuits on the first differing byte, and `docs/webhooks.md` presents this
function's algorithm as the customer-facing verification recipe while telling
customers to "compare it against your own computation using a constant-time
comparison" — the shipped implementation does not do what its own documentation
instructs (RS1, R49).
What breaks in production: a caller who can submit candidate signatures to any
endpoint that reuses `verify` recovers the correct digest byte by byte from
response-time differences, after which arbitrary forged payloads verify.
Fix: `return hmac.compare_digest(expected, signature)` (`hmac` is already
imported). Boundary and tie: `compare_digest` still leaks length, so reject
signatures whose length differs from `len("sha256=") + 64` before comparing, and
state that a signature equal to the expected value except in case is a reject
(hex digests are lower-case here). Allow side pinned: the existing
`test_verify_accepts_signature_produced_by_sign` must still pass unchanged — the
fix must not become "reject everything". Red-prove with two separate executed
mutations: (i) replace `compare_digest` with `==` and observe a new test that
asserts `verify` is wired to `hmac.compare_digest` (patch `hmac.compare_digest`
with a spy and assert it was called with both operands) go red; (ii) flip the
recomputed digest by one byte and observe the accept test go red. If `signature`
is not a `str` (an off-type value from a caller), raise a `TypeError` rather
than returning `False`, so "could not compare" is distinguishable from
"compared and rejected".

---

### Critical: the transmitted body is not the bytes that were signed, and the timestamp is unsigned
File: `app/webhooks/delivery.py` — `send_once`; `app/webhooks/signing.py` — `sign`
What is wrong: `sign` computes the MAC over `json.dumps(payload, sort_keys=True)`
while `send_once` transmits `client.post(endpoint.url, json=delivery.payload, ...)`,
letting httpx serialize the payload independently (its own separators, no key
sorting), and the MAC input omits the timestamp entirely — yet `docs/webhooks.md`
states the signature is "the HMAC-SHA256 of `"{timestamp}.{raw_request_body}"`"
(R40 producer/strict-consumer divergence, R49 overstated claim). Codebase
awareness: the change already contains the shared serializer
`signing.serialize()`, and `send_once` bypasses it by using httpx's `json=`
kwarg rather than feeding it the bytes it signed (R1).
What breaks in production: every customer who implements the documented recipe
computes a different MAC and rejects 100% of deliveries, and because the
timestamp is outside the MAC an attacker who captures one request can rewrite
`X-Acme-Timestamp` to `now` and replay it forever, defeating the five-minute
replay window the docs promise.
Fix: in `send_once`, build the body once — `body = signing.serialize(delivery.payload).encode()`
— change `sign` to take that byte string and return
`hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256)`,
and POST with `client.post(endpoint.url, content=body, headers=headers)` keeping
the explicit `Content-Type: application/json` header already present. Give
`verify(secret, timestamp, body, signature, max_age_seconds=300)` the same
signature so the two sides share one input string, and have it reject when
`abs(now - int(timestamp)) > max_age_seconds`. Preserve the feature: the request
body must remain valid JSON that decodes to the same object, so
`test_send_once_posts_the_signed_payload`'s `json.loads(captured["body"])["type"]`
assertion still holds. Boundary and tie: a timestamp exactly 300 seconds old is
accepted and 301 is rejected; a request whose timestamp is in the future by more
than the skew allowance is rejected; two payloads that differ only in key order
now produce the same MAC because `serialize` sorts keys — say so. Red-prove with
three separate executed mutations, one per clause: (i) re-serialize the body
independently in `send_once` (e.g. `json.dumps(payload)` without `sort_keys`)
and observe a new round-trip test — which feeds the *captured request bytes and
captured timestamp header* into `verify` — go red; (ii) drop the `f"{timestamp}."`
prefix from the MAC input and observe a test that mutates only the timestamp
header and expects `verify` to fail go red; (iii) set the age check to
`> 100000` and observe the stale-timestamp test go red. A non-numeric or absent
timestamp header must raise a named error, not be treated as age zero.

---

### Critical: the signing secret is returned on every endpoint read
File: `app/webhooks/models.py` — `WebhookEndpoint.to_dict`, `"signing_secret": self.signing_secret`
What is wrong: `to_dict` unconditionally includes the HMAC key, and it is the
serializer used by both `create_webhook_endpoint` and `list_webhook_endpoints`,
so `GET /v1/settings/webhook-endpoints` hands every endpoint's secret back on
every call — directly contradicting `docs/webhooks.md`, which states "the
response is the only place the signing secret appears — it cannot be read back
afterwards" (RS4, R49).
What breaks in production: the key that authenticates every outbound webhook is
sprayed into browser caches, proxy logs, API response logs and any client-side
storage that holds a settings page response, so a single log read lets an
attacker forge signed events to that customer's endpoint.
Fix: remove `signing_secret` from `to_dict`, and have `create_webhook_endpoint`
return `{**endpoint.to_dict(), "signing_secret": secret}` using the value
returned by `new_signing_secret()` that it already holds in a local variable —
so the secret appears exactly once, at creation, as the docs promise. Preserve
the feature the change ships: creation must still return the secret, otherwise
customers can never configure verification; do not "fix" this by removing the
secret from the create response too. Boundary and tie: state explicitly that an
endpoint created before this change keeps its secret and that the only recovery
path for a lost secret is a rotate endpoint (add one, or document that deletion
and re-creation is the recovery path). Red-prove with two separate executed
mutations: (i) re-add the key to `to_dict` and observe a new test asserting
`"signing_secret" not in list_webhook_endpoints(...)[0]` go red; (ii) drop the
key from the create response and observe the creation test asserting
`response["signing_secret"].startswith("whsec_")` go red.

---

### Critical: user-supplied URL is fetched with redirects followed and no scheme or address restriction
File: `app/api/routes/settings.py` — `create_webhook_endpoint`; `app/webhooks/delivery.py` — `run_worker`
What is wrong: registration accepts anything whose scheme merely *starts with*
`"http"` and whose netloc is non-empty (`parsed.scheme.startswith("http")`), a
surface-form check over a string whose meaning is fixed by the URL resolver and
the HTTP client (R47), while the worker's client is constructed with
`follow_redirects=True` — so `http://169.254.169.254/latest/meta-data/`,
`http://127.0.0.1:6379/`, and any external URL that 302s to them are all valid
endpoints, and plain `http://` is accepted despite `docs/webhooks.md` stating
"Only `https://` URLs are accepted" (R49).
What breaks in production: a tenant registers an internal address and the worker
POSTs signed customer event payloads to it while returning the response body
into `webhook_deliveries.response_body`, which the deliveries route then serves
back — a full read-side SSRF against the internal network with an exfiltration
channel.
Fix: replace the prefix test with an exact decision made by the interpreter that
gives the string meaning: require `parsed.scheme == "https"`, require
`parsed.hostname` non-empty, reject userinfo (`parsed.username`/`parsed.password`)
and non-default ports outside an allowlist; then, at request time in
`send_once`, resolve the hostname with `socket.getaddrinfo` and reject if any
returned address satisfies `ipaddress.ip_address(a).is_private or .is_loopback
or .is_link_local or .is_reserved or .is_multicast`, and set
`follow_redirects=False` on the `AsyncClient` so a 3xx is recorded as a
permanent failure rather than chased. The resolve-at-request-time half is
required because a registration-time check alone is bypassed by DNS rebinding.
Preserve the feature: a genuine public HTTPS endpoint whose DNS resolves to a
public address must still receive its POST — pin that with a test using a
resolver stub returning `203.0.113.10`. Boundary and tie: `100.64.0.0/10`
(carrier-grade NAT) and IPv6 `::ffff:127.0.0.1` must be rejected; a hostname
resolving to both a public and a private address is rejected (all-must-pass, not
any). Red-prove with three separate executed mutations: (i) restore
`startswith("http")` and observe the `http://…` registration test go red; (ii)
remove the private-range predicate and observe the `169.254.169.254` delivery
test go red; (iii) set `follow_redirects=True` and observe the redirect-to-
loopback test go red. When `getaddrinfo` raises, mark the delivery failed with a
named "could not resolve host" detail — an unresolvable host must not fall
through to "no private address found, therefore allowed".

---

### Critical: the migration's status CHECK constraint does not contain the status the code writes
File: `migrations/0042_webhook_delivery.sql` — `CHECK (status IN ('pending', 'in_flight', 'delivered', 'failed'))`; `app/webhooks/delivery.py` — `_finish(delivery.id, "failed_permanent", ...)`
What is wrong: the code and `app/webhooks/models.py::STATUSES` use
`"failed_permanent"` while the constraint permits `"failed"` — the same
four-member enum was written twice with a divergent spelling in one copy (R3,
R40).
What breaks in production: the first delivery that exhausts `MAX_ATTEMPTS`
raises an `IntegrityError` inside `_finish`, which propagates out of `deliver`
and out of the `asyncio.gather` in `run_worker`, killing the worker loop and
leaving that delivery stuck in `in_flight` forever.
Fix: change the constraint to
`CHECK (status IN ('pending', 'in_flight', 'delivered', 'failed_permanent'))`
and derive the SQL list from `app.webhooks.models.STATUSES` in a test rather
than restating it — add
`test_migration_check_matches_STATUSES` that parses the `CHECK (status IN (...))`
literal out of `migrations/0042_webhook_delivery.sql` and asserts set equality
with `STATUSES`, so the next added status cannot drift again. Preserve the
control: keep the CHECK constraint — do not fix this by dropping it, which would
make every future spelling error silent. Boundary and tie: state that the
constraint is the authority and the Python tuple must be a subset-equal of it;
if a row already exists with a status outside the new list the migration must
fail loudly rather than being written `NOT VALID`. Red-prove with two separate
executed mutations: (i) change one element of `STATUSES` and observe the new
parity test go red; (ii) revert the SQL literal to `'failed'` and observe an
integration test that drives a delivery to `MAX_ATTEMPTS` against a real
migrated database go red with an `IntegrityError`. If the SQL file cannot be
parsed for the CHECK literal, the test must fail with "could not locate the
status constraint", never skip.

---

### Critical: the unique index on `event_id` alone permits only one delivery per event
File: `migrations/0042_webhook_delivery.sql` — `CREATE UNIQUE INDEX idx_webhook_deliveries_event ON webhook_deliveries (event_id)`
What is wrong: `enqueue_for_event` inserts one `WebhookDelivery` row per
matching endpoint for a single `event_id`, so the uniqueness key is one column
short of the natural key `(endpoint_id, event_id)`.
What breaks in production: the moment an organization registers a second
endpoint subscribed to the same event type, `session.add_all(rows)` violates the
index and the whole insert is rolled back — and because
`app/events/dispatcher.py` wraps the call in `except Exception: log.warning`,
every delivery for that event is silently dropped with only a warning line.
Fix: replace with
`CREATE UNIQUE INDEX idx_webhook_deliveries_endpoint_event ON webhook_deliveries (endpoint_id, event_id);`.
Preserve what the index was for: it is the idempotency guard backing the docs'
"delivery is at-least-once, so deduplicate on `event_id`" — keep it unique
rather than downgrading it to a plain index, so a re-dispatched event still
cannot double-enqueue for the same endpoint. Boundary and tie: two endpoints of
the *same* org receiving the same `event_id` is now legal and must succeed; the
same endpoint receiving the same `event_id` twice must still raise; state that
`event_id` is not unique across orgs and therefore is not usable alone as a
dedupe key by consumers. Red-prove with two separate executed mutations: (i)
drop `endpoint_id` from the index and observe a test that enqueues one event for
two endpoints of one org go red on `IntegrityError`; (ii) drop the `UNIQUE`
keyword and observe a test that calls `enqueue_for_event` twice with the same
`event_id` and asserts a single row per endpoint go red.

---

### Critical: `time.sleep` inside an async coroutine blocks the whole worker
File: `app/webhooks/delivery.py` — `deliver`, `time.sleep(delay)`
What is wrong: `deliver` is `async def` but its retry backoff uses the blocking
`time.sleep`, so the coroutine holds the event loop instead of yielding it.
What breaks in production: `run_worker` fans out a batch of up to `BATCH_SIZE`
(100) deliveries with `asyncio.gather`, and one failing endpoint's
2+4+8+16 = 30 seconds of blocking sleep freezes all 99 siblings, the httpx
connection pool and any timeout bookkeeping — a handful of dead endpoints in one
batch exceeds the 60-second lock TTL, letting a second worker claim and re-send
the same events.
Fix: `await asyncio.sleep(delay)` (`asyncio` is already imported at the top of
the module). Preserve the behaviour the sleep provides: the delay must still be
`backoff_for(attempt).total_seconds()` and still occur between attempts, so
retries do not become a tight loop against a failing endpoint. Boundary and tie:
state that the total wall time of a fully-failing delivery (sum of backoffs plus
`MAX_ATTEMPTS × REQUEST_TIMEOUT`) is now the number the lock TTL must exceed,
and cap the per-delivery total with an `asyncio.timeout` so a delivery that sits
exactly at the TTL boundary is abandoned by its own worker rather than
overlapping with the next one. Red-prove with two separate executed mutations:
(i) restore `time.sleep` and observe a test that runs two `deliver` coroutines
under `asyncio.gather` and asserts the total elapsed time is close to the max
rather than the sum go red; (ii) delete the sleep entirely and observe a test
asserting the elapsed time is at least `BASE_DELAY_SECONDS` go red. Both tests
must drive the delay through a monkeypatched clock, not a real 30-second wait —
a test that needs a real sleep is reporting the race rather than pinning it.

---

### Critical: delivery rows are used after their session closes
File: `app/webhooks/delivery.py` — `_claim_batch` (returns `rows` after the `with session_scope()` block) and `deliver` (`endpoint` fetched inside a `with` block, used after it)
What is wrong: both functions return or retain SQLAlchemy ORM instances past the
end of their `session_scope()` context, and every later attribute read
(`delivery.attempts`, `delivery.payload`, `delivery.id`, `endpoint.signing_secret`,
`endpoint.url`) is a lazy load against a closed, committed session.
What breaks in production: with SQLAlchemy's default `expire_on_commit=True`
every one of those reads raises `DetachedInstanceError`, so no delivery is ever
sent and the exception escapes `asyncio.gather` and terminates `run_worker` —
the feature is inoperative from the first poll, and the unit tests cannot see it
because `FakeEndpoint`/`FakeDelivery` in `tests/webhooks/test_delivery.py` are
plain classes with no session at all (RT1: the doubles diverge from the real
boundary in exactly the property under test).
Fix: have `_claim_batch` return plain data rather than ORM instances — inside
the session, build
`[DeliveryJob(id=r.id, endpoint_id=r.endpoint_id, attempts=r.attempts, payload=r.payload) for r in rows]`
from a frozen dataclass, and likewise have `deliver` read
`endpoint.url`/`endpoint.signing_secret` into locals inside its `with` block
before leaving it. Preserve the behaviour: the claim must still flip
`status = "in_flight"` in the same transaction as the SELECT, which is what
stops a second worker taking the same rows — do not fix this by widening the
session's lifetime around the network calls, which would hold a DB connection
open for the full `MAX_ATTEMPTS × REQUEST_TIMEOUT`. Boundary and tie: state that
a row whose endpoint was deleted between claim and send yields no `DeliveryJob`
and is marked failed with a named reason, and that `payload` is copied by value
so a later DB change cannot alter what was signed. Red-prove with two separate
executed mutations, run against a real (SQLite or Postgres) session rather than
the fakes: (i) return the ORM rows from `_claim_batch` again and observe an
integration test that claims a batch and then reads `job.payload` go red with
`DetachedInstanceError`; (ii) move the `endpoint.url` read back outside the
`with` block in `deliver` and observe the same test go red on the endpoint side.
The fakes in `test_delivery.py` must be replaced with real persisted rows for
these two tests, or they pass vacuously.

---

### Major: the distributed lock is not atomic and its TTL is a second round trip
File: `app/webhooks/delivery.py` — `_acquire_lock`
What is wrong: the check-then-set (`if await redis_client.get(LOCK_KEY): return False` /
`await redis_client.set(LOCK_KEY, "1")`) is two round trips with no atomicity,
the expiry is a third, and `run_worker`'s `finally` deletes `LOCK_KEY`
unconditionally without checking the holder token.
What breaks in production: two workers polling within the same round-trip window
both acquire, both claim overlapping rows and both POST — duplicate signed
events to customers; a crash between `set` and `expire` leaves a lock with no
TTL that halts all webhook delivery until someone deletes the key by hand; and
after a TTL expiry worker A's `finally` deletes worker B's freshly acquired
lock.
Fix: replace the body with a single atomic call —
`return bool(await redis_client.set(LOCK_KEY, token, nx=True, ex=LOCK_TTL_SECONDS))`
where `token = uuid.uuid4().hex` is returned to the caller — and replace the
unconditional `await redis_client.delete(LOCK_KEY)` in `run_worker` with a
compare-and-delete Lua script that deletes only when the stored value equals the
caller's token. Preserve the feature: a single worker must still be able to
re-acquire on the next poll after releasing, so the release path must actually
run — do not fix this by removing the release and relying on the TTL, which
would cap throughput at one batch per TTL. Boundary and tie: name
`LOCK_TTL_SECONDS` as a named constant and state that it must exceed the
worst-case batch wall time computed in the `time.sleep` finding above; a worker
whose TTL expires while still delivering must not release, and the tie — two
workers presenting the same token — is impossible by construction because the
token is a uuid4. Red-prove with three separate executed mutations against a
real or in-memory Redis fake honouring `nx`/`ex`: (i) drop `nx=True` and observe
a test where two concurrent `_acquire_lock` calls assert exactly one `True` go
red; (ii) drop `ex=` and observe a test asserting `ttl(LOCK_KEY) > 0` go red;
(iii) revert the release to an unconditional delete and observe a test where
worker A releases after B acquired and asserts B's token still holds go red. If
the Redis call raises, `_acquire_lock` must return `False` and log — an
unreachable lock server must stop the worker, not let it proceed unlocked.

---

### Major: `in_flight` is a non-terminal state with no reset path
File: `app/webhooks/delivery.py` — `_claim_batch` (sets `row.status = "in_flight"`), `_finish`
What is wrong: `in_flight` is only left via `_finish`, which is reached solely
on the success and exhausted-retries paths inside `deliver`; every other exit —
process kill, `IntegrityError` from the status CHECK mismatch above,
`DetachedInstanceError`, an `AttributeError` in `_finish` — leaves the row in
`in_flight`, and `_claim_batch` selects only `status == "pending"` (R38 clause 1).
What breaks in production: a single worker restart silently strands every
in-flight delivery permanently — customers never receive those events, the rows
are never retried and never marked failed, and nothing surfaces the backlog
because `list_deliveries` reports them as merely "in flight".
Fix: add a `claimed_at TIMESTAMPTZ` column set at claim time and a reaper query
run at the top of each `run_worker` iteration that resets
`status = 'pending', next_attempt_at = now()` for rows where
`status = 'in_flight' AND claimed_at < now() - interval '<STALE_AFTER>'`, with
`STALE_AFTER` a named constant strictly greater than the worst-case per-delivery
wall time. Preserve the property the `in_flight` flip provides: it must still
prevent a concurrent worker from claiming the same row within the window — do
not fix this by removing the flip. Boundary and tie: a row claimed exactly
`STALE_AFTER` ago is not yet reclaimed (strict `<`), one microsecond older is;
a row reclaimed while its original worker is still delivering will be sent
twice, which is why `STALE_AFTER` must exceed the worst case and why the
`(endpoint_id, event_id)` unique index above is what bounds the damage. Also
increment `attempts` at claim time so a repeatedly-crashing delivery still
reaches `MAX_ATTEMPTS` instead of looping forever. Red-prove with three separate
executed mutations: (i) delete the reaper and observe a test that claims a batch,
kills the coroutine, then asserts the row returns to `pending` go red; (ii) set
`STALE_AFTER` to zero and observe a test asserting an actively-delivering row is
*not* reclaimed go red (the allow side); (iii) remove the claim-time `attempts`
increment and observe a test that crashes `MAX_ATTEMPTS` times and asserts a
terminal `failed_permanent` go red. If the reaper query itself errors, log at
error and skip the poll — never proceed as if there were nothing stale.

---

### Major: enqueue failures are swallowed and the dispatcher's own event-type gate contradicts the documented contract
File: `app/events/dispatcher.py` — `WEBHOOK_EVENT_TYPES` and the `try/except Exception` around `webhook_delivery.enqueue_for_event`
What is wrong: two defects in the same block — the bare `except Exception` logs
a warning and lets `dispatch` return the event id as if delivery were scheduled,
and `WEBHOOK_EVENT_TYPES` hard-codes three types as a second, divergent
adjudicator of the same predicate that `enqueue_for_event` already decides per
endpoint (`if not endpoint.event_types or event_type in endpoint.event_types`),
while `docs/webhooks.md` states an empty `event_types` "subscribes the endpoint
to every event type we emit" (R11/R12, R49).
What breaks in production: an endpoint registered with `event_types: []` receives
only three of the product's event types instead of all of them and the customer
has no way to see the gap; and when the enqueue insert fails — which the
`event_id` unique index above guarantees for any org with two endpoints — the
deliveries vanish with a single `log.warning` and no retry, reconciliation or
alert.
Fix: delete `WEBHOOK_EVENT_TYPES` and its use in the `log.info` call, and let
`enqueue_for_event` be the single adjudicator of subscription — it already
holds the per-endpoint predicate, so the dispatcher's copy is a duplicate that
can only drift. Replace the swallow with: catch only the exceptions you can
recover from, re-raise everything else, and emit at `log.exception` with a
counter/metric named for the failure so a dropped enqueue is visible. Preserve
what the `try` was protecting: a webhook failure must still not roll back the
already-committed event row, so keep the enqueue outside the event's
`session_scope` and make the recovery an explicit outbox row or retry rather
than a silent pass. Boundary and tie: state that an event type no endpoint
subscribes to results in zero delivery rows and is a success, not a failure, and
that `dispatch` returns the event id in both cases. Red-prove with three
separate executed mutations: (i) restore the hard-coded set and observe a test
that dispatches a fourth event type to an endpoint with `event_types: []` and
asserts one delivery row go red; (ii) make `enqueue_for_event` raise and observe
a test asserting the failure is recorded/counted go red; (iii) restore the bare
`except Exception: log.warning` and observe the same test go red because the
signal is a warning with no counter. Cross-cutting: this is the only
fire-and-forget in the diff, and it is correctly placed after the event's
`session_scope` closes — the transaction boundary itself is fine.

---

### Major: the worker dies permanently on the first exception
File: `app/webhooks/delivery.py` — `run_worker`
What is wrong: the `while True` loop has a `finally` that releases the lock but
no `except`, so any exception from `_claim_batch`, from `asyncio.gather` (which
re-raises the first child exception by default) or from the lock calls
propagates out of `run_worker` and ends the loop; a related latent defect is
that `batch` is referenced at `if not batch:` outside the `try`, so it is
unbound on any path where `_claim_batch` raised.
What breaks in production: one transient database blip or one endpoint-deleted
`AttributeError` in `_finish` stops all webhook delivery for the whole
deployment until someone notices and restarts the process.
Fix: wrap the loop body in `try/except Exception: log.exception(...)` followed by
`await asyncio.sleep(poll_interval)` so the loop survives, initialise
`batch: list = []` before the inner `try` so the later reference is always bound,
and pass `return_exceptions=True` to `asyncio.gather` so one failed delivery
cannot abort its siblings. Preserve the behaviour that makes the loop useful:
`asyncio.CancelledError` must still propagate so shutdown works — catch
`Exception`, not `BaseException`. Boundary and tie: state that the backoff after
a caught error is `poll_interval` and that repeated failures must escalate (a
consecutive-failure counter that logs at error past a threshold) so a permanently
broken worker is not merely quiet; a batch of exactly zero rows still sleeps
`poll_interval`. Red-prove with three separate executed mutations: (i) make
`_claim_batch` raise once and observe a test asserting the loop performs a second
iteration go red; (ii) remove the `batch = []` initialisation and observe the
same test go red with `UnboundLocalError`; (iii) drop `return_exceptions=True`,
make one of two deliveries raise, and observe a test asserting the other still
completed go red. A caught exception must be logged with `log.exception` so the
traceback is preserved — "the loop continued" must not be spelled the same as
"nothing went wrong".

---

### Major: 4xx responses are retried and the backoff has no jitter, both contrary to the documented contract
File: `app/webhooks/delivery.py` — `deliver` retry branch; `backoff_for`; `docs/webhooks.md` "Retries"
What is wrong: `deliver` treats every non-2xx identically and retries up to
`MAX_ATTEMPTS`, while the docs state "a 4xx is permanent and we stop
immediately"; and `backoff_for` returns a deterministic `2**attempt` while the
docs state "backoff is exponential with jitter" — the test
`test_backoff_grows_exponentially` asserts exact equality, pinning the
jitter-free behaviour as the contract (R29/R49).
What breaks in production: a customer endpoint that returns 401 or 410 receives
five signed copies of every event instead of one, multiplying load on a system
already telling us it will not accept the request; and because every delivery of
a batch is enqueued with the same `next_attempt_at` and backs off by the same
deterministic amount, a downstream outage produces synchronised retry
thundering-herds at 2s, 4s, 8s and 16s.
Fix: in `deliver`, branch on the status — `if 400 <= response.status_code < 500
and response.status_code not in RETRYABLE_4XX: _finish(delivery.id,
"failed_permanent", attempt, response.status_code, detail); return` — with
`RETRYABLE_4XX = {408, 429}` as a named constant, and change `backoff_for` to
return `timedelta(seconds=BASE_DELAY_SECONDS**attempt * (1 + random.random() *
JITTER_FRACTION))`. Update `test_backoff_grows_exponentially` to assert the
value lies in `[base, base * (1 + JITTER_FRACTION)]` rather than deleting the
test — the growth assertion is what makes a collapsed backoff visible. Preserve
the feature: 5xx, timeouts and connection errors must still retry, which is what
the docs promise and what `test_send_once_propagates_connection_errors` covers.
Boundary and tie: 399 and 400 fall on opposite sides; 429 retries and 428 does
not; 500 retries; a 429 carrying `Retry-After` should take that value in
preference to the computed backoff, and state which wins when both are present.
Red-prove with three separate executed mutations: (i) remove the 4xx branch and
observe a test asserting a 404 endpoint is POSTed exactly once go red; (ii) add
429 to the permanent set and observe a test asserting a 429 is retried go red
(the allow side); (iii) set `JITTER_FRACTION = 0` and observe a test asserting
two calls to `backoff_for(3)` differ go red.

---

### Major: the signature header is written to the application log on every attempt
File: `app/webhooks/delivery.py` — `send_once`, `log.info("POST %s headers=%s", endpoint.url, headers)`
What is wrong: the log line interpolates the whole `headers` dict, which
contains `X-Acme-Signature` and `X-Acme-Timestamp` — the complete authenticator
for that request.
What breaks in production: anyone with read access to application logs (a much
wider set than anyone with database access) can lift a `(payload, timestamp,
signature)` triple and replay it to the customer's endpoint — and because the
timestamp is not covered by the MAC, the replay never expires.
Fix: log only what is diagnostic —
`log.info("POST %s delivery=%s attempt=%s", endpoint.url, delivery.id, attempt)`
— and if header presence must be observable, log the header *names* only
(`sorted(headers)`), never their values. Preserve the diagnostic value the line
was added for: the target URL and an identifier that ties the line to a
`webhook_deliveries` row must remain, so an operator can still correlate a log
line with a delivery. Boundary and tie: state that the same redaction applies to
`_finish`'s `response_body` on any path that logs it, and that a header whose
name merely *contains* "signature" or "authorization" is redacted (name-substring
match, case-insensitive) rather than an exact allowlist of the two constants.
Red-prove with two separate executed mutations: (i) restore the `headers=%s`
interpolation and observe a test that captures `caplog` and asserts the emitted
text does not contain the signature value go red; (ii) drop `delivery.id` from
the format string and observe a test asserting the log line contains the
delivery id go red (the allow side, so redaction does not degrade into logging
nothing).

---

### Major: response bodies from an untrusted remote are stored unbounded
File: `app/webhooks/delivery.py` — `_finish` callers, `response.text` passed as `detail`; `app/webhooks/models.py` — `response_body = Column(Text)`
What is wrong: the full body returned by a customer-controlled endpoint is
written verbatim into an unbounded `TEXT` column on every attempt, for both the
success and failure paths.
What breaks in production: an endpoint returning a large error page writes
megabytes per attempt across five attempts and every event, so a single
misbehaving customer can inflate the `webhook_deliveries` table until writes for
every tenant slow or fail on disk.
Fix: truncate at the boundary — `detail = response.text[:RESPONSE_BODY_LIMIT]`
with `RESPONSE_BODY_LIMIT = 4096` as a named module constant, applied on both
the success and failure branches of `deliver`, and cap the read itself by using
`httpx`'s streaming with a byte limit so an unbounded body is never fully
materialised in memory. Preserve what makes the field useful: the first
`RESPONSE_BODY_LIMIT` characters must still be stored so operators can debug a
failing endpoint — do not fix this by dropping `response_body` entirely.
Boundary and tie: a body of exactly `RESPONSE_BODY_LIMIT` characters is stored
unchanged and is a byte-identical no-op through the truncation; one character
more is truncated and marked (append a `"…[truncated]"` sentinel that is
out-of-band relative to the stored prefix). Red-prove with two separate executed
mutations: (i) remove the slice and observe a test that returns a 1 MB body and
asserts `len(row.response_body) <= RESPONSE_BODY_LIMIT + len(marker)` go red;
(ii) set the limit to 0 and observe a test asserting a short body round-trips
unchanged go red.

---

### Major: `_finish` dereferences a row it did not check for existence
File: `app/webhooks/delivery.py` — `_finish`, `row = session.get(m.WebhookDelivery, delivery_id)` followed by `row.status = status`
What is wrong: `session.get` returns `None` for a missing primary key and the
next line assigns straight through it, with no guard.
What breaks in production: an endpoint deleted mid-flight cascades away its
deliveries (`ON DELETE CASCADE` in the migration), so the in-flight `_finish`
raises `AttributeError: 'NoneType' object has no attribute 'status'`, which
escapes `deliver` and — per the `run_worker` finding above — terminates the
worker for every tenant.
Fix: guard with
`if row is None: log.warning("delivery %s vanished before finish", delivery_id); return`
before the assignments. Preserve the behaviour: the normal path must still
persist all five fields (`status`, `attempts`, `response_status`,
`response_body`, `updated_at`) — the guard must return early, not skip
individual assignments. Boundary and tie: state that "row absent" is a
successful no-op while "row present but already terminal" is a real conflict
that must not silently overwrite a `delivered` row with `failed_permanent` —
add `if row.status not in ("pending", "in_flight"): return` and say which side
of that a concurrent double-finish falls on. Red-prove with two separate
executed mutations: (i) remove the `None` guard and observe a test that deletes
the row then calls `_finish` go red with `AttributeError`; (ii) remove the
terminal-status guard and observe a test that calls `_finish(..., "delivered")`
then `_finish(..., "failed_permanent")` and asserts the row is still
`delivered` go red.

---

### Major: naive and aware datetimes are mixed across the write path, and the migration's columns carry no time zone
File: `app/webhooks/delivery.py` — `enqueue_for_event` (`next_attempt_at=datetime.utcnow()`); `migrations/0042_webhook_delivery.sql` — all four `TIMESTAMP` columns; `app/webhooks/models.py` — `DateTime(timezone=True)`
What is wrong: `enqueue_for_event` is the single site in the diff using naive
`datetime.utcnow()` while every other new site — `models._now`, `_claim_batch`,
`_finish`, and the dispatcher's `datetime.now(timezone.utc)` — is aware, and the
migration declares `TIMESTAMP` (without time zone) for `created_at`,
`next_attempt_at` and `updated_at` while the model declares
`DateTime(timezone=True)` for all six datetime columns (R3, R40).
What breaks in production: `_claim_batch` compares an aware `now` against a
column that the migration created without a zone, so on any deployment whose
session `TimeZone` is not UTC the comparison shifts by the offset and deliveries
are either claimed early or held back by hours; and `WebhookDelivery.to_dict`
returns `next_attempt_at.isoformat()` with no offset suffix, so API consumers
cannot tell which zone the timestamp is in.
Fix: change `enqueue_for_event` to `next_attempt_at=datetime.now(timezone.utc)`
(the module already imports `timezone`) and change all four migration columns to
`TIMESTAMPTZ`, including the `DEFAULT now()` ones. Preserve the behaviour:
`next_attempt_at` must still be "immediately eligible", so the value stays
"now", not "now plus a delay". Boundary and tie: a delivery whose
`next_attempt_at` is exactly equal to `now` is claimed (`<=`, as written) — say
so explicitly, and note that `enqueue_for_event` gives every row in one batch an
identical `next_attempt_at`, so `ORDER BY next_attempt_at` alone is not a total
order (R57) and must be `ORDER BY next_attempt_at, id` for a deterministic
batch. Red-prove with three separate executed mutations: (i) restore
`datetime.utcnow()` and observe a test that sets the session time zone to a
non-UTC value, enqueues, and asserts the row is claimable go red; (ii) revert
one column to bare `TIMESTAMP` and observe a schema test asserting every
datetime column reports `timestamp with time zone` go red; (iii) drop the `, id`
tie-break and observe a test that enqueues 150 identically-timed rows and
asserts two successive `_claim_batch` calls return disjoint id sets go red. A
naive datetime reaching the model must raise rather than being coerced — add an
assertion in `_now`'s callers so "no zone information" is not spelled the same
as "UTC".

---

### Major: `webhooks_enabled` is added to `organizations` but nothing reads it
File: `migrations/0042_webhook_delivery.sql` — `ALTER TABLE organizations ADD COLUMN webhooks_enabled BOOLEAN NOT NULL DEFAULT FALSE;`
What is wrong: the column is created but no code in the change consults it —
`enqueue_for_event` filters endpoints on `m.WebhookEndpoint.active.is_(True)`
only, and neither the routes nor the dispatcher references the flag (R41,
declared capability with no backing path).
What breaks in production: the flag defaults to `FALSE`, so an operator reading
the schema will believe outbound webhooks are off for every organization while
deliveries are in fact being sent for all of them — and flipping it during an
incident to stop deliveries will do nothing.
Fix: either wire it — add
`.join(Organization, Organization.id == m.WebhookEndpoint.org_id).filter(Organization.webhooks_enabled.is_(True))`
to `enqueue_for_event`'s endpoint query, and set the column `DEFAULT TRUE` (or
backfill existing rows to `TRUE`) so the migration does not silently disable a
shipping feature — or drop the column from this migration entirely. Preserve the
behaviour: whichever branch is taken, an endpoint that is `active` in an
org where webhooks are enabled must still receive deliveries. Boundary and tie:
state which flag wins when `Organization.webhooks_enabled` is true and
`WebhookEndpoint.active` is false (endpoint-level must be the narrower one), and
that toggling the org flag off does not cancel already-enqueued `pending` rows —
say whether that is intended. Red-prove with two separate executed mutations
(if wiring): (i) remove the org-level predicate and observe a test that disables
the flag and asserts zero delivery rows go red; (ii) leave the default at
`FALSE` and observe a test that enqueues for a pre-existing org and asserts one
delivery row go red (the allow side, which is what catches the silent
feature-disable).

---

### Major: the new production symbols have no tests, and the tests present cannot fail for the reasons they claim
File: `tests/webhooks/test_delivery.py` — imports `MAX_ATTEMPTS, backoff_for, send_once` only
What is wrong: the diff adds `enqueue_for_event`, `_acquire_lock`,
`_claim_batch`, `_finish`, `deliver`, `run_worker`, three HTTP routes and two
ORM models, none of which appears in any test (RT6); and of the tests present,
`test_verify_accepts_signature_produced_by_sign` calls `sign` on both sides so
it stays green for any MAC function including a constant one (RT1/RT5), while
`test_send_once_posts_the_signed_payload` captures both `captured["body"]` and
the signature header but never checks that one verifies the other — the single
assertion that would have caught the serialize-vs-wire divergence above.
What breaks in production: every Critical in this review is invisible to a green
suite, so the divergences ship and are discovered by customers rejecting
signatures.
Fix: add, in this PR, (a) a round-trip test that feeds the *captured request
bytes* and the *captured timestamp header* from the `MockTransport` handler into
`signing.verify` and asserts `True` — this is the test that reaches the real
production primitive rather than re-invoking `sign` (RT5); (b) an integration
test for `deliver` against a real session and a `MockTransport` covering the
2xx, 5xx-retry, 4xx-permanent and connection-error paths, asserting the final
`webhook_deliveries.status` and `attempts` values, not just that no exception
was raised; (c) route tests for all three endpoints asserting both the allow
case (own org, correct body) and the deny case (foreign `endpoint_id` → 404
*and* zero rows returned, asserting the mutation/read did not happen, not only
the status — RT8). Preserve the existing tests: keep
`test_backoff_grows_exponentially`, `test_max_attempts_matches_documented_limit`
and `test_send_once_propagates_connection_errors`, adjusting the backoff bounds
for jitter rather than deleting them. Boundary and tie: state that the
round-trip test must construct the expected digest independently of
`signing.sign` (a literal HMAC computed in the test body) so the test cannot be
satisfied by the implementation it is checking. Red-prove each added assertion
separately by execution: corrupt one byte of the captured body and see (a) red;
return 404 from the handler and see the permanent-failure assertion in (b) red;
delete the `org_id` filter and see the deny case in (c) red — three mutations,
three different assertions. Note also that `FakeEndpoint`/`FakeDelivery` are
plain classes with no session, so they cannot exhibit the detached-instance
defect at all; the new tests in (b) and (c) must use real persisted rows.

---

### Major: `limit` is bounded below but not above
File: `app/api/routes/settings.py` — `list_deliveries`, `limit: int = Query(50, ge=1)`
What is wrong: the author validated one side of the range (`ge=1`) and left the
upper side open, so any integer is accepted and passed straight to `.limit()`.
What breaks in production: a single request with `limit=100000000` materialises
every delivery row for that endpoint — each carrying an unbounded
`response_body` — into the process, exhausting memory and taking the API down
for all tenants.
Fix: `limit: int = Query(50, ge=1, le=200)` and add keyset pagination
(`before_id: int | None`) so callers can still reach older rows. Preserve the
feature: the default of 50 must not change and callers asking for the current
maximum must still succeed — do not fix this by capping silently at 50, which
would break any client already asking for more. Boundary and tie: `limit=200` is
accepted and `limit=201` is a 422; state that ties on `created_at` (a whole
enqueued batch shares one timestamp) make `ORDER BY created_at DESC` alone a
non-total order, so the order must be `created_at DESC, id DESC` and the cursor
must carry both (R57). Red-prove with three separate executed mutations: (i)
remove `le=200` and observe a test asserting `limit=201` returns 422 go red; (ii)
change `le` to 49 and observe a test asserting the default 50 still returns 50
rows go red (the allow side); (iii) drop the `id` tie-break and observe a test
that inserts 300 identically-timed rows and asserts two pages are disjoint go
red.

---

### Minor: `event_types` is accepted as arbitrary free text
File: `app/api/routes/settings.py` — `EndpointIn.event_types: list[str] = []`
What is wrong: the field is typed `list[str]` with no membership check against
the set of event types the product emits, and the value is stored straight into
JSONB and later compared in `enqueue_for_event`'s
`event_type in endpoint.event_types`.
What breaks in production: a customer who misspells `invoice.payed` receives no
deliveries and gets no error at registration time, and the endpoint appears
healthy in the settings list.
Fix: validate against the emitted set — since the diff does not show the
authoritative registry of event types (only `SUBSCRIBERS` is referenced, whose
contents are outside the change), the question to answer is whether such a
registry exists; if it does, constrain the field to an `Enum`/`Literal` derived
from it and return 422 listing the unknown values, with a test asserting a known
value is still accepted unchanged.

---

### Minor: DB work runs synchronously inside `async def`
File: `app/webhooks/delivery.py` — `enqueue_for_event`, `_claim_batch` (both `async def`, neither contains an `await`)
What is wrong: both coroutines perform blocking SQLAlchemy calls with no `await`,
so they hold the event loop for the duration of the query.
What breaks in production: under load the claim query's latency is added to every
concurrent delivery's timeline, though the effect is much smaller than the
`time.sleep` above.
Fix: either use an async SQLAlchemy session, or wrap the bodies in
`await asyncio.to_thread(...)`, or make them plain `def` and call them via
`to_thread` from `run_worker` — the choice depends on whether `app.db` exposes an
async session factory, which the change does not show.

---

### Minor: `_claim_batch`'s index does not cover its predicate
File: `migrations/0042_webhook_delivery.sql` — `CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries (status)`
What is wrong: the only index is on `status` alone, while `_claim_batch` filters
`status = 'pending' AND next_attempt_at <= now` and orders by `next_attempt_at`.
What breaks in production: as the delivered/failed backlog grows the poll query
sorts an increasingly large `pending` slice on every one-second tick.
Fix: `CREATE INDEX idx_webhook_deliveries_due ON webhook_deliveries (status, next_attempt_at, id);`
matching the ordering the claim query should use.

---

### Minor: `signing.verify` has no production caller
File: `app/webhooks/signing.py` — `verify`
What is wrong: `verify` is exercised only by `tests/webhooks/test_delivery.py`;
no production module in the diff imports it, and `docs/webhooks.md` describes the
verification recipe in prose rather than pointing at this function.
What breaks in production: nothing directly, but it means the constant-time and
replay-window defects above were never on a path anyone runs — the function is
the customer-facing reference implementation with no test that treats it as one.
Fix: either publish it as the documented reference (and then the Critical fixes
above are mandatory), or delete it — but not before the round-trip test in the
testing finding adopts it as the verifier, which is what makes it load-bearing.

---

## Cross-cutting verification

- **Tenancy filter**: present in `list_webhook_endpoints`
  (`org_id == user.org_id`) and correctly set on insert in
  `create_webhook_endpoint`; absent in `list_deliveries` — the only miss, and it
  is the security-relevant one.
- **Status spelling**: `"failed_permanent"` in `app/webhooks/delivery.py::_finish`
  call and in `app/webhooks/models.py::STATUSES`; `'failed'` in the migration
  CHECK — one of three sites drifted.
- **Datetime awareness**: `datetime.now(timezone.utc)` in
  `app/events/dispatcher.py`, `models._now`, `_claim_batch`, `_finish`;
  `datetime.utcnow()` only in `enqueue_for_event` — one of five sites drifted.
- **Column time zone**: `DateTime(timezone=True)` on all six model columns;
  bare `TIMESTAMP` on all four migration columns — the drift is systematic, not
  a single column.
- **Serialization helper**: `signing.serialize()` exists and is used by `sign`
  but bypassed by `send_once`'s `json=` kwarg — the change already contains the
  helper the wire path reimplements (R1).
- **Constant-time comparison**: `verify` is the only credential comparison added;
  no other `==` on a secret-shaped value appears in the diff.
- **Range validation**: `Query(50, ge=1)` is the only numeric bound added and it
  is one-sided; no other new route takes a numeric parameter.
- **Rate limiting (question, not an assertion)**: none of the three new routes
  carries a limiter in the diff, and `create_webhook_endpoint` mints a secret and
  writes a row per call. The change does not show the app's middleware stack, so
  this is a question rather than a finding: is a global limiter applied at the
  router or ASGI layer, and does it cover `POST /v1/settings/webhook-endpoints`?
  If yes, this closes; if no, the route needs a per-org limit plus a cap on
  endpoints per org, since each endpoint multiplies outbound requests per event.
