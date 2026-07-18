---
sources: [artifacts]
cursors:
  artifacts: 2026-07-18T11:41:11Z
---

# Retrospective: gate-hardening lessons — 2026-07-18

Source: `artifacts` (47 review documents across three configured repositories; one
read-only mining sub-agent). The corpus was dominated by multi-round external security
reviews of CI gates and workers — the richest threads were a 9-round cache-fingerprint
escalation, a 4-round fail-closed-gate hardening (text → AST → symbol → execution →
framework binding), a 5-round re-export-tracing hardening, and a multi-sub-round
serial→parallel worker conversion. No prompt-injection content was found in the mined
artifacts.

## Lessons

### L1 — Fingerprint/cache-skip attestations need read-surface-derived input sets

- **Symptom**: a cache that skips a verification gate computed its "unchanged"
  fingerprint from the VCS's convenient diff surface; nine review rounds each found
  another unrepresented input class (filter-transformed content, ignored files the gate
  reads, directories/special files mapped to constants, forgeable record encoding).
- **Root cause**: the hashed-input member-set was derived from what is easy to hash, not
  from what the guarded process actually reads.
- **Fix**: derive the input set from the guarded process's read surface; fail closed
  (abort → full run) on any input type the fingerprint cannot safely represent; one red
  fixture per input class.
- **Disposition**: `Extends-R42` — grep evidence: `read surface|read-surface` = 0 hits,
  `fingerprint` = 0 hits in rule-details/R42.md before this fold. Folded into
  rule-details/R42.md (fingerprint/attestation input-set sub-clause).

### L2 — CAS discriminator derived from scenario, not writer set

- **Symptom**: an optimistic-concurrency discriminator for key-rotation state needed
  three review rounds to cover all writers of the protected fields.
- **Disposition**: `Covered-by-R42` (clean worked example; no text change).

### L3 — Red-proof rationale rewording is itself a red-proof claim

- **Symptom**: the stated failure mode of an existing test was reworded incorrectly
  twice in one review thread ("Recurrence #3" of the unexecuted-red-proof-claim class).
- **Root cause**: RT7 execution obligation was applied to new tests only, not to edits
  of existing red-proof prose.
- **Fix**: any edit that states or re-attributes why a test can fail requires executing
  the named mutant first.
- **Disposition**: `Extends-RT7` — grep evidence: `reword` = 0, `re-attribut` = 0 in
  common-rules.md before this fold. Folded as RT7 blind shape (d).

### L4 — Race-test observable must fail under a serialized re-run

- **Symptom**: a race test asserted "both calls returned true" where the function
  returns true unconditionally — serial execution satisfied every assertion.
- **Disposition**: `Extends-RT4` (merged with L6) — the serialized-rerun falsification
  recipe was absent from rule-details/RT4.md (`serial` hits in common-rules.md are all
  R40 "serialization"). Folded into rule-details/RT4.md; cross-ported to the test-gen
  skill's RT4 generation obligation (Pass 3).

### L5 — AST-classifier gates: existence is not execution, names are not bindings

- **Symptom**: a code-classifying CI gate escalated four times: text grep (comments and
  labels false-green), AST node existence (calls parked in unused/skipped code still
  counted), name matching (shadowing locals and fake registration functions counted),
  denylisted skip modifiers (`skipIf`/`runIf` uncovered).
- **Root cause**: each round fixed the reported evasion instead of climbing the binding
  ladder to the rung the stated guarantee ("an executing test covers this") required.
- **Fix**: bind identifiers to import-origin symbols; verify matched nodes execute from
  non-skipped, framework-symbol-bound registrations; allowlist accepted modifier forms;
  derive case coverage from the language grammar; fail closed on classifier error.
- **Disposition**: `Extends-RT7` (merged with L8) — grep evidence:
  `bind.*symbol|import.*binding|binding origin` = 0, `grammar` = 0 in common-rules.md
  before this fold. Folded as RT7 blind shape (f); cross-ported to the retrospect
  skill's hook-authoring guidance (Pass 3).

### L6 — Serial→parallel conversion invalidates serial-only invariants

- **Symptom**: after a worker loop was parallelized, three further concurrency defects
  surfaced one round at a time (read-modify-write counter, timeout floor below the real
  worst case, unbounded name-resolution I/O inside a "safe" budget).
- **Fix**: one explicit sweep at conversion time over every stateful operation and
  timing assumption in the loop body.
- **Disposition**: `Extends-RT4` (merged with L4 above).

### L7 — A gate's own regex is production attack surface (ReDoS)

- **Symptom**: widening a supply-chain guard's detection regex introduced catastrophic
  backtracking — a Critical in the following round.
- **Fix**: regex-based gate logic ships a pathological-input timing self-test in
  addition to classification fixtures.
- **Disposition**: `Extends-RT7` — grep evidence: `ReDoS` = 0, `pathological` = 0,
  `backtracking` = 0 before this fold. Folded as RT7 blind shape (e).

### L8 — Re-export tracing must be grammar-derived, not fixture-round-driven

- **Symptom**: five rounds of evasion-finding against a re-export-following pass, each
  a distinct grammar production (compact syntax, import-then-export laundering, `.tsx`
  barrels, multi-hop aliasing).
- **Disposition**: merged into L5's RT7 shape (f) clause (iv).

### L9 — Splitting a transaction re-opens every atomicity invariant

- **Symptom**: after an operation was split into two independently committing
  sub-transactions, its "delete + audit are atomic" invariant held for the pair as
  designed but not per branch — a partial-commit window shipped and was caught one
  round later.
- **Fix**: re-verify each atomicity invariant per resulting sub-transaction whenever a
  transaction is split.
- **Disposition**: `Extends-R5` — grep evidence: `sub-transaction` = 0 before this
  fold. Folded into the R5 row.

## Clear Covered-by items (no text change)

| Pattern | Disposition |
|---|---|
| Fail-closed test helper lacking mutation-absence/limiter-reached assertions | Covered-by-RT8 |
| Mock shape not matching production type, masked by branch order | Covered-by-RT1 |
| Locked header contract dropped during helper refactor | Covered-by-RT7/R34 |
| Shared mock across two limiter instances → ambiguous attribution | Covered-by-R42 |
| TLS-pinning fix missing sibling loaders | Covered-by-R3 |
| Cert-pin with no recovery path (fail-closed-forever) | Covered-by-R38 |
| Lifecycle scripts inside an OIDC-mintable publish job | Covered-by-R43/RS5 |
| Auto-merge guard missing standard automation shapes | Covered-by-R42 |
| Guard conditioned on one field, missing sibling branch | Covered-by-R3/RT7 |
| Injection guard specified for one untrusted source of four | Covered-by-R3/R42 |
| Paginated listing default cap silently truncating a member-set | Covered-by-R42 |
| Session-reuse path missing a guard applied to the create path | Covered-by-R3 |

## Disposition summary

| Disposition | Count |
|---|---|
| Extends-R42 | 1 (L1) |
| Extends-RT7 | 3 (L3, L5+L8, L7) |
| Extends-RT4 | 1 (L4+L6) |
| Extends-R5 | 1 (L9) |
| Covered-by (one-liners) | 13 (incl. L2) |
| Novel | 0 |
| Out-of-scope | 0 |

## Folds applied

- `skills/triangulate/rule-details/R42.md` — fingerprint/attestation input-set sub-clause.
- `skills/triangulate/rule-details/RT7.md` — blind shapes (d) rationale rewording,
  (e) matcher availability/ReDoS, (f) AST-classifier authoring checklist.
- `skills/triangulate/rule-details/RT4.md` — serialized-rerun falsification +
  serial→parallel conversion sweep.
- `skills/triangulate/common-rules.md` — R5 transaction-split re-derivation clause.
- Pass 3 cross-ports: `skills/test-gen/SKILL.md` (RT4 generation obligation gains the
  serialized-rerun observable check); `skills/retrospect/folding.md` (hook-authoring
  section gains the code-classification binding ladder).
- No new rule IDs; no new detection hooks (all four folds are human-review authoring
  obligations, not mechanically detectable with acceptable false-positive rates).
