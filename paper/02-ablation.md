# 2. Rule ablation: what the catalogue does and does not do

The review skill ships a catalogue of 74 rules, every one added on the same
theory: a review missed something *because the rule was not written down*. The
counterfactual — whether the reviewer would have found it anyway — was never
measured until this line did what the repository's hooks already required of
themselves: red-prove the rule by removing it and seeing whether the finding
disappears (`../evals/rule-ablation/README.md`). Eleven rounds later the answer
has a shape nobody designed: **the catalogue's measurable value is not
detection, and not "remedy quality" in general — it is the literal transmission
of the specific clauses a routed rule states.** The ablation audit's own
closing phrase is the chapter's thesis: *a rule is worth exactly what it says*
(`../docs/archive/audit/2026-08-04-rule-ablation.md`, Round 8).

The protocol behind every figure: an authored fixture containing exactly one
instance of the target rule's defect class plus five to fifteen competing
defects; an oracle written before any run; arms differing only in catalogue
material — the spotlit rule (A), pattern names only (B), nothing (C), and the
deployed configuration (F); scoring against the oracle by the experimenter,
never by the reviewing agent. Three trials is a look, not a result: two
early n = 3 claims, one in each direction, vanished at n = 8.

## 2.1 Detection: no detectable difference, stated at its true weight

Across rounds 1–3 — eight fixtures, single-file to eight-file, cued and
uncued — **no detection difference survived replication** (MEASURED;
`../docs/archive/audit/2026-08-04-rule-ablation.md`, Rounds 1–3) — the two
n = 3 retractions of the protocol section among the casualties.

The power audit is part of the claim, not a footnote to it: detection was
scored as a binary at n = 8 per arm, where 8/8 against 6/8 is p = 0.47 and
nothing short of 8/8 against 3/8 would have registered. The nulls could only
ever have ruled out a very large effect, and the one cell the rounds did flag
(arm C missing F6's defect in 3 of 8 runs) sits at p = 0.20 (MEASURED; the
audit's power section). "The rules do not move detection" is not licensed by
this design; "no detectable difference, where only an enormous one was
detectable" is.

One null in the set is load-bearing at exactly its measured width: **arm B —
pattern names only — showed no detectable difference from no catalogue at
all**, under the same power caveat. Chapter 6's routing refutation is the
same fact met from the other side, and the audit's first listed consequence
is the operational form: do not shrink rows to digest names.

## 2.2 Remedy: where the self-score was wrong twice, and what survived blinding

Round 4 scored proposed fixes against a rubric read off R54's own text — the
arm holding the rule graded against the document it was handed — and its
headline did not survive. Round 5 rebuilt the rubric with ten panellists who
never saw the rule (`../evals/rule-ablation/independent-rubric.md`): the
rule's three clauses were all independently required, and the panel demanded
**six more** that the rule taught nowhere. One panellist named the
consequence: a naive `try/finally` passes both tests the rule asks for and
fails only the concurrency test the rule never mentions — the taught tests
certified exactly the wrong fix.

Round 6.5 then re-scored all 32 round-4 fixes blind — arm identity redacted,
fixed-seed shuffle, three scorers, pairwise agreement 94.6–99.6% (MEASURED;
the audit, Round 6.5). What survived and what did not:

- **F6, the buried unfamiliar-mechanism fixture: the advantage is real and
  blind.** 6.25/9 with the deployed catalogue against 4.40/9 without —
  diff 1.85 against an MDE of 1.21 — with three no-catalogue runs never
  fixing the defect at all, and the same-context test at 8/8 vs 0/5.
- **F9, where the platform idiom encodes the fix: the gap is inside the
  noise.** 7.25 vs 6.75 is 0.50 against an MDE of 0.70; the power audit
  marks the direction as not established. Round 4 had scored one F9 cell's
  error path at 1/8; blind, the same cell is 8/8 — the mechanism the
  no-catalogue reviewers chose restores on throw by construction, and the
  self-score missed it.
- **Self-scoring erred in both directions** — inflating the fixture where
  the rule looked good, deflating the arm it underestimated — which is the
  argument for blinding stated as an observation, not a principle.
- **P9 — the concurrency property a naive fix uniquely fails — was 0/29
  across every arm and fixture.** What no rule teaches, no reviewer
  produces, with or without a catalogue.

Round 6 located the deficit structurally: panels applied to four more rules
found catalogue rows carrying **2–5 of the ~11–15 properties** an independent
panel requires of a correct fix (MEASURED;
`../evals/rule-ablation/panel-audit.md`). The catalogue's problem was not one
rule's wording; it was how much of a correct fix the rows state at all.

## 2.3 Wiring, then transmission: the two positive results

**Round 7 — a section no routing path names is dead text.** The Remedy Floor
merged as prose that the digest never mentioned and no template cited; a
four-run probe of the deployed configuration, read from tool-call traces,
found **zero of four reviewers read it** (MEASURED;
`../evals/rule-ablation/README.md`, Round 7). Wired by one digest line and
ablated properly — wired arm against absence — the floor moved its own
clauses (+1.6/8 on F1, +3.6/5 on F3) with no detectable mechanism change,
scorer agreement ≥ 89.8%. Reachability precedes content, and the probe costs
four agents.

**Round 8 — taught, they produce it.** The R54 extension, written on round
6.5's 0/29 evidence, was owed its own ablation: extended rule against
pre-extension rule, floor wired in both, one variable, blind-scored against
the round-5 rubric that pre-dates the extension, agreement 99.7–100%
(MEASURED; the audit, Round 8). The extension properties went from near-zero
to near-ceiling — **P9, the 0/29 property, is 16/16 with the extension and
0/16 without**; P8 16/16 vs 1/16; P4 16/16 vs 0/16 — while the control
properties sat exactly flat at 3.00 in all four cells. The one clause that
under-transmitted (P5, isolation, 1/8 on the Postgres fixture) had the one
platform-split wording.

**Round 9 — the rewording, and the trap the same-batch control caught.**
Rewriting P5's clause into two named variants took it to 8/8 on the fixture
where it failed — against a **same-batch** re-run of the old materials at
5/8, not against round 8's stored 1/8. Byte-identical materials moved four
points between batches; a cross-batch comparison would have claimed
1/8 → 8/8. The defensible claim shipped instead, and the lesson entered the
standing method (§7.1.2): arm comparisons are valid within a batch; a stored
number is context, not a control.

## 2.4 What this chapter claims, and no more

The catalogue does not detectably change what reviewers find, at a power that
could only have caught a very large change — and a names-only catalogue is
not detectably better than nothing, under the same caveat. Its remedy value
is real where the defect mechanism is unfamiliar (F6, blind, diff above MDE),
not established where the platform idiom already encodes the fix (F9, inside
its MDE), and bounded tight only where the nulls were tight — rounds 10–11's
remedy nulls bound their effects at roughly 5–9% of the rubric (MEASURED; the
audit's power section). What the catalogue demonstrably does is transmit:
clauses it states arrive in fixes at near-ceiling rates; the one untaught
property tracked to zero everywhere — the concurrency test — never appeared
(0/29, then 0/16 in the later unextended arm), while other untaught
properties appeared rarely rather than never (the throw-path test: 2/16 and
1/16); a section nothing routes to might as well not exist; and a clause's
wording is part of whether it arrives. Every fixture was authored by
someone who knew the rule under test — an authorship bias whose direction
Chapter 8 argues cannot be assigned —
and every figure above is one model epoch, blind-scored where stated, and
re-runnable from the archived sheets.
