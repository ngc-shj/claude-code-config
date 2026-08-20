#!/usr/bin/env bats
# Tests for the compiler and its replay in evals/rule-precision/packet-compiler/
#
# Gate C1 refutes, so what needs pinning is anything that could understate the
# saving: the packet must be carried by every surviving request from the host on
# (one packet for the fixture, not each member from where it happened to arrive),
# the digest and the historical fetches must be taken back out of those contexts,
# and the figure must be allowed to go negative - the whole-catalogue packet does.
#
# The coverage side is pinned too, because the verdict rests on the union being
# the CHEAPEST covering packet rather than on how compiler.py selects.
#
# No transcript is read: every fixture is built in the test.

bats_require_minimum_version 1.5.0

DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/packet-compiler"

c1() {
  { printf '%s\n' \
      'import collections, importlib.util, os' \
      "def L(n, p):" \
      "    s = importlib.util.spec_from_file_location(n, p)" \
      "    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m" \
      "m = L('gate_c1', '$DIR/gate_c1.py')" \
      "C = L('compiler', '$DIR/compiler.py')" \
      'U = {"input_tokens": 0, "cache_read_input_tokens": 1000,' \
      '     "cache_creation_input_tokens": 0, "output_tokens": 0}' \
      '# packet/digest: [(result bytes, command bytes, request)]' \
      'def fixture(n_req, packet, digest, extra=()):' \
      '    usages = [dict(U) for _ in range(n_req)]' \
      '    n_gone = collections.Counter(r for _b, _c, r in packet + digest)' \
      '    n_results = collections.Counter(n_gone)' \
      '    for r in extra:' \
      '        n_results[r] += 1' \
      '    resp = {r: (1, collections.Counter({"the candidate, generous": 1}))' \
      '            for r in range(n_req)}' \
      '    return dict(usages=usages, packet=packet, digest=digest,' \
      '                n_results=n_results, n_gone=n_gone, resp=resp)'
    cat; } | python3 -
}

@test "the packet is carried by every surviving request from the host onward" {
  # This is what makes C1 different from C0: one packet for the fixture, not a
  # bundle whose members each stop being re-sent where they used to arrive.
  # Every request from 1 on survives with the packet in context; charging it only
  # up to each member's old arrival would understate what a compiler costs.
  run c1 <<'PY'
ag = fixture(6, [(400, 20, 2)], [(800, 20, 1)], extra=[1, 2, 3, 4, 5])
# digest 800B and the old fetch 400B come out; a 4000B packet plus the 140B
# compiler invocation goes in from req 1
print(f"{m.compiled_round(ag, 4000, 4.0):.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "-3775" ]]
}

@test "a packet small enough still wins, so the sign is not built in" {
  run c1 <<'PY'
ag = fixture(6, [(400, 20, 2)], [(800, 20, 1)], extra=[1, 2, 3, 4, 5])
print(f"{m.compiled_round(ag, 100, 4.0):.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1100" ]]
}

@test "a request whose every result the packet replaces is not made" {
  # Request 2 fetched nothing but catalogue, so it goes and the saving is 1860.
  # Give it one result the packet does not replace and it survives, taking its
  # round trip with it - 1100.
  run c1 <<'PY'
ag = fixture(6, [(400, 20, 2)], [(800, 20, 1)], extra=[1])
with_trip = m.compiled_round(ag, 100, 4.0)
ag2 = fixture(6, [(400, 20, 2)], [(800, 20, 1)], extra=[1, 2])
print(f"{with_trip:.0f} {m.compiled_round(ag2, 100, 4.0):.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1860 1100" ]]
}

@test "the host survives even when it fetched nothing but the digest" {
  # Request 1 ingests the digest and nothing else, so it is in the set of requests
  # the packet replaces - but it is also where the packet is delivered. Removing it
  # with the others credits a round trip that still has to happen, and the earlier
  # fixtures could not see this because their host also carried something else.
  run c1 <<'PY'
ag = fixture(6, [(400, 20, 3)], [(800, 20, 1)], extra=[2, 4, 5])
print(f"{m.compiled_round(ag, 100, 4.0):.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1760" ]]
}

@test "the compiler's own invocation is charged, not assumed free" {
  # The protocol says this gate measures the command it actually issues. Leaving
  # it out makes the saving larger, which is the direction a refutation must not
  # be generous in.
  run c1 <<'PY'
ag = fixture(6, [(400, 20, 2)], [(800, 20, 1)], extra=[1, 2, 3, 4, 5])
free = m.compiled_round(ag, 100, 4.0)
padded = m.compiled_round(ag, 100 + len(m.COMMAND.encode("utf-8")), 4.0)
print(f"{len(m.COMMAND.encode('utf-8'))} {free - padded:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "140 175" ]]
}

@test "the union of what agents used is the cheapest packet that covers them" {
  # The verdict rests on this and not on compiler.py: one packet serves every
  # review, so it must contain each agent's own set, so it must contain their
  # union - and any covering packet is a superset of it.
  run c1 <<'PY'
used = {"a": {"R1", "R3"}, "b": {"R3", "R49"}, "c": {"R1"}}
union = set().union(*used.values())
assert all(v <= union for v in used.values()), union
for candidate in ({"R1", "R3"}, {"R3", "R49"}, set(), {"R1", "R49"}):
    covers = all(v <= candidate for v in used.values())
    assert not covers or union <= candidate, (candidate, union)
print(sorted(union))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "['R1', 'R3', 'R49']" ]]
}

@test "a rule fires only on a token its own row is specific about" {
  # `set` and `error` occur in every change ever written; a rule that fires on
  # them has selected the whole catalogue rather than a packet.
  run c1 <<'PY'
print(sorted(C.tokens_of("| R9 | x | wrap it in `FOR UPDATE SKIP LOCKED` and `set` and `err` |")))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "['LOCKED', 'SKIP', 'UPDATE']" ]]
}

@test "the whole-catalogue packet cannot miss a rule, and pays for it" {
  run c1 <<'PY'
import tempfile, os
d = tempfile.mkdtemp()
open(os.path.join(d, "common-rules.md"), "w").write(
    "| ID | Pattern | Trigger |\n| R1 | a | `alpha` |\n| R2 | b | `beta` |\n")
os.mkdir(os.path.join(d, "rule-details"))
open(os.path.join(d, "rule-details", "R2.md"), "w").write("page\n")
sel, pgs = C.compile_packet("nothing matches here", d)
all_sel, all_pgs = C.compile_packet("nothing matches here", d, everything=True)
print(sorted(sel), sorted(all_sel), sorted(all_pgs))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[] ['R1', 'R2'] ['R2']" ]]
}
