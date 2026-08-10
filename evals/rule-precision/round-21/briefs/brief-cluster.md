# Clustering brief

You are grouping review findings into distinct CLAIMS. You are not judging
whether any of them is true, and you must not try to: a verdict from you would
contaminate the panel that judges them later.

## Inputs

- The findings to cluster: the input TSV path given in your instructions.
  Columns: id, severity, file, title, what_is_wrong. Nothing in these columns
  says which review or which reviewing catalogue wrote a finding, and the id
  ordering carries no such signal either. Do not attempt to infer it.
- The change these findings are about:
  `/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F11-exports.diff`
  Read it first, so that you can tell whether two findings are about the same
  code. Read nothing else in that repository.

There is no pre-existing claim list for this change. Every claim you write is a
new one.

## The rule for grouping

Two findings belong to the same claim when **both** hold:

1. A single change to the code resolves both, and
2. they assert the same thing about the same code.

Same file is not enough. Same general topic is not enough. "Missing tests for
X" and "missing tests for Y" are two claims. A finding that asserts a stronger
version of another finding's point is the same claim only if one change closes
both.

## Writing a claim

Give each claim an id of the form `<PREFIX>-NN`, where `<PREFIX>` is the prefix
given in your instructions and NN starts at 01. Write the claim as one
sentence: what is asserted about which code, specific enough that someone
reading only the claim and the diff could judge it. Do not state or imply how
many findings are in the cluster, and do not hedge a claim because few findings
made it — the panel is given the claims without their member counts, on
purpose.

## Output

Write TSV to the output path given in your instructions, with this header:

```
cluster_id	status	n	member_ids	claim
```

- `status` is always `new` for this change.
- `n` is the number of member ids.
- `member_ids` is a comma-separated list, no spaces.
- `claim` is the one-sentence claim.

**Every finding id in the input appears in exactly one cluster. None is
dropped.** Check that before you write: the sum of `n` must equal the number of
input rows, and the union of member ids must equal the input's id set.

After writing the file, run `wc -l` on it and reply with `DONE <n>` where <n> is
that count. Do not reply before the file exists.
