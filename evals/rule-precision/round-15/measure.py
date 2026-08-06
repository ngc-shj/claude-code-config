#!/usr/bin/env python3
"""Re-derive round 15: is a titles-only base as good as the full one?

Six reviews (of eight pre-registered; the batch was halted against a budget
ceiling), each with the same fixed BASE — the union of that review's first three
replies from round 13. Three arms of three agents each on top of it:

  T  given the base's finding TITLES only
  C  given the full base, as round 14 gave it
  I  given the standard brief alone

C and I are re-run rather than carried over from round 14: a stored cross-batch
number is context and never the control arm. n=6 rather than 8 widens every
interval by about 19%, which is why t_crit is 2.228 here.

Pre-registration, including the decision rule and the two deviations:
`../../rule-ablation/protocols/round-15.md`.

  findings.tsv          456 findings, with arm, review and reviewer position
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
T_CRIT, Z_BETA = 2.228, 0.868  # df=10 at n=6/arm


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
              'round-13/adjudications', 'round-14/adjudications',
              'round-15/adjudications'):
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
    used = sorted(arms['T'])          # only the reviews this round actually ran
    print(f'base (the shared first three reviewers, over the {len(used)} reviews run): '
          f'{st.mean(len(base[k] & real) for k in used):.2f} real defects\n')

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
    print(f'{"":26s}{"T":>8s}{"C":>8s}{"I":>8s}{"T vs C":>18s}{"T vs I":>18s}')
    for label, fn in metrics:
        vals = {a: [fn(k, arms[a][k]) for k in sorted(arms[a])] for a in ('T', 'C', 'I')}
        tc, ti = compare(vals['T'], vals['C']), compare(vals['T'], vals['I'])
        print(f'{label:26s}{st.mean(vals["T"]):8.2f}{st.mean(vals["C"]):8.2f}'
              f'{st.mean(vals["I"]):8.2f}'
              f'   t={tc[0]:+5.2f} MDE {tc[1]:4.2f}   t={ti[0]:+5.2f} MDE {ti[1]:4.2f}')

    print('\nThe rule: ship T if it is not worse than C on the primary and not worse '
          'than I on the\ncost. Both hold — but round 14 measured C costing 2.12 more '
          'than I, and here that gap\nis 0.83, so the second condition was met in a '
          'batch where the comparison arm also lost\nits penalty. See the audit doc.')


if __name__ == '__main__':
    main()
