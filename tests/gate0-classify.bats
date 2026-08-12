#!/usr/bin/env bats
# Tests for the tool-call classifier in evals/rule-precision/routing-trim/gate0.py
#
# The classifier decides which tool calls fetched catalogue material, and every
# token figure Gate 0 reports is a sum over what it selects. It was wrong once in
# a way no input check could catch: it tested substrings of the whole serialised
# tool input, so a reviewer's own WRITTEN OUTPUT — a finding quoting
# `common-rules.md` and an `rg` command — was counted as a catalogue fetch. That
# inflated the round-trip term by 37 phantom requests and moved the Gate 0
# ceiling from below the 20% bar to above it. These tests pin the fix.
#
# No transcript is read: each case is a literal tool call.

bats_require_minimum_version 1.5.0

GATE0="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/routing-trim/gate0.py"

# Evaluate a python expression with gate0 imported as `g`.
classify() {
  python3 - "$GATE0" "$1" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('g', sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
call = json.loads(sys.argv[2])
t = g.tool_target(call['name'], call['input'])
print(f"rows={g.is_rows(t)} catalogue={g.is_catalogue(t)} page={g.is_detail_page(t)} dir={g.is_detail(t)}")
PY
}

@test "an anchored rg over the rules file is a row fetch" {
  run classify '{"name":"Bash","input":{"command":"cd /t/cat-W && rg -n '"'"'^\\| (R3|R49|RS3) \\|'"'"' common-rules.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=True catalogue=True page=False dir=False" ]]
}

@test "a review body quoting the catalogue is NOT a fetch" {
  # The exact shape that produced the phantom requests: a Write whose content
  # mentions common-rules.md and shows an rg command with an anchored pattern.
  run classify '{"name":"Write","input":{"file_path":"/t/out/W-3-c.md","content":"### Major: rule lookup\nI ran rg -n '"'"'^\\| (R3) \\|'"'"' common-rules.md to confirm this."}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=False page=False dir=False" ]]
}

@test "a row fetch combined with listing rule-details is still a row fetch" {
  # Five agents issue both in one command. Excluding anything that mentions
  # rule-details - the previous test - dropped these real fetches.
  run classify '{"name":"Bash","input":{"command":"cd /t/cat-W && rg -n '"'"'^\\| (R3|R49) \\|'"'"' common-rules.md && ls rule-details"}}'
  [ "$status" -eq 0 ]
  # A listing is directory traffic but names no page: generous scope only.
  [[ "$output" == "rows=True catalogue=True page=False dir=True" ]]
}

@test "a bare directory listing is generous-scope only, never a page" {
  # The strict and generous ceilings differ by exactly these calls, so the two
  # predicates must not collapse into one.
  run classify '{"name":"Bash","input":{"command":"cd /t/cat-W && ls rule-details | head -80"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=True page=False dir=True" ]]
}

@test "a path under rule-details/ that names no page is not a page" {
  # The strict and generous ceilings differ by exactly these. A predicate that
  # tests for the directory prefix instead of an identifiable <ID>.md file
  # collapses the two, and this is the case that catches it.
  run classify '{"name":"Bash","input":{"command":"cd /t/cat-W && ls rule-details/ | wc -l"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=True page=False dir=True" ]]
}

@test "reading a rule-detail page is catalogue but not a row fetch" {
  run classify '{"name":"Read","input":{"file_path":"/t/cat-W/rule-details/R49.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=True page=True dir=True" ]]
}

@test "the Remedy Floor awk extraction is catalogue but not a row fetch" {
  run classify '{"name":"Bash","input":{"command":"cd /t/cat-W && awk '"'"'/^### Remedy Floor/,/^### Anti-Deferral/'"'"' common-rules.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=True page=False dir=False" ]]
}

@test "writing the review out is neither, however long the content" {
  run classify '{"name":"Write","input":{"file_path":"/t/out/W-1-a.md","content":"### Critical: something about /t/cat-W/rule-details/R3.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "rows=False catalogue=False page=False dir=False" ]]
}

@test "tool_target never returns the payload a call writes" {
  # The behavioural form of the fix: whatever a Write carries, the text the
  # classifier sees is the destination, not the bytes. A source-text assertion
  # would pass on a refactor that reintroduced the bug through another field.
  run python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('g', '$GATE0')
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
payload = 'common-rules.md rg ^\\\\| every catalogue string at once /cat-W/rule-details/R3.md'
t = g.tool_target('Write', {'file_path': '/t/out/W-1-a.md', 'content': payload})
assert payload not in t, f'payload leaked into the classified text: {t!r}'
assert '/t/out/W-1-a.md' in t, t
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
