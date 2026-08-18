#!/usr/bin/env bats
# Tests for the causal replay in evals/rule-precision/request-batching/gate_b1.py
#
# Gate B1 refutes, and it does so 0.5 points under the bar, so the rules that
# could quietly shrink the figure are the ones that matter: the causal floor that
# forbids the batch landing where B0 put it, and the two relaxations that a
# refutation phrased as "no batching form" has to cover. Each is pinned below by a
# case that goes red when the rule is inverted.
#
# No transcript is read: every fixture is built in the test.

bats_require_minimum_version 1.5.0

GATEB1="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/request-batching/gate_b1.py"

b1() {
  { printf '%s\n' \
      'import collections, importlib.util' \
      "spec = importlib.util.spec_from_file_location('gate_b1', '$GATEB1')" \
      'm = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)' \
      'U = {"input_tokens": 0, "cache_read_input_tokens": 1000,' \
      '     "cache_creation_input_tokens": 0, "output_tokens": 0}' \
      '# scoped: [(bytes, request)]. extra: requests ingesting something else too.' \
      '# digest: where the digest result arrived. floor: indices of scoped results' \
      '# whose command also ran a floor extraction.' \
      'def fixture(n_req, scoped, extra=(), digest=0, out=(), floor=()):' \
      '    usages = [dict(U, output_tokens=dict(out).get(r, 0)) for r in range(n_req)]' \
      '    res = [m.Res(b, b, r, 10, 10, i in floor)' \
      '           for i, (b, r) in enumerate(scoped)]' \
      '    n_scoped = collections.Counter(r for _b, r in scoped)' \
      '    n_results = collections.Counter(n_scoped)' \
      '    for r in extra:' \
      '        n_results[r] += 1' \
      '    resp = {r: (1, collections.Counter({m.b0.PRIMARY: 1})) for r in range(n_req)}' \
      '    return dict(usages=usages, results=res, n_results=n_results,' \
      '                n_scoped=n_scoped, digest=digest, resp=resp)' \
      'NAME = m.b0.PRIMARY'
    cat; } | python3 -
}

@test "the batch lands after the digest, not in the request that carries it" {
  # B0 put the batch in whatever request survived anyway, which for 79 of the 150
  # agents is the request that ingests the digest itself. The rows are derived
  # from that digest, so the causal floor forbids it: request 1 ingests the diff
  # and would host under B0, but stage 1 cannot arrive before request 2.
  run b1 <<'PY'
ag = fixture(6, [(400, 2), (400, 3)], extra=[1], digest=1)
a, b, c = m.figures(ag, 4.0, NAME)
# request 3 is catalogue-only and goes; request 2 hosts the batch and stays
print(f"{a:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "900" ]]
}

@test "a result whose request survives anyway is not worth batching" {
  # Moving it earlier removes no round trip - the request stays for the diff it
  # also carries - and costs early carry. A form free to leave it where it is
  # saves more, and a bound over batching forms has to say so.
  run b1 <<'PY'
ag = fixture(6, [(400, 2), (400, 4)], extra=[1, 4], digest=1)
a, b, c = m.figures(ag, 4.0, NAME)
print(f"{a:.0f} {b:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "-200 0" ]]
}

@test "a request whose carry exceeds its own cost is not batched either" {
  # 8000 bytes at 4.0 B/tok is 2000 tokens, re-sent by the three requests between
  # the host and where it arrived - 6000 against a 1000-token request. Batching it
  # is a loss, so the move-subset bound takes zero, not the loss.
  run b1 <<'PY'
ag = fixture(6, [(400, 2), (8000, 5)], extra=[1], digest=1)
a, b, c = m.figures(ag, 4.0, NAME)
print(f"{a:.0f} {b:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "-5000 0" ]]
}

@test "deferring the host is enumerated, and never reported below the fixed form" {
  # (c) tries every position at or after the causal floor. It can only be larger
  # than (a): if no later host helps, the floor position is among the candidates.
  run b1 <<'PY'
for scoped, extra in ([(400, 2), (400, 4)], [1]), ([(400, 2), (400, 3)], [1]), ([(900, 3)], [1, 2]):
    ag = fixture(6, scoped, extra=extra, digest=1)
    a, b, c = m.figures(ag, 4.0, NAME)
    assert c >= a - 1e-9 and c >= b - 1e-9, (a, b, c)
print("c dominates")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "c dominates" ]]
}

@test "carry is charged only to requests that certainly survive" {
  # Requests 2, 3 and 5 are catalogue-only and 4 ingests the diff. When the bound
  # asks what request 5 would pay to move, only 4 is certainly still there to
  # re-send it - counting 2 and 3 as well charges the moved bytes to requests the
  # same bound is removing, and turns a 500-token gain into a decline.
  run b1 <<'PY'
ag = fixture(7, [(400, 2), (400, 3), (2000, 5)], extra=[1, 4], digest=1)
a, b, c = m.figures(ag, 4.0, NAME)
print(f"{a:.0f} {b:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "900 1500" ]]
}

@test "a later host can beat the causal floor, and the enumeration finds it" {
  # The 1200-byte result arrives at request 6 and pays carry over every surviving
  # request back to the host. Hosting at the floor costs it three of those and
  # leaves 100 tokens; hosting at 5 costs one and leaves 700. An enumeration that
  # only tries the floor reports the smaller number as the maximum.
  run b1 <<'PY'
ag = fixture(8, [(400, 2), (1200, 6)], extra=[1, 3, 4, 5], digest=1)
a, b, c = m.figures(ag, 4.0, NAME)
print(f"{a:.0f} {b:.0f} {c:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "-200 100 700" ]]
}

@test "the difference formula equals the batched round costed from scratch" {
  run b1 <<'PY'
for scoped, extra, out in (([(400, 2), (400, 3)], [1], {3: 500}),
                           ([(400, 2), (1200, 5)], [1, 4], {}),
                           ([(300, 2)], [1, 3], {2: 700})):
    ag = fixture(6, scoped, extra=extra, digest=1, out=out)
    for bpt in (3.5, 3.8, 4.2):
        a, _b, _c = m.figures(ag, bpt, NAME)
        assert abs(a - m.rebuilt(ag, bpt, NAME)) < 1e-9, (a, m.rebuilt(ag, bpt, NAME))
print("agree")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "agree" ]]
}

@test "a floor extraction pulled in by a directory mention can be taken back out" {
  # `protocol.md` puts the floor extraction in the whole-catalogue superset only,
  # but the call-level predicate pulls the whole result into the primary scope
  # when the same command also touches the directory. Dropping it lowers the
  # figure, which is why it is a correction and not the headline.
  run b1 <<'PY'
ag = fixture(6, [(400, 2), (5000, 3)], extra=[1], digest=1, floor=[1])
kept = m.figures(ag, 4.0, NAME)[0]
dropped = m.figures(ag, 4.0, NAME, drop_floor=True)[0]
print(f"{kept:.0f} {dropped:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "-250 0" ]]
}
