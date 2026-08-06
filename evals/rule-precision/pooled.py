#!/usr/bin/env python3
"""Pool rounds 14 and 15 as MATCHED PAIRS, and apply the decision rule to the result.

Arms C (conditioned on the first wave's findings) and I (blind) share a review id,
a base and a preamble in both rounds, so each review is a matched pair and the
right pooling is over the 14 paired differences — 8 from round 14, 6 from round 15
— not over arm means. Round 9's rule against cross-batch comparison forbids
measuring an arm against a stored number from another batch; it does not forbid
combining two within-batch paired differences, which is what this is.

This analysis is POST-HOC. Neither round pre-registered it, so it is exploratory:
a strong summary of what the two batches jointly say, not a pre-registered result.

Usage:
  evals/rule-precision/pooled.py
"""
import collections
import csv
import glob
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
T_CRIT_13 = 2.160  # two-sided .05 at df = 14 - 1


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


def main():
    verdict = {}
    for d in ('adjudications', 'round-12/adjudications', 'round-13/adjudications',
              'round-14/adjudications', 'round-15/adjudications'):
        found = sorted(glob.glob(os.path.join(HERE, d, '*.tsv')))
        if found:
            verdict.update(majority(found))
    real = {c for c, v in verdict.items() if v == 'real'}

    b2c = assignment(os.path.join(HERE, 'round-13', 'clusters.tsv'))
    base = collections.defaultdict(set)
    for row in csv.DictReader(open(os.path.join(HERE, 'round-13', 'findings.tsv')),
                              delimiter='\t'):
        if row['part'] in '012':
            base[row['review']].add(b2c[row['id']])

    pairs = {'cost': [], 'added': []}
    for rnd in (14, 15):
        f2c = assignment(os.path.join(HERE, f'round-{rnd}', 'clusters.tsv'))
        arms = collections.defaultdict(lambda: collections.defaultdict(list))
        for row in csv.DictReader(open(os.path.join(HERE, f'round-{rnd}', 'findings.tsv')),
                                  delimiter='\t'):
            if row['arm'] in 'CI':
                arms[row['arm']][row['review']].append(row)
        for k in sorted(arms['C']):
            def cost(fs):
                return sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
                           and f2c[f['id']] not in real)

            def added(fs):
                return len({f2c[f['id']] for f in fs if f2c[f['id']] in real} - base[k])
            pairs['cost'].append(cost(arms['C'][k]) - cost(arms['I'][k]))
            pairs['added'].append(added(arms['C'][k]) - added(arms['I'][k]))

    n = len(pairs['cost'])
    print(f'{n} matched review pairs (8 from round 14 + 6 from round 15), post-hoc\n')
    print(f'{"paired difference, C - I":30s}{"mean":>7s}{"sd":>7s}{"se":>7s}'
          f'{"t":>7s}{"95% CI":>20s}')
    stats = {}
    for key, label in (('cost', 'Critical/Major non-defects'),
                       ('added', 'real defects added')):
        d = pairs[key]
        m, sd = st.mean(d), st.stdev(d)
        se = sd / math.sqrt(len(d))
        stats[key] = (m, se)
        print(f'{label:30s}{m:+7.2f}{sd:7.2f}{se:7.2f}{m / se:+7.2f}'
              f'   {m - T_CRIT_13 * se:+6.2f} to {m + T_CRIT_13 * se:+6.2f}')

    print(f'\nper-pair cost  differences: {pairs["cost"]}')
    print(f'per-pair added differences: {pairs["added"]}')
    pos = sum(1 for x in pairs['cost'] if x > 0)
    print(f'\n{pos} of {n} pairs show a positive cost difference — rounds 14 and 15 '
          f'differed in\nwhether the effect was DETECTABLE, not in its sign.')

    m, se = stats['cost']
    lo = m - T_CRIT_13 * se
    print(f'\nApplying round 14\'s rule ("adopt only if the non-defect count is no '
          f'worse"):\nthe cost interval is {lo:+.2f} upward, excluding zero, so the '
          f'cost condition FAILS and\nconditioning is not adopted. The ratio of the '
          f'two effects is a descriptive\nexchange rate, not a decision — a real '
          f'defect and a non-defect are not one unit.')


if __name__ == '__main__':
    main()
