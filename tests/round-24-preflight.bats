#!/usr/bin/env bats
# Tests for evals/rule-precision/round-24/preflight.py
#
# The preflight's job is to fail when the round's starting line has moved. That
# only means something if the committed manifest is checked against a fresh
# build, and if the arm construction is exercised rather than described — so
# these import the module and rebuild the arms, rather than reading its report.

bats_require_minimum_version 1.5.0

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
R24="$REPO/evals/rule-precision/round-24"

setup() {
  export SANDBOX
  SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "$SANDBOX"
}

# Run a python snippet with preflight.py imported as `p`.
pf() {
  run python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location('p', '$R24/preflight.py')
p = importlib.util.module_from_spec(s); s.loader.exec_module(p)
$1"
}

@test "the committed manifest reproduces from a fresh build of the arms" {
  pf "
w, n = '$SANDBOX/cat-W', '$SANDBOX/cat-N'
p.build_arm(p.CATALOGUE_COMMIT, w, w); p.build_arm(p.CATALOGUE_COMMIT, n, n)
p.apply_arms_diff(n, n)
got = {'arm\tcat-W': p.tree_hash(p.tree(w, w)),
       'arm\tcat-N': p.tree_hash(p.tree(n, n))}
for rel in p.PINNED:
    got['pinned\t' + rel] = p.file_sha1(p.os.path.join(p.REPO, 'evals', rel))
bad = []
for line in open(p.MANIFEST).read().splitlines()[1:]:
    kind, name, sha = line.split('\t')
    if kind == 'arm-file':
        continue
    key = kind + '\t' + name
    if key in got and got[key] != sha:
        bad.append((key, sha, got[key]))
assert not bad, bad
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "the arms differ in exactly the two files the protocol names" {
  pf "
w, n = '$SANDBOX/cat-W', '$SANDBOX/cat-N'
p.build_arm(p.CATALOGUE_COMMIT, w, w); p.build_arm(p.CATALOGUE_COMMIT, n, n)
p.apply_arms_diff(n, n)
tw = {r: s for r, _, s in p.tree(w, w)}
tn = {r: s for r, _, s in p.tree(n, n)}
assert set(tw) == set(tn), set(tw) ^ set(tn)
differ = sorted(r for r in tw if tw[r] != tn[r])
assert differ == sorted(p.THE_VARIABLE), differ
print(len(tw), differ)"
  [ "$status" -eq 0 ]
  [[ "$output" == "44 ['common-rules.digest.md', 'common-rules.md']" ]]
}

@test "the Finding Floor leaves N and stays in W" {
  pf "
w, n = '$SANDBOX/cat-W', '$SANDBOX/cat-N'
p.build_arm(p.CATALOGUE_COMMIT, w, w); p.build_arm(p.CATALOGUE_COMMIT, n, n)
p.apply_arms_diff(n, n)
def has(root, needle):
    return needle in open(p.os.path.join(root, 'common-rules.md')).read()
def digest(root):
    return open(p.os.path.join(root, 'common-rules.digest.md')).read()
assert has(w, '### Finding Floor') and not has(n, '### Finding Floor')
assert 'Finding Floor' in digest(w) and 'Finding Floor' not in digest(n)
assert '### Remedy Floor' in open(p.os.path.join(n, 'common-rules.md')).read()
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "arm hashes do not depend on where the arm was built" {
  pf "
a, b = '$SANDBOX/one/cat-W', '$SANDBOX/two-longer-name/cat-W'
p.build_arm(p.CATALOGUE_COMMIT, a, a); p.build_arm(p.CATALOGUE_COMMIT, b, b)
assert open(p.os.path.join(a, 'common-rules.digest.md')).read() != \
       open(p.os.path.join(b, 'common-rules.digest.md')).read(), 'paths did not differ'
assert p.tree_hash(p.tree(a, a)) == p.tree_hash(p.tree(b, b))
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "mutation: an edited arm file moves the tree hash" {
  pf "
w = '$SANDBOX/cat-W'
p.build_arm(p.CATALOGUE_COMMIT, w, w)
before = p.tree_hash(p.tree(w, w))
path = p.os.path.join(w, 'SKILL.md')
open(path, 'a').write('\nx\n')
assert p.tree_hash(p.tree(w, w)) != before
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "only the digest is rewritten, so phase-3-review keeps the repo path" {
  # Deliberate, and recorded in round-24/README.md: rewriting it would make a
  # third file differ between the arms and break the diff -rq invariant.
  pf "
w = '$SANDBOX/cat-W'
p.build_arm(p.CATALOGUE_COMMIT, w, w)
phase = open(p.os.path.join(w, 'phases', 'phase-3-review.md')).read()
assert p.CATALOGUE_PATH + '/common-rules.md' in phase
assert w not in phase
digest = open(p.os.path.join(w, 'common-rules.digest.md')).read()
assert p.CATALOGUE_PATH + '/' not in digest and w in digest
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "the live catalogue has not drifted from the arm commit" {
  # phase-3-review.md sends a reviewer to the repo path; that is only harmless
  # while the repo file matches bc0f966.
  run bash -c "diff <(git -C '$REPO' show ${CATALOGUE_COMMIT:-bc0f966}:skills/triangulate/common-rules.md) '$REPO/skills/triangulate/common-rules.md'"
  [ "$status" -eq 0 ]
}

@test "the manifest records the merged protocol baseline" {
  run grep -F "$(git -C "$REPO" rev-parse origin/main)" "$R24/preflight-manifest.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == baseline* ]]
}

@test "no measurement artifact exists in round-24" {
  for f in findings.tsv clusters.tsv reviews.tsv tiebreak.tsv adjudications bridge; do
    [ ! -e "$R24/$f" ]
  done
}
