# What each number is for

Rounds 12 through 19 used one quantity — the MDE — for two jobs, and the two
jobs disagree. This separates them. Every protocol from round 20 on states which
of these three it is using and where.

## 1. Before the run: the MDE is a design quantity

The minimum detectable effect,

    MDE = (t_crit + z_beta) * sd * sqrt(2/n)      (unpaired)
    MDE = (t_crit + z_beta) * sd_d / sqrt(n)      (paired)

answers **"is this n big enough to be worth running?"** It is computed from an
sd borrowed from earlier data, before anything is observed, and it gates the
spend: if the MDE exceeds the effect the round is sized for, the round is
underpowered and should be resized or abandoned.

That is its whole job. It is a property of the *design*.

## 2. After the run: the test and the interval

Whether the round observed an effect is answered by the test and the confidence
interval, computed on the observed data:

    t = mean(d) / (sd_d / sqrt(n)),  compared against t_crit at df = n-1
    CI = mean(d) +/- t_crit * sd_d / sqrt(n)

**An observed effect does not have to exceed the MDE to be significant.** The
MDE is the effect detectable with 80% power; significance needs only
`|t| > t_crit`, which is a lower bar. Requiring the observed difference to clear
the MDE is a stricter test than α=.05, applied by accident.

Round 19 is the worked example. Its primary was −2.00 with a 95% CI of
**[−3.76, −0.24]**, which excludes zero, and t=−2.93 against t_crit 2.571. Its
pre-registered rule required the difference to exceed an MDE of 2.33, so the
round recorded no confirmatory claim. Both statements are true and they are
about different things. The pre-registration was followed; it was also asking
the wrong question.

## 3. If a size actually matters: pre-register a SESOI

"Significant" and "big enough to act on" are different claims. When a round
needs the second, it pre-registers a **smallest effect size of interest** — a
number chosen from what the change is for, not from the variance of a previous
batch — and the decision rule reads the confidence interval against it:

- the whole CI beyond the SESOI: the effect is at least worth acting on
- the whole CI inside (−SESOI, +SESOI): the effect is smaller than matters
- the CI straddling it: inconclusive at this n

A SESOI is never an MDE. The MDE moves when the variance moves; the SESOI is
fixed by what the intervention is supposed to buy. Round 19's secondary
threshold was an MDE computed from a borrowed sd, pressed into service as a
substantive bar, and it stopped meaning what it meant the moment the observed sd
came in at a third of the borrowed one.

## 4. Confirmatory and exploratory are labels, not grades

A comparison is **confirmatory** only if its decision rule was fixed before the
data existed and is applied as written. Everything else is **exploratory**, and
exploratory results are reported with their numbers and named as exploratory —
not discounted, and not promoted afterwards by replacing the threshold they
missed with one they clear.

Round 19's secondary is the case to keep in mind. W − W₂ came out −1.83, 95% CI
[−2.62, −1.04], t=−5.97: strong evidence, and its pre-registered threshold said
it meant nothing because that threshold had been computed from a variance twice
the observed one. The honest record is **exploratory, strong** — not
confirmatory, because the rule that would have made it confirmatory was wrong
before the round started and cannot be rewritten afterwards.

## The template a protocol should follow

> **Power (before the run).** sd borrowed from `<source>`; at n=`<n>` the MDE is
> `<x>`; the round is sized for an effect of `<y>`. Gate: if the observed MDE
> exceeds `<y>`, report underpowered and do not extend n.
>
> **Inference (after the run).** Paired t and 95% CI on the per-review
> difference. The confirmatory claim is `<one comparison>`; its rule is
> `<CI excludes zero | CI beyond SESOI = z>`.
>
> **Everything else is exploratory**, reported with numbers and labelled.
