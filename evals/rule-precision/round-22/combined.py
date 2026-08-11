#!/usr/bin/env python3
"""The two exploratory cross-round quantities round 22 pre-registered.

Both are EXPLORATORY. Neither is in the confirmatory rule, and round 22's gate
fired, so neither licenses a claim about replication.

1. The COMBINED estimate over rounds 21 and 22, on the primary metric
   (Critical/Major `not-a-defect`, all reasons, per review). Round is the
   blocking factor and the combination is fixed-effect inverse-variance:

       w_i = 1/SE_i^2 ,  d_bar = sum(w_i d_i)/sum(w_i) ,  SE = 1/sqrt(sum w_i)

   No random-effects variance is estimated: two rounds cannot support one. A
   naive pool of the 34 reviews per arm is deliberately NOT computed — it would
   merge two samples drawn under different designs and hide which round carries
   the result.

2. D = delta_F11 - delta_F10, the only quantity that speaks to whether the two
   fixtures' effects differ. delta_F10 is round 20's same two arms re-estimated
   UNPAIRED by Welch for comparability; round 20's own paired interval is printed
   beside it, since that is the form its README states.

   D is a DESCRIPTIVE CROSS-STUDY HETEROGENEITY CONTRAST. Fixture is confounded
   with round, inventory history, and review batch, so the interval cannot
   attribute any difference to the fixture alone.

Usage:  round-22/combined.py
"""
import collections
import csv
import glob
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
EVALS = os.path.dirname(HERE)
ARMS = ('W', 'W23')


def t_crit(df):
    table = {1: 12.706, 2: 4.303, 4: 2.776, 8: 2.306, 12: 2.179, 14: 2.145, 16: 2.120,
             20: 2.086, 24: 2.064, 28: 2.048, 30: 2.042, 40: 2.021, 48: 2.011,
             60: 2.000, 120: 1.980}
    keys = sorted(table)
    if df <= keys[0]:
        return table[keys[0]]
    if df >= keys[-1]:
        return table[keys[-1]]
    lo = max(k for k in keys if k <= df)
    hi = min(k for k in keys if k >= df)
    if lo == hi:
        return table[lo]
    return table[lo] + (df - lo) / (hi - lo) * (table[hi] - table[lo])


def welch(a, b):
    """(difference, se, df) for mean(a) - mean(b), independent groups."""
    na, nb = len(a), len(b)
    va, vb = st.variance(a), st.variance(b)
    se = math.sqrt(va / na + vb / nb)
    df = (va / na + vb / nb) ** 2 / ((va / na) ** 2 / (na - 1) + (vb / nb) ** 2 / (nb - 1))
    return st.mean(a) - st.mean(b), se, df


def verdicts(sheet_dirs, seed=None):
    """Majority verdict per claim, later sheets overriding earlier ones."""
    out = dict(seed or {})
    for d in sheet_dirs:
        paths = sorted(glob.glob(os.path.join(d, '*.tsv')))
        if not paths:
            continue
        sheets = [{r['cluster_id']: r['verdict'].strip() for r in
                   csv.DictReader(open(p, newline=''), delimiter='\t')} for p in paths]
        for cid in sheets[0]:
            out[cid] = collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
    return out


def primary_series(round_dir, verdict):
    f2c = {}
    for r in csv.DictReader(open(os.path.join(round_dir, 'clusters.tsv'), newline=''),
                            delimiter='\t'):
        for fid in r['member_ids'].split(','):
            f2c[fid.strip()] = r['cluster_id']
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in csv.DictReader(open(os.path.join(round_dir, 'findings.tsv'), newline=''),
                            delimiter='\t'):
        by[f['arm']][f['review']].append(f)
    order = sorted(by['W'], key=int)
    cm = lambda f: f['severity'] in ('Critical', 'Major')
    return {a: [sum(1 for f in by[a][k] if cm(f)
                    and verdict[f2c[f['id']]] == 'not-a-defect') for k in order]
            for a in ARMS}


def paired(a, b):
    d = [x - y for x, y in zip(a, b)]
    n = len(d)
    se = st.stdev(d) / math.sqrt(n)
    half = t_crit(n - 1) * se
    return st.mean(d), se, st.mean(d) - half, st.mean(d) + half


def main():
    r21 = os.path.join(EVALS, 'round-21')
    r22 = HERE
    r20 = os.path.join(EVALS, 'round-20')

    v_f11 = verdicts([os.path.join(r21, 'adjudications'),
                      os.path.join(r22, 'adjudications')])
    s21 = primary_series(r21, v_f11)
    s22 = primary_series(r22, v_f11)
    d21 = welch(s21['W'], s21['W23'])
    d22 = welch(s22['W'], s22['W23'])

    print('PRIMARY METRIC, per round — C+M not-a-defect, all reasons, per review\n')
    print(f'{"":26s}{"n/arm":>7s}{"diff":>8s}{"se":>7s}{"df":>7s}{"95% CI":>18s}')
    for label, s, d in (('round 21 (exploratory)', s21, d21),
                        ('round 22 (gate fired)', s22, d22)):
        t = t_crit(d[2])
        print(f'{label:26s}{len(s["W"]):7d}{d[0]:8.2f}{d[1]:7.3f}{d[2]:7.1f}'
              f'   [{d[0] - t * d[1]:6.2f},{d[0] + t * d[1]:6.2f}]')

    ws = [1 / d21[1] ** 2, 1 / d22[1] ** 2]
    ds = [d21[0], d22[0]]
    db = sum(w * d for w, d in zip(ws, ds)) / sum(ws)
    seb = 1 / math.sqrt(sum(ws))
    print(f'\n{"COMBINED, fixed-effect IV":26s}{"":7s}{db:8.2f}{seb:7.3f}{"":7s}'
          f'   [{db - 1.96 * seb:6.2f},{db + 1.96 * seb:6.2f}]   (normal interval)')
    print('Weights: ' + '  '.join(f'round {r} {w / sum(ws):.0%}'
                                  for r, w in zip((21, 22), ws)))
    print('\nEXPLORATORY. Round 22\'s gate fired, so this licenses no claim about\n'
          'replication; it is the two rounds\' estimates put on one line.')

    # D — F10 from round 20, same two arms, re-estimated unpaired
    seed = {r['cluster_id']: r['verdict'].strip() for r in
            csv.DictReader(open(os.path.join(EVALS, 'round-16', 'seed', 'inventory.tsv'),
                                newline=''), delimiter='\t')}
    v_f10 = verdicts([os.path.join(EVALS, f'round-{n}', 'adjudications')
                      for n in (17, 18, 19, 20)], seed=seed)
    s20 = primary_series(r20, v_f10)
    d20 = welch(s20['W'], s20['W23'])
    p20 = paired(s20['W'], s20['W23'])
    t20 = t_crit(d20[2])

    print('\n\nD = delta_F11 - delta_F10 — descriptive cross-study heterogeneity contrast\n')
    print(f'  delta_F10  round 20, unpaired Welch   {d20[0]:6.2f}  se {d20[1]:.3f}  '
          f'df {d20[2]:.1f}   [{d20[0] - t20 * d20[1]:6.2f},{d20[0] + t20 * d20[1]:6.2f}]')
    print(f'             round 20, paired (its README form)   {p20[0]:6.2f}  '
          f'se {p20[1]:.3f}   [{p20[2]:6.2f},{p20[3]:6.2f}]')
    print(f'  delta_F11  round 22, fresh 25/arm      {d22[0]:6.2f}  se {d22[1]:.3f}  '
          f'df {d22[2]:.1f}')
    D = d22[0] - d20[0]
    seD = math.sqrt(d22[1] ** 2 + d20[1] ** 2)
    dfD = (d22[1] ** 2 + d20[1] ** 2) ** 2 / (d22[1] ** 4 / d22[2] + d20[1] ** 4 / d20[2])
    tD = t_crit(dfD)
    print(f'\n  D = {D:+.2f}   SE {seD:.3f}   df {dfD:.1f}   '
          f'95% CI [{D - tD * seD:+.2f}, {D + tD * seD:+.2f}]')
    print('\nFixture is confounded with round, inventory history, and review batch, so\n'
          'this interval cannot attribute any difference to the fixture alone. It is\n'
          'recorded, it is exploratory, and it fires no rule.')


if __name__ == '__main__':
    main()
