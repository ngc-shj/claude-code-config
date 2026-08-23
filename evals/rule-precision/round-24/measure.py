#!/usr/bin/env python3
"""Round 24's analysis, written before any of its data exists.

Everything that could otherwise be decided after seeing the numbers is decided
here instead: how three adjudicators combine when they disagree three ways, which
claims the bridge panel re-judges, what happens when a review index is lost, and
which interval the confirmatory rule reads. Protocol:
`../../rule-ablation/protocols/round-24.md`.

  --bridge-sample   the 24 claims the bridge panel re-judges. Runs NOW, from the
                    frozen round-17 material alone, so the sample is fixed on
                    disk before any round-24 output exists.
  --splits          list the claims where this round's three adjudicators
                    disagreed three ways; these go to the tie-break pass.
  --bridge          bridge agreement, three ways, once bridge/ is populated.
  (no flag)         the arm table and the confirmatory interval.

The primary is Critical/Major findings whose claim is adjudicated
`not-a-defect`. The composite round 17 pre-registered is carried as an
exploratory SECONDARY and fires no rule.
"""
import collections
import csv
import glob
import math
import os
import random
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.dirname(HERE)
ARMS = ('W', 'N')
VERDICTS = ('real', 'not-a-defect', 'wrong')

N_PLANNED = 12          # per arm, pre-registered
N_FLOOR = 11            # below this the round is descriptive only
BRIDGE_N = 24
BRIDGE_STRATA = {'real': 15, 'not-a-defect': 7, 'wrong': 2}
BRIDGE_SEED = 24        # fixes the shuffle the panel sees

Z_BETA = 0.842


def tsv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))


def frozen():
    """Round 17's verdicts, unchanged. The measurement standard, append-only."""
    v = {r['cluster_id']: r['verdict'].strip()
         for r in tsv(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'))}
    sheets = [{r['cluster_id']: r['verdict'].strip() for r in tsv(p)}
              for p in sorted(glob.glob(os.path.join(PREV, 'round-17',
                                                     'adjudications', '*.tsv')))]
    for cid in sheets[0]:
        v[cid] = collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
    return v


def sheets_here():
    paths = sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv')))
    if not paths:
        sys.exit('no adjudications/*.tsv yet — this round has not been run')
    return [{r['cluster_id']: r['verdict'].strip() for r in tsv(p)} for p in paths]


def splits(sheets):
    """Claims where the three adjudicators returned three different verdicts.

    `Counter.most_common` breaks such a tie by insertion order, which is sheet
    filename order — a real degree of freedom on the `wrong` / `not-a-defect`
    boundary, which is exactly the boundary the primary is made of. Rather than
    let filenames decide it, these claims go to a fourth blind adjudicator. The
    verdict space has three members, so a fourth verdict necessarily duplicates
    one of the three and the majority is then unique.
    """
    out = []
    for cid in sheets[0]:
        got = [s.get(cid) for s in sheets]
        if len(set(got)) == len(got):
            out.append(cid)
    return sorted(out)


def verdicts():
    """Frozen verdicts, then this round's new claims under the tie-break rule."""
    v = frozen()
    sheets = sheets_here()
    unresolved = splits(sheets)
    tb_path = os.path.join(HERE, 'tiebreak.tsv')
    tb = {r['cluster_id']: r['verdict'].strip() for r in tsv(tb_path)} \
        if os.path.exists(tb_path) else {}
    missing = [c for c in unresolved if c not in tb]
    if missing:
        sys.exit(f'{len(missing)} three-way split(s) without a tie-break verdict: '
                 f'{missing}\nRun the tie-break pass before any arm table.')
    for cid in sheets[0]:
        got = [s.get(cid) for s in sheets]
        if cid in tb:
            got.append(tb[cid])
        v[cid] = collections.Counter(got).most_common(1)[0][0]
    return v


def assignment():
    out = {}
    for row in tsv(os.path.join(HERE, 'clusters.tsv')):
        for fid in row['member_ids'].split(','):
            out[fid.strip()] = row['cluster_id']
    return out


def series(metric, f2c, v):
    rows = tsv(os.path.join(HERE, 'findings.tsv'))
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in rows:
        by[f['arm']][f['review']].append(f)
    shared = sorted(set(by[ARMS[0]]) & set(by[ARMS[1]]), key=int)
    return {a: [metric(by[a][k], f2c, v) for k in shared] for a in ARMS}, shared


def primary(fs, f2c, v):
    return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
               and v[f2c[f['id']]] == 'not-a-defect')


def composite(fs, f2c, v):
    return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
               and v[f2c[f['id']]] != 'real')


def control(fs, f2c, v):
    return len({f2c[f['id']] for f in fs if v[f2c[f['id']]] == 'real'})


def t_crit(df):
    z = 1.959964
    return z + (z ** 3 + z) / (4 * df) + (5 * z ** 5 + 16 * z ** 3 + 3 * z) / (96 * df ** 2)


def welch(a, b):
    """Difference, standard error, Satterthwaite df, and the 95% interval.

    Both arms constant makes se and df both zero and the interval a point. It is
    not a case any round has produced, and it is decided here rather than on the
    day: a zero-width interval is an artifact of the sample, not a measurement of
    infinite precision, so `df` comes back NaN and the caller reports the round
    descriptively instead of firing on it.
    """
    na, nb = len(a), len(b)
    va, vb = st.variance(a) / na, st.variance(b) / nb
    d = st.mean(a) - st.mean(b)
    if va == 0 and vb == 0:
        return d, 0.0, float('nan'), (d, d)
    se = math.sqrt(va + vb)
    df = (va + vb) ** 2 / (va ** 2 / (na - 1) + vb ** 2 / (nb - 1))
    h = t_crit(df) * se
    return d, se, df, (d - h, d + h)


def bridge_sample(v):
    """The 24 claims the bridge panel re-judges — deterministic, no judgement.

    Within each verdict stratum, cluster ids are sorted lexicographically and the
    claims at 1-indexed positions ceil(j*N/m), j = 1..m, are taken: a spread that
    depends only on the frozen files, with no start offset to choose and no
    rounding left open. The panel then sees them in one fixed shuffle, so no
    claim's position carries information about its stratum.
    """
    picked = []
    for verdict, m in BRIDGE_STRATA.items():
        ids = sorted(c for c, x in v.items() if x == verdict)
        n = len(ids)
        if m > n:
            sys.exit(f'stratum {verdict}: asked for {m} of {n}')
        picked += [(ids[math.ceil(j * n / m) - 1], verdict) for j in range(1, m + 1)]
    if len(picked) != BRIDGE_N or len({c for c, _ in picked}) != BRIDGE_N:
        sys.exit(f'bridge sample is {len(picked)} claims, expected {BRIDGE_N} distinct')
    random.Random(BRIDGE_SEED).shuffle(picked)
    return picked


def report_bridge(v):
    paths = sorted(glob.glob(os.path.join(HERE, 'bridge', '*.tsv')))
    if not paths:
        sys.exit('no bridge/*.tsv yet')
    sheets = [{r['cluster_id']: r['verdict'].strip() for r in tsv(p)} for p in paths]
    # The committed sample is the sample. Re-deriving it here would let a later
    # edit to bridge_sample() silently change which claims the agreement is over.
    pinned = os.path.join(HERE, 'bridge-sample.tsv')
    sample = [r['cluster_id'] for r in tsv(pinned)]
    if sample != [c for c, _ in bridge_sample(v)]:
        sys.exit(f'{pinned} no longer matches --bridge-sample. The committed file '
                 f'is\nthe pre-registered sample; investigate the difference rather '
                 f'than overwriting it.')

    hits = tot = 0
    per = collections.defaultdict(lambda: [0, 0])
    for cid in sample:
        for s in sheets:
            got = s.get(cid)
            if got is None:
                continue
            tot += 1
            per[v[cid]][1] += 1
            if got == v[cid]:
                hits += 1
                per[v[cid]][0] += 1
    maj_hits, three_way = 0, 0
    for cid in sample:
        got = [s.get(cid) for s in sheets if s.get(cid)]
        c = collections.Counter(got)
        if len(set(got)) == len(got) and len(got) == len(sheets):
            three_way += 1
        if c and c.most_common(1)[0][0] == v[cid]:
            maj_hits += 1

    print(f'BRIDGE — the current panel against round 17\'s frozen verdicts.\n'
          f'Fires no rule. The frozen verdicts are not rewritten.\n')
    print(f'  individual judgements   {hits}/{tot} = {100 * hits / tot:.1f}%')
    print(f'  panel-majority verdicts {maj_hits}/{len(sample)} = '
          f'{100 * maj_hits / len(sample):.1f}%')
    print(f'  three-way splits        {three_way} of {len(sample)}')
    print(f'\n{"stratum":16s}{"agree":>8s}{"of":>6s}')
    for verdict in VERDICTS:
        h, t = per[verdict]
        if t:
            print(f'{verdict:16s}{h:8d}{t:6d}')


def main():
    if '--bridge-sample' in sys.argv:
        v = frozen()
        counts = collections.Counter(v.values())
        print(f'Frozen inventory: {len(v)} claims — '
              + ', '.join(f'{counts[k]} {k}' for k in VERDICTS))
        print(f'Bridge sample, {BRIDGE_N} claims, shuffle seed {BRIDGE_SEED}:\n')
        print('cluster_id\tfrozen_verdict')
        for cid, verdict in bridge_sample(v):
            print(f'{cid}\t{verdict}')
        print('\nThe frozen verdict column is for the record, NOT for the panel: '
              'the\nrendered brief carries claim text only.', file=sys.stderr)
        return

    if '--splits' in sys.argv:
        s = splits(sheets_here())
        print(f'{len(s)} three-way split(s): {s if s else "none"}')
        return

    if '--bridge' in sys.argv:
        report_bridge(verdicts())
        return

    v = verdicts()
    f2c = assignment()
    prim, idx = series(primary, f2c, v)
    comp, _ = series(composite, f2c, v)
    ctrl, _ = series(control, f2c, v)
    n = len(idx)

    n_new = sum(1 for r in tsv(os.path.join(HERE, 'clusters.tsv'))
                if r['status'] == 'new')
    print(f'{len(f2c)} findings, {len(v)} claims ({n_new} added here), '
          f'n = {n} per arm (planned {N_PLANNED})\n')

    eligible = n >= N_FLOOR
    if not eligible:
        print(f'*** n = {n} is below the pre-registered floor of {N_FLOOR}. The round\n'
              f'*** is DESCRIPTIVE ONLY: no confirmatory claim, and n is not extended.\n'
              f'*** This is a design-integrity rule about executed sample size, not a\n'
              f'*** sensitivity gate on observed variance — round 24 registers none.\n')

    print(f'{"":28s}{"W":>8s}{"N":>8s}{"diff":>8s}{"95% CI":>20s}{"df":>7s}')
    for label, vals, kind in (('PRIMARY   C+M not-a-defect', prim, 'confirmatory'),
                              ('SECONDARY C+M composite', comp, 'exploratory'),
                              ('CONTROL   real claims', ctrl, 'no rule')):
        a, b = vals['W'], vals['N']
        d, se, df, (lo, hi) = welch(a, b)
        print(f'{label:28s}{st.mean(a):8.2f}{st.mean(b):8.2f}{d:8.2f}'
              f'{f"[{lo:.2f}, {hi:.2f}]":>20s}{df:7.1f}   {kind}')

    d, se, df, (lo, hi) = welch(prim['W'], prim['N'])
    print('\nCONFIRMATORY RULE — the Welch 95% CI for W - N on the PRIMARY '
          'lies entirely below zero.')
    if not eligible:
        print(f'  NOT APPLIED: n = {n} < {N_FLOOR}. Reported above as descriptive.')
    elif math.isnan(df):
        print(f'  NOT APPLIED: both arms are constant, so the interval is a point\n'
              f'  at {d:.2f} rather than a measurement. Reported descriptively.')
    elif hi < 0:
        print(f'  FIRES: [{lo:.2f}, {hi:.2f}]. The effect is CONFIRMED on F10.\n'
              f'  Direction held. The interval, not the rule, states the size — the\n'
              f'  rule does not require it to match round 17\'s 2.67.')
    elif lo > 0:
        print(f'  Interval entirely ABOVE zero: [{lo:.2f}, {hi:.2f}]. An effect in the\n'
              f'  opposite direction on the primary, recorded with its interval and\n'
              f'  no cause identified.')
    else:
        print(f'  Does not fire: [{lo:.2f}, {hi:.2f}] crosses zero. No effect detected\n'
              f'  under this design. Not evidence of absence, and not identifiable\n'
              f'  between the two null causes the protocol names.')

    print('\nper-review primary  W: ' + str(prim['W']) + '\n' + ' ' * 20
          + 'N: ' + str(prim['N']))
    print('review indices      ' + ','.join(idx))
    lost = N_PLANNED - n
    if lost:
        print(f'{lost} index/indices void — see the round README for cause. '
              f'n is never backfilled.')


if __name__ == '__main__':
    main()
