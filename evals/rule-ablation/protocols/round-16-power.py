#!/usr/bin/env python3
"""Re-derive round 16's sample size and its sensitivity to the borrowed variance.

Written WITH the protocol and before any run, so the numbers in
`round-16.md` are checkable rather than asserted.

The paired standard deviations are SURROGATES: they come from six paired reviews
of a different contrast (round 15's T against C, two conditioning variants) on a
different fixture. An sd from n=6 carries roughly a +/-40% interval of its own,
which is why the sensitivity table matters more than the point estimate.

Usage:
  round-16-power.py
"""
import math

SD_PRIMARY = 2.32   # round 15, paired T-C, Critical/Major non-defects
SD_CONTROL = 2.53   # round 15, paired T-C, real defects added
REDUCTION = 1.35    # pre-registered primary effect
MARGIN = 1.50       # pre-registered non-inferiority margin
POWER_Z = 0.8416    # 80%

# one-sided t at alpha .05, by df
T_ONE = {4: 2.132, 5: 2.015, 6: 1.943, 7: 1.895, 8: 1.860, 9: 1.833, 10: 1.812,
         11: 1.796, 12: 1.782, 13: 1.771, 14: 1.761, 15: 1.753, 16: 1.746,
         17: 1.740, 18: 1.734, 19: 1.729, 20: 1.725, 24: 1.711, 29: 1.699,
         34: 1.691, 39: 1.685, 44: 1.680, 49: 1.677, 59: 1.671, 79: 1.664,
         99: 1.660}


def n_paired(sd, delta):
    """Reviews per arm for a paired one-sided test, solved iteratively in t."""
    n = 4
    for _ in range(300):
        df = max(4, n - 1)
        tc = T_ONE[min(T_ONE, key=lambda k: abs(k - df))]
        nxt = max(4, math.ceil(((tc + POWER_Z) * sd / delta) ** 2))
        if nxt == n:
            break
        n = nxt
    return n


def main():
    print(f'paired sds borrowed from round 15 (T-C, n=6, fixture F9): '
          f'primary {SD_PRIMARY}, control {SD_CONTROL}\n')

    print('reviews per arm, by effect size')
    print(f'{"primary reduction":>20s}{"n":>5s}     {"margin":>8s}{"n":>5s}')
    for d, m in ((0.75, 1.00), (1.00, 1.50), (1.25, 2.00), (1.57, 2.50)):
        print(f'{-d:>20.2f}{n_paired(SD_PRIMARY, d):>5d}     '
              f'{m:>8.2f}{n_paired(SD_CONTROL, m):>5d}')
    print('\n  -1.57 is the ESTIMATED conditioning penalty (CI +0.67..+2.47), a landmark')
    print('  on the scale rather than a ceiling on what a stopping rule could remove.\n')

    print(f'sensitivity at the design point (reduction {REDUCTION}, margin {MARGIN})')
    print(f'{"sd multiplier":>14s}{"primary sd":>12s}{"control sd":>12s}{"n per arm":>11s}')
    for f in (0.70, 0.85, 1.00, 1.15, 1.30):
        a, b = n_paired(SD_PRIMARY * f, REDUCTION), n_paired(SD_CONTROL * f, MARGIN)
        mark = '  <- point estimate' if f == 1.00 else ''
        print(f'{f:>14.2f}{SD_PRIMARY * f:>12.2f}{SD_CONTROL * f:>12.2f}'
              f'{max(a, b):>11d}{mark}')

    n = max(n_paired(SD_PRIMARY, REDUCTION), n_paired(SD_CONTROL, MARGIN))
    print(f'\ndesign point: n = {n} per arm. Agents = seed inventory 9 + reviews '
          f'{n} x 9 + analysis 13\n            = {9 + n * 9 + 13}, roughly '
          f'{(9 + n * 9 + 13) * 0.072:.1f}M tokens at 72k per agent.')
    print('\nIf window 1 of a split run shows either sd above 1.15x its borrowed value,')
    print('window 2 is re-sized from the observed variance BEFORE it runs. That check')
    print('reads the variance only; the effect estimate is not looked at until both')
    print('windows are complete.')


if __name__ == '__main__':
    main()
