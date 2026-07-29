#!/usr/bin/env bats
#
# RT10 deny-only guard detector.
#
# Every deny case below is paired with the allow case that must stay silent
# — the detector is an RT10 tool, and a suite for it that only proved it
# fires would be the defect it exists to report.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/hooks/check-deny-only-guard.sh"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  echo seed > seed.txt
  git add -A >/dev/null
  git commit -qm seed
  BASE="$(git rev-parse HEAD)"
  mkdir -p tests
}

teardown() {
  cd /
  rm -rf "$WORK"
  rm -f /tmp/DOG_SED_INJECT_PROOF
  rm -f /tmp/DOG_TRAP_PROOF
}

commit_tests() {
  git add -A >/dev/null 2>&1
  git commit -qm changes >/dev/null 2>&1
}

deny_only_bats() {
  printf '@test "rejects" {\n  run bash ./g.sh bad\n  [ "$status" -eq 1 ]\n}\n' > "tests/$1"
}

paired_bats() {
  printf '@test "rejects" {\n  run bash ./g.sh bad\n  [ "$status" -eq 1 ]\n}\n@test "accepts" {\n  run bash ./g.sh good\n  [ "$status" -eq 0 ]\n}\n' > "tests/$1"
}

# --- bats status grammar ----------------------------------------------------

@test "bats status: deny-only file is flagged" {
  deny_only_bats guard.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/guard.bats"* ]]
  [[ "$output" == *"Total findings: 1"* ]]
}

@test "bats status: file with a paired allow case stays silent" {
  paired_bats guard.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "bats status: -ne 0 spelling is a deny alternative" {
  printf '@test "rejects" {\n  run bash ./g.sh bad\n  [ "$status" -ne 0 ]\n}\n' > tests/ne.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/ne.bats"* ]]
}

# --- hook decision grammar --------------------------------------------------

@test "hook decision: block-only file is flagged" {
  printf '@test "blocks" {\n  run bash ./h.sh\n  [[ "$output" == *'"'"'"decision":"block"'"'"'* ]]\n}\n' > tests/dec.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/dec.bats"* ]]
}

@test "hook decision: a paired approve assertion silences the file" {
  printf '@test "blocks" {\n  [[ "$output" == *'"'"'"decision":"block"'"'"'* ]]\n}\n@test "approves" {\n  [[ "$output" == *'"'"'"decision": "approve"'"'"'* ]]\n}\n' > tests/dec.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "hook decision: a negated approve assertion is scored deny, not allow" {
  # `!= *"decision": "approve"*` asserts the input was NOT approved. Scoring
  # the token without its operator would read this as an allow case and
  # silence a genuinely deny-only suite.
  printf '@test "not approved" {\n  [[ "$output" != *'"'"'"decision": "approve"'"'"'* ]]\n}\n' > tests/neg.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/neg.bats"* ]]
}

@test "hook decision: a negated block assertion is scored allow, not deny" {
  printf '@test "not blocked" {\n  [[ "$output" != *'"'"'"decision":"block"'"'"'* ]]\n}\n' > tests/negb.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

# --- Jest/Vitest grammar ----------------------------------------------------

@test "jest: throw-only file is flagged" {
  printf 'it("rejects", () => {\n  expect(() => parse("bad")).toThrow("nope");\n});\n' > tests/p.test.ts
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/p.test.ts"* ]]
}

@test "jest: an ordinary assertion elsewhere in the file silences it" {
  printf 'it("rejects", () => {\n  expect(() => parse("bad")).toThrow("nope");\n});\nit("accepts", () => {\n  expect(parse("good")).toEqual({ ok: true });\n});\n' > tests/p.test.ts
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "jest: a Prettier-wrapped deny assertion does not cancel itself" {
  # The bare `expect(` opener carries no matcher, so it must not score as an
  # allow line. Counting it would let every multi-line deny assertion
  # manufacture its own counterpart and the fire condition could never hold.
  printf 'it("rejects", async () => {\n  await expect(\n    send({ to: "x" }),\n  ).rejects.toThrow("nope");\n});\n' > tests/w.test.ts
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/w.test.ts"* ]]
}

@test "jest: .not.toThrow is an allow assertion, not a deny one" {
  printf 'it("accepts", () => {\n  expect(() => parse("good")).not.toThrow();\n});\n' > tests/n.test.ts
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

# --- diff scoping -----------------------------------------------------------

@test "a deny line outside the diff + set does not fire" {
  deny_only_bats old.bats
  commit_tests
  MID="$(git rev-parse HEAD)"
  echo "unrelated" > other.txt
  git add -A >/dev/null
  git commit -qm later >/dev/null
  run bash "$HOOK" "$MID"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "a changed file whose only + line is unrelated does not fire" {
  deny_only_bats live.bats
  commit_tests
  MID="$(git rev-parse HEAD)"
  printf '# note\n' | cat - tests/live.bats > tmp && mv tmp tests/live.bats
  git add -A >/dev/null
  git commit -qm comment >/dev/null
  run bash "$HOOK" "$MID"
  [[ "$output" == *"Total findings: 0"* ]]
}

# --- comment handling -------------------------------------------------------

@test "a commented-out allow assertion does not suppress a finding" {
  printf '@test "rejects" {\n  run bash ./g.sh bad\n  [ "$status" -eq 1 ]\n}\n# [ "$status" -eq 0 ]\n' > tests/c.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/c.bats"* ]]
}

@test "a commented-out deny assertion does not create a finding" {
  printf '@test "nothing" {\n  true\n}\n# [ "$status" -eq 1 ]\n' > tests/cd.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

# --- file classification ----------------------------------------------------

@test "a non-test JS path is not analyzed" {
  mkdir -p src
  printf 'export const f = () => { throw new Error("x"); };\n' > src/f.ts
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "EXTRA_EXCLUDE_PATH_RE drops a file that would otherwise fire" {
  deny_only_bats guard.bats
  commit_tests
  run env EXTRA_EXCLUDE_PATH_RE='^tests/guard\.bats$' bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "EXTRA_ALLOW_ASSERTION_RE silences a project-specific allow idiom" {
  printf '@test "rejects" {\n  [ "$status" -eq 1 ]\n}\n@test "accepts" {\n  assert_ok\n}\n' > tests/x.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/x.bats"* ]]
  run env EXTRA_ALLOW_ASSERTION_RE='assert_ok' bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "EXTRA_DENY_ASSERTION_RE flags a project-specific deny idiom" {
  printf '@test "rejects" {\n  assert_refused\n}\n' > tests/y.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"Total findings: 0"* ]]
  run env EXTRA_DENY_ASSERTION_RE='assert_refused' bash "$HOOK" "$BASE"
  [[ "$output" == *"tests/y.bats"* ]]
}

# --- EXTRA_* validation -----------------------------------------------------

@test "a malformed EXTRA_* value exits 1 naming the variable" {
  deny_only_bats guard.bats
  commit_tests
  run env EXTRA_DENY_ASSERTION_RE='[unterminated' bash "$HOOK" "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXTRA_DENY_ASSERTION_RE"* ]]
  [[ "$output" == *"not a valid regular expression"* ]]
}

@test "an EXTRA_* value keeps its literal meaning through the scan" {
  # Passed via ENVIRON rather than `awk -v`: -v performs escape processing
  # first, turning this pattern into a bracket expression that matches
  # almost every line, which would silence the detector permanently.
  deny_only_bats guard.bats
  commit_tests
  run env EXTRA_ALLOW_ASSERTION_RE='\[ *"\$status" *-ne *0 *\]' bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total findings: 1"* ]]
}

# --- setup errors -----------------------------------------------------------

@test "an invalid base-ref exits 1" {
  run bash "$HOOK" no-such-ref
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid commit-ish"* ]]
}

@test "an option-shaped base-ref exits 1 and writes no file" {
  rm -f "/tmp/DOG_ARG_PROOF...HEAD"
  run bash "$HOOK" '--output=/tmp/DOG_ARG_PROOF'
  [ "$status" -eq 1 ]
  [ ! -e "/tmp/DOG_ARG_PROOF...HEAD" ]
}

@test "a valid base-ref is accepted (the paired allow case for the ref check)" {
  deny_only_bats guard.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
}

# --- untrusted filenames ----------------------------------------------------

@test "a var-assignment-shaped filename is still analyzed, not swallowed" {
  # Unguarded, awk consumes an operand of the form NAME=value as a variable
  # assignment rather than a file, so the file is silently never scanned —
  # a deny-only guard suite would go unreported and the run would still say
  # "Total findings: 0". That is the fail-open direction RT7 shape (c) names.
  deny_only_bats guard.bats
  printf '@test "rejects" {\n  run bash ./g.sh bad\n  [ "$status" -eq 1 ]\n}\n' > 'FS=x.bats'
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FS=x.bats"* ]]
  # The paired case: an ordinary file in the same run is still analyzed.
  [[ "$output" == *"tests/guard.bats"* ]]
}

@test "a path git would C-quote is analyzed, not skipped" {
  # --name-only C-quotes a path containing a newline and emits the quotes as
  # literal bytes; a consumer that assumes a raw path then drops the file
  # silently. NUL framing carries it through as itself.
  printf '[ "$status" -eq 1 ]\n' > "$(printf 'tests/nl\nx.bats')"
  deny_only_bats guard.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total findings: 2"* ]]
  [[ "$output" == *"tests/guard.bats"* ]]
}

@test "a failed base diff exits non-zero instead of reporting a clean run" {
  # A tree-ish passes plain `git rev-parse --verify`, and every later
  # `git diff` then exits 128. Unchecked, that reads as "Total findings: 0"
  # and exit 0 — a clean report from a command that never ran.
  deny_only_bats guard.bats
  commit_tests
  run bash "$HOOK" 'HEAD^{tree}'
  [ "$status" -eq 1 ]
  [[ "$output" != *"Total findings: 0"* ]]
}

@test "a staged but uncommitted test file is analyzed" {
  deny_only_bats staged.bats
  git add -A >/dev/null 2>&1
  run bash "$HOOK" HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/staged.bats"* ]]
}

@test "an untracked test file is analyzed" {
  # test-gen runs this hook immediately after writing new test files, which
  # are untracked until someone stages them. No `git diff` shows them.
  deny_only_bats fresh.bats
  run bash "$HOOK" HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/fresh.bats"* ]]
}

@test "an untracked file with a paired allow case stays silent" {
  paired_bats fresh.bats
  run bash "$HOOK" HEAD
  [[ "$output" == *"Total findings: 0"* ]]
}

big_paired_bats() {
  # Large enough that dropping the single allow test leaves similarity above
  # git's 50% rename threshold — which is the realistic evasion shape and the
  # only one where git emits R rather than A+D.
  {
    for i in 1 2 3 4 5 6 7 8; do
      printf '@test "rejects case %s" {\n  run bash ./g.sh bad%s\n  [ "$status" -eq 1 ]\n}\n' "$i" "$i"
    done
    printf '@test "accepts" {\n  run bash ./g.sh good\n  [ "$status" -eq 0 ]\n}\n'
  } > "tests/$1"
}

@test "a renamed test that loses its allow case is analyzed at the new path" {
  # Moving a paired suite while dropping its allow assertions is the cheapest
  # way to turn it deny-only, and an AM-only filter drops it from the set.
  big_paired_bats old.bats
  commit_tests
  MID="$(git rev-parse HEAD)"
  git mv tests/old.bats tests/renamed.bats
  # Drop only the allow test; the rest is untouched, so git reports R.
  head -n -4 tests/renamed.bats > tmp && mv tmp tests/renamed.bats
  git add -A >/dev/null
  git commit -qm rename >/dev/null
  [ "$(git diff --name-status "$MID" | cut -c1)" = "R" ]
  run bash "$HOOK" "$MID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/renamed.bats"* ]]
}

@test "a renamed test that keeps its allow case stays silent" {
  big_paired_bats old.bats
  commit_tests
  MID="$(git rev-parse HEAD)"
  git mv tests/old.bats tests/renamed.bats
  git add -A >/dev/null
  git commit -qm rename >/dev/null
  run bash "$HOOK" "$MID"
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "a TMPDIR containing a quote does not execute at exit" {
  # A string-expanded `trap "rm -rf '$dir'" EXIT` embeds the path as shell
  # code; the handler must quote at trap-execution time instead.
  EVIL="$WORK/qu';touch /tmp/DOG_TRAP_PROOF;'dir"
  mkdir -p "$EVIL"
  rm -f /tmp/DOG_TRAP_PROOF
  deny_only_bats guard.bats
  commit_tests
  run env TMPDIR="$EVIL" bash "$HOOK" "$BASE"
  [ ! -e /tmp/DOG_TRAP_PROOF ]
  [[ "$output" == *"tests/guard.bats"* ]]
}

@test "a filename cannot forge a summary line in the report" {
  # Unescaped, a path containing a newline splits the finding across lines and
  # injects text that reads as the hook's own summary.
  printf '[ "$status" -eq 1 ]\n' > "$(printf 'tests/a\nTotal findings: 0\nx.bats')"
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^Total findings')" -eq 1 ]
  [[ "$output" == *"Total findings: 1"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^  \[Major\]')" -eq 1 ]
}

@test "a filename cannot emit terminal escapes into the report" {
  printf '[ "$status" -eq 1 ]\n' > "$(printf 'tests/\033[31mred.bats')"
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | LC_ALL=C tr -cd '\033' | wc -c | tr -d ' ')" -eq 0 ]
  [[ "$output" == *"Total findings: 1"* ]]
}

@test "a filename cannot carry bidi override bytes into the report" {
  # U+202E reverses the rendering of the text around it. Under a UTF-8 locale
  # `%q` treats it as printable and passes it through; the escaping is pinned
  # to the C locale so every non-ASCII byte is escaped instead.
  RLO="$(printf '\342\200\256')"
  printf '[ "$status" -eq 1 ]\n' > "tests/a${RLO}b.bats"
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$RLO"* ]]
  [[ "$output" == *"Total findings: 1"* ]]
}

@test "an ordinary filename is displayed unescaped" {
  # The paired allow case for the escaping: normal reports must stay readable.
  deny_only_bats guard.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [[ "$output" == *"  [Major] tests/guard.bats:"* ]]
}

@test "a tracked symlink is skipped rather than followed out of the repo" {
  # The link target is itself deny-only, so following it would produce a
  # finding attributed to a path inside the repo whose bytes live outside it.
  OUTSIDE="$(mktemp -d)"
  # The deny assertion sits on line 1: a symlink's own diff contains a
  # single added line (the target path), so a target whose deny assertion is
  # further down could not fire even unguarded, and the fixture would not
  # discriminate.
  printf '[ "$status" -eq 1 ]\n' > "$OUTSIDE/target.bats"
  deny_only_bats guard.bats
  ln -s "$OUTSIDE/target.bats" tests/link.bats
  commit_tests
  run bash "$HOOK" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"tests/link.bats"* ]]
  [[ "$output" == *"tests/guard.bats"* ]]
  rm -rf "$OUTSIDE"
}
