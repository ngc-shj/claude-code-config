#!/usr/bin/env bats
# Tests for the compiled-packet witness in evals/rule-precision/packet-compiler/gate_c0.py
#
# C0 does not refute, so the risk it carries is the cheap one - continuing work
# that should have stopped. The rules pinned here are the ones that could inflate
# the figure: crediting the digest in requests that no longer happen, eliminating
# the request the packet is delivered to, and letting the packet arrive after the
# reviewer used it. The command-payload charge is pinned too, but as the
# CONSERVATIVE choice it is - the compiled form issues no such command, which is
# why this figure is a witness and not a ceiling.
#
# No transcript is read: every fixture is built in the test.

bats_require_minimum_version 1.5.0

GATEC0="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/packet-compiler/gate_c0.py"

c0() {
  { printf '%s\n' \
      'import collections, importlib.util' \
      "spec = importlib.util.spec_from_file_location('gate_c0', '$GATEC0')" \
      'm = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)' \
      'U = {"input_tokens": 0, "cache_read_input_tokens": 1000,' \
      '     "cache_creation_input_tokens": 0, "output_tokens": 0}' \
      '# packet/digest: [(result bytes, command bytes, request)].' \
      '# extra: requests that also ingest something the packet does not replace.' \
      'def fixture(n_req, packet, digest, extra=()):' \
      '    usages = [dict(U) for _ in range(n_req)]' \
      '    n_gone = collections.Counter(r for _b, _c, r in packet + digest)' \
      '    n_results = collections.Counter(n_gone)' \
      '    for r in extra:' \
      '        n_results[r] += 1' \
      '    resp = {r: (1, collections.Counter({m.b0.PRIMARY: 1})) for r in range(n_req)}' \
      '    return dict(usages=usages, packet=packet, digest=digest,' \
      '                n_results=n_results, n_gone=n_gone, resp=resp)'
    cat; } | python3 -
}

@test "the request the packet is delivered to survives; the rest go" {
  # The digest arrived at request 1 and the packet takes its place there, so
  # request 1 stays. Requests 2 and 3 fetched nothing else and are not made.
  run c0 <<'PY'
ag = fixture(6, [(400, 20, 2), (400, 20, 3)], [(800, 20, 1)])
d, t, c = m.saving(ag, 4.0)
print(f"{t:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "2000" ]]
}

@test "a request that also fetched something else survives the packet" {
  # Nothing about the catalogue removes a round trip the reviewer still needs for
  # the change - the rule every gate in this line uses.
  run c0 <<'PY'
ag = fixture(6, [(400, 20, 2), (400, 20, 3)], [(800, 20, 1)], extra=[3])
d, t, c = m.saving(ag, 4.0)
print(f"{t:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1000" ]]
}

@test "the digest is credited only where it would still have been re-sent" {
  # It arrived at request 1 and rode in 1..5, but 2 and 3 no longer happen, so it
  # is saved in three requests, not five. Crediting the removed ones counts them
  # twice - their whole cost is already in the trip term.
  run c0 <<'PY'
ag = fixture(6, [(400, 20, 2), (400, 20, 3)], [(800, 20, 1)])
d, t, c = m.saving(ag, 4.0)
print(f"{d:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "600" ]]
}

@test "a moved result carries its command payload with it" {
  # This pins the CONSERVATIVE choice, not a ceiling: the compiled form issues no
  # `rg` and no `cat`, so charging their payloads pays for something the
  # intervention does not. Dropping the charge makes the figure larger, which is
  # why Gate C0 can pass on this arithmetic but could never have refuted on it.
  run c0 <<'PY'
ag = fixture(6, [(400, 200, 3)], [(800, 20, 1)], extra=[3])
d, t, c = m.saving(ag, 4.0)
# 600 bytes over the two surviving requests between the packet and request 3
print(f"{c:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "300" ]]
}

@test "the packet may not be delivered after the reviewer used it" {
  # Later positions carry less, so the enumeration would take one if it were
  # allowed - but the rows were used where they arrived.
  run c0 <<'PY'
ag = fixture(7, [(400, 20, 3), (400, 20, 5)], [(800, 20, 1)], extra=[4])
print(m.legal_positions(ag))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[1, 2, 3]" ]]
}

@test "the difference form equals the compiled round costed from scratch" {
  run c0 <<'PY'
cases = [(6, [(400, 20, 2), (400, 20, 3)], [(800, 20, 1)], []),
         (7, [(400, 200, 3), (1200, 40, 5)], [(900, 20, 1)], [4]),
         (5, [(300, 10, 2)], [(700, 15, 1)], [2, 3])]
for n_req, packet, digest, extra in cases:
    ag = fixture(n_req, packet, digest, extra)
    for bpt in (3.5, 3.8, 4.2):
        for where in (None, *m.legal_positions(ag)):
            got = sum(x * s for x, s in zip(m.saving(ag, bpt, where), (1, 1, -1)))
            assert abs(got - m.rebuilt(ag, bpt, where)) < 1e-9, (got, m.rebuilt(ag, bpt, where))
print("agree")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "agree" ]]
}
