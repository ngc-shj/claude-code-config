#!/usr/bin/env bats
# Tests for evals/rule-precision/split_clusters.py
# Every fixture is built in an ephemeral tree, so no test reads a real round.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/evals/rule-precision/split_clusters.py"

setup() {
  export SANDBOX OUT DIFF FINDINGS
  SANDBOX="$(mktemp -d)"
  OUT="$SANDBOX/out"
  DIFF="$SANDBOX/fixture.diff"
  FINDINGS="$SANDBOX/findings.tsv"

  # A Go change plus a SQL migration: the Go paths are the ones extract.py's
  # extension whitelist cannot see, which is the gap this script exists to close.
  cat > "$DIFF" <<'EOF'
diff --git a/internal/exports/worker.go b/internal/exports/worker.go
new file mode 100644
--- /dev/null
+++ b/internal/exports/worker.go
@@ -0,0 +1,2 @@
+package exports
+func run() {}
diff --git a/internal/exports/model.go b/internal/exports/model.go
new file mode 100644
--- /dev/null
+++ b/internal/exports/model.go
@@ -0,0 +1,1 @@
+package exports
diff --git a/migrations/0057_export.sql b/migrations/0057_export.sql
new file mode 100644
--- /dev/null
+++ b/migrations/0057_export.sql
@@ -0,0 +1,1 @@
+CREATE TABLE t (id INT);
EOF
}

teardown() {
  rm -rf "$SANDBOX"
}

# Writes a findings.tsv whose rows are the File: fields passed as arguments.
write_findings() {
  printf 'id\tarm\treview\tpart\tseverity\ttarget\tfile\ttitle\twhat_is_wrong\n' > "$FINDINGS"
  local i=0
  for field in "$@"; do
    i=$((i + 1))
    printf 'F%04d\tW\t1\ta\tMajor\t(other)\t%s\ttitle %d\twrong %d\n' "$i" "$field" "$i" "$i" >> "$FINDINGS"
  done
}

@test "a Go finding lands in its own file's bucket, not in a catch-all" {
  write_findings 'internal/exports/worker.go — Worker.tick'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ -f "$OUT/internal_exports_worker_go.tsv" ]
  [ "$(tail -n +2 "$OUT/internal_exports_worker_go.tsv" | wc -l)" -eq 1 ]
  [ ! -f "$OUT/unassigned.tsv" ]
}

@test "a backticked basename with no directory still finds its changed file" {
  write_findings '`model.go` — the Store type'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ "$(tail -n +2 "$OUT/internal_exports_model_go.tsv" | wc -l)" -eq 1 ]
}

@test "a finding naming several changed files goes to the one it names first" {
  write_findings 'internal/exports/model.go — Store.Due; internal/exports/worker.go — tick'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ "$(tail -n +2 "$OUT/internal_exports_model_go.tsv" | wc -l)" -eq 1 ]
  [ ! -f "$OUT/internal_exports_worker_go.tsv" ]
}

@test "a finding naming no changed file is kept in unassigned, not dropped" {
  write_findings 'some/file/the/diff/never/touched.rb — nothing'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ "$(tail -n +2 "$OUT/unassigned.tsv" | wc -l)" -eq 1 ]
  [[ "$output" == *"named no changed file"* ]]
}

@test "every finding lands in exactly one bucket and none is lost" {
  write_findings \
    'internal/exports/worker.go — a' \
    'internal/exports/worker.go — b' \
    'internal/exports/model.go — c' \
    'migrations/0057_export.sql — d' \
    'unrelated.rb — e'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 findings over 4 files"* ]]
  total=$(cat "$OUT"/*.tsv | grep -c '^F[0-9]')
  [ "$total" -eq 5 ]
  ids=$(cat "$OUT"/*.tsv | grep -o '^F[0-9]*' | sort | uniq -d)
  [ -z "$ids" ]
}

@test "the split key comes from the diff, so a new extension needs no code change" {
  # .rb appears in no whitelist anywhere in this pipeline; it works because the
  # diff says it changed.
  cat > "$DIFF" <<'EOF'
diff --git a/app/exporter.rb b/app/exporter.rb
--- /dev/null
+++ b/app/exporter.rb
@@ -0,0 +1,1 @@
+class Exporter; end
EOF
  write_findings 'app/exporter.rb — Exporter#call'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ "$(tail -n +2 "$OUT/app_exporter_rb.tsv" | wc -l)" -eq 1 ]
  [ ! -f "$OUT/unassigned.tsv" ]
}

@test "/dev/null is not treated as a changed file" {
  write_findings 'internal/exports/worker.go — a'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  [ ! -f "$OUT/dev_null.tsv" ]
}

@test "a diff with no file headers exits 1 rather than writing an empty split" {
  printf 'this is not a diff\n' > "$DIFF"
  write_findings 'internal/exports/worker.go — a'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no changed files"* ]]
}

@test "wrong argument count exits 1 with usage" {
  run "$SCRIPT" "$FINDINGS" "$DIFF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"split_clusters.py"* ]]
}

@test "the output carries only the columns a clustering agent may see" {
  write_findings 'internal/exports/worker.go — a'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  # csv writes CRLF, which is what every round's TSV in this pipeline uses.
  header=$(head -1 "$OUT/internal_exports_worker_go.tsv" | tr -d '\r')
  [ "$header" = "$(printf 'id\tseverity\tfile\ttitle\twhat_is_wrong')" ]
  # the arm is the one column that must never reach a clustering agent
  ! grep -q $'\tW\t' "$OUT/internal_exports_worker_go.tsv"
}

@test "output keeps the pipeline's CRLF, so it reads back like every round's TSV" {
  write_findings 'internal/exports/worker.go — a'
  run "$SCRIPT" "$FINDINGS" "$DIFF" "$OUT"
  [ "$status" -eq 0 ]
  run grep -c $'\r$' "$OUT/internal_exports_worker_go.tsv"
  [ "$output" -eq 2 ]   # header + one finding
}
