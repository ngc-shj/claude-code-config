# Round 16 — stopped at its own tripwire, with a second fixture to show for it

Pre-registration: `../../rule-ablation/protocols/round-16.md`.

**Two of the ten pre-registered reviews ran, the manipulation check said the
treatment did not arrive, and the round stopped there** — 8 reviews and 5.4M
tokens unspent. The stopping-rule question is unanswered. What the round did buy
is a second fixture with an adjudicated inventory, which five earlier conclusions
had had to do without.

```bash
evals/rule-precision/round-16/seed/prepare-adjudication.py   # the id-conservation gate
```

Read § "Manipulation check" for the result and § "The round stopped here" for
what it does and does not license.

## The fixture

`../../rule-ablation/fixtures/F10-webhooks.diff` — outbound webhook delivery for
a B2B SaaS, Python 3.11 + asyncio, 8 files, 470 added lines.

**It was written by an agent that knew nothing about the arms.** This session had
read round 16's protocol before the fixture existed, and the arms differ over
whether a reviewer should stop writing — so an author who knows that has a live
reason to choose how many defects the diff carries. The author agent was given
the domain, the file shape and the line budget, and was told not to label,
count, or comment on any problem it introduced. That agent is not in the
protocol's cost table; it is one agent beyond the nine.

Size, against the protocol's "comparable size to F9":

| | claimed insertions | actual added lines |
|---|---|---|
| F9 | 437 | **297** |
| F10 | 470 | **470** |

F9's diffstat overstates its own added lines by 140. Against F9's claimed number
F10 is +7.5%; against its real one, +58%. Both are recorded because "comparable
size" was pre-registered against the claimed figure. The fixture was **not**
trimmed to close the gap: choosing which hunks to cut is exactly the decision the
blind author existed to keep away from someone who knows the arms.

## The seed inventory

`seed/inventory.tsv` — **64 claims, 54 of them real.** Built by the protocol's
method: five panellists enumerate independently, clusters at ≥3/5 survive, three
adjudicators judge them blind under the rounds 11–15 brief.

| | |
|---|---|
| entries enumerated | 361 (A 90, B 69, C 70, D 72, E 60) |
| distinct claims after clustering | 93 |
| kept at ≥3/5 panellists | **64** |
| below threshold, not in the seed | 29 |
| adjudicator pairwise agreement | **92.2 – 96.9%** |
| claims with no majority verdict | 0 |
| verdicts | 54 `real`, 9 `not-a-defect`, 1 `wrong` |

### The threshold earns its place, and its bottom row does not

| panellists | claims | real | rate |
|---|---|---|---|
| 5/5 | 42 | 38 | 90.5% |
| 4/5 | 12 | 11 | 91.7% |
| 3/5 | 10 | 5 | **50.0%** |

Four-of-five and five-of-five agreement predict `real` at about nine in ten. At
exactly three, it is a coin flip. The ≥3/5 rule is doing real filtering work —
and the ten claims at the boundary are the least trustworthy part of the seed. A
later round that wants a cleaner standard should consider 4/5, and pay ten
claims for it.

### Density against F9, which is the requirement that mattered

| | claims | real | real % | added lines | real per added line |
|---|---|---|---|---|---|
| F9 at round 11 | 83 | 39 | 47.0% | 297 | 0.131 |
| F9 after rounds 11–15 | 135 | 61 | 45.2% | 297 | 0.205 |
| **F10 seed** | **64** | **54** | **84.4%** | 470 | **0.115** |

Defect density is comparable — 0.115 against F9's 0.131 at the equivalent stage,
and F9 grew to 0.205 as four rounds of arm output accumulated into it, which is
what F10's append-only growth will do too.

**The `real` percentages are not comparable and must not be read as a quality
difference.** F9's inventory is the union of what review replies claimed, so it
carries every preference and scope call a reviewer filed — 47% real is a property
of review output. F10's seed is the subset three of five independent panellists
*agreed on*, which filters preferences out before adjudication ever sees them —
84% real is a property of that filter. The two numbers measure different objects.

### What the seed cannot be

A seed panel that has not seen the arms misses defects the arms will find; this
is the caveat the protocol states, and it is why the inventory is append-only
rather than frozen complete. What is frozen tonight is **the standard and the
seed**. Every verdict in `seed/inventory.tsv` is final: it is not revisited in
window 1, in window 2, or in a later round, because `real` has to mean the same
thing in both windows for the paired analysis to be worth anything.

## The adjudication brief, recovered rather than reconstructed

The protocol requires the brief to be byte-identical to the one rounds 11–15
used and checked in "so the comparison can be audited rather than trusted". It
had never been checked in — it lived in a previous session's scratchpad, which
still existed. `../adjudication-brief.md` is that file with the three lines that
already varied between rounds turned into slots (`{N}`, `{DIFF}`, `{CLAIMS}`).

The identity is verified, not asserted — rendering the template at each round's
own claim count and paths reproduces all five instances byte-for-byte:

| round | claims | md5 of the recovered brief |
|---|---|---|
| 11 | 83 | `26695173d0f798749e55647f58d78867` |
| 12 | 6 | `60ca2bd529d1410891d6e36699581589` |
| 13 | 6 | `5616d5a9e8f61ba30af586739c1a6336` |
| 14 | 20 | `e8ba8a47ae325d23a9105a1225d4ecae` |
| 15 | 20 | `e2bc3a769f80aa60369548c924a03132` |

`briefs/adjudicate-brief-seed.md` is tonight's rendering at N=64 against F10.
One thing about it is worth flagging: the standing assumption's illustrative list
names F9's parts ("the ORM schema, the middleware that calls the guard, the
session layer"), which F10 does not have. It is left byte-identical, because the
sentence that carries the standard is the one before the list — everything the
diff does not show exists and is correct — and rewording the list to suit the new
fixture would be a change to the standard made by someone who knows the arms.

## The arms, rendered and checked

`briefs/` holds all three. `brief-T.md` is round 15's brief-T with two paths
swapped (the fixture, the catalogue snapshot) and `brief-base.md` is round 15's
brief-I the same way. `brief-TS.md` is `brief-T.md` plus the pre-registered
stopping paragraph and nothing else:

```bash
diff <(sed '/^## When to stop$/,$d' briefs/brief-TS.md) briefs/brief-T.md   # empty
```

That check passes byte-for-byte. Making it pass required one deviation worth
recording: **`brief-T.md` carries a trailing blank line round 15's did not**, so
that deleting the appended section leaves T exactly. The alternative was to
weaken the pre-registered `sed` check. A trailing newline is invisible to a
reviewer reading the brief; a loosened verification command is not.

### The manipulation is smaller than the protocol implies

Recorded before any arm output exists, because it changes how a null should be
read. Round 15's brief-T already ends:

> If after reading it you have nothing to add, state `No findings` rather than
> padding.

So TS does not introduce a stopping rule — T has one. What TS adds is a restated
permission plus one genuinely new sentence:

> That a finding is not on the list is not by itself a reason to report it.

The protocol's mechanism check says zero `No findings` replies means "the wording
did not land". The finding above sharpens that: T's own escape hatch already
licenses `No findings`, so if **both** arms produce zero, what failed is not TS's
phrasing but the premise that a reviewer given an escape hatch will take it. The
wording is unchanged — it is pre-registered — but the reading of a null is now
narrower than the protocol wrote it.

## The catalogue, frozen

Every agent tonight and in both windows reads one snapshot of
`skills/triangulate/` taken at `bc0f966`, with the digest's own example paths
rewritten to the snapshot — the same preparation rounds 12–15 used, and
`SKILL.md`, `common-rules.md` and `rule-details/` are byte-identical to theirs.
The snapshot lives in the session scratchpad, so the briefs checked in here name
paths that will not outlive the run; the catalogue they point at is recoverable
from the commit.

## Cost so far, and what the log could not tell us

The protocol budgets 9 agents and ≈0.6M tokens for the seed inventory — 5
panellists, 1 merge, 3 adjudicators. All nine ran, plus the blind fixture author
the cost table does not carry.

| | agents | tokens |
|---|---|---|
| blind fixture author | 1 | 86,464 |
| seed panellists | 5 | 245,494 |
| merge | 1 | 117,707 |
| adjudicators | 3 | 149,573 |
| **seed total** | **10** | **599,238** |
| base, reviews 1–2 | 6 | 509,425 |
| T, reviews 1–2 | 6 | 440,655 |
| TS, reviews 1–2 | 6 | 423,263 |
| **round total** | **28** | **1,972,581** |

0.60M against a 0.6M seed budget, at one agent over. The arm agents came in
lighter than the base wave — 73k and 71k against 85k — because a reviewer told
what is already covered stops early; the protocol's per-review estimate of 9 ×
~80k held.

At the reading below, the eight reviews not run would have cost about **5.4M**.

One reading of the plan's own percentages was taken by hand from the mobile
usage screen at **22:06, with the weekly window having opened at 20:00 the same
evening: 2% of the weekly allowance used, 9% of the five-hour one.** At that
point 16 agents and 1.11M tokens had been spent. It is a single observation,
floored to whole percent, transcribed from a screenshot rather than logged — and
the flooring is the point: 2% could be anything from 2.00 to 2.99, so the same
1.11M implies a weekly allowance anywhere between about 37M and 55M. A round
sized against that number inherits a 1.5× uncertainty, which is precisely the
resolution problem `hooks/statusline-usage.sh` was written to remove and did not,
here, get the chance to.

**`~/.claude/usage-log.jsonl` recorded nothing**, so the rate-limit percentages
this round was meant to be measured against do not exist for it. The instrument
is sound — fed a synthetic payload, `hooks/statusline-usage.sh` prints
`5h 12.34% 7d 3.5%` and records both decimals — but no `.state` or `.lock` file
was ever created, so the status line was never invoked in this session's
transport. The token figures above come from the per-agent completion reports
instead, which is a different quantity from a share of a weekly window and
should not be substituted for one when the windows are compared.

## Manipulation check, reviews 1–2, recorded before deciding anything

18 agents. Written down before the question "do we pay for the other eight
reviews" was put, so the answer cannot reshape the record.

| | replies | findings | per reply | replies ending `No findings` |
|---|---|---|---|---|
| base | 6 | 163 | 27.2 | **0** |
| T | 6 | 51 | 8.5 | **0** |
| TS | 6 | 40 | 6.7 | **0** |

Per reply — base `33 25 27 27 26 25`, T `7 10 7 10 9 8`, TS `9 6 6 4 7 8`.
"No findings" does not occur anywhere in any of the 18 replies, in any casing.
**No metric, threshold or prediction above was changed after seeing this**, and
nothing else was computed: the primary and the control need adjudication, which
the append-only rule holds until after window 2.

The pre-registered tripwire says stop. The protocol's mechanism check reads: if
the count of `No findings` replies is zero, "the sentence did not arrive, and
the round says nothing about stopping rules — only about that wording."

**The other half of the same mechanism moved.** Findings written is the
protocol's own second mechanism measure, and TS wrote 21% fewer than T on the
same six bases. Something in TS landed; what did not happen is any reviewer
concluding it had *nothing* to add.

That is the reading this README pre-registered before any arm ran, in
§ "The manipulation is smaller than the protocol implies": T's brief already
ends by licensing `No findings`, so a zero in **both** arms tests the premise
that a reviewer takes an offered escape hatch, not TS's phrasing. Two reviews
now say that premise is false on this fixture. And F10 is dense — 64 seeded
claims at ≥3/5 over 470 lines — so "no defect worth reporting that the list does
not already cover" may be an outcome the fixture cannot produce at all, which
would make the tripwire uninformative here rather than negative.

**Both of those are arguments for continuing, and both were written down before
the numbers existed. That does not make them safe.** The tripwire is a
pre-registered stopping rule and it fired; continuing means overriding it, and
the override would have been chosen by someone who had already seen that findings
written moved in the direction the round hoped for.

## The round stopped here

**The pre-registration was honoured. The remaining eight reviews were not run.**

So round 16's result is its manipulation check, and the claim it supports is the
narrow one the protocol licensed in advance:

> On F10, the sentence *"If there is no defect worth reporting that the list does
> not already cover, end with `No findings`"* produced no `No findings` reply in
> six attempts, against six for the arm without it, which also produced none.

Nothing follows about stopping rules. Nothing follows about the primary metric,
which was never computed. The 21% gap in findings written is **recorded and not
claimed**: n=2 reviews, no adjudication behind it, and it is exactly the kind of
number that becomes a finding if you let the arm it favours choose the analysis.

The cost of honouring the rule was 5.4M tokens not spent. The cost of breaking it
would have been that no future reader could tell which of this round's rules were
fixed in advance and which were chosen once the data was in — which is the whole
value the pre-registration files in `../../rule-ablation/protocols/` carry.

## What this round leaves behind

The stopping rule question is unanswered, and three durable things exist that did
not this morning:

1. **A second fixture** with an adjudicated inventory. Five conclusions rested on
   F9; the next round that wants to replicate one of them no longer has to.
2. **The adjudication brief is in the repository**, checksum-verified against all
   five rounds that used it, instead of living in a scratchpad one `rm` from gone.
3. **A measured reason to doubt the tripwire.** `No findings` may be unreachable
   on a dense fixture, in which case it cannot discriminate between "the wording
   failed" and "the fixture never permitted the outcome". A cheap way to settle
   that independently — run T and TS on a low-density fixture and see whether
   `No findings` is producible at all — would let a future round 16 re-run rest on
   evidence that does not come from its own arms. That test does not exist yet and
   this round does not claim its result.

## What would have run next

Reviews 3–10 of window 1: 72 agents, then the variance check the protocol
pre-registered — recompute both paired sds from the 10 differences and re-size
window 2 before running it if either exceeds ×1.15 of the borrowed value. That
path is closed for this round and the materials to walk it are all here, so a
later round re-running from `briefs/` and `seed/` starts at review 3 rather than
at the fixture.
