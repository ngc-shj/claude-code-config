# Clustering brief

You are grouping review findings into distinct CLAIMS. You are not judging
whether any of them is true, and you must not try to: a verdict from you would
contaminate the panel that judges them later.

## Inputs

- The findings to cluster: the input TSV path given in your instructions.
  Columns: id, severity, file, title, what_is_wrong. Nothing in these columns
  says which review or which reviewing catalogue wrote a finding, and the id
  ordering carries no such signal either. Do not attempt to infer it.
- The claims already recorded for this change:
  `/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/15767388-c891-4ea8-b689-89f8506a0299/scratchpad/round-22/existing-claims.tsv`
  as `cluster_id<TAB>claim`. Read it in full before you start.
- The change these findings are about:
  `/home/noguchi/ghq/github.com/ngc-shj/claude-code-config/evals/rule-ablation/fixtures/F11-exports.diff`
  Read it first, so that you can tell whether two findings are about the same
  code. Read nothing else in that repository.

## The rule for grouping

Two findings belong to the same claim when **both** hold:

1. A single change to the code resolves both, and
2. they assert the same thing about the same code.

Same file is not enough. Same general topic is not enough. "Missing tests for
X" and "missing tests for Y" are two claims. A finding that asserts a stronger
version of another finding's point is the same claim only if one change closes
both.

## Existing claims are matched on meaning and copied VERBATIM

A finding belongs to an existing claim when it asserts the same thing about the
same code — **the wording does not have to match.** Match on meaning, not on
phrasing.

When you assign a finding to an existing claim, **copy that claim's id and its
claim text through byte-for-byte.** Do not improve it, shorten it, correct its
grammar, or make it fit your finding better. A reworded claim is a DIFFERENT
claim, and the verdict already recorded against the original stops applying to
it. This is checked mechanically afterwards and a reworded claim is a defect in
your output.

Only when no existing claim matches do you write a new one. Give it an id of
the form `<PREFIX>-NN`, where `<PREFIX>` is the prefix given in your
instructions and NN starts at 01. Write the claim as one sentence: what is
asserted about which code, specific enough that someone reading only the claim
and the diff could judge it. Do not state or imply how many findings are in the
cluster.

Expect most findings to match an existing claim. That is the normal outcome and
not a sign you are matching too eagerly — but a finding that genuinely asserts
something new must get a new claim rather than be forced into a near neighbour.

## Output

Write TSV to the output path given in your instructions, with this header:

```
cluster_id	status	n	member_ids	claim
```

- `status` is `existing` if `cluster_id` came from the existing-claims file,
  `new` otherwise.
- `n` is the number of member ids.
- `member_ids` is a comma-separated list, no spaces.
- `claim` is the one-sentence claim.

**Every finding id in the input appears in exactly one cluster. None is
dropped.** Check that before you write: the sum of `n` must equal the number of
input rows, and the union of member ids must equal the input's id set.

After writing the file, run `wc -l` on it and reply with `DONE <n>` where <n> is
that count. Do not reply before the file exists.
