#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/apply-merge.py
#
# Four cases decide where a finding ends up and which sentence the adjudication
# panel judges, so each is exercised on synthetic input rather than inferred from
# the real run: keep, new -> new, new -> existing, and the chain the applier must
# refuse. The real round's own output is never read here.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
R24="$REPO/evals/rule-precision/round-24"

setup() {
  export SANDBOX WORK
  SANDBOX="$(mktemp -d)"
  WORK="$SANDBOX/round-24"
  mkdir -p "$WORK" "$SANDBOX/clusters"
  cp "$R24/apply-merge.py" "$WORK/"

  # inventory: two recorded claims, with text the applier must copy verbatim
  { printf 'cluster_id\tclaim\n'
    printf 'OLD-01\tthe recorded sentence for OLD-01\n'
    printf 'OLD-02\tthe recorded sentence for OLD-02\n'
  } > "$WORK/cluster-inventory.tsv"

  { printf 'target\tpacket\tprefix\toutput\n'
    printf 'a.py\t%s\tR24A\t%s\n' "$SANDBOX/p1.tsv" "$SANDBOX/clusters/one.tsv"
  } > "$WORK/cluster-outputs.tsv"
}

teardown() {
  rm -rf "$SANDBOX"
}

# clusters <rows...>  — each row is "id|status|members|claim"
clusters() {
  { printf 'cluster_id\tstatus\tn\tmember_ids\tclaim\n'
    for r in "$@"; do
      IFS='|' read -r id st mem cl <<<"$r"
      n=$(awk -F, '{print NF}' <<<"$mem")
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$n" "$mem" "$cl"
    done
  } > "$SANDBOX/clusters/one.tsv"
}

# verdicts <rows...> — each row is "id|verdict|target"
verdicts() {
  { printf 'cluster_id\tverdict\ttarget\twhy\n'
    for r in "$@"; do
      IFS='|' read -r id v t <<<"$r"
      printf '%s\t%s\t%s\tbecause\n' "$id" "$v" "$t"
    done
  } > "$WORK/merge-verdicts.tsv"
}

findings() {
  { printf 'id\tarm\treview\tpart\tseverity\ttarget\tfile\ttitle\twhat_is_wrong\n'
    for i in "$@"; do
      printf '%s\tW\t1\ta\tMajor\ta.py\ta.py\tt\tw\n' "$i"
    done
  } > "$WORK/findings.tsv"
}

apply() { run python3 "$WORK/apply-merge.py" --root "$SANDBOX" --out-dir "$WORK"; }
field() { awk -F'\t' -v id="$2" -v c="$3" 'NR>1 && $1==id {print $c}' "$1"; }

@test "keep: a new claim that stands alone keeps its id, members and claim" {
  clusters 'R24A-01|new|F0001,F0002|the new sentence'
  verdicts 'R24A-01|keep|'
  findings F0001 F0002
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 2)" = new ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 4)" = 'F0001,F0002' ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 5)" = 'the new sentence' ]
}

@test "existing: id, status and the inventory's claim text are carried through" {
  clusters 'OLD-01|existing|F0001|the recorded sentence for OLD-01'
  verdicts
  findings F0001
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" OLD-01 2)" = existing ]
  [ "$(field "$WORK/clusters.tsv" OLD-01 5)" = 'the recorded sentence for OLD-01' ]
}

@test "existing: a reworded claim is replaced by the inventory's canonical text" {
  clusters 'OLD-01|existing|F0001|a REWORDED version of the recorded sentence'
  verdicts
  findings F0001
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" OLD-01 5)" = 'the recorded sentence for OLD-01' ]
}

@test "new -> new keep: members fold in and the TARGET's claim survives" {
  clusters 'R24A-01|new|F0001|the keep sentence' 'R24A-02|new|F0002,F0003|the merged-away sentence'
  verdicts 'R24A-01|keep|' 'R24A-02|merge|R24A-01'
  findings F0001 F0002 F0003
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 4)" = 'F0001,F0002,F0003' ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 5)" = 'the keep sentence' ]
  run grep -c 'R24A-02' "$WORK/clusters.tsv"
  [ "$output" = "0" ]
}

@test "new -> existing: members fold in and the INVENTORY's claim is used" {
  clusters 'OLD-02|existing|F0001|the recorded sentence for OLD-02' \
           'R24A-01|new|F0002|the new sentence that duplicates OLD-02'
  verdicts 'R24A-01|merge|OLD-02'
  findings F0001 F0002
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" OLD-02 2)" = existing ]
  [ "$(field "$WORK/clusters.tsv" OLD-02 4)" = 'F0001,F0002' ]
  [ "$(field "$WORK/clusters.tsv" OLD-02 5)" = 'the recorded sentence for OLD-02' ]
  run grep -c 'R24A-01' "$WORK/clusters.tsv"
  [ "$output" = "0" ]
}

@test "new -> existing works when the target has no existing row of its own" {
  clusters 'R24A-01|new|F0001,F0002|the new sentence that duplicates OLD-01'
  verdicts 'R24A-01|merge|OLD-01'
  findings F0001 F0002
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" OLD-01 2)" = existing ]
  [ "$(field "$WORK/clusters.tsv" OLD-01 5)" = 'the recorded sentence for OLD-01' ]
}

@test "a merge chain is refused rather than applied" {
  clusters 'R24A-01|new|F0001|one' 'R24A-02|new|F0002|two' 'R24A-03|new|F0003|three'
  verdicts 'R24A-01|keep|' 'R24A-02|merge|R24A-01' 'R24A-03|merge|R24A-02'
  findings F0001 F0002 F0003
  apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"chains are not"* ]]
}

@test "member ids are sorted, so the output is byte-reproducible" {
  clusters 'R24A-01|new|F0009,F0001,F0005|s'
  verdicts 'R24A-01|keep|'
  findings F0001 F0005 F0009
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 4)" = 'F0001,F0005,F0009' ]
  cp "$WORK/clusters.tsv" "$SANDBOX/first.tsv"
  apply
  run diff "$SANDBOX/first.tsv" "$WORK/clusters.tsv"
  [ "$status" -eq 0 ]
}

@test "a finding lost between findings.tsv and the clusters is caught" {
  clusters 'R24A-01|new|F0001|s'
  verdicts 'R24A-01|keep|'
  findings F0001 F0002
  apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"differ from findings.tsv"* ]]
}

@test "a finding claimed by two clusters is caught" {
  clusters 'R24A-01|new|F0001|one' 'R24A-02|new|F0001|two'
  verdicts 'R24A-01|keep|' 'R24A-02|keep|'
  findings F0001
  apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"more than one final cluster"* ]]
}

@test "the adjudication input is claim-only and covers exactly the keep set" {
  clusters 'OLD-01|existing|F0001|the recorded sentence for OLD-01' \
           'R24A-01|new|F0002|keeps' 'R24A-02|new|F0003|merges away'
  verdicts 'R24A-01|keep|' 'R24A-02|merge|R24A-01'
  findings F0001 F0002 F0003
  apply
  [ "$status" -eq 0 ]
  [ "$(head -1 "$WORK/adjudicate-input.tsv")" = "$(printf 'cluster_id\tclaim')" ]
  [ "$(tail -n +2 "$WORK/adjudicate-input.tsv" | cut -f1 | tr '\n' ' ')" = "R24A-01 " ]
  run grep -c 'OLD-01' "$WORK/adjudicate-input.tsv"
  [ "$output" = "0" ]
  [ "$(awk -F'\t' 'NR>1{print NF}' "$WORK/adjudicate-input.tsv" | sort -u)" = "2" ]
}

@test "no unregistered exclusion: a one-member cluster survives" {
  clusters 'R24A-01|new|F0001|a singleton claim' 'R24A-02|new|F0002,F0003|a bigger one'
  verdicts 'R24A-01|keep|' 'R24A-02|keep|'
  findings F0001 F0002 F0003
  apply
  [ "$status" -eq 0 ]
  [ "$(field "$WORK/clusters.tsv" R24A-01 3)" = 1 ]
  run grep -c 'R24A-01' "$WORK/adjudicate-input.tsv"
  [ "$output" = "1" ]
}
