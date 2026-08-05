# Rule firing frequency

`evals/rule-ablation/` asks whether a rule *changes* a review — expensive, one
mechanism at a time, two authored fixtures per question. This asks the cheaper
question that should come first: **does the rule ever fire at all?**

It needs no fixtures and no agents. It reads the review artifacts that sibling
repositories already accumulated and counts, per rule, how often it was cited
in a finding versus how often it was merely listed as checked.

```bash
evals/rule-firing/measure.py                 # table, dead-rule list
evals/rule-firing/measure.py --tsv           # machine-readable
evals/rule-firing/measure.py --json out.json # raw counts
```

## What the two counts mean

| | |
|---|---|
| **checked** | reviews citing the rule anywhere — usually the Recurring Issue Check line, `R10: N/A` |
| **findings** | reviews citing it inside a finding block (a heading carrying a severity tag) |

The gap between them is the measurement. A rule can be routed to, considered,
and answered "not applicable" hundreds of times without ever having produced a
defect — and that costs routing attention on every review with nothing recorded
in return.

Opportunities are age-corrected against the rule's first appearance in
`common-rules.md`: a rule added last week cannot have fired in a review written
last month, so a young rule's zero means nothing. `--mature` (default 200) sets
how many opportunities a zero needs before it counts as evidence.

## What it cannot tell you

- **Prophylaxis is invisible.** Rules are read during implementation as well as
  review; a rule that stops the defect being written shows zero findings and
  looks identical to a dead one. Nothing here distinguishes them.
- **Demotion is self-fulfilling.** A rule removed from the routing index can
  never fire again, so acting on this measurement forecloses re-measuring it.
  That is the reason the 2026-08-05 result records deletion *candidates* and
  stops there.
- **The corpus is one person's repositories** — TypeScript/Next.js web apps,
  a Swift client, shell tooling. A rule dead here may be live elsewhere.
- **Citation is the proxy for firing.** A reviewer who fixes a defect without
  naming the rule ID is invisible to this. The `checked` counts (up to 628 of
  1026 opportunities) show the citation convention is followed closely enough
  to trust, but it is a convention, not an instrument.

## Result

`docs/archive/audit/2026-08-05-rule-firing.md`.
