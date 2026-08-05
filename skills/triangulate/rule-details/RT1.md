# RT1 — Mock-reality divergence

This file contains the full normative procedure for `RT1`. The compact row in `../common-rules.md` is only its routing summary.

## Full rule

| ID | Pattern | Procedure | Severity if missed |
|---|---|---|---|
| RT1 | Mock-reality divergence | Fires when a test double stands in for a boundary (persistence layer, HTTP client, message broker, platform SDK) and the value it returns is not what the real boundary returns. **The obligations below were derived from a panel shown only the defective code, none of whom saw this rule** (`evals/rule-firing/rubrics/RT1-merged.md`); the rule previously said only that the shapes must match, and the panel found unanimously that satisfying exactly that fixes nothing. (a) **Shape completeness is enforced by the type system, not by a reader counting fields** — bind the fixture to the boundary's own declared type so omitting a field fails the build, and reject every escape hatch that re-admits a short value (casts, partials, `any`, suppression comments); a fixture that merely happens to be complete today reopens the gap at the next schema change. (b) **The compile-time guard must actually be executed** — a type annotation in a pipeline that runs only the test runner is documentation. (c) **A constant double cannot support an oracle**: when the double returns a value fixed before the call and the subject echoes it, an assertion comparing two outputs of that subject is an identity, true under every implementation — completing the fixture converts a tautology over few fields into a tautology over many. Make the double compute its return from the arguments it received, and hold state across calls when the behaviour under test is about repetition. (d) **At least one assertion compares against an independently written expected value**, not only output-against-output, and not an expression derived from what was fed to the double. (e) **Compare the whole value exactly**, on the key set as well as the values; a comparator that treats an absent key and a present-but-empty one as equal is how a dropped field survives, and loose matchers or recorded snapshots reintroduce the incompleteness at the assertion layer. (f) **Choose fixture values away from the boundary's defaults and away from each type's zero value**, so "the subject substituted a default" is distinguishable from "the subject returned what was stored". (g) **Compare at the serialization boundary the caller sees** — a value that crosses an encoding step is asserted in its encoded form. (h) **One definition of the complete value, shared**; and fix the class, not the instance — search for the other doubles of the same boundary and repair them, recording the search. **Distinct from**: RT5 (the production primitive is absent from the call path, rather than present and fed a wrong-shaped value), RT8 (the assertion omits the side effect, rather than comparing the wrong value). | Critical when the divergence hides a security or correctness control; Major otherwise |

## Why the shape clause alone is insufficient

The panel's own statement of the mechanism, which no wording of "make the shapes match" reaches:

> Completing the fixture to nine fields converts a tautology over 4 fields into a tautology over 9. The assertion never had contact with [the property it names]: [that property] is a property of repeated writes against *state*, and there is no state in this test.

and, on what a reader of the short rule will most likely do:

> Fixing only (A) (padding the literal to nine fields) leaves (B) fully intact and is the most likely lazy outcome.

Clauses (c) and (d) exist for that reason: they are the ones that make the test able to fail at all, and they are invisible from the shape requirement.

## Evidence

Panel of four, none shown the rule set, given only the defective code and a neutral statement of the defect (`evals/rule-firing/sketches/RT1-mock-shape.ts`). Thirty properties reached >=3/4 support, twenty of them unanimous; the rule as it stood carried one. Audit: `docs/archive/audit/2026-08-05-panel-audit-oneliners.md`.
