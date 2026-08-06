#!/usr/bin/env python3
"""Re-derive round 12's published table from the checked-in sheets.

Round 12 asks whether a Finding Floor — three clauses inherited by every finding,
reachable through one digest line — cuts the findings that are not defects.
Pre-registration: `../../rule-ablation/protocols/round-12.md`, written before any
run, with the primary metric, the control, and the difference the design could
catch all fixed in advance.

  findings.tsv              599 findings, with the arm and reviewer position
  clusters.tsv              each finding assigned to a claim; `status` says
                            whether the claim came from round 11 or is new
  adjudications/*.tsv       three agents on the 6 NEW claims only

Verdicts for the 77 reused claims come from `../adjudications/`, unchanged. That
is the point: re-adjudicating them would let the standard drift between arms.

Usage:
  round-12/measure.py
"""
import collections
import csv
import glob
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.dirname(HERE)
T_CRIT, Z_BETA = 2.145, 0.868  # two-sided .05 at df=14; 80% power


def majority(paths):
    sheets = [{r['cluster_id']: r['verdict'].strip()
               for r in csv.DictReader(open(p), delimiter='\t')} for p in paths]
    return {cid: collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
            for cid in sheets[0]}


def compare(a, b):
    n = min(len(a), len(b))
    sp = math.sqrt((st.variance(a) + st.variance(b)) / 2)
    if not sp:
        return 0.0, 0.0
    return ((st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / n)),
            (T_CRIT + Z_BETA) * sp * math.sqrt(2 / n))


def main():
    verdict = majority(sorted(glob.glob(os.path.join(PREV, 'adjudications', '*.tsv'))))
    verdict.update(majority(sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv')))))

    f2c, fresh = {}, 0
    for row in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv')), delimiter='\t'):
        fresh += row['status'] == 'new'
        for fid in row['member_ids'].split(','):
            f2c[fid.strip()] = row['cluster_id']
    real = {c for c, v in verdict.items() if v == 'real'}

    by = collections.defaultdict(lambda: collections.defaultdict(list))
    findings = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv')), delimiter='\t'))
    for f in findings:
        by[f['arm']][f['review']].append(f)

    print(f'{len(findings)} findings, {len(set(f2c.values()))} claims '
          f'({fresh} new this round), {len(real)} adjudicated real\n')

    def cm_notreal(fs):
        return sum(1 for r in fs
                   if r['severity'] in ('Critical', 'Major') and f2c[r['id']] not in real)

    metrics = [
        ('PRIMARY  C+M not-real', cm_notreal, False),
        ('CONTROL  real claims', lambda fs: len({f2c[r['id']] for r in fs
                                                 if f2c[r['id']] in real}), False),
        ('         C+M findings', lambda fs: sum(1 for r in fs
                                                 if r['severity'] in ('Critical', 'Major')), False),
        ('         all findings', len, False),
        ('         precision', lambda fs: sum(1 for r in fs if f2c[r['id']] in real) / len(fs), True),
    ]
    print(f'{"":24s}{"W (floor)":>11s}{"N (HEAD)":>11s}{"t":>8s}{"MDE@80%":>10s}')
    for label, fn, pct in metrics:
        vals = {a: [fn(by[a][k]) for k in sorted(by[a])] for a in ('W', 'N')}
        t, mde = compare(vals['W'], vals['N'])
        fmt = (lambda x: f'{x:.1%}') if pct else (lambda x: f'{x:.2f}')
        print(f'{label:24s}{fmt(st.mean(vals["W"])):>11s}{fmt(st.mean(vals["N"])):>11s}'
              f'{t:>8.2f}{mde:>10.2f}')

    print('\nper-review primary (Critical/Major findings that are not defects)')
    for arm in ('W', 'N'):
        print(f'  {arm}: {sorted(cm_notreal(by[arm][k]) for k in by[arm])}')


if __name__ == '__main__':
    main()
