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
  naming the rule ID is invisible to this. The `checked` counts (up to 568 of
  1026 opportunities) show the citation convention is followed closely enough
  to trust, but it is a convention, not an instrument.

## Changing the ID pattern

Both guards in `RULE_ID` were paid for in false positives, and both times the
wrong reading survived because it was checked against an invented example. The
corpus writes `NF-R2` for a requirement, `R1-R35` for a span, and `R2-F1` for
round 2's first finding — none of which is a citation, and the last of which
looks exactly like one.

So: before changing that pattern, sample what the corpus actually puts around
the token.

```bash
grep -rhoE '.{20}\bR2\b.{20}' ../../../*/docs/archive/review/*-review.md | shuf -n 20
```

The dead-rule list is the one output safe from this class of error in either
direction — a false positive can only *add* a finding, so a rule at zero stays
at zero. Both corrections left it intact; the second grew it by one.

## Panel audits pointed by this measurement

`sketches/` holds defect sketches derived from real findings in the corpus, and
`rubrics/` the merged panel rubrics built from them — the round-5/6 method
aimed where the firing data says the catalogue actually earns its keep, rather
than alphabetically.

A sketch is much cheaper than an ablation fixture: the panel does no detection,
so the code needs no burial and no competing defects, only the defect itself in
its real shape. Twenty to forty lines is enough.

## Results

- `docs/archive/audit/2026-08-05-rule-firing.md` — the firing measurement.
- `docs/archive/audit/2026-08-05-panel-audit-oneliners.md` — RT1 and R1
  audited against it: 30 and 29 majority properties against one-sentence rules,
  and both panels finding the rule names the symptom rather than the hazard.
