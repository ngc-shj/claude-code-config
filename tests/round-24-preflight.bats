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

@test "the baseline is a constant, not whatever branch tip is current" {
  # Comparing against origin/main would break the moment this merges: the
  # registered starting line is a fixed commit, not the newest one.
  pf "
line = [l for l in open(p.MANIFEST).read().splitlines() if l.startswith('baseline')]
assert len(line) == 1, line
assert line[0].split('\t')[2] == p.PROTOCOL_BASELINE, line
src = open('$R24/preflight.py').read()
assert 'rev-parse' not in src.split('def manifest_rows')[1].split('def main')[0]
print(p.PROTOCOL_BASELINE)"
  [ "$status" -eq 0 ]
  [ "$output" = "9f4026c11d6630cc451f0c479de0f906043c353a" ]
}

@test "the registered baseline is an ancestor of HEAD" {
  run git -C "$REPO" merge-base --is-ancestor 9f4026c11d6630cc451f0c479de0f906043c353a HEAD
  [ "$status" -eq 0 ]
}

@test "--write refuses to replace a manifest that already exists" {
  cp "$R24/preflight-manifest.tsv" "$SANDBOX/before.tsv"
  run python3 "$R24/preflight.py" --out "$SANDBOX/build" --write
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
  [[ "$output" == *"--re-register"* ]]
  # refused means untouched, not "refused after writing"
  run diff "$SANDBOX/before.tsv" "$R24/preflight-manifest.tsv"
  [ "$status" -eq 0 ]
}

@test "a plain run compares every manifest row, and a changed pinned file fails it" {
  # Without the comparison, a pinned file could change and the run would print
  # its new hash and pass.
  pf "
rows = [tuple(l.split('\t')) for l in
        open(p.MANIFEST).read().splitlines()[1:] if l]
kinds = {k for k, _, _ in rows}
assert kinds == {'baseline', 'arm', 'arm-file', 'pinned'}, kinds
pinned = [r for r in rows if r[0] == 'pinned']
assert len(pinned) == len(p.PINNED), (len(pinned), len(p.PINNED))
# every pinned row is the file's real hash today
for _, rel, sha in pinned:
    got = p.file_sha1(p.os.path.join(p.REPO, 'evals', rel))
    assert got == sha, (rel, sha, got)
print(len(rows))"
  [ "$status" -eq 0 ]
  [ "$output" = "109" ]
}

@test "the clustering inventory is all 94 frozen claims, not round 16's 64" {
  # Pointing the clustering brief at the seed alone would let the 30 claims
  # round 17 adjudicated come back as new.
  pf "
import csv
rows = list(csv.DictReader(open('$R24/cluster-inventory.tsv', newline=''), delimiter='\t'))
ids = [r['cluster_id'] for r in rows]
assert len(ids) == p.N_CLUSTER_CLAIMS == 94, len(ids)
assert len(set(ids)) == 94
assert ids == sorted(ids), 'not sorted'
assert all(r['claim'].strip() for r in rows)
print(len(ids))"
  [ "$status" -eq 0 ]
  [ "$output" = "94" ]
}

@test "the clustering inventory regenerates from the two frozen sources" {
  run bash -c "python3 '$R24/measure.py' --cluster-inventory 2>/dev/null | diff - '$R24/cluster-inventory.tsv'"
  [ "$status" -eq 0 ]
}

@test "every frozen claim carries canonical text, and the ids match the verdicts" {
  run python3 -c "
import importlib.util, csv
s = importlib.util.spec_from_file_location('m', '$R24/measure.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
v, t = m.frozen(), m.frozen_text()
inv = {r['cluster_id'] for r in csv.DictReader(open('$R24/cluster-inventory.tsv', newline=''), delimiter='\t')}
assert set(v) == inv, set(v) ^ inv
assert all(t.get(c, '').strip() for c in v)
print(len(v))"
  [ "$status" -eq 0 ]
  [ "$output" = "94" ]
}

@test "an empty round directory shows no measurement artifact" {
  pf "
assert p.measurement_artifacts('$SANDBOX') == [], p.measurement_artifacts('$SANDBOX')
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "every registered measurement artifact is detected, one at a time" {
  # The rule is checked against a sandbox, not against the real round-24
  # directory: the round has legitimately started, so that directory holds these
  # files now. What must stay true is that each of them is DETECTED.
  pf "
import os, shutil
for name in p.MEASUREMENT:
    root = '$SANDBOX/probe'
    shutil.rmtree(root, ignore_errors=True); os.makedirs(root)
    assert p.measurement_artifacts(root) == []
    target = os.path.join(root, name)
    os.makedirs(target) if '.' not in name else open(target, 'w').close()
    got = p.measurement_artifacts(root)
    assert got == [name], (name, got)
print(len(p.MEASUREMENT))"
  [ "$status" -eq 0 ]
  [ "$output" = "6" ]
}

@test "the production check reads the round directory itself" {
  pf "
import inspect
src = inspect.getsource(p.main)
assert 'measurement_artifacts(HERE)' in src, 'production call does not pass HERE'
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
