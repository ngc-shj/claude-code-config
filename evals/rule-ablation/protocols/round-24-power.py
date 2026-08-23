#!/usr/bin/env python3
"""Size round 24 from round 17's own per-arm variance on the metric round 24 tests.

Round 17 borrowed round 12's pooled sd, measured on F9, and F9's sd did not
transfer (`../../rule-precision/round-17/README.md`). The plug-in here is F10's
own — the fixture round 24 re-runs — on the `not-a-defect` metric, which is
round 24's primary and which round 17 reported only as a post-hoc split.

The MDE below does ONE job: choosing n before the round runs
(`../../rule-precision/methods.md`, quantity 1). Round 24 registers no
observed-MDE gate, so nothing here is a bar the observed difference must clear,
and none of these numbers reappear after the data exists.

Usage:  evals/rule-ablation/protocols/round-24-power.py
"""
import math

Z_BETA = 0.842
ALPHA = 0.05

# Round 17, F10, per review: Critical/Major findings whose claim is adjudicated
# `not-a-defect`. Re-derivable from the frozen material the protocol pins —
# round-17/findings.tsv, round-17/clusters.tsv, round-16/seed/inventory.tsv and
# round-17/adjudications/*.tsv — by filtering verdict == 'not-a-defect'.
R17 = {'W': [1, 1, 4, 1, 2, 0, 0, 1, 1],
       'N': [4, 4, 4, 4, 4, 5, 3, 4, 3]}

# The same reviews under round 17's own pre-registered primary — the composite,
# which pools `not-a-defect` with `wrong`. Round 24 carries it as an exploratory
# secondary; this is why it is not the primary.
R17_COMPOSITE = {'W': [2, 1, 7, 3, 2, 0, 2, 2, 3],
                 'N': [5, 5, 5, 5, 4, 5, 4, 5, 3]}

EFFECT = 2.67          # round 17's observed difference on this metric
EFFECT_COMPOSITE = 2.11
INFLATIONS = (1.0, 1.25, 1.5, 1.75, 2.0, 2.5)
NS = (9, 12, 15, 20)


def var(xs):
    m = sum(xs) / len(xs)
    return sum((x - m) ** 2 for x in xs) / (len(xs) - 1)


def welch(v_a, v_b, n):
    """Standard error and Satterthwaite df for W - N at n per arm."""
    se2 = v_a / n + v_b / n
    df = se2 ** 2 / ((v_a / n) ** 2 / (n - 1) + (v_b / n) ** 2 / (n - 1))
    return math.sqrt(se2), df


def t_crit(df):
    """Two-sided .05 critical value; Cornish-Fisher expansion, ample here."""
    z = 1.959964
    return z + (z ** 3 + z) / (4 * df) + (5 * z ** 5 + 16 * z ** 3 + 3 * z) / (96 * df ** 2)


def phi(x):
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def power(delta, se, df, steps=4000):
    """P(reject) for a two-sided t at true difference `delta`.

    Noncentral t by numerical integration over S = sqrt(chi2_df/df): the
    statistic is (Z + ncp)/S, so power conditions on S and averages. Exact up to
    quadrature error; scipy is not a dependency of this repository.
    """
    ncp, tc = delta / se, t_crit(df)
    k = df / 2
    log_norm = k * math.log(df / 2) - math.lgamma(k)
    lo, hi = 1e-6, 1 + 12 / math.sqrt(df)
    h = (hi - lo) / steps
    total = 0.0
    for i in range(steps + 1):
        s = lo + i * h
        # density of S, from chi2 by the change of variable x = df * s^2
        log_f = log_norm + (2 * k - 1) * math.log(s) - df * s * s / 2 + math.log(2)
        cond = (1 - phi(tc * s - ncp)) + phi(-tc * s - ncp)
        w = 1 if i in (0, steps) else (4 if i % 2 else 2)
        total += w * math.exp(log_f) * cond
    return total * h / 3


def main():
    v_w, v_n = var(R17['W']), var(R17['N'])
    print(f'Round 17, F10, `not-a-defect` per review — the plug-in\n')
    print(f'  W  sd {math.sqrt(v_w):.3f}   N  sd {math.sqrt(v_n):.3f}   '
          f'pooled sd {math.sqrt((v_w + v_n) / 2):.3f}   observed difference {EFFECT}')
    se9, df9 = welch(v_w, v_n, 9)
    print(f'  Welch se at n=9 {se9:.3f}, df {df9:.1f}\n')
    print('Both arm sds are estimated from nine reviews, so they are imprecise in\n'
          'their own right. The table inflates BOTH by the same factor and reports\n'
          'power against round 17\'s observed effect, which is the quantity that\n'
          'decides whether the round is worth running.\n')

    head = ''.join(f'{f"x{lam:g}":>9s}' for lam in INFLATIONS)
    print(f'{"":6s}{"":11s}power at true difference {EFFECT}')
    print(f'{"n/arm":6s}{"MDE x1.5":>11s}{head}')
    for n in NS:
        se, df = welch(v_w, v_n, n)
        mde15 = (t_crit(df) + Z_BETA) * se * 1.5
        row = ''.join(f'{power(EFFECT, se * lam, df) * 100:8.0f}%' for lam in INFLATIONS)
        mark = '  <- chosen' if n == 12 else ''
        print(f'{n:<6d}{mde15:11.2f}{row}{mark}')

    print('\nRead the columns, not the MDE. n=12 holds 99% power if both arm sds come\n'
          'in half again as large as round 17 measured them, and 90% at double.\n'
          'n=9 repeats round 17\'s n and would be defensible on these numbers; n=12\n'
          'buys margin against the one thing round 22 proved can happen — a plug-in\n'
          'variance the fresh batch does not honour — for a third more agents.')

    cv_w, cv_n = var(R17_COMPOSITE['W']), var(R17_COMPOSITE['N'])
    print(f'\n\nWhy the composite is the SECONDARY and not the primary\n')
    print(f'  W  sd {math.sqrt(cv_w):.3f}   N  sd {math.sqrt(cv_n):.3f}   '
          f'pooled sd {math.sqrt((cv_w + cv_n) / 2):.3f}   '
          f'observed difference {EFFECT_COMPOSITE}\n')
    print(f'{"n/arm":6s}{"agents":>8s}{head}')
    for n in (12, 15, 20, 25):
        se, df = welch(cv_w, cv_n, n)
        row = ''.join(f'{power(EFFECT_COMPOSITE, se * lam, df) * 100:8.0f}%'
                      for lam in INFLATIONS)
        print(f'{n:<6d}{n * 6:>8d}{row}')
    print('\nSmaller effect, larger variance: the composite needs n=25 — twice the\n'
          'review agents — to reach the margin the primary reaches at n=12.')


if __name__ == '__main__':
    main()
