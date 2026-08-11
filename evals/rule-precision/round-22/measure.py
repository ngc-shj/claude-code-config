#!/usr/bin/env python3
"""Re-derive round 22: does round 20's confirmed effect replicate on F11?

Two arms, twenty-five FRESH reviews of three identical generalists each, on F11:

  W    clauses 1, 2, 3        W23  clauses 2, 3   (clause 1 removed)

Pre-registration: `../../rule-ablation/protocols/round-22.md`.

THE PRIMARY IS ROUND 20'S CONFIRMATORY METRIC, deliberately: Critical/Major
findings whose claim is adjudicated `not-a-defect`, all reasons, per review. That
is what makes "replicates" mean something exact.

ROUND 21'S NINE REVIEWS PER ARM ARE NOT HERE. Their value on this metric was
read before this round was designed, and testing the pooled series at .05 would
be a sequential design with no alpha-spending rule. The two rounds are reported
separately and combined by fixed-effect inverse-variance weighting, in
`combined.py`, which also computes the cross-study contrast D.

VERDICTS COME FROM TWO PLACES. The 71 claims round 21 already adjudicated keep
the verdicts pinned in `../round-21/`; only the 21 claims new to this round were
judged here. `merge-map.tsv` records which parallel-written new claims collapsed
into which.

INFERENCE IS WELCH. The arms share review indices and nothing else. The
index-paired analysis is a sensitivity check, never the primary.

MDE IS A DESIGN QUANTITY. It gated the spend before the arms were compared; the
observed difference is NOT required to exceed it. See `../methods.md`.

Usage:
  round-22/measure.py --gate   # observed MDE on the primary, no arm comparison
  round-22/measure.py          # the table
"""
import collections
import csv
import math
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.join(os.path.dirname(HERE), 'round-21')
ARMS = ('W', 'W23')
MDE_CEILING = 1.33          # the effect round 20 observed on F10, on this metric
Z_BETA = 0.842
T_PAIRED = {25: 2.064}      # two-sided .05 at df = n-1


def sheets(directory):
    out = []
    for name in sorted(os.listdir(directory)):
        rows = csv.DictReader(open(os.path.join(directory, name), newline=''),
                              delimiter='\t')
        out.append({r['cluster_id']: (r['verdict'].strip(), (r.get('reason') or '').strip())
                    for r in rows})
    return out


def reasons():
    """Majority reason among the sheets that called a claim not-a-defect."""
    out = {}
    for d in (os.path.join(PREV, 'adjudications'), os.path.join(HERE, 'adjudications')):
        ss = sheets(d)
        for cid in ss[0]:
            rs = [s[cid][1] for s in ss if s[cid][0] == 'not-a-defect']
            if rs:
                out[cid] = collections.Counter(rs).most_common(1)[0][0]
    return out


def labels():
    """Verdict by majority and the joint outside-diff label, over both rounds' sheets.

    Round 21's claims keep the verdicts recorded against them there. This round's
    panel judged only the claims that were new here.
    """
    verdict, joint = {}, set()
    for d in (os.path.join(PREV, 'adjudications'), os.path.join(HERE, 'adjudications')):
        ss = sheets(d)
        for cid in ss[0]:
            verdict[cid] = collections.Counter(s[cid][0] for s in ss).most_common(1)[0][0]
            if sum(1 for s in ss if s[cid] == ('not-a-defect', 'outside-diff')) >= 2:
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


def t_crit(df):
    table = {1: 12.706, 2: 4.303, 4: 2.776, 8: 2.306, 12: 2.179, 16: 2.120, 20: 2.086,
             24: 2.064, 28: 2.048, 30: 2.042, 40: 2.021, 48: 2.011, 60: 2.000, 120: 1.980}
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


def paired(a, b):
    d = [x - y for x, y in zip(a, b)]
    n = len(d)
    sd = st.stdev(d)
    se = sd / math.sqrt(n)
    half = T_PAIRED[n] * se
    return st.mean(d), sd, st.mean(d) / se if sd else 0.0, st.mean(d) - half, st.mean(d) + half


def main():
    verdict, joint = labels()
    reason = reasons()
    real = {c for c, x in verdict.items() if x == 'real'}
    f2c = assignment()
    by = by_review()
    cm = lambda f: f['severity'] in ('Critical', 'Major')

    primary = lambda fs: sum(1 for f in fs if cm(f)
                             and verdict[f2c[f['id']]] == 'not-a-defect')
    subtype = lambda fs: sum(1 for f in fs if cm(f) and f2c[f['id']] in joint)
    prim = series(by, primary)

    if '--gate' in sys.argv:
        print('POWER GATE — pre-registered to run before the arms are compared.\n'
              'No arm mean is printed here, by design.\n')
        d, se, df, t, mde, lo, hi = welch(prim['W'], prim['W23'])
        print(f'  arm sds                        W {st.stdev(prim["W"]):.3f}   '
              f'W23 {st.stdev(prim["W23"]):.3f}')
        print(f'  Welch df                       {df:.1f}')
        print(f'  observed Welch MDE at n=25     {mde:.2f}')
        print(f'  pre-registered ceiling         {MDE_CEILING:.2f}   '
              f'{"within" if mde <= MDE_CEILING else "EXCEEDS — report underpowered"}')
        print('\nIf this exceeds, the pre-registered response is to report the primary as\n'
              'underpowered. It is NOT to extend n.')
        return

    clusters = list(csv.DictReader(open(os.path.join(HERE, 'clusters.tsv'), newline=''),
                                   delimiter='\t'))
    new = {r['cluster_id'] for r in clusters if r['status'] == 'new'}
    here = {r['cluster_id'] for r in clusters}
    pinned = {r['cluster_id'] for r in
              csv.DictReader(open(os.path.join(PREV, 'clusters.tsv'), newline=''),
                             delimiter='\t')}
    print(f'{len(f2c)} findings.\n'
          f'  claims REACHED here            {len(here)}  '
          f'({len(here & pinned)} existing, {len(new)} new)\n'
          f'  of those, adjudicated real     {sum(1 for c in here if verdict[c] == "real")}\n'
          f'  round 21 inventory             {len(pinned)}  '
          f'({len(pinned - here)} of them not reached by any review here)\n'
          f'  cumulative inventory after     {len(pinned | new)}  '
          f'({len(real)} real across both rounds)\n')

    metrics = [
        ('PRIMARY   C+M not-a-defect, all reasons', primary),
        ('          C+M not-a-defect / outside-diff', subtype),
        ('          C+M wrong', lambda fs: sum(1 for f in fs if cm(f)
                                               and verdict[f2c[f['id']]] == 'wrong')),
        ('          .. not-a-defect / preference',
         lambda fs: sum(1 for f in fs if cm(f) and reason.get(f2c[f['id']]) == 'preference'
                        and verdict[f2c[f['id']]] == 'not-a-defect')),
        ('          .. not-a-defect / scope',
         lambda fs: sum(1 for f in fs if cm(f) and reason.get(f2c[f['id']]) == 'scope'
                        and verdict[f2c[f['id']]] == 'not-a-defect')),
        ('          .. not-a-defect / misreads-code',
         lambda fs: sum(1 for f in fs if cm(f) and reason.get(f2c[f['id']]) == 'misreads-code'
                        and verdict[f2c[f['id']]] == 'not-a-defect')),
        ('          real claims reached', lambda fs: len({f2c[f['id']] for f in fs
                                                          if f2c[f['id']] in real})),
        ('          findings written', len),
        ('          C+M not-a-defect on claims new here',
         lambda fs: sum(1 for f in fs if cm(f) and f2c[f['id']] in new
                        and verdict[f2c[f['id']]] == 'not-a-defect')),
    ]
    print(f'{"":43s}' + ''.join(f'{a:>8s}' for a in ARMS))
    rows = {}
    for label, metric in metrics:
        s = series(by, metric)
        rows[label] = s
        print(f'{label:43s}' + ''.join(f'{st.mean(s[a]):8.2f}' for a in ARMS))

    p = rows['PRIMARY   C+M not-a-defect, all reasons']
    print('\nPer review, the primary:')
    for a in ARMS:
        print(f'  {a:4s} {p[a]}')

    print('\nWELCH two-sample intervals, independent groups — the pre-registered inference.')
    print(f'{"":43s}{"diff":>8s}{"se":>7s}{"df":>6s}{"t":>7s}{"95% CI":>17s}{"MDE":>7s}')
    for label, key in (('CONFIRMATORY primary  W - W23',
                        'PRIMARY   C+M not-a-defect, all reasons'),
                       ('exploratory  outside-diff subtype',
                        '          C+M not-a-defect / outside-diff')):
        s = rows[key]
        d, se, df, t, mde, lo, hi = welch(s['W'], s['W23'])
        print(f'{label:43s}{d:8.2f}{se:7.3f}{df:6.1f}{t:7.2f}   '
              f'[{lo:6.2f},{hi:6.2f}]{mde:7.2f}')

    d, sd, t, lo, hi = paired(p['W'], p['W23'])
    print('\nSENSITIVITY — the nominal index-paired analysis. Not the primary.')
    print(f'{"primary W - W23":43s}{d:8.2f}{sd:7.3f}{t:7.2f}   [{lo:6.2f},{hi:6.2f}]')

    n = rows['          C+M not-a-defect on claims new here']
    tot = {a: sum(rows['PRIMARY   C+M not-a-defect, all reasons'][a]) for a in ARMS}
    print('\nNew-claim share of the primary, per arm — the pre-registered definition:\n'
          'C+M findings on a claim NEW here and adjudicated not-a-defect, over that arm\'s\n'
          'primary total. Reported because those claims, unlike the ones carried over,\n'
          'were adjudicated after this round\'s arms ran:')
    for a in ARMS:
        print(f'  {a:4s} {sum(n[a]):3d} / {tot[a]:4d} = {sum(n[a]) / tot[a]:.2%}')

    print('\nReal claims reached, per arm — recorded, read by no decision rule, and NOT\n'
          "comparable with F10's fixed inventory.")
    s = rows['          real claims reached']
    for a in ARMS:
        print(f'  {a:4s} mean {st.mean(s[a]):5.2f}')

    print('\nThe confirmatory rule is the primary Welch CI lying entirely below zero.\n'
          'The confidence interval, not the MDE, states which effect sizes remain\n'
          'compatible with the data.')


if __name__ == '__main__':
    main()
