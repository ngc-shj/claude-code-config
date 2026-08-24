#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/compose-prompt.py
#
# The composer decides, byte for byte, what a review agent is told. Index 5 is
# the standing reason it is checked rather than trusted: one agent delivered its
# review through a shell heredoc and another volunteered its severity counts,
# and a third produced nothing because a hand-built prompt lost its output path.
# Each of those is a property of the prompt, so each is a test.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
R24="$REPO/evals/rule-precision/round-24"
SCRIPT="$R24/compose-prompt.py"

setup() {
  export ROOT
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/briefs" "$ROOT/cat-W" "$ROOT/cat-N"
  for arm in W N; do
    printf '# Review brief\n\nCatalogue: %s/cat-%s\n\nWrite to the output path given in your instructions.\n' \
      "$ROOT" "$arm" > "$ROOT/briefs/brief-$arm.md"
  done
}

teardown() {
  rm -rf "$ROOT"
}

# stdout only: the composer prints the prompt to stdout and its sha1 line,
# which also names the path, to stderr. Merging them would double the count.
compose() { run --separate-stderr python3 "$SCRIPT" --root "$ROOT" "$@"; }

@test "the composed prompt is exactly the brief, the separator and the envelope" {
  compose --index 6 --arm N --part a
  [ "$status" -eq 0 ]
  run python3 -c "
import sys
brief = open('$ROOT/briefs/brief-N.md').read()
env = open('$R24/delivery-envelope.md').read().replace(
    '<OUTPUT_PATH>',
    '/home/noguchi/.local/state/claude-code-config/round-24-measurement/reviews/review-06-N-a.md')
sys.stdout.write(brief + '\n---\n\n' + env)"
  expected="$output"
  compose --index 6 --arm N --part a
  [ "$output" = "$expected" ]
}

@test "the output path slot is substituted exactly once" {
  compose --index 6 --arm N --part a
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'review-06-N-a.md')" -eq 1 ]
  [[ "$output" != *"<OUTPUT_PATH>"* ]]
}

@test "the path matches the index, arm and part it was asked for" {
  compose --index 9 --arm W --part c
  [ "$status" -eq 0 ]
  [[ "$output" == *"review-09-W-c.md"* ]]
  [[ "$output" != *"review-06"* ]]
  [[ "$output" != *"-N-"* ]]
}

@test "an index/arm/part with no registered path is refused" {
  compose --index 13 --arm W --part a
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"no registered output path"* ]]
}

@test "W and N differ only in the catalogue path and the output path" {
  compose --index 6 --check-arms
  [ "$status" -eq 0 ]
  [[ "$output" == *"identical modulo <CAT> and <OUT>"* ]]
}

@test "mutation: a brief that differs between the arms is caught" {
  printf 'extra line only in N\n' >> "$ROOT/briefs/brief-N.md"
  compose --index 6 --check-arms
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"differ beyond the catalogue and output paths"* ]]
}

@test "a missing rendered brief is refused rather than composed around" {
  rm "$ROOT/briefs/brief-W.md"
  compose --index 6 --arm W --part a
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"render the briefs first"* ]]
}

@test "a brief already carrying the slot or separator is refused as ambiguous" {
  printf '\n<OUTPUT_PATH>\n' >> "$ROOT/briefs/brief-N.md"
  compose --index 6 --arm N --part a
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"would not be unambiguous"* ]]
}

@test "the envelope names the slot exactly once and forbids the shell route" {
  run cat "$R24/delivery-envelope.md"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '<OUTPUT_PATH>')" -eq 1 ]
  [[ "$output" == *"Write tool only"* ]]
  [[ "$output" == *"Do not use Bash, cat, heredoc, redirection"* ]]
  [[ "$output" == *"retry once with Write"* ]]
  [[ "$output" == *"single word FAILED"* ]]
  [[ "$output" == *"single word DONE"* ]]
  [[ "$output" == *"Never include, quote, summarize, or count findings"* ]]
}

@test "every registered index, arm and part composes and lands on its own path" {
  run python3 -c "
import subprocess, sys
for i in list(range(1, 5)) + list(range(6, 13)):
    for arm in ('W', 'N'):
        for part in ('a', 'b', 'c'):
            p = subprocess.run([sys.executable, '$SCRIPT', '--root', '$ROOT',
                                '--index', str(i), '--arm', arm, '--part', part],
                               capture_output=True, text=True)
            assert p.returncode == 0, (i, arm, part, p.stderr)
            want = 'review-%02d-%s-%s.md' % (i, arm, part)
            assert p.stdout.count(want) == 1, (i, arm, part, p.stdout.count(want))
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "--verify-sent refuses an agent whose prompt was not the composed one" {
  # the reachability probe was launched before the envelope existed
  run --separate-stderr python3 "$SCRIPT" --root "$ROOT" --index 6 --arm N --part a \
    --verify-sent a3ed8e17ab309fbc6
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"not the composed one"* ]]
}
