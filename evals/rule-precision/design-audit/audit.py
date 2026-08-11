#!/usr/bin/env python3
"""Design audit: is another round of this experiment worth running?

RETROSPECTIVE AND EXPLORATORY. It changes no confirmatory conclusion from rounds
20-22, establishes no cause, and proposes no change to clause 1. It asks one
operational question: would a further round change what we would do?

Nothing here shows clause 1 is harmful. Every interval below includes zero at the
loss ratios that matter, and no round was designed to detect the coverage
quantity this audit puts at the centre.

Two fixtures, three rounds. F10 was reviewed once (round 20); F11 was reviewed
twice (rounds 21 and 22). Those two F11 samples are fresh reviews but NOT
independent fixture-level replicates.

Usage:  design-audit/audit.py
"""
import itertools
import math
import statistics as st

from _data import ROUNDS, series, load, welch, tcrit, PRIM, REAL, CM

BUDGETS = (100, 150, 200, 300, 450)


def head(t):
    print('\n' + '=' * 76 + f'\n{t}\n' + '=' * 76)


def main():
    head('1. THE TWO METRICS SIDE BY SIDE')
    print('Units matter. The false-positive metric counts Critical/Major findings')
    print('whose claim was adjudicated not-a-defect, per review. The coverage metric')
    print('counts DISTINCT real claims reached by the three reviewers of a review')
    print('together. One is a finding count, the other a claim count over a union.\n')
    for label, metric in (('C+M not-a-defect (per review)', PRIM),
                          ('distinct real claims reached', REAL)):
        print(f'  {label}')
        print(f'  {"":10s}{"W":>7s}{"W23":>7s}{"diff":>8s}{"se":>7s}{"95% CI":>18s}')
        for name in ROUNDS:
            w, x = series(name, 'W', metric), series(name, 'W23', metric)
            d, se, df, lo, hi = welch(w, x)
            print(f'  {name:10s}{st.mean(w):7.2f}{st.mean(x):7.2f}{d:8.2f}{se:7.3f}'
                  f'   [{lo:6.2f},{hi:6.2f}]')
        print()
    print('  Only round 20\'s false-positive difference was a confirmatory result.')
    print('  Every coverage figure is a control that fired no rule in its round.')

    head('2. NET BENEFIT — the quantity a decision actually needs')
    print('rho = cost(one missed real claim) / value(one avoided false positive),')
    print('in the units above. THE VALUE OF RHO IS AN OPERATIONAL JUDGEMENT, NOT A')
    print('RESULT: this audit computes the arithmetic for a range and takes no')
    print('position on which rho is right.\n')
    print('Computed per review as u = fp - rho*real, so the within-review')
    print('correlation is carried. Positive favours keeping clause 1.\n')
    print(f'  {"round":10s}{"rho":>6s}{"net":>8s}{"se":>7s}{"95% CI":>18s}')
    for name in ROUNDS:
        fw, fx = series(name, 'W', PRIM), series(name, 'W23', PRIM)
        rw, rx = series(name, 'W', REAL), series(name, 'W23', REAL)
        for i, rho in enumerate((0.0, 0.5, 1.0, 2.0, 3.0)):
            uw = [f - rho * r for f, r in zip(fw, rw)]
            ux = [f - rho * r for f, r in zip(fx, rx)]
            d, se, df, lo, hi = welch(ux, uw)
            print(f'  {name if not i else "":10s}{rho:6.1f}{d:8.2f}{se:7.3f}'
                  f'   [{lo:6.2f},{hi:6.2f}]')
        print()
    print('  Break-even rho, from the point estimates:')
    for name in ROUNDS:
        fp = st.mean(series(name, 'W23', PRIM)) - st.mean(series(name, 'W', PRIM))
        rl = st.mean(series(name, 'W23', REAL)) - st.mean(series(name, 'W', REAL))
        print(f'    {name:10s} fp saved {fp:+.2f}   real lost {rl:+.2f}   '
              f'break-even rho {fp / rl:.2f}')
    print('\n  Above its break-even rho the POINT ESTIMATE turns against clause 1 in')
    print('  all three rounds. Every interval at rho >= 0.5 includes zero, so this')
    print('  does NOT establish that clause 1 is harmful. It establishes that the')
    print('  sign of the decision depends on a quantity no round was sized to measure.')

    head('3. REVIEWER CONFIGURATION — one observation, three agents')
    print('Averaged over all C(3,k) subsets of round 22, so each k uses the same')
    print('agents. Effect/MDE at a fixed agent budget: >1 would clear the MDE.\n')
    for label, metric in (('C+M not-a-defect', PRIM), ('real claims reached', REAL)):
        stats = {}
        for k in (1, 2, 3):
            subs = list(itertools.combinations('abc', k))
            sw = [series('round 22', 'W', metric, parts=s) for s in subs]
            sx = [series('round 22', 'W23', metric, parts=s) for s in subs]
            eff = st.mean([st.mean(v) for v in sw]) - st.mean([st.mean(v) for v in sx])
            sd = math.sqrt((st.mean([st.variance(v) for v in sw])
                            + st.mean([st.variance(v) for v in sx])) / 2)
            stats[k] = (eff, sd, st.mean([st.mean(v) for v in sw]),
                        st.mean([st.mean(v) for v in sx]))
        print(f'  {label}')
        print(f'  {"agents":>8s}' + ''.join(f'{"k=" + str(k):>9s}' for k in (1, 2, 3)))
        for A in BUDGETS:
            row = f'  {A:8d}'
            for k in (1, 2, 3):
                n = A // (2 * k)
                eff, sd = stats[k][0], stats[k][1]
                mde = (tcrit(2 * (n - 1)) + 0.842) * sd * math.sqrt(2 / n)
                row += f'{abs(eff) / mde:9.2f}'
            print(row)
        ind = stats[1][1] * math.sqrt(3)
        print('    mean W  by k: ' + '  '.join(f'{stats[k][2]:6.2f}' for k in (1, 2, 3))
              + '   mean W23: ' + '  '.join(f'{stats[k][3]:6.2f}' for k in (1, 2, 3)))
        print(f'    effect by k: ' + '  '.join(f'{stats[k][0]:+.2f}' for k in (1, 2, 3)))
        print(f'    sd at k=3 {stats[3][1]:.3f} vs {ind:.3f} under independence '
              f'({stats[3][1] / ind:.2f}x)\n')
    print('  The two metrics disagree about k. The finding count is a sum, so its')
    print('  effect grows linearly with k while its sd grows faster than sqrt(k).')
    print('  Coverage is a union, so one reviewer reaches most of what three do and')
    print('  the arm gap only opens on aggregation. No single k optimises both.')

    head('4. NON-INFERIORITY ON COVERAGE — what it would cost')
    sd = math.sqrt((st.variance(series('round 22', 'W', REAL))
                    + st.variance(series('round 22', 'W23', REAL))) / 2)
    print(f'Plug-in pooled sd from round 22 at k=3: {sd:.3f}. One-sided alpha .025,')
    print('power .80, equal variances assumed. n per arm:\n')
    print(f'  {"margin":>8s}' + ''.join(f'{"theta=" + f"{t:+.1f}":>13s}'
                                        for t in (0.0, -0.5, -1.0)))
    for m in (0.5, 1.0, 1.5, 2.0, 2.5):
        row = f'  {m:8.1f}'
        for th in (0.0, -0.5, -1.0):
            gap = m + th
            row += f'{"unreachable":>13s}' if gap <= 0 else \
                   f'{math.ceil(2 * sd * sd * 7.849 / gap ** 2):13d}'
        print(row)
    print('\n  theta is the ASSUMED true W-W23 coverage difference. If theta equals')
    print('  round 22\'s observed -1.20, no margin below 1.20 is reachable at any n.')
    print('  Every figure is conditional on that assumption, on equal variances, and')
    print('  on plugging in one round\'s observed sd as if it were known.')

    head('5. WHERE EACH SIDE COMES FROM (round 22, F11 only)')
    rd, verdict, _ = ROUNDS['round 22']
    f2c, by = load(rd, verdict)
    import collections, csv, os
    claim = {r['cluster_id']: r['claim'] for r in
             csv.DictReader(open(os.path.join(rd, 'clusters.tsv'), newline=''),
                            delimiter='\t')}
    fp = collections.defaultdict(collections.Counter)
    reach = collections.defaultdict(collections.Counter)
    real = {c for c, v in verdict.items() if v == 'real'}
    for arm in ('W', 'W23'):
        for i in range(1, 26):
            got = set()
            for p in 'abc':
                for f in by[arm][i][p]:
                    c = f2c[f['id']]
                    got.add(c)
                    if CM(f) and verdict[c] == 'not-a-defect':
                        fp[c][arm] += 1
            for c in got & real:
                reach[c][arm] += 1
    fps = sorted(fp, key=lambda c: -(fp[c]['W23'] - fp[c]['W']))
    tot = sum(fp[c]['W23'] - fp[c]['W'] for c in fps)
    print(f'  FALSE POSITIVES AVOIDED — net {tot:+d} findings over 25 reviews/arm')
    print(f'  {"cluster":14s}{"W":>4s}{"W23":>5s}{"diff":>6s}  claim')
    for c in fps[:3]:
        print(f'  {c:14s}{fp[c]["W"]:4d}{fp[c]["W23"]:5d}'
              f'{fp[c]["W23"] - fp[c]["W"]:+6d}  {claim[c][:60]}')
    t3 = sum(fp[c]['W23'] - fp[c]['W'] for c in fps[:3])
    print(f'  top 3 sum {t3:+d} against a net of {tot:+d}; dropping the largest alone '
          f'takes\n  the per-review difference from '
          f'{tot / 25:+.2f} to {(tot - (fp[fps[0]]["W23"] - fp[fps[0]]["W"])) / 25:+.2f}.')
    print('  Concentrated, and concentrated in one shape: demands for infrastructure')
    print('  the diff does not show. THIS DESCRIBES ROUND 22 ON F11 AND NOTHING ELSE.')

    rs = sorted(reach, key=lambda c: (reach[c]['W'] - reach[c]['W23'], c))
    net = sum(reach[c]['W'] - reach[c]['W23'] for c in rs)
    neg = [c for c in rs if reach[c]['W'] - reach[c]['W23'] < 0]
    pos = [c for c in rs if reach[c]['W'] - reach[c]['W23'] > 0]
    print(f'\n  COVERAGE — net {net:+d} review-reaches over 25 reviews/arm '
          f'({net / 25:+.2f} per review)')
    print(f'  {"cluster":14s}{"W":>4s}{"W23":>5s}{"diff":>6s}  claim')
    for c in rs:
        d = reach[c]['W'] - reach[c]['W23']
        if abs(d) >= 2:
            print(f'  {c:14s}{reach[c]["W"]:4d}{reach[c]["W23"]:5d}{d:+6d}  {claim[c][:60]}')
    print(f'\n  {len(neg)} claims W reached less often (sum '
          f'{sum(reach[c]["W"] - reach[c]["W23"] for c in neg):+d}), '
          f'{len(pos)} more often (sum '
          f'{sum(reach[c]["W"] - reach[c]["W23"] for c in pos):+d}).')
    print(f'  The three largest negatives sum '
          f'{sum(reach[c]["W"] - reach[c]["W23"] for c in rs[:3]):+d} of {net:+d}.')
    print('  The coverage side is DIFFUSE where the false-positive side is')
    print('  concentrated. A narrow wording change cannot be assumed to keep the')
    print('  benefit while dropping the loss: the loss is not localised the same way.')

    head('6. SIZING WITHOUT PAYING IN FULL FIRST')
    W, X = series('round 22', 'W', PRIM), series('round 22', 'W23', PRIM)
    full = (st.variance(W) + st.variance(X)) / 2

    def n_for(v, target=1.33, cap=60):
        for n in range(5, cap + 1):
            if (tcrit(2 * (n - 1)) + 0.842) * math.sqrt(2 * v / n) <= target:
                return n
        return None

    print('Round 22 spent 150 agents and then learned its MDE was 1.41 against a')
    print('1.33 ceiling. Replaying its own first n1 indices as an internal pilot:\n')
    print(f'  {"pilot n1":>9s}{"pooled sd":>11s}{"re-sized n":>12s}')
    for n1 in (8, 10, 12, 15):
        v = (st.variance(W[:n1]) + st.variance(X[:n1])) / 2
        print(f'  {n1:9d}{math.sqrt(v):11.3f}{n_for(v):12d}')
    print(f'\n  full sample (n=25): sd {math.sqrt(full):.3f}, would ask for '
          f'n={n_for(full)}')
    print('\n  The pilots at n1=8, 10 and 12 point above 25; the pilot at n1=15 lands')
    print('  exactly on 25 and would NOT have flagged a shortfall. A pilot is not a')
    print('  guarantee — its own variance estimate is imprecise, which argues for a')
    print('  cap and a stop rule rather than for trusting its point estimate.')
    print('\n  This pooling averages the two arms\' variances and so uses the group')
    print('  labels, even though it never looks at the arm MEANS. It is therefore')
    print('  not automatically alpha-free: any future use has to pre-register the')
    print('  re-estimation method and calibrate its type-I error, not assume it.')


if __name__ == '__main__':
    main()
