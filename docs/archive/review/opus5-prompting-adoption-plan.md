# Plan: opus5-prompting-adoption

Adopt the Opus-5-specific prompting guidance Anthropic published after commit
#107 (`refactor: apply Claude 5 context-engineering guidance to the
always-loaded prompt`) into this repo's always-loaded prompt and the
context-budget skill.

## Project context

- **Type**: `config-only` (Markdown prompt text, shell hooks, bats tests — no application code)
- **Test infrastructure**: `unit tests only` (bats, `tests/`), no CI/CD pipeline in this repo
- **Verification environment constraints**:
  - `VC1` — **Prompt-effect verification is not mechanically testable.** Whether a
    prompt line actually changes model behavior cannot be asserted by bats. The
    testable surface is *delivery* (the text reaches `~/.claude/CLAUDE.md` via
    `install.sh`) and *shape* (no stale hardcoded model facts). Behavior itself is
    `blocked-deferred`.
    - **Anti-Deferral cost-justification**: building a behavioral eval harness
      (fixture prompts + model calls + output-length scoring) would cost real API
      spend per run and require a golden-output corpus this repo has no
      infrastructure for. The repo's established control for this class is a
      delivery assertion in `tests/install.bats` (precedent: the Rules Layer test
      at `install.bats:233` and the option-proposal test at `install.bats:243`,
      both of which assert delivery of prompt text whose *effect* is likewise
      untestable). This plan follows that precedent rather than inventing a
      heavier mechanism.
  - `VC2` — **Anthropic docs are the authority for model facts and may change.**
    The three source pages are fetched, not vendored. Re-verification requires
    network access. Facts are cited in the plan so a future reader can re-check.

Per the `config-only` rule, findings recommending new test *frameworks* or CI/CD
are Minor informational only. Findings recommending a new bats *test* in the
existing suite are in scope and normal severity — the framework already exists,
and `CLAUDE.md` mandates a matching test for hook changes.

## Objective

Close the gap between this repo's prompt text and the Opus-5-specific behaviors
Anthropic documents, without re-introducing the over-constraint that #107
removed.

## Source facts (Anthropic official, fetched 2026-07-26)

| Fact | Source |
| --- | --- |
| Opus 5 default user-facing responses run longer than prior Opus models'. Effort controls thinking volume, **not** visible response length — "to control response length, prompt for it explicitly". | [Prompting Claude Opus 5 → Response length and verbosity](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) |
| Files Opus 5 writes to disk (reports, Markdown, summaries) are often longer than on prior models; add explicit length calibration. | same → Written deliverable length |
| Opus 5 delegates to subagents more readily; give explicit guidance on which scenarios warrant delegation. Do not use subagents to verify your own work. | same → Controlling subagent spawning |
| Opus 5 verifies and self-corrects without being told; explicit verification/re-check instructions cause over-verification and should be removed. | same → Task scope and over-verification / Self-correction |
| Opus 5 has a 1M-token context window as both default *and* maximum. Other current models do not. | same → Capability improvements |
| Effort default `high`; `low`/`medium` are the primary cost control; `xhigh` for demanding agentic work. Re-sweep effort when carrying settings from an earlier model. | [Effort → Recommended effort levels for Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/effort) |
| Anthropic removed >80% of Claude Code's system prompt for Claude 5 models with no eval loss; it was "overconstraining". Prefer judgment over rigid rules. | [The new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) |

## Requirements

### Functional

- `FR1` The always-loaded prompt carries output-length calibration covering both
  conversational responses and Claude-authored files.
- `FR2` The always-loaded prompt carries subagent-delegation criteria, including
  the "do not delegate verification of your own work" clause.
- `FR3` The context-budget report stops hardcoding a 1M context window.
- `FR4` Delivery of FR1/FR2 is asserted by `tests/install.bats`.

### Non-functional

- `NFR1` **Context budget.** `global/CLAUDE.md` is always loaded. Net addition
  must stay under ~120 words (~160 tokens). Measured before/after.
- `NFR2` **No over-constraint regression.** Additions must be judgment-granting
  prose, not rule enumerations — the failure mode #107 fixed. No new numbered
  rule lists, no "always/never" scaffolding where a judgment sentence works.
- `NFR3` **No new verification instructions.** The additions must not tell the
  model to double-check, re-verify, or re-read its own work; Anthropic
  documents that as actively harmful on Opus 5.

## Technical approach

Three independent edits. No shared code path, no ordering dependency between
them, so each is separately revertable.

**Where the text goes.** `global/CLAUDE.md` (→ `~/.claude/CLAUDE.md`), not
`rules/common/*.md`. Rationale: `rules/common/*` is scoped to coding-style /
testing / security guidance for *code being written*; output length and
delegation are session-conduct policy, which is what `global/CLAUDE.md` already
holds (Language Policy, Git Workflow, Proposing options). Putting it in
`rules/common/` would also be loaded always (no `paths:`) so the token cost is
identical — the choice is about topical fit, not budget.

**Why not a skill.** Skills load on invocation. The behavior being corrected
(verbosity, delegation) happens on *every* turn including turns where no skill
fires, so delivery has to be always-on. Same argument the option-proposal test
records at `install.bats:243`.

## Contracts

### C1 — Output-length calibration section in `global/CLAUDE.md`

- **Signature**: a new `## Output length` section (heading text exactly
  `## Output length`), placed after `## Language Policy` and before
  `## Coding Style`.
- **Content obligations**: must cover (a) conversational response length, (b)
  length of files Claude writes to disk. Must be phrased as calibration ("match
  length to what the task needs"), not a hard cap — a hard word limit would
  damage the long-form review artifacts this repo's own skills produce
  (`docs/archive/review/*-review.md` are legitimately long).
- **Invariants** (app-enforced — prose review, no runtime check available):
  - Does not instruct verification, re-checking, or re-reading (NFR3).
  - Does not conflict with `skills/context-budget` report format or the
    triangulate review-artifact templates, which mandate specific long shapes.
    Both are skill-scoped and specify their own output; a global "match length to
    the task" line yields to an explicit format request rather than fighting it —
    the section must say so, otherwise the two are in tension.
- **Forbidden patterns**:
  - `pattern: /double.?check|re-?verify|verify your own/i` — reason: NFR3, Opus 5 over-verifies when told to verify.
  - `pattern: /\b(under|at most|no more than) \d+ (words|lines|sentences)\b/i` — reason: hard caps break long-form review artifacts (C1 content obligation).
- **Acceptance criteria**:
  - `grep -q '^## Output length' ~/.claude/CLAUDE.md` after install → 0.
  - Section body mentions both conversational output and written files.
  - Section body ≤ 60 words.

### C2 — Subagent-delegation criteria in `global/CLAUDE.md`

- **Signature**: delegation guidance added to the existing `## Model Routing`
  section (heading unchanged), not a new section.
- **Rationale for placement**: `## Model Routing` already owns "what runs where"
  and already points to `model-routing.md`. A separate `## Delegation` section
  would split one topic across two headings and cost a heading's worth of
  always-loaded tokens for no gain.
- **Content obligations**: must state (a) delegate only genuinely independent,
  sizeable work, (b) do not delegate what you can finish in a few tool calls,
  (c) the delegation/verification boundary — expressed via the locked sentence
  below, which carries (c) without using the word "verify".
- **Invariants**:
  - Clause (c) must not contradict `skills/triangulate` R21, which requires the
    *orchestrator* to verify a *subagent's* reported work. R21 is
    orchestrator-verifies-delegate; clause (c) forbids
    delegate-verifies-orchestrator. These are opposite directions and both hold.
    **The wording must make the direction explicit** — an unqualified "do not use
    subagents to verify" would read as licensing the R21 skip, which is a
    Critical silent-regression rule in this repo.
  - Must not weaken the existing local-LLM-first routing line.
- **Forbidden patterns**:
  - `pattern: /do not (use )?(sub-?agents?|delegate).{0,40}verif/i` used without a self/own qualifier — reason: collides with R21 as above. (Reviewer-checked, not grep-decidable alone.)
- **Acceptance criteria**:
  - `## Model Routing` in the installed copy mentions delegation criteria.
  - **Full-sentence anchor, not a fragment** (security review Round 2 F-01
    escalated this and the escalation is accepted). Round 1 pinned only the
    3-word fragment `your own work`, leaving the surrounding sentence free — so a
    technically-compliant commit could land with a subtly wrong direction and no
    automated gate would fail. Since this clause gates R21 (Critical), the weak
    control was inconsistent with the plan's own reasoning for demoting the
    forbidden-pattern regexes. The locked sentence is therefore:

    > Delegate a whole slice of work, not the checking of work already done.

    C4 greps this **verbatim**. The reviewer's judgment call moves from "is
    whatever sentence someone wrote correct?" to "is the already-reviewed
    sentence still present?" — strictly stronger, and the same tightening RT7/RT8
    forced onto C3's placeholder and C4's status guard.
  - **Why this sentence.** It states the positive shape (delegate a slice) rather
    than a prohibition, so it cannot be read as "don't verify". It never contains
    the word "verify", which is what made the earlier draft ambiguous against
    R21 — "checking of work already done" describes the *spawn* being discouraged,
    not the orchestrator's own reading of a delegate's report. Note this drops the
    `your own work` fragment; C4 greps the sentence above instead.
  - **Residual risk, accepted explicitly** (rather than left implicit, per
    security's request): a verbatim anchor cannot prove the sentence *means* the
    right thing to a future model — only that the reviewed wording survived. A
    behavioral check is `blocked-deferred` under `VC1` for the same reason as
    every other prompt-effect claim here. Recorded as `SC6`.
  - Net addition to the section ≤ 45 words.

### C3 — Dynamic context window in `skills/context-budget/SKILL.md`

- **Signature**: the report template line currently reading
  `コンテキストウィンドウ: 1M tokens` (line 131) becomes a placeholder filled from
  the session's actual model, and Step 6 gains a one-line instruction on how to
  fill it.
- **Resolution mechanism** (pinned — pre-screening flagged this as undefined):
  the window is **not** shell-resolvable in this repo. Verified: `settings.json`
  has no `"model"` key, and no `ANTHROPIC_MODEL`-style env var is exported (only
  `CLAUDE_CODE_EXECPATH`). So Step 1's shell inventory cannot emit it, and adding
  a detection script would be inventing a fact source that does not exist.
  The mechanism is therefore: **the orchestrating model fills the placeholder from
  its own session context, and writes `不明` when it cannot.** Step 6 states this
  in one line. This is the honest mechanism — the model does know its own
  identity, whereas the shell does not.
- **Invariants**:
  - The skill must not *hardcode a different* number — that is the same bug one
    model later. It must be a placeholder.
  - When the actual window is unknown, the report must say so rather than guess;
    a wrong denominator makes 実効残量 (effective remaining) wrong, which is the
    number the user acts on. The 実効残量 line must be suppressed or marked
    unknown when the window is `不明` — printing a percentage against an unknown
    denominator is the fail-open direction of this contract.
- **Placeholder shape** (pinned — functionality review F-01 asked for a checkable
  shape): the line becomes `コンテキストウィンドウ: {{context_window}}`. Locking the
  literal token means the *shape* is grep-assertable even though the *fill* is
  not, which is the best available split given the resolution mechanism above.
  **Fill-correctness is `VC1`-class `blocked-deferred`** — whether the model
  substitutes a *correct* window (vs. leaving the token, or writing `不明` when it
  did know) is unverifiable here for exactly the reason `VC1` gives for C1/C2's
  prose effect. Stated explicitly at functionality review's request so the
  shape-lock is not mistaken for a full close of R41.
- **Forbidden patterns**:
  - `pattern: コンテキストウィンドウ: 1M tokens` — reason: the stale hardcode being removed; its reappearance is the regression.
- **Acceptance criteria** (paired positive+negative — testing review F-05 showed a
  bare negative grep is vacuous):
  - `[ -f skills/context-budget/SKILL.md ]` — the file still exists. **Verified
    necessary**: `! grep -q PATTERN missing-file` exits 0, so `!`-inversion
    reports PASS when the file is gone. Reproduced during this review.
  - `grep -q 'コンテキストウィンドウ: {{context_window}}' skills/context-budget/SKILL.md`
    — the placeholder line is present (positive assertion).
  - `! grep -q 'コンテキストウィンドウ: 1M tokens' skills/context-budget/SKILL.md`
    — the stale hardcode is gone (negative assertion, only meaningful paired with
    the two above).
  - Step 6 explains how to resolve the placeholder and what to print when unknown.
- **Test home** (resolved now, not deferred — testing review F-06): `tests/install.bats`
  `setup()` deliberately skips staging `skills/` (`# Skip skills/ for speed`,
  verified at `tests/install.bats:32`), while `install.sh:225-235` *does* install
  skills in production. So there is **no** installed-copy home for a C3 assertion
  today. Decision: **(b) source-only grep, deliberately.** Rationale for treating
  C3 differently from C1/C2: C1/C2 protect a *delivery* path whose silent failure
  is the exact bug `install.bats` exists to catch, and whose content is invisible
  at the source (the model only ever reads the installed copy). C3 is a *content*
  fix, and a stale string in it is visible in the repo source, which is where every
  future editor reads it.

  **Coverage claim corrected** (testing review Round 2 F-R2-03, verified): an
  earlier draft said C3's delivery is "already covered by the generic skill-install
  loop". That is false as a coverage statement. `install.sh:225-235` is real
  production code, but **no test in this suite exercises it for any skill file** —
  `grep -rn 'skill' tests/install.bats` returns only two comments, and no test
  asserts anything reaches `~/.claude/skills/`. C3's source-only grep therefore
  does not *regress* that pre-existing gap, but it cannot claim credit for coverage
  that does not exist either. Closing the gap is `SC7`'s separate issue.

  **Rationale corrected** (functionality review Round 2 F-05R2): an earlier draft
  claimed staging `skills/` "would slow every test in the file". That overclaims —
  `setup()` already stages individual files selectively (`global/RTK.md`,
  `global/model-routing.md` are copied one by one), so adding a single
  `skills/context-budget/SKILL.md` would cost one more `cp`, not a whole-tree copy.
  The honest reason is **precedent, not speed**: none of the existing tests stage
  skill-internal files, and doing it here would make `install.bats` responsible for
  staging arbitrary skill files on demand, coupling it to paths inside `skills/`
  that it otherwise knows nothing about — for one string whose staleness is already
  visible in-source. Recorded as `SC5` so the choice is auditable rather than a
  Phase-2 accident.

### C4 — `tests/install.bats` delivery assertions

- **Signature**: one new bats test, `@test "install: CLAUDE.md carries the
  Opus 5 output-length and delegation guidance"`, following the shape of the
  existing test at `install.bats:243`.
- **Content obligations**: asserts C1's heading (`^## Output length`) and C2's
  locked sentence (`Delegate a whole slice of work, not the checking of work
  already done.`) are delivered verbatim, after running `install.sh` into
  `$TEST_HOME`.
  - **Status guard is mandatory, not inherited** (testing review F-03): the test
    MUST include `[ "$status" -eq 0 ]` immediately after the
    `run env HOME="$TEST_HOME" bash "$STAGING/install.sh"` line, before any
    `grep`. Stated explicitly rather than left to "follows the shape of
    `install.bats:243`", so a skimming implementer cannot drop it. Without it a
    silently-failing `install.sh` reaches a grep against an absent file.
- **Invariants**:
  - Must be **red-provable** (RT7): removing the C1/C2 text from
    `global/CLAUDE.md` must make it fail.
  - Must assert on the **installed** copy (`$TEST_HOME/.claude/CLAUDE.md`), not
    the repo source — asserting the source would pass even if `install.sh`
    stopped delivering the file, which is the failure the test exists to catch.
    (Confirmed by review as matching all nine existing delivery tests.)
- **Mutation-proof procedure** (concrete, per testing review F-01 — the previous
  wording named the safety property but not the commands):

  **Exactly one mechanism is permitted** (security review F-04: naming two
  alternatives would let a future implementer invent an untested third). The
  mechanism is the **scratch repo tree**, and no other: `install.bats` derives
  `REPO_DIR` from `$BATS_TEST_FILENAME`'s parent (`tests/install.bats:7`), so
  running bats from a copied tree makes `REPO_DIR` follow it there automatically.
  No inline `setup()` override, no env-var injection, no editing the test file.
  The tracked file is never touched, so there is nothing to "restore".

  **This procedure was executed during Phase 1 review** against the existing
  `Rules Layer` test to prove the path works: mutating the scratch copy made that
  test go red (`grep -q '^## Rules Layer' ... failed`) while
  `git diff --stat global/CLAUDE.md` stayed empty. The mechanism is verified, not
  assumed — run twice, with no edit to any tracked file.

  **Why `REPO_DIR` needs no override** (testing review Round 2 F-R2-01 argued this
  mechanism was a dead end; that argument was checked and does not hold). The
  objection was that `REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"`
  is a bare assignment, so `REPO_DIR=/scratch bats ...` is ignored — correct, and
  that is precisely why this procedure does not use an env override. Copying
  `tests/install.bats` **into the scratch tree** makes `$BATS_TEST_FILENAME` resolve
  to the scratch path, so `REPO_DIR` recomputes to the scratch root on its own. No
  env var, no edit to `install.bats`, no throwaway `.bats` file. Recorded because
  the objection is the natural first reading of line 7.

  ```bash
  SCRATCH=$(mktemp -d)
  mkdir -p "$SCRATCH"/{global,hooks,rules/common,tests}
  cp install.sh settings.json "$SCRATCH/"
  cp global/*.md "$SCRATCH/global/"
  cp hooks/block-sensitive-files.sh "$SCRATCH/hooks/"
  cp rules/common/*.md "$SCRATCH/rules/common/"
  cp tests/install.bats "$SCRATCH/tests/"

  # Run 1 — strip C1's heading only:
  grep -v '^## Output length' "$SCRATCH/global/CLAUDE.md" > "$SCRATCH/g.tmp"
  mv "$SCRATCH/g.tmp" "$SCRATCH/global/CLAUDE.md"
  bats "$SCRATCH/tests/install.bats" -f 'Opus 5'   # MUST fail, naming the C1 grep

  # Run 2 — restore, then strip C2's locked sentence only:
  cp global/CLAUDE.md "$SCRATCH/global/CLAUDE.md"
  grep -v 'Delegate a whole slice of work' "$SCRATCH/global/CLAUDE.md" > "$SCRATCH/g.tmp"
  mv "$SCRATCH/g.tmp" "$SCRATCH/global/CLAUDE.md"
  bats "$SCRATCH/tests/install.bats" -f 'Opus 5'   # MUST fail, naming the C2 grep

  rm -rf "$SCRATCH"
  ```

  - **Strip each anchor separately, not both at once.** A single run with both
    removed proves only that *some* assertion fired. Two runs — one per anchor —
    prove each assertion is independently load-bearing. Without this, a test that
    silently dropped its C2 grep would still pass the mutation proof.
  - **This is a minimal anchor-strip, not a whole-section deletion** (testing
    review F-R2-02): `grep -v` drops only the matching line, so C1's run leaves the
    section body as an orphaned paragraph. Harmless here — C4 asserts only on the
    two single-line, single-occurrence anchors, and both are genuinely absent — but
    do not generalize the technique to assertions that are not line-anchored.
  - **`grep -v` removes whole lines**, so the strip must target a line that
    contains the anchor and nothing else load-bearing. For C1 the heading line is
    clean. C2's locked sentence must be written as **its own line** inside
    `## Model Routing` so that `grep -v 'Delegate a whole slice of work'` removes
    exactly it and nothing else — otherwise the strip also deletes adjacent
    delegation prose and the red could be attributed to the wrong assertion. The
    proof MUST confirm the failure message names the C2 assertion specifically.

  - **Residue check after the proof** (testing review F-02, matching this repo's
    own R21 mutation-residue precedent — a "restored" claim is never accepted as
    proof): run `git diff --stat global/CLAUDE.md` and confirm the only diff is
    the intended C1/C2 additions, with no artifact of the mutation exercise.
- **Acceptance criteria**:
  - `bats tests/install.bats` green.
  - Mutation proof recorded: anchors stripped → test fails; real text → passes.
  - `git diff --stat global/CLAUDE.md` shows no mutation residue.

### Consumer-flow walkthrough

C1/C2 produce prose consumed by the *model at session start*, not by code, so
there is no field-shape consumer. The one code-shaped consumer is C4:

- `Consumer tests/install.bats (path: tests/install.bats)` reads
  `{ heading "## Output length", delegation-criteria substring }` from
  `$TEST_HOME/.claude/CLAUDE.md` and uses each to assert `install.sh` delivered
  the section. Both fields are literal strings fixed by C1/C2 acceptance
  criteria, so the consumer is satisfiable from the locked shape.
- `Consumer tests/install.bats:253 (reference-file test)` reads every
  `~/.claude/*.md` path mentioned in `CLAUDE.md` and asserts install delivers
  it. **C1/C2 must therefore not introduce a `~/.claude/<file>.md` pointer to a
  file this repo does not install** — that would break an existing test. Neither
  C1 nor C2 adds a pointer, so this holds; recorded because it is a
  non-obvious existing contract on the file being edited.
- `Consumer tests/install.bats:268 (heavy-detail test)` asserts heavy reference
  detail stays out of the always-loaded prompt. C1/C2 are short prose, but this
  test's specific assertions must be re-read before editing to confirm none of
  them keys off a line count or a section list that the additions would break.

### R42 member-set derivation

The universal claim in this plan is NFR3: *no* prompt text in the always-loaded
set instructs verification. The class is "always-loaded prompt files", and its
defining primitive is "files loaded with no `paths:` frontmatter".

Derived member-set:

```bash
# Always-loaded set = global/CLAUDE.md + repo CLAUDE.md + rules/common/*.md (no paths: frontmatter)
grep -Ln '^paths:' rules/common/*.md          # → all three: coding-style, security, testing
ls global/CLAUDE.md CLAUDE.md
```

→ Members: `global/CLAUDE.md`, `CLAUDE.md`, `rules/common/coding-style.md`,
`rules/common/security.md`, `rules/common/testing.md`.

The NFR3 sweep must cover **all five**, not just the two files this plan edits.
A pre-existing verification instruction in `rules/common/testing.md` would be a
member of the class this plan declares clean. Verified during Phase 2 as an
explicit step, and any hit is a finding in its own right (it may be
pre-existing — then R34 Anti-Deferral applies, not a silent skip).

**Root `CLAUDE.md` is a sweep member but NOT an edit target** (pre-screening
asked whether it needs a parallel update — it explicitly must not get one).
Copying C1/C2 there would load both sections twice in sessions opened in this
repo, which `tests/install.bats:222` asserts against and which commit #106 fixed
under "stop CLAUDE.md double-loading". It participates in the NFR3 read-only
sweep and nothing more.

Note the deliberate **non**-member: `skills/**`. Skill files load on invocation,
so their verification instructions are scoped to a running skill and are exactly
the external-command verification (lint/test/build, `check-*.sh`) that Anthropic's
guidance does *not* target — it targets generic "verify your work" instructions to
the model. This exclusion is documented rather than assumed; see Scope contract
`SC1`.

## Go/No-Go Gate

| ID | Subject | Status |
| --- | --- | --- |
| C1 | Output-length calibration section in `global/CLAUDE.md` | locked |
| C2 | Subagent-delegation criteria in `## Model Routing` | locked |
| C3 | Dynamic context window in context-budget report | locked |
| C4 | `tests/install.bats` delivery assertions | locked |

## Testing strategy

| Contract | Mechanism |
| --- | --- |
| C1, C2 | `tests/install.bats` delivery assertion (C4), mutation-proved per RT7. **C2 additionally requires a manual reviewer side-by-side read against R21 in `skills/triangulate/common-rules.md` before acceptance — not covered by C4's grep** (testing review F-R2-05: this obligation was discoverable only from C2's own contract text, so a reader skimming this table could mistake it for automated) |
| C3 | Paired positive+negative grep + file-existence guard (see C3 acceptance criteria); source-only per `SC5` |
| C4 | `bats tests/` full suite |
| NFR1 | `wc -w global/CLAUDE.md` before/after |
| NFR3 | R42 member-set grep over all five always-loaded files |

**Forbidden-pattern checks are reviewer-checked, not bats-asserted** (testing
review F-07 asked which). C1/C2's forbidden patterns (`double.?check|re-?verify`,
hard-cap regexes) are read by the Phase 3 reviewer, not automated. Automating
them would mean asserting the *absence* of arbitrary prose in a file that will
keep growing — a check that passes vacuously the moment the wording shifts, which
is the same trap F-05 found in C3. C4 asserts presence of the two anchors only.

### Green-before baseline (measured, not deferred)

Testing review F-08 asked for a concrete command and a go/no-go rule. Both now
recorded, and the baseline is already taken:

```bash
bats tests/          # → 790 passing, 0 failing (measured 2026-07-26, pre-change)
wc -w global/CLAUDE.md   # → 365 words (pre-change baseline for NFR1)
```

- **Go/no-go rule**: the baseline above is green, so the plan proceeds. Had it
  been red, the rule is: halt, file the pre-existing failure separately, do not
  attribute it to this change and do not fold its fix into this PR.
- **After-state expectation**: 791 passing (790 + the one new C4 test), 0 failing.
  A different total means something else changed and must be explained before the
  PR opens.
- **NFR1 arithmetic**: net addition = C1 (≤60) + C2 (≤45) = **≤105 words**, within
  the ~120-word budget. Post-change total is therefore ≤470 words (365 + 105) —
  that total is *not* what NFR1 bounds; NFR1 bounds the addition only.
  (Corrected after functionality review flagged the earlier phrasing, which read
  "470 words, within the ~120-word net-addition budget" — conflating total with
  net addition.)

## Considerations & constraints

### Scope contract

- `SC1` — **Skill-internal verification steps are NOT removed.** The
  lint/test/build blocks and `check-*.sh` gates in `skills/test-gen`,
  `skills/simplify`, and `skills/triangulate` stay as-is. Rationale: Anthropic's
  "remove verification instructions" targets generic self-verification prompts;
  these are external-command gates whose results the model cannot know without
  running them, plus R21-style verification of *another agent's* output. Removing
  them would recreate the silently-dead-gate class that commit #106 fixed. Owner:
  no future issue — this is a deliberate permanent exclusion.
- `SC2` — **Effort configuration is not touched.** Anthropic recommends
  re-sweeping effort per model, but effort is a user-level runtime choice
  (`/model`, currently `high`) and not a `settings.json` key in this repo. Owner:
  user decision, out of band.
- `SC3` — **The "report everything, filter separately" review guidance is not
  applied to `skills/triangulate`.** Its severity system already reports all
  findings with a severity label rather than suppressing low-severity ones, so
  the guidance is already satisfied; no edit needed. Verified by reading the
  severity tables in Phase 2 — if that reading turns out wrong, this becomes a
  finding, not a silent skip. Owner: this plan, Phase 2 verification step.
- `SC6` — **C2's correctness is anchored verbatim, not proven semantically.** The
  locked sentence is grep-asserted; whether a future model *reads* it in the
  intended direction is unverifiable here for the same reason as `VC1`. Accepted
  as a documented trade-off at security review's request rather than left as an
  implicit gap. Owner: this plan, permanent.
- `SC7` — **`skills/security-scan/` delivery remains untested; not fixed here.**
  Security review Round 2 F-05 found that `install.bats` `setup()`'s blanket
  `skills/` skip means no test asserts `skills/security-scan/SKILL.md` reaches
  `~/.claude/skills/` — the same silently-dead-delivery class commit #106 fixed
  for hooks and CLAUDE.md, never extended to skills. **Pre-existing and not caused
  by this plan**; SC5 neither creates nor worsens it. Fixing it here would mean
  staging `skills/` in `setup()`, which is exactly the cost SC5 declines. Owner:
  **separate future issue** — stage only `skills/security-scan/` (preserving SC5's
  speed rationale) and add one delivery assertion. Recorded rather than silently
  skipped, per R34.
- `SC5` — **C3 gets a source-only grep, not an installed-copy bats test.**
  `tests/install.bats` `setup()` skips staging `skills/`, so no installed-copy home
  exists today. Declined on **precedent** grounds — no existing test stages
  skill-internal files, and doing so would couple `install.bats` to paths inside
  `skills/` — not on speed grounds (see the corrected rationale under C3 → Test
  home). Owner: this plan, permanent decision; revisit only if `setup()` starts
  staging `skills/` for an unrelated reason.
- `SC4` — **Narration-cadence guidance is not added.** Anthropic offers it as an
  option; this repo's user has expressed no dissatisfaction with narration, and
  adding unrequested behavioral constraints is the over-constraint NFR2 forbids.
  Owner: future issue if the user raises it.

### Risks

- **R-a — Wording collision with R21.** C2 clause (c) is one qualifier away from
  licensing a Critical rule skip. Mitigated by the C2 invariant requiring an
  explicit self/own qualifier, and called out for the security reviewer.
- **R-b — Tension between C1 and this repo's own long-form artifacts.** The
  triangulate review templates and the context-budget report are deliberately
  long. Mitigated by C1's "yields to an explicit format request" clause.
- **R-c — NFR1 creep.** Three additions to an always-loaded file is exactly how
  context bloat starts; the repo has a skill (`context-budget`) whose whole
  purpose is catching this. Mitigated by the word budget and by measuring.

## User operation scenarios

1. **Fresh session in an unrelated project.** User asks a short factual
   question. Expected: C1 keeps the answer short; C2 does not fire. Failure mode
   to watch: C1 phrased as a hard cap truncates a legitimately complex answer.
2. **`/context-budget` run on a Sonnet session.** Expected: C3 reports Sonnet's
   actual window, or states the window is unknown — not "1M". Failure mode: the
   placeholder is silently filled with 1M anyway because Step 6 does not say how
   to resolve it.
3. **`/triangulate` run producing a review artifact.** Expected: C1 does not
   shorten the mandated review-file sections. Failure mode: R-b materializes and
   the artifact loses required sections.
4. **A large multi-file refactor.** Expected: C2 permits delegation (genuinely
   independent, sizeable). Failure mode: C2 phrased too restrictively suppresses
   delegation the triangulate Phase 2 flow actively requires.
5. **`install.sh` run after someone edits `global/CLAUDE.md` and drops a
   section.** Expected: C4 fails loudly. Failure mode: C4 asserts against the
   repo source and passes anyway.
