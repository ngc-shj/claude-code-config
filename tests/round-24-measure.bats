#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/measure.py
#
# Round 24's analysis is committed before its data exists, which means every
# decision it encodes — the confirmatory rule, the n >= 11 design-integrity
# floor, the three-way-split tie-break, the sheet-completeness checks, the pinned
# bridge sample — is a gate that has never fired. A gate nobody has seen fire
# reports PASS by never running, so each is exercised here on synthetic input,
# with the mutation that should flip it.
#
# Fixtures are built in an ephemeral tree whose round-16 and round-17 are
# symlinks to the real frozen material: those two ARE the measurement standard
# and the script is supposed to read them unchanged.

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

# build <complete_reviews> <W findings/review> <N findings/review> [split]
#
# Reviews 1..complete_reviews are complete in both arms; the rest of 1..12 are
# void with a cause. Counts vary by index so neither arm is constant — a constant
# arm is its own pre-registered edge case, covered separately.
build() {
  local n=$1 w=$2 nn=$3 split=${4:-}
  rm -rf "$R24"
  mkdir -p "$R24/adjudications"
  cp "$RP/round-24/measure.py" "$RP/round-24/bridge-sample.tsv" \
     "$RP/round-24/bridge-input.tsv" "$R24/"

  python3 - "$n" "$w" "$nn" "$split" "$ND" "$R24" <<'PY'
import sys
n, w, nn, split, ndpath, out = sys.argv[1:]
n, w, nn = int(n), int(w), int(nn)
nd = [x.strip() for x in open(ndpath) if x.strip()]

with open(out + '/reviews.tsv', 'w') as f:
    f.write('review\tarm\tstatus\tcause\n')
    for r in range(1, 13):
        for arm in ('W', 'N'):
            if r <= n:
                f.write(f'{r}\t{arm}\tcomplete\t\n')
            else:
                f.write(f'{r}\t{arm}\tvoid\tsynthetic\n')

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

# ------------------------------------------------------- the confirmatory rule

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

@test "both arms constant: the point interval is reported, never fired on" {
  build 12 1 4
  python3 - "$R24" <<'PY'
import sys
out = sys.argv[1]
rows = [l.rstrip('\n').split('\t') for l in open(out + '/findings.tsv')]
head, body, keep, seen = rows[0], rows[1:], [], {}
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

@test "the critical value is the exact t quantile, not an expansion" {
  # df=10 -> 2.228139 in every published table. The Cornish-Fisher expansion an
  # earlier draft used returns 2.2254, anti-conservative in the fourth decimal.
  run python3 -c "
import importlib.util
s = importlib.util.spec_from_file_location('m', '$RP/round-24/measure.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
for df, ref in ((1, 12.706205), (10, 2.228139), (30, 2.042272), (1000, 1.962339)):
    assert abs(m.t_crit(df) - ref) < 1e-5, (df, m.t_crit(df), ref)
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ------------------------------------------------------------ the n manifest

@test "n comes from the manifest, so a review with no findings still counts" {
  build 12 1 4
  # strip every W finding on review 5: the review completed and found nothing
  python3 - "$R24" <<'PY'
import sys
out = sys.argv[1]
lines = open(out + '/findings.tsv').read().splitlines()
head, body = lines[0], lines[1:]
keep = [l for l in body if not (l.split('\t')[1] == 'W' and l.split('\t')[2] == '5')]
open(out + '/findings.tsv', 'w').write('\n'.join([head] + keep) + '\n')
PY
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"n = 12 per arm"* ]]
  # twelve values, the fifth of them zero — not eleven values
  [[ "$output" == *"per-review primary  W: [2, 3, 1, 2, 0, "* ]]
}

@test "an index outside 1..12 is refused rather than analysed" {
  build 12 1 4
  printf '13\tW\tcomplete\t\n' >> "$R24/reviews.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"not one of 1..12"* ]]
}

@test "arms disagreeing on which indices completed is refused" {
  build 12 1 4
  sed -i '0,/^7\tN\tcomplete/s//7\tN\tvoid\tlost/' "$R24/reviews.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"arms disagree"* ]]
}

@test "a manifest missing a registered index x arm pair is refused" {
  build 12 1 4
  sed -i '/^4\tN\t/d' "$R24/reviews.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected all 24 registered"* ]]
}

@test "a void index with no recorded cause is refused" {
  build 11 1 4
  sed -i 's/^12\tW\tvoid\tsynthetic/12\tW\tvoid\t/' "$R24/reviews.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"void with no cause"* ]]
}

@test "a finding on an index the manifest voided is refused" {
  build 11 1 4
  printf 'F8888\tW\t12\tMajor\tt\n' >> "$R24/findings.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest does not list as complete"* ]]
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
  [[ "$output" == *"void indices        12"* ]]
}

# ------------------------------------------------------------- adjudication

@test "a three-way adjudicator split blocks the arm table until it is resolved" {
  build 12 1 4 split
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tiebreak.tsv"* ]]
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
  build 12 1 4 split
  printf 'cluster_id\tverdict\nNEW24-01\tnot-a-defect\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -eq 0 ]
  as_nd="$(printf '%s\n' "$output" | grep 'per-review primary')"
  printf 'cluster_id\tverdict\nNEW24-01\treal\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -eq 0 ]
  [ "$as_nd" != "$(printf '%s\n' "$output" | grep 'per-review primary')" ]
}

@test "a tiebreak sheet naming a claim that did not split is refused" {
  build 12 1 4 split
  printf 'cluster_id\tverdict\nNEW24-01\treal\nNEW24-99\treal\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected"* ]]
}

@test "a tiebreak sheet with nothing to break is refused" {
  build 12 1 4
  printf 'cluster_id\tverdict\nNEW24-01\treal\n' > "$R24/tiebreak.tsv"
  run_measure
  [ "$status" -ne 0 ]
}

@test "two adjudication sheets instead of three is refused" {
  build 12 1 4 split
  rm "$R24/adjudications/a3.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 sheet(s)"* ]]
  [[ "$output" == *"expected 3"* ]]
}

@test "an adjudication sheet missing a new claim is refused" {
  build 12 1 4 split
  printf 'cluster_id\tverdict\n' > "$R24/adjudications/a2.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing: ['NEW24-01']"* ]]
}

@test "an adjudication sheet judging a claim that is not new is refused" {
  build 12 1 4 split
  printf 'NEW24-77\treal\n' >> "$R24/adjudications/a1.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected: ['NEW24-77']"* ]]
}

@test "a verdict outside the three-value space is refused" {
  build 12 1 4 split
  printf 'cluster_id\tverdict\nNEW24-01\tmaybe\n' > "$R24/adjudications/a1.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict 'maybe'"* ]]
}

@test "a duplicated cluster id inside one sheet is refused" {
  build 12 1 4 split
  printf 'NEW24-01\treal\n' >> "$R24/adjudications/a1.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"appears twice"* ]]
}

@test "no new claims: the round runs with no adjudication at all" {
  build 12 1 4
  rm -f "$R24"/adjudications/*.tsv
  run_measure
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0 added here)"* ]]
  [[ "$output" == *"FIRES"* ]]
}

@test "adjudication sheets with no new claims to judge are refused" {
  build 12 1 4
  printf 'cluster_id\tverdict\nX-1\treal\n' > "$R24/adjudications/a1.tsv"
  run_measure
  [ "$status" -ne 0 ]
  [[ "$output" == *"judges claims but clusters.tsv has no new claims"* ]]
}

# ------------------------------------------------------------------- bridge

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

@test "--bridge-input carries claim text and no verdict, in the pinned order" {
  build 12 1 4
  out="$SANDBOX/in.tsv"
  python3 "$R24/measure.py" --bridge-input 2>/dev/null > "$out"
  run diff "$out" "$RP/round-24/bridge-input.tsv"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$out")" = "$(printf 'cluster_id\tclaim')" ]
  [ "$(tail -n +2 "$out" | wc -l)" -eq 24 ]
  # the claim ids, in order, are the committed sample's
  run diff <(tail -n +2 "$out" | cut -f1) \
           <(tail -n +2 "$RP/round-24/bridge-sample.tsv" | cut -f1)
  [ "$status" -eq 0 ]
  # and no cell is one of the three verdicts
  run grep -cE $'\t(real|not-a-defect|wrong)$' "$out"
  [ "$status" -ne 0 ]
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

@test "bridge agreement reports all three numbers and excludes three-way splits" {
  build 12 1 4
  mkdir -p "$R24/bridge"
  python3 - "$R24" "$RP/round-24/bridge-sample.tsv" <<'PY'
import sys
out, sample = sys.argv[1], sys.argv[2]
rows = [l.rstrip('\n').split('\t') for l in open(sample)][1:]
other = {'real': 'not-a-defect', 'not-a-defect': 'wrong', 'wrong': 'real'}
third = {'real': 'wrong', 'not-a-defect': 'real', 'wrong': 'not-a-defect'}
for i in range(1, 4):
    with open(f'{out}/bridge/p{i}.tsv', 'w') as f:
        f.write('cluster_id\tverdict\n')
        for j, (cid, frozen) in enumerate(rows):
            if j == 0:                      # claim 0: a deliberate three-way split
                f.write(f'{cid}\t{(frozen, other[frozen], third[frozen])[i-1]}\n')
            elif j == 1:                    # claim 1: unanimous disagreement
                f.write(f'{cid}\t{other[frozen]}\n')
            else:
                f.write(f'{cid}\t{frozen}\n')
PY
  run_measure --bridge
  [ "$status" -eq 0 ]
  [[ "$output" == *"no majority (three-way) 1 of 24"* ]]
  [[ "$output" == *"excluded from the line above"* ]]
  # 24 claims, one split, one unanimous miss -> 22 of 23 majorities agree
  [[ "$output" == *"panel-majority verdicts 22/23"* ]]
  # individual: 72 judgements, minus 3 on the unanimous miss, minus 2 of the 3
  # on the split -> 67
  [[ "$output" == *"individual judgements   67/72"* ]]
}

@test "a bridge panel of two sheets is refused" {
  build 12 1 4
  mkdir -p "$R24/bridge"
  printf 'cluster_id\tverdict\n' > "$R24/bridge/p1.tsv"
  printf 'cluster_id\tverdict\n' > "$R24/bridge/p2.tsv"
  run_measure --bridge
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 sheet(s)"* ]]
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
