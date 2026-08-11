#!/usr/bin/env python3
"""Descriptive audit: which components carried the primary's sd increase?

Round 21's se on the primary (C+M not-a-defect, all reasons, per review) implied
per-arm sds near 1.42. Round 22 measured 1.895 (W) and 1.590 (W23), which fired
its gate. This asks WHICH COMPONENT of the per-review count that growth sits in.

IT ESTABLISHES NO CAUSE AND RUNS NO TEST. Every number here is descriptive. No
quantity in it may be used to justify a hypothesis, an n, or a gate for a later
round.

Inputs are pinned at fa7658ca032b727df3584410530d21f45a4e5802.
"""
import collections
import csv
import glob
import itertools
import math
import os
import statistics as st

EVALS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARMS = ('W', 'W23')
PARTS = ('a', 'b', 'c')
# review index == the order the batches were launched; the five-hour window reset
# between index 15 and index 16 of round 22. That is execution bookkeeping, not a
# designed factor.
R22_WINDOW_BREAK = 15


def _norm_inv(p):
    """Inverse standard normal CDF (Acklam), adequate for the quantiles used here."""
    a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00]
    lo = 0.02425
    if p < lo:
        q = math.sqrt(-2 * math.log(p))
        return ((((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1))
    if p > 1 - lo:
        q = math.sqrt(-2 * math.log(1 - p))
        return -((((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                 / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1))
    q = p - 0.5
    r = q * q
    return ((((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1))


def chi2_quantile(p, df):
    """Wilson-Hilferty approximation to the chi-square quantile."""
    z = _norm_inv(p)
    return df * (1 - 2 / (9 * df) + z * math.sqrt(2 / (9 * df))) ** 3


def sd_interval(variance, n, conf=0.95):
    """Normal-theory chi-square interval for the population sd.

    The quantile is Wilson-Hilferty, not exact: at these df it agrees with a
    table to about the third decimal, which is finer than anything read off it
    here. Reported as approximate wherever it is printed.
    """
    df = n - 1
    a = (1 - conf) / 2
    return (math.sqrt(df * variance / chi2_quantile(1 - a, df)),
            math.sqrt(df * variance / chi2_quantile(a, df)))


def sheet_verdicts(dirs):
    out = {}
    for d in dirs:
        paths = sorted(glob.glob(os.path.join(d, '*.tsv')))
        if not paths:
            continue
        ss = [{r['cluster_id']: (r['verdict'].strip(), (r.get('reason') or '').strip())
               for r in csv.DictReader(open(p, newline=''), delimiter='\t')} for p in paths]
        for cid in ss[0]:
            v = collections.Counter(s[cid][0] for s in ss).most_common(1)[0][0]
            rs = [s[cid][1] for s in ss if s[cid][0] == 'not-a-defect']
            out[cid] = (v, collections.Counter(rs).most_common(1)[0][0] if rs else '')
    return out


def load(round_dir, verdict):
    f2c = {}
    status = {}
    for r in csv.DictReader(open(os.path.join(round_dir, 'clusters.tsv'), newline=''),
                            delimiter='\t'):
        status[r['cluster_id']] = r['status']
        for fid in r['member_ids'].split(','):
            f2c[fid.strip()] = r['cluster_id']
    rows = list(csv.DictReader(open(os.path.join(round_dir, 'findings.tsv'), newline=''),
                               delimiter='\t'))
    return rows, f2c, status


def counts(rows, f2c, verdict, pred):
    """{(arm, review, part): count} under a predicate on (finding, cluster_id)."""
    out = collections.Counter()
    for f in rows:
        cid = f2c[f['id']]
        if pred(f, cid):
            out[(f['arm'], int(f['review']), f['part'])] += 1
    return out


def per_review(c, arm, reviews, parts=PARTS):
    return [sum(c.get((arm, i, p), 0) for p in parts) for i in reviews]


def fmt(xs):
    return f'mean {st.mean(xs):5.2f}  sd {st.stdev(xs):5.3f}  var {st.variance(xs):6.3f}'


def main():
    v21 = sheet_verdicts([os.path.join(EVALS, 'round-21', 'adjudications')])
    v22 = sheet_verdicts([os.path.join(EVALS, 'round-21', 'adjudications'),
                          os.path.join(EVALS, 'round-22', 'adjudications')])
    r21 = load(os.path.join(EVALS, 'round-21'), v21)
    r22 = load(os.path.join(EVALS, 'round-22'), v22)
    cm = lambda f: f['severity'] in ('Critical', 'Major')

    data = {}
    for name, (rows, f2c, status), verdict, n in (('round 21', r21, v21, 9),
                                                  ('round 22', r22, v22, 25)):
        reviews = list(range(1, n + 1))
        prim = counts(rows, f2c, verdict,
                      lambda f, c: cm(f) and verdict[c][0] == 'not-a-defect')
        data[name] = dict(rows=rows, f2c=f2c, status=status, verdict=verdict,
                          reviews=reviews, prim=prim)

    print('=' * 78)
    print('0. HOW PRECISE ARE THESE SD ESTIMATES?')
    print('=' * 78)
    print('The whole audit is about a change in sd, so the sds\' own sampling intervals')
    print('come first. Normal-theory chi-square intervals, Wilson-Hilferty quantile')
    print('(approximate, not exact).\n')
    est = {}
    for name in ('round 21', 'round 22'):
        d = data[name]
        for a in ARMS:
            xs = per_review(d['prim'], a, d['reviews'])
            lo, hi = sd_interval(st.variance(xs), len(xs))
            est[(name, a)] = (st.stdev(xs), lo, hi)
            print(f'  {name}  {a:4s} n={len(xs):2d}  sd {st.stdev(xs):.3f}   '
                  f'95% CI [{lo:.3f}, {hi:.3f}]')
    print('\n  Is each round\'s point estimate inside the other round\'s interval?')
    for a in ARMS:
        s21, l21, h21 = est[('round 21', a)]
        s22, l22, h22 = est[('round 22', a)]
        print(f'    {a:4s} round 22\'s {s22:.3f} in round 21\'s [{l21:.2f}, {h21:.2f}]: '
              f'{"yes" if l21 <= s22 <= h21 else "no"}    '
              f'round 21\'s {s21:.3f} in round 22\'s [{l22:.2f}, {h22:.2f}]: '
              f'{"yes" if l22 <= s21 <= h22 else "no"}')
    print('\n  The sizing assumption was sd ~ 1.42 (round 21\'s se at n=9):')
    for a in ARMS:
        _, lo, hi = est[('round 22', a)]
        print(f'    {a:4s} inside round 22\'s interval [{lo:.2f}, {hi:.2f}]: '
              f'{"yes" if lo <= 1.42 <= hi else "no"}')
    print('\n  Overlapping intervals do not show the underlying variances are equal,\n'
          '  and non-overlap would not show they differ. This is stated so the rest of\n'
          '  the audit is read as decomposition, not as evidence of a change.\n')

    print('=' * 78)
    print('1. PER-ARM VARIANCE, AND WHAT ONE REVIEW MOVES (leave-one-out)')
    print('=' * 78)
    for name in ('round 21', 'round 22'):
        d = data[name]
        print(f'\n{name}')
        for a in ARMS:
            xs = per_review(d['prim'], a, d['reviews'])
            loo = [st.stdev(xs[:i] + xs[i + 1:]) for i in range(len(xs))]
            k = max(range(len(xs)), key=lambda i: abs(loo[i] - st.stdev(xs)))
            print(f'  {a:4s} {fmt(xs)}   series {xs}')
            print(f'       leave-one-out sd range [{min(loo):.3f}, {max(loo):.3f}]; '
                  f'dropping review {d["reviews"][k]} (value {xs[k]}) '
                  f'moves sd {st.stdev(xs):.3f} -> {loo[k]:.3f}')

    print('\n' + '=' * 78)
    print('2. VARIANCE BY REVIEW PART, AND THE COVARIANCE BETWEEN PARTS')
    print('=' * 78)
    print('A review is the sum of its three parts, so var(review) = sum var(part)')
    print('+ 2*sum cov(part_i, part_j). This splits the growth between the two.\n')
    for name in ('round 21', 'round 22'):
        d = data[name]
        print(f'{name}')
        for a in ARMS:
            pv = {p: [d['prim'].get((a, i, p), 0) for i in d['reviews']] for p in PARTS}
            vs = {p: st.variance(pv[p]) for p in PARTS}
            covs = {(x, y): st.covariance(pv[x], pv[y]) for x, y in itertools.combinations(PARTS, 2)}
            tot = st.variance(per_review(d['prim'], a, d['reviews']))
            print(f'  {a:4s} var(review) {tot:6.3f} = '
                  f'sum var(parts) {sum(vs.values()):6.3f} + 2*sum cov {2 * sum(covs.values()):6.3f}')
            print('       ' + '  '.join(f'{p}: mean {st.mean(pv[p]):.2f} var {vs[p]:.3f}'
                                        for p in PARTS))
            print('       ' + '  '.join(f'cov({x},{y}) {c:+.3f}' for (x, y), c in covs.items()))
        print()

    print('=' * 78)
    print('3. THE PRIMARY BY REASON COMPONENT, AND THEIR COVARIANCES')
    print('=' * 78)
    print('The primary is the sum of its reason components, so the same decomposition')
    print('applies: a component with small variance cannot carry the total.\n')
    REASONS = ('preference', 'scope', 'outside-diff', 'misreads-code')
    for name in ('round 21', 'round 22'):
        d = data[name]
        print(f'{name}')
        for a in ARMS:
            comp = {}
            for r in REASONS:
                c = counts(d['rows'], d['f2c'], d['verdict'],
                           lambda f, cid, r=r: cm(f) and d['verdict'][cid] == ('not-a-defect', r))
                comp[r] = per_review(c, a, d['reviews'])
            tot = per_review(d['prim'], a, d['reviews'])
            print(f'  {a:4s} var(primary) {st.variance(tot):6.3f}')
            for r in REASONS:
                if any(comp[r]):
                    print(f'       {r:14s} mean {st.mean(comp[r]):5.2f}  var {st.variance(comp[r]):6.3f}')
            live = [r for r in REASONS if any(comp[r])]
            for x, y in itertools.combinations(live, 2):
                print(f'       cov({x},{y}) {st.covariance(comp[x], comp[y]):+.3f}')
        print()

    print('=' * 78)
    print('4. THE PRIMARY AGAINST TOTAL FINDINGS WRITTEN')
    print('=' * 78)
    print('If a review writing more findings writes proportionally more non-defects,')
    print('the primary inherits the spread of review length.\n')
    for name in ('round 21', 'round 22'):
        d = data[name]
        print(f'{name}')
        allf = counts(d['rows'], d['f2c'], d['verdict'], lambda f, c: True)
        for a in ARMS:
            tot = per_review(allf, a, d['reviews'])
            prim = per_review(d['prim'], a, d['reviews'])
            rate = [p / t for p, t in zip(prim, tot)]
            r = st.correlation(tot, prim) if len(set(tot)) > 1 else float('nan')
            print(f'  {a:4s} findings/review {fmt(tot)}')
            print(f'       primary rate     mean {st.mean(rate):.4f}  sd {st.stdev(rate):.4f}')
            print(f'       corr(findings, primary) {r:+.3f}')
        print()

    print('=' * 78)
    print('5. PINNED VS NEW CLAIMS (round 22 only; round 21 had no inventory)')
    print('=' * 78)
    d = data['round 22']
    for a in ARMS:
        for label, want in (('claims carried over', 'existing'), ('claims new here', 'new')):
            c = counts(d['rows'], d['f2c'], d['verdict'],
                       lambda f, cid, w=want: cm(f) and d['verdict'][cid][0] == 'not-a-defect'
                       and d['status'][cid] == w)
            xs = per_review(c, a, d['reviews'])
            print(f'  {a:4s} {label:22s} {fmt(xs)}')
    print()

    print('=' * 78)
    print('6. EXECUTION ORDER (round 22)')
    print('=' * 78)
    print('Review index is the order the batches were launched. The five-hour window')
    print('reset between index 15 and 16. This is execution bookkeeping, not a designed')
    print('factor, and nothing here is randomised against it.\n')
    d = data['round 22']
    for a in ARMS:
        xs = per_review(d['prim'], a, d['reviews'])
        first, second = xs[:R22_WINDOW_BREAK], xs[R22_WINDOW_BREAK:]
        print(f'  {a:4s} index 1-15  {fmt(first)}')
        print(f'       index 16-25 {fmt(second)}')
    print()

    print('=' * 78)
    print('7. HOW MUCH OF THE PART-COVARIANCE IS THE WINDOW SHIFT? (round 22)')
    print('=' * 78)
    print('Any factor shared by the three parts of one index shows up as covariance')
    print('between them. Subtracting each window stratum\'s mean removes whatever the')
    print('window carried; what remains is shared within a window and is not described')
    print('here. This attributes nothing: it partitions, it does not explain.\n')
    for a in ARMS:
        pv = {p: [d['prim'].get((a, i, p), 0) for i in d['reviews']] for p in PARTS}
        cen = {}
        for p in PARTS:
            m1 = st.mean(pv[p][:R22_WINDOW_BREAK])
            m2 = st.mean(pv[p][R22_WINDOW_BREAK:])
            cen[p] = ([x - m1 for x in pv[p][:R22_WINDOW_BREAK]]
                      + [x - m2 for x in pv[p][R22_WINDOW_BREAK:]])
        tot = per_review(d['prim'], a, d['reviews'])
        tc = [sum(cen[p][i] for p in PARTS) for i in range(len(tot))]
        raw = sum(st.covariance(pv[x], pv[y]) for x, y in itertools.combinations(PARTS, 2))
        cc = sum(st.covariance(cen[x], cen[y]) for x, y in itertools.combinations(PARTS, 2))
        print(f'  {a:4s} sd(review)        raw {st.stdev(tot):.3f}  '
              f'window-centred {st.stdev(tc):.3f}')
        print(f'       2*sum cov(parts)  raw {2 * raw:+.3f}  window-centred {2 * cc:+.3f}')
        print(f'       sum var(parts)    raw {sum(st.variance(pv[p]) for p in PARTS):.3f}  '
              f'window-centred {sum(st.variance(cen[p]) for p in PARTS):.3f}')
    print()


if __name__ == '__main__':
    main()
