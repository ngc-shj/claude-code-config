#!/usr/bin/env python3
"""Re-derive the finding-precision numbers from the adjudication sheets.

`../rule-ablation/` scores whether a review's fix for ONE seeded defect has the
properties a correct fix needs. That is remedy quality, and it says nothing
about the rest of what a review reports — whether those findings are accurate,
and how many genuine defects the review reaches.

This measures both, on round 11's material (`../rule-ablation/protocols/round-11.md`):

  findings.tsv                574 findings, one row each, with the arm and the
                              reviewer position (part 0/1/2) they came from
  clusters.tsv                the 574 grouped into 83 distinct claims
  adjudications/*.tsv         three agents' verdicts on the 83 claims, blind to
                              arm and to how many reviewers made each claim

Majority vote per claim; a finding inherits its cluster's verdict.

Usage:
  measure.py
"""
import collections
import csv
import itertools
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
T_CRIT, Z_BETA = 2.145, 0.868  # two-sided .05 at df=14; 80% power


def load():
    findings = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv')), delimiter='\t'))
    f2c = {}
    for row in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv')), delimiter='\t'):
        for fid in row['member_ids'].split(','):
            f2c[fid.strip()] = row['cluster_id']
    sheets = []
    for i in (1, 2, 3):
        path = os.path.join(HERE, 'adjudications', f'adjudicator{i}.tsv')
        sheets.append({r['cluster_id']: r['verdict'].strip()
                       for r in csv.DictReader(open(path), delimiter='\t')})
    return findings, f2c, sheets


def majority(sheets):
    out = {}
    for cid in sheets[0]:
        top, n = collections.Counter(s.get(cid) for s in sheets).most_common(1)[0]
        out[cid] = top if n >= 2 else 'split'
    return out


def compare(a, b):
    """Welch-free pooled t and the difference an n-per-arm design could catch."""
    n = min(len(a), len(b))
    sp = math.sqrt((st.variance(a) + st.variance(b)) / 2)
    if not sp:
        return 0.0, 0.0
    return ((st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / n)),
            (T_CRIT + Z_BETA) * sp * math.sqrt(2 / n))


def main():
    findings, f2c, sheets = load()
    verdict = majority(sheets)
    real = {c for c, v in verdict.items() if v == 'real'}

    print(f'{len(findings)} findings, {len(verdict)} distinct claims, '
          f'{len(real)} adjudicated real\n')
    print('claim verdicts:', dict(collections.Counter(verdict.values())))
    agree = [sum(1 for c in sheets[0] if a.get(c) == b.get(c)) / len(sheets[0])
             for a, b in itertools.combinations(sheets, 2)]
    print('adjudicator agreement:', ', '.join(f'{x:.1%}' for x in agree))

    per_arm = collections.defaultdict(collections.Counter)
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in findings:
        per_arm[f['arm']][verdict[f2c[f['id']]]] += 1
        by[f['arm']][f['review']].append((int(f['part']), f['id']))

    print('\nfinding-level precision')
    for arm in sorted(per_arm):
        c = per_arm[arm]
        tot = sum(c.values())
        print(f'  {arm}: {tot:4d} findings   real {c["real"]:3d} ({c["real"] / tot:5.1%})'
              f'   not-a-defect {c["not-a-defect"]:3d}   wrong {c["wrong"]:2d}')

    print(f'\ndistinct real claims reached, of {len(real)}')
    cov, prec = {}, {}
    for arm in sorted(by):
        n1, n2, n3, pr = [], [], [], []
        for k in sorted(by[arm]):
            parts = [[fid for p, fid in by[arm][k] if p == i] for i in range(3)]
            rs = [{f2c[i] for i in p if f2c[i] in real} for p in parts]
            n1 += [len(r) for r in rs]
            n2 += [len(rs[i] | rs[j]) for i, j in ((0, 1), (0, 2), (1, 2))]
            n3.append(len(rs[0] | rs[1] | rs[2]))
            ids = [fid for _, fid in by[arm][k]]
            pr.append(sum(1 for i in ids if f2c[i] in real) / len(ids))
        cov[arm], prec[arm] = n3, pr
        print(f'  {arm}: N=1 {st.mean(n1):4.1f}   N=2 {st.mean(n2):4.1f} '
              f'(+{st.mean(n2) - st.mean(n1):3.1f})   N=3 {st.mean(n3):4.1f} '
              f'(+{st.mean(n3) - st.mean(n2):3.1f})   precision {st.mean(pr):5.1%}')

    arms = sorted(cov)
    if len(arms) == 2:
        a, b = arms
        t, mde = compare(cov[a], cov[b])
        print(f'\ncoverage at N=3, {a} vs {b}: t={t:+.2f} (|t|>{T_CRIT} is p<.05), '
              f'MDE@80% {mde:.2f} claims')
        t, mde = compare(prec[a], prec[b])
        print(f'precision, {a} vs {b}:        t={t:+.2f}, MDE@80% {mde:.1%}')


if __name__ == '__main__':
    main()
