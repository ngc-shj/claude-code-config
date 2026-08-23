#!/usr/bin/env python3
"""Reserve the round's 72 review output paths, before any of them exists.

Extraction takes these paths explicitly. It never globs `*.md` over a shared
tree, because a glob is a promise about a directory's future contents and the
probe's reviews are the standing proof that directories acquire files nobody
planned. Registering the list up front also means a missing output is a named
absence rather than a smaller glob result that no one notices.

The list is a pure function of the design — 12 review indices x 2 arms x 3 parts
— so it is generated rather than typed, and committed as
`measurement-outputs.tsv` so the round cannot quietly widen or narrow it.

Usage:
  round-24/register-outputs.py --root <dir>            # print
  round-24/register-outputs.py --root <dir> --write    # ... and commit the list
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(HERE, 'measurement-outputs.tsv')

N_REVIEWS = 12
ARMS = ('W', 'N')
PARTS = ('a', 'b', 'c')          # three identical generalists per review


def rows(root):
    out = []
    for index in range(1, N_REVIEWS + 1):
        for arm in ARMS:
            for part in PARTS:
                name = f'review-{index:02d}-{arm}-{part}.md'
                out.append((str(index), arm, part,
                            os.path.join(root, 'reviews', name)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--write', action='store_true')
    a = ap.parse_args()
    reserved = rows(os.path.abspath(a.root))

    expected = N_REVIEWS * len(ARMS) * len(PARTS)
    if len(reserved) != expected or len({p for *_, p in reserved}) != expected:
        sys.exit(f'{len(reserved)} paths, expected {expected} distinct')

    existing = [p for *_, p in reserved if os.path.exists(p)]
    if existing:
        sys.exit(f'{len(existing)} registered output(s) already exist, so this is '
                 f'not a reservation:\n  ' + '\n  '.join(existing[:5]))

    if a.write:
        if os.path.exists(REGISTRY):
            sys.exit(f'{os.path.relpath(REGISTRY, HERE)} already exists; the '
                     f'registered output set is not rewritten in passing')
        with open(REGISTRY, 'w') as f:
            f.write('review\tarm\tpart\tpath\n')
            for row in reserved:
                f.write('\t'.join(row) + '\n')
        print(f'wrote {os.path.relpath(REGISTRY, os.path.dirname(HERE))}')

    print(f'{len(reserved)} output paths reserved under {a.root}, none of which '
          f'exists yet.')
    print(f'{reserved[0][3]}\n  ...\n{reserved[-1][3]}')


if __name__ == '__main__':
    main()
