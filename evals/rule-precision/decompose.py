#!/usr/bin/env python3
"""Split the Finding Floor's primary metric into the two failure modes it mixes.

POST-HOC. Rounds 12 and 17 both pre-registered ONE primary — Critical/Major
findings whose claim is not `real` — and that set contains two things the
adjudication has always distinguished and the metric then merges:

  not-a-defect   accurate about the code, but a preference or a requirement
                 asserted about code the change does not contain
  wrong          misreads the code

The Finding Floor is aimed at the first (`skills/triangulate/common-rules.md`
says so in its own rationale: 5 misreads against 34 ungrounded requirements and
83 preferences). Nothing in it addresses the second. Splitting the metric along
that line is therefore not data dredging for a better p-value; it is separating
the quantity the intervention targets from one it does not.

This was NOT pre-registered in either round and does not change either round's
recorded result. It is a hypothesis about the metric, to be pre-registered
before the next round rather than claimed here.

Usage:
  evals/rule-precision/decompose.py
"""
import collections
import csv
import glob
import math
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
# Each round's own power constants, so the `PRIMARY as published` row reproduces
# that round's printed MDE to the digit rather than to something near it. The
# two rounds rounded z(0.80) differently and neither is being corrected here.
CONST = {8: (2.145, 0.868), 9: (2.120, 0.842)}   # n -> (t at df=2(n-1), z_beta)


def majority(paths):
    sheets = [{r['cluster_id']: r['verdict'].strip()
               for r in csv.DictReader(open(p, newline=''), delimiter='\t')}
              for p in paths]
    return {cid: collections.Counter(s.get(cid) for s in sheets).most_common(1)[0][0]
            for cid in sheets[0]}


def rows(path):
    return list(csv.DictReader(open(os.path.join(HERE, path), newline=''), delimiter='\t'))


def assignment(path):
    out = {}
    for row in rows(path):
        for fid in row['member_ids'].split(','):
            out[fid.strip()] = row['cluster_id']
    return out


def round_12():
    """F9. Verdicts: round 11's sheets, plus round 12's on its 6 new claims."""
    verdict = majority(sorted(glob.glob(os.path.join(HERE, 'adjudications', '*.tsv'))))
    verdict.update(majority(sorted(glob.glob(os.path.join(HERE, 'round-12', 'adjudications', '*.tsv')))))
    return verdict, assignment('round-12/clusters.tsv'), rows('round-12/findings.tsv')


def round_17():
    """F10. Verdicts: round 16's seed inventory, plus round 17's on its 30 new."""
    verdict = {r['cluster_id']: r['verdict'].strip()
               for r in rows('round-16/seed/inventory.tsv')}
    verdict.update(majority(sorted(glob.glob(os.path.join(HERE, 'round-17', 'adjudications', '*.tsv')))))
    return verdict, assignment('round-17/clusters.tsv'), rows('round-17/findings.tsv')


def series(findings, pred):
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in findings:
        by[f['arm']][f['review']].append(f)
    order = sorted(by['W'], key=int)
    return {a: [sum(1 for f in by[a][k] if pred(f)) for k in order] for a in ('W', 'N')}


def compare(s):
    a, b = s['W'], s['N']
    sp = math.sqrt((st.variance(a) + st.variance(b)) / 2)
    n = len(a)
    if not sp:
        return st.mean(a), st.mean(b), 0.0, 0.0
    t_crit, z_beta = CONST[n]
    return (st.mean(a), st.mean(b),
            (st.mean(a) - st.mean(b)) / (sp * math.sqrt(2 / n)),
            (t_crit + z_beta) * sp * math.sqrt(2 / n))


def report(label, fixture, verdict, f2c, findings):
    real = {c for c, x in verdict.items() if x == 'real'}
    cm = lambda f: f['severity'] in ('Critical', 'Major')
    parts = (
        ('PRIMARY as published', lambda f: cm(f) and f2c[f['id']] not in real),
        ('  not-a-defect  (scope)', lambda f: cm(f) and verdict[f2c[f['id']]] == 'not-a-defect'),
        ('  wrong         (misread)', lambda f: cm(f) and verdict[f2c[f['id']]] == 'wrong'),
    )
    counts = collections.Counter(verdict[c] for c in set(f2c.values()))
    print(f'\n{label} — {fixture}: {len(findings)} findings, '
          f'{len(set(f2c.values()))} claims hit '
          f'({counts["wrong"]} wrong, {counts["not-a-defect"]} not-a-defect, {counts["real"]} real)')
    print(f'{"":28s}{"W":>7s}{"N":>7s}{"diff":>8s}{"t":>8s}{"MDE":>8s}')
    for name, pred in parts:
        s = series(findings, pred)
        w, n, t, m = compare(s)
        print(f'{name:28s}{w:7.2f}{n:7.2f}{w - n:+8.2f}{t:8.2f}{m:8.2f}')
        print(f'{"":28s}W {s["W"]}\n{"":28s}N {s["N"]}')


def main():
    report('Round 12', 'F9', *round_12())
    report('Round 17', 'F10', *round_17())
    print("""
Read: on F9 the split is degenerate — no Critical/Major misread was written by
either arm — so the published primary and the not-a-defect series are the same
number. On F10 they are not, and the difference goes the way that matters: the
effect on the quantity the floor targets is LARGER than the published composite
(-2.67 at t=-5.95, against -2.11 at t=-3.05), because a misread claim the floor
does not act on is mixed into the same total.""")


if __name__ == '__main__':
    main()
