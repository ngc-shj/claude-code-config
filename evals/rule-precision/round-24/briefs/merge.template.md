# Merge brief — deduplicating newly written claims

{N_CLUSTER_AGENTS} agents clustered this change's findings in parallel. Each was given the same
list of claims already recorded for it, and each wrote new claims only for
findings that matched none of them. Because they worked in parallel and could
not see each other, **two of them may have written separate new claims for the
same assertion.** Your job is to find those and say which collapse into which.

You are not judging whether any claim is true, and you must not try to.

## Inputs

- The new claims:
  `{NEW_CLAIMS}`
  as `cluster_id<TAB>n<TAB>claim`.
- The claims already recorded for this change:
  `{EXISTING_CLAIMS}`
  as `cluster_id<TAB>claim`.
- The change:
  `{DIFF}`
  Read it, so you can tell whether two claims are about the same code. Read
  nothing else in that repository.

## The rule

Two claims are the SAME claim when **both** hold:

1. A single change to the code resolves both, and
2. they assert the same thing about the same code.

Same file is not enough. Same general topic is not enough. Two claims that name
the same function but assert different defects in it are two claims.

A new claim may also turn out to duplicate an **existing** claim — one of the
clustering agents may have missed a match. Say so when it does.

## Output

Write TSV to the output path given in your instructions, with this header:

```
cluster_id	verdict	target	why
```

One row for **every** id in the new-claims file, in the order given.

- `verdict` is `keep` if the claim stands on its own, or `merge` if it is the
  same claim as another.
- `target` is empty for `keep`. For `merge`, it is the id this claim collapses
  INTO — either another new id or an existing id. When two new claims are the
  same, keep the alphabetically first id and merge the other into it. Never
  merge an existing claim into a new one: existing ids always win.
- `why` is one sentence.

A `merge` chain must not be circular, and a `merge` target must itself be a
`keep` row or an existing id.

After writing the file, run `wc -l` on it and reply with `DONE <n>` where <n> is
that count. Do not reply before the file exists.
