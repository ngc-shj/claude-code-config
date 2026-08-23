#!/usr/bin/env python3
"""Round 24's analysis, written before any of its data exists.

Everything that could otherwise be decided after seeing the numbers is decided
here instead: which reviews are in the denominator, how three adjudicators
combine when they disagree three ways, which claims the bridge panel re-judges,
what happens when a review index is lost, and which interval the confirmatory
rule reads. Protocol: `../../rule-ablation/protocols/round-24.md`.

  --bridge-sample   the 24 claims the bridge panel re-judges, with their frozen
                    verdicts, for the record. Runs from the frozen files alone.
  --bridge-input    the same 24 claims in the same order, cluster_id and claim
                    text ONLY. This is the file the bridge brief points at; the
                    verdict column above must never reach the panel.
  --splits          claims where this round's three adjudicators disagreed three
                    ways; these go to the tie-break pass.
  --bridge          bridge agreement, three ways.
  (no flag)         the arm table and the confirmatory interval.

The primary is Critical/Major findings whose claim is adjudicated
`not-a-defect`. The composite round 17 pre-registered is an exploratory
SECONDARY and fires no rule.

Nothing here trusts a file to be well-formed. Every sheet, every id set and every
review index is checked against what the protocol registered, and a mismatch
stops the run rather than being averaged into a number.
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

N_PLANNED = 12
N_FLOOR = 11                                  # below this: descriptive only
INDICES = tuple(str(i) for i in range(1, N_PLANNED + 1))
N_PANEL = 3                                   # adjudicators per pass
BRIDGE_N = 24
BRIDGE_STRATA = {'real': 15, 'not-a-defect': 7, 'wrong': 2}
BRIDGE_SEED = 24


def die(msg):
    sys.exit(f'round-24: {msg}')


def rows(path):
    if not os.path.exists(path):
        die(f'{os.path.relpath(path, HERE)} is missing')
    with open(path, newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))


def sheet(path, allowed):
    """One adjudication sheet, checked before it can influence anything."""
    out = {}
    for r in rows(path):
        cid, verdict = r['cluster_id'].strip(), r['verdict'].strip()
        if cid in out:
            die(f'{os.path.basename(path)}: {cid} appears twice')
        if verdict not in VERDICTS:
            die(f'{os.path.basename(path)}: {cid} has verdict {verdict!r}, '
                f'not one of {VERDICTS}')
        out[cid] = verdict
    if set(out) != set(allowed):
        missing, extra = set(allowed) - set(out), set(out) - set(allowed)
        die(f'{os.path.basename(path)}: judges {len(out)} claims, expected '
            f'{len(allowed)}\n  missing: {sorted(missing) or "none"}\n'
            f'  unexpected: {sorted(extra) or "none"}')
    return out


def panel(dirname, allowed, what):
    """Exactly N_PANEL sheets, each covering exactly `allowed`."""
    paths = sorted(glob.glob(os.path.join(HERE, dirname, '*.tsv')))
    if len(paths) != N_PANEL:
        die(f'{what}: {len(paths)} sheet(s) in {dirname}/, expected {N_PANEL}')
    return [sheet(p, allowed) for p in paths]


# ---------------------------------------------------------------- the standard

def frozen():
    """Round 17's verdicts, unchanged. The measurement standard, append-only."""
    v = {r['cluster_id']: r['verdict'].strip()
         for r in rows(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'))}
    sheets = [{r['cluster_id']: r['verdict'].strip() for r in rows(p)}
              for p in sorted(glob.glob(os.path.join(PREV, 'round-17',
                                                     'adjudications', '*.tsv')))]
    for cid in sheets[0]:
        v[cid] = collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
    return v


def frozen_text():
    """Canonical claim text for every frozen claim."""
    t = {r['cluster_id']: r['claim']
         for r in rows(os.path.join(PREV, 'round-16', 'seed', 'inventory.tsv'))}
    for r in rows(os.path.join(PREV, 'round-17', 'clusters.tsv')):
        t.setdefault(r['cluster_id'], r['claim'])
    return t


# ------------------------------------------------------------- this round's

def clusters():
    return rows(os.path.join(HERE, 'clusters.tsv'))


def new_ids():
    return sorted(r['cluster_id'] for r in clusters() if r['status'] == 'new')


def splits(sheets):
    """Claims where the three adjudicators returned three different verdicts.

    `Counter.most_common` breaks such a tie by insertion order, which is sheet
    filename order — a filename deciding a value the primary is made of, on the
    `wrong` / `not-a-defect` boundary. These go to a fourth blind adjudicator
    instead. The verdict space has three members, so a fourth verdict duplicates
    one of them and the majority is then unique.
    """
    return sorted(cid for cid in sheets[0]
                  if len({s[cid] for s in sheets}) == N_PANEL)


def verdicts():
    """Frozen verdicts, then this round's new claims under the tie-break rule."""
    v = frozen()
    new = new_ids()
    tb_path = os.path.join(HERE, 'tiebreak.tsv')
    if not new:
        # A header-only sheet is a pass that ran and judged nothing, which is
        # what "no new claims" looks like on disk. Only a sheet carrying rows
        # contradicts clusters.tsv.
        judged = [p for p in sorted(glob.glob(os.path.join(HERE, 'adjudications',
                                                           '*.tsv'))) if rows(p)]
        if judged:
            die(f'{os.path.basename(judged[0])} judges claims but clusters.tsv '
                f'has no new claims')
        if os.path.exists(tb_path):
            die('tiebreak.tsv exists but there are no new claims to split')
        return v
    sheets = panel('adjudications', new, 'new-claim adjudication')

    unresolved = splits(sheets)
    if unresolved and not os.path.exists(tb_path):
        die(f'{len(unresolved)} three-way split(s) and no tiebreak.tsv: '
            f'{unresolved}\n  Run the tie-break pass before any arm table.')
    tb = sheet(tb_path, unresolved) if os.path.exists(tb_path) else {}
    if not unresolved and tb:
        die('tiebreak.tsv exists but no claim split three ways')

    for cid in new:
        got = [s[cid] for s in sheets] + ([tb[cid]] if cid in tb else [])
        v[cid] = collections.Counter(got).most_common(1)[0][0]
    return v


def manifest():
    """reviews.tsv — which of the 24 registered reviews completed, and which did not.

    n comes from here and never from `findings.tsv`. Inferring it from the arms'
    shared review ids, as an earlier draft did, cannot tell a completed review
    that produced no Critical/Major finding from one that never ran, and would
    silently analyse an index the protocol never registered.
    """
    seen, complete = set(), collections.defaultdict(set)
    for r in rows(os.path.join(HERE, 'reviews.tsv')):
        idx, arm, status = r['review'].strip(), r['arm'].strip(), r['status'].strip()
        if idx not in INDICES:
            die(f'reviews.tsv: index {idx!r} is not one of 1..{N_PLANNED}')
        if arm not in ARMS:
            die(f'reviews.tsv: arm {arm!r} is not one of {ARMS}')
        if status not in ('complete', 'void'):
            die(f'reviews.tsv: status {status!r} is not complete/void')
        if (idx, arm) in seen:
            die(f'reviews.tsv: review {idx} arm {arm} appears twice')
        seen.add((idx, arm))
        if status == 'complete':
            complete[arm].add(idx)
        elif not r.get('cause', '').strip():
            die(f'reviews.tsv: review {idx} arm {arm} is void with no cause')
    expected = {(i, a) for i in INDICES for a in ARMS}
    if seen != expected:
        die(f'reviews.tsv: {len(seen)} rows, expected all {len(expected)} '
            f'registered (index x arm) pairs; missing {sorted(expected - seen)}')
    if complete['W'] != complete['N']:
        die(f'reviews.tsv: arms disagree on which indices completed — the void '
            f'rule voids an index in BOTH arms.\n  W only: '
            f'{sorted(complete["W"] - complete["N"])}\n  N only: '
            f'{sorted(complete["N"] - complete["W"])}')
    return sorted(complete['W'], key=int)


def assignment():
    out = {}
    for row in clusters():
        for fid in row['member_ids'].split(','):
            if fid.strip():
                out[fid.strip()] = row['cluster_id']
    return out


def series(metric, f2c, v, idx):
    """Per-review values over the manifest's completed indices, in order.

    A completed review with no qualifying finding contributes 0 — it is not
    absent, and building the series from the manifest rather than from the rows
    present in findings.tsv is what makes that distinction survive.
    """
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in rows(os.path.join(HERE, 'findings.tsv')):
        if f['arm'] not in ARMS:
            die(f'findings.tsv: {f["id"]} has arm {f["arm"]!r}')
        if f['review'] not in idx:
            die(f'findings.tsv: {f["id"]} is on review {f["review"]}, which the '
                f'manifest does not list as complete in both arms')
        if f['id'] not in f2c:
            die(f'findings.tsv: {f["id"]} is in no cluster')
        by[f['arm']][f['review']].append(f)
    return {a: [metric(by[a][k], f2c, v) for k in idx] for a in ARMS}


def primary(fs, f2c, v):
    return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
               and v[f2c[f['id']]] == 'not-a-defect')


def composite(fs, f2c, v):
    return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
               and v[f2c[f['id']]] != 'real')


def control(fs, f2c, v):
    return len({f2c[f['id']] for f in fs if v[f2c[f['id']]] == 'real'})


# ------------------------------------------------------------------ inference

def betacf(a, b, x):
    """Continued fraction for the incomplete beta, modified Lentz."""
    tiny = 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 300):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / (c if abs(c) > tiny else tiny)
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / (c if abs(c) > tiny else tiny)
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 3e-16:
            return h
    die('betacf did not converge')


def betai(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    lb = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
          + a * math.log(x) + b * math.log1p(-x))
    bt = math.exp(lb)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * betacf(a, b, x) / a
    return 1.0 - bt * betacf(b, a, 1.0 - x) / b


def t_sf(t, df):
    """P(T > t) for t >= 0, exact up to the continued fraction's tolerance."""
    return 0.5 * betai(df / 2.0, 0.5, df / (df + t * t))


def t_crit(df, alpha=0.05):
    """Two-sided critical value, by bisection on the exact survival function.

    An earlier draft used a Cornish-Fisher expansion, which returns 2.2254 at
    df = 10 against the true 2.2281 — small, and anti-conservative in the
    direction that widens no interval. This is the registered rule: the exact
    quantile, computed the same way every time it is called.
    """
    target = alpha / 2.0
    lo, hi = 0.0, 1e3
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if t_sf(mid, df) > target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def welch(a, b):
    """Difference, standard error, Satterthwaite df, and the 95% interval.

    Both arms constant makes se and df zero and the interval a point. It is not a
    case any round has produced, and it is decided here rather than on the day: a
    zero-width interval is an artifact of the sample, not infinite precision, so
    `df` comes back NaN and the caller reports descriptively instead of firing.
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


# --------------------------------------------------------------------- bridge

def bridge_sample(v):
    """The 24 claims the bridge panel re-judges — deterministic, no judgement.

    Within each verdict stratum, cluster ids are sorted lexicographically and the
    claims at 1-indexed positions ceil(j*N/m), j = 1..m, are taken: a spread that
    depends only on the frozen files, with no start offset to choose and no
    rounding left open. One fixed shuffle then means no claim's position in the
    panel's file carries information about its stratum.
    """
    picked = []
    for verdict, m in BRIDGE_STRATA.items():
        ids = sorted(c for c, x in v.items() if x == verdict)
        n = len(ids)
        if m > n:
            die(f'stratum {verdict}: asked for {m} of {n}')
        picked += [(ids[math.ceil(j * n / m) - 1], verdict) for j in range(1, m + 1)]
    if len(picked) != BRIDGE_N or len({c for c, _ in picked}) != BRIDGE_N:
        die(f'bridge sample is {len(picked)} claims, expected {BRIDGE_N} distinct')
    random.Random(BRIDGE_SEED).shuffle(picked)
    return picked


def pinned_sample(v):
    """The committed sample, checked against the sampler that produced it."""
    pinned = os.path.join(HERE, 'bridge-sample.tsv')
    sample = [r['cluster_id'] for r in rows(pinned)]
    if sample != [c for c, _ in bridge_sample(v)]:
        die('bridge-sample.tsv no longer matches --bridge-sample. The committed '
            'file\n  is the pre-registered sample; investigate the difference '
            'rather than\n  overwriting it.')
    return sample


def report_bridge(v):
    sample = pinned_sample(v)
    sheets = panel('bridge', sample, 'bridge re-adjudication')

    hits = tot = 0
    per = collections.defaultdict(lambda: [0, 0])
    maj_hits = no_majority = 0
    for cid in sample:
        got = [s[cid] for s in sheets]
        tot += len(got)
        per[v[cid]][1] += len(got)
        agree = sum(1 for g in got if g == v[cid])
        hits += agree
        per[v[cid]][0] += agree
        if len(set(got)) == N_PANEL:
            no_majority += 1                  # three ways: there is no majority
        elif collections.Counter(got).most_common(1)[0][0] == v[cid]:
            maj_hits += 1
    decided = len(sample) - no_majority

    print('BRIDGE — the current panel against round 17\'s frozen verdicts.\n'
          'Fires no rule. The frozen verdicts are not rewritten.\n')
    print(f'  individual judgements   {hits}/{tot} = {100 * hits / tot:.1f}%')
    print(f'  panel-majority verdicts {maj_hits}/{decided} = '
          f'{100 * maj_hits / decided:.1f}%' if decided else
          '  panel-majority verdicts  undefined: every claim split three ways')
    print(f'  no majority (three-way) {no_majority} of {len(sample)}'
          f'{"  — excluded from the line above" if no_majority else ""}')
    print(f'\n{"frozen class":16s}{"agree":>8s}{"of":>6s}')
    for verdict in VERDICTS:
        h, t = per[verdict]
        if t:
            print(f'{verdict:16s}{h:8d}{t:6d}')


# ----------------------------------------------------------------------- main

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
        print('\nThe verdict column is for the record and must NOT reach the '
              'panel.\nUse --bridge-input for the file the bridge brief points '
              'at.', file=sys.stderr)
        return

    if '--bridge-input' in sys.argv:
        text = frozen_text()
        print('cluster_id\tclaim')
        for cid in pinned_sample(frozen()):
            if cid not in text:
                die(f'{cid} has no canonical claim text in the frozen files')
            print(f'{cid}\t{text[cid]}')
        return

    if '--splits' in sys.argv:
        new = new_ids()
        s = splits(panel('adjudications', new, 'new-claim adjudication')) if new else []
        print(f'{len(s)} three-way split(s): {s if s else "none"}')
        return

    if '--bridge' in sys.argv:
        report_bridge(frozen())
        return

    v = verdicts()
    f2c = assignment()
    idx = manifest()
    n = len(idx)
    prim = series(primary, f2c, v, idx)
    comp = series(composite, f2c, v, idx)
    ctrl = series(control, f2c, v, idx)

    n_new = len(new_ids())
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
    void = [i for i in INDICES if i not in idx]
    if void:
        print(f'void indices        {",".join(void)} — see reviews.tsv for cause. '
              f'n is never backfilled.')


if __name__ == '__main__':
    main()
