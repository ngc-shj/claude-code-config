# Clustering brief

You are grouping review findings into distinct CLAIMS. You are not judging
whether any of them is true, and you must not try to: a verdict from you would
contaminate the panel that judges them later.

## Inputs

- `<INPUT>` — the findings to cluster. Columns: id, severity, file, title,
  what_is_wrong. Nothing in these columns says which review or which arm wrote
  a finding, and the id ordering carries no such signal either. Do not attempt
  to infer it.
- `<CLAIMS>` — the 114 claims already recorded for this fixture by earlier
  rounds, as `cluster_id<TAB>claim`.

## The rule for grouping

Two findings belong to the same claim when **both** hold:

1. A single change to the code resolves both, and
2. they assert the same thing about the same code.

Same file is not enough. Same general topic is not enough. "Missing tests for
X" and "missing tests for Y" are two claims. A finding that asserts a stronger
version of another finding's point is the same claim only if one change closes
both.

## Existing claims are reused VERBATIM

If a finding matches an existing claim, put it in that cluster and **copy the
claim text through byte-for-byte**. Do not improve it, shorten it, correct its
grammar, or make it fit your finding better. A reworded claim is a DIFFERENT
claim, and the verdict already recorded against the original stops applying to
it. This is checked mechanically afterwards and a reworded claim is a defect in
your output.

Only when no existing claim matches do you write a new one. Give it an id of
the form `R20-NN` (NN starting at 01, unique within your file) and write the
claim as one sentence, in the same voice as the existing ones: what is asserted
about which code, specific enough that someone reading only the claim and the
diff could judge it.

## Output

Write TSV to the output path given in your instructions, with this header:

```
cluster_id	status	n	member_ids	claim
```

- `status` is `existing` if `cluster_id` came from `<CLAIMS>`, `new` otherwise.
- `n` is the number of member ids.
- `member_ids` is a comma-separated list, no spaces.
- `claim` is the one-sentence claim.

**Every finding id in the input appears in exactly one cluster. None is
dropped.** Check that before you write: the sum of `n` must equal the number of
input rows, and the union of member ids must equal the input's id set.

After writing the file, run `wc -l` on it and reply with `DONE <n>` where <n> is
that count. Do not reply before the file exists.
