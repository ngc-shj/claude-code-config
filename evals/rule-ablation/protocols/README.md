# Pre-registration protocols

The audit doc claims, for rounds 7 through 9, that the arms, the metric split
and the predictions were written **before any output was read**. These are the
files that were written. They are checked in so the claim can be inspected
rather than taken on trust — a pre-registration you cannot produce is not one.

| | question | arms | pre-registered split |
|---|---|---|---|
| `round-7.md` | does the Remedy Floor work when wired? | W (wired) / N (absent) | floor-mapped vs mechanism, per fixture |
| `round-8.md` | does #125's R54 extension transmit? | E (extended) / O (pre-#125) | extension properties vs the original three |
| `round-9.md` | does the reworded obligation (c) transmit for the GUC variant? | Cnew / Cold | P5 vs the rest |
| `round-10.md` | does expert SPECIALISATION buy anything over REPETITION? | S (3 roles) / G (3 identical) | remedy rubric coverage; detection as control |
| `round-11.md` | ... and does that hold where the SECURITY expert should win? | S / G, on F9 | untaught properties vs material-taught ones |

`round-10.md` is the first round to vary the skill's STRUCTURE rather than its
catalogue. Both arms run three agents on the same fixture with the same
materials, so the comparison isolates specialisation from multiplicity —
"three experts vs one reviewer" would have measured the latter, which wins
trivially.

`round-11.md` carries two amendments, both written after the rubric was built
and before the first arm ran, and both recorded as amendments rather than
edited into the text they revise. It also documents a deviation from round 10's
plan: the fixture is the one round 10 named, but the instrument is not, because
F9's existing rubric turned out to be saturated under HEAD materials and a
ceiling cannot show a difference in either direction.

`round-7.md` also carries the probe result recorded before the ablation was
designed — four deployed-arm reviewers, zero reads of the Remedy Floor — which
is why round 7 compares W against N rather than the shipped configuration
against absence.

## Rounds 1–6 have no file here

Their protocol lives in `../README.md` and in the audit doc, written as the
rounds ran. Round 5's `../independent-rubric.md` and round 6's
`../panel-audit.md` are the closest equivalents and are checked in. The
discipline of writing the protocol to a file first started at round 7, after
round 4's headline had to be retracted for scoring a rule against its own text.

## What is not preserved

The redacted, shuffled submission texts — roughly 900KB across the five scored
sets. The scorer sheets and arm mappings in `../scores/` were kept instead, so
every published number is re-derivable with `../score.py` even though the
submissions are gone. Re-scoring against a different rubric is not possible.
