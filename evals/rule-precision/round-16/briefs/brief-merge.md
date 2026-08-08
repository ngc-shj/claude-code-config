# Merge brief

You are grouping enumerated defects from five independent panellists into
distinct CLAIMS. You are NOT judging whether any claim is true — a later
independent panel does that, and a verdict from you would contaminate it.

## Materials

- The enumerations: `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/e392c887-68cf-492b-a61c-d5d0f9838aa9/scratchpad/r16/all.tsv`
  One row per enumerated defect, tab-separated, columns `id`, `panellist`,
  `severity`, `file`, `title`, `what_is_wrong`. Five panellists, `A` through `E`,
  each of whom read the change independently and did not see the others' output.
- The change all these entries concern:
  `/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F10-webhooks.diff`
  Read it for reference, so you can tell whether two differently-worded entries
  are about the same code and the same problem.

Read nothing else in that repository.

## The clustering rule

Two entries belong to the SAME cluster only if a single change would resolve
both, AND they assert the same thing about the same code.

- Same code, different assertion → DIFFERENT clusters. (One saying a set is
  missing an entry, another saying the same set should not exist, are two claims.)
- Same assertion, different wording, different severity → same cluster.
- An entry that bundles two separable problems goes in the cluster of its
  PRIMARY assertion — the one its `what_is_wrong` leads with. Do not split ids.
- Every id must appear in exactly one cluster. None may be dropped.
- Two entries from the SAME panellist may land in the same cluster; if they do,
  that panellist still counts once in `panellists`.

## Output

Write a tab-separated file with a header row and one row per cluster to the path
given in your instructions:

```
cluster_id	panellists	n	member_ids	claim
SIGN-01	4	5	A03,B07,C02,C09,E01	<one sentence stating the claim neutrally>
```

- `cluster_id` is a short uppercase prefix naming the area of the change the
  claim concerns — derive the prefixes from the files in the diff, one prefix per
  file, and number from 01 within each prefix. List the clusters ordered by
  descending `panellists`, then descending `n`.
- `panellists` is the number of DISTINCT panellist letters among the members.
- `n` is the number of member ids and must equal the count in `member_ids`.
- `claim` is one sentence, stated as an assertion about the code, in neutral
  words — not "the panellist says". Concrete enough that someone reading the diff
  can decide whether it is true. Do not soften, strengthen, or merge the claim
  with your own opinion of it.

Before writing, check: the `n` values sum to the number of input rows, and every
input id appears exactly once.

Your reply after writing the file is the single word DONE.
