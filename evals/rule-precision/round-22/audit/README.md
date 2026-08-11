# Variance audit — which components carried the primary's sd increase?

Descriptive only. **No cause is established, no test is run, and nothing here
may be used to justify a hypothesis, an n, or a gate for a later round.**

Inputs pinned at `fa7658ca032b727df3584410530d21f45a4e5802`:

```
8c9eb4ee8f509feeb49e716728549d3a23d59e96  round-22/findings.tsv
eb4d0a44bf876bc17b5ff7fe54f6d8239dd3d3f6  round-22/clusters.tsv
1e39c259e7482e55005e6f223c84b18f2089dce9  round-22/adjudications/panel-1.tsv
3b4e1688e76d3c17c9f31dd25c1c3ae3110d813b  round-22/adjudications/panel-2.tsv
2e849dfbde68f2b0f8d916c79e1093707db5762c  round-22/adjudications/panel-3.tsv
5a7b7932a689de5232fd4a14310b7c8660ded3b3  round-22/measure.py
fa8893093a63b8c5285e15196523cf0ccca14c6d  round-22/combined.py
cefac6eb91b247de7632ac5f658a7388364e1bc1  round-21/findings.tsv
6166c25dbcc1a21bd4ab5248c24533e54fef691b  round-21/clusters.tsv
78dd1877c07286f0c1f569cac6c067efbd986513  round-21/adjudications/panel-1.tsv
6e276875bc66d61971e25c95d9645cf64f33f83e  round-21/adjudications/panel-2.tsv
0d62f2ef089429fe57019cd9cf33124a3f7bcff4  round-21/adjudications/panel-3.tsv
```

Every one of these twelve blobs was **re-verified against the merged tree at
`a0b34e1a9ec98eab9e5c65c4f9b8aed0235acd7e`** before this was written; all twelve
match, so the round-22 README correction that landed in between changed no audit
input and no number here was recomputed.

Reproduce with `variance-audit.py`; its section 0 prints the sd intervals below.

## The first thing the audit found is about the question, not the answer

Round 22's write-up first said "the variance did not transfer", and three other
phrasings carried the same reading. Putting sampling intervals on the two sd
estimates shows all four were stronger than the data:

| | n | sd | 95% CI (χ², normal theory, Wilson–Hilferty quantile) |
|---|---|---|---|
| round 21 W | 9 | 1.453 | **[0.98, 2.80]** |
| round 21 W₂₃ | 9 | 1.394 | [0.94, 2.69] |
| round 22 W | 25 | 1.895 | [1.48, 2.64] |
| round 22 W₂₃ | 25 | 1.590 | [1.24, 2.21] |

**Round 22's sds sit inside round 21's intervals — both of them.** Round 21 never
excluded what round 22 measured; its nine reviews simply could not pin the sd to
better than a factor of about three. The design assumption of ≈1.42 falls just
outside round 22's W interval [1.48, 2.64] and inside its W₂₃ interval.

The accurate statement is narrower: *the observed spread was larger than the
point values used for sizing, and for W the sizing value now sits outside the
interval.* **The two rounds' variances are not shown to differ.** Round 22's
README was corrected on this point before it merged, and this audit is the
record of why.

The design error was not that variance moved — it was **sizing a 13.7M-token
round on a variance estimate whose own interval spanned 0.98 to 2.80 without
carrying that uncertainty into the n.**

## Where the growth sits, if it is growth

Both decompositions below are exact partitions of the same variance, not
competing explanations.

### By reviewer part — the arms differ in kind, not just degree

A review is the sum of its three parts, so
`var(review) = Σ var(part) + 2 Σ cov(part_i, part_j)`.

| | Σ var(parts) | 2 Σ cov | var(review) |
|---|---|---|---|
| round 21 W | 2.278 | **−0.167** | 2.111 |
| round 22 W | 2.570 | **+1.020** | 3.590 |
| round 21 W₂₃ | 1.750 | +0.194 | 1.944 |
| round 22 W₂₃ | 2.530 | −0.003 | 2.527 |

**W's increase is almost entirely the covariance term**: individual reviewers'
variance rose 2.278 → 2.570 (+0.29) while the between-reviewer covariance swung
−0.167 → +1.020 (+1.19), about 80% of W's +1.48 total. **W₂₃'s smaller increase is
the opposite** — all in individual part variance, with its covariance flat.

In W's round 22, the three reviewers of a given index moved together. In round 21
they did not, and in W₂₃ they did not in either round.

### How much of that is the execution window?

Review index is launch order; the five-hour window reset between index 15 and 16.
Anything shared by the three parts of one index appears as covariance between
them, and a level shift between windows is such a thing.

| | raw | window-centred |
|---|---|---|
| W sd(review) | 1.895 | **1.786** |
| W 2 Σ cov | +1.020 | **+0.775** |
| W₂₃ sd(review) | 1.590 | 1.586 |

W's means were 3.93 (indices 1–15) and 5.20 (16–25); W₂₃'s were 5.20 and 5.00.
Removing the window strata's means accounts for roughly a quarter of W's
covariance and takes its sd from 1.895 to 1.786. **Most of the covariance survives
centring, and what it is shared with is not described here.** Nothing was
randomised against execution order, so this stratification partitions; it does
not explain.

### By reason component

| W | var(primary) | preference | scope | outside-diff |
|---|---|---|---|---|
| round 21 | 2.111 | 1.944 | 0.250 | 1.000 |
| round 22 | 3.590 | **2.907** | 0.490 | **0.340** |

`preference` carries most of W's marginal growth (+0.96 of +1.48). Its
`outside-diff` variance *fell*. W₂₃: preference 2.000 → 1.860, scope 0.361 → 0.707,
outside-diff 0.750 → 0.873.

### Review length, new claims, single reviews

- **Length is not it.** Findings per review: sd 3.1–3.7 in every arm and round.
  What grew in W is the *rate* — primary per finding, sd 0.0208 → 0.0295.
  `corr(findings, primary)` fell in both arms (W 0.71 → 0.58, W₂₃ 0.59 → 0.45).
- **New claims are not it.** Their per-review variance is 0.19 (W) and 0.22 (W₂₃)
  against totals of 3.59 and 2.53. The carried-over claims carry the spread.
- **Single reviews move these numbers a lot.** Dropping W's index 23 (value 9)
  takes its sd 1.895 → 1.675; dropping W₂₃'s index 21 (value 1) takes 1.590 → 1.367.
  At n=25 the sd is still a soft quantity, which is the same lesson as the
  intervals above.

## What this changes, and what it does not

It does not change round 22's outcome. The gate compared an observed MDE with a
pre-registered ceiling and fired; that is a fact about the numbers, not about
their interpretation.

What it changes is what a next round should take from round 22. **Round 22's own
sd is a second imprecise estimate, not a firm one** — its W interval is [1.48,
2.64], wide enough that plugging its point estimate into a power calculation
would repeat round 22's mistake one level down. Any n chosen from a point estimate
of this variance is a bet that the point estimate is right, and **round 22 shows
that this plug-in bet can fail** — one round, not a pattern across two.

Whether the next design should carry variance uncertainty explicitly, target a
metric with a tighter component, or change the review structure that produced W's
between-reviewer covariance, is a design question this audit does not answer and
must not be read as answering.
