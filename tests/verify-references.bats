#!/usr/bin/env bats
# Tests for hooks/verify-references.sh
# Uses --root to point at an ephemeral fixture tree so tests never read real repo files.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/verify-references.sh"

setup() {
  export ROOT_DIR SANDBOX_DIR
  # ROOT is nested one level inside the sandbox, so tests needing a path
  # OUTSIDE ROOT can use "$ROOT_DIR/.." without reaching into shared /tmp —
  # teardown then reclaims those fixtures too, even when a test fails before
  # its own cleanup line.
  SANDBOX_DIR="$(mktemp -d)"
  ROOT_DIR="$SANDBOX_DIR/root"
  mkdir -p "$ROOT_DIR/src" "$ROOT_DIR/lib"
  printf 'a\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"     # 5 lines
  printf '%s\n' one two three > "$ROOT_DIR/lib/bar.py"    # 3 lines
}

teardown() {
  rm -rf "$SANDBOX_DIR"
}

@test "empty stdin: reports total=0" {
  run bash -c "echo -n '' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=0"* ]]
}

@test "valid reference in range: reported as OK" {
  run bash -c "echo 'See src/foo.ts:3 for details.' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"src/foo.ts:3"* ]]
  [[ "$output" == *"total=1, ok=1, issues=0"* ]]
}

@test "nonexistent file: reported as MISSING" {
  run bash -c "echo 'check src/gone.ts:10' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]]
  [[ "$output" == *"src/gone.ts:10"* ]]
  [[ "$output" == *"total=1, ok=0, issues=1"* ]]
}

@test "out-of-range line: reported as OUT-OF-RANGE" {
  run bash -c "echo 'src/foo.ts:9999' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-RANGE"* ]]
  [[ "$output" == *"src/foo.ts:9999"* ]]
  [[ "$output" == *"file has 5 lines"* ]]
}

@test "range reference (start-end): verifies start line only" {
  run bash -c "echo 'src/foo.ts:2-4' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"src/foo.ts:2-4"* ]]
}

@test "non-filesystem refs (bare words): skipped" {
  # 'localhost:8080' and 'http:3000' should not be treated as file refs
  run bash -c "echo 'localhost:8080 and http:3000 are URIs, src/foo.ts:1 is a file' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1"* ]]
  [[ "$output" == *"src/foo.ts:1"* ]]
}

@test "duplicate refs: deduplicated" {
  run bash -c "printf 'src/foo.ts:1\nsrc/foo.ts:1\nsrc/foo.ts:1\n' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1"* ]]
}

@test "mixed refs: summary counts each category" {
  run bash -c "printf 'src/foo.ts:1\nsrc/gone.ts:5\nlib/bar.py:999\n' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=3, ok=1, issues=2"* ]]
}

@test "unknown flag: exits 1" {
  run bash "$SCRIPT" --bogus arg
  [ "$status" -eq 1 ]
}

@test "--help: prints usage to stderr and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h short flag: prints usage and exits 0" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "nonexistent ROOT: exits 1" {
  run bash "$SCRIPT" --root "$ROOT_DIR/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# Containment checks (S1 regression guards): traversal, absolute-path escape,
# and symlink escape must all resolve to OUT-OF-ROOT, NOT leak file metadata.
# ---------------------------------------------------------------------------

@test "traversal (../): reported as OUT-OF-ROOT, no file metadata leaked" {
  # Create a sibling file the traversal would reach if unchecked.
  echo "sensitive-content" > "$ROOT_DIR/../escape-target.txt"
  run bash -c "echo '../escape-target.txt:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" == *"../escape-target.txt:1"* ]]
  # Explicitly must NOT report OK / OUT-OF-RANGE / file metadata.
  [[ "$output" != *"OK "* ]]
  [[ "$output" != *"OUT-OF-RANGE"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/../escape-target.txt"
}

@test "absolute path outside ROOT: reported as OUT-OF-ROOT" {
  run bash -c "echo '/etc/hostname:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" == *"/etc/hostname:1"* ]]
  [[ "$output" != *"file has "* ]]
}

@test "absolute path inside ROOT: reported as OK" {
  # CLAUDE.md instructs sub-agents to share absolute paths; conforming refs
  # must verify correctly (F1 regression guard).
  run bash -c "echo '$ROOT_DIR/src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"$ROOT_DIR/src/foo.ts:3"* ]]
}

@test "symlink escaping ROOT: reported as OUT-OF-ROOT" {
  # Create a symlink inside ROOT that points to a file outside ROOT.
  echo "outside-content-line1" > "$ROOT_DIR/../outside-secret.txt"
  ln -sf "$ROOT_DIR/../outside-secret.txt" "$ROOT_DIR/src/link.ts"
  run bash -c "echo 'src/link.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/../outside-secret.txt" "$ROOT_DIR/src/link.ts"
}

@test "symlink CHAIN escaping ROOT: reported as OUT-OF-ROOT" {
  # Two links planted inside ROOT: A -> B (both inside) -> target outside.
  # A one-hop resolution clears this because A's immediate target still sits
  # inside ROOT — the escape only shows up when the whole chain is chased.
  echo "outside-content-line1" > "$ROOT_DIR/../outside-chained.txt"
  ln -sf "$ROOT_DIR/../outside-chained.txt" "$ROOT_DIR/src/hop2.ts"
  ln -sf "$ROOT_DIR/src/hop2.ts" "$ROOT_DIR/src/hop1.ts"
  run bash -c "echo 'src/hop1.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/../outside-chained.txt" "$ROOT_DIR/src/hop2.ts" "$ROOT_DIR/src/hop1.ts"
}

@test "relative symlink target resolving inside ROOT: reported as OK" {
  # Relative target (no leading /) exercises the dirname-join branch, which the
  # absolute-target cases never reach. The target must be a real IN-ROOT file:
  # an escaping relative target would report OUT-OF-ROOT even with the join
  # broken, because a bare relative path then resolves against the working
  # directory (also outside ROOT) — so only the in-ROOT direction distinguishes
  # a working join from a broken one.
  ln -sf "foo.ts" "$ROOT_DIR/src/rel-inside.ts"
  run bash -c "echo 'src/rel-inside.ts:2' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"MISSING"* ]]
  rm -f "$ROOT_DIR/src/rel-inside.ts"
}

@test "symlink chain longer than the hop cap: fails closed, no metadata leak" {
  # The cap stops the walk on an in-ROOT link, so containment passes — and the
  # kernel then follows the remaining hops for `-f` and `wc -l`, leaking the
  # outside file's line count. Only refusing the reference outright closes it.
  # The cycle case does NOT cover this: a cycle is dangling, so `-f` fails and
  # the leftover path looks safe.
  mkdir -p "$ROOT_DIR/../outside-deep"
  printf '1\n2\n3\n4\n5\n6\n7\n' > "$ROOT_DIR/../outside-deep/secret.ts"
  ln -sf "$ROOT_DIR/../outside-deep/secret.ts" "$ROOT_DIR/src/L40.ts"
  for i in $(seq 39 -1 0); do
    ln -sf "$ROOT_DIR/src/L$((i + 1)).ts" "$ROOT_DIR/src/L$i.ts"
  done
  run bash -c "printf 'src/L0.ts:1\nsrc/L0.ts:999\n' | bash '$SCRIPT' --root '$ROOT_DIR'"
  rm -rf "$ROOT_DIR/../outside-deep"
  rm -f "$ROOT_DIR"/src/L*.ts
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK "* ]]
  [[ "$output" != *"file has "* ]]
}

@test "symlink cycle: terminates and fails closed as MISSING" {
  # A -> B -> A never stops being a symlink; the hop cap must end the walk and
  # refuse the path rather than spinning or accepting the in-ROOT link itself.
  ln -sf "$ROOT_DIR/src/cycB.ts" "$ROOT_DIR/src/cycA.ts"
  ln -sf "$ROOT_DIR/src/cycA.ts" "$ROOT_DIR/src/cycB.ts"
  # `timeout` so a missing cap reports RED here instead of wedging the suite —
  # an unbounded walk would otherwise hang CI rather than fail it.
  run bash -c "echo 'src/cycA.ts:1' | timeout 30 bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]]
  [[ "$output" != *"OK "* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/src/cycA.ts" "$ROOT_DIR/src/cycB.ts"
}

@test "dangling symlink pointing outside ROOT: reported as OUT-OF-ROOT" {
  # Target does not exist but its parent does, so the chain still canonicalizes
  # to an out-of-ROOT path — containment decides it, not existence.
  ln -sf "$ROOT_DIR/../outside-absent.txt" "$ROOT_DIR/src/dangle-out.ts"
  run bash -c "echo 'src/dangle-out.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" != *"file has "* ]]
  rm -f "$ROOT_DIR/src/dangle-out.ts"
}

@test "dangling symlink pointing inside ROOT: reported as MISSING" {
  # Contained but absent — passes containment, fails the existence check.
  ln -sf "$ROOT_DIR/src/never-created.ts" "$ROOT_DIR/src/dangle-in.ts"
  run bash -c "echo 'src/dangle-in.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISSING"* ]]
  rm -f "$ROOT_DIR/src/dangle-in.ts"
}

@test "reference THROUGH a symlinked directory escaping ROOT: reported as OUT-OF-ROOT" {
  # A symlinked DIRECTORY component mid-path, not a symlink leaf: the escape
  # happens during the parent-directory `cd -P`, before the leaf loop runs.
  # Distinct from the leaf cases — the referenced basename is a regular file.
  mkdir -p "$ROOT_DIR/../outside-dir"
  echo "secret" > "$ROOT_DIR/../outside-dir/secret.ts"
  ln -sf "$ROOT_DIR/../outside-dir" "$ROOT_DIR/src/dirlink"
  run bash -c "echo 'src/dirlink/secret.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  rm -rf "$ROOT_DIR/../outside-dir" "$ROOT_DIR/src/dirlink"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUT-OF-ROOT"* ]]
  [[ "$output" != *"file has "* ]]
}

@test "--root / : paths under the filesystem root are not all refused" {
  # `pwd -P` yields "/" for the filesystem root, which makes the containment
  # pattern "//"* — matching nothing, so every path is refused including ones
  # genuinely inside ROOT. Fails closed, but wrong.
  run bash -c "echo '$ROOT_DIR/src/foo.ts:1' | bash '$SCRIPT' --root /"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"OUT-OF-ROOT"* ]]
}

@test "symlink inside ROOT: reported as OK" {
  # Symlinks that stay within ROOT are legitimate (e.g., monorepo aliases).
  ln -sf "$ROOT_DIR/src/foo.ts" "$ROOT_DIR/lib/alias.ts"
  run bash -c "echo 'lib/alias.ts:2' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -f "$ROOT_DIR/lib/alias.ts"
}

@test "traversal via '/../': reported as OUT-OF-ROOT" {
  # Sneakier form — path with interior `..` segment.
  run bash -c "echo 'src/../../escape.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  # Either OUT-OF-ROOT (resolved and rejected) or skipped (regex filter).
  # Both are safe outcomes; the critical invariant is no file metadata leak.
  [[ "$output" != *"file has "* ]]
}

# ---------------------------------------------------------------------------
# --base: citation ROT. Existence and line-count are both blind to a cited line
# whose text moved out from under the sentence, which is how a document that was
# accurate when written becomes false without any edit to the document itself.
# ---------------------------------------------------------------------------

# Commits the current ROOT_DIR tree and echoes the commit. Config is passed per
# invocation so the fixture does not depend on — or write to — the machine's
# git identity, and signing is forced off so a globally-signed setup cannot make
# these tests fail for a reason unrelated to what they assert.
git_fixture_commit() {
  git -C "$ROOT_DIR" -c user.email=t@example.invalid -c user.name=t \
      -c commit.gpgsign=false -c gpg.format=openpgp "$@" >/dev/null
}

setup_git_root() {
  git -C "$ROOT_DIR" init -q .
  git -C "$ROOT_DIR" add -A
  git_fixture_commit commit -qm base
  git -C "$ROOT_DIR" rev-parse HEAD
}

@test "--base: cited line whose text moved is reported SHIFTED" {
  base=$(setup_git_root)
  # Inserting a line at the top is the canonical rot: every ref below it now
  # names different text while still existing and still being in range.
  printf 'inserted\na\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SHIFTED"* ]]
  [[ "$output" == *"src/foo.ts:3"* ]]
  [[ "$output" == *"total=1, ok=0, issues=1, shifted=1"* ]]
}

@test "--base: cited line still holding its text in an edited file is OK" {
  # The allow-side counterpart. A gate that flagged every ref into every edited
  # file would fire on most refs of most rounds and be switched off; what makes
  # the report worth reading is that an edit elsewhere in the file is silent.
  base=$(setup_git_root)
  printf 'a\nb\nc\nd\nEEE\n' > "$ROOT_DIR/src/foo.ts"   # line 5 only
  run bash -c "echo 'src/foo.ts:2' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"SHIFTED"* ]]
  [[ "$output" == *"total=1, ok=1, issues=0, shifted=0"* ]]
}

@test "--base: ref into a file the branch never touched is OK" {
  base=$(setup_git_root)
  printf 'a\nb\nc\nd\nEEE\n' > "$ROOT_DIR/src/foo.ts"
  run bash -c "echo 'lib/bar.py:2' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"SHIFTED"* ]]
}

@test "--base: ref into a file that did not exist at base is OK, not SHIFTED" {
  # Nothing it once pointed at can have moved. Reporting these would make every
  # citation into new code an issue.
  base=$(setup_git_root)
  printf 'new1\nnew2\n' > "$ROOT_DIR/src/added.ts"
  run bash -c "echo 'src/added.ts:1' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"SHIFTED"* ]]
}

@test "--base: an UNCOMMITTED edit that moves the line is SHIFTED" {
  # Base-to-worktree, not base-to-HEAD. The gate runs at the moment fixes land,
  # and a fix still sitting in the worktree has already invalidated the prose.
  base=$(setup_git_root)
  printf 'x\ny\nz\n' > "$ROOT_DIR/src/foo.ts"
  # Deliberately NOT committed.
  run bash -c "echo 'src/foo.ts:2' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SHIFTED"* ]]
}

@test "--base without --strict keeps the advisory exit 0" {
  base=$(setup_git_root)
  printf 'inserted\na\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SHIFTED"* ]]
}

@test "--strict: a shifted ref exits 1" {
  base=$(setup_git_root)
  printf 'inserted\na\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base' --strict"
  [ "$status" -eq 1 ]
  [[ "$output" == *"shifted=1"* ]]
}

@test "--strict: a clean run exits 0" {
  # Paired with the case above so the exit code is shown to discriminate rather
  # than to be 1 for any reason.
  base=$(setup_git_root)
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base '$base' --strict"
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1, ok=1, issues=0, shifted=0"* ]]
}

@test "--strict: a MISSING ref exits 1 even without --base" {
  run bash -c "echo 'src/gone.ts:10' | bash '$SCRIPT' --root '$ROOT_DIR' --strict"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "without --base, a moved line is still reported OK" {
  # The rot check is what --base buys; the advisory caller's behaviour is
  # unchanged. If this ever reports SHIFTED, the flag stopped gating anything.
  base=$(setup_git_root)
  printf 'inserted\na\nb\nc\nd\ne\n' > "$ROOT_DIR/src/foo.ts"
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"SHIFTED"* ]]
}

@test "--base naming no commit: exits 1 rather than reporting everything OK" {
  # Fail closed. A comparison that silently never ran prints the same clean
  # report as one that ran and found nothing — the false green this flag exists
  # to remove.
  setup_git_root
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base no-such-ref"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not name a commit"* ]]
  [[ "$output" != *"OK "* ]]
}

@test "--base beginning with a dash: refused before it reaches git" {
  setup_git_root
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base --upload-pack=x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an option"* ]]
}

@test "--base outside a git repository: exits 1" {
  # ROOT_DIR is deliberately left un-inited here.
  run bash -c "echo 'src/foo.ts:3' | bash '$SCRIPT' --root '$ROOT_DIR' --base HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}
