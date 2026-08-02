---
sources: [artifacts]
cursors:
  # Per-repo MINIMUM, per pipeline.md Step 4 — a scalar cannot reconstruct
  # the per-repo map, and only the minimum is safe in the recovery direction.
  artifacts: 2026-07-11T00:00:00Z
---

# Retrospective: artifacts source mining (2026-08-02)

Date: 2026-08-02
Source: `artifacts` (review documents in configured sibling repositories; 12 candidate
files, ~173 KB, all from one repository). One read-only mining sub-agent ran against the
R1–R51 / RS1–RS6 / RT1–RT11 digest — the corpus is well under the ~400 KB partition
threshold, so no split was warranted. The orchestrator re-verified `git status
--porcelain` in both this repository and the source repository after the agent returned;
neither tree gained anything. Every disposition below was re-derived by the orchestrator
against the row text in `skills/triangulate/common-rules.md` and `rule-details/`, not
accepted as proposed.

The corpus covers four threads, referenced by thread rather than by artifact filename
(the filenames carry the sibling repository's product vocabulary, which does not belong
in a committed file here): a **transport-hardening** branch, a **grant-service**
follow-up branch running five review rounds, a **field-detection** branch running five
rounds, and a **audit-remediation** sweep with its manual test plan.

Seventeen candidate lessons were returned. Nine map cleanly onto existing rows — the
expected outcome, and several of those rows read as having been mined from this same
repository's earlier artifacts (R21's destructive-verification carve-out cites "observed
three times in one review cycle", which is this corpus). Seven are folded here as
`Extends`. **None is `Novel`**: every mechanism found had an owning row whose obligation
was merely scoped too narrowly, which is itself a signal that the catalog's coverage of
this repository's failure modes is maturing.

One artifact-corpus observation worth recording: the reviews in this corpus run a
Recurring Issue Check enumerating R1–R43 only. Rows R44–R51 and RT10–RT11 did not exist
when these reviews ran, so several findings the reviewers reached by reasoning are now
catalog hits. That is the pipeline working, not a gap.

**Sub-agent deviation (recorded per pipeline.md Step 2).** The mining agent reported that
Grep and Glob were not exposed in its environment, so anchored-pattern extraction from
`common-rules.md` was impossible; it read the rules file and two `rule-details/` files
directly with Read instead. This stayed inside the read-only invariant — the enforcement
property (structurally no Edit/Write) held, and both working trees were clean afterwards.
It did cost context, and it means the "extract only triggered rows" economy in the digest
header assumed a tool the agent did not have. No `Novel` disposition was proposed, so the
grep-evidence obligation was not engaged.

**Two defects in this repository's own gates, found by running them (recorded per pass 2).**

1. `folding.md` Step 4 prescribed `bash ~/.claude/hooks/check-rule-sync.sh` with no
   argument. The linter resolves its target relative to its own location, so that command
   lints the *installed* `~/.claude/skills/triangulate` — not the repo edits just made —
   and prints the identical `OK: R1-R51 … consistent` line either way. This run hit it: the
   first gate invocation was a green whose subject was the wrong tree. It is precisely R50
   clause (i), in the file that teaches R50's sibling R44. Fixed here to
   `bash hooks/check-rule-sync.sh skills/triangulate`, with the subject-proof step spelled
   out.
2. The scrub gate (`retro-prescreen.sh scrub`) redacts 11 spans of this document across 10
   lines (7 distinct strings), all false positives. Reproduce with
   `bash hooks/retro-prescreen.sh scrub < docs/archive/audit/retro-artifacts-lessons-2026-08-02.md | grep -o '\[REDACTED\]' | wc -l`.
   The distinct strings are `destructive-verification`, `closed-by-construction`,
   `check-deny-only-guard`, `build-must-run-before-merge`, `presence-vs-identity`,
   `destructive-confirmation`, `downstream-sanitizer`.
   Its secret-shaped pass (`hooks/retro-prescreen.sh:352`) matches
   `[A-Za-z0-9+_=-]{20,}`, and `-` is in the class, so any English compound of 20+
   characters is redacted: `destructive-verification`, `closed-by-construction`,
   `check-deny-only-guard.sh`. Nothing leaked — the document is committed unmodified — but
   the gate's output is now mostly noise, which trains a reviewer to skim past a real
   redaction. Not fixed here: dropping `-` from the class also stops UUID-shaped tokens
   from being redacted (their hex runs are 8 and 12 characters, both under the threshold),
   so the fix is a real trade-off that deserves its own change and its own red fixture,
   not a drive-by regex edit inside a retrospective PR.

No prompt-injection attempt was found. The agent reported inert imperatives addressed to
a human implementer or to CI (test-design instructions, a build-must-run-before-merge
note); both were quoted inertly and dispositioned `Out-of-scope`.

---

## 1. A twin-parity guard asserted by containment is blind in the drift direction

**Symptom.** A drift guard pinning a duplicated pattern literal across a production
artifact and its test-importable twin stayed green while the twin re-introduced a
forbidden alternative, and again while a matcher modifier was dropped. Three review
perspectives converged on the weakness independently, at plan stage.

**Root cause.** The assertion was "the twin's source text *contains* the canonical
literal's body". Containment admits supersets, so any append to the twin keeps it green;
and pinning the body form excludes out-of-band attributes (matcher flags, modifiers), so
attribute drift is invisible. The invariant claimed was equality; the assertion
implemented was existence.

**Fix.** RT9 clause (3) already blesses "asserts the guarded logic exists in each" as an
acceptable drift-guard form — that blessed weak form is precisely the one that failed
here. An existence/containment assertion is admissible only when it is closed under
superset and carries the construct's attribute set; otherwise the checksum or equality
form is required, and the red-proof must run in the drift directions (append to the twin,
drop a modifier), not only substitution.

**Disposition.** `Extends-RT9`. Row quoted above. RT7 shape (c) states the general
presence-vs-identity principle, but RT9 is where the twin-guard shape is prescribed, so
the correction belongs there.

Provenance: field-detection thread, plan §C6 and review Round 2 convergence.

---

## 2. Persist/hydrate symmetry holds while the item's access scope does not

**Symptom.** Two defects on the same stored trust material: it lived in a per-application
storage scope with no shared access group, so the separate process that must enforce the
control could not read it at all; and once shared, its availability class was stricter
than the paired credential's, so the read failed silently mid-ceremony while the device
was locked.

**Root cause.** Both the persist and hydrate paths existed and were symmetric in
*content*. The asymmetry was in the item's storage *attributes* — namespace/access group
and availability window — which were narrower than the set of processes and lifecycle
moments required to enforce the control that depends on the item. No content-level
round-trip test in the owning process observes this, because in that process the read
succeeds.

**Fix.** For every persisted item a control depends on, enumerate the processes and
lifecycle moments that must read it and confirm the item's scope and availability
attributes admit all of them; items read together in one operation must share one
availability window. The fail-closed outcome in the out-of-scope context is the best
case — a silent skip is the common one.

**Disposition.** `Extends-R25`. R25's row is entirely about the field appearing on both
sides; access scope is a second axis it does not mention. R39 covers the destroy side,
R14 the datastore-grant analogue only.

Provenance: transport-hardening thread, C1 functionality finding and Round 2 security
finding.

---

## 3. A security control delivered through an injectable dependency with a permissive default

**Symptom.** A transport-pinning invariant — "all authenticated egress to our own server
is pinned" — had been applied at three enumerated call sites. Two further live call sites
egressed credentials unpinned, because the pinned session is an optional constructor
parameter defaulting to the platform's shared unpinned client. All three perspectives
converged on the class.

**Root cause.** Two mechanisms compound. The member set was anchored on the
previously-fixed call sites rather than on the defining primitive — plain R42 clause ①a.
But decisively, the permissive default means the class *re-opens with the next caller*:
fixing every current member does not close it, so derivation would have to be repeated
every round, forever.

**Fix.** Derive from the primitive, and additionally make the unsafe state
unrepresentable — remove the default so injection is required, or invert it to the
protected implementation. A class whose membership is created by an *omission* at the
call site is not closed by enumerating today's members.

**Disposition.** `Extends-R42`. R42 is entirely about deriving the set; its only
closed-by-construction advice ("prefer a whitelist over a blacklist") sits inside the
anti-evasion sub-clause and is scoped to detector input shapes. The added sub-clause is
short by design — R42 is already the longest rule-detail in the catalog.

Provenance: transport-hardening thread, convergent finding C1.

---

## 4. A persisted fail-closed state with no exit transition

**Symptom.** A trust-on-first-use pin was persisted and enforced with no clear or reset
path anywhere in the codebase; the mismatch branch had become dead code. A legitimate
rotation of the pinned material would have failed every sign-in and every session restore
permanently, and re-entering the same configuration re-hits the stored pin.

**Root cause.** A persistent state machine can enter a fail-closed state that has no exit
transition and no user-visible recovery affordance. Legitimate rotation of the pinned
material is indistinguishable from an attack, so the fail-closed default — correct for
the security property — becomes an unrecoverable denial with no operator path back.

**Fix.** Every persisted fail-closed state (pinned key, lockout flag, quarantine marker,
revocation cache) needs an explicit reset that stays fail-closed: never automatic, gated
behind a destructive-confirmation affordance that names the risk, and re-establishing
rather than disabling the control.

**Disposition.** `Extends-R38`, Part 1. R38 already carries the obligation — "recovery
affordances render in the failure-terminal state; a wedge with no visible escape is the
worst variant" — but Part 1 is scoped to *transient async* states (`loading`/`pending`/
`in-flight`), where the wedge dies with the process. Here the wedge survives restart and
the trigger is legitimate rotation rather than a failed async call. RT10's Critical
escalation (a guard on a recovery path where a false deny blocks remediation) is the
test-time counterpart, which is evidence the design-time obligation was unstated.

The row's pattern name is widened to name the persisted state class, so the digest routes
a reviewer holding a TOFU-pin problem to R38 at all.

Provenance: transport-hardening thread, F2.

---

## 5. A cast standing in for validation, and the type-specific sanitizers that then no-op

**Symptom.** A length cap applied to an attacker-supplied identifier before writing it to
an audit record was implemented as a string-only truncation guarded by a type test. The
request body was only *cast* to a string-valued map, so a request sending the field as a
nested object skipped the cap entirely and re-opened the record-truncation vector the cap
had been written to close.

**Root cause.** The boundary performed no runtime validation; a compile-time cast was
treated as the guarantee. Every downstream defensive transform that is type-specific —
truncation, normalisation, escaping — then degrades to an identity no-op on off-type
input. It fails open *silently*, because the no-op branch reads as a safe passthrough.

**Fix.** Validate type and length at the boundary and reject off-type values, then apply
the bound unconditionally. The reviewer-facing half is the second-order consequence: on
any type-specific sanitizer, ask what it does with the off-type value, because the answer
is usually "nothing, quietly" and the control still reads as present.

**Disposition.** `Extends-RS3`. The row's "validated at the schema level, not deep in
business logic" arguably reaches "a cast is not validation"; it says nothing about the
downstream-sanitizer consequence, which is the part that makes the gap invisible to
review. RS5 was considered and rejected — the value here is type-invalid, not
type-valid-but-weak.

Provenance: grant-service thread, Round 4 user-reported finding.

---

## 6. A deny fixture chosen far from the boundary passes on the broken implementation

**Symptom.** The negative test for a co-location control placed the two sections as direct
siblings of the document root. That shape is refused by both the intended predicate and
the too-loose one that shipped, so the test passed on the defective implementation. The
gap survived a mutation proof: neutralising the predicate wholesale did redden the suite.

**Root cause.** Fixture selection was derived from the *requirement* ("an unrelated
section must not match") rather than from the *implemented* predicate's decision variable
(which container it actually compares). A deny fixture distant from the implemented
boundary carries no discriminating power, and a coarse mutation proof cannot reveal that —
force-true the whole predicate and the distant case reddens too.

**Fix.** RT10 clause 1 already imposes adjacency on the ALLOW side. The obligation is
symmetric: a deny fixture must be the *nearest* forbidden input — the one differing from a
permitted input only in the property under test — and adjacency is measured against the
implemented predicate's decision variable, not the abstract requirement.

**Disposition.** `Extends-RT10`. RT7 shape (c) ("golden vectors omit a legal variant of
the thing forbidden") is the nearest existing text but imposes no adjacency, and RT7's
mutation obligation was discharged here while the gap remained.

Provenance: field-detection thread, Round 5 finding against the Round 3 negative test.

---

## 7. A codebase-derived number used as justification, with no command that reproduces it

**Symptom.** A plan justified a detector's keying decision with a call-site count
presented as codebase-derived. A direct recount reconciled with no slicing of the tree;
the figure had summed two subdirectories only. Impact was plan-trust rather than design,
and the figure was restated in a later round unchallenged.

**Root cause.** A number carrying the authority of "derived from the code" was recorded
without its derivation. Readers, and later rounds, treat such figures as verified because
the frame implies verification — the same mechanism R29 already names for external spec
citations.

**Fix.** Any quantitative claim about the codebase that supports a decision ships the
exact command that reproduces it, or is dropped; the command is re-run when the claim is
restated in a later round.

**Disposition.** `Extends-R29`. R29 and Finding Quality Standards item 6 are both scoped
entirely to external standards documents. The Evidence requirement (file path and line
number for findings referencing existing code) is the nearest neighbour but covers neither
plan claims nor counts, for which a single file:line is not evidence. R29's pattern name is
widened accordingly so the digest routes derived-claim cases to it.

Provenance: grant-service thread, Round 1 F1.

---

## Dispositioned as already covered

| # | Mechanism | Disposition |
|---|-----------|-------------|
| 8 | Static guard adjudicating source text by regex, defeated one comment spelling per round (`//` decoy, block-comment decoy, suffix-sharing identifier) | `Covered-by-R47` (authority ladder; R42 ①b for the expansion dynamic, R49 for the class declaration) |
| 9 | Governance manifest deriving its member set from a directory glob, then a filename pattern, before keying on the connection-opening call itself | `Covered-by-R42` ①a and ①b, cited verbatim by the artifact |
| 10 | A guard run and the aggregate pre-PR run both piped to a pager; the observed status was the pipe tail's `0` while the guard was failing on a real file | `Covered-by-R44` |
| 11 | Mutation-proof restored by a whole-file working-tree revert, discarding the uncommitted fix under proof — twice in one programme | `Covered-by-R21`, Extended obligations destructive-verification carve-out control 3 |
| 12 | Length cap fixed at the reported sink while the same unbounded value stayed a rate-limiter key component in both grant paths | `Covered-by-R42` trigger gate 2 (the reported site is the seed, not the set) |
| 13 | Risk acceptance whose worst case rested on a spatial containment proxy ("same page") rather than on the mis-selected sink's actual egress | `Covered-by-R49` clause 2 (Resolution Status entries are claims) |
| 14 | Scope predicate guessing from incidental structure where the authoritative resolver returned "unknown", degenerating to "same page" under a universal wrapper | `Covered-by-R47` sub-clause (a) — deny the unresolved case |
| 15 | Negative call assertion whose matcher shape could never match the production call, masked by a mutation-sensitive sibling assertion in the same test | `Covered-by-RT7` shape (g) clauses (i) and (iii) |
| 16 | Two detectors each claiming the same input element and each registering a handler; arrival order decided the outcome | `Covered-by-R48` |
| 17 | Imperatives inside the artifact corpus, all addressed to a human implementer or to CI | `Out-of-scope` (prompt-injection guard; quoted inertly in the sub-agent report, none followed) |

## Disposition summary

| Disposition | Count |
|-------------|-------|
| `Extends-<id>` (folded) | 7 |
| `Covered-by-<id>` | 9 |
| `Novel` | 0 |
| `Out-of-scope` | 1 |
| **Total** | **17** |

Extended rows: R25, R29, R38, R42, RS3, RT9, RT10.

## No detection hook this round

Folding.md requires recording why a folded lesson ships without a mechanical detector, so
the next round does not re-litigate it. All seven extensions were assessed and none is
decidable by a regex or AST scan over a diff with acceptable false-positive rates:

- **RT9, RT10** are judgment calls by construction. `check-deny-only-guard.sh` already
  documents that RT10 clause 1's *adjacency* is not mechanically decidable; extension 6
  makes the deny side symmetric, which inherits the same limitation. Deciding whether a
  twin-parity assertion is "closed under superset" requires knowing which literal is
  canonical, which lives in the project's own design.
- **R25, R38, R42** turn on facts outside the diff: which processes read a stored item,
  whether a persisted state has an operator reset anywhere in the product, whether a
  defaulted parameter's default is the unprotected implementation. A scan sees the
  declaration, not the deployment.
- **RS3** is the closest call. A detector for "a cast on a parsed request body treated as
  validation" is expressible per-language, but the useful half of the extension — auditing
  each type-specific sanitizer's off-type behaviour — is a semantic question, and a hook
  covering only the cast would report clean on the sanitizers, which is the fail-green
  direction RT7 exists to prevent.
- **R29** has nothing to match on: the defect is the *absence* of a reproducing command
  beside a number in prose.
