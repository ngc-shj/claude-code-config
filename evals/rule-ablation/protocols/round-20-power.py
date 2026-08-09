#!/usr/bin/env python3
"""Reproduce round 20's power table from round 19's observed paired series.

The MDE here does ONE job: sizing the round before it runs. It is not a bar the
observed difference has to clear — see `../../rule-precision/methods.md`, which
round 19 is the worked example for.

Usage:  evals/rule-ablation/protocols/round-20-power.py
"""
import math
import statistics as st

Z_BETA = 0.842
T_PAIRED = {6: 2.571, 9: 2.306, 12: 2.201}      # two-sided .05 at df = n-1

# Round 19, F10, Critical/Major findings whose claim is `not-a-defect`, per
# review. One batch, so these differences are the paired series round 20 is
# sized from.
R19 = {'W': [2, 2, 1, 2, 2, 1],
       'W2': [4, 5, 3, 3, 3, 3],
       'N': [6, 3, 5, 2, 3, 3]}


def sd_d(a, b):
    return st.stdev([x - y for x, y in zip(a, b)])


def mde(sd, n):
    return (T_PAIRED[n] + Z_BETA) * sd / math.sqrt(n)


def main():
    print('Round 19 observed paired sds on the primary metric:\n')
    for a, b in (('W', 'W2'), ('W', 'N'), ('W2', 'N')):
        print(f'  sd({a} - {b}) = {sd_d(R19[a], R19[b]):.3f}')

    print('\nRound 20 arms — a 2x2 in (clause 1) x (clause 3), clause 2 always present:\n')
    print('  W    clauses 1, 2, 3      W12  clauses 1, 2')
    print('  W23  clauses 2, 3         W2   clause 2 alone')
    print('\n  PRIMARY    W - W23   clause 1, with 2 and 3 present')
    print('  SECONDARY  W - W12   clause 3, with 1 and 2 present')

    print(f'\n{"sd_d assumed":>14s}' + ''.join(f'{f"MDE n={n}":>11s}' for n in T_PAIRED))
    for sd in (0.753, 1.0, 1.2, 1.5):
        mark = '   <- W - W2, observed' if sd == 0.753 else ''
        print(f'{sd:14.3f}' + ''.join(f'{mde(sd, n):11.2f}' for n in T_PAIRED) + mark)

    print("""
WHAT THE ROUND IS SIZED FOR, and what that number is not.

Round 19 measured clauses 1 and 3 contributing -1.83 JOINTLY. How that splits is
unknown; "about 0.9 each" is a DESIGN ASSUMPTION used to pick n, and nothing has
observed it. The round is sized so that an even split is visible, because a
lopsided split is the easier case and sizing for it would leave the likelier one
undetectable.""")
    for share in (1.83, 1.20, 0.92, 0.60):
        print(f'  clause 1 carrying {share:.2f} needs sd_d <= '
              f'{share * math.sqrt(6) / (T_PAIRED[6] + Z_BETA):.2f} at n=6, '
              f'{share * 3 / (T_PAIRED[9] + Z_BETA):.2f} at n=9')

    print(f'\n  n=6  {4 * 6 * 3} review agents   n=9  {4 * 9 * 3} review agents   '
          f'n=12  {4 * 12 * 3} review agents')
    print('\nAt round 19\'s observed sd_d of 0.753, n=6 sees an even split only if the sd\n'
          'holds below 0.66 — it did not — and n=9 sees it with room. n=9.')


if __name__ == '__main__':
    main()
