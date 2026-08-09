#!/usr/bin/env python3
"""Re-derive round 20: which of the Finding Floor's clauses 1 and 3 contributes?

Nine reviews of three identical generalists per arm on F10, four arms in one
batch — a 2x2 in (clause 1) x (clause 3) with clause 2 always present:

  W    clauses 1, 2, 3        W12  clauses 1, 2
  W23  clauses 2, 3           W2   clause 2 alone

Pre-registration: `../../rule-ablation/protocols/round-20.md`.

WHAT THIS IDENTIFIES: the positive contribution of each clause in the presence
of the others. It is NOT a non-inferiority design, and a null on any comparison
cannot license deleting the clause it isolates.

ONE CONFIRMATORY COMPARISON: W - W23, the contribution of clause 1. Its rule is
that the 95% CI lies entirely below zero. Everything else is exploratory and is
reported with its numbers.

MDE IS A DESIGN QUANTITY. It gates the spend before the run; the observed
difference is NOT required to exceed it. See `../methods.md`, which round 19 is
the worked example for.

Usage:
  round-20/measure.py --gate      # observed sd_d and MDE on the primary, no arm mean
  round-20/measure.py             # the table
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
ARMS = ('W', 'W12', 'W23', 'W2')
MDE_CEILING = 1.83          # the joint contribution clauses 1 and 3 showed in round 19
T_PAIRED = {9: 2.306}       # two-sided .05 at df = n-1
Z_BETA = 0.842


def verdicts():
    """F10's inventory, then this round's — no claim is judged twice."""
    v = {r['cluster_id']: r['verdict'].strip() for r in
         csv.DictReader(open(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'),
                             newline=''), delimiter='\t')}
    for pattern in ('round-17/adjudications/*.tsv', 'round-18/adjudications/*.tsv',
                    'round-19/adjudications/*.tsv', None):
        paths = (sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv')))
                 if pattern is None else sorted(glob.glob(os.path.join(PREV, pattern))))
        if not paths:
            continue
        sheets = [{r['cluster_id']: r['verdict'].strip() for r in
                   csv.DictReader(open(p, newline=''), delimiter='\t')} for p in paths]
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
    out = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in csv.DictReader(open(os.path.join(HERE, 'findings.tsv'), newline=''),
                            delimiter='\t'):
        out[f['arm']][f['review']].append(f)
    return out


def series(by, metric):
    order = sorted(by['W'], key=int)
    return {a: [metric(by[a][k]) for k in order] for a in ARMS}


def paired(a, b):
    """(mean difference, sd_d, t, MDE, CI low, CI high) for a - b."""
    d = [x - y for x, y in zip(a, b)]
    n = len(d)
    sd = st.stdev(d)
    se = sd / math.sqrt(n)
    t = st.mean(d) / se if sd else 0.0
    half = T_PAIRED[n] * se
    return (st.mean(d), sd, t, (T_PAIRED[n] + Z_BETA) * se,
            st.mean(d) - half, st.mean(d) + half)


def main():
    v = verdicts()
    real = {c for c, x in v.items() if x == 'real'}
    f2c = assignment()
    by = by_review()
    cm = lambda f: f['severity'] in ('Critical', 'Major')
    primary = lambda fs: sum(1 for f in fs if cm(f) and v[f2c[f['id']]] == 'not-a-defect')
    prim = series(by, primary)

    if '--gate' in sys.argv:
        print('POWER GATE — pre-registered to run before any arm comparison.\n'
              'No arm mean is printed here, by design.\n')
        _, sd, _, obs, _, _ = paired(prim['W'], prim['W23'])
        print('PRIMARY W - W23, paired')
        print(f'  observed sd of differences   {sd:.3f}')
        print(f'  observed MDE at n=9          {obs:.2f}')
        print(f'  pre-registered ceiling       {MDE_CEILING:.2f}   '
              f'{"within" if obs <= MDE_CEILING else "EXCEEDS — report underpowered"}')
        print('\nIf this exceeds, the pre-registered response is to report the primary as'
              '\nunderpowered. It is NOT to extend n. The MDE gates the spend; it is not'
              '\na bar the observed difference has to clear.')
        return

    metrics = [
        ('PRIMARY   C+M not-a-defect', primary),
        ('          C+M wrong', lambda fs: sum(1 for f in fs if cm(f)
                                               and v[f2c[f['id']]] == 'wrong')),
        ('          C+M not real (r12/r17)', lambda fs: sum(1 for f in fs if cm(f)
                                                            and f2c[f['id']] not in real)),
        ('          real claims reached', lambda fs: len({f2c[f['id']] for f in fs
                                                          if f2c[f['id']] in real})),
        ('          findings written', len),
    ]
    n_new = sum(1 for r in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv'),
                                               newline=''), delimiter='\t')
                if r['status'] == 'new')
    print(f'{len(f2c)} findings, {len(v)} claims in the inventory ({n_new} added here), '
          f'{len(real)} real\n')
    print(f'{"":34s}' + ''.join(f'{a:>8s}' for a in ARMS))
    rows = {}
    for label, metric in metrics:
        s = series(by, metric)
        rows[label] = s
        print(f'{label:34s}' + ''.join(f'{st.mean(s[a]):8.2f}' for a in ARMS))

    p = rows['PRIMARY   C+M not-a-defect']
    print('\nPer review, C+M not-a-defect:')
    for a in ARMS:
        print(f'  {a:4s} {p[a]}')

    print('\nPAIRED comparisons on the primary metric.')
    print(f'{"":34s}{"diff":>8s}{"sd_d":>7s}{"t":>7s}{"95% CI":>17s}{"MDE":>7s}')
    for label, x, y in (('CONFIRMATORY W - W23  (clause 1)', 'W', 'W23'),
                        ('exploratory  W - W12  (clause 3)', 'W', 'W12'),
                        ('exploratory  W12 - W2 (clause 1)', 'W12', 'W2'),
                        ('exploratory  W23 - W2 (clause 3)', 'W23', 'W2')):
        d, sd, t, m, lo, hi = paired(p[x], p[y])
        print(f'{label:34s}{d:8.2f}{sd:7.3f}{t:7.2f}   [{lo:6.2f},{hi:6.2f}]{m:7.2f}')

    inter = [(w - w23) - (w12 - w2) for w, w12, w23, w2
             in zip(p['W'], p['W12'], p['W23'], p['W2'])]
    sd_i = st.stdev(inter)
    se_i = sd_i / math.sqrt(len(inter))
    half = T_PAIRED[len(inter)] * se_i
    print(f'{"exploratory  2x2 interaction":34s}{st.mean(inter):8.2f}{sd_i:7.3f}'
          f'{st.mean(inter) / se_i if sd_i else 0:7.2f}   '
          f'[{st.mean(inter) - half:6.2f},{st.mean(inter) + half:6.2f}]')

    print(f'\nt_crit at df={len(p["W"]) - 1} is {T_PAIRED[9]}. Only W - W23 is confirmatory;'
          '\nits rule is that the CI lies entirely below zero. The MDE column is the'
          '\ndesign quantity the gate used, not a bar the difference must clear.')

    print('\nReal defects reached, per arm — recorded, read by no decision rule.')
    s = rows['          real claims reached']
    for a in ARMS:
        print(f'  {a:4s} mean {st.mean(s[a]):5.2f}   {s[a]}')


if __name__ == '__main__':
    main()
