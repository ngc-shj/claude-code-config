#!/usr/bin/env python3
"""Re-derive round 17: does the shipped Finding Floor hold on a second fixture?

Nine reviews of three identical generalists per arm on F10, arms interleaved
within each batch so no arm sits systematically earlier:

  W  the catalogue at HEAD — the Finding Floor present and wired by its digest line
  N  identical except the Finding Floor section and its wiring are removed

Pre-registration, including the n=6 calculation and the reachability gate:
`../../rule-ablation/protocols/round-17.md`.

  findings.tsv          977 findings, with arm, review and reviewer position
  clusters.tsv          each finding assigned to a claim; `status` marks the 25
                        this round added to round 16's 64-claim seed
  adjudications/*.tsv   three agents on those 25 NEW claims only

Verdicts for the 64 seed claims come from `../round-16/seed/inventory.tsv`
unchanged — the append-only rule, which is what lets `real` mean the same thing
here as it did before any arm ran.

THE VARIANCE CHECK RUNS FIRST AND ALONE. `--variance` prints the observed pooled
sd against the value n=6 was computed from and nothing else, because a design
that looks at its effect before deciding whether it was powered has decided
nothing. Run it, then run the comparison.

Usage:
  round-17/measure.py --variance     # the gate; prints sds, no arm means
  round-17/measure.py                # the two-arm table
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
ARMS = ('W', 'N')
BORROWED_SD = 1.217          # round 12's pooled sd on the primary, on F9
SD_TOLERANCE = 1.15          # pre-registered: beyond this, report underpowered
T_CRIT = {6: 2.228, 7: 2.179, 8: 2.145, 9: 2.120}   # df=2(n-1)
Z_BETA = 0.842


def verdicts():
    """Seed verdicts, then this round's — no claim is judged twice."""
    v = {r['cluster_id']: r['verdict'].strip() for r in
         csv.DictReader(open(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'),
                             newline=''), delimiter='\t')}
    sheets = [{r['cluster_id']: r['verdict'].strip() for r in
               csv.DictReader(open(p, newline=''), delimiter='\t')}
              for p in sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv')))]
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


def series(metric, f2c, real):
    """Per-review values for each arm, in review order."""
    rows = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv'), newline=''),
                               delimiter='\t'))
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in rows:
        by[f['arm']][f['review']].append(f)
    order = sorted(by[ARMS[0]], key=int)
    return ({a: [metric(by[a][k], f2c, real) for k in order] for a in ARMS},
            [('1' if int(k) <= 6 else '2') for k in order])


def primary(fs, f2c, real):
    return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
               and f2c[f['id']] not in real)


def control(fs, f2c, real):
    return len({f2c[f['id']] for f in fs if f2c[f['id']] in real})


def pooled_sd(a, b):
    return math.sqrt((st.variance(a) + st.variance(b)) / 2)


def mde(a, b):
    n = min(len(a), len(b))
    return (T_CRIT[n] + Z_BETA) * pooled_sd(a, b) * math.sqrt(2 / n)


def blocked(vals, batches):
    """Arm difference with the batch mean removed, then averaged over batches.

    Declared in the deviation: both arms sit in both batches, so a batch effect
    that shifts them equally is a nuisance the pooled estimate carries and this
    one does not. Reported alongside, never instead."""
    out = []
    for b in sorted(set(batches)):
        idx = [i for i, x in enumerate(batches) if x == b]
        out.append((b, len(idx),
                    st.mean(vals['W'][i] for i in idx) - st.mean(vals['N'][i] for i in idx)))
    n = sum(k for _, k, _ in out)
    return out, sum(k * d for _, k, d in out) / n


def main():
    v = verdicts()
    real = {c for c, x in v.items() if x == 'real'}
    f2c = assignment()
    prim, batches = series(primary, f2c, real)
    ctrl, _ = series(control, f2c, real)

    if '--variance' in sys.argv:
        print('VARIANCE CHECK — pre-registered to run before any arm comparison.\n'
              'No arm mean is printed here, by design.\n')
        sd_p, sd_c = pooled_sd(*[prim[a] for a in ARMS]), pooled_sd(*[ctrl[a] for a in ARMS])
        ceiling = BORROWED_SD * SD_TOLERANCE
        print(f'{"":24s}{"observed sd":>13s}{"borrowed":>10s}{"x1.15 ceiling":>15s}{"":>4s}verdict')
        for label, sd in (('primary', sd_p), ('control', sd_c)):
            ok = sd <= ceiling
            print(f'{label:24s}{sd:13.3f}{BORROWED_SD:10.3f}{ceiling:15.3f}    '
                  f'{"within" if ok else "EXCEEDS — report underpowered"}')
        print(f'\nMDE at the observed variance: primary {mde(*[prim[a] for a in ARMS]):.2f}, '
              f'control {mde(*[ctrl[a] for a in ARMS]):.2f}')
        print(f'Round 12 measured the primary effect at 2.50 on F9.')
        return

    n_new = sum(1 for r in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv'),
                                               newline=''), delimiter='\t')
                if r['status'] == 'new')
    print(f'{len(f2c)} findings, {len(v)} claims in the inventory ({n_new} added here), '
          f'{len(real)} real\n')
    print(f'{"":34s}{"W":>8s}{"N":>8s}{"t":>8s}{"MDE@80%":>10s}')
    for label, vals in (('PRIMARY  C+M not-real', prim), ('CONTROL  real claims', ctrl)):
        a, b = vals['W'], vals['N']
        sp = pooled_sd(a, b)
        t = (st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / len(a))) if sp else 0.0
        print(f'{label:34s}{st.mean(a):8.2f}{st.mean(b):8.2f}{t:8.2f}{mde(a, b):10.2f}')
    print(f'\nper-review primary  W: {prim["W"]}\n{"":20s}N: {prim["N"]}')
    print(f'per-review control  W: {ctrl["W"]}\n{"":20s}N: {ctrl["N"]}')
    print(f'batch               {batches}')

    print('\nBLOCKED estimate (batch mean removed), reported alongside the pooled one')
    for label, vals in (('primary', prim), ('control', ctrl)):
        per, comb = blocked(vals, batches)
        detail = '  '.join(f'batch {b} (n={k}) {d:+.2f}' for b, k, d in per)
        print(f'  {label:9s}{detail}   combined {comb:+.2f}')


if __name__ == '__main__':
    main()
