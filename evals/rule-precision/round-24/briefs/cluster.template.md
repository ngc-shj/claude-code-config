# Clustering brief

You are grouping code-review findings into distinct CLAIMS, against an inventory
of claims that already exists. You are NOT judging whether any claim is true — a
later independent panel does that, and a verdict from you would contaminate it.

## Materials

- **Your group file** (path in your instructions): one row per finding,
  tab-separated, columns `id`, `severity`, `file`, `title`, `what_is_wrong`. The
  ids are opaque; they carry no information you need.
- **The existing inventory**: `{INVENTORY}`
  {N_CLAIMS} claims already recorded on this change, each with its `cluster_id` and one
  sentence stating it. **Read this in full before you cluster anything.** It
  covers the whole change, not only the files in your group — a finding about one
  file often restates a claim recorded against another.
- **The change**: `{FIXTURE}`
  Read it for reference, so you can tell whether two differently-worded findings
  are about the same code and the same problem.

Read nothing else in that repository.

## The clustering rule

Two findings belong to the SAME cluster only if a single change would resolve
both, AND they assert the same thing about the same code.

- Same code, different assertion → DIFFERENT clusters. (One saying a set is
  missing an entry, another saying the same set should not exist, are two claims.)
- Same assertion, different wording, different severity → same cluster.
- A finding that bundles two separable problems goes in the cluster of its
  PRIMARY assertion — the one its `what_is_wrong` leads with. Do not split ids.
- Every id must appear in exactly one cluster. None may be dropped.

## Existing claim, or new one

For each finding, first ask whether it asserts one of the {N_CLAIMS} existing claims.

- **It does** → assign it that `cluster_id`, unchanged. Same rule as above: the
  single change that resolves the finding also resolves the recorded claim, and
  they assert the same thing about the same code.
- **It does not** → it belongs to a new cluster. Number new clusters
  `<PREFIX>-01` upward using the prefix given in your instructions.

Being more specific than a recorded claim is not enough to be new. Being about
the same line for a different reason is.

## Output

Write a tab-separated file with a header row and one row per cluster, to the
path given in your instructions:

```
cluster_id	status	n	member_ids	claim
DELIVERY-03	existing	14	K0001,K0057,K0203	<the recorded claim, copied verbatim>
NEWDEL-01	new	3	K0091,K0140,K0388	<one sentence stating the claim neutrally>
```

- `status` is `existing` for one of the {N_CLAIMS}, `new` otherwise.
- For an `existing` cluster, `claim` is the inventory's sentence **copied
  verbatim**. Do not reword it — a reworded claim is a different claim, and its
  recorded verdict would no longer apply to it.
- For a `new` cluster, `claim` is one sentence, stated as an assertion about the
  code, in neutral words — not "the reviewer says". Concrete enough that someone
  reading the diff can decide whether it is true. Do not soften, strengthen, or
  merge it with your own opinion of it.
- `n` is the member count and must equal the number of ids listed.
- Emit a row only for clusters that have at least one member. Do not list
  existing claims your group's findings never assert.

Before writing, check: the member counts sum to the number of input rows, and
every input id appears exactly once.

Your reply after writing the file is the single word DONE.
