#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/briefs/render.py
#
# Round 24 cannot reuse round 17's briefs: they name a scratchpad that no longer
# exists and counts that no longer apply. It re-renders them from templates
# instead, which is only safe if the templates carry the instrument unchanged and
# the renderer refuses to emit a brief that still names a template slot.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
BRIEFS="$REPO/evals/rule-precision/round-24/briefs"
R17="$REPO/evals/rule-precision/round-17/briefs"
RENDER="$BRIEFS/render.py"

setup() {
  export OUT
  OUT="$(mktemp -d)"
}

teardown() {
  rm -rf "$OUT"
}

render_all() {
  run python3 "$RENDER" --out "$OUT" \
    --cat-w /sandbox/cat-W --cat-n /sandbox/cat-N \
    --inventory /sandbox/seed-claims.tsv --n-claims 94 \
    --bridge-claims /sandbox/bridge.tsv --n-bridge 24 "$@"
}

@test "rendering leaves no template slot behind" {
  render_all
  [ "$status" -eq 0 ]
  run grep -rlE '\{[A-Z_]+\}' "$OUT"
  [ "$status" -ne 0 ]
}

@test "a claim file without its row count is refused rather than rendered" {
  render_all --new-claims /sandbox/new.tsv
  [ "$status" -ne 0 ]
  [[ "$output" == *"without its row count"* ]]
  [ ! -f "$OUT/adjudicate-new.md" ]
}

@test "an unsubstituted slot is a hard error, not a warning" {
  cp "$BRIEFS/review.template.md" "$OUT/broken.template.md"
  printf '\nleftover {NOT_A_REAL_SLOT}\n' >> "$OUT/broken.template.md"
  run python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location('r', '$RENDER')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.render('$OUT/broken.template.md', {'FIXTURE': 'f', 'REPO': 'r', 'CAT': 'c'},
         '$OUT/broken.md')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT_A_REAL_SLOT"* ]]
}

@test "W and N differ in the catalogue path and nothing else" {
  render_all
  [ "$status" -eq 0 ]
  run diff <(sed 's|/sandbox/cat-W|<CAT>|g' "$OUT/brief-W.md") \
           <(sed 's|/sandbox/cat-N|<CAT>|g' "$OUT/brief-N.md")
  [ "$status" -eq 0 ]
}

@test "the review template round-trips byte-exactly to round 17's brief-W" {
  local r17cat='/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/e392c887-68cf-492b-a61c-d5d0f9838aa9/scratchpad/r17/cat-W'
  run python3 "$RENDER" --out "$OUT" \
    --cat-w "$r17cat" --cat-n "$r17cat" \
    --inventory /sandbox/i.tsv --n-claims 94
  [ "$status" -eq 0 ]
  run diff "$OUT/brief-W.md" "$R17/brief-W.md"
  [ "$status" -eq 0 ]
}

@test "the cluster template round-trips to round 17's, up to the 89/64 slot" {
  local r17inv='/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/e392c887-68cf-492b-a61c-d5d0f9838aa9/scratchpad/r17/seed-claims.tsv'
  run python3 "$RENDER" --out "$OUT" \
    --cat-w /x --cat-n /x --inventory "$r17inv" --n-claims 64
  [ "$status" -eq 0 ]
  # Round 17's own brief says "89 claims" here and "the 64 existing claims"
  # twice below; unifying those into one slot is the single intended change.
  run diff "$OUT/brief-cluster.md" "$R17/brief-cluster.md"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 2 ]
  [[ "$output" == *"89 claims already recorded"* ]]
  [[ "$output" == *"64 claims already recorded"* ]]
}

@test "the printed template hashes are the ones the protocol pins" {
  render_all
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git -C "$REPO" hash-object "$BRIEFS/review.template.md")"* ]]
  [[ "$output" == *"$(git -C "$REPO" hash-object "$BRIEFS/cluster.template.md")"* ]]
}
