#!/usr/bin/env python3
"""Design audit: is another round of this experiment worth running?

RETROSPECTIVE AND EXPLORATORY. It changes no confirmatory conclusion from rounds
20-22, establishes no cause, and proposes no change to clause 1. It asks one
operational question: would a further round change what we would do?

This audit does not establish that clause 1 is harmful. rho was not fixed in
advance, coverage was not a confirmatory metric in any round, and the one
interval that excludes zero (rho = 5, round 22) was found in a retrospective scan
over rho. No round was designed to detect the coverage quantity this audit puts
at the centre.

Two fixtures, three rounds. F10 was reviewed once (round 20); F11 was reviewed
twice (rounds 21 and 22). Those two F11 samples are fresh reviews but NOT
independent fixture-level replicates.

Usage:  design-audit/audit.py
"""
import itertools
import math
import statistics as st

from _data import (ROUNDS, series, load, welch, tcrit, verify_inputs,
                   PRIM, REAL, CM)

BUDGETS = (100, 150, 200, 300, 450)


def head(t):
    print('\n' + '=' * 76 + f'\n{t}\n' + '=' * 76)


def main():
    n = verify_inputs()
    print(f'inputs verified: {n} files match inputs.sha1 (pinned at the base commit)')

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
    print('  Only round 20\'s false-positive difference was a confirmatory result,')
    print('  and its CONFIRMATORY interval is the pre-registered PAIRED one,')
    print('  [-2.27, -0.39]. The [-2.29, -0.38] above is a Welch RE-ESTIMATE made')
    print('  here so all three rounds sit on one scale. Round 20\'s conclusion is')
    print('  unchanged; only the presentation scale is.')
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
        for i, rho in enumerate((0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0)):
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
    print('  all three rounds.')
    print('\n  At rho = 0.5, 1, 2 and 3 every interval above includes zero. That is')
    print('  NOT a statement about all rho: at rho = 5 round 22\'s interval is')
    print('  [-10.48, -0.16] and excludes zero, because at a large enough loss ratio')
    print('  the coverage difference dominates the composite.')
    print('\n  It still does not establish that clause 1 is harmful. rho was not fixed')
    print('  in advance, coverage is not a confirmatory metric in any round, and an')
    print('  interval chosen by scanning rho until one excludes zero is not a test.')
    print('  What the scan shows is that the sign of the decision depends on a')
    print('  quantity no round was sized to measure.')

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
    print('  effect/MDE here uses F11\'s OBSERVED effect, so it is a retrospective')
    print('  efficiency heuristic for comparing configurations at equal cost. It is')
    print('  not a decision rule and nothing is judged by it.\n')
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
    print('\n  What those n cost, at 3 reviewers per index, 2 arms, and this')
    print('  project\'s observed ~83k tokens per review agent:\n')
    print(f'    {"margin (theta=0)":>17s}{"n/arm":>7s}{"agents":>8s}{"review tokens":>15s}')
    for m, n in ((0.5, 193), (1.0, 49), (1.5, 22)):
        ag = 2 * 3 * n
        print(f'    {m:17.1f}{n:7d}{ag:8d}{ag * 0.083:14.0f}M')
    print('\n  Round 22 alone cost 12.5M in reviews. THIS PROJECT DOES NOT ADOPT THAT')
    print('  SPEND at the margins that would persuade a reader. That is an')
    print('  operational judgement about this budget, not a claim that the design')
    print('  is invalid or that the effect is absent.')

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
    import csv as _csv
    status = {r['cluster_id']: r['status'] for r in
              _csv.DictReader(open(os.path.join(rd, 'clusters.tsv'), newline=''),
                              delimiter='\t')}
    dec = collections.Counter()
    for c in reach:
        for arm in ('W', 'W23'):
            dec[(arm, status[c])] += reach[c][arm]
    print('\n  Does the coverage gap depend on claims adjudicated AFTER the arms ran?')
    for stat, label in (('existing', 'claims carried in from round 21'),
                        ('new', 'claims new to round 22')):
        w, x = dec[('W', stat)], dec[('W23', stat)]
        print(f'    {label:34s} W {w:4d}  W23 {x:4d}  diff {w - x:+4d}'
              f'  ({(w - x) / 25:+.2f}/review)')
    print('    The whole gap sits on claims whose verdicts were fixed before this')
    print('    round\'s arms ran. It does not rest on this round\'s adjudication.')
    print('\n  Full table, every real claim the two arms reached a different number')
    print('  of times. Canonical claim text in full, not truncated.\n')
    for c in rs:
        d = reach[c]['W'] - reach[c]['W23']
        if d:
            print(f'    {c}  W {reach[c]["W"]:2d}  W23 {reach[c]["W23"]:2d}  {d:+3d}'
                  f'  [{status[c]}]')
            for ln in __import__('textwrap').wrap(claim[c], 70):
                print(f'        {ln}')
    print('\n  The coverage side is DIFFUSE where the false-positive side is')
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
