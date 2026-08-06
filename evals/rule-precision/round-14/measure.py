#!/usr/bin/env python3
"""Re-derive round 14: does a second wave gain from being told what the first found?

Eight reviews, each with a fixed shared BASE — the union of that review's first
three replies from round 13. Two arms of three agents each on top of it:

  C  given the base and asked for what it missed
  I  given the standard brief alone

Arm I is round 13's 4th-6th reviewer RE-RUN, not reused: round 9 established that
a stored cross-batch number is context and never the control arm.

Pre-registration, including the decision rule that this result trips:
`../../rule-ablation/protocols/round-14.md`.

  findings.tsv          451 findings, with arm, review and reviewer position
  clusters.tsv          each finding assigned to a claim; `status` marks the 20
                        this round added
  adjudications/*.tsv   three agents on those 20 NEW claims only

Base membership comes from `../round-13/`, and verdicts for reused claims from
the three earlier rounds' adjudications, unchanged.

Usage:
  round-14/measure.py
"""
import collections
import csv
import glob
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.dirname(HERE)
T_CRIT, Z_BETA = 2.145, 0.868


def majority(paths):
    sheets = [{r['cluster_id']: r['verdict'].strip()
               for r in csv.DictReader(open(p), delimiter='\t')} for p in paths]
    return {cid: collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
            for cid in sheets[0]}


def assignment(path):
    out = {}
    for row in csv.DictReader(open(path), delimiter='\t'):
        for fid in row['member_ids'].split(','):
            out[fid.strip()] = row['cluster_id']
    return out


def compare(a, b):
    n = min(len(a), len(b))
    sp = math.sqrt((st.variance(a) + st.variance(b)) / 2)
    if not sp:
        return 0.0, 0.0
    return ((st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / n)),
            (T_CRIT + Z_BETA) * sp * math.sqrt(2 / n))


def main():
    verdict = {}
    for d in ('adjudications', 'round-12/adjudications',
              'round-13/adjudications', 'round-14/adjudications'):
        verdict.update(majority(sorted(glob.glob(os.path.join(PREV, d, '*.tsv')))))
    real = {c for c, v in verdict.items() if v == 'real'}

    f2c = assignment(os.path.join(HERE, 'clusters.tsv'))
    b2c = assignment(os.path.join(PREV, 'round-13', 'clusters.tsv'))

    base = collections.defaultdict(set)
    for row in csv.DictReader(open(os.path.join(PREV, 'round-13', 'findings.tsv')),
                              delimiter='\t'):
        if row['part'] in '012':          # the first three reviewers are the base
            base[row['review']].add(b2c[row['id']])

    arms = collections.defaultdict(lambda: collections.defaultdict(list))
    findings = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv')), delimiter='\t'))
    for f in findings:
        arms[f['arm']][f['review']].append(f)

    fresh = sum(1 for r in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv')),
                                          delimiter='\t') if r['status'] == 'new')
    print(f'{len(findings)} findings, {len(verdict)} claims in the inventory '
          f'({fresh} added here), {len(real)} real')
    print(f'base (the shared first three reviewers): '
          f'{st.mean(len(base[k] & real) for k in base):.2f} real defects\n')

    metrics = [
        ('PRIMARY real defects ADDED',
         lambda k, fs: len({f2c[f['id']] for f in fs if f2c[f['id']] in real} - base[k])),
        ('COST    C+M non-defects',
         lambda k, fs: sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
                           and f2c[f['id']] not in real)),
        ('        six-reviewer total',
         lambda k, fs: len(({f2c[f['id']] for f in fs if f2c[f['id']] in real} | base[k]) & real)),
        ('        findings written', lambda k, fs: len(fs)),
        ('        restating the base',
         lambda k, fs: sum(1 for f in fs if f2c[f['id']] in base[k])),
    ]
    print(f'{"":30s}{"C (told)":>11s}{"I (blind)":>11s}{"t":>8s}{"MDE@80%":>9s}')
    for label, fn in metrics:
        vals = {a: [fn(k, arms[a][k]) for k in sorted(arms[a])] for a in ('C', 'I')}
        t, mde = compare(vals['C'], vals['I'])
        print(f'{label:30s}{st.mean(vals["C"]):11.2f}{st.mean(vals["I"]):11.2f}'
              f'{t:8.2f}{mde:9.2f}')

    print('\nThe rule: adopt conditioning if C adds >= 1.0 more real defect AND its '
          'non-defect count\nis no worse. It adds more and costs more, so the '
          'pre-registered output is both numbers\nand no recommendation.')


if __name__ == '__main__':
    main()
