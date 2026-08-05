# Panel audit of the two one-line rules — 2026-08-05

The firing measurement named where the catalogue actually earns its keep. Two of
the top six are one-sentence rules: **RT1** (29 findings, the highest of any rule) and **R1** (20).
Rounds 8–9 established that a rule transmits exactly what it states, so a rule
this short firing this often is the sharpest gap the catalogue has. This is the
round-5/6 panel method pointed at it.

## Method

Eight panellists, four per rule, each shown only a defect sketch and a neutral
one-sentence statement of what is wrong. None saw the rule set; none was asked
to review anything; each had the whole task to itself. The sketches
(`evals/rule-firing/sketches/`) were derived from real findings in the corpus,
not invented — RT1's from a partial Prisma mock in `passwd-sso-ios`, R1's from
the shape the corpus shows for helper reimplementation.

Clusters kept at >=3/4 support. Merged rubrics: `evals/rule-firing/rubrics/`.

## Result

| | panel properties (per panellist) | merged at >=3/4 | of which 4/4 | in the rule |
|---|---|---|---|---|
| RT1 | 50 / 44 / 39 / 36 | **30** | 20 | **1** |
| R1 | 49 / 40 / 38 / 33 | **29** | 20 | **1–2** |

RT1's entire text is "Mock return values must match actual API response
shapes" — merged property Q1, and nothing else. R1's is "`grep -r` for existing
helpers before accepting new implementations" — Q2, and Q1 by implication.

Round 6 found rules carrying a quarter to a third of what a panel demands. These
carry a thirtieth.

## The finding that matters: the rule names the symptom, not the hazard

Both audits converged, 4/4 each, on something round 6 did not see. The defect
the rule names is real, and fixing exactly what the rule prescribes leaves a
worse defect untouched.

**RT1.** The mock is incomplete *and* the assertion has no oracle — a constant
`mockResolvedValue` against an echoing route makes the two compared responses
equal by construction.

> "Completing the fixture to nine fields converts a tautology over 4 fields into
> a tautology over 9. The assertion never had contact with idempotency."
> — panel RT1_c

> "Fixing only (A) (padding the literal to nine fields) leaves (B) fully intact
> and is the most likely lazy outcome." — panel RT1_d

**R1.** The helper is duplicated *and* the call site retries a non-idempotent
`POST /invoices/:id/charge` on every error class.

> "It does not fix the actual hazard. ... Deduplicating them yields one copy of
> the same double-charge exposure — a tidier diff and an unchanged risk. A fix
> that stops at deduplication has resolved the stated problem and left the
> dangerous one in place." — panel R1_c

> "IDEMPOTENCY — the failure mode that makes this a billing bug rather than a
> duplication bug" — panel R1_d, section heading

A detail worth keeping: adopting the shared helper, which is all R1 asks for,
*introduces* a behaviour change on the payment path — `withRetry` jitters by
default and the local loop did not, so retry timing becomes non-deterministic
and its floor drops from 200ms to 100ms. Following the rule literally is not
even behaviour-preserving.

## Why the Remedy Floor does not cover this

The five floor clauses are about the *quality* of a remedy: pair the allow side,
red-prove by execution, fail loudly, don't delete the useful behaviour, name the
boundary. All five presume the remedy is aimed at the right defect. Neither
audit's central finding is reachable from any of them.

## Candidate sixth clause — recorded, not claimed

> **The rule that fired names a pattern, not necessarily the hazard.** Before
> writing the `Fix:`, state what the defect's presence implies about the code
> around it, and name the failure the prescribed fix does NOT address — or state
> that there is none. A remedy that resolves the pattern and leaves a larger
> exposure in place reads as complete and is not.

Under `folding.md`'s own standard this does not get to claim it works until an
ablation shows reviewers carrying it produce fixes that reviewers without it do
not. The rubrics above are the scoring instrument that ablation would use, and
the sketches are its fixtures. That run is the next thing, exactly as #126 was
owed #127.

## Folded (same day)

Both rules were extended from their rubrics — `rule-details/RT1.md` and
`rule-details/R1.md`, with the rows pointing at them and carrying the
"necessary and not sufficient" statement inline so a reader who never opens the
details file still gets the correction.

RT1 gains eight clauses, of which (c) and (d) — a constant double cannot
support an oracle; assert against an independently written expected value — are
the ones the shape requirement cannot reach. R1 gains six, of which (e) — ask
what the duplicate's existence implies about the call site, and name the failure
the dedup does not address — is the one "search for the helper" cannot reach.

This fold rests on #128, not on the panels alone: that round showed, replicated
across two fixtures, that extending a rule transmits the clauses added (the
property that was 0/29 everywhere went 16/16). The panels establish *what* is
missing; #128 establishes that writing it down is a mechanism that works. What
is not yet measured is whether these particular clauses transmit, which is the
same debt every extension carries.

## What follows

1. **Ablate the candidate clause** against these two rubrics, W/N, n=8 per cell,
   blind-scored — the harness and the instrument both already exist.
2. **Panel-audit the remaining five of the top seven** (R3, R2, RT5, R19, RT7).
   Their texts are long, so the round-6 ratio may hold rather than this one.
3. **Do not conclude from two rules** that every one-liner is this bad. RT1 and
   R1 were chosen precisely because they were the shortest of the high-firing
   set, which is the strongest possible selection bias toward this result.
