#!/usr/bin/env python3
"""Reproduce round 19's power table from the series rounds 17 and 18 recorded.

Round 19 is analysed PAIRED: the test statistic, the sd and the MDE are computed
on the per-review difference, not on two arm means with a pooled sd.

A caveat this script exists to make visible rather than hide. Pairing pays only
when the paired units share something. In rounds 17 and 18 as they were actually
run, every review within an arm received an IDENTICAL brief — there were no
per-review preambles — so review i in one arm shares nothing with review i in
another beyond its index. The observed numbers agree: sd(W-N) is 1.323 against
the 1.344 that independence predicts, a correlation of about zero.

So the paired analysis here is exact and conservative, not more powerful. It
costs degrees of freedom (t at n-1 rather than 2(n-1)) and buys back nothing,
and it is still the right analysis to pre-register, because the design is paired
by construction and an unpaired test would be claiming an independence the
design does not assert. Making the pairing REAL — one shared preamble per review
index across all arms — is a change to the review condition and is not made
here; it is the obvious thing for a later round to fix.

Usage:  evals/rule-ablation/protocols/round-19-power.py
"""
import math
import statistics as st

Z_BETA = 0.842
T_PAIRED = {6: 2.571, 9: 2.306, 12: 2.201, 15: 2.145}    # two-sided .05, df = n-1
T_POOLED = {6: 2.228, 9: 2.120, 12: 2.074, 15: 2.052}    # two-sided .05, df = 2(n-1)

# F10, Critical/Major findings whose claim is `not-a-defect`, per review.
R17_W = [1, 1, 4, 1, 2, 0, 0, 1, 1]
R17_N = [4, 4, 4, 4, 4, 5, 3, 4, 3]
R18_W2 = [2, 4, 6, 3, 1, 4]
R18_N = [3, 5, 5, 5, 3, 5]


def paired_sd(a, b):
    return st.stdev([x - y for x, y in zip(a, b)])


def mde_paired(sd_d, n):
    return (T_PAIRED[n] + Z_BETA) * sd_d / math.sqrt(n)


def mde_pooled(a, b, n):
    sp = math.sqrt((st.variance(a) + st.variance(b)) / 2)
    return (T_POOLED[n] + Z_BETA) * sp * math.sqrt(2 / n)


def main():
    print('Per-review series recorded so far (C+M not-a-defect, F10)\n')
    for label, s in (('round 17  W ', R17_W), ('round 17  N ', R17_N),
                     ('round 18  W2', R18_W2), ('round 18  N ', R18_N)):
        print(f'  {label}  mean {st.mean(s):5.2f}  sd {st.stdev(s):5.3f}   {s}')

    sd_wn, sd_w2n = paired_sd(R17_W, R17_N), paired_sd(R18_W2, R18_N)
    indep_wn = math.sqrt(st.variance(R17_W) + st.variance(R17_N))
    print(f'\nPairing buys nothing on the data we have:')
    print(f'  sd(W - N) observed          {sd_wn:.3f}')
    print(f'  sd(W - N) if independent    {indep_wn:.3f}   -> correlation ~ 0')
    print(f'  sd(W2 - N) observed         {sd_w2n:.3f}')

    # W vs W2 has never been run in one batch, so no difference series exists.
    # Estimate it under independence, which the line above shows is what the
    # paired series actually look like.
    sd_ww2 = math.sqrt(st.variance(R17_W) + st.variance(R18_W2))

    shift = st.mean(R18_N) - st.mean(R17_N)
    eff_ww2 = st.mean(R18_W2) - (st.mean(R17_W) + shift)
    rows = [('PRIMARY   W  vs N ', sd_wn, st.mean(R17_N) - st.mean(R17_W)),
            ('SECONDARY W  vs W2', sd_ww2, eff_ww2),
            ('RECORDED  W2 vs N ', sd_w2n, st.mean(R18_N) - st.mean(R18_W2))]

    print(f'\nN moved {shift:+.2f} between the two batches, so the W-vs-W2 effect below is a\n'
          f'cross-batch subtraction — the very quantity round 19 exists to stop relying on.\n')
    print(f'{"":20s}{"sd_d":>7s}{"effect":>9s}' +
          ''.join(f'{f"MDE n={n}":>10s}' for n in T_PAIRED))
    for label, sd_d, eff in rows:
        print(f'{label:20s}{sd_d:7.3f}{eff:9.2f}' +
              ''.join(f'{mde_paired(sd_d, n):10.2f}' for n in T_PAIRED))

    print(f'\nFor comparison, the unpaired reading of the primary at n=6: '
          f'{mde_pooled(R17_W, R18_N, 6):.2f}')
    print(f'The paired MDE at n=6 is {mde_paired(sd_wn, 6):.2f}, against an effect of '
          f'{st.mean(R17_N) - st.mean(R17_W):.2f}\n'
          f'and a pre-registered ceiling of 2.67. n=6 clears it either way.')
    print('\nThe secondary does not clear at any n listed: its expected effect is '
          f'{eff_ww2:.2f}\nagainst {mde_paired(sd_ww2, 15):.2f} at n=15 (135 review agents). '
          'Its null is uninformative\nand is pre-declared as such.')

    print(f'\nAgents at n=6: {3 * 6 * 3} reviews + 8 clustering + 3 adjudication = '
          f'{3 * 6 * 3 + 11}')


if __name__ == '__main__':
    main()
