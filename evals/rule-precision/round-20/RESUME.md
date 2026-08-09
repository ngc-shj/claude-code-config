# Round 20 — PAUSED MID-RUN. Do not measure this data.

Paused at the five-hour rate-limit boundary, part way through the reviews.
Nothing here has been extracted, clustered, adjudicated or measured, and none of
it should be until the arms are complete.

Pre-registration: `../../rule-ablation/protocols/round-20.md`.
Power table: `../../rule-ablation/protocols/round-20-power.py`.

## What exists

`reviews/` holds the review outputs written so far, copied out of the session
scratchpad because that directory is session-scoped and a new session cannot
find it. `briefs/` holds the four briefs the agents were given; `arms.diff`
shows W minus each other arm, generated from the actual catalogue snapshots.

**Reviews complete at the pause: 77 of 108.** Reviews 1–6 are complete in all
four arms (72 files). Review 7 is partial. Reviews 8 and 9 have none.

Some agents launched before the pause were still running when the snapshot was
taken, so a few of the files listed as missing below may have landed afterwards.
**Check `reviews/` against this list before relaunching anything** — relaunching
a review that already exists would overwrite a completed one with a second
sample and silently break the pairing.

## Still to run — 31 agents

```
W-7-c    W-8-a    W-8-b    W-8-c    W-9-a    W-9-b    W-9-c
W12-7-b  W12-7-c  W12-8-a  W12-8-b  W12-8-c  W12-9-a  W12-9-b  W12-9-c
W23-7-b  W23-7-c  W23-8-a  W23-8-b  W23-8-c  W23-9-a  W23-9-b  W23-9-c
W2-7-b   W2-7-c   W2-8-a   W2-8-b   W2-8-c   W2-9-a   W2-9-b   W2-9-c
```

Each is one agent, given exactly this and nothing else:

> Read `<repo>/evals/rule-precision/round-20/briefs/brief-<ARM>.md` first and
> follow it exactly. It is your complete task specification.
> Your output path is `<somewhere>/<ARM>-<review>-<part>.md`.

**The briefs in `briefs/` contain absolute paths into the paused session's
scratchpad** (`.../e5fcdaef-.../scratchpad/round-20/cat-<ARM>`). Those catalogue
directories will not exist in a new session. Before relaunching, rebuild the
four arms from `bc0f966` and rewrite the paths — the build is scripted in the
protocol's terms and the resulting `common-rules.md` must match `arms.diff`.
**Verify W and W2 are byte-identical to round 19's arms before running
anything**, as this round's pre-registration requires.

## What must NOT happen on resume

- **Do not measure a partial round.** The pre-registered analysis is paired
  across four arms at n=9. Reviews 7–9 are incomplete; measuring 1–6 would be an
  n=6 round that was never pre-registered.
- **Do not treat "reviews 1–6 are complete" as a stopping point.** n=6 was
  explicitly rejected in the protocol: at round 19's observed sd_d it cannot see
  an even split of the joint effect, which is the case the round exists for.
- **Do not change the arms, the brief, or the review condition** to make the
  remainder cheaper. Anything that differs between the first 72 reviews and the
  last 36 becomes a confound with the arm.
- **Do not run the gate or `measure.py` until all 108 exist.** The gate is
  pre-registered to run once, alone, before any arm mean.

## Operational note for whoever resumes

Concurrency is capped at 20 subagents (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`).
Launching a full review of 12 at once works; launching 24 does not, and the
excess is rejected outright rather than queued. The rejections are free but they
leave an arm short until you notice, so **launch one review index at a time (4
arms × 3 parts = 12) and confirm all 12 landed before starting the next.**

Two hazards seen repeatedly in this round, both already in the protocol's
working rules and both worth restating:

- An agent's `DONE` fires twice sometimes, with **different** line counts. The
  file on disk after the dust settles is what counts.
- Several agents hard-wrap their fields across lines (630, 841, 975, 735 lines
  against a norm of ~180) while writing a normal ~30 findings. That is
  formatting, not content; `../extract.py` joins continuation lines and is the
  extractor this round must use.

## Cost so far

77 reviews at roughly 90k tokens each, about 6.9M. The weekly window read 26%
when the round began and 34% at the pause. The remaining 31 reviews plus
clustering and adjudication are about 3.5M.
