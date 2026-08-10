#!/usr/bin/env python3
"""Re-derive round 21: does clause 1's effect land where predicted, and off F10?

Two arms, nine reviews of three identical generalists each, on F11:

  W    clauses 1, 2, 3        W23  clauses 2, 3   (clause 1 removed)

Pre-registration: `../../rule-ablation/protocols/round-21.md`.

THE PRIMARY IS A SUBTYPE, NOT A TOTAL. It counts Critical/Major findings whose
claim was adjudicated `not-a-defect` with reason `outside-diff` — the class the
hypothesis names. A claim enters it only when at least two of the three
adjudicators assigned that JOINT label; a claim two of them called
`not-a-defect` for different reasons does not. That rule is fixed in the
protocol, before the sheets were read.

INFERENCE IS WELCH, NOT PAIRED. The arms share review indices and nothing else:
there is no per-review preamble, so index i in one arm has no factor in common
with index i in the other. The index-paired analysis is computed and printed as
a sensitivity analysis, never as the primary.

MDE IS A DESIGN QUANTITY. It gates the spend before the arms are compared; the
observed difference is NOT required to exceed it. See `../methods.md`.

Usage:
  round-21/measure.py --gate   # subtype base rate and observed MDE, no comparison
  round-21/measure.py          # the table
"""
import collections
import csv
import math
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARMS = ('W', 'W23')
MDE_CEILING = 1.78          # the effect the subtype showed on F10 in round 20
Z_BETA = 0.842
T_PAIRED = {9: 2.306}       # two-sided .05 at df = n-1


def panels():
    """The three adjudication sheets, each as {cluster_id: (verdict, reason)}."""
    out = []
    for name in sorted(os.listdir(os.path.join(HERE, 'adjudications'))):
        rows = csv.DictReader(open(os.path.join(HERE, 'adjudications', name), newline=''),
                              delimiter='\t')
        out.append({r['cluster_id']: (r['verdict'].strip(), (r.get('reason') or '').strip())
                    for r in rows})
    return out


def labels(sheets):
    """(verdict by majority, joint outside-diff non-defect by 2-of-3)."""
    verdict, joint = {}, set()
    for cid in sheets[0]:
        vs = [s[cid][0] for s in sheets]
        verdict[cid] = collections.Counter(vs).most_common(1)[0][0]
        if sum(1 for s in sheets if s[cid] == ('not-a-defect', 'outside-diff')) >= 2:
            joint.add(cid)
    return verdict, joint


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


def welch(a, b):
    """(difference, se, df, t, MDE, CI low, CI high) for mean(a) - mean(b)."""
    na, nb = len(a), len(b)
    va, vb = st.variance(a), st.variance(b)
    se = math.sqrt(va / na + vb / nb)
    d = st.mean(a) - st.mean(b)
    if se == 0:
        return d, 0.0, float('nan'), 0.0, 0.0, d, d
    df = (va / na + vb / nb) ** 2 / ((va / na) ** 2 / (na - 1) + (vb / nb) ** 2 / (nb - 1))
    tc = t_crit(df)
    return d, se, df, d / se, (tc + Z_BETA) * se, d - tc * se, d + tc * se


def t_crit(df):
    """Two-sided .05 critical value, interpolated on a small table (no scipy)."""
    table = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365,
             8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179, 13: 2.160,
             14: 2.145, 15: 2.131, 16: 2.120, 17: 2.110, 18: 2.101, 19: 2.093,
             20: 2.086, 22: 2.074, 24: 2.064, 26: 2.056, 28: 2.048, 30: 2.042,
             40: 2.021, 60: 2.000, 120: 1.980}
    keys = sorted(table)
    if df <= keys[0]:
        return table[keys[0]]
    if df >= keys[-1]:
        return table[keys[-1]]
    lo = max(k for k in keys if k <= df)
    hi = min(k for k in keys if k >= df)
    if lo == hi:
        return table[lo]
    w = (df - lo) / (hi - lo)
    return table[lo] + w * (table[hi] - table[lo])


def paired(a, b):
    """(difference, sd_d, t, MDE, CI low, CI high) — the sensitivity analysis."""
    d = [x - y for x, y in zip(a, b)]
    n = len(d)
    sd = st.stdev(d)
    se = sd / math.sqrt(n)
    half = T_PAIRED[n] * se
    return (st.mean(d), sd, st.mean(d) / se if sd else 0.0,
            (T_PAIRED[n] + Z_BETA) * se, st.mean(d) - half, st.mean(d) + half)


def agreement(sheets, cids):
    """Pairwise agreement on the joint binary classification, and on the verdict."""
    def rate(f):
        hits = tot = 0
        for i in range(len(sheets)):
            for j in range(i + 1, len(sheets)):
                for c in cids:
                    tot += 1
                    hits += f(sheets[i][c]) == f(sheets[j][c])
        return hits / tot
    return rate(lambda x: x == ('not-a-defect', 'outside-diff')), rate(lambda x: x[0])


def main():
    sheets = panels()
    verdict, joint = labels(sheets)
    real = {c for c, x in verdict.items() if x == 'real'}
    f2c = assignment()
    by = by_review()
    cm = lambda f: f['severity'] in ('Critical', 'Major')

    primary = lambda fs: sum(1 for f in fs if cm(f) and f2c[f['id']] in joint)
    secondary = lambda fs: sum(1 for f in fs if cm(f)
                               and verdict[f2c[f['id']]] == 'not-a-defect')
    other = lambda fs: secondary(fs) - primary(fs)

    prim = series(by, primary)

    if '--gate' in sys.argv:
        print('POWER GATE — pre-registered to run before the arms are compared.\n'
              'The subtype base rate in W23 is printed first, because a floor effect\n'
              'is reported whatever the intervals say.\n')
        print(f'  W23 subtype mean, per review   {st.mean(prim["W23"]):.2f}   {prim["W23"]}')
        if st.mean(prim['W23']) < 1.0:
            print('  BELOW 1.0 — the fixture left the round no room to see its own effect.')
        d, se, df, t, mde, lo, hi = welch(prim['W'], prim['W23'])
        print(f'\n  arm sds                        W {st.stdev(prim["W"]):.3f}   '
              f'W23 {st.stdev(prim["W23"]):.3f}')
        print(f'  Welch df                       {df:.1f}')
        print(f'  observed Welch MDE at n=9      {mde:.2f}')
        print(f'  pre-registered ceiling         {MDE_CEILING:.2f}   '
              f'{"within" if mde <= MDE_CEILING else "EXCEEDS — report underpowered"}')
        print('\nIf this exceeds, the pre-registered response is to report the primary as\n'
              'underpowered. It is NOT to extend n.')
        return

    n_claims = len(verdict)
    print(f'{len(f2c)} findings, {n_claims} claims (all new to this fixture), '
          f'{len(real)} real, {len(joint)} joint outside-diff non-defects\n')

    jr, vr = agreement(sheets, list(verdict))
    print(f'adjudicator pairwise agreement   joint outside-diff label {jr:.1%}   '
          f'verdict {vr:.1%}\n')

    metrics = [
        ('PRIMARY   C+M not-a-defect / outside-diff', primary),
        ('SECONDARY C+M not-a-defect, all reasons', secondary),
        ('          C+M not-a-defect, other reasons', other),
        ('          C+M wrong', lambda fs: sum(1 for f in fs if cm(f)
                                               and verdict[f2c[f['id']]] == 'wrong')),
        ('          real claims reached', lambda fs: len({f2c[f['id']] for f in fs
                                                          if f2c[f['id']] in real})),
        ('          findings written', len),
    ]
    print(f'{"":43s}' + ''.join(f'{a:>8s}' for a in ARMS))
    rows = {}
    for label, metric in metrics:
        s = series(by, metric)
        rows[label] = s
        print(f'{label:43s}' + ''.join(f'{st.mean(s[a]):8.2f}' for a in ARMS))

    p = rows['PRIMARY   C+M not-a-defect / outside-diff']
    print('\nPer review, the primary:')
    for a in ARMS:
        print(f'  {a:4s} {p[a]}')

    print('\nWELCH two-sample intervals, independent groups — the pre-registered inference.')
    print(f'{"":43s}{"diff":>8s}{"se":>7s}{"df":>6s}{"t":>7s}{"95% CI":>17s}{"MDE":>7s}')
    for label, key in (('CONFIRMATORY primary  W - W23',
                        'PRIMARY   C+M not-a-defect / outside-diff'),
                       ('exploratory  secondary W - W23',
                        'SECONDARY C+M not-a-defect, all reasons'),
                       ('exploratory  other reasons W - W23',
                        '          C+M not-a-defect, other reasons')):
        s = rows[key]
        d, se, df, t, mde, lo, hi = welch(s['W'], s['W23'])
        print(f'{label:43s}{d:8.2f}{se:7.3f}{df:6.1f}{t:7.2f}   '
              f'[{lo:6.2f},{hi:6.2f}]{mde:7.2f}')

    print('\nSENSITIVITY — the nominal index-paired analysis. Not the primary.')
    print(f'{"":43s}{"diff":>8s}{"sd_d":>7s}{"t":>7s}{"95% CI":>17s}')
    for label, key in (('primary   W - W23',
                        'PRIMARY   C+M not-a-defect / outside-diff'),
                       ('secondary W - W23',
                        'SECONDARY C+M not-a-defect, all reasons')):
        s = rows[key]
        d, sd, t, mde, lo, hi = paired(s['W'], s['W23'])
        print(f'{label:43s}{d:8.2f}{sd:7.3f}{t:7.2f}   [{lo:6.2f},{hi:6.2f}]')

    dd = (st.mean(rows['PRIMARY   C+M not-a-defect / outside-diff']['W'])
          - st.mean(rows['PRIMARY   C+M not-a-defect / outside-diff']['W23'])) - \
         (st.mean(rows['          C+M not-a-defect, other reasons']['W'])
          - st.mean(rows['          C+M not-a-defect, other reasons']['W23']))
    print(f'\nRECORDED, exploratory: d(outside-diff) - d(other reasons) = {dd:+.2f}')
    print('Calling the effect selective would require this to be the pre-registered test,\n'
          'with its own n. It is not, and this round is not sized for it.')

    print('\nReal defects reached, per arm — recorded, read by no decision rule, and NOT\n'
          "comparable with F10's fixed inventory: this claim space is arm-generated.")
    s = rows['          real claims reached']
    for a in ARMS:
        print(f'  {a:4s} mean {st.mean(s[a]):5.2f}   {s[a]}')

    print('\nThe confirmatory rule is the primary Welch CI lying entirely below zero.\n'
          'An interval that crosses zero is a failure to detect, never a demonstration\n'
          'that the effect is absent.')


if __name__ == '__main__':
    main()
