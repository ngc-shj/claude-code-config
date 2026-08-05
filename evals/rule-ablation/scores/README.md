# Scored data

Three agents scored each anonymised, shuffled submission set against a fixed
rubric; the audit doc's tables are majority votes over these sheets. The
submissions themselves were not kept — see `../protocols/README.md`.

```bash
../score.py --round 8      # re-derive round 8's published table
../score.py --round 7-F1   # ... and every other: 6.5, 7-F1, 7-F3, 8, 9, 10, 11
```

Each mapping is `sid → fixture, arm, preamble`; each scorer sheet is one line
per submission. The subsets `score.py` prints as `subset` and `control` are the
ones named in `../protocols/`, not chosen after the fact.
