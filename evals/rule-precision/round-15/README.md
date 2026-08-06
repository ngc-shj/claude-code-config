# Round 15 — is a titles-only base as good as the full one?

Pre-registration: `../../rule-ablation/protocols/round-15.md`, including two
deviations: the batch was halted at **six of eight** reviews against a budget
ceiling, and a substitution of the clusterer was considered and rejected.

```bash
evals/rule-precision/round-15/measure.py
```

Three arms on the same fixed base — round 13's first three reviewers per review:
**T** gets the base's finding titles only, **C** gets the full base as round 14
gave it, **I** gets nothing.

| | T (titles) | C (full) | I (blind) |
|---|---|---|---|
| real defects added | **7.83** | 7.83 | 4.50 |
| Critical/Major non-defects | 3.33 | 3.50 | 2.67 |
| restating the base | 0.17 | 0.17 | 30.00 |
| findings written | 17.83 | 20.17 | 38.00 |

**T and C are identical to two decimals** on everything that matters. A title is
enough to recognise your own finding by; the file, severity and explanation add
nothing measurable.

The pre-registered rule fires for T — and it fires on ground weaker than it
looks, because **round 14's cost penalty did not replicate here** (C over I was
2.12 there against an MDE of 2.05; it is 0.83 here). The skill is not changed on
that. Full reasoning: `docs/archive/audit/2026-08-06-titles-only-conditioning.md`.

`base/` holds the titles-only stimulus. C's full-text stimulus is round 14's.
