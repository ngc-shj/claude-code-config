#!/usr/bin/env python3
"""Build round 24's arms and check everything the protocol pins — no agents.

This runs before the reachability probe and before any review. It launches
nothing, reads no model output, and produces no measurement. What it does is
turn the protocol's "verified before the first batch" sentences into a command
that either passes or names what is wrong:

  1. build cat-W and cat-N from `bc0f966` plus `round-17/arms.diff`
  2. `diff -rq` over the two, which must name exactly two files
  3. hash both arms, and every file the protocol pins
  4. render the six briefs and check W and N differ only in the catalogue path
  5. confirm no round-24 measurement artifact exists yet

Arm hashes are taken over a NORMALISED copy: each arm's digest names its own
catalogue directory, so a literal hash would depend on where the arm was built
and could not be compared across machines or runs. Normalising that path back to
`<CAT>` — the same normalisation `arms.diff` itself uses — makes the manifest a
property of the arms rather than of this afternoon's temp directory.

Usage:
  round-24/preflight.py --out <dir>            # build, check, print
  round-24/preflight.py --out <dir> --write    # ... and rewrite preflight-manifest.tsv
"""
import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(RP))

# The commit that merged the protocol. A CONSTANT, not `git rev-parse HEAD`:
# the baseline is the state the round was registered against, and reading it
# from the current branch means it silently becomes whatever was committed last.
PROTOCOL_BASELINE = '9f4026c11d6630cc451f0c479de0f906043c353a'

CATALOGUE_COMMIT = 'bc0f966'
CATALOGUE_PATH = 'skills/triangulate'
ARMS_DIFF = os.path.join(RP, 'round-17', 'arms.diff')
MANIFEST = os.path.join(HERE, 'preflight-manifest.tsv')

# The session prefix round 17 baked into arms.diff, ahead of its own <CAT> slot.
R17_CAT = ('/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-'
           'config/e392c887-68cf-492b-a61c-d5d0f9838aa9/<CAT>')

# The one variable. `diff -rq` over the arms must name these and nothing else.
THE_VARIABLE = ('common-rules.digest.md', 'common-rules.md')

# Everything the protocol pins by hash, relative to `evals/`.
PINNED = (
    'rule-ablation/fixtures/F10-webhooks.diff',
    'rule-precision/round-16/seed/inventory.tsv',
    'rule-precision/round-17/clusters.tsv',
    'rule-precision/round-17/adjudications/adjudicator1.tsv',
    'rule-precision/round-17/adjudications/adjudicator2.tsv',
    'rule-precision/round-17/adjudications/adjudicator3.tsv',
    'rule-precision/round-17/measure.py',
    'rule-precision/round-17/arms.diff',
    'rule-precision/round-17/briefs/brief-W.md',
    'rule-precision/round-17/briefs/brief-N.md',
    'rule-precision/round-17/briefs/brief-cluster.md',
    'rule-precision/round-17/briefs/adjudicate-brief.md',
    'rule-precision/round-24/briefs/review.template.md',
    'rule-precision/round-24/briefs/cluster.template.md',
    'rule-precision/adjudication-brief.md',
    'rule-precision/round-24/bridge-sample.tsv',
    'rule-precision/round-24/bridge-input.tsv',
    'rule-precision/round-24/cluster-inventory.tsv',
)

# The clustering brief must name every claim already recorded on F10 — the 64
# seed claims AND the 30 round 17 added. Point it at round 16's seed alone and
# thirty adjudicated claims come back as new.
CLUSTER_INVENTORY = os.path.join(HERE, 'cluster-inventory.tsv')
N_CLUSTER_CLAIMS = 94

# Anything here means the round has started and this is not a preflight.
MEASUREMENT = ('findings.tsv', 'clusters.tsv', 'reviews.tsv', 'tiebreak.tsv',
               'adjudications', 'bridge')

FAILURES = []


def check(ok, label, detail=''):
    print(f'  {"PASS" if ok else "FAIL"}  {label}{"  " + detail if detail else ""}')
    if not ok:
        FAILURES.append(label)
    return ok


def sh(*cmd, cwd=None):
    """Every subprocess in C locale: this script parses `diff -rq` output, and a
    localised "... は異なります" is not the string the check is written against."""
    env = dict(os.environ, LC_ALL='C', LANG='C')
    r = subprocess.run(cmd, cwd=cwd or REPO, capture_output=True, text=True,
                       env=env)
    return r.returncode, r.stdout, r.stderr


def blob_sha1(data):
    """git hash-object, so digests match what the protocol and README quote."""
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def file_sha1(path):
    with open(path, 'rb') as f:
        return blob_sha1(f.read())


def build_arm(commit, dest, cat_token):
    """Extract the catalogue and point THE DIGEST at this copy of itself.

    Only the digest. `arms.diff`'s own preamble says so — "each arm's digest
    names its own catalogue copy" — and its corollary is the check in step 3:
    every other file is byte-identical between the arms, which stops being true
    the moment a second file is rewritten per-arm. `phases/phase-3-review.md`
    also names `skills/triangulate/` and is deliberately left alone, so that the
    arms match round 17's construction rather than an improved one. Step 3b is
    what keeps that safe.
    """
    os.makedirs(dest, exist_ok=True)
    code, out, err = sh('git', 'archive', '--format=tar',
                        f'{commit}:{CATALOGUE_PATH}')
    if code:
        sys.exit(f'git archive {commit}:{CATALOGUE_PATH} failed: {err.strip()}')
    p = subprocess.run(['tar', '-x', '-C', dest], input=out.encode('utf-8',
                       'surrogateescape'), capture_output=True)
    if p.returncode:
        sys.exit(f'tar failed: {p.stderr.decode()}')
    path = os.path.join(dest, 'common-rules.digest.md')
    with open(path) as f:
        text = f.read()
    with open(path, 'w') as f:
        f.write(text.replace(CATALOGUE_PATH + '/', cat_token + '/'))


def apply_arms_diff(dest, cat_token):
    """Cut the Finding Floor from N, by the committed diff and not by hand."""
    with open(ARMS_DIFF) as f:
        patch = f.read().replace(R17_CAT, cat_token)
    p = subprocess.run(['git', 'apply', '-p0', '-'], input=patch, text=True,
                       cwd=dest, capture_output=True)
    if p.returncode:
        sys.exit(f'git apply of arms.diff failed in {dest}:\n{p.stderr}')


def tree(root, cat_token):
    """(relative path, mode, sha1) for every file, with the arm path normalised."""
    out = []
    for dirpath, dirnames, names in os.walk(root):
        dirnames.sort()
        for name in sorted(names):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            with open(path, 'rb') as f:
                data = f.read()
            data = data.replace(cat_token.encode(), b'<CAT>')
            mode = '100755' if os.access(path, os.X_OK) else '100644'
            out.append((rel, mode, blob_sha1(data)))
    return out


def tree_hash(entries):
    h = hashlib.sha1()
    for rel, mode, sha in entries:
        h.update(f'{mode} {rel}\0{sha}\n'.encode())
    return h.hexdigest()


def manifest_rows(entries, pinned):
    """Every line the manifest holds, built the same way for writing and checking."""
    out = [('baseline', 'protocol-head', PROTOCOL_BASELINE)]
    for label in ('W', 'N'):
        out.append(('arm', f'cat-{label}', tree_hash(entries[label])))
        out += [('arm-file', f'cat-{label}/{rel}', sha)
                for rel, _, sha in entries[label]]
    out += [('pinned', rel, sha) for rel, sha in pinned]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True, help='where to build the arms')
    ap.add_argument('--write', action='store_true',
                    help='write preflight-manifest.tsv; refused if one exists')
    ap.add_argument('--re-register', action='store_true',
                    help='overwrite an existing manifest. This retires the '
                         'registered starting line and is never routine.')
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    cat_w, cat_n = os.path.join(out, 'cat-W'), os.path.join(out, 'cat-N')

    print('ROUND 24 PREFLIGHT — no agent is launched by this script.\n')

    code, head, _ = sh('git', 'rev-parse', 'HEAD')
    head = head.strip()
    _, dirty, _ = sh('git', 'status', '--porcelain')
    print(f'baseline    {PROTOCOL_BASELINE}')
    print(f'repo HEAD   {head}')
    print(f'worktree    {"clean" if not dirty.strip() else "DIRTY"}')
    code, ver, _ = sh('claude', '--version')
    print(f'cli         {ver.strip() or "unavailable"}')
    print(f'built at    {out}\n')

    print('0. the registered baseline is behind us')
    code, _, _ = sh('git', 'merge-base', '--is-ancestor', PROTOCOL_BASELINE, 'HEAD')
    check(code == 0, f'{PROTOCOL_BASELINE[:7]} is an ancestor of HEAD',
          'the protocol commit is not in this history' if code else '')

    print('\n1. the round has not started')
    started = [n for n in MEASUREMENT if os.path.exists(os.path.join(HERE, n))]
    check(not started, 'no measurement artifact in round-24/',
          f'found {started}' if started else '')

    # The reachability probe's three reviews are unopened and stay that way. The
    # measurement run gets its own directory so that no later step can reach
    # them by a glob it did not mean to widen — extraction takes the 72
    # registered output paths explicitly, never `*.md` over a shared tree.
    strays = []
    for dirpath, _, names in os.walk(out) if os.path.isdir(out) else ():
        strays += [os.path.relpath(os.path.join(dirpath, n), out)
                   for n in names if n.startswith('probe-')]
    check(not strays, f'no probe output under {os.path.basename(out) or out}',
          f'found {strays}' if strays else '')

    print('\n2. arms built from the committed catalogue and diff')
    for d in (cat_w, cat_n):
        shutil.rmtree(d, ignore_errors=True)
    build_arm(CATALOGUE_COMMIT, cat_w, cat_w)
    build_arm(CATALOGUE_COMMIT, cat_n, cat_n)
    apply_arms_diff(cat_n, cat_n)
    check(os.path.exists(os.path.join(cat_w, 'common-rules.md')),
          f'cat-W from {CATALOGUE_COMMIT}:{CATALOGUE_PATH}')
    check(os.path.exists(os.path.join(cat_n, 'common-rules.md')),
          f'cat-N, arms.diff applied')

    print('\n3. the one variable')
    code, dq, _ = sh('diff', '-rq', cat_w, cat_n)
    differing = sorted(re.findall(r'Files .*/([^/ ]+) and ', dq))
    only_in = [l for l in dq.splitlines() if l.startswith('Only in')]
    check(differing == sorted(THE_VARIABLE) and not only_in,
          'diff -rq names exactly the two expected files',
          f'{differing}{"  " + str(only_in) if only_in else ""}')
    for line in dq.splitlines():
        print(f'        {line}')

    print('\n3b. the one path an arm copy does not capture')
    # phases/phase-3-review.md carries `awk ... skills/triangulate/common-rules.md`,
    # a repo path rather than an arm path. A reviewer who follows it reads the
    # live catalogue instead of its arm's copy. It extracts the REMEDY Floor,
    # which both arms hold, so it cannot leak the arm variable — but it can
    # deliver bytes from a catalogue that has moved since bc0f966. That is only
    # harmless while the file has not moved, so this asserts it rather than
    # assuming it.
    live = os.path.join(REPO, CATALOGUE_PATH, 'common-rules.md')
    code, at_commit, _ = sh('git', 'show', f'{CATALOGUE_COMMIT}:{CATALOGUE_PATH}'
                            '/common-rules.md')
    with open(live) as f:
        check(f.read() == at_commit,
              f'{CATALOGUE_PATH}/common-rules.md at HEAD is byte-identical to '
              f'{CATALOGUE_COMMIT}')
    code, refs, _ = sh('git', 'grep', '-l', f'{CATALOGUE_PATH}/',
                       CATALOGUE_COMMIT, '--', CATALOGUE_PATH)
    named = sorted(l.split(':', 1)[1] for l in refs.splitlines() if ':' in l)
    check(named == [f'{CATALOGUE_PATH}/common-rules.digest.md',
                    f'{CATALOGUE_PATH}/phases/phase-3-review.md'],
          'exactly the two known files name the repo catalogue path',
          str(named))

    print('\n4. arm hashes, normalised so they do not depend on the build path')
    entries = {}
    for label, root in (('W', cat_w), ('N', cat_n)):
        entries[label] = tree(root, root)
        print(f'        cat-{label}  {len(entries[label]):3d} files  '
              f'tree {tree_hash(entries[label])}')
    check(len(entries['W']) == len(entries['N']),
          'both arms hold the same number of files',
          f'{len(entries["W"])} vs {len(entries["N"])}')
    same = [r for r, _, s in entries['W']
            if (r, s) in {(x, y) for x, _, y in entries['N']}]
    check(len(same) == len(entries['W']) - len(THE_VARIABLE),
          f'all but {len(THE_VARIABLE)} files are byte-identical',
          f'{len(same)} of {len(entries["W"])} identical')

    print('\n5. everything the protocol pins')
    pinned = []
    for rel in PINNED:
        path = os.path.join(REPO, 'evals', rel)
        sha = file_sha1(path)
        pinned.append((rel, sha))
        print(f'        {sha}  {rel}')
    check(len(pinned) == len(PINNED), f'{len(PINNED)} pinned files hashed')

    print('\n6. the frozen bridge artifacts still reproduce')
    measure = os.path.join(HERE, 'measure.py')
    code, got, _ = sh(sys.executable, measure, '--bridge-sample')
    emitted = '\n'.join(got.splitlines()[3:]) + '\n'
    with open(os.path.join(HERE, 'bridge-sample.tsv')) as f:
        check(emitted == f.read(), 'bridge-sample.tsv reproduces from measure.py')
    code, got, _ = sh(sys.executable, measure, '--bridge-input')
    with open(os.path.join(HERE, 'bridge-input.tsv')) as f:
        check(got == f.read(), 'bridge-input.tsv reproduces from measure.py')
    code, got, _ = sh(sys.executable, measure, '--cluster-inventory')
    with open(CLUSTER_INVENTORY) as f:
        body = f.read()
        check(got == body, 'cluster-inventory.tsv reproduces from measure.py')
    ids = [l.split('\t')[0] for l in body.splitlines()[1:]]
    check(len(ids) == N_CLUSTER_CLAIMS and len(set(ids)) == N_CLUSTER_CLAIMS,
          f'the clustering inventory holds {N_CLUSTER_CLAIMS} unique claims',
          f'{len(ids)} rows, {len(set(ids))} unique')

    print('\n7. briefs render, and W and N differ only in the catalogue path')
    briefs = os.path.join(out, 'briefs')
    code, _, err = sh(sys.executable, os.path.join(HERE, 'briefs', 'render.py'),
                      '--out', briefs, '--cat-w', cat_w, '--cat-n', cat_n,
                      '--inventory', CLUSTER_INVENTORY,
                      '--n-claims', str(N_CLUSTER_CLAIMS),
                      '--bridge-claims', os.path.join(HERE, 'bridge-input.tsv'),
                      '--n-bridge', '24')
    if not check(code == 0, 'render.py exits clean', err.strip()):
        return finish(a, head, ver, out, entries, pinned)
    with open(os.path.join(briefs, 'brief-W.md')) as f:
        bw = f.read().replace(cat_w, '<CAT>')
    with open(os.path.join(briefs, 'brief-N.md')) as f:
        bn = f.read().replace(cat_n, '<CAT>')
    check(bw == bn, 'brief-W and brief-N are identical modulo <CAT>')
    for name in sorted(os.listdir(briefs)):
        print(f'        {file_sha1(os.path.join(briefs, name))}  {name}')

    print('\n8. reachability')
    check(True, 'NOT RUN — this script launches no agent')

    finish(a, head, ver, out, entries, pinned)


def finish(a, head, ver, out, entries, pinned):
    rows = manifest_rows(entries, pinned) if entries and pinned else []
    exists = os.path.exists(MANIFEST)

    if a.write or a.re_register:
        if exists and not a.re_register:
            sys.exit(f'\n{os.path.relpath(MANIFEST, REPO)} already exists. It is '
                     f'the registered\nstarting line, and --write will not '
                     f'silently replace it. Compare first;\nif the starting line '
                     f'genuinely has to move, say --re-register and say why in\n'
                     f'the commit message.')
        if exists:
            print('\n*** --re-register: replacing a manifest that was already '
                  'registered. ***')
        with open(MANIFEST, 'w') as f:
            f.write('kind\tname\tsha1\n')
            for kind, name, sha in rows:
                f.write(f'{kind}\t{name}\t{sha}\n')
        print(f'wrote {os.path.relpath(MANIFEST, REPO)}')
    elif rows:
        print('\n9. the committed manifest still describes this build')
        if not check(exists, 'preflight-manifest.tsv exists'):
            pass
        else:
            want = [tuple(l.split('\t')) for l in
                    open(MANIFEST).read().splitlines()[1:] if l]
            missing = [r for r in want if r not in rows]
            added = [r for r in rows if r not in want]
            check(not missing and not added,
                  f'all {len(rows)} manifest rows match',
                  f'{len(missing)} changed/missing, {len(added)} new')
            for r in (missing + added)[:10]:
                print(f'        {"was" if r in missing else "now"}  '
                      f'{r[0]}\t{r[1]}\t{r[2]}')

    print(f'\n{"PREFLIGHT PASSED" if not FAILURES else "PREFLIGHT FAILED"} — '
          f'{len(FAILURES)} failure(s){": " + ", ".join(FAILURES) if FAILURES else ""}')
    print('Measurement data produced by this run: none. Agents launched: none.')
    sys.exit(1 if FAILURES else 0)


if __name__ == '__main__':
    main()
