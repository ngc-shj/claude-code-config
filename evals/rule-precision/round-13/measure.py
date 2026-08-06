#!/usr/bin/env python3
"""Re-derive round 13's reviewer-count curve from the checked-in sheets.

Eight reviews of six IDENTICAL general reviewers, on one fixture, HEAD materials
with the Finding Floor in place. For each review and each N in 1…6 the metric is
averaged over all C(6,N) subsets of its replies, so one batch of 48 agents yields
six points.

Sub-sampling is only valid for identical reviewers, and that is why this arm is
generalist: any N of six generalists is an unbiased sample of "N generalists",
whereas a 2-subset of the specialised split could be {functionality, security} or
{security, testing}, which are different configurations.

Pre-registration, including the decision rule: `../../rule-ablation/protocols/round-13.md`.

  findings.tsv          591 findings, with the review and reviewer position
  clusters.tsv          each finding assigned to a claim; `status` marks the ones
                        this round added to the inventory
  adjudications/*.tsv   three agents on the 6 NEW claims only

Verdicts for reused claims come from `../adjudications/` and
`../round-12/adjudications/`, unchanged — holding the standard fixed across
rounds is the point.

Usage:
  round-13/measure.py
"""
import collections
import csv
import glob
import itertools
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.dirname(HERE)
TOKENS_PER_REVIEWER = 71_000  # measured mean over rounds 11-13


def majority(paths):
    sheets = [{r['cluster_id']: r['verdict'].strip()
               for r in csv.DictReader(open(p), delimiter='\t')} for p in paths]
    return {cid: collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
            for cid in sheets[0]}


def main():
    verdict = {}
    for d in (os.path.join(PREV, 'adjudications'),
              os.path.join(PREV, 'round-12', 'adjudications'),
              os.path.join(HERE, 'adjudications')):
        verdict.update(majority(sorted(glob.glob(os.path.join(d, '*.tsv')))))
    real = {c for c, v in verdict.items() if v == 'real'}

    f2c, fresh = {}, 0
    for row in csv.DictReader(open(os.path.join(HERE, 'clusters.tsv')), delimiter='\t'):
        fresh += row['status'] == 'new'
        for fid in row['member_ids'].split(','):
            f2c[fid.strip()] = row['cluster_id']

    by = collections.defaultdict(lambda: collections.defaultdict(list))
    findings = list(csv.DictReader(open(os.path.join(HERE, 'findings.tsv')), delimiter='\t'))
    for f in findings:
        by[f['review']][f['part']].append(f)

    print(f'{len(findings)} findings over {len(by)} reviews of 6 reviewers; '
          f'{len(verdict)} claims in the inventory ({fresh} added here), {len(real)} real\n')
    print(f'{"N":>2s}{"real defects":>14s}{"marginal":>10s}'
          f'{"C+M non-defects":>18s}{"marginal":>10s}{"tokens":>9s}{"per defect":>12s}')

    prev_real = prev_noise = 0.0
    for n in range(1, 7):
        reached, noise = [], []
        for review in by:
            for subset in itertools.combinations(sorted(by[review]), n):
                fs = [f for p in subset for f in by[review][p]]
                reached.append(len({f2c[f['id']] for f in fs if f2c[f['id']] in real}))
                noise.append(sum(1 for f in fs if f['severity'] in ('Critical', 'Major')
                                 and f2c[f['id']] not in real))
        r, x = st.mean(reached), st.mean(noise)
        cost = n * TOKENS_PER_REVIEWER
        print(f'{n:2d}{r:14.1f}{(r - prev_real) if n > 1 else 0:10.1f}'
              f'{x:18.1f}{(x - prev_noise) if n > 1 else 0:10.1f}'
              f'{cost // 1000:8d}k{cost / r:12.0f}')
        prev_real, prev_noise = r, x

    print('\nThe pre-registered rule: adopt the smallest N whose next reviewer adds '
          'under 1.0 real defect.')


if __name__ == '__main__':
    main()
