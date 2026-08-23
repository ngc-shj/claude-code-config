#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/measure.py
#
# Round 24's analysis is committed before its data exists, which means every
# decision it encodes — the confirmatory rule, the three-way-split tie-break, the
# n >= 11 design-integrity floor, the pinned bridge sample — is a gate that has
# never fired. A gate nobody has seen fire reports PASS by never running, so each
# one is exercised here on synthetic input, with the mutation that should flip it.
#
# Fixtures are built in an ephemeral tree whose round-16 and round-17 are symlinks
# to the real frozen material: those two ARE the measurement standard and the
# script is supposed to read them unchanged.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RP="$REPO/evals/rule-precision"

setup() {
  export SANDBOX TREE R24 ND
  SANDBOX="$(mktemp -d)"
  TREE="$SANDBOX/rule-precision"
  R24="$TREE/round-24"
  mkdir -p "$TREE"
  ln -s "$RP/round-16" "$TREE/round-16"
  ln -s "$RP/round-17" "$TREE/round-17"

  # `not-a-defect` cluster ids from the frozen inventory: the synthetic findings
  # point at real claims so the verdict lookup exercises the real standard.
  ND="$SANDBOX/nd.txt"
  python3 -c "
import importlib.util
s = importlib.util.spec_from_file_location('m', '$RP/round-24/measure.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
v = m.frozen()
print('\n'.join(sorted(c for c, x in v.items() if x == 'not-a-defect')))" > "$ND"
}

teardown() {
  rm -rf "$SANDBOX"
}

# build <n_reviews> <W findings/review> <N findings/review> [split]
#
# Counts vary by review index so neither arm is constant — a constant arm is its
# own pre-registered edge case and is covered separately below.
build() {
  local n=$1 w=$2 nn=$3 split=${4:-}
  rm -rf "$R24"
  mkdir -p "$R24/adjudications"
  cp "$RP/round-24/measure.py" "$RP/round-24/bridge-sample.tsv" "$R24/"

  python3 - "$n" "$w" "$nn" "$split" "$ND" "$R24" <<'PY'
import sys
n, w, nn, split, ndpath, out = sys.argv[1:]
n, w, nn = int(n), int(w), int(nn)
nd = [x.strip() for x in open(ndpath) if x.strip()]

findings, members = [], []
fid = 0
for r in range(1, n + 1):
    for arm in ('W', 'N'):
        k = (w if arm == 'W' else nn) + r % 3
        for _ in range(k):
            fid += 1
            name = 'F%04d' % fid
            findings.append((name, arm, r))
            members.append((name, nd[fid % len(nd)]))
if split:
    findings.append(('F9999', 'W', 1))

with open(out + '/findings.tsv', 'w') as f:
    f.write('id\tarm\treview\tseverity\ttitle\n')
    for name, arm, r in findings:
        f.write(f'{name}\t{arm}\t{r}\tMajor\tt\n')

by = {}
for name, cid in members:
    by.setdefault(cid, []).append(name)
with open(out + '/clusters.tsv', 'w') as f:
    f.write('cluster_id\tstatus\tn\tmember_ids\tclaim\n')
    for cid, ids in sorted(by.items()):
        f.write(f'{cid}\texisting\t{len(ids)}\t{",".join(ids)}\tc\n')
    if split:
        f.write('NEW24-01\tnew\t1\tF9999\tsynthetic new claim\n')

verdicts = ('real', 'not-a-defect', 'wrong') if split else ()
for i in range(1, 4):
    with open(f'{out}/adjudications/a{i}.tsv', 'w') as f:
        f.write('cluster_id\tverdict\n')
        if split:
            f.write(f'NEW24-01\t{verdicts[i - 1]}\n')
PY
}

run_measure() { run python3 "$R24/measure.py" "$@"; }

@test "n=12 with an arm difference: the confirmatory rule fires" {
  build 12 1 4
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"n = 12 per arm"* ]]
  [[ "$output" == *"FIRES"* ]]
  [[ "$output" == *"CONFIRMED on F10"* ]]
}

@test "mutation: no arm difference leaves the interval across zero" {
  build 12 4 4
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"Does not fire"* ]]
  [[ "$output" != *"FIRES"* ]]
}

@test "mutation: the effect reversed is reported as the opposite direction" {
  build 12 4 1
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"opposite direction"* ]]
  [[ "$output" != *"FIRES"* ]]
}

@test "a three-way adjudicator split blocks the arm table until it is resolved" {
  build 12 1 4 split
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"without a tie-break verdict"* ]]
  [[ "$output" != *"PRIMARY"* ]]
}

@test "--splits names the claim the tie-break pass must judge" {
  build 12 1 4 split
  run_measure --splits
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW24-01"* ]]
}

@test "the arm table computes once the tie-break verdict exists" {
  build 12 1 4 split
  printf 'cluster_id\tverdict\nNEW24-01\tnot-a-defect\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIRES"* ]]
}

@test "the tie-break verdict changes the primary, so sheet order must not decide it" {
  # F9999 is a W-arm Critical/Major finding on the split claim: judged
  # `not-a-defect` it joins the primary, judged `real` it does not. Round 17's
  # Counter tie-break would have settled this by adjudication filename.
  build 12 1 4 split
  printf 'cluster_id\tverdict\nNEW24-01\tnot-a-defect\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -eq 0 ]
  as_nd="$(printf '%s\n' "$output" | grep 'per-review primary')"

  printf 'cluster_id\tverdict\nNEW24-01\treal\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -eq 0 ]
  as_real="$(printf '%s\n' "$output" | grep 'per-review primary')"

  [ "$as_nd" != "$as_real" ]
}

@test "n below the floor is descriptive only and the rule is not applied" {
  build 10 1 4
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"DESCRIPTIVE ONLY"* ]]
  [[ "$output" == *"NOT APPLIED"* ]]
  [[ "$output" != *"FIRES"* ]]
}

@test "n=11 is still analysed exactly as registered" {
  build 11 1 4
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" != *"DESCRIPTIVE ONLY"* ]]
  [[ "$output" == *"FIRES"* ]]
}

@test "both arms constant: the point interval is reported, never fired on" {
  build 12 1 4
  # strip the per-review variation so every review carries the same count
  python3 - "$R24" <<'PY'
import sys
out = sys.argv[1]
rows = [l.rstrip('\n').split('\t') for l in open(out + '/findings.tsv')]
head, body = rows[0], rows[1:]
keep, seen = [], {}
for r in body:
    k = (r[1], r[2])
    seen[k] = seen.get(k, 0) + 1
    if seen[k] <= (1 if r[1] == 'W' else 4):
        keep.append(r)
with open(out + '/findings.tsv', 'w') as f:
    f.write('\t'.join(head) + '\n')
    for r in keep:
        f.write('\t'.join(r) + '\n')
PY
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"both arms are constant"* ]]
  [[ "$output" != *"FIRES"* ]]
}

@test "--bridge-sample is deterministic and matches the committed file" {
  build 12 1 4
  emitted="$SANDBOX/emitted.tsv"
  python3 "$R24/measure.py" --bridge-sample 2>/dev/null | tail -n +4 > "$emitted"
  run diff "$emitted" "$RP/round-24/bridge-sample.tsv"
  [ "$status" -eq 0 ]
}

@test "--bridge-sample draws the pre-registered strata, 15/7/2" {
  build 12 1 4
  body="$SANDBOX/body.tsv"
  python3 "$R24/measure.py" --bridge-sample 2>/dev/null | tail -n +5 > "$body"
  [ "$(grep -c $'\treal$' "$body")" -eq 15 ]
  [ "$(grep -c $'\tnot-a-defect$' "$body")" -eq 7 ]
  [ "$(grep -c $'\twrong$' "$body")" -eq 2 ]
  [ "$(wc -l < "$body")" -eq 24 ]
}

@test "a bridge sample that no longer matches the sampler is refused" {
  build 12 1 4
  mkdir -p "$R24/bridge"
  printf 'cluster_id\tverdict\n' > "$R24/bridge/panel-1.tsv"
  sed -i '2s/^[A-Za-z0-9-]*/DELIVERY-01/' "$R24/bridge-sample.tsv"
  run_measure --bridge
  [ "$status" -ne 0 ]
  [[ "$output" == *"no longer matches"* ]]
}

@test "the frozen inventory the round measures against is 94 claims, 64/28/2" {
  build 12 1 4
  run_measure --bridge-sample
  [ "$status" -eq 0 ]
  [[ "$output" == *"94 claims"* ]]
  [[ "$output" == *"64 real"* ]]
  [[ "$output" == *"28 not-a-defect"* ]]
  [[ "$output" == *"2 wrong"* ]]
}
