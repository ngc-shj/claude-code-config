#!/usr/bin/env python3
"""Re-derive an ablation round's published numbers from its scorer sheets.

Every table in `docs/archive/audit/2026-08-04-rule-ablation.md` came from three
agents scoring an anonymised, shuffled submission set against a fixed rubric.
The submissions themselves were not kept — they are ~900KB of redacted review
text nobody re-reads — but the sheets and the arm mapping were, so the numbers
remain checkable rather than merely asserted.

Majority vote per property across the three scorers; a submission the majority
marked `no-fix` scores nothing and is counted separately.

  scores/round-8-mapping.tsv    sid -> fixture, arm, preamble
  scores/round-8-scorer{1,2,3}.txt   one line per submission

Usage:
  score.py --round 8
  score.py --mapping M.tsv --scorers A.txt B.txt C.txt --props 9 --subset 3,4,5,8,9

`--subset` names the properties a change was predicted to move; the complement
is printed beside it as the control. Both were pre-registered before any output
was read — see `protocols/`.
"""
import argparse
import collections
import itertools
import math
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCORES = os.path.join(HERE, 'scores')

# Pre-registered in protocols/round-{7,8,9}.md before any output was read.
ROUNDS = {
    '6.5': dict(mapping='round-6.5-mapping.tsv', stem='round-6.5', props=9, subset=[]),
    '7-F1': dict(mapping='round-7-F1-mapping.tsv', stem='round-7-F1', props=19,
                 subset=[5, 6, 8, 9, 11, 16, 17, 18]),
    '7-F3': dict(mapping='round-7-F3-mapping.tsv', stem='round-7-F3', props=11,
                 subset=[5, 6, 8, 9, 11]),
    '8': dict(mapping='round-8-mapping.tsv', stem='round-8', props=9, subset=[3, 4, 5, 8, 9]),
    '9': dict(mapping='round-9-mapping.tsv', stem='round-9', props=9, subset=[5]),
    '10': dict(mapping='round-10-mapping.tsv', stem='round-10', props=11, subset=[]),
    # subset = the properties no material either arm carries states; see
    # score/F9-merged.md, tagged before any round-11 arm output existed.
    '11': dict(mapping='round-11-mapping.tsv', stem='round-11', props=34,
               subset=[8, 10, 14, 18, 19, 22, 25, 26, 31, 32, 33, 34]),
}


def parse_sheet(path, props):
    """One line per submission: `<ID>: P1=y ... total=N`, or `<ID>: no-fix`."""
    out = {}
    for line in open(path):
        m = re.match(r'\s*([A-Za-z0-9]+)\s*:\s*(.*)', line)
        if not m:
            continue
        sid, rest = m.groups()
        if 'no-fix' in rest:
            out[sid] = None
        else:
            got = dict(re.findall(r'([PQ]\d+)=([yn])', rest))
            if len(got) == props:
                out[sid] = got
    return out


def load_mapping(path):
    rows = {}
    with open(path) as fh:
        header = fh.readline()
        for line in fh:
            parts = line.rstrip('\n').split('\t')
            sid, fixture, arm = parts[0], parts[1], parts[2]
            rows[sid] = (fixture, arm)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--round', choices=sorted(ROUNDS))
    ap.add_argument('--mapping')
    ap.add_argument('--scorers', nargs=3)
    ap.add_argument('--props', type=int)
    ap.add_argument('--subset', default='')
    args = ap.parse_args()

    if args.round:
        cfg = ROUNDS[args.round]
        mapping_path = os.path.join(SCORES, cfg['mapping'])
        sheets = [os.path.join(SCORES, f"{cfg['stem']}-scorer{i}.txt") for i in (1, 2, 3)]
        props, subset = cfg['props'], cfg['subset']
    elif args.mapping and args.scorers and args.props:
        mapping_path, sheets, props = args.mapping, args.scorers, args.props
        subset = [int(x) for x in args.subset.split(',') if x.strip()]
    else:
        sys.exit('need --round, or all of --mapping/--scorers/--props')

    mapping = load_mapping(mapping_path)
    scorers = [parse_sheet(p, props) for p in sheets]
    names = [f'P{i}' for i in range(1, props + 1)]
    if not any(n in (list(scorers[0].values()) or [{}])[0] or {} for n in names):
        names = [f'Q{i}' for i in range(1, props + 1)]
    sub = [names[i - 1] for i in subset]
    comp = [n for n in names if n not in sub]

    cells = collections.defaultdict(list)
    for sid, (fixture, arm) in sorted(mapping.items()):
        votes = [s.get(sid) for s in scorers]
        present = [v for v in votes if v is not None]
        if len(present) < 2:
            cells[(fixture, arm)].append(None)
            continue
        maj = {n: ('y' if sum(1 for v in present if v.get(n) == 'y') >= 2 else 'n')
               for n in names}
        cells[(fixture, arm)].append(maj)

    print(f'{len(mapping)} submissions, {props} properties, '
          f'{len(sub)} in the pre-registered subset\n')
    head = f'{"cell":14s}{"n":>4s}{"no-fix":>8s}'
    if sub:
        head += f'{"subset":>9s}{"control":>9s}'
    print(head + f'{"total":>8s}')
    for key in sorted(cells):
        vals = [m for m in cells[key] if m]
        nofix = sum(1 for m in cells[key] if m is None)
        if not vals:
            continue
        tot = sum(sum(1 for n in names if m[n] == 'y') for m in vals) / len(vals)
        line = f'{key[0] + " " + key[1]:14s}{len(cells[key]):4d}{nofix:8d}'
        if sub:
            s = sum(sum(1 for n in sub if m[n] == 'y') for m in vals) / len(vals)
            c = sum(sum(1 for n in comp if m[n] == 'y') for m in vals) / len(vals)
            line += f'{s:9.2f}{c:9.2f}'
        print(line + f'{tot:8.2f}')

    print('\nper-property y-rate')
    print(f'{"cell":14s}' + ''.join(f'{n:>6s}' for n in names))
    for key in sorted(cells):
        vals = [m for m in cells[key] if m]
        if not vals:
            continue
        row = ''.join(f'{sum(1 for m in vals if m[n] == "y")}/{len(vals):<4d}' for n in names)
        print(f'{key[0] + " " + key[1]:14s}' + row)

    # A null is only worth reading beside the difference the design could have
    # caught. Rounds 1-3 called detection flat at n=8 per arm, where 8/8 vs 6/8
    # is p=0.47 — that null could only ever have ruled out a very large effect.
    pairs = collections.defaultdict(dict)
    for (fixture, arm), ms in cells.items():
        vals = [sum(1 for n in names if m[n] == 'y') for m in ms if m]
        if len(vals) > 1:
            pairs[fixture][arm] = vals
    printed = False
    for fixture, arms in sorted(pairs.items()):
        if len(arms) != 2:
            continue
        (a1, v1), (a2, v2) = sorted(arms.items())
        n = min(len(v1), len(v2))
        sp = math.sqrt((statistics.variance(v1) + statistics.variance(v2)) / 2)
        if not sp:
            continue
        if not printed:
            print('\nobserved difference vs what n could catch '
                  '(two-sided .05, 80% power)')
            printed = True
        diff = abs(statistics.mean(v1) - statistics.mean(v2))
        mde = (2.145 + 0.868) * sp * math.sqrt(2 / n)
        verdict = 'above MDE' if diff >= mde else 'below MDE — bounds the effect, not zero'
        print(f'  {fixture} {a1} vs {a2}: diff {diff:.2f}, MDE {mde:.2f} /{props} — {verdict}')

    print('\nscorer agreement')
    for a, b in itertools.combinations(range(3), 2):
        same = tot = 0
        for sid in mapping:
            va, vb = scorers[a].get(sid), scorers[b].get(sid)
            if va is None or vb is None:
                continue
            for n in names:
                tot += 1
                same += va.get(n) == vb.get(n)
        if tot:
            print(f'  scorer{a + 1} vs scorer{b + 1}: {same}/{tot} = {same / tot:.2%}')


if __name__ == '__main__':
    main()
