#!/usr/bin/env bats
# Tests for the Gate 1 replay in evals/rule-precision/routing-trim/gate1.py
#
# Gate 1 refutes on an UPPER bound, so every rule that decides how much a result
# saves has to be checked in the direction it moves that bound. Three of them are
# easy to get backwards: attributing a row line to the rules its prose mentions
# rather than to the rule it IS; splitting a multi-page result that carries no
# boundary; and crediting the first ingestion of bytes whose request has already
# been removed whole. Each is pinned below by a case that goes red when the rule
# is inverted.
#
# No transcript is read: every fixture is built in the test.

bats_require_minimum_version 1.5.0

GATE1="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/routing-trim/gate1.py"

# Run a python snippet with gate1 loaded as `m`. The heredoc is quoted at the
# call site, so `$f` inside a fixture shell command reaches python untouched.
g1() {
  { printf '%s\n' \
      'import importlib.util, sys' \
      "spec = importlib.util.spec_from_file_location('gate1', '$GATE1')" \
      'm = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)'
    cat; } | python3 -
}

@test "a row line is attributed to the rule it IS, not the rules it mentions" {
  # 833 of the 3070 row lines in the corpus name more than one rule: the row for
  # R1 cross-refers to R40 and R49 in its own prose. Reading the IDs out of the
  # line as a set hands those bytes to rules the line is not about, and every
  # per-rule saving downstream is built on this attribution.
  run g1 <<'PY'
text = '307:| R1 | see R40 and R49 for the rest |\n12:| R40 | plain |\n'
print(m.row_parts(text))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[('R1', 42), ('R40', 19)]" ]]
}

@test "row bytes that name no rule stay unattributed" {
  # `rg ... && ls rule-details` puts a directory listing in the same result. It
  # belongs to no rule, so it can only be carried as a band.
  run g1 <<'PY'
print(m.row_parts('7:| R3 | x |\nR1.md  3.8K\n'))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[('R3', 13), (None, 12)]" ]]
}

@test "a multi-page result splits at the separator its own command wrote" {
  # `for f in ...; do echo "##### $f"; cat $f.md; done` marks each page, so the
  # bytes attribute per page even though one call carried six.
  run g1 <<'PY'
cmd = 'cd /d/rule-details && for f in R3 R49; do echo "##### $f"; cat $f.md; done'
res = '##### R3\n# R3 - x\nbody mentioning R49 in passing\n##### R49\n# R49 - y\n'
print(m.page_parts(res, cmd, {'R3', 'R49'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[('R3', 49), ('R49', 20)]" ]]
}

@test "the separator comes from the command, so page prose cannot fake one" {
  # A page opens with `# R49 - ...` and cross-refers to other rules. A splitter
  # that looked for ID-shaped lines in the OUTPUT would cut R3's page in two and
  # hand half of it to R49.
  run g1 <<'PY'
cmd = 'cd /d/rule-details && for f in R3 R49; do echo "##### $f"; cat $f.md; done'
res = '##### R3\n# R3 - x\n## R49\nsee R49\n##### R49\n# R49 - y\n'
parts = m.page_parts(res, cmd, {'R3', 'R49'})
print(sorted(set(i for i, _ in parts)), len(parts))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "['R3', 'R49'] 2" ]]
}

@test "a literal echo marker splits too, and the listing before it does not" {
  # `ls && echo "---R3---" && cat R3.md && ...` - the marker names the page
  # outright, and the `ls` output ahead of the first marker belongs to no page.
  run g1 <<'PY'
cmd = 'cd /d/rule-details && ls && echo "---R3---" && cat R3.md && echo "---RS3---" && cat RS3.md'
print(m.page_parts('R1.md 3.8K\n---R3---\nbody3\n---RS3---\nbodyS3\n', cmd, {'R3', 'RS3'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[(None, 11), ('R3', 15), ('RS3', 17)]" ]]
}

@test "a result whose command wrote no boundary cannot be split" {
  # `cat R3.md R40.md` returns two pages as one run of bytes. Splitting it would
  # need a guess, and a guess in either direction is not a bound.
  run g1 <<'PY'
print(m.page_parts('aaa\nbbb\n', 'cd /d/rule-details && cat R3.md R40.md', {'R3', 'R40'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "None" ]]
}

@test "a split that misses one of its own pages is not a split" {
  # The command claims three pages and the output marks two. Attributing the
  # third page's bytes to whichever segment they landed in would silently move
  # bytes between rules.
  run g1 <<'PY'
cmd = 'cd /d/rule-details && for f in R3 R49 RS3; do echo "##### $f"; cat $f.md; done'
print(m.page_parts('##### R3\nx\n##### R49\ny\n', cmd, {'R3', 'R49', 'RS3'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "None" ]]
}

@test "a single-page result attributes wholly to its page" {
  run g1 <<'PY'
print(m.page_parts('anything at all\n', '/d/rule-details/R49.md', {'R49'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "[('R49', 16)]" ]]
}

@test "a result loses everything only when every ID it carries is dropped" {
  # The third value decides a round trip, so it must not be true for a result the
  # gate still needs. Retaining R1 keeps the request even though R2's line goes.
  run g1 <<'PY'
r = m.Result(380, 1, 'rows', {'R1', 'R2'}, [('R1', 200), ('R2', 180)])
print(m.removal(r, set()), m.removal(r, {'R1'}), m.removal(r, {'R1', 'R2'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(380, 380, True) (180, 180, False) (0, 0, False)" ]]
}

@test "an unsplittable result is a band: nothing at the lower end, all at the upper" {
  # Refutation is on the upper end, so the unattributable case has to resolve
  # towards the LARGER saving. The earlier version of this rule kept the result
  # whole and credited zero - a lower bound, which can refute nothing.
  run g1 <<'PY'
r = m.Result(500, 2, 'page', {'R3', 'R40'}, None)
print(m.removal(r, {'R3'}), m.removal(r, set()))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(0, 500, False) (500, 500, True)" ]]
}

@test "bytes that belong to no rule ride the upper end, not the lower" {
  run g1 <<'PY'
r = m.Result(120, 1, 'rows', {'R1', 'R2'}, [('R1', 50), ('R2', 40), (None, 30)])
print(m.removal(r, {'R1'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(40, 70, False)" ]]
}

@test "a directory call goes only when the agent retains nothing" {
  # It names no page, so no rule can drop it on its merits: with anything
  # retained the reviewer still has a reason to look in the directory.
  run g1 <<'PY'
r = m.Result(90, 1, 'dir', set(), None)
print(m.removal(r, set()), m.removal(r, {'R3'}))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "(90, 90, True) (0, 0, False)" ]]
}

@test "a removed request carries its own first ingestion, and is not paid twice" {
  # 4 requests of 1000 raw tokens each; one 380-byte row result ingested by
  # request 1, and nothing else in that request. At 3.8 B/tok that is 100 tokens,
  # re-sent by 2 later requests: trip 1000, content 300 - 100 = 200, because the
  # first 100 is already inside the request that disappeared.
  run g1 <<'PY'
import collections
u = {'input_tokens': 0, 'cache_read_input_tokens': 1000,
     'cache_creation_input_tokens': 0, 'output_tokens': 0}
ag = dict(usages=[dict(u) for _ in range(4)],
          results=[m.Result(380, 1, 'rows', {'R1', 'R2'}, [('R1', 200), ('R2', 180)])],
          n_results=collections.Counter({1: 1}), opened=set(), candidates={'R1', 'R2'})
trip, content, _api = m.evaluate(ag, set(), 3.8)
print(f"{trip:.0f} {content['lower']:.0f} {content['upper']:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1000 200 200" ]]
}

@test "a surviving request still saves the bytes it no longer ingests" {
  # Same fixture, R1 retained: no request disappears, so the 180 removed bytes
  # are saved where they were ingested AND in the 2 later re-sends - 3 x 47.37.
  # Dropping the first ingestion here is what gate0.py does; it understates the
  # bound, and understating an upper bound is how a gate refutes too easily.
  run g1 <<'PY'
import collections
u = {'input_tokens': 0, 'cache_read_input_tokens': 1000,
     'cache_creation_input_tokens': 0, 'output_tokens': 0}
ag = dict(usages=[dict(u) for _ in range(4)],
          results=[m.Result(380, 1, 'rows', {'R1', 'R2'}, [('R1', 200), ('R2', 180)])],
          n_results=collections.Counter({1: 1}), opened=set(), candidates={'R1', 'R2'})
trip, content, _api = m.evaluate(ag, {'R1'}, 3.8)
g0, c0, _a0 = m.evaluate(ag, {'R1'}, 3.8, gate0_mode=True)
print(f"{trip:.0f} {content['upper']:.2f} {g0:.0f} {c0['upper']:.2f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "0 142.11 0 94.74" ]]
}

@test "a request that ingests anything else survives its own scope being emptied" {
  # The same result, but the request also carried the diff. Nothing about the
  # catalogue can delete a round trip the reviewer still needs for the change.
  run g1 <<'PY'
import collections
u = {'input_tokens': 0, 'cache_read_input_tokens': 1000,
     'cache_creation_input_tokens': 0, 'output_tokens': 0}
ag = dict(usages=[dict(u) for _ in range(4)],
          results=[m.Result(380, 1, 'rows', {'R1'}, [('R1', 380)])],
          n_results=collections.Counter({1: 2}), opened=set(), candidates={'R1'})
trip, content, _api = m.evaluate(ag, set(), 3.8)
print(f"{trip:.0f} {content['upper']:.0f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "0 300" ]]
}

@test "a consolidating gate fetches the retained rows once, so later fetches go whole" {
  # The protocol's consolidated variant says the retained IDs "are fetched in one
  # `rg`". Costing each historical fetch on its own merits keeps a second fetch
  # alive because it happened to carry a retained ID - and understates both the
  # bytes and the round trip for the five agents that fetch rows more than once.
  # Without consolidation the same fixture saves the second fetch nothing.
  run g1 <<'PY'
import collections
u = {'input_tokens': 0, 'cache_read_input_tokens': 1000,
     'cache_creation_input_tokens': 0, 'output_tokens': 0}
ag = dict(usages=[dict(u) for _ in range(5)],
          results=[m.Result(400, 1, 'rows', {'R1', 'R2'}, [('R1', 200), ('R2', 200)]),
                   m.Result(300, 3, 'rows', {'R1'}, [('R1', 300)])],
          n_results=collections.Counter({1: 1, 3: 1}), opened=set(), candidates={'R1', 'R2'})
on = m.evaluate(ag, {'R1'}, 3.8)
off = m.evaluate(ag, {'R1'}, 3.8, consolidate=False)
print(f"{on[0]:.0f} {on[1]['upper']:.2f} {off[0]:.0f} {off[1]['upper']:.2f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "1000 289.47 0 210.53" ]]
}

@test "the fetch that survives consolidation is one that carries a retained ID" {
  # If the survivor were just the first row fetch, a first fetch that retains
  # nothing would be removed along with every later one - and the gate would be
  # credited with fetching no rows at all while still keeping R1.
  run g1 <<'PY'
import collections
u = {'input_tokens': 0, 'cache_read_input_tokens': 1000,
     'cache_creation_input_tokens': 0, 'output_tokens': 0}
ag = dict(usages=[dict(u) for _ in range(5)],
          results=[m.Result(400, 1, 'rows', {'R2'}, [('R2', 400)]),
                   m.Result(300, 3, 'rows', {'R1'}, [('R1', 300)])],
          n_results=collections.Counter({1: 1, 3: 1}), opened=set(), candidates={'R1', 'R2'})
keeper = m.consolidated_rows(ag['results'], {'R1'})
trip, content, _api = m.evaluate(ag, {'R1'}, 3.8)
print(f"{keeper.req} {trip:.0f} {content['upper']:.2f}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "3 1000 315.79" ]]
}

@test "the four rules nest, so the savings can only fall from G1 to G4" {
  # G1 subset G2 subset G3 subset G4 by construction. If a later rule ever
  # retained less than an earlier one, the ordering the protocol reports the
  # table in would be meaningless.
  run g1 <<'PY'
keys = [('W', 1, 'a'), ('W', 1, 'b'), ('W23', 1, 'a')]
scanned = [dict(opened={'R9'}), dict(opened=set()), dict(opened={'RT2'})]
cited = {('W', 1, 'a'): {'R1'}, ('W', 1, 'b'): {'R2'}, ('W23', 1, 'a'): {'R3'}}
rules = m.retention(keys, scanned, cited)
k = keys[0]
sets = [sorted(rules[n][k]) for n in rules]
print(sets)
print(all(set(a) <= set(b) for a, b in zip(sets, sets[1:])))
PY
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[['R1'], ['R1', 'R9'], ['R1', 'R2', 'R9'], ['R1', 'R2', 'R3', 'R9', 'RT2']]" ]]
  [[ "${lines[1]}" == "True" ]]
}

@test "G3 unions the reviewers of one review only, G4 crosses the arms" {
  # Both are keyed on the review INDEX. A rule that unioned the whole round
  # would retain nearly every candidate and report a saving of about nothing.
  run g1 <<'PY'
keys = [('W', 1, 'a'), ('W', 2, 'a'), ('W23', 1, 'a')]
scanned = [dict(opened=set())] * 3
cited = {('W', 1, 'a'): {'R1'}, ('W', 2, 'a'): {'R2'}, ('W23', 1, 'a'): {'R3'}}
rules = m.retention(keys, scanned, cited)
print(sorted(rules['G3 + the other two reviewers'][('W', 1, 'a')]),
      sorted(rules['G4 + the other arm'][('W', 1, 'a')]))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "['R1'] ['R1', 'R3']" ]]
}
