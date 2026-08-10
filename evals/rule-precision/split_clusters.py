#!/usr/bin/env python3
"""Split findings.tsv into one clustering input per changed file.

Clustering is fanned out one agent per changed file, so the split needs to know
which file a finding is about. `extract.py`'s `target()` cannot answer that: it
matches an extension whitelist (`py|sql|txt|cfg|toml|ini|md|yaml|yml`), so round
21's Go fixture put 926 of 1094 findings in `(other)`. That whitelist is not a
bug to widen — `target()` also orders the id assignment, and the ids it produces
are arbitrary labels no analysis reads, so its only real requirements are that it
be deterministic and carry no arm signal. Widening it would renumber every id and
cost the round-19 byte-for-byte reproduction that file documents, to fix a column
nothing depends on.

So the split is derived here instead, and from the fixture diff rather than from
any list of extensions: the changed files are whatever the diff says they are.
A new language needs no change to this script.

A finding's `File:` field is free text and often names several files. It is
assigned to the changed file mentioned EARLIEST in that text, which is the one
the reviewer led with. A finding naming no changed file at all goes to
`unassigned` rather than being dropped — a silently missing finding is the
failure mode this whole pipeline is built to avoid.

Usage:  split_clusters.py <findings.tsv> <fixture.diff> <out-dir>
"""
import collections
import csv
import pathlib
import re
import sys

DIFF_PATH = re.compile(r'^\+\+\+ [ab]/(.+)$')
COLUMNS = ['id', 'severity', 'file', 'title', 'what_is_wrong']


def changed_files(diff_text):
    """Every path the diff writes to, in the order the diff introduces them."""
    out = []
    for line in diff_text.splitlines():
        m = DIFF_PATH.match(line)
        if m and m.group(1) != 'dev/null' and m.group(1) not in out:
            out.append(m.group(1))
    return out


def assign(field, files):
    """The changed file this finding is about: the one its File: names first."""
    hits = []
    for path in files:
        # A reviewer writes the path, the basename, or either in backticks. The
        # basename is what every form has in common.
        i = field.find(path.split('/')[-1])
        if i >= 0:
            hits.append((i, path))
    return min(hits)[1] if hits else 'unassigned'


def slug(path):
    return path.replace('/', '_').replace('.', '_').replace('-', '_')


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().splitlines()[-1].strip())
    findings, diff, out_dir = (pathlib.Path(p) for p in sys.argv[1:4])
    files = changed_files(diff.read_text())
    if not files:
        sys.exit(f'no changed files found in {diff} — is it a unified diff?')

    rows = list(csv.DictReader(findings.open(newline=''), delimiter='\t'))
    buckets = collections.defaultdict(list)
    for r in rows:
        buckets[assign(r['file'], files)].append(r)

    out_dir.mkdir(parents=True, exist_ok=True)
    for target, group in sorted(buckets.items(), key=lambda kv: -len(kv[1])):
        dest = out_dir / f'{slug(target)}.tsv'
        with dest.open('w', newline='') as fh:
            w = csv.DictWriter(fh, delimiter='\t', fieldnames=COLUMNS,
                               extrasaction='ignore')
            w.writeheader()
            w.writerows(group)
        print(f'{len(group):6d}  {dest.name}   ({target})')

    written = sum(len(g) for g in buckets.values())
    print(f'{written} findings over {len(buckets)} files')
    if written != len(rows):
        sys.exit(f'LOST FINDINGS: read {len(rows)}, wrote {written}')
    if 'unassigned' in buckets:
        print(f'{len(buckets["unassigned"])} findings named no changed file — '
              'they are in unassigned.tsv, not dropped')


if __name__ == '__main__':
    main()
