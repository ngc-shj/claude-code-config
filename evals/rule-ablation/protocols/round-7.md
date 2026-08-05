# Round 7 protocol — Remedy Floor ablation (written before any run output was read)

## Wiring finding (static, pre-probe)

As merged in #126, the Remedy Floor is a section of `common-rules.md` that no
routing path names: the digest does not mention it, SKILL.md's loading protocol
extracts triggered rows + Extended obligations + explicitly named sections only,
and phase-3's expert requirements ask for "recommended fix" without citing it.
A reviewer following the deployed extraction protocol never reads the section.

Probe: n=4 arm-F runs on F1 at HEAD (deployed, unwired digest), varied preambles.
Prediction recorded before results: floor clauses will NOT appear in Fix: lines
beyond the pre-floor base rate. If they DO appear, the wiring concern is moot and
the ablation compares deployed-as-is vs no-floor instead.

## Arms

- **W** — HEAD materials + one digest line wiring the floor: every Fix: must
  satisfy the Remedy Floor; extract the section with a bounded awk.
- **N** — HEAD materials with the Remedy Floor section removed and the
  `Fix:` template pointer reverted; digest without the wiring line.

Same reviewer prompt as round 4's arm F (5-step protocol), identical between
arms except the materials directory. Eight preamble variants per fixture,
the same eight in both arms (paired).

## Fixtures

F1 (R44, shell gate) and F3 (RT8, vacuous denial test). Chosen because:
neither rule was touched by #125's R54 extension (no confound), detection was
saturated on both in rounds 1–3 (remedy differences measurable on ~all runs),
and their round-6 panels demanded ~13 / ~11 properties of which the rules carry 2.

n=8 per cell → 32 runs.

## Scoring

Blind. Outputs anonymised by the same redaction as the round-4 re-score
(protocol headers, rule IDs, catalogue vocabulary, fixture filenames, plus the
token "Remedy Floor" itself), shuffled with a fixed seed. Three independent
scorers each score all submissions against the merged panel rubric for the
fixture's rule (majority ≥3/4 items from the four round-6 panellists); majority
vote per item decides.

## Metrics (pre-registered)

- **Primary**: coverage of the floor-mapped subset of the merged rubric. The
  item→floor-clause mapping is written when the merged rubrics arrive and
  BEFORE any ablation output is read.
- **Secondary**: total merged-rubric coverage.
- Report n beside every number. A difference that does not appear in BOTH
  fixtures is fixture-specific and is not a claim.
- The round-4 lesson stands: a W−N difference at n≤3 on any sub-slice is a
  reason to run more trials, not a result.

## Preambles (same order both arms)

1. plain
2. "Work independently; do not assume any particular defect is present."
3. "You are a senior engineer performing a pre-merge review."
4. "You are the reviewer of record; your findings gate this merge."
5. "Be thorough but concise."
6. "You have limited time; prioritise the defects that matter most."
7. "You are the second reviewer, double-checking a colleague's pass."
8. "You are the last gate before deploy."

## Probe result (recorded 2026-08-05, before any ablation run)

n=4, F1, HEAD materials, arm-F protocol. Tool-call traces show all four agents
performed digest read → anchored row extraction (R44/R50/R47/RT7) →
rule-details reads, and ZERO reads or extractions of the Remedy Floor section.
No output mentions the floor. The wiring gap is confirmed by execution, not
inference: as merged in #126 the floor is unreachable under the deployed
extraction protocol. Design goes ahead as W (wired) vs N (absent).

Note: the four probe outputs themselves are usable qualitative context but are
NOT part of the W/N comparison (different digest from both arms).

## Floor mapping — R44 merged rubric (written before any ablation output was read)

Floor clause → merged-rubric items:
1. allow-side pair        → Q16
2. red-proof by execution → Q18
3. fail loudly / cannot-run → Q8, Q9, Q11, Q17
4. preserve useful behaviour → Q5, Q6
5. boundary and tie       → (no R44 item; clause not applicable to this fixture)

Floor-mapped subset (8 items): Q5 Q6 Q8 Q9 Q11 Q16 Q17 Q18
Mechanism subset (11 items): Q1 Q2 Q3 Q4 Q7 Q10 Q12 Q13 Q14 Q19

## Floor mapping — RT8 merged rubric (written before any ablation output was read)

1. allow-side pair        → Q5; Q6 (positive control / wiring-break guarantee, clauses 1+2 jointly)
2. red-proof by execution → Q8, Q9
3. fail loudly / cannot-run → (no kept item; D11 dropped at 1/4)
4. preserve useful behaviour → Q11 (weak mapping: mutations reverted, no .only/.skip)
5. boundary and tie       → (no kept item)

Floor-mapped subset (5 items): Q5 Q6 Q8 Q9 Q11
Mechanism subset (6 items): Q1 Q2 Q3 Q4 Q7 Q10
