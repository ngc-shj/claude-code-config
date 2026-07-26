# Code Review: opus5-prompting-adoption

Date: 2026-07-26
Branch: `feature/opus5-prompting-adoption`
Review round: 1 (Phase 3)

## Pre-screening (local LLM, pre-review.sh code)

`No issues found.`

## Diff under review

```
global/CLAUDE.md                 |  9 +
skills/context-budget/SKILL.md   |  4 +-
tests/install.bats               | 17 +
docs/archive/review/*-plan.md    | (plan, committed in Phase 1)
docs/archive/review/*-review.md  | (plan review, committed in Phase 1)
```

## Functionality Findings

- **F-01 (Major) — CONFIRMED and fixed.** C2's net addition measured **51 words**
  against its locked ≤45 cap. Verified independently (`sed -n '48,49p' | wc -w` →
  51). The expert correctly noted this does not break NFR1 (total net was 95, under
  ~120) but that NFR1 and C2's own cap are two independent gates, and the plan's
  own arithmetic assumed per-contract compliance rather than only the sum.
  **Fixed** by trimming the first sentence — the locked sentence was untouchable —
  from "Reach for a sub-agent when a task is large, self-contained, and
  parallelisable … Anything you can finish in a handful of tool calls" to "Reach for
  a sub-agent on large, self-contained, parallelisable work … A few tool calls".
  Now **42 words**, and it reads tighter. Mutation proof and full suite re-run after
  the edit (see Verification).
- **F-02 (Minor) — accepted and fixed.** The report template showed
  `実効残量` unconditionally inside the fenced shape, with the omit-when-unknown rule
  only in prose *after* the fence — so a reader copying the shape literally would
  emit a percentage against an unknown denominator, the fail-open direction the plan
  names. **Fixed**: the fence line now carries
  `← {{context_window}} が不明なら省略`, co-locating rule and shape.
- Verified conformant by the expert, independently measured: C1 body 41 words
  (≤60), correct placement, calibration phrasing with no hard cap, and an explicit
  "that request wins" yield clause satisfying the invariant against the
  context-budget and triangulate long-form templates. C3's placeholder shape exact,
  stale hardcode gone, Step 6 explains both the resolution mechanism and the
  unknown case. C4 has the status guard before any grep. NFR3 sweep across all five
  always-loaded files: no hits. No new `~/.claude/*.md` pointer introduced, so the
  reference-file delivery test is unaffected.

## Security Findings

**No Critical or Major.** The central R21 question was answered directly:

> The shipped sentence gates what task shape may be *handed to* an agent; R21 gates
> what the *orchestrator does after* a subagent reports back. Different actors,
> different moments — so the sentence cannot literally license an R21 skip; it never
> touches the orchestrator's own re-run/spot-check obligation.

- **SEC-M1 (Minor) — accepted and fixed.** The guardrail was protected only by a
  verbatim grep, which catches an exact-string change but not a well-intentioned
  paraphrase in a later PR that drifts the sense past review. **Fixed**: an HTML
  comment now sits directly above the sentence in `global/CLAUDE.md` —
  `Wording reviewed against skills/triangulate R21; reword only after re-reading it.`
  It is a comment, so it costs no prompt prose against C2's word cap while putting
  the warning where the next editor will be standing.
- **SEC-M2 (Minor) — declined, with reason.** The expert asked whether C1's "no
  filler" could trim caveats from an *ad hoc* security remark made with no skill
  firing, and offered "brevity does not mean omitting caveats or lower-severity
  findings". Declined: the expert itself rated it "informational only… not required
  given current design", the real review protocols (triangulate, security-scan) are
  skill-scoped and already exempted by C1's "that request wins" clause, and adding a
  defensive clause for a low-probability off-protocol case is the over-constraint
  NFR2 exists to prevent. Recorded rather than silently dropped.
- Verified clean: gate liveness (no `hooks/*.sh`, `settings.json`, or `install.sh`
  touched, so none of the #106 dead-gate mechanisms are implicated); the new test
  genuinely asserts the installed copy; **RS4** on both new docs files (read in full
  — no credentials, tokens, keys, IPs, hostnames, or PII; all "token" hits are
  token-count references); C3's direction is fail-safe (suppresses the derived
  percentage rather than guessing); and **SC7** is a legitimate pre-existing
  deferral with a named owner, not a live gap being obscured.

## Testing Findings

**No Critical or Major.** All six verification tasks were independently reproduced
with no discrepancy:

- Full suite 791 passing / 0 failing — matches exactly.
- RT7 mutation proof: run 1 fails at **line 265** (the C1 grep), run 2 at
  **line 266** (the C2 grep) — confirmed load-bearing *by name*, not merely by
  count, which is what distinguishes "two assertions work" from "one exists".
  Residue check clean.
- **Vacuous-pass analysis, new evidence**: the expert traced `set -euo pipefail` in
  `install.sh` and confirmed a broken or no-op `cp` propagates to a non-zero
  `$status`, caught by `[ "$status" -eq 0 ]` *before* any grep runs. It separately
  confirmed `grep -q` on a missing file exits 2. So the guard is load-bearing, not
  decorative — a stronger result than the plan claimed.
- **F1 (Minor) — no change.** `grep -qF` vs `-q` makes no behavioral difference for
  the current sentence (its only metacharacter is a trailing `.`, which matches
  literally in that position under BRE anyway). Keeping `-F` as the right default
  for verbatim prose anchors, protecting the next edit that adds a real
  metacharacter.
- **F2 (Minor) — Major from plan review, now downgraded by its own author.** The
  expert that raised C3's missing regression test as Major in Phase 1 reassessed the
  shipped state as "adequately justified" and downgraded to Minor-informational: the
  `SC5` trade-off is explicit, owned, carries a stated revisit condition, and was
  reasoned through two rounds rather than asserted. Accepted as shipped.
- **F3 (Minor)** — `SC7` is pre-existing and correctly out of scope. No action.

## Adjacent Findings

- Security F-03-equivalent (C3 self-fill reliability) → functionality. Already
  converged in plan review; no new instance this round.

## Quality Warnings

None. Every finding arrived with a reproduction or a measurement, and the two that
changed the code (F-01's word count, F-02's fence line) were re-verified by the
orchestrator before acceptance.

## Verification after fixes

Re-run after the F-01 trim, SEC-M1 comment, and F-02 fence edit:

- C2 prose: **42 words** (≤45 cap) — the HTML comment is excluded as markup, not
  prompt prose; 54 words if counted, noted for transparency.
- NFR1 net addition: **98 words** (~120 budget), total 463.
- RT7 mutation proof re-run: run 1 → line 265, run 2 → line 266. Still independently
  load-bearing.
- Full suite: **791 passing, 0 failing**.

## Recurring Issue Check

### Functionality expert
- R1–R20: N/A — no matching change classes
- R21: Checked — C2's direction verified not to license an R21 skip
- R22–R33: N/A
- R34: Checked — SC5/SC7 record deferrals with cost-justification
- R35, R41: Checked / N/A — C3 fill-correctness is VC1-class blocked-deferred by design
- R42: Checked — five-member always-loaded set independently recomputed, no sixth found
- R43: N/A
- R44: Checked — bats status read directly, unpiped
- R45, R46: N/A

### Security expert
- R1–R20: N/A — no application code, no auth/crypto surface
- R21: Checked — mechanism in common-rules.md untouched by this diff
- R22–R33: N/A
- R34: Checked — SC7 carries cost-justification and owner
- R35–R41: N/A
- R42: Checked — root `CLAUDE.md` correctly left unedited per #106
- R43–R46: N/A
- RS1–RS3, RS5, RS6: N/A
- RS4: Checked — both new docs files clean

### Testing expert
- R1–R41, R43–R46: N/A for this diff's shape
- R42: Checked — all five members re-swept clean
- RT7: Satisfied — both mutation runs reproduced with per-anchor failure naming
- RT4, RT6, RT8: N/A — no concurrency, no new exports, no new gate script
- RT1–RT3, RT5, RT9: N/A

## Disposition summary

| Finding | Severity | Disposition |
| --- | --- | --- |
| Func F-01 | Major | Fixed — C2 trimmed 51 → 42 words |
| Func F-02 | Minor | Fixed — omit-rule co-located in the fence |
| Sec SEC-M1 | Minor | Fixed — anti-drift comment above the locked sentence |
| Sec SEC-M2 | Minor | Declined with reason (NFR2 over-constraint; expert rated informational) |
| Test F1 | Minor | No change — `-F` kept as the correct default |
| Test F2 | Minor | Accepted as shipped; author downgraded from Major |
| Test F3 | Minor | Pre-existing, out of scope (SC7) |
