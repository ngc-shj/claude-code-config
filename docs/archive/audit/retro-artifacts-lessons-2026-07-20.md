---
sources: [artifacts]
cursors:
  artifacts: 2026-07-20T00:00:00Z
---

# Retrospective: artifacts source mining (2026-07-20)

Date: 2026-07-20
Source: `artifacts` (review documents in configured sibling repositories; 18 candidate
files since the previous cursor). One read-only mining sub-agent against the
R1–R44 / RS1–RS6 / RT1–RT9 digest; dispositions verified by the orchestrator with grep
evidence over `skills/triangulate/common-rules.md` and `rule-details/`. The corpus was
dominated by a single long thread: an anti-evasion CI gate (a static AST classifier
enforcing a fail-closed test-coverage invariant) hardened across ~8 external-review
rounds, then a CI-timeout performance regression and its scope-aware fix. No
prompt-injection content was found in the mined artifacts (the injection-shaped text was
itself a documented finding, quoted inertly by the sub-agent).

---

## 1. A repo-wide analyzer/gate that scales super-linearly with the scanned set trips CI timeouts

**Symptom.** A correctness feature added incrementally to a whole-corpus AST analyzer
made the analyzer's total runtime explode (a whole-corpus classify went from ~0.02s to
~13s; the full gate from a few seconds to ~42s), tripping fixed CI test timeouts. It was
not a logic failure — a pure performance regression, invisible locally on small inputs
and only surfacing when CI ran the full corpus.

**Root cause.** The analyzer called APIs whose cost is per-CORPUS, not per-node: once a
type-checker / language-service initializes on a shared in-memory analyzer project, every
subsequent symbol lookup type-checks the entire scan set (a ~640× slowdown). Compounded
by redundant whole-tree traversals (a second full-file walk per file for a new sub-check)
and node-wrapping every identifier across the whole corpus. No correctness round
re-measured the analyzer's cost against the full set.

**Fix.** A new or extended repo-wide gate/analyzer must be complexity-bounded against the
FULL scan set before merge, and must never invoke a whole-corpus operation (language
service / type-checker symbol lookup, whole-tree walk, per-file subprocess) inside a
per-item loop. Resolve locally/syntactically where a same-file scan suffices; gate
expensive AST walks behind a cheap raw-text prefilter so only matching files pay; batch
per-file subprocess calls into one. Measure with CI-timeout HEADROOM (not a few seconds
under the limit) and treat CI-timeout as a first-class review dimension co-equal with
correctness.

**Disposition.** `Novel` → **R45**. Grep evidence before this fold:
`super-linear|language.service|per-item loop|full scan set|CI.timeout` = 0 hits in
`common-rules.md` and `rule-details/`. Considered R32 (deploy boot-smoke — not analyzer
complexity), R33 (CI-config duplication), R16 (dev/CI parity), R44 (piped gate status);
none covers analyzer performance regression as a CI-breaking class.
Provenance: `fail-closed-tranche2-deviation.md` D16; downstream mitigation codified in
`fail-closed-tranche3-plan.md` §Testing strategy (a `time <analyzer>` full-corpus
measurement gate).

## 2. Scope-blind by-name binding resolution in a security analyzer is an evasion hole

**Symptom.** A performance rewrite (lesson 1) replaced semantic symbol resolution with a
by-NAME whole-file declaration scan. The analyzer became scope-blind: it collected all
same-name declarations in a file and took the first. A fake object named `X` in a test
bound to an unrelated same-name production alias in a sibling function, so a fail-closed
security check read the fake as production and passed — the control silently fail-open. A
real security regression introduced BY a performance fix.

**Root cause.** Name-equality was substituted for scope/binding resolution. A by-name
match ignores lexical scope, shadowing, and alias chains — it equals true symbol
resolution only for genuinely same-file, single-binding names, which was assumed but not
guaranteed. The perf fix traded correctness silently at a security boundary.

**Fix.** When an analyzer resolves an identifier that feeds a security decision, the
resolution MUST be scope/binding-aware (respect shadowing, sibling-scope reuse, alias
chains) — a by-name match is insufficient. If performance forces a syntactic fast-path,
confine it to inputs where name-equality provably equals binding resolution and route
security-relevant binding resolution through a scope-aware path (e.g. a bounded semantic
project over only the small relevant file subset, keeping the whole-corpus scan
syntactic). Unresolvable inputs must FAIL CLOSED (treated as non-legitimate); a
semantic-vs-syntactic divergence must throw, never silently fall back. Ship regression
tests for sibling-scope same-name, inner-shadows-outer (both directions), and alias
chains.

**Disposition.** `Novel` → **R46**, cross-referenced from R43. Grep evidence before this
fold: `scope.blind|by.name.*scope|lexical scope|binding resolution` = 0 hits. Considered
R42 (class-membership — different: per-identifier binding, not set membership), R3
(incomplete propagation), R43 (fix-induced boundary widening — closest in spirit, since a
perf fix widened the boundary; R46 is the specific mechanism and cross-links to R43's
fail-safe-precedence review). Provenance: `fail-closed-tranche2-deviation.md` D17.

## 3. An anti-evasion gate must close the whole bypass class in one pass, not patch reported instances

**Symptom.** Closing one anti-evasion gap took ~8 external-review rounds because each fix
closed exactly one reported bypass and the reviewer immediately found the next member of
the same class: inline fake → const-bound → factory-result alias → module auto-mock →
`doMock` verb → typed `import()` specifier → config `resolve.alias` → global setup-file
placement → lexical scope. Each round shipped a narrow blacklist patch; the class stayed
open. The author recorded it as a thoroughness failure.

**Root cause.** Blacklist / whack-a-mole mindset — patching the reported instance instead
of deriving and closing the defect CLASS up front. The class had enumerable axes
(specifier form × mock verb × specifier kind × config-alias × placement × binding shape);
enumerating them once closes all at once. A whitelist (verify the ONE legitimate shape)
is inherently closed; a blacklist (enumerate every illegitimate shape) is inherently
open.

**Fix.** R42 already requires deriving the whole member-set from a defining primitive and
(clause ①b) re-deriving on the first expansion. This lesson adds the anti-evasion
specialization: when the gate defends against EVASION of a security control, prefer
verifying the single legitimate shape (whitelist) over enumerating illegitimate ones
(blacklist); enumerate the bypass class along its axes and close all members in one pass;
self-audit the sibling variants BEFORE submitting rather than waiting for the next review
round; factor the shared extraction (one specifier/binding parser used by every detector)
so a new input shape cannot lag one detector behind another. Do not attribute residual
gaps to "cat-and-mouse / inherent limit" — that is usually incomplete enumeration.

**Disposition.** `Extends-R42`. Grep evidence: `whitelist.*blacklist|one pass|anti-evasion`
= 0 hits in R42.md before this fold. Folded as a new R42 sub-clause. Considered a
standalone rule but the mechanism is the same class-derivation discipline as R42, sharpened
for evasion gates. Provenance: `fail-closed-tranche2-code-review.md` Rounds 3–9 (Round 7
"Note on process", Round 8 "Class closed"); `fail-closed-tranche2-deviation.md` D9–D15.

---

## Candidates considered and NOT adopted

- **Fingerprint/cache keying a safety gate must be injective and fail-closed on
  unrepresentable inputs** (from `pre-pr-gate-cache` artifacts): a strong, recurring
  pattern — but **already folded** into `rule-details/R42.md` as the "Fingerprint/
  attestation input-set sub-clause" during the 2026-07-18 retro (L1). No change.
  `Covered-by-R42`.
- **Reject-vs-missing collapsed to one sentinel → misleading downstream message** (soma
  `_probe_size` returning `-1` for both absent and policy-rejected): the injectivity
  cousin of the above but the consequence is a misleading user string; `Covered-by-R37`
  and the same injectivity principle. No separate fold.
- **Fail-open pane/identity check → fail-closed; TOCTOU on path-passing; TTL/sweeper
  races** (soma): `Covered-by-R38` / `RS3`+`R31` / `R9` respectively. No fold.
- **Indirect prompt-injection: auto-submitting target-authored content to an autonomous
  agent** (soma, fixed to insert-only human-in-the-loop): a product threat-model decision,
  not a generalizable code-review detection obligation. `Out-of-scope`.
- **Filename-suffix drift excludes a test from the mandatory lane** (roadmap R2-1):
  `Covered-by-R16`/`RT9`-adjacent, adjudicated in-artifact. No fold.
- **The bulk of tranche/roadmap review findings** (vacuous denial helper → RT8; class
  unpinned → R42; scan-root incompleteness → R42/R18; `logAudit`-in-assertNoMutation →
  RT8; snapshot re-key → RT9; throttle-bleed cross-test → RT4): all explicitly adjudicated
  against existing rows in the artifacts. `Covered`, no fold.

## Fold summary

- **R45** (new, all-expert): repo-wide analyzer/gate super-linear scaling → CI timeout.
- **R46** (new, all-expert): scope-blind binding resolution in a security analyzer →
  evasion; cross-referenced from R43.
- **R42** (extended): anti-evasion sub-clause — whitelist-over-blacklist, one-pass axis
  enumeration, self-audit before review.
