#!/usr/bin/env bats
# Tests for the batching ceiling in evals/rule-precision/request-batching/gate_b0.py
#
# Gate B0 refutes when the upper end falls below the bar, so the rule that most
# needs pinning is the one that makes the figure SMALLER: moving a fetch earlier
# puts it in the context sooner, and every surviving request in between re-sends
# it. A "saving" that counts only the vanished requests is not a saving, and on
# some agents batching costs more than it removes.
#
# No transcript is read: every fixture is built in the test.

bats_require_minimum_version 1.5.0

GATEB0="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/request-batching/gate_b0.py"

# Run a python snippet with gate_b0 loaded as `m`, and a fixture builder in scope.
b0() {
  { printf '%s\n' \
      'import collections, importlib.util' \
      "spec = importlib.util.spec_from_file_location('gate_b0', '$GATEB0')" \
      'm = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)' \
      'U = {"input_tokens": 0, "cache_read_input_tokens": 1000,' \
      '     "cache_creation_input_tokens": 0, "output_tokens": 0}' \
      '# scoped: [(bytes, request)]. extra: requests ingesting something else too.' \
      '# out: {request: output tokens}. busy: requests whose RESPONSE also did work' \
      '# that is not a catalogue fetch, so that output relocates rather than vanishes.' \
      'def fixture(n_req, scoped, extra=(), out=(), busy=()):' \
      '    usages = [dict(U, output_tokens=dict(out).get(r, 0)) for r in range(n_req)]' \
      '    hits = {"S": list(scoped)}' \
      '    n_scoped = {"S": collections.Counter(r for _b, r in scoped)}' \
      '    n_results = collections.Counter(n_scoped["S"])' \
      '    for r in extra:' \
      '        n_results[r] += 1' \
      '    resp = {r: ((2, collections.Counter({"S": 1})) if r in busy' \
      '                else (1, collections.Counter({"S": 1}))) for r in range(n_req)}' \
      '    return usages, hits, n_results, n_scoped, resp'
    cat; } | python3 -
}

@test "a request whose every result is in scope disappears; the host stays" {
  # Two catalogue fetches, in requests 1 and 2, and the diff in request 3. The
  # batch lands where the first result arrived, so request 1 hosts it and
  # request 2 has nothing left to do.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 1), (400, 2)], extra=[3])
print(m.batch_plan(u, h, nr, ns, "S"))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(1, frozenset({2}))" ]]
}

@test "a request that also ingests the diff survives its catalogue result moving" {
  # Nothing about the catalogue can delete a round trip the reviewer still needs
  # for the change - the same rule Gate 0 and Gate 1 use.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 1), (400, 2)], extra=[2, 3])
print(m.batch_plan(u, h, nr, ns, "S"))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(1, frozenset())" ]]
}

@test "moving a fetch earlier is charged to every surviving request in between" {
  # 400 bytes at 4.0 B/tok is 100 tokens. Request 2 disappears (trip 1000); the
  # result it carried is now in the context from request 1, so request 1 re-sends
  # it once - 100 tokens back. A trip-only figure would report 1000.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 1), (400, 2)], extra=[3])
trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
print(f"{trip:.0f} {pen:.0f} {trip - pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1000 100 900" ]]
}

@test "the penalty skips the requests that disappeared, which the trip already paid for" {
  # A fetch at request 4 crosses requests 1, 2 and 3 on its way to the host.
  # Request 2 is eliminated and its whole cost is already in the trip term, so
  # charging the moved bytes to it as well would count them twice.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(6, [(400, 1), (400, 2), (400, 4)], extra=[3])
trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
# request 2 and 4 go; the fetch from 4 is re-sent by surviving 1 and 3 only
print(sorted(m.batch_plan(u, h, nr, ns, "S")[1]), f"{pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[2, 4] 300" ]]
}

@test "batching can cost more than it saves, and the figure must be able to say so" {
  # One catalogue fetch shares its request with the diff, another arrives later
  # in a request that also carries the diff. Nothing disappears, so the whole
  # effect is the early carry - a negative saving. A formula that clamps at zero
  # would hide the case the intervention has to answer for.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 1), (400, 3)], extra=[1, 3])
trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
print(f"{trip:.0f} {pen:.0f} {trip - pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "0 200 -200" ]]
}

@test "an agent whose catalogue already lands in one request saves nothing" {
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 2), (900, 2)], extra=[2])
trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
print(f"{trip:.0f} {pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "0 0" ]]
}

@test "a result no request ever ingested is neither saved nor charged" {
  # A tool call made by the final turn lands past the end of the transcript. It
  # costs nothing today, so batching cannot save on it - and charging it an early
  # carry would invent a cost that was never paid.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(4, [(400, 1), (400, 4)], extra=[2])
print(m.in_scope(h, "S", len(u)))
trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
print(f"{trip:.0f} {pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[(400, 1)]" ]]
  [[ "${lines[1]}" == "0 0" ]]
}

@test "the batch rides in a request that survives anyway, so none is kept to host it" {
  # Requests 2 and 3 ingest nothing but catalogue; request 1 ingests something
  # else. Issuing the fetches in the turn that produced request 1 costs an extra
  # request of early carry and removes BOTH catalogue-only requests. Keeping one
  # alive to host the batch - what the protocol first registered - is not the
  # maximum, so it was not a ceiling.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 2), (400, 3)], extra=[1])
print(m.batch_plan(u, h, nr, ns, "S"))
print(m.batch_plan(u, h, nr, ns, "S", colocate=False))
PY
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "(1, frozenset({2, 3}))" ]]
  [[ "${lines[1]}" == "(2, frozenset({3}))" ]]
}

@test "with no earlier request to ride in, the first catalogue arrival hosts the batch" {
  # The first request ingests nothing - results are attributed to the request
  # AFTER the one that asked - so it cannot be where the batch lands, and one
  # catalogue-only request has to stay alive to hold it.
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(4, [(400, 1), (400, 2)])
print(m.batch_plan(u, h, nr, ns, "S"))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(1, frozenset({2}))" ]]
}

@test "a removed request keeps its output when its response did other work" {
  # 143 of this corpus's removable requests emit the review `Write`. That work
  # does not disappear because the fetch beside it moved into the batch - it
  # relocates, and relocated output costs what it cost. Crediting it as saved was
  # worth 4.45% of the round, which is more than the distance to the bar.
  run b0 <<'PY'
free = fixture(5, [(400, 1), (400, 2)], extra=[3], out={2: 500})
busy = fixture(5, [(400, 1), (400, 2)], extra=[3], out={2: 500}, busy=[2])
for u, h, nr, ns, rp in (free, busy):
    trip, pen = m.saving(u, h, nr, ns, rp, "S", 4.0)
    print(f"{trip:.0f} {pen:.0f} {trip - pen:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "1500 100 1400" ]]
  [[ "${lines[1]}" == "1000 100 900" ]]
}

@test "a response that issued no catalogue fetch at all keeps its output" {
  run b0 <<'PY'
u, h, nr, ns, rp = fixture(5, [(400, 1), (400, 2)], extra=[3], out={2: 500}, busy=[2])
print(m.keeps_its_output(rp, 1, "S"), m.keeps_its_output(rp, 2, "S"))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "True False" ]]
}

@test "the closed form equals the total rebuilt from the definition" {
  # The formula is the thing that is easy to get subtly wrong; rebuilding each
  # surviving request's cost is the thing that is slow. They must agree.
  run b0 <<'PY'
cases = [(6, [(400, 1), (400, 2), (400, 4)], [3], {2: 300, 4: 900}, [4]),
         (5, [(400, 1), (400, 3)], [1, 3], {1: 250}, [1, 3]),
         (7, [(1200, 2), (300, 5), (900, 6)], [4, 6], {5: 700, 6: 400}, [5]),
         (4, [(500, 1)], [2, 3], {}, [])]
for n_req, scoped, extra, out, busy in cases:
    u, h, nr, ns, rp = fixture(n_req, scoped, extra, out, busy)
    for bpt in (3.5, 3.8, 4.2):
        trip, pen = m.saving(u, h, nr, ns, rp, "S", bpt)
        rebuilt = m.saving_reconstructed(u, h, nr, ns, rp, "S", bpt)
        assert abs((trip - pen) - rebuilt) < 1e-9, (n_req, bpt, trip - pen, rebuilt)
print("agree")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "agree" ]]
}
