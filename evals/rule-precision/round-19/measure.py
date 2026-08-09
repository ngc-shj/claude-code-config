#!/usr/bin/env python3
"""Re-derive round 19: W, W2 and N on one ruler.

Six reviews of three identical generalists per arm on F10, all three arms in one
batch, interleaved review by review:

  W   the Finding Floor's three clauses, wired by the digest line
  W2  clause 2 alone, renumbered, rationale kept
  N   the section and its digest paragraph removed

Pre-registration, including why the comparator is N and why three arms cannot
say which of clause 1 and clause 3 matters:
`../../rule-ablation/protocols/round-19.md`.

ONE INFERENTIAL COMPARISON. Only W vs N can fire the decision rule. W vs W2 is
secondary and pre-declared underpowered; W2 vs N is calibration. Multiplicity is
handled by fixing that in advance, not by correcting alpha afterwards.

PAIRED. The arms share review indices, so the statistic, the sd and the MDE are
computed on the per-review difference. The protocol is explicit that this buys
no power here — every review within an arm got an identical brief, so index i
shares nothing across arms — and that the paired test is nonetheless what a
paired design asserts.

THE CONTROL FIRES NO RULE. Real defects reached are printed per arm and nothing
is concluded from them. Calling a flat control "within its MDE" would use an
observed-variance quantity as an equivalence margin, which lets a noisier arm
license a larger real-defect loss.

Usage:
  round-19/measure.py --gate      # observed sd_d and MDE on the primary, no arm mean
  round-19/measure.py             # the table
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
MDE_CEILING = 2.67           # the effect round 17 measured for the full section
T_PAIRED = {6: 2.571}        # two-sided .05 at df = n-1
Z_BETA = 0.842


def verdicts():
    """F10's inventory, then this round's — no claim is judged twice."""
    v = {r['cluster_id']: r['verdict'].strip() for r in
         csv.DictReader(open(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'),
                             newline=''), delimiter='\t')}
    for pattern in ('round-17/adjudications/*.tsv', 'round-18/adjudications/*.tsv',
                    None):
        paths = (sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv')))
                 if pattern is None else
                 sorted(glob.glob(os.path.join(PREV, pattern))))
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
    rows = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv'), newline=''),
                               delimiter='\t'))
    out = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in rows:
        out[f['arm']][f['review']].append(f)
    return out


def series(by, metric):
    order = sorted(by['W'], key=int)
    return {a: [metric(by[a][k]) for k in order] for a in ('W', 'W2', 'N')}


def paired(a, b):
    """(mean difference, sd_d, t, MDE, CI low, CI high) for a - b.

    The MDE is here for the gate only. Whether the round SAW an effect is the
    t and the interval; requiring the observed difference to exceed the MDE is a
    stricter bar than alpha=.05 applied by accident. See `../methods.md`."""
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
        _, sd, _, obs, _, _ = paired(prim['W'], prim['N'])
        print(f'PRIMARY W - N, paired')
        print(f'  observed sd of differences   {sd:.3f}')
        print(f'  observed MDE at n=6          {obs:.2f}')
        print(f'  pre-registered ceiling       {MDE_CEILING:.2f}   '
              f'{"within" if obs <= MDE_CEILING else "EXCEEDS — report underpowered"}')
        print('\nIf this exceeds, the pre-registered response is to report the primary as\n'
              'underpowered. It is NOT to extend n.')
        return

    metrics = [
        ('PRIMARY   C+M not-a-defect', primary),
        ('SECONDARY C+M wrong', lambda fs: sum(1 for f in fs if cm(f)
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
    print(f'{"":34s}{"W":>7s}{"W2":>7s}{"N":>7s}')
    rows = {}
    for label, metric in metrics:
        s = series(by, metric)
        rows[label] = s
        print(f'{label:34s}{st.mean(s["W"]):7.2f}{st.mean(s["W2"]):7.2f}{st.mean(s["N"]):7.2f}')
        for a in ('W', 'W2', 'N'):
            print(f'{"":34s}{a:>3s} {s[a]}')

    print('\nPAIRED comparisons on the primary metric, per review.')
    print('Only W - N was confirmatory. The others are EXPLORATORY and are'
          '\nreported with their numbers rather than promoted or discounted.')
    print(f'{"":30s}{"diff":>8s}{"sd_d":>8s}{"t":>8s}{"95% CI":>18s}{"MDE":>8s}')
    for label, x, y in (('CONFIRMATORY W  - N ', 'W', 'N'),
                        ('exploratory  W  - W2', 'W', 'W2'),
                        ('exploratory  W2 - N ', 'W2', 'N')):
        s = rows['PRIMARY   C+M not-a-defect']
        d, sd, t, m, lo, hi = paired(s[x], s[y])
        print(f'{label:30s}{d:8.2f}{sd:8.3f}{t:8.2f}   [{lo:6.2f},{hi:6.2f}]{m:8.2f}')
    print(f'\nt_crit at df={len(rows["PRIMARY   C+M not-a-defect"]["W"]) - 1} '
          f'is {T_PAIRED[6]}. The MDE column is the DESIGN quantity the gate used;'
          '\nit is not a bar the observed difference has to clear. See ../methods.md.')

    print('\nReal defects reached, per arm — recorded, read by no decision rule.')
    s = rows['          real claims reached']
    for a in ('W', 'W2', 'N'):
        print(f'  {a:3s} mean {st.mean(s[a]):5.2f}   {s[a]}')


if __name__ == '__main__':
    main()
