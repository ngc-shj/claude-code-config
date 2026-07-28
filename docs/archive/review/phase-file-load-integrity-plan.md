# Plan: phase-file-load-integrity

Make a partial read of a triangulate phase file self-detectable by the agent that read it,
instead of silently invisible.

*Revision 4 — incorporates plan-review rounds 1 (21 merged findings), 2 (25) and 3 (21); all 67
accepted, none skipped.*
*r1 → r2: the `end:` key removed (it planted the terminator token in the always-surviving region,
making the reader's check vacuously true), the terminator convention moved to `SKILL.md`, the
heading scan made fence-aware, `common-rules.digest.md` pulled into scope (C7), the installed
skill copy guarded (C6).*
*r2 → r3: sub-checks decomposed into individually-fixtured clauses, fence matching widened to
indented fences, terminator uniqueness given a loose second scan, the terminator token given a
single source of truth, C6's message corrected for unmanaged skills, the staged installed-layout
test corrected (as first specified it exits 1).*
*r3 → r4: `$HOME` normalized in `block-sensitive-files.sh` (a trailing slash silently fails the
guard open — executed), the uniqueness scan made structural rather than an enumeration of the
evasions that happened to be tried, 8h.4 made disjoint from 8h.1/8h.3 so both can be isolated,
`SKILL.md` given one canonical declaration line as the sole extraction target, 8j decomposed into
four clauses, gating restated by dependency, and the isolation matrix corrected and marked
provisional-pending-execution.*

**Gate decision (recorded, not implicit)**: rounds 1-3 each closed the previous round's design
findings and found no new bypass of the *design* in r3 — every r3 Major except the `$HOME` one is
an accounting error in the fixture matrix, which is a prediction of runtime behaviour. This plan's
own Testing strategy forbids writing a "red-proves" claim before executing it, so continuing to
review that matrix in plan-space contradicts the plan's own discipline. The gate is therefore
locked here and the matrix carried into Phase 2 as provisional; the per-clause ablation runs
settle every remaining cell empirically, and any contradiction is recorded in the deviation log
rather than argued in advance. Phase 3 reviews the implementation, which is a stronger check on
these cells than a fourth plan round.

## Project context

- **Type**: `config-only` (shell hooks + markdown skill/rule definitions; no application code)
- **Test infrastructure**: `unit tests only` — `bats tests/*.bats`, run locally. There is no
  `.github/workflows/`, so bats IS the gate.
- **Verification environment constraints**:
  - `VE1` — No CI. Every gate must be reachable from `bats tests/`. Status of all contracts:
    `verifiable-local`, including the installed-layout check (C5's staged run).
  - `VE2` — Ollama is a soft dependency. Not touched by this change.
  - `VE3` — **One obligation is not mechanically verifiable: invariant I9 — that the reading
    agent actually performs the check `SKILL.md` instructs.** `blocked-deferred`. Anti-Deferral
    cost-justification: a harness for it means replaying skill invocations against a live model
    and asserting on tool-call sequences — an order of magnitude larger than this change, with a
    nondeterministic oracle. **VE3 covers I9 and nothing else**; every other part of C3 is a grep
    and is gated in C4/C5.
  - `VE4` — **Step *content* is not gated.** Every check here verifies the heading skeleton:
    which steps exist, in what order, that none is hidden. Emptying Step 3-3's body, or rewriting
    it to permit inline self-review, leaves every check green. That residue belongs to human diff
    review and I9. Recorded because r1's rationale for fence awareness read as though it closed
    this; it closes only the heading-relocation variant.

## Objective

A triangulate phase file that is read only in part must be detectable as such **by the reader,
from the bytes it did receive**. Today it is not: the phase files carry no declaration of what
they contain and no terminator, so a first-page-only read is indistinguishable from a complete
one.

## Background — the observed failure

In a prior session the orchestrator entered Phase 3, read `phases/phase-3-review.md` only in
part, and skipped **Step 3-3** (launching the three expert sub-agents), substituting an inline
self-review. The phase reported complete. Nothing in the file, the skill, or the hooks could have
caught this.

**Layer 1 — the read channel truncates silently.** Bash tool output passes through the `rtk`
compressing proxy (`global/RTK.md`). Reproduced in this repo:

```
$ for f in skills/triangulate/phases/*.md; do echo "--- $f"; head -3 "$f"; done
--- skills/triangulate/phases/phase-1-plan.md
## Phase 1: Plan Creation, Review & Commit
[362 more lines]
```

**Exactly one line survives**, followed by a marker that reads like ordinary elision. (The same
`head -3` as a bare command returns three real lines; inside a compound command it collapses.)
The `Read` tool does not do this.

**Layer 2 — the content is unfalsifiable.** Even given a truncated read there is nothing to
compare against. `phases/*.md` have no front matter and end on a bare `---` rule. "How many steps
does Phase 3 have?" exists *only* inside the region that was cut off.

### Coverage, per channel

| Channel | What survives | What detects the truncation |
|---|---|---|
| `Read` with `limit`/`offset`, context compaction, a paste that dropped the tail | the head of the file | **the manifest** (C1) — step count and IDs present, terminator absent |
| Bash whole-file dump through the `rtk` proxy | line 1 only (`---`) | **only** the standing terminator rule in `SKILL.md` (C3), loaded in full every session; and `SC3` if built |

On the Bash channel the change is a small regression in what line 1 *says*: today
`## Phase 1: …`, after C1 `---`. Accepted: front matter only has the always-arrives property at
byte 0, and that channel is covered by C3's standing rule rather than by file content. Stated
plainly because a reader who believes the manifest covers this channel will under-weight C3 and
SC3, which are what actually cover it.

## Prior art inside this repo

`phases/phase-3-review.md:51` already mandates this discipline — for *Ollama* output — and
`:56-59` checks it correctly: `sed '/^[[:space:]]*$/d' | tail -1 | grep -q '^## END-OF-ANALYSIS$'`
— anchored, full-line, last-non-empty-line, never a substring scan. The skill distrusts a
truncated file from a local model and trusts a truncated file describing its own procedure. This
change applies the skill's own pattern to the skill's own procedure files, in the same anchored,
tail-bound form.

## Requirements

**Functional**

- F1: Each `phases/phase-N-*.md` declares at byte 0 what a complete read contains: phase number,
  title, step count, step IDs, and the step that has no substitute.
- F2: Each `phases/phase-N-*.md` ends with a terminator identifying which file ended, appearing
  exactly once, with no earlier line a reader could mistake for it.
- F3: `SKILL.md` obliges the reader to (a) use `Read` for phase files, (b) confirm the last line
  received is the terminator, (c) reconcile executed steps against the declared step IDs before
  reporting the phase complete. The terminator convention is stated in `SKILL.md` — not read out
  of the file being checked — and `SKILL.md` is the single source of the token.
- F4: Every declaration in F1/F2/F3 is machine-verified **at clause granularity**. Metadata
  nobody checks is decoration, and decoration that looks like a gate is worse than nothing (RT7).

**Non-functional**

- N1: `SKILL.md` grows by ≤ 12 lines; no other always-loaded context is added.
- N2: No new hook process, no new `settings.json` wiring, no new install-time step.
- N3: Both layouts pass — the repo copy and the `cp -r`-installed `~/.claude` copy (RT9 twins) —
  exercised through the **zero-argument** self-relative default (`check-rule-sync.sh:36`), which
  no test covers today.

## Technical approach

**The manifest lives in the phase file**, at byte 0, adjacent to the headings it must agree with.
A step list in `SKILL.md` would be a second copy drifting independently.

**The terminator convention lives in `SKILL.md`**, and `SKILL.md` is the *only* place the token
literal is authored. r1 put an `end:` key in the front matter so the reader could learn the token
from the region that always arrives — backwards: that plants the very token the reader searches
for in the region that always arrives, so "did I see the terminator?" answers yes on every
truncated read. `SKILL.md` is loaded in full every session, so the convention is already standing
knowledge. The linter *derives* the expected token from `SKILL.md` and compares by equality
everywhere else (8j), so the token cannot drift between prose, phase files, and digest.

**Two ends, two questions.** The front matter answers *what should be here*; the terminator
answers *did I get all of it*.

**Verification joins the existing linter.** `hooks/check-rule-sync.sh` exists to catch
declaration-vs-content drift across these files, has a `drift()` shape and a 0/1/2 exit contract,
and is already permitted in `settings.json:165-166` in both invocation forms.

## Contracts

### C1 — Phase-file front matter

**Shape** — the first bytes of each `skills/triangulate/phases/phase-N-*.md`:

```
---
phase: 3
title: "Phase 3: Code Review, Fix & Commit"
steps: 9
step_ids: 3-1, 3-2, 3-3, 3-4, 3-5, 3-6, 3-7, 3-8, 3-9
core: 3-3 — code review by three expert sub-agents launched in parallel; inline self-review by the orchestrator is not a substitute
---
```

That is the literal, fully expanded form for `phase-3-review.md`. The other two:

| File | phase | steps | step_ids (literal) | core |
|---|---|---|---|---|
| `phase-1-plan.md` | 1 | 7 | `1-1, 1-2, 1-3, 1-4, 1-5, 1-6, 1-7` | `1-4` — plan review by three expert sub-agents launched in parallel |
| `phase-2-coding.md` | 2 | 5 | `2-1, 2-2, 2-3, 2-4, 2-5` | `2-5` — focused recurring-rule self-check before the phase reports complete |

Counts verified against `grep -cE '^### Step [0-9]+-[0-9]+'` → 7 / 5 / 9.

- Five keys, exactly. There is **no `end:` key**.
- `title` is double-quoted: the real titles contain `": "`, not a valid YAML plain scalar in a
  mapping value. Nothing parses these blocks as YAML today, but the first tool that does must not
  error (R40).
- `step_ids` is a comma-separated inline list — regex-checkable, no `yq`, bash-3.2 clean.
- **Step-ID grammar**: `[0-9]+-[0-9]+[a-z]?`. No suffixed heading exists today, but
  `phase-3-review.md` already treats Step 3-2b as an executable unit in prose (`:37`, `:38`,
  `:257`). Once a sub-step becomes a `### Step` heading it **is** a member of `step_ids`.
- `step_ids` is the payload that matters under truncation: precisely what a cut-off read loses.

**Invariants** — all machine-enforced by C4 unless marked otherwise:

- I1: `steps` equals the number of `### Step` headings, counted **outside fenced code blocks**.
- I2: `step_ids`, in order, equals those headings' IDs.
- I3: `phase` equals the `N` in the filename.
- I4: the key set is exactly `{phase, title, steps, step_ids, core}` — no missing key and **no
  extra key**.
- I5: `title` equals the first `^## ` heading after the front matter.
- I6: `core`'s leading step ID is in `step_ids` and resolves to a counted, out-of-fence heading.
- I7 (R42 member-set): the class is "files under `skills/triangulate/phases/`". Code-derived:
  `ls skills/triangulate/phases/*.md` → three members. C4 sweeps the directory rather than the
  fixed `PHASE1/PHASE2/PHASE3` triple, so a fourth phase file is covered without a linter edit.

**Forbidden patterns**

- `pattern: ^[a-z_]+:[[:space:]]*$` within the front-matter window — reason: an empty required
  key is drift wearing the shape of compliance. *Ownership: clause 8a.3 (the interior line-shape
  rule), not 8b.* r2 found r1 assigned this to 8b while 8a's shape rule rejects it first, making
  the 8b fixture red three sub-checks.

**Acceptance criteria**

- `head -1` is `---`; lines 2-6 are the five keys; line 7 is `---`.
- `bash hooks/check-rule-sync.sh` exits 0 on the repo; exits 1 with the matching `DRIFT:` line
  after any single-clause mutation (see C5's isolation matrix).
- **Skill-loader inertness, measured not argued**: record `ls ~/.claude/skills/` before and after
  `install.sh` and confirm it is unchanged and that no loader warning mentions a phase file. r1
  claimed this was "verified against `install.sh:227`", which established only which
  *directories* become skills.

**Consumer-flow walkthrough**

- Consumer A — `hooks/check-rule-sync.sh` reads `{phase, title, steps, step_ids, core}`: `steps`/
  `step_ids` against fence-filtered `### Step` headings, `phase` against the filename, `title`
  against the first `## ` heading, `core` against `step_ids` and the heading set. None is
  presence-only.
- Consumer B — the orchestrating agent reads `{step_ids, core}` to reconcile what it executed and
  to know which omission is disqualifying. It does **not** read a terminator name from the file.
- Consumer C — `install.sh:225-235` copies the directory verbatim (`cp -r`); reads no field.
- Consumer D — the Claude Code skill loader. Premise: it parses front matter from
  `skills/*/SKILL.md` only. Evidence: the empirical before/after check above.
- Consumer E — `hooks/generate-triangulate-rule-digest.sh` reads `common-rules.md` only.

### C2 — Phase-file terminator

**Shape**: the last non-empty line of each `phases/phase-N-*.md` is exactly `## END-OF-PHASE-<N>`,
where the token stem comes from `SKILL.md` (C3) and `<N>` from the filename.

The existing trailing `---` horizontal rule is **removed**. r1 kept it, which left three `^---$`
lines per file and made "the front matter has a closing `---`" satisfiable by a rule ~490 lines
away. With it gone each file has exactly two, both in the front matter.

**Invariants**

- I8a: exactly one line matches `^## END-OF-PHASE-[0-9]+$`.
- I8b: that line's `<N>` equals the filename's `<N>`.
- I8c: that line is the last non-empty line (trailing blanks stripped, as
  `phase-3-review.md:56-58` does for `END-OF-ANALYSIS`).
- I8d: **no earlier line could be mistaken for a terminator**. The strict anchored pattern above
  is right for presence; it is the wrong tool for uniqueness, because the entity that must not be
  fooled is a model reading rendered markdown, not `grep`. Executed against r2's spec, all of
  these passed a strict-anchor uniqueness count while remaining fully legible as a terminator:
  `## END-OF-PHASE-3 ` (trailing space), `  ## END-OF-PHASE-3` (indented ≤ 3 spaces — still an ATX
  heading), `## END‐OF‐PHASE‐3` (U+2010 hyphens). So the uniqueness scan is deliberately **loose**,
  and **structural rather than enumerated**: strip every non-alphanumeric character from the line,
  case-fold it, and drift if it contains the stem's own alphanumeric reduction (`endofphase`).
  r3 executed the enumerated form r2 specified (whitespace + `\r` + unicode dashes) and showed it
  still evades on a zero-width space inside the stem — invisible when rendered, which is exactly
  the property this clause exists to defeat. The structural reduction catches every case the
  enumerated one catches, plus ZWSP, at the same cost, and was verified not to false-positive on
  the six real `END-OF-ANALYSIS` occurrences in `phase-3-review.md` (`endofanalysis` ≠
  `endofphase`). **Letter homoglyphs (Cyrillic `О` for `O`) are out of scope**, resolved by the
  drift-not-tamper boundary this plan draws in Considerations: closing them needs transliteration,
  out of reach under I18's bash 3.2 / BSD constraint.
  Over-approximating what a reader might mistake for a terminator is the fail-closed direction: a
  false positive costs a contributor one rephrase, a false negative costs the mechanism.
- I8e: **8h.4 excludes lines matching 8h.1's strict pattern.** Without this the loose scan is a
  strict superset of both 8h.1 (an exact mid-file duplicate is by definition non-final and
  contains the stem) and 8h.3 (a terminator that is not last becomes itself a non-final line
  containing the stem), so neither clause can ever be isolated by a fixture — r3 found this on
  both. The exclusion loses nothing: a line matching the strict pattern is already 8h.1's case.
  It also keeps the two diagnostics distinct — "duplicate terminator" vs "terminator lookalike".

**Acceptance criteria**

- `sed '/^[[:space:]]*$/d' <file> | tail -1` equals `## END-OF-PHASE-N`.
- `grep -c '^## END-OF-PHASE-[0-9]\+$' <file>` equals 1 — anchored full-line count; the unanchored
  form counts *matching lines* and under-reports a same-line duplicate.

### C3 — SKILL.md loading protocol clause

**Shape**: ≤ 12 lines added to `skills/triangulate/SKILL.md` after the existing **Loading
protocol** paragraph:

1. Read phase files and `common-rules.digest.md` with the `Read` tool, whole-file. Do not
   `cat`/`head` them through Bash — Bash output passes through an output-compressing proxy that
   can render a 500-line file as its first line plus `[N more lines]`.
2. Every phase file's last line is `## END-OF-PHASE-<N>`; `common-rules.digest.md`'s last line is
   `## END-OF-DIGEST`. If the last line you received is not that terminator, the read was
   partial: re-read before acting on it.
3. Before reporting a phase complete, reconcile the steps you executed against the `step_ids:` in
   that phase's front matter. An unexecuted ID means the phase is not complete. The step named in
   `core:` has no substitute — inline work by the orchestrator does not discharge it.

**Authoring constraints on this clause** (they are what makes 8i/8j implementable):

- The clause ends with one **canonical declaration line**, which is the sole extraction target
  for both 8i and 8j:

  ```
  Manifest keys: `step_ids:`, `core:`. Terminator stems: `END-OF-PHASE` (phase files), `END-OF-DIGEST` (the digest).
  ```

  r3 found that r3's own draft contradicted itself here — the constraint said "bare tokens" while
  the clause body wrote them decorated as `` `## END-OF-PHASE-<N>` `` — leaving 8j with nothing
  well-defined to extract. One explicit declaration line resolves it and costs one line against
  N1's budget; the prose above stays readable in its decorated form.
- **The extraction region is that declaration line only** — not "the clause", whose boundaries r3
  showed were never defined. This matters more than it looks: `skills/triangulate/SKILL.md`
  currently contains **zero** backticked colon-suffixed tokens, so whole-file and region-scoped
  extraction are indistinguishable on day one and the ambiguity would survive every test. The
  first unrelated `` `paths:` ``-style token added anywhere in `SKILL.md` would otherwise inject a
  phantom key and fire 8i on all three *good* phase files.
- Front-matter keys are named backticked and colon-suffixed; 8i extracts exactly `` `[a-z_]\+:` ``
  from the declaration line. r2 showed that without a canonical form the natural extractor yields
  `{core}` only — silently dropping `step_ids`, the more likely rename target — while a looser one
  yields `{read, cat, head, …}` and fires on the good file.
- Terminator stems are compared by **equality** at every other site, never containment.
- `SKILL.md:45`'s existing sentence ("Each phase file ends with a summary and a pointer to the
  next phase") is amended in the same edit to "…and its `## END-OF-PHASE-N` terminator as the
  final line" — after C2 the two statements about how a phase file ends otherwise contradict each
  other inside the one file the design treats as standing truth.

**Invariants**

- I9 (app-enforced, runtime, unverifiable — VE3): the reader performs the check. No
  schema-enforced equivalent exists; the actor is a model. C1/C2/C4 guarantee the *data* the
  obligation reads, confining the residual risk to a model skipping an instruction it was given.
- I10 (8j.1): the clause exists and names `Read`.
- I11 (8i): every front-matter key the declaration line names is present in every phase file's
  front matter — closing the direction where a key is renamed in C1 *and* in the linter while
  `SKILL.md` keeps pointing at the old name.
- I12 (8j.4): `SKILL.md` contains no `^### Step` enumeration. The manifest has one home. (This is
  why r2's `wc -l` bound was dropped in favour of a content check — an argument that only holds if
  the content check is itself fixtured, which r3 found it was not.)
- I13 (8j.2, 8j.3): the terminator stems declared in `SKILL.md` are the single source, and every
  *comparison* — 8h's and C7's alike — uses the extracted values.
- I28 (restated after r3): the linter necessarily holds the two **role anchors** (`PHASE`,
  `DIGEST`) — nothing else distinguishes which extracted stem 8h uses from which one the digest
  assertion uses, so "no literal in the linter" was unachievable as r3 stated it. The obtainable
  and still-useful property is the one this contract needs: renaming the token in the phase files
  and the linter together still reds against a stale `SKILL.md`.
- I29: **a stem that fails to extract is drift with its own message, evaluated before 8h runs for
  any file, and short-circuits 8h entirely for that run.** Without this an empty stem makes 8h.4's
  containment test match every line of every phase file — hundreds of drift lines burying the real
  diagnosis, and a fixture whose substring assertion could pass for the wrong reason (I19).

**Acceptance criteria**: 8i, 8j green on the repo, each red-proven by its own fixture. (r1's
`wc -l ≤ 55` bound is dropped — a line count is the wrong instrument, and I12's content check is
the repo's own idiom for this concern, cf. `tests/install.bats:285-295`.)

**Consumer-flow walkthrough**

- Consumer B reads the three obligations and gates its phase-completion report on them. Every
  field it must then read (`step_ids`, `core`) is in C1's locked shape; the terminator stem comes
  from this clause. I11/I13 keep that true over time.
- Consumer F — `check-rule-sync.sh` checks 3, 4, 5 and 6. Verified inert: the added clause, the
  front matter, and both terminators contain no `R`/`RS`/`RT`-plus-digit token.

### C4 — `hooks/check-rule-sync.sh` check 8: phase manifest

**Signature**: no new script, no new argument, no new exit code. A block before the `fail`
trailer, emitting `DRIFT: ...` through the existing `drift()` helper.

Clauses, for each file matched by `"$SKILL_DIR"/phases/phase-*.md`.

**Gating is by dependency, not by letter span** (r3: r3's own "8a gates 8b-8i" swept in a clause
whose stated rationale did not cover it):

- A file failing any 8a clause skips **8b-8g and 8i** — the clauses that read the parsed
  front-matter window, which does not exist.
- Within 8a: 8a.1 gates 8a.2, and 8a.2 gates 8a.3. (Without this, whether `8a-open` also reds
  8a.3 is implementation-dependent, and two matrix cells are undetermined.)
- **8h runs unconditionally.** Its inputs are the filename and the stem from `SKILL.md`; it needs
  no window. A file with both a malformed front matter and a missing terminator should report both
  in one run — the terminator is the clause a partial reader actually depends on.
- Within 8h: 8h.1 gates 8h.2 and 8h.3 (both say "*that* line", which presupposes exactly one
  match). 8h.4 is independent of all three.
- 8j is per-run, and per I29 its stem-extraction failure short-circuits 8h for the whole run.

| Clause | Check |
|---|---|
| 8a.1 | line 1 is `---` |
| 8a.2 | the closing `---` is the next `^---$`, at line ≤ 10 |
| 8a.3 | every line between matches `^[a-z_]+: .+$` (this owns the empty-value case) |
| 8b | the key set is exactly `{phase, title, steps, step_ids, core}` — no missing, no extra (I4) |
| 8c | `phase` equals the filename's `<N>` |
| 8d | `steps` equals the count of out-of-fence `^### Step [0-9]+-[0-9]+[a-z]?` headings |
| 8e | `step_ids` equals those heading IDs, **in order** |
| 8f | `title` equals the first `^## ` heading after the front matter |
| 8g | `core`'s leading step ID is in `step_ids` and resolves to a counted heading |
| 8h.1 | exactly one `^## <stem>-[0-9]+$` line (strict anchor) |
| 8h.2 | its `<N>` equals the filename's `<N>` |
| 8h.3 | it is the last non-empty line |
| 8h.4 | no earlier line *resembles* a terminator — loose structural scan, excluding lines that match 8h.1's strict pattern (I8d, I8e) |
| 8i | every front-matter key named in `SKILL.md`'s declaration line is present in this file's front matter |
| 8j.1 | `SKILL.md` names `Read` |
| 8j.2 | `SKILL.md` declares the `END-OF-PHASE` stem — the value 8h compares against |
| 8j.3 | `SKILL.md` declares the `END-OF-DIGEST` stem — the value the digest assertion compares against |
| 8j.4 | `SKILL.md` contains no `^### Step` line (I12) |

Drift messages follow the existing shape: `<base>: <what was declared> vs <what the file has>`.
r3 decomposed 8j for the same reason 8h was decomposed a revision earlier: as one clause with one
fixture, three of its four properties — including I12, the invariant that justified dropping the
`wc -l` bound — had no mutation that reds them.

**Invariants**

- I14 — **`<N>` comes from the filename, for 8c and 8h only.** 8d and 8e use the generic ID
  pattern `[0-9]+-[0-9]+[a-z]?` and compare the extracted IDs against `step_ids`, so `phase:`
  never enters either. r3 showed that binding 8d/8e to the filename's `<N>` would make the base
  fixture's fenced decoy inert in two of the three fixture files (a `### Step 1-9` decoy cannot
  inflate a count that only matches `### Step 2-…`), collapsing the decoy's coverage to one third.
- I15 — **fence awareness**, anchored `^[[:space:]]*` + triple backtick. Not `^```: the phase
  files already contain **12 indented fences** (`phase-2-coding.md` 10, `phase-1-plan.md` 2, all
  balanced list-item blocks, none nested inside a column-0 fence). A column-0-only toggle never
  fires on them, and r2 executed the resulting bypass: a real `### Step` heading moved into an
  indented fence leaves 8d, 8e, 8g and 8h all passing while the instruction is gone. Verified free
  of regression: the whitespace-tolerant toggle yields 7 / 5 / 9 — identical to the naive one and
  to the declared values. Additionally, an unbalanced fence state at EOF is drift (a cheap desync
  tripwire, fail-closed).
- I16 — **fail-closed comes from the preflight, and is recorded as such**: the loop at
  `check-rule-sync.sh:45-50` exits 2 when any of `ALL_FILES` is missing, and `ALL_FILES` names the
  three phase files, so check 8's glob can never be empty. The literal-glob guard
  (`[ -e "$f" ] || continue`) is retained as defence-in-depth with an inline
  "unreachable by construction" comment and is **not** listed among the mutation-proven gates. The
  phases directory is added to that preflight. **Removing the three phase paths from `ALL_FILES`
  would break this guarantee** — recorded because that is the refactor a directory sweep invites.
- I17 — **no `exit` of any status inside the new block**. r1 forbade only `exit 0`; an `exit 2`
  would discard a `fail=1` accumulated by checks 1-7, reporting real rule-ID drift as
  "missing/unparsable" and suppressing the summary (R44). `retrospect/pipeline.md:118` and
  `folding.md:91` gate on this status.
- I18 — bash 3.2 / BSD portable: no associative arrays, no `mapfile`/`readarray`, no `sed -i`.

**Forbidden patterns**

- `pattern: mapfile|readarray|declare -A|sed -i` — reason: breaks stock-macOS bash 3.2 / BSD sed.
  (No trailing space: `sed -i.bak` and `sed -i''` must match.)
- *(Conceptual, verified by reading the block)*: any `exit` inside check 8 — see I17.

**Acceptance criteria**

- `bash hooks/check-rule-sync.sh` exits 0 against `skills/triangulate/` after C1/C2.
- Every clause in the table is red-proven by the fixture named for it in C5's matrix, per the
  per-clause ablation procedure — demonstrated, not asserted.
- The closing "Sync points:" summary names the phase manifest.

**Consumer-flow walkthrough**

- Consumer G — `tests/check-rule-sync.bats` reads `{exit status, stdout DRIFT lines}`, using the
  substring to identify which clause fired.
- Consumer H — a human running `bash ~/.claude/hooks/check-rule-sync.sh`; permitted at
  `settings.json:165-166` in both forms.

### C5 — `tests/check-rule-sync.bats`: fixture repair + fixtures

**Hard coupling**: `setup()` today writes fixture phase files with no front matter, no
`### Step` headings and no terminator, and a two-line `$FIX/SKILL.md` (`:61-64`) containing none
of the required tokens. Precisely: the file has 20 `@test` blocks; the **two** `status -eq 0`
fixture assertions (`:100`, `:247`) go red the moment C4 lands, and 8j would additionally pollute
the output of the 14 drift tests. The 14 survive on status because each also asserts its own
`DRIFT:` substring — the only reason they stay honest while the fixture globally drifts. The three
exit-2 tests short-circuit at the preflight.

**Fixture repair**

- Each fixture phase file gets valid front matter, **three** `### Step N-1/N-2/N-3` headings, and
  a terminator. Three, not one: no mutation of a one-element `step_ids` distinguishes an ordered
  comparison from a sorted-set or a count, and a one-step fixture resembles no real phase file
  (RT1).
- Each fixture phase file also gets a **fenced decoy**: an indented fenced block containing
  `### Step <N>-9`, matching that fixture file's own phase number, with `steps: 3` and
  `step_ids: <N>-1, <N>-2, <N>-3` unchanged. Per-file `<N>`, not a fixed `1-9`: r3 showed a fixed
  ID is inert in two of the three files under a filename-bound reading of 8d (now excluded by
  I14, but the per-file form is correct under either reading and costs nothing).
  Why the decoy exists at all: measured on the real files, fence awareness is currently a
  **no-op** — `grep -cE '^### Step [0-9]+-[0-9]+'` already returns 7/5/9, because the fenced `###`
  lines are `### Functionality expert` and `##### MANUAL CHECKS`, not step headings. Without a
  decoy in the base fixture, every pass test is invariant under I15 and only one directional
  fixture proves it. With it, a non-fence-aware implementation counts 4 headings, so **the two
  pass tests and the `8d` fixture** go red — r3 walked this and corrected r3's own claim, which
  had also named `8e-sub` and `8e-perm` (both keep passing: their asserted 8e substring is present
  either way). (`phase-3-review.md:430` already carries `### [Finding number] …` inside a fenced
  template, so a step-shaped fenced line is one edit away.)
- `$FIX` gains a **`common-rules.digest.md`**, generated in `setup()` from the fixture's own
  `common-rules.md`. Two reasons: check 7 currently never executes in any fixture test
  (`check-rule-sync.sh:206` guards it with `[ -f "$DIGEST" ]` and `$FIX` has no digest), and
  without a fixture digest the `END-OF-DIGEST` stem's equality (I13/I28) has no fixture home —
  C7's assertions all live in `tests/triangulate-rule-digest.bats` and compare against a literal.
- **`>>` into a fixture phase file is no longer a body append.** After the repair the terminator is
  the last line, so `tests/check-rule-sync.bats:189` and `:196` — which append with `>>` — would
  land *after* it and trip 8h.3 and 8h.4 in addition to the check each exists for. Both still pass
  (each asserts its own substring), but they become undocumented multi-trip fixtures in a plan
  whose central artifact is a matrix of exactly that. Change both to insert **before** the
  terminator via a `setup()` helper (`append_body <file> <line>`). `:203` appends to
  `$FIX/SKILL.md` and is safe — verified: the added text introduces no `^### Step` line and no
  backticked colon token.
- `$FIX/SKILL.md` gains a minimal loading-protocol clause naming `Read`, `` `step_ids:` ``,
  `` `core:` ``, `END-OF-PHASE`, `END-OF-DIGEST`. Without it 8j fires on every test and — worse —
  8i **degrades open**: its derived key set is empty, so it checks nothing and reports PASS.
  Verified safe against check 5's dangling-rule grep: none of those tokens contains `R`/`RS`/`RT`
  followed by a digit.
- The terminator stem and key names are hoisted into `setup()` variables (RT3).

**Fixtures and isolation matrix** — each asserts `status -eq 1` **and** its own `DRIFT:` substring
(I19). Every clause has at least one fixture that isolates it. Mutation targets are pinned where
r3 showed the choice decides the outcome:

| Fixture | Mutation | Isolates | Also reds |
|---|---|---|---|
| `8a-open` | delete line 1's `---` | 8a.1 | — (8a.1 gates 8a.2/8a.3; 8a gates 8b-8g, 8i) |
| `8a-close` | delete the closing `---` only | 8a.2 | — (gated) |
| `8a-empty` | blank out `core:`'s value | 8a.3 | — (gated) |
| `8b-extra` | insert a sixth key `extra: x` | 8b, and I4's no-extra-key clause | — (line matches 8a.3; closing `---` moves to line 8, still ≤ 10; both SKILL.md-named keys still present, so 8i is green) |
| `8c` | `phase: 1` → `phase: 9` | 8c | — (I14: 8d/8e use the generic ID pattern) |
| `8d` | `steps: 3` → `steps: 4` (front-matter side) | 8d | — |
| `8e-sub` | substitute the **last** ID (`<N>-3` → `<N>-9`) | 8e | — (pinned to a non-`core` ID; substituting `<N>-1` would also red 8g) |
| `8e-perm` | permute `step_ids` (`<N>-1, <N>-3, <N>-2`) | 8e's ordering — the unique mutation that reds an ordered comparison and stays green under a sorted-set one | — (keeps `<N>-1` first, so `core` still resolves) |
| `8f` | alter `title:` | 8f | — |
| `8g` | `core: <N>-1 …` → `core: <N>-9 …` | 8g — and both its halves at once: `<N>-9` exists *only* inside the base fixture's fenced decoy, so it exercises "resolves to a **counted** heading" as well as "is in `step_ids`" | — |
| `fence` | move the **last** real `### Step` heading (`<N>-3`) into an indented fence | I15 | 8d, 8e (inherent — multi-trip; pinned to a non-`core` step so 8g stays green) |
| `decoy-off` | remove the fenced decoy from `setup()` | I15 from the other direction — this is the row the I15 ablation run compares against | the two pass tests and `8d` (r3-derived; not `8e-sub`/`8e-perm`) |
| `8h-dup` | insert `## END-OF-PHASE-<N>` *after* the fixture's first `## ` heading | 8h.1 | — (8h.4 excludes strict-form lines per I8e; insertion point keeps 8f, which reads the *first* `## `, green) |
| `8h-missing` | delete the terminator line | 8h.1 | — (8h.1 gates 8h.2/8h.3) |
| `8h-wrongN` | `## END-OF-PHASE-1` → `## END-OF-PHASE-7` | 8h.2 | — |
| `8h-notlast` | append a content line after the terminator | 8h.3 | — (8h.4 excludes the strict-form terminator line itself, per I8e) |
| `8h-decoy` | insert `  ## END​-OF-PHASE-1 ` mid-file (indented, trailing space, ZWSP inside the stem) | 8h.4's structural scan | — (strict count still 1) |
| `8h-stem` | change the stem `END-OF-PHASE` → `END-OF-STAGE` in the fixture `SKILL.md` **only** | I13's phase-side derivation | 8j.2 (inherent — multi-trip) |
| `8i` | rename `step_ids:` → `step_names:` in the fixture `SKILL.md` **only** | 8i | — |
| `8i-outside` | add a backticked colon token *outside* the declaration line in the fixture `SKILL.md`; assert **no drift** | the region scoping — the only fixture distinguishing a region-scoped extractor from a whole-file one | n/a (negative fixture) |
| `8j-read` | delete `Read` from the fixture `SKILL.md` | 8j.1 | — |
| `8j-phase` | delete the `END-OF-PHASE` stem from the declaration line | 8j.2 | 8h short-circuits with one "stem unavailable" line (I29) |
| `8j-digest` | change `END-OF-DIGEST` → `END-OF-INDEX` in the fixture `SKILL.md` | 8j.3 and I28's digest-side equality, against the `$FIX` digest | — |
| `8j-step` | `printf '### Step 1-1\n' >> "$FIX/SKILL.md"` | 8j.4 / I12 | — |
| `sweep` | write `$FIX/phases/phase-4-extra.md` with no manifest | I7's directory sweep — the only assertion distinguishing it from a hard-coded triple | 8h (the stray file has no terminator; 8h runs ungated) |

Notes the matrix encodes deliberately:

- **`8i`, `8h-stem` and the `8j-*` family mutate `SKILL.md`, not the phase file.** A mutation on
  the phase-file side reds 8b/8e independently *and* reds identically under a hardcoded
  implementation, so it can prove neither isolation nor the cross-file derivation. `8h-stem` is
  the sharp case r3 found: deleting the stem reds under both a derived and a hardcoded linter;
  only *changing* it separates them.
- **`8b-extra` adds a key rather than blanking one.** Blanking is 8a.3's case.
- **The "Also reds" column is a prediction, not an observation.** Per this plan's own rule that no
  "red-proves" claim is written before execution, these cells are provisional: the Phase 2
  per-clause ablation runs are what settle them, and any cell the runs contradict is corrected in
  the deviation log rather than argued about in advance.

**Installed-layout / zero-argument coverage (N3)**: stage **both** `hooks/check-rule-sync.sh`
**and** `hooks/generate-triangulate-rule-digest.sh` plus the real `skills/triangulate/` under
`$BATS_TEST_TMPDIR/inst/`, `cd` elsewhere, invoke with **no argument**, assert exit 0 and `OK:`.
Staging both is required, not incidental: r2 executed r1's single-hook version and it exits **1**
with `DRIFT: common-rules.digest.md exists but digest generator is missing`
(`check-rule-sync.sh:204-212`). It is also the fidelity-correct shape — the installed layout
contains both hooks (RT9). Do not "fix" it by deleting the digest from the staged copy; that
silently drops check 7 from the installed-layout run.

**Invariants**

- I19 (RT8): every fixture asserts its specific `DRIFT:` substring, not the status alone.
- I20 (RT7): each **clause** is ablation-proven per Testing strategy.
- I21: the live-repo pass test continues to exit 0.

### C6 — Guard the installed skill copy in `block-sensitive-files.sh`

r1's scenario S5 asserted the hook already guards the installed copies. It does not:
`block-sensitive-files.sh:73-82` matches only `$HOME/.claude/hooks/*.sh`,
`$HOME/.claude/settings.json` and `$HOME/.claude/CLAUDE.md`. `~/.claude/skills/**` appears in no
case arm in any hook — so Step 3-3 could be stripped from the *installed* `phase-3-review.md`
with every check in this repo green.

**Shape**: add `"$CLAUDE_HOME/skills/"*` to the expanded arm and `"~/.claude/skills/"*` to the
literal-tilde arm (r1 said to add the `$HOME` form to both, which would be a no-op duplicate in
the tilde arm). Case globs match `/`, so nested paths are covered.

**`$HOME` must be normalized once, for every arm — not just the new one.** r3 executed this
against the hook as it stands today:

```
HOME=/home/<user>    -> BLOCKED
HOME=/home/<user>/   -> *** ALLOWED (fail-open) ***
```

A trailing slash yields the pattern `…//.claude/skills/*`, which never matches the single-slash
path the tool reports: the guard silently disappears, with no error and no drift. And with `HOME`
unset, `set -euo pipefail` (`block-sensitive-files.sh:5`) kills the hook at the `case` line before
any decision is emitted — taking down **every** arm, including `.env`, credentials, keys, `.git`
internals and the harness config. The existing three arms carry the identical defect, so patching
only the new one would be R3 (fix one instance of a pattern, leave the rest). Introduce once,
above the case:

```sh
CLAUDE_HOME="${HOME:?}"; CLAUDE_HOME="${CLAUDE_HOME%/}/.claude"
```

`${HOME%/}` was verified to block correctly under both shapes; `${HOME:?}` turns the unset case
into a stated precondition with a message rather than a mid-`case` crash.

**The block message for the skills arm is new text, not the existing message reused.** Verified:
`~/.claude/skills/` is **not** a mirror of the repo. `install.sh:231-236` iterates
`$SCRIPT_DIR/skills/*/` and removes only the destinations it is about to write, so skills absent
from the repo survive every install — and one does: `improve` (`~/.claude/skills/improve/` exists;
`git log -- skills/improve` is empty). Reusing the existing "the repo is the source of truth —
edit there and run `install.sh`" text would give factually unfollowable guidance for that skill,
leaving the user two bad escapes: disable the hook wholesale in `settings.local.json` (which
simultaneously un-blocks `.env`, credentials, keys, `.git` internals and the harness config), or
route the edit through Bash — training the exact bypass SC4 documents. The skills-arm message
therefore names both cases: repo-managed skills are edited in the repo and installed; a skill with
no repo source should be added to the repo, or exempted via `settings.local.json`.

The axis against the alternative (enumerate the nine repo-managed skill names in the case arm):
that fails open for every *newly added* repo skill until someone updates the hook — drift of
exactly the class this plan exists to prevent. Message accuracy is the cheaper half to give up.

**Invariants**

- I22: `install.sh` is unaffected — it copies via `cp -r` in Bash, while the hook is wired to
  `Edit|Write|MultiEdit` only (`settings.json:200`).
- I23: `~/.claude/settings.local.json` remains unblocked (the documented override path).
- I24: the **repo** copy stays editable. This is not optional politeness — the entire
  "edit the repo, run `install.sh`" workflow and this plan's own implementation depend on it, and
  a careless arm (`*"/.claude/skills/"*` or `*"skills/"*`) would block it.

**Acceptance criteria** — five fixtures in `tests/block-sensitive-files.bats`, matching the
per-arm discipline the file already follows (`:70`/`:91` hooks, `:81`/`:96` settings.json):

1. deny: `$HOME/.claude/skills/triangulate/phases/phase-3-review.md` (expanded arm)
2. deny: `~/.claude/skills/triangulate/phases/phase-3-review.md` (literal-tilde arm)
3. deny: `$HOME/.claude/skills/improve/SKILL.md`, asserting with `grep -qF` **the specific
   sentence** about a skill with no repo source — not merely that a block occurred. r3 showed that
   with one arm and one message, a fixture asserting only "blocked" duplicates fixture 1 and pins
   no distinct branch; the verbatim-sentence form (the idiom at `tests/install.bats:266`) is what
   reds if a later message edit drops the unmanaged half.
4. approve: `<repo>/skills/triangulate/phases/phase-3-review.md` — the lookalike negative (I24),
   matching the file's convention of negatives a naive pattern would catch (`:105`)
5. deny: fixture 1's path with `HOME` set to a **trailing-slash** value — the only assertion that
   makes the normalization guarantee real. r3's key point: none of fixtures 1-4 can see this
   failure, because they all inherit the developer's ambient `$HOME`, so the control's one silent
   failure mode is invisible to the tests written to prove it (RT7).

All use the existing `run_hook` helper and the compact block-decision JSON spacing that
`tests/block-sensitive-files.bats:6-18` documents as shared across the seven `block-*.bats` files,
and must not hardcode a real home directory path (RS4).

**Why in this change rather than deferred**: scoping it out leaves the runtime-loaded artifact
governing whether the security review runs with no control at all — what the Objective claims to
close — while the fix is two case arms, one message, and four fixtures, well under the
Anti-Deferral 30-minute rule.

### C7 — `common-rules.digest.md` terminator

`SKILL.md:22` and the digest's own line 4 direct the reader to read the digest **whole**, before
every rule selection. It has no terminator, and its tail is R44-R46, **RS1-RS6**, RT1-RT9. A
truncated read silently deletes the security and testing recurring-rule sets from the routing
index, and the Recurring Issue Check then reports clean over R1-R43 only. r1 scoped this out
because check 7 already verifies the digest against the source table — a category error: check 7
verifies bytes *on disk*, while this plan's thesis is that on-disk correctness says nothing about
what the reader received. Under R42 this is the highest-value member of the "read whole,
pointer-loaded" class.

**Shape**: `hooks/generate-triangulate-rule-digest.sh` emits `## END-OF-DIGEST` as the final line
of the generated file — one `echo` **after** the awk pass, inside the existing `{ … } > "$TMP"`.

**Invariants**

- I25: staleness needs no new path — `--check` compares with `cmp -s`
  (`generate-triangulate-rule-digest.sh:50-54`), so a digest missing the terminator is already
  "stale" and `check-rule-sync.sh:206-212` routes that to `DRIFT`. **Executed**: `--check` returns
  0 on the committed digest and 1 after deleting its last line.
- I26: **position is a separate property and needs its own assertion.** `cmp -s` pins the digest
  to whatever the generator emits — including a terminator emitted in the wrong place. Move the
  `echo` above the awk pass and the terminator lands mid-file: `cmp` still matches, check 7 stays
  green, and a reader truncated past line 10 sees `## END-OF-DIGEST` and certifies a partial read
  as complete. That is the M1 bug reproduced in the digest, in the same revision that removed
  `end:` from the phase files to fix it. So: on a freshly generated digest, assert the last
  non-empty line is exactly `## END-OF-DIGEST` and that `grep -c '^## END-OF-DIGEST$'` is 1.
  (Uniqueness is genuinely lower-risk here than for phase files — the body is generated from table
  rows, not authored — but the assertion is one line and the asymmetry with 8h would otherwise be
  unexplained.)
- I27: the digest is regenerated in this change; its committed bytes must match the new generator.
- I28: `END-OF-DIGEST` is not a literal in the linter — it is the stem 8j extracts from
  `SKILL.md` (I13).

**Acceptance criteria**, all in `tests/triangulate-rule-digest.bats`:

- on the committed digest: last non-empty line is `## END-OF-DIGEST`, anchored count is 1;
- on a freshly generated digest (the staged path at `:22-33`): same two assertions — this is what
  reds when the `echo` is removed from the generator;
- **presence** red-proven by removing the `echo`; **position** red-proven by moving it above the
  awk pass; **uniqueness** red-proven by duplicating it. r3 noted that the position mutation
  leaves the count assertion green, so without the duplicate mutation the uniqueness assertion was
  a listed check outside this plan's own standard — the alternative (record it as
  defence-in-depth, explicitly not mutation-proven, the way I16 records the literal-glob guard)
  costs one line less and is acceptable if the duplicate mutation proves awkward;
- the digest-side **stem equality** (I28) is red-proven from the `$FIX` digest by the `8j-digest`
  fixture, not from these literal assertions — r3 found that all four assertions here compare
  against a hardcoded `## END-OF-DIGEST`, so none of them observes `SKILL.md`;
- the existing `--check` staleness test stays green after regeneration.

## Go/No-Go Gate

| ID | Subject | Status |
|----|---------|--------|
| C1 | Phase-file front matter — five keys, literal values for three files | locked |
| C2 | Phase-file terminator: unique, last, structurally decoy-resistant; trailing `---` removed | locked |
| C3 | SKILL.md clause (≤ 12 lines) + canonical declaration line + `:45` amendment | locked |
| C4 | `check-rule-sync.sh` check 8, clauses 8a.1-8j.4, fence-aware incl. indented, dependency gating, no `exit` | locked |
| C5 | Fixture repair (3 steps + per-file fenced decoy + SKILL.md clause + digest + `>>` fix) + 24 fixtures + staged zero-arg run | locked |
| C6 | `block-sensitive-files.sh`: `$HOME` normalized for all arms, `~/.claude/skills/` guarded with a skills-specific message + 5 fixtures | locked |
| C7 | Digest terminator emitted last + presence/position/uniqueness assertions + stem equality via `$FIX` | locked |

## Testing strategy

- **Unit (bats)**: the 24 fixtures of C5's matrix, each asserting status 1 plus its own `DRIFT:`
  substring (I19) — except `8i-outside`, which is the one negative fixture and asserts no drift;
  C6's five fixtures; C7's assertions.
- **Per-clause ablation (RT7)** — the mutation proof, at the granularity r2 showed is required.
  r1 ablated per sub-check, which is near-automatic: because I19 mandates a substring assertion,
  removing sub-check 8x always removes its substring and always fails its fixture. What that
  cannot surface is a **clause inside a sub-check with no fixture** — which is how 8h's `N`-match
  and last-line clauses, 8g's binding, and I4's no-extra-key clause all reached r2 unproven.
  Procedure, per clause: comment out that clause alone → run `bats tests/check-rule-sync.bats`
  unpiped → confirm its fixture goes green **and no other fixture does**, except where C5's matrix
  marks the fixture multi-trip → restore → re-run. Read bats' own exit status; do not judge
  through a pipe (R44). No "red-proves" claim is written into the plan or the review until the two
  runs have been executed.
- **Live-repo**: `bash hooks/check-rule-sync.sh` exit 0 on `skills/triangulate/`.
- **Zero-argument / installed-layout (N3)**: C5's staged run with both hooks.
- **Skill-loader inertness**: the empirical before/after inventory check in C1's acceptance.
- **Full suite**: `bats tests/` green-before / green-after.
- **Not tested, by declaration**: I9 (VE3) and step-body content (VE4).

## Considerations & constraints

- **The unverifiable residue is named twice and bounded**: I9 (the reader honours the instruction)
  and VE4 (what a step body says). Everything else is a clause with a fixture.
- **This is drift detection, not tamper-evidence.** The manifest lives in the same file, same
  commit, unsigned; an adversary with repo write access updates both halves in one edit and the
  gate stays green. Against careless edits and truncation — the threats in scope — it holds. C6
  narrows the installed-copy gap; it does not make the control tamper-evident.
- **Front matter is inert to every non-linter consumer** — read for `install.sh` and the digest
  generator, *measured* for the skill loader per C1's acceptance.
- **Drift risk is bounded by C4.** Adding a step without updating `steps`/`step_ids` turns the
  suite red — the reason the manifest sits next to the headings.

### Scope contract

- `SC1` — **`skills/retrospect/` sub-files** (`pipeline.md` 164 L, `folding.md` 98 L,
  `sources/*.md` 35-45 L): same class. R42 member-set for "pointer-loaded skill sub-file read as
  procedure": triangulate's 3 phase files (C1/C2) + `common-rules.md` + `common-rules.digest.md`
  (C7) + 10 `rule-details/*.md` + retrospect's 6 = **21**; 4 addressed here. Excluded from the
  class by ID rather than omission: `skills/agent-review/review-backend.sh` and
  `skills/agent-review/schemas/review-output.schema.json` — pointer targets executed or parsed by
  tools, not read as procedure. Deferred. Anti-Deferral: worst case — a truncated `pipeline.md`
  read drops late retrospect steps; likelihood — lower, the files are 3-5× shorter and
  `retrospect/SKILL.md:39-52` already carries a Step 0-9 table making a partial read partially
  falsifiable from the entry point; cost — generalizing C4 into a cross-skill manifest linter.
  Owner: follow-up issue. `TODO(phase-file-load-integrity): extend the manifest/terminator pattern to skills/retrospect/`.
- `SC2` — **`common-rules.md` and `rule-details/*.md`** get no terminator. `common-rules.md` is
  read by targeted `rg` extraction of single rows, never whole; `rule-details/*.md` are 9 lines
  each and already identity-checked against their table row (`check-rule-sync.sh:224-240`). Cost
  if wrong: one line each. Owner: same follow-up.
- `SC3` — **Mechanically blocking Bash whole-file reads of skill files** (a PreToolUse deny on
  `cat`/`head` targeting `skills/**/*.md`) is the fail-closed control for root-cause layer 1 and
  is strictly stronger than C3's prose *on that channel*. Deferred. Anti-Deferral: worst case —
  the Bash channel keeps relying on the reader honouring C3; likelihood — moderate, it is how the
  original failure happened; cost — a new deny hook plus test file plus settings wiring (N2
  excludes a new hook here), and it must not break legitimate `grep`/`rg`. It constrains only
  honest readers, not an adversary, who edits the file rather than the read. Owner: raise with the
  user after this change.
  `TODO(phase-file-load-integrity): reconsider a PreToolUse deny for Bash whole-file reads of skills/**/*.md`.
- `SC4` — **Two pre-existing bypasses of `block-sensitive-files.sh`**, neither introduced nor
  widened by C6, both recorded so C6's fixture set is knowingly bounded:
  (a) the hook is wired to `Edit|Write|MultiEdit` only (`settings.json:200`), so a Bash redirect
  bypasses it even for the paths it covers; (b) it matches `$FILE_PATH` literally with no
  `realpath` normalization, so `$HOME/.claude/../.claude/skills/…` or a relative path from a cwd
  inside the tree evades every arm. *(A third — `$HOME`-shape sensitivity — was found in r3 and is
  **fixed in this change**, not deferred: see C6's normalization block. It is listed here only so
  the enumeration of this hook's known weaknesses is complete.)* Anti-Deferral: worst case — an agent writing under
  `~/.claude/**` by redirect or traversal is ungated; likelihood — low (no workflow in this repo
  writes there that way; `install.sh` uses `cp`); cost — (a) means parsing redirection targets out
  of arbitrary command strings, (b) means normalizing untrusted paths in every arm, which commit
  `82449bb` shows this repo treats as a real contract when it is in scope. Owner: follow-up issue,
  as one change covering both. `TODO(phase-file-load-integrity): block-sensitive-files.sh — Edit/Write/MultiEdit-only wiring and unnormalized path matching`.

## User operation scenarios

- **S1 — Phase 3 entered on a fresh session.** The orchestrator reads `phases/phase-3-review.md`
  with `Read`. Front matter states `steps: 9`, `step_ids: 3-1 … 3-9`, `core: 3-3 …`. The last line
  received is `## END-OF-PHASE-3`, which `SKILL.md` told it to expect → complete read. Before
  reporting Phase 3 done it walks 3-1…3-9 against what it ran.
- **S2 — The prior failure, replayed on the Bash channel.** The orchestrator dumps the file
  through Bash and receives `---` plus `[523 more lines]`. The manifest does **not** survive. What
  catches it is that the last line received is not `## END-OF-PHASE-3` — a convention held from
  `SKILL.md`, which is loaded in full. This is why C3 states the terminator rather than the file
  declaring it.
- **S3 — Truncation with more of the file delivered** (`Read` with `limit`, a compaction pass):
  the manifest survives, so the reader knows nine steps exist and that 3-3 has no substitute, and
  the missing terminator says the read was partial. This is the channel the manifest is for.
- **S4 — A contributor adds Step 3-10 and forgets the front matter.** `bats tests/` goes red:
  `phase-3-review.md: front matter declares 9 steps but file has 10 '### Step' headings`.
- **S5 — A contributor hides a step in an indented fence.** 8d/8e fire, because I15's toggle is
  whitespace-tolerant and the base fixture carries a fenced decoy that keeps it honest.
- **S6 — A contributor adds `phases/phase-4-*.md`.** C4's directory sweep picks it up with no
  linter edit; the `sweep` fixture proves the sweep is real.
- **S7 — Someone edits `~/.claude/skills/triangulate/` directly.** After C6 the `Edit`/`Write` is
  blocked with the skills-specific message. Editing `~/.claude/skills/improve/` is also blocked,
  with the branch of that message that tells the truth for an unmanaged skill. Before C6 both
  silently succeeded and survived until the next install. Residual paths: SC4.

---

## Implementation Checklist

Derived in Phase 2 Step 2-1. Every location that must change, every existing helper that must be
reused, every pattern that must hold across sites.

### Files to modify (complete set)

| File | Contract | Change |
|---|---|---|
| `skills/triangulate/phases/phase-1-plan.md` | C1, C2 | front matter (7 steps); trailing `---` → `## END-OF-PHASE-1` |
| `skills/triangulate/phases/phase-2-coding.md` | C1, C2 | front matter (5 steps); trailing `---` → `## END-OF-PHASE-2` |
| `skills/triangulate/phases/phase-3-review.md` | C1, C2 | front matter (9 steps); trailing `---` → `## END-OF-PHASE-3` |
| `skills/triangulate/SKILL.md` | C3 | loading-protocol clause + declaration line; amend `:45` |
| `hooks/check-rule-sync.sh` | C4 | check 8 (8a.1-8j.4); phases dir added to the preflight; trailer text |
| `tests/check-rule-sync.bats` | C5 | fixture repair; 24 fixtures; staged zero-arg run; `>>` → insert-before-terminator at `:189`/`:196` |
| `hooks/block-sensitive-files.sh` | C6 | `$HOME` normalization for all arms; two skills arms; skills-specific message |
| `tests/block-sensitive-files.bats` | C6 | 5 fixtures |
| `hooks/generate-triangulate-rule-digest.sh` | C7 | emit `## END-OF-DIGEST` after the awk pass |
| `skills/triangulate/common-rules.digest.md` | C7 | regenerated (I27) |
| `tests/triangulate-rule-digest.bats` | C7 | presence / position / uniqueness assertions |

### Shared utilities that MUST be reused (no new helpers)

- `drift()` — `check-rule-sync.sh:53-56`. Every check-8 message goes through it; no new reporting path.
- `check_contiguous()` / `check_ranges()` — existing; not needed by check 8 but the style to match.
- `emit_block()` — `block-sensitive-files.sh:23-26`. JSON-encodes the reason via `jq -Rs`; C6 adds a case arm, never a second emit path.
- `run_hook()` — `tests/block-sensitive-files.bats`. All five C6 fixtures use it.
- `sed_i()` — `tests/check-rule-sync.bats:18-22`. BSD/GNU-portable in-place edit; every fixture mutation uses it.
- The staged-layout pattern at `tests/triangulate-rule-digest.bats:22-33` — the model for C5's zero-argument run.
- `$FIX` fixture builder in `setup()` — extended, not replaced.

### Patterns that must hold across all sites

- bash 3.2 / BSD-sed portable: no `mapfile`/`readarray`/`declare -A`/`sed -i` (I18).
- No `exit` of any status inside check 8 (I17).
- Every new bats assertion pairs `status` with a specific `DRIFT:` substring (I19).
- Terminator stems and front-matter key names come from `setup()` variables in tests (RT3), and from `SKILL.md` in the linter (I13).

### Impact analysis results

- **Duplicate implementations**: the only parallel copy is the installed `~/.claude/` tree, produced by `install.sh`'s `cp -r`. Repo is the source of truth; C5's staged run covers the twin (RT9). No other duplication.
- **R42 member sets**: `skills/triangulate/phases/*.md` = 3 files (`ls`-derived, matches I7). `~/.claude/skills/*` = 10 dirs vs 9 in the repo; the extra (`improve`) is C6's unmanaged-skill case.
- **All-test-tree enumeration (R19)**: `tests/` is the single test root — no co-located or e2e trees. Files referencing the changed hooks: `tests/check-rule-sync.bats`, `tests/block-sensitive-files.bats`, `tests/triangulate-rule-digest.bats`, `tests/install.bats` (skills staging only).
- **CI gate parity (Step 2-1 item 7)**: **no CI exists** (`.github/` absent) and **no local pre-PR script exists** (`scripts/`, `Makefile`, `Justfile` all absent). The parity diff is therefore vacuous rather than skipped: the gate set is exactly `bats tests/`, run locally. No deferred-parity entry is needed; this is recorded so a future reader does not mistake absence of the diff for an omission.
- **Baseline**: `bats tests/check-rule-sync.bats tests/block-sensitive-files.bats tests/triangulate-rule-digest.bats` = 45 passed, 0 failed, before any change (green-before).
- **Storage-backend / migration / ORM sub-steps**: N/A — config-only repo, no datastore.

---

## END-OF-PLAN
