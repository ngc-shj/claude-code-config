# Review — F10-webhooks.diff

Routing: digest read whole (`## END-OF-DIGEST` confirmed). Rows extracted by anchored `rg`
for R1, R2, R3, R4, R5, R9, R11, R12, R29, R38, R40, R41, R55, R57, RS1, RS2, RS3, RS4,
RT1, RT5, RT6, RT7, RT8; detail pages read for R1, R38, R40, RS3, RT1, RT5. Finding Floor
and Remedy Floor extracted once. Full `common-rules.md` was not read — targeted extraction
was conclusive.

---

### Critical: delivery history is readable across organizations
File: `app/api/routes/settings.py` — `list_deliveries`
What is wrong: the query filters only on `WebhookDelivery.endpoint_id` and never joins to
`WebhookEndpoint.org_id == user.org_id`, while its two sibling handlers added in the same
hunk (`create_webhook_endpoint`, `list_webhook_endpoints`) both scope on `user.org_id`.
What breaks in production: any authenticated customer can enumerate integer endpoint ids and
read another tenant's delivery rows, whose `to_dict()` exposes `event_id`, `event_type` and
`response_status` for that tenant's invoice and subscription events.
Fix: join the delivery query to the endpoint table and filter on the caller's org in the same
statement — `session.query(m.WebhookDelivery).join(m.WebhookEndpoint, m.WebhookDelivery.endpoint_id == m.WebhookEndpoint.id).filter(m.WebhookEndpoint.id == endpoint_id, m.WebhookEndpoint.org_id == user.org_id)`
— and return `404` (not `403`) when the join is empty so the endpoint id is not an existence
oracle. Preserve what the route was for: the owning org must still receive its own rows —
pin that with a test that seeds two orgs, asserts org A's caller gets exactly its N rows
(allow side), and asserts org B's caller gets `404` **and** an empty body (deny side, RT8:
assert the rows, not only the status). Red-prove each clause separately: (i) delete the
`org_id` predicate → the cross-tenant test reds; (ii) delete the `endpoint_id` predicate →
the allow-side count assertion reds; (iii) change `404` to `403` → the status assertion reds.
Fail loudly rather than silently widening: if `user.org_id` is `None` the handler must raise
`HTTPException(500)` naming the missing tenant claim, never fall through to an unfiltered
query. Boundary: an endpoint id that exists but belongs to another org and an endpoint id
that does not exist must both take the `404` branch, and a delivery whose endpoint was
deleted (cascade) is out of the result set on both sides.

### Critical: the signing secret is returned by the list endpoint and written to the logs
File: `app/webhooks/models.py` — `WebhookEndpoint.to_dict`; `app/api/routes/settings.py` — `list_webhook_endpoints`; `app/webhooks/delivery.py` — `send_once`
What is wrong: `to_dict()` includes `"signing_secret"` and is reused verbatim by
`list_webhook_endpoints`, directly contradicting `docs/webhooks.md` ("the response is the only
place the signing secret appears — it cannot be read back afterwards"), and `send_once` logs
`headers=%s` at INFO, which contains `SIGNATURE_HEADER`.
What breaks in production: the shared secret that authenticates every outbound event is
retrievable forever by any principal who can call `GET /v1/settings/webhook-endpoints`, and
valid signatures are copied into the application log stream where they can be replayed by
anyone with log access.
Fix: make secret exposure opt-in at the single serialization point rather than at each caller
— change the signature to `to_dict(self, *, include_secret: bool = False)` and emit
`signing_secret` only when the flag is set; pass `include_secret=True` from
`create_webhook_endpoint` only. In `send_once`, log `endpoint.url` and the timestamp header
only, never the signature or the secret. Cross-cutting: `WebhookDelivery.to_dict` is the
other new serializer in this diff and must be checked the same way — it currently omits
`payload`, which is correct, and that omission must be asserted rather than left incidental.
Preserve the useful behaviour: the create response must still carry the secret exactly once
(allow side) — assert it in a test, or the fix degrades into "no one can ever get a secret".
Red-prove each clause separately: (i) flip the default to `True` → the list-endpoint test
asserting `"signing_secret" not in body[0]` reds; (ii) drop the `include_secret=True` at the
create call site → the create test asserting the secret is present reds; (iii) restore the
`headers=%s` log line → a `caplog` test asserting no record's message contains the secret or
the `sha256=` prefix reds. Fail loudly: `to_dict(include_secret=True)` on an instance whose
`signing_secret` is `None` must raise, not emit `null`, so a broken row is not mistaken for a
secretless endpoint. Boundary: an endpoint created and listed in the same request cycle must
still be secretless on the list path, and two endpoints sharing a URL are serialized
independently.

### Critical: signing secrets come from a non-cryptographic PRNG
File: `app/webhooks/signing.py` — `new_signing_secret`
What is wrong: the secret is built from `random.choice`, which is the Mersenne Twister PRNG
seeded from process state and fully recoverable from ~624 observed outputs, not from
`secrets`/`os.urandom`.
What breaks in production: an attacker who registers a handful of their own endpoints
observes enough generator output to reconstruct its state and then predicts other tenants'
signing secrets, letting them forge events that every customer's receiver accepts as
authentic.
Fix: replace the body with `return SECRET_PREFIX + secrets.token_urlsafe(SECRET_BYTES)`,
import `secrets`, and delete the `random`, `string` and `_ALPHABET` imports outright rather
than leaving them unreferenced (R1 clause (d) — no dead duplicate of the old mechanism).
Rename `SECRET_BYTES` to mean what it says: it currently indexes a character count, and the
existing test `len(secret) == len(SECRET_PREFIX) + SECRET_BYTES` will red once the value is a
byte count — update that assertion to `>= len(SECRET_PREFIX) + 32` rather than deleting it
(Remedy Floor clause 4: the length property is what made the misnomer visible, keep it).
Preserve the allow side: the prefix contract survives — assert `startswith(SECRET_PREFIX)`
and that `verify()` still accepts a signature made with a freshly generated secret.
Red-prove each clause separately: (i) revert to `random.choice` under a fixed `random.seed(0)`
→ a test asserting two secrets generated after identical seeding differ reds; (ii) drop the
prefix → the prefix assertion reds; (iii) shorten to 8 bytes → the length assertion reds.
Fail loudly: if `secrets.token_urlsafe` raises (no entropy source), let it propagate — endpoint
creation must fail with a 5xx that names the entropy failure, never fall back to `random`.
Boundary: a secret of exactly the minimum length is accepted; one byte shorter is rejected.

### Critical: signature verification uses a variable-time comparison
File: `app/webhooks/signing.py` — `verify`, `return expected == signature`
What is wrong: the recomputed digest is compared with `==`, which short-circuits on the first
differing byte, instead of `hmac.compare_digest` (RS1).
What breaks in production: this is the reference verifier the product ships and the one its own
tests exercise; a caller using it to authenticate inbound replays leaks the digest byte by byte
under timing measurement, and `verify` also crashes on a `None` signature rather than returning
`False`.
Fix: `return hmac.compare_digest(expected, signature or "")` — the `or ""` makes a missing or
`None` header a clean deny instead of a `TypeError`. Preserve the allow side: a signature
produced by `sign` with the matching secret must still return `True`, asserted in a test that
survives the change. Red-prove each clause separately: (i) restore `==` → a test that patches
`hmac.compare_digest` with a spy and asserts it was called reds; (ii) remove the `or ""` →
`verify(SECRET, {"a": 1}, None)` raising instead of returning `False` reds; (iii) compare
against `sign(other_secret, ...)` → the negative test reds. Fail loudly for the case that is
neither pass nor fail: a `secret` of `None` or `""` must raise rather than compute an HMAC
under an empty key that then compares equal for anyone who guesses the empty secret. Boundary:
a signature equal to `expected` except for the `sha256=` prefix casing must deny, and two
distinct payloads that hash equal cannot occur — state that the comparison is on the full
64-hex digest, not a prefix.

### Critical: the signature covers neither the timestamp nor the bytes actually sent
File: `app/webhooks/signing.py` — `sign`; `app/webhooks/delivery.py` — `send_once`
What is wrong: `sign` MACs only `json.dumps(payload, sort_keys=True)`, whereas
`docs/webhooks.md` states the signature is the HMAC of `"{timestamp}.{raw_request_body}"` —
and `send_once` transmits the body via `client.post(..., json=delivery.payload)`, which httpx
serializes with its own separators and insertion order, so the signed bytes are not the sent
bytes (R40: producer wire shape vs the consumer's documented contract; R29: the doc claim is
false about the code it describes).
What breaks in production: every receiver implemented from the published documentation computes
a different MAC and rejects 100% of deliveries, and because the timestamp is unsigned an
attacker who captures one request can rewrite `X-Acme-Timestamp` to defeat the five-minute
replay window the docs tell customers to rely on.
Fix: make one function own the bytes. Change `sign` to
`def sign(secret, body: bytes) -> tuple[str, str]` computing
`hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256)`, and change
`send_once` to serialize once — `body = serialize(delivery.payload).encode()` — passing
`content=body` to `client.post` with an explicit `Content-Type: application/json` header, so
the signed bytes and the transmitted bytes are the same object. Update `verify` to the same
`(secret, body: bytes, timestamp: str, signature: str)` shape and have it reject a timestamp
more than 300 seconds from now, since the docs promise that window and nothing in the change
implements it. Delete `sign(secret, payload: dict)` rather than keeping it as a wrapper (R1
clause (d)) — it is the thing that makes the divergence possible. Preserve the allow side and
prove it the way R40 requires: a round-trip test that feeds the ACTUAL `httpx` request
captured by `MockTransport` (`request.content`, `request.headers`) into the ACTUAL `verify`
and asserts `True`; the existing `test_send_once_posts_the_signed_payload` must be extended to
this, not replaced by two independently mocked shapes. Red-prove each clause separately:
(i) drop the `f"{timestamp}."` prefix → the round-trip test still passes but a new test that
verifies a captured request against a mutated `X-Acme-Timestamp` stops reding, so assert that
mutation reds; (ii) revert `content=body` to `json=payload` → the round-trip verify reds on the
first payload whose key order differs from sorted order (use `{"b": 2, "a": 1}` — a payload
already in the suite); (iii) set the skew window to `None` → the stale-timestamp test reds.
Fail loudly: a payload that is not JSON-serializable must raise at `serialize` before any
request is made, never be sent unsigned. Boundary: a timestamp exactly 300 seconds old is
accepted and 301 is rejected — state the side, and state that two requests sharing a timestamp
are independently valid because the body differs.

### Critical: the URL check accepts plaintext and internal destinations, and redirects are followed
File: `app/api/routes/settings.py` — `create_webhook_endpoint`, `parsed.scheme.startswith("http")`; `app/webhooks/delivery.py` — `httpx.AsyncClient(..., follow_redirects=True)`
What is wrong: `startswith("http")` admits `http://` (the docs say "Only `https://` URLs are
accepted") and any scheme merely prefixed with those four characters, there is no check on the
resolved host, and the delivery client follows redirects, so a validated public URL can bounce
the signed POST to `http://169.254.169.254/` or an RFC1918 address.
What breaks in production: a tenant registers an endpoint that turns the worker into a
server-side request forgery proxy against internal services and the cloud metadata endpoint,
and unmodified `http://` endpoints ship customer invoice payloads in cleartext.
Fix: replace the prefix test with an exact-set check, `if parsed.scheme != "https" or not
parsed.hostname: raise HTTPException(422, ...)`; reject a hostname that resolves to any
non-global address (`ipaddress.ip_address(...).is_private or .is_loopback or .is_link_local or
.is_reserved` over every A/AAAA record) and reject an explicit port outside `{443}` unless a
config allowlist says otherwise; set `follow_redirects=False` on the delivery client so a 3xx
becomes a delivery failure rather than a second, unvalidated request. Preserve the allow side:
a normal public `https://hooks.example.com/acme` endpoint must still register and still receive
a POST — the DNS check must not deny on a resolver timeout by accident. Red-prove each clause
separately: (i) restore `startswith("http")` → a test registering `http://…` and asserting 422
reds; (ii) remove the private-address check → a test registering a host resolving to `127.0.0.1`
and asserting 422 reds; (iii) restore `follow_redirects=True` → a `MockTransport` test asserting
a 302 to an internal host results in a failed delivery and no second request reds. Fail loudly
for the outcomes that are neither pass nor fail: DNS resolution failure, an unresolvable host,
or a resolver timeout must be a 422 that names "could not resolve", never a silent accept —
"examined nothing" must not be spelled like "found nothing". Boundary: a host resolving to both
a public and a private address is rejected (any-private denies), and re-resolution at delivery
time means the check is advisory — say so, and state that the delivery-time private-address
check is the enforcing one.

### Critical: the migration's status CHECK rejects the status the code writes
File: `migrations/0042_webhook_delivery.sql` — `CHECK (status IN ('pending', 'in_flight', 'delivered', 'failed'))`; `app/webhooks/models.py` — `STATUSES`; `app/webhooks/delivery.py` — `_finish(delivery.id, "failed_permanent", ...)`
What is wrong: the migration spells the terminal failure state `'failed'` while `STATUSES` and
the only production writer both spell it `'failed_permanent'` (R3: the same enum changed in one
place and not its other instances; R2: the literal is written in three files with no shared
source).
What breaks in production: the first delivery to exhaust `MAX_ATTEMPTS` raises an
`IntegrityError` inside `_finish`, so the row stays `in_flight` forever and the batch that
contained it dies — permanent failures are unrecordable and the queue leaks rows.
Fix: derive the constraint from one source. Change the migration to
`CHECK (status IN ('pending', 'in_flight', 'delivered', 'failed_permanent'))`, and stop
`delivery.py` writing bare literals — have `_finish` take a member of `m.STATUSES` and assert
`status in m.STATUSES` on entry, so a fourth spelling cannot be introduced without tripping.
Add a test that reads the four values out of `STATUSES` and asserts each one is accepted by an
`INSERT` against a real migrated database — a mocked session cannot see a CHECK constraint (RT5:
the test path must include the primitive being claimed). Preserve the allow side: `'delivered'`
and `'pending'` inserts must still succeed, asserted in the same test. Red-prove each clause
separately: (i) revert the migration to `'failed'` → the parametrized insert test reds on the
`failed_permanent` case only; (ii) add `"failed"` to `STATUSES` without touching the migration →
the same test reds on the new member, proving it is driven by the constant and not a hardcoded
list; (iii) pass `"bogus"` to `_finish` → the entry assertion reds. Fail loudly: `_finish` must
raise when `session.get` returns `None` (a delivery deleted mid-flight) instead of the current
`AttributeError` on `row.status`, and the raise must name the delivery id. Boundary: an existing
row already holding `'failed'` from a partially applied deploy — the migration must either be
unreleased (state it) or carry an `UPDATE ... SET status = 'failed_permanent' WHERE status =
'failed'` before the constraint is added, since adding the CHECK to a table containing `'failed'`
fails the whole transaction.

### Critical: the unique index on `event_id` allows only one endpoint per event
File: `migrations/0042_webhook_delivery.sql` — `CREATE UNIQUE INDEX idx_webhook_deliveries_event ON webhook_deliveries (event_id)`
What is wrong: the uniqueness is on `event_id` alone, but `enqueue_for_event` builds one
`WebhookDelivery` row per matching endpoint and calls `session.add_all(rows)` — the fan-out the
feature exists for.
What breaks in production: any organization with two subscribed endpoints gets a unique-violation
on `add_all`, which the dispatcher's bare `except Exception` swallows as a warning, so both
deliveries are silently dropped and the customer never learns an event was lost.
Fix: change the index to the pair that is actually unique —
`CREATE UNIQUE INDEX idx_webhook_deliveries_event ON webhook_deliveries (endpoint_id, event_id)`
— which keeps the idempotency the index was clearly for (one delivery per event per endpoint)
while permitting fan-out; add the matching `UniqueConstraint("endpoint_id", "event_id")` to
`WebhookDelivery` so SQLAlchemy and the schema agree. Preserve the property the original index
supplied: re-dispatching the same event must still not duplicate rows — assert that calling
`enqueue_for_event` twice for one `event_id` against one endpoint leaves exactly one row (allow
side is the fan-out; deny side is the replay). Red-prove each clause separately: (i) drop the
index entirely → the double-enqueue test reds with two rows; (ii) revert to `(event_id)` → a
test enqueueing one event against two endpoints and asserting two rows reds; (iii) remove the
model-side constraint → a test asserting `WebhookDelivery.__table_args__` names both columns
reds. Fail loudly: `enqueue_for_event` must use an explicit `ON CONFLICT DO NOTHING` and return
the count actually inserted, so a suppressed conflict is visible in the return value rather than
raising into a caller that logs and forgets. Boundary: two endpoints of the SAME org for one
event yields two rows; the same endpoint re-enqueued for one event yields one, and the second
call returns `0`, not `1`.

### Critical: the worker uses ORM instances after their session has closed
File: `app/webhooks/delivery.py` — `_claim_batch` (`return rows` inside `with session_scope()`), `deliver` (`endpoint = session.get(...)` then used outside the block)
What is wrong: both functions return or retain SQLAlchemy instances past the end of their
`session_scope()` block, and every later access — `delivery.attempts`, `delivery.id`,
`delivery.payload`, `endpoint.signing_secret`, `endpoint.url` — is a lazy load on a detached,
expired instance.
What breaks in production: the first iteration of `run_worker` raises `DetachedInstanceError`
inside `asyncio.gather`, which propagates out of the `try`, deletes the lock and re-enters the
loop, leaving every claimed row stuck in `in_flight` — the worker delivers nothing at all.
Fix: stop moving ORM objects across session boundaries — have `_claim_batch` return plain data
(`list[tuple[int, int, int, dict]]` of `(delivery_id, endpoint_id, attempts, payload)`) read
inside the session, and have `deliver` take that tuple plus an endpoint snapshot
(`url`, `signing_secret`) loaded in its own short session; this also removes the per-delivery
`session.get(WebhookEndpoint, ...)` round trip the current code does inside the delivery path.
Preserve the allow side: the happy path must still mark the row `delivered` with the real
response status — assert that against a real (SQLite or test-Postgres) session, since a mocked
session cannot exhibit detachment at all (RT5). Red-prove each clause separately: (i) return the
ORM rows from `_claim_batch` again → a test that closes the session and reads `.payload` reds
with `DetachedInstanceError`; (ii) drop the endpoint snapshot and re-read `endpoint.url` after
the block → the same test reds on the endpoint; (iii) return the tuple but with `attempts`
omitted → the retry-count assertion reds. Fail loudly: if `session.get(WebhookEndpoint, id)`
returns `None` (endpoint deleted between claim and send) the delivery must be finished as
`failed_permanent` with a detail naming the missing endpoint, not raise an `AttributeError` into
`gather`. Boundary: a batch of exactly `BATCH_SIZE` and a batch of zero both return a list, and
zero must not be spelled the same as an error.

### Critical: a blocking `time.sleep` inside an async coroutine stalls the event loop
File: `app/webhooks/delivery.py` — `deliver`, `time.sleep(delay)`
What is wrong: `deliver` is `async` and is run under `asyncio.gather`, but the retry backoff
calls the synchronous `time.sleep`, which blocks the entire event loop rather than yielding.
What breaks in production: one failing endpoint serializes the whole worker — with
`MAX_ATTEMPTS = 5` a single dead endpoint blocks for 2+4+8+16 = 30 s, a batch of a few such
endpoints exceeds the 60 s lock TTL, and a second worker then claims rows the first is still
sending, producing duplicate deliveries; any other coroutine sharing the loop (health checks,
the HTTP client's own timeouts) is frozen for the same window.
Fix: `await asyncio.sleep(delay)` — `asyncio` is already imported in this file — and stop
holding a delivery's retries inside one coroutine at all: on a retryable failure, write
`status = "pending"`, `attempts = attempt`, `next_attempt_at = now + backoff_for(attempt)` and
return, letting the next poll re-claim it. That removes the unbounded in-memory loop and makes
the persisted `next_attempt_at` column the code already declares actually load-bearing.
Preserve the behaviour the loop provided: a transient failure must still be retried up to
`MAX_ATTEMPTS` and must still terminate at `failed_permanent` — assert both, or the fix
degrades into "one attempt and give up". Red-prove each clause separately: (i) restore
`time.sleep` → a test that runs `deliver` concurrently with a sentinel coroutine and asserts
the sentinel advanced within the window reds; (ii) drop the `next_attempt_at` write → a test
asserting the row is not re-claimable before the backoff elapses reds; (iii) drop the
`attempts` write → the `failed_permanent`-after-5 test reds by looping forever, so bound it
with `pytest.mark.timeout` rather than letting it hang. Fail loudly: a `delay` that computes to
`inf` or overflows (see the `2**attempt` growth) must raise rather than schedule a delivery for
the heat death of the universe — cap `backoff_for` at a `MAX_BACKOFF` constant. Boundary:
`attempt == MAX_ATTEMPTS` is terminal and `attempt == MAX_ATTEMPTS - 1` schedules one more try;
a row whose `next_attempt_at` is exactly `now` is claimable (the existing `<=`), and two rows
sharing that instant are both claimed.

### Critical: the dispatch lock is not atomic and is released by whoever finishes first
File: `app/webhooks/delivery.py` — `_acquire_lock`, and `finally: await redis_client.delete(LOCK_KEY)` in `run_worker`
What is wrong: `_acquire_lock` does a `GET` then a separate `SET`/`EXPIRE`, so two workers that
both see the key absent both proceed, and the `finally` deletes the key unconditionally without
proving the deleting worker is the owner.
What breaks in production: with more than one worker replica — the reason the lock exists —
both claim overlapping batches and every customer endpoint receives duplicate charges/events;
worse, a worker whose lock already expired deletes the lock a *different* worker now holds,
collapsing mutual exclusion entirely.
Fix: make acquisition one atomic operation with a fenced token —
`token = secrets.token_hex(16)`, `acquired = await redis_client.set(LOCK_KEY, token, nx=True,
ex=LOCK_TTL_SECONDS)` — and release only via a Lua compare-and-delete
(`if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0
end`) passing the same token. Set `LOCK_TTL_SECONDS` from the worst-case batch duration once
the blocking sleep is removed, and renew it if a batch can outlive it. Preserve the allow side:
a single worker must still acquire, run, and release so the next poll acquires again — assert
that round trip, or a fix that always denies passes every other clause. Red-prove each clause
separately: (i) revert to `GET`-then-`SET` → a test running two `_acquire_lock` calls
concurrently against a fake redis and asserting exactly one `True` reds; (ii) drop `nx=True` →
the same test reds; (iii) replace the compare-and-delete with a plain `delete` → a test where
worker A's token has expired and worker B holds the lock, asserting A's release is a no-op,
reds. Fail loudly: a redis error in `_acquire_lock` must return `False` and log at ERROR — the
worker must idle rather than proceed unlocked, and the "redis unreachable" outcome must not be
spelled the same as "lock free". Boundary: a TTL that expires exactly as the batch completes —
state that the compare-and-delete makes that case a harmless no-op, and that two workers can
never both hold the token because `SET NX` decides the tie.

### Critical: no test exercises the relationship the signature scheme depends on
File: `tests/webhooks/test_delivery.py` — `test_verify_accepts_signature_produced_by_sign`, `test_send_once_posts_the_signed_payload`; `app/webhooks/signing.py` — `sign`/`verify`
What is wrong: `verify` is only ever tested against output that `sign` produced in the same
process, so the assertion compares two outputs of the same subject and is true under every
implementation including a `sign` that returns a constant (RT1 clauses (c) and (d): no
independently written expected value), and `test_send_once_posts_the_signed_payload` asserts
only that the signature header *starts with* `sha256=` — never that the transmitted body
verifies against it (RT5: the test's call path does not reach the primitive it names).
What breaks in production: this suite is green for a signing scheme that no external receiver
can verify (see the `sign`/`send_once` finding above), so the defect ships with the appearance
of coverage.
Fix: add one test whose expected value is written independently of `sign` —
`expected = hmac.new(SECRET.encode(), f"{ts}.".encode() + body, hashlib.sha256).hexdigest()`
computed in the test from a frozen timestamp and a literal body — and assert the header equals
`"sha256=" + expected` exactly (RT1 clause (e): compare the whole value, not a prefix). Add the
round-trip: capture `request.content` and `request.headers` from `MockTransport` and feed those
actual bytes through the actual `verify`. Choose fixture values away from defaults (RT1 clause
(f)): a non-empty payload with out-of-order keys, and a timestamp that is not `0`. Preserve the
allow side: the legitimate signature must still verify — that is the round-trip assertion
itself. Red-prove each clause separately: (i) make `sign` return a constant digest → the
independent-expected-value assertion reds while the current `verify`/`sign` pairing does not;
(ii) drop the timestamp from the MAC input → the round-trip verify of a request with a mutated
`X-Acme-Timestamp` reds; (iii) re-serialize the body with different separators before signing →
the round-trip verify reds. Fail loudly: the test must assert the transport handler was actually
invoked (`captured` non-empty) so a transport that never fires is not read as a pass. Boundary:
an empty payload `{}` still signs and verifies, and two payloads differing only in key order
produce the same signature only if the serializer is canonical — assert that, since the whole
scheme rests on it.

---

### Major: `in_flight` has no exit path, so a crashed batch is lost forever
File: `app/webhooks/delivery.py` — `_claim_batch` (`row.status = "in_flight"`), `_finish`, `_claim_batch`'s filter `status == "pending"`
What is wrong: rows enter `in_flight` at claim time and leave it only through `_finish`'s
success or permanent-failure paths, while `_claim_batch` selects only `pending` — so any
process crash, `SIGTERM`, unhandled exception in `gather`, or the `DetachedInstanceError` above
leaves rows in a state nothing ever re-selects (R38 failure mode 1: a transient state with no
failure-exit and no bounded timeout).
What breaks in production: a single worker restart silently strands every claimed delivery, and
because `list_deliveries` reports the row as `in_flight` rather than failed, neither the customer
nor an operator has any signal that the event will never arrive.
Fix: give the transient state a bounded lease and an automatic reclaim. Add
`claimed_at TIMESTAMPTZ` to `webhook_deliveries`, set it alongside `status = 'in_flight'`, and
change `_claim_batch`'s predicate to
`(status = 'pending' AND next_attempt_at <= now) OR (status = 'in_flight' AND claimed_at < now - CLAIM_LEASE)`,
with `CLAIM_LEASE` a module constant strictly greater than the request timeout plus one backoff.
Preserve the allow side: a delivery that is genuinely in flight within its lease must NOT be
re-claimed — assert that a row claimed 1 second ago is invisible to a second `_claim_batch`,
or the fix trades a stall for a duplicate-send storm. Red-prove each clause separately:
(i) remove the `claimed_at < now - CLAIM_LEASE` disjunct → a test that claims a batch, simulates
a crash, advances the clock past the lease and asserts re-claim reds; (ii) remove the
`claimed_at` write → the same test reds because the row is immediately re-claimable;
(iii) set `CLAIM_LEASE` to zero → the within-lease non-reclaim assertion reds. Fail loudly: a
row whose `attempts` already equals `MAX_ATTEMPTS` and is reclaimed must be finished
`failed_permanent` immediately with a detail naming "lease expired", not retried a sixth time.
Boundary: a row whose `claimed_at` is exactly `now - CLAIM_LEASE` is not yet reclaimable (strict
`<`) — state the side, and note that two workers racing on the reclaim are resolved by the same
`SET NX` dispatch lock, not by this predicate.

### Major: `run_worker` references `batch` outside the block that binds it, and one failure kills the batch
File: `app/webhooks/delivery.py` — `run_worker`, `if not batch:` after the `finally`
What is wrong: `batch` is assigned inside the `try`, so if `_claim_batch` raises the `finally`
runs, control reaches `if not batch:` with the name unbound and raises `NameError` (or reads a
stale batch from the previous iteration, which is worse); separately `asyncio.gather` without
`return_exceptions=True` propagates the first delivery's exception and abandons its siblings.
What breaks in production: one transient database error turns the worker loop into a tight
crash loop that reacquires and deletes the lock without doing any work, and one malformed
delivery cancels every other delivery in the same batch mid-flight.
Fix: initialize `batch: list = []` before the `try`, wrap the body in an `except Exception` that
logs at ERROR and continues after `await asyncio.sleep(poll_interval)`, and call
`asyncio.gather(*[...], return_exceptions=True)` then inspect the results, finishing each
exceptional delivery via `_finish(..., "failed_permanent" | retry, ...)` rather than discarding
it. Preserve the allow side: a batch in which every delivery succeeds must still complete
without sleeping (the current fast-path when `batch` is non-empty) — assert that, or the fix
adds a poll delay to the hot path. Red-prove each clause separately: (i) remove the
initialization and make `_claim_batch` raise → a test asserting the loop survives one iteration
reds with `NameError`; (ii) drop `return_exceptions=True` with one delivery raising → a test
asserting the other deliveries in the batch still reached `_finish` reds; (iii) drop the
result inspection → a test asserting the raising delivery's row is no longer `in_flight` reds.
Fail loudly: the `except Exception` must log the traceback at ERROR with the batch size, so
"claimed nothing" and "claim exploded" are distinguishable in the logs. Boundary: an empty
batch sleeps and a batch of one does not; a batch where every entry raised is treated as a
non-empty batch for sleep purposes.

### Major: naive `utcnow()` is written into a timezone-aware column that another query compares against an aware value
File: `app/webhooks/delivery.py` — `enqueue_for_event`, `next_attempt_at=datetime.utcnow()`; `app/webhooks/models.py` — `_now`
What is wrong: `models.py` already defines the shared `_now()` helper returning
`datetime.now(timezone.utc)` and uses it for every other timestamp default, but
`enqueue_for_event` hand-rolls a naive `datetime.utcnow()` for a column declared
`DateTime(timezone=True)`, while `_claim_batch` compares that column against an aware
`datetime.now(timezone.utc)` (R1: a shared helper reimplemented, with a behavioural difference
that is not accidental).
What breaks in production: depending on driver and dialect the naive value is either rejected,
compared as local time (shifting every delivery's eligibility by the server's UTC offset), or
silently coerced — so deliveries fire hours early or late, and in the offset-behind case
`_claim_batch` never selects them at all.
Fix: import and call `m._now()` in `enqueue_for_event`, delete the local `datetime.utcnow()`
call outright, and state the behavioural difference the adoption introduces (R1 clause (b)):
the value gains a `tzinfo` of UTC, which is what the column and the comparison already assume,
so no other call site moves. Cross-cutting: `_claim_batch`, `_finish` and `models._now` all
already use aware `now` — `enqueue_for_event` is the only divergent site in the diff, and the
search for others is this file plus `settings.py`, neither of which produces a second.
Preserve the allow side: a freshly enqueued delivery must be claimable on the very next poll —
assert that `_claim_batch` returns a row enqueued microseconds earlier, or the fix could
silently push everything one offset into the future. Red-prove each clause separately:
(i) revert to `datetime.utcnow()` → a test asserting `row.next_attempt_at.tzinfo is not None`
reds; (ii) change `_now()` to return local time → a test asserting the stored value equals a
`datetime.now(timezone.utc)` taken in the test within a tolerance reds; (iii) change
`_claim_batch`'s `now` to naive → the claim test reds with a naive/aware comparison
`TypeError`. Fail loudly: the comparison must raise rather than coerce — do not defend by
stripping tzinfo, which would hide the class. Boundary: a row whose `next_attempt_at` equals
`now` exactly is claimed (the existing `<=`), and two rows at the same instant are ordered by
the tie-break added in the ordering finding below.

### Major: the migration declares `TIMESTAMP` where the models declare `DateTime(timezone=True)`
File: `migrations/0042_webhook_delivery.sql` — `created_at`, `next_attempt_at`, `updated_at` on both tables; `app/webhooks/models.py` — the matching `Column(DateTime(timezone=True))`
What is wrong: every timestamp column in the migration is `TIMESTAMP` (i.e. `timestamp without
time zone`) while the ORM declares `timezone=True`, so SQLAlchemy hands the driver an aware
value that Postgres stores stripped of its offset and returns naive.
What breaks in production: `WebhookDelivery.to_dict()` calls `self.next_attempt_at.isoformat()`
and emits a timestamp with no offset, so the deliveries API tells customers a retry is scheduled
at a wall-clock time whose zone is unstated, and any future comparison against an aware value
raises.
Fix: change all six columns to `TIMESTAMPTZ NOT NULL DEFAULT now()` in the migration so the
schema matches the declared model, and add an assertion in the model-level test that
`WebhookDelivery.__table__.c.next_attempt_at.type.timezone is True`. Preserve the allow side:
`to_dict()` must still return a parseable ISO-8601 string — assert that
`datetime.fromisoformat(d["next_attempt_at"]).tzinfo is not None`. Red-prove each clause
separately: (i) revert one column to `TIMESTAMP` → a round-trip test that inserts an aware value
and asserts the read-back has `tzinfo` reds; (ii) drop the `timezone=True` on the model → the
`type.timezone` assertion reds; (iii) drop the `NOT NULL` on `next_attempt_at` → an insert
omitting it succeeds where the test expects a violation. Fail loudly: `to_dict()` must raise a
named error if `next_attempt_at` is `None` rather than crashing on `.isoformat()` of `None`,
since the column is `nullable=False` and a `None` there means the schema and model have drifted
again. Boundary: a value at exactly midnight UTC must serialize with `+00:00`, not bare, and two
rows written in the same transaction share `now()` — which is why the ordering finding below
needs a tie-break.

### Major: the dispatcher swallows enqueue failures, so events are silently un-delivered
File: `app/events/dispatcher.py` — `except Exception as exc: log.warning(...)` around `webhook_delivery.enqueue_for_event`
What is wrong: the enqueue runs after the event's transaction has already committed and every
failure — the unique-index violation above, a database blip, a serialization error — is caught
and downgraded to a warning with no persistence, no retry, and no signal on the returned
`event_id`.
What breaks in production: the event row exists and `dispatch` reports success while no delivery
row was ever created, so a paid invoice is recorded internally and never reaches the customer's
system, with the only trace a WARNING line nobody reads.
Fix: make the enqueue part of the same transaction as the event insert — move the
`enqueue_for_event` call inside the existing `with session_scope()` block and have it accept the
open session rather than opening its own, so an event and its deliveries commit or roll back
together (an outbox). If that coupling is unacceptable, the alternative is a durable outbox row
written in the same transaction and drained by the worker; do not keep a bare `except` that
converts data loss into a log line. Preserve what the current shape provides: a webhook problem
must not break in-process subscribers — keep the subscriber loop before the enqueue and keep
`dispatch` returning `event_id` on the happy path. Red-prove each clause separately: (i) make
`enqueue_for_event` raise → a test asserting the event row is absent afterwards reds under the
current code and passes under the fix; (ii) remove the enqueue call → a test asserting one
delivery row per active endpoint reds; (iii) make a subscriber raise → a test asserting the
event row still committed reds if the ordering is changed. Fail loudly: if the enqueue must stay
out of the transaction, the failure has to increment a named error counter and re-raise, so
"enqueued nothing" is not spelled like "enqueued zero endpoints". Boundary: an org with zero
active endpoints yields zero rows and is a success, distinct from an org whose enqueue failed —
the return value must let a caller tell those apart.

### Major: only three event types can ever reach a webhook, contradicting the documented contract
File: `app/events/dispatcher.py` — `WEBHOOK_EVENT_TYPES`; `docs/webhooks.md` — "An empty `event_types` subscribes the endpoint to every event type we emit"; `app/api/routes/settings.py` — `EndpointIn.event_types`
What is wrong: the enqueue is gated on a hardcoded three-member set in the dispatcher, while the
registration API accepts any strings at all and the documentation promises that an empty list
subscribes to everything emitted (R11: the emission group and the subscription group are
different sets used as one; R12: the enum has no single registry).
What breaks in production: a customer subscribes to an event type the product genuinely emits,
sees it accepted by the API and documented as supported, and never receives a single delivery —
with no error anywhere, because the gate is silent.
Fix: put the deliverable set in one place — export `WEBHOOK_EVENT_TYPES` from
`app/webhooks/models.py` next to `STATUSES`, import it in the dispatcher, and validate
`EndpointIn.event_types` against it at the schema boundary so an unsupported type is a `422` at
registration rather than silence at delivery. Preserve the documented behaviour: an empty
`event_types` must still fan out to every member of that set — assert it, or the validation
turns "subscribe to everything" into "subscribe to nothing". Red-prove each clause separately:
(i) remove one member from the shared set → a test asserting a delivery row for that type reds;
(ii) remove the registration-time validation → a test asserting `422` for
`{"event_types": ["not.a.real.event"]}` reds; (iii) change the empty-list branch to match
nothing → the fan-out test reds. Fail loudly: the dispatcher must log at ERROR when
`envelope.type` is absent from the set but a subscriber for it exists, so a type emitted but
never deliverable is visible rather than inferred. Boundary: an endpoint whose `event_types` is
`[]` and one whose `event_types` lists every member must receive identical deliveries — assert
that equivalence, and state that a type present in the set but with no subscriber yields zero
rows, not an error.

### Major: `webhooks_enabled` is added to the schema and read by nothing
File: `migrations/0042_webhook_delivery.sql` — `ALTER TABLE organizations ADD COLUMN webhooks_enabled BOOLEAN NOT NULL DEFAULT FALSE`
What is wrong: the migration introduces an org-level gate defaulting to `FALSE`, but no code in
the diff consults it — `create_webhook_endpoint` does not check it and `enqueue_for_event`
filters only on `WebhookEndpoint.active` (R41: a declared capability with no backing path).
What breaks in production: whoever operates this feature will believe webhooks are off for every
organization because the column says `FALSE`, while in fact every org that registers an endpoint
receives deliveries — a rollout control that exists in the schema and not in the runtime.
Fix: either wire it or drop it, and say which. To wire it: check
`organization.webhooks_enabled` in `create_webhook_endpoint` (return `403` with a message naming
the disabled feature) and join it into `enqueue_for_event`'s endpoint query
(`.join(Organization).filter(Organization.webhooks_enabled.is_(True))`). Preserve the allow
side: an org with the flag `TRUE` must still register endpoints and receive every delivery it
would have received before — assert that explicitly, since a fail-closed gate defaulting to
`FALSE` denies everyone until someone flips it, and the flip must be part of the rollout plan.
Red-prove each clause separately: (i) remove the registration check → a test asserting `403` for
a disabled org reds; (ii) remove the enqueue join → a test asserting zero delivery rows for a
disabled org's active endpoint reds; (iii) set the default to `TRUE` → a test asserting a
newly-created org is disabled reds. Fail loudly: an org row that cannot be loaded must deny
rather than default to enabled — "could not read the flag" is not "the flag is on". Boundary:
an org disabled *after* endpoints were registered — state whether in-flight deliveries drain or
stop, and assert the chosen answer.

### Major: the retry policy does not match the one the documentation publishes
File: `app/webhooks/delivery.py` — `deliver`, `backoff_for`; `docs/webhooks.md` — the Retries section
What is wrong: the docs say "a 4xx is permanent and we stop immediately" and "backoff is
exponential with jitter", but `deliver` retries every non-2xx status identically and
`backoff_for` returns a deterministic `2**attempt` with no jitter; additionally only
`httpx.HTTPError` is caught, so a `json` serialization error or a `ValueError` from
`send_once` escapes into `gather` (R29: a published rationale that the code contradicts).
What breaks in production: a customer endpoint returning `400` or `404` is hammered five times
per event, and because every delivery in a batch computes identical delays, a shared outage
produces synchronized retry waves that keep the endpoint down.
Fix: branch on the status class — `if 400 <= response.status_code < 500 and response.status_code
not in (408, 429): _finish(..., "failed_permanent", ...); return` — and add jitter to
`backoff_for` as `timedelta(seconds=min(MAX_BACKOFF, BASE_DELAY_SECONDS**attempt) * random.uniform(0.5, 1.5))`
(here `random` is acceptable: jitter is not a secret, unlike the secret-generation finding
above — name that distinction so the two uses are not conflated). Broaden the `except` to
`Exception` and finish the delivery rather than letting it escape. The existing
`test_backoff_grows_exponentially` asserts exact equality and will red once jitter is added —
change it to a bounds assertion rather than deleting it (Remedy Floor clause 4: the growth
property is the thing worth keeping). Preserve the allow side: `429` and `503` must still be
retried and a `2xx` must still finish `delivered` — assert both. Red-prove each clause
separately: (i) remove the 4xx branch → a test asserting a `400` produces exactly one attempt
reds; (ii) remove the `408, 429` exemption → a test asserting a `429` is retried reds;
(iii) remove the jitter → a test asserting two `backoff_for(2)` calls are not byte-identical
reds. Fail loudly: an unexpected exception class must be recorded in `response_body` with its
type name, so "unknown failure" is distinguishable from "endpoint returned an error".
Boundary: `399`/`400` and `499`/`500` — state that `400..499` except `408, 429` is permanent and
`>= 500` is retryable, and that a response with no status (connection error) takes the retryable
path.

### Major: the delivered payload carries no event identity, so the documented deduplication is impossible
File: `app/webhooks/delivery.py` — `send_once`, `client.post(endpoint.url, json=delivery.payload, ...)`; `docs/webhooks.md` — "delivery is at-least-once, so deduplicate on `event_id`"
What is wrong: the body sent is the bare `delivery.payload` — the raw event payload — while
`delivery.event_id` and `delivery.event_type` are stored on the row and never transmitted, in
either the body or a header.
What breaks in production: the docs instruct every customer to deduplicate on `event_id`, but no
receiver has an `event_id` to deduplicate on, so the at-least-once guarantee turns into
duplicate side effects (double-crediting an invoice) on every retry.
Fix: send an envelope rather than the raw payload —
`{"id": delivery.event_id, "type": delivery.event_type, "created_at": <iso>, "data":
delivery.payload}` — serialized by the single `serialize()` path introduced in the signing fix
so the signed bytes and the sent bytes remain identical, and add an `X-Acme-Event-Id` header for
receivers that dedupe before parsing. Preserve the allow side: the original payload must remain
reachable unchanged under `data` — assert `json.loads(body)["data"] == original_payload` so the
envelope is additive, not a rename that drops fields. Red-prove each clause separately:
(i) revert to `json=delivery.payload` → a test asserting `body["id"] == delivery.event_id` reds;
(ii) drop `data` and splat the payload at the top level → the `data` equality assertion reds and
a payload containing its own `id` key silently collides; (iii) drop the header → the header
assertion reds. Fail loudly: a `delivery.event_id` of `None` must raise before the request, not
send `"id": null` that every receiver dedupes to the same bucket. Boundary: two deliveries of
one event to two different endpoints share the `id` — that is intended and must be asserted, so
receivers are not told the id is globally unique per request.

### Major: none of the three new routes is rate limited
File: `app/api/routes/settings.py` — `create_webhook_endpoint`, `list_webhook_endpoints`, `list_deliveries`
What is wrong: three new authenticated endpoints are added with no limiter dependency, and
nothing in the diff caps how many `WebhookEndpoint` rows an org may create (RS2).
What breaks in production: a single API key can create unbounded endpoints, each of which
multiplies every subsequent event into another outbound request, turning the delivery worker
into an amplifier against third parties and against the database.
Fix: attach the project's existing limiter dependency to all three routes (the codebase already
has an `app/api/deps.py` supplying `current_user`, which is where a shared limiter dependency
belongs — check for one there before adding a new mechanism, R1), and add a hard cap in
`create_webhook_endpoint`: count the org's existing endpoints inside the same session and raise
`HTTPException(409, "endpoint limit reached")` past `MAX_ENDPOINTS_PER_ORG`. Preserve the allow
side: an org under the cap must still create successfully and a normal request rate must still
pass — assert a create at `MAX_ENDPOINTS_PER_ORG - 1` succeeds, or a fix that always denies
satisfies every other clause. Red-prove each clause separately: (i) remove the limiter dependency
from one route → a test asserting `429` after N+1 rapid calls to that route reds; (ii) remove the
cap → a test asserting `409` at the limit reds; (iii) make the count query org-blind → a test
where org B's endpoints do not consume org A's quota reds. Fail loudly: if the limiter backend
is unreachable the route must fail closed with `503`, never silently admit — "limiter down" is
not "under the limit". Boundary: the request that creates exactly the `MAX_ENDPOINTS_PER_ORG`-th
endpoint succeeds and the next fails; two concurrent creates at the boundary are resolved by
counting inside the transaction, not before it.

### Major: request parameters are accepted without bounds or domain validation
File: `app/api/routes/settings.py` — `limit: int = Query(50, ge=1)`, `EndpointIn.url: str`, `EndpointIn.event_types: list[str] = []`
What is wrong: `limit` has a lower bound and no upper bound, `url` is a bare `str` validated only
by the `startswith("http")` test in the handler body rather than at the schema, and
`event_types` accepts an unbounded list of arbitrary strings that is written straight into a
JSONB column (RS3: validation belongs at the schema level, not deep in business logic).
What breaks in production: `GET …/deliveries?limit=100000000` materializes the whole delivery
table into memory and takes the API process down, and an endpoint registered with a
multi-megabyte `event_types` array bloats every row and every enqueue-time membership test.
Fix: bound each at the schema — `limit: int = Query(50, ge=1, le=200)`; declare
`url: HttpUrl` (or `AnyHttpUrl` with an `https`-only validator) so the scheme and host checks are
schema-level rather than a handler-body prefix test; declare
`event_types: list[str] = Field(default_factory=list, max_length=50)` with each member
constrained to the shared `WEBHOOK_EVENT_TYPES` set from the finding above; add `max_length` to
the URL. Preserve the allow side: the default `limit=50` and a normal `https` URL with two event
types must still be accepted — assert each, or the tightening is unmeasured in the direction
that gets it reverted. Red-prove each clause separately: (i) remove `le=200` → a test asserting
`422` for `limit=100000` reds; (ii) revert `url` to `str` → a test asserting `422` for
`"not-a-url"` reds; (iii) remove `max_length` on `event_types` → a test asserting `422` for a
51-element list reds. Fail loudly: a body that fails validation must return `422` with the
offending field named, and the handler must not additionally re-validate silently — one refusal,
named. Boundary: `limit=200` is accepted and `limit=201` is `422`; a 50-element `event_types` is
accepted and 51 is not; state that `event_types=[]` is valid and means "all".

### Major: the full response body of every attempt is stored unbounded
File: `app/webhooks/delivery.py` — `_finish(delivery.id, "delivered", attempt, response.status_code, response.text)` and `detail = f"HTTP {response.status_code}: {response.text}"`; `app/webhooks/models.py` — `response_body = Column(Text)`
What is wrong: the entire response body from an arbitrary customer-controlled endpoint is written
to an unbounded `TEXT` column on every attempt, including on the success path.
What breaks in production: a customer endpoint returning a large HTML error page (or a
deliberately gigantic body) writes megabytes per delivery into the primary database, and any
sensitive content that endpoint returns is now retained in the vendor's storage indefinitely.
Fix: truncate at the single write point — add `MAX_RESPONSE_BODY = 2048`, and store
`(response.text or "")[:MAX_RESPONSE_BODY]`; stop reading the body at all on the 2xx path, where
it carries no diagnostic value, and cap the read itself so a multi-gigabyte body is never
materialized (`response.text` after an `httpx` `Limits`-bounded read). Preserve the diagnostic
value the field exists for: the first 2 KB of a failing response must still be stored and still
be visible to whoever debugs the endpoint — do not fix this by dropping the column. Red-prove
each clause separately: (i) remove the slice → a test asserting `len(row.response_body) <=
MAX_RESPONSE_BODY` for a 1 MB response reds; (ii) keep storing on the 2xx path → a test asserting
`response_body is None` after a success reds; (iii) set `MAX_RESPONSE_BODY` to `0` → a test
asserting the first 100 characters of a failure body are retained reds. Fail loudly: a body that
cannot be decoded must store a marker naming the decode failure, not an empty string that reads
like "the endpoint returned nothing". Boundary: a body of exactly `MAX_RESPONSE_BODY` bytes is
stored whole and one byte more is truncated — assert both sides.

### Major: `_claim_batch` and `list_deliveries` order on non-unique keys
File: `app/webhooks/delivery.py` — `.order_by(m.WebhookDelivery.next_attempt_at).limit(BATCH_SIZE)`; `app/api/routes/settings.py` — `.order_by(WebhookDelivery.created_at.desc()).limit(limit)`
What is wrong: both queries order on a wall-clock timestamp with no tie-break, and both are
combined with a `LIMIT` — `next_attempt_at` is set to the same instant for every row of one
enqueue fan-out, and `created_at` defaults to `now()` for every row of a batch insert, so ties
are the norm rather than the edge case (R57).
What breaks in production: the delivery queue's order among same-instant rows is undefined, so a
persistently-full queue can starve some rows indefinitely, and the deliveries API returns
different members of a tied group on repeated calls, which reads to a customer as deliveries
appearing and disappearing.
Fix: append the primary key as the tie-break in both queries —
`.order_by(m.WebhookDelivery.next_attempt_at, m.WebhookDelivery.id)` and
`.order_by(WebhookDelivery.created_at.desc(), WebhookDelivery.id.desc())` — since `id` is a
`BIGSERIAL` the caller cannot name, and add the composite index
`CREATE INDEX idx_webhook_deliveries_due ON webhook_deliveries (status, next_attempt_at, id)`,
which also fixes the missing `next_attempt_at` index (`idx_webhook_deliveries_status` alone
forces a sort over every pending row). Preserve the allow side: ordering by due time must still
dominate — a row due earlier must still be claimed before a row due later with a smaller `id`;
assert that, or the tie-break silently becomes the primary sort. Red-prove each clause
separately: (i) remove the `id` tie-break from `_claim_batch` → a test inserting `BATCH_SIZE + 1`
rows with identical `next_attempt_at` and asserting the same set is returned on two consecutive
calls reds; (ii) remove it from `list_deliveries` → the equivalent pagination-stability test
reds; (iii) reverse the primary sort → the due-time-dominates assertion reds. Fail loudly: a row
whose `next_attempt_at` is `NULL` cannot exist (the column is `NOT NULL`) — assert the constraint
rather than sorting `NULL`s into an arbitrary position. Boundary: two rows sharing
`next_attempt_at` are ordered by ascending `id`, and a page cut through a tied group resumes at
the next `id` rather than repeating the group.

### Major: the new production surface ships almost entirely untested
File: `tests/webhooks/test_delivery.py` — the whole file, against `app/webhooks/delivery.py` and `app/api/routes/settings.py`
What is wrong: the diff adds `enqueue_for_event`, `deliver`, `run_worker`, `_acquire_lock`,
`_claim_batch`, `_finish`, two ORM models with `to_dict`, and three HTTP routes, and the only
delivery-side test covers `send_once` through hand-written `FakeEndpoint`/`FakeDelivery` classes
that carry three attributes between them (RT6; RT1 — the doubles diverge from the real models,
which have `active`, `event_types`, `status`, `attempts` and `next_attempt_at`, and nothing
binds the fakes to the models' declared shape).
What breaks in production: every Critical above — the detached instances, the CHECK-constraint
mismatch, the unique-index fan-out failure, the cross-tenant read — is invisible to a green
suite, because no test ever constructs a real `WebhookDelivery`, opens a real session, or calls
a route.
Fix: replace `FakeEndpoint`/`FakeDelivery` with factory functions that build the real
`m.WebhookEndpoint` / `m.WebhookDelivery` instances against a migrated test database, so a field
added to a model or a constraint added to the migration is reachable from the tests (RT1 clause
(a): the shape is enforced by the type, not by a reader), and add at minimum: a route test per
new endpoint including the cross-tenant deny with the body asserted (RT8), an
`enqueue_for_event` test over two endpoints with disjoint `event_types`, a `_claim_batch`
concurrency test, and a `deliver` test that walks a failure to `failed_permanent` against the
real CHECK constraint. Preserve what the current tests do well: the signing tests exercise the
real `sign`/`verify` and must stay, extended per the RT1/RT5 finding above rather than replaced.
Red-prove each clause separately: (i) break `enqueue_for_event`'s `event_types` filter → the
disjoint-subscription test reds; (ii) revert the migration's CHECK to `'failed'` → the
`failed_permanent` test reds; (iii) drop the org filter from `list_deliveries` → the
cross-tenant test reds. Fail loudly: the suite must fail, not skip, when the test database is
unavailable — a skipped integration test reports the same green as a passing one, and that is
exactly how this gap survived. Boundary: an org with zero endpoints enqueues zero rows and is a
pass, distinct from an org whose enqueue raised.

---

### Minor: `STATUSES` is defined and never used
File: `app/webhooks/models.py` — `STATUSES`
What is wrong: the tuple naming the four legal statuses is exported but no code references it —
`WebhookDelivery.status` uses the raw literal `default="pending"` and `delivery.py` writes bare
strings.
What breaks in production: nothing directly, but it is the reason the migration's `'failed'` and
the code's `'failed_permanent'` could drift without anything noticing.

### Minor: `_finish` and `deliver` dereference rows that may be `None`
File: `app/webhooks/delivery.py` — `_finish` (`row = session.get(...)`, then `row.status = status`), `deliver` (`endpoint = session.get(...)`)
What is wrong: neither `session.get` result is checked, so a delivery or endpoint deleted between
claim and completion produces `AttributeError: 'NoneType' object has no attribute 'status'`.
What breaks in production: the `ON DELETE CASCADE` on `webhook_endpoints` makes this reachable —
deleting an endpoint mid-batch crashes the coroutine handling its delivery.

### Minor: deleting an endpoint destroys its delivery history
File: `migrations/0042_webhook_delivery.sql` — `endpoint_id BIGINT NOT NULL REFERENCES webhook_endpoints (id) ON DELETE CASCADE`
What is wrong: the cascade removes every `webhook_deliveries` row when an endpoint is deleted,
and the deliveries table is the only record that an event was ever attempted.
What breaks in production: a customer who removes and re-adds an endpoint loses the delivery
audit trail for that period, and no other table retains it.

### Minor: no route deactivates an endpoint or rotates its secret
File: `app/api/routes/settings.py` — the three new routes
What is wrong: `WebhookEndpoint.active` and `signing_secret` are both writable fields with no
API that writes them, so an endpoint can be created but never disabled or rotated.
What breaks in production: a customer whose signing secret leaks has no way to rotate it and no
way to stop deliveries short of a support request.

### Minor (question): is `SECRET_BYTES` meant to be a byte count?
File: `app/webhooks/signing.py` — `SECRET_BYTES = 32`, `random.choice(_ALPHABET) for _ in range(SECRET_BYTES)`
What is wrong: the constant is named for bytes but indexes a character count over a 62-symbol
alphabet, and `test_new_signing_secret_has_prefix_and_length` asserts the character reading, so
the misnomer is now pinned by a test.
What breaks in production: nothing at the current value (32 alphanumerics is ~190 bits), but the
next reader who "fixes" the units to match the name will change the secret length without
intending to. What would close this: a statement of which unit is intended, after which the
constant is renamed to match.
