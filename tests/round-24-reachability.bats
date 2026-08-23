#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/reachability.py
#
# The reachability gate decides whether the ablation can mean anything at all, so
# both of its jobs are exercised on synthetic transcripts rather than trusted:
#
#   1. it counts an EXECUTED extraction, not an issued one — a Bash call that
#      named the Finding Floor and then failed must not score;
#   2. it reads the three agents the manifest names and nothing else, and it
#      prints tool calls only — never review text, never tool-result content.
#
# Every fixture is built in an ephemeral tree; no test reads the real probe.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
R24="$REPO/evals/rule-precision/round-24"
SCRIPT="$R24/reachability.py"
SESSION="00000000-0000-4000-8000-000000000000"

setup() {
  export SANDBOX SUB MAN
  SANDBOX="$(mktemp -d)"
  SUB="$SANDBOX/$SESSION/subagents"
  MAN="$SANDBOX/manifest.tsv"
  mkdir -p "$SUB"
}

teardown() {
  rm -rf "$SANDBOX"
}

# agent <id> <floor-result: ok|error|missing|no-flag|absent>
#
# Writes a transcript that reads the digest, extracts the Finding Floor, and
# writes a review. The review text is real prose so that a leak would be visible
# in the output if one existed.
agent() {
  python3 - "$SUB" "$1" "$2" <<'PY'
import json, sys
sub, aid, floor = sys.argv[1:]
SECRET = 'CRITICAL: signing_secret leaks through to_dict'   # a finding, verbatim
lines = []


def assistant(blocks):
    lines.append({'message': {'role': 'assistant', 'content': blocks}})


def result(tid, is_error=False):
    lines.append({'message': {'role': 'user', 'content': [
        {'type': 'tool_result', 'tool_use_id': tid, 'is_error': is_error,
         'content': 'FILE BODY ' + SECRET}]}})


assistant([{'type': 'thinking', 'thinking': SECRET}])
assistant([{'type': 'tool_use', 'id': 't1', 'name': 'Read',
            'input': {'file_path': '/x/cat-W/common-rules.digest.md'}}])
result('t1')
if floor != 'absent':
    assistant([{'type': 'tool_use', 'id': 't2', 'name': 'Bash',
                'input': {'command': "awk '/^### Finding Floor/,/^### Remedy Floor/' /x/cat-W/common-rules.md"}}])
    if floor == 'ok':
        result('t2')
    elif floor == 'error':
        result('t2', is_error=True)
    elif floor == 'no-flag':
        # a result exists and simply does not say whether it failed
        lines.append({'message': {'role': 'user', 'content': [
            {'type': 'tool_result', 'tool_use_id': 't2',
             'content': 'FILE BODY ' + SECRET}]}})
    # 'missing' writes no result at all
assistant([{'type': 'tool_use', 'id': 't3', 'name': 'Write',
            'input': {'file_path': '/x/probe.md'}}])
result('t3')
assistant([{'type': 'text', 'text': SECRET}])

with open(f'{sub}/agent-{aid}.jsonl', 'w') as f:
    for rec in lines:
        f.write(json.dumps(rec) + '\n')
PY
}

manifest() {
  { printf 'session\tagent_id\tgit_blob_sha1\n'
    for id in "$@"; do
      printf '%s\t%s\t%s\n' "$SESSION" "$id" \
        "$(git -C "$REPO" hash-object "$SUB/agent-$id.jsonl")"
    done
  } > "$MAN"
}

probe() { run python3 "$SCRIPT" --manifest "$MAN" --transcript-dir "$SANDBOX"; }

@test "three successful extractions pass the gate" {
  agent aaa1 ok; agent aaa2 ok; agent aaa3 ok
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"3/3"* ]]
  [[ "$output" == *"GATE: 3/3 — proceed"* ]]
}

@test "an extraction that returned is_error does not count as executed" {
  agent aaa1 ok; agent aaa2 error; agent aaa3 ok
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"2/3"* ]]
  [[ "$output" == *"GATE: 2/3 — STOP"* ]]
  [[ "$output" == *"uncontrolled mixture"* ]]
  [[ "$output" == *"ERROR"* ]]
}

@test "an extraction with no matching tool-result does not count as executed" {
  agent aaa1 missing; agent aaa2 missing; agent aaa3 missing
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"0/3"* ]]
  [[ "$output" == *"would measure nothing"* ]]
  [[ "$output" == *"no-result"* ]]
}

@test "a tool-result with no is_error flag is unknown, not success" {
  # `bool(block.get("is_error"))` reads a missing flag as False, i.e. as
  # success — the one direction this gate must never be generous in.
  agent aaa1 no-flag; agent aaa2 no-flag; agent aaa3 no-flag
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"0/3"* ]]
  [[ "$output" == *"no-flag"* ]]
  [[ "$output" == *"would measure nothing"* ]]
}

@test "no extraction issued at all is 0/3" {
  agent aaa1 absent; agent aaa2 absent; agent aaa3 absent
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"0/3"* ]]
}

@test "a fourth agent in the same session is not analysed" {
  agent aaa1 ok; agent aaa2 ok; agent aaa3 ok
  agent zzz9 error          # a later, unrelated agent — e.g. one of the 72
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"GATE: 3/3 — proceed"* ]]
  [[ "$output" != *"zzz9"* ]]
}

@test "a manifest of other than three agents is refused" {
  agent aaa1 ok; agent aaa2 ok
  manifest aaa1 aaa2
  probe
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected exactly 3"* ]]
}

@test "an edited transcript fails on its pinned hash" {
  agent aaa1 ok; agent aaa2 ok; agent aaa3 ok
  manifest aaa1 aaa2 aaa3
  printf '{"message":{"role":"assistant","content":[]}}\n' >> "$SUB/agent-aaa2.jsonl"
  probe
  [ "$status" -eq 2 ]
  [[ "$output" == *"SHA1 MISMATCH"* ]]
}

@test "a transcript named by the manifest but absent is refused" {
  agent aaa1 ok; agent aaa2 ok; agent aaa3 ok
  manifest aaa1 aaa2 aaa3
  rm "$SUB/agent-aaa3.jsonl"
  probe
  [ "$status" -eq 2 ]
  [[ "$output" == *"TRANSCRIPT MISSING"* ]]
}

@test "no review text, thinking or tool-result body reaches the output" {
  agent aaa1 ok; agent aaa2 ok; agent aaa3 ok
  manifest aaa1 aaa2 aaa3
  probe
  [ "$status" -eq 0 ]
  # the finding text appears in text blocks, thinking blocks and tool_result
  # bodies of every fixture; none of it may be printed
  [[ "$output" != *"signing_secret"* ]]
  [[ "$output" != *"CRITICAL"* ]]
  [[ "$output" != *"FILE BODY"* ]]
}

@test "the committed manifest names three distinct agents in one session" {
  run python3 -c "
import csv
rows = list(csv.DictReader(open('$R24/reachability-manifest.tsv', newline=''), delimiter='\t'))
assert len(rows) == 3, len(rows)
assert len({r['agent_id'] for r in rows}) == 3
assert len({r['session'] for r in rows}) == 1
assert all(len(r['git_blob_sha1']) == 40 for r in rows)
# git blob sha1, not the plain file digest: prove they differ for a real file
import hashlib, subprocess
b = open('$R24/reachability-manifest.tsv','rb').read()
plain = hashlib.sha1(b).hexdigest()
blob = hashlib.sha1(b'blob %d\\0' % len(b) + b).hexdigest()
assert plain != blob
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
