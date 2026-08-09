#!/usr/bin/env python3
"""Re-derive round 18: is the Finding Floor reducible to its second clause?

Six reviews of three identical generalists per arm on F10, arms interleaved so
neither sits systematically earlier:

  W2  the catalogue at HEAD with Finding Floor clauses 1 and 3 removed; clause 2
      alone remains, renumbered, its digest wiring intact
  N   the catalogue at HEAD with the whole Finding Floor section removed and its
      digest paragraph reverted — round 17's N arm, re-run in this batch

Pre-registration, including why the comparator is N and not W:
`../../rule-ablation/protocols/round-18.md`.

  findings.tsv          every finding, with arm, review and reviewer position
  clusters.tsv          each finding assigned to a claim; `status` marks the
                        ones this round adds to F10's 94-claim inventory
  adjudications/*.tsv   three agents on the NEW claims only

Verdicts for existing claims come from `../round-16/seed/inventory.tsv` and
`../round-17/adjudications/` unchanged. No claim is judged twice.

THE PRIMARY IS THE SPLIT, AND THIS IS ITS FIRST PRE-REGISTERED USE. Rounds 12
and 17 counted Critical/Major findings that are not `real`, which merges
`not-a-defect` with `wrong`. `../decompose.py` showed the floor acts on the
first and not the second; that analysis was post-hoc and this round is where the
split is committed to in advance. The composite is still printed, for
comparability with rounds 12 and 17 and for nothing else.

THE GATE RUNS FIRST AND ALONE, and it is pre-registered as the quantity rather
than as an sd ceiling: if the observed MDE on the primary exceeds 2.67 — the
effect the full floor produced on F10 — the round reports underpowered and makes
no adoption claim. It does NOT extend n.

Usage:
  round-18/measure.py --gate      # observed sd and MDE, no arm mean
  round-18/measure.py             # the table
"""
import collections
import csv
import glob
import math
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.dirname(HERE)
ARMS = ('W2', 'N')
MDE_CEILING = 2.67           # the effect the full floor produced on F10
T_CRIT = {6: 2.228}          # two-sided .05 at df = 2(n-1)
Z_BETA = 0.842


def verdicts():
    """F10's inventory, then this round's — no claim is judged twice."""
    v = {r['cluster_id']: r['verdict'].strip() for r in
         csv.DictReader(open(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'),
                             newline=''), delimiter='\t')}
    for pattern in (os.path.join(PREV, 'round-17', 'adjudications', '*.tsv'),
                    os.path.join(HERE, 'adjudications', '*.tsv')):
        sheets = [{r['cluster_id']: r['verdict'].strip() for r in
                   csv.DictReader(open(p, newline=''), delimiter='\t')}
                  for p in sorted(glob.glob(pattern))]
        if not sheets:
            continue
        for cid in sheets[0]:
            v[cid] = collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
    return v


def assignment():
    out = {}
    for row in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv'), newline=''),
                              delimiter='\t'):
        for fid in row['member_ids'].split(','):
            out[fid.strip()] = row['cluster_id']
    return out


def by_review():
    rows = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv'), newline=''),
                               delimiter='\t'))
    out = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in rows:
        out[f['arm']][f['review']].append(f)
    return out, rows


def series(by, metric):
    order = sorted(by[ARMS[0]], key=int)
    return {a: [metric(by[a][k]) for k in order] for a in ARMS}


def pooled_sd(a, b):
    return math.sqrt((st.variance(a) + st.variance(b)) / 2)


def mde(a, b):
    n = min(len(a), len(b))
    return (T_CRIT[n] + Z_BETA) * pooled_sd(a, b) * math.sqrt(2 / n)


def main():
    v = verdicts()
    real = {c for c, x in v.items() if x == 'real'}
    f2c = assignment()
    by, rows = by_review()

    cm = lambda f: f['severity'] in ('Critical', 'Major')
    metrics = [
        ('PRIMARY   C+M not-a-defect', lambda fs: sum(1 for f in fs if cm(f)
                                                      and v[f2c[f['id']]] == 'not-a-defect')),
        ('SECONDARY C+M wrong', lambda fs: sum(1 for f in fs if cm(f)
                                               and v[f2c[f['id']]] == 'wrong')),
        ('          C+M not real (r12/r17)', lambda fs: sum(1 for f in fs if cm(f)
                                                            and f2c[f['id']] not in real)),
        ('CONTROL   real claims reached', lambda fs: len({f2c[f['id']] for f in fs
                                                          if f2c[f['id']] in real})),
        ('          findings written', len),
    ]
    prim = series(by, metrics[0][1])

    if '--gate' in sys.argv:
        print('POWER GATE — pre-registered to run before any arm comparison.\n'
              'No arm mean is printed here, by design.\n')
        a, b = prim[ARMS[0]], prim[ARMS[1]]
        obs = mde(a, b)
        print(f'observed pooled sd on the primary   {pooled_sd(a, b):.3f}')
        print(f'observed MDE at n={len(a)}              {obs:.2f}')
        print(f'pre-registered ceiling              {MDE_CEILING:.2f}   '
              f'{"within" if obs <= MDE_CEILING else "EXCEEDS — report underpowered"}')
        print('\nIf this exceeds, the pre-registered response is to report the '
              'comparison as\nunderpowered. It is NOT to extend n.')
        return

    n_new = sum(1 for r in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv'),
                                               newline=''), delimiter='\t')
                if r['status'] == 'new')
    print(f'{len(f2c)} findings, {len(v)} claims in the inventory ({n_new} added here), '
          f'{len(real)} real\n')
    print(f'{"":34s}{ARMS[0]:>8s}{ARMS[1]:>8s}{"t":>8s}{"MDE@80%":>10s}')
    for label, metric in metrics:
        s = series(by, metric)
        a, b = s[ARMS[0]], s[ARMS[1]]
        sp = pooled_sd(a, b)
        t = (st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / len(a))) if sp else 0.0
        print(f'{label:34s}{st.mean(a):8.2f}{st.mean(b):8.2f}{t:8.2f}{mde(a, b):10.2f}')
        print(f'{"":34s}{ARMS[0]} {a}\n{"":34s}{ARMS[1]} {b}')


if __name__ == '__main__':
    main()
