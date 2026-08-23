#!/usr/bin/env python3
"""Render round 24's briefs from canonical templates, and hash both ends.

Every round in this series committed its briefs as *rendered artifacts* — with
that session's scratchpad paths and that round's claim counts baked in. They are
run records, not instruments: round 17's clustering brief says "89 claims" in one
place and "the 64 existing claims" in two others, and its adjudication brief asks
for 25 rows. None of that is reusable, so "reuse the briefs verbatim" is not a
thing a protocol can ask for.

What is reusable is the part that carries the instrument: the role, the standing
assumption, the clustering rule, the obligations, the output shape. This script
separates that from the per-run substitutions, so the protocol can pin the
INVARIANT by template hash and still produce briefs that address the round in
front of it. The rendered briefs are hashed too, and both hashes go in the round
README beside the numbers they produced.

Substitutions, and nothing else is variable:

  review.template.md    {FIXTURE} {REPO} {CAT}
  cluster.template.md   {FIXTURE} {INVENTORY} {N_CLAIMS}
  ../../adjudication-brief.md  {DIFF} {CLAIMS} {N}

The adjudication brief is already a template in this repository and is used for
all three adjudication passes — new claims, the bridge sample, and the tie-break
— differing only in {CLAIMS} and {N}.

Usage:
  round-24/briefs/render.py --out <dir> --cat-w <dir> --cat-n <dir> \
      --inventory <path> --n-claims 94 \
      --new-claims <path> --n-new <int> \
      --bridge-claims <path> --n-bridge 24 \
      [--tiebreak-claims <path> --n-tiebreak <int>]

Any unsubstituted `{PLACEHOLDER}` left in an output is a hard error: a brief that
still names a template slot is a brief that will send an agent to a path that
does not exist.
"""
import argparse
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
FIXTURE = os.path.join(REPO, 'evals', 'rule-ablation', 'fixtures', 'F10-webhooks.diff')
ADJUDICATE = os.path.join(HERE, '..', '..', 'adjudication-brief.md')

LEFTOVER = re.compile(r'\{[A-Z_]+\}')


def render(template, subs, out_path):
    with open(template) as f:
        text = f.read()
    for k, v in subs.items():
        text = text.replace('{%s}' % k, str(v))
    stray = LEFTOVER.findall(text)
    if stray:
        sys.exit(f'{out_path}: unsubstituted placeholders {sorted(set(stray))}')
    with open(out_path, 'w') as f:
        f.write(text)
    return (sha1(template), sha1(out_path))


def sha1(path):
    """git hash-object, so the digests match what the protocol pins."""
    with open(path, 'rb') as f:
        body = f.read()
    return hashlib.sha1(b'blob %d\0' % len(body) + body).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--cat-w', required=True)
    p.add_argument('--cat-n', required=True)
    p.add_argument('--inventory', required=True)
    p.add_argument('--n-claims', type=int, required=True)
    p.add_argument('--new-claims')
    p.add_argument('--n-new', type=int)
    p.add_argument('--bridge-claims')
    p.add_argument('--n-bridge', type=int, default=24)
    p.add_argument('--tiebreak-claims')
    p.add_argument('--n-tiebreak', type=int)
    a = p.parse_args()

    os.makedirs(a.out, exist_ok=True)
    jobs = [
        ('brief-W.md', 'review.template.md',
         {'FIXTURE': FIXTURE, 'REPO': REPO, 'CAT': a.cat_w}),
        ('brief-N.md', 'review.template.md',
         {'FIXTURE': FIXTURE, 'REPO': REPO, 'CAT': a.cat_n}),
        ('brief-cluster.md', 'cluster.template.md',
         {'FIXTURE': FIXTURE, 'INVENTORY': a.inventory, 'N_CLAIMS': a.n_claims}),
    ]
    for name, claims, n in (('adjudicate-new.md', a.new_claims, a.n_new),
                            ('adjudicate-bridge.md', a.bridge_claims, a.n_bridge),
                            ('adjudicate-tiebreak.md', a.tiebreak_claims, a.n_tiebreak)):
        if claims is None:
            continue
        if n is None:
            sys.exit(f'{name}: claim file given without its row count')
        jobs.append((name, ADJUDICATE, {'DIFF': FIXTURE, 'CLAIMS': claims, 'N': n}))

    print(f'{"rendered":26s}{"template sha1":>42s}{"output sha1":>42s}')
    for name, template, subs in jobs:
        path = template if os.path.isabs(template) else os.path.join(HERE, template)
        t, o = render(path, subs, os.path.join(a.out, name))
        print(f'{name:26s}{t:>42s}{o:>42s}')

    print('\nBoth columns go in the round README. The template hash is what the '
          'protocol\npins as the instrument; the output hash is what the agents '
          'actually read.')


if __name__ == '__main__':
    main()
