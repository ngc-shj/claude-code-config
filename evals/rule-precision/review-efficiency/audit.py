#!/usr/bin/env python3
"""Review-efficiency audit: what a review actually costs, and what buys the coverage.

Retrospective and exploratory. It states no confirmatory result, tests no
hypothesis anyone pre-registered, and changes no skill. Everything comes from
rounds 12-22 as committed, plus per-agent token counts recovered from the
session transcripts those rounds ran in (`cost-ledger.tsv`, built by
`_ledger.py`).

Inputs are PINNED: `inputs.sha1` lists every repository file this audit reads
with its blob hash, and `verify()` checks the path set and the hashes before a
number is produced. The claim verdicts come from `../design-audit/_data.py`
rather than being re-derived here, so the two audits cannot disagree about which
claims are real.

Usage:  review-efficiency/audit.py
"""
import collections
import csv
import hashlib
import itertools
import os
import statistics as st
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'design-audit'))
import _data                                                    # noqa: E402
import _ledger                                                  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EVALS = _data.EVALS

# Cost-equivalent tokens, in units of one base input token. Anthropic's published
# ratios: cache write 1.25x (5m TTL) / 2x (1h), cache read 0.1x, output 5x. This
# is the only unit in this audit in which a cached re-send and a generated token
# are comparable quantities.
W_CC5M, W_CC1H, W_READ, W_OUT = 1.25, 2.0, 0.1, 5.0


def cost_eq(r):
    return (r['uncached'] + W_CC5M * r['cc5m'] + W_CC1H * r['cc1h']
            + W_READ * r['cache_read'] + W_OUT * r['output'])


def verify():
    man = os.path.join(HERE, 'inputs.sha1')
    want = {}
    for line in open(man):
        if line.startswith('#') or not line.strip():
            continue
        h, rel = line.split()
        want[rel] = h
    bad = []
    for rel, h in sorted(want.items()):
        full = os.path.join(EVALS, rel)
        if not os.path.exists(full):
            bad.append(f'MISSING  {rel}')
        else:
            data = open(full, 'rb').read()
            got = hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()
            if got != h:
                bad.append(f'CHANGED  {rel}')
    pinned = {rel for rel in want if '/adjudications/' in rel}
    for d in {os.path.dirname(r) for r in pinned}:
        on_disk = {f'{d}/{n}' for n in os.listdir(os.path.join(EVALS, d)) if n.endswith('.tsv')}
        for extra in sorted(on_disk - pinned):
            bad.append(f'UNPINNED {extra}  (a sheet this audit was not written against)')
    if bad:
        raise SystemExit('input verification failed:\n  ' + '\n  '.join(bad)
                         + '\n\nRe-pin inputs.sha1 and re-run every number if this is intended.')
    return len(want)


# ---------------------------------------------------------------- data loading

def round13():
    """Round 13: 8 reviews x 6 identical generalists on F9. One arm, no clause 1.

    Its verdict inventory is the one round 13 itself used - rounds 11-12's
    adjudications plus its own 6 new claims - not the F10/F11 inventory rounds
    20-22 share.
    """
    verdict = _data.verdicts([f'{EVALS}/adjudications', f'{EVALS}/round-12/adjudications',
                              f'{EVALS}/round-13/adjudications'])
    f2c = {}
    for row in csv.DictReader(open(f'{EVALS}/round-13/clusters.tsv', newline=''), delimiter='\t'):
        for fid in row['member_ids'].split(','):
            f2c[fid.strip()] = row['cluster_id']
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for f in csv.DictReader(open(f'{EVALS}/round-13/findings.tsv', newline=''), delimiter='\t'):
        by[int(f['review'])][f['part']].append(f)
    return f2c, verdict, by


def arm_reviews(name, arm):
    """{review index: {part: [findings]}} for one arm of rounds 20-22."""
    rd, verdict, n = _data.ROUNDS[name]
    f2c, by = _data.load(rd, verdict)
    return f2c, verdict, {i: by[arm][i] for i in range(1, n + 1)}


# ------------------------------------------------------------------- measures

def reached(fs, f2c, verdict):
    return {f2c[f['id']] for f in fs if verdict.get(f2c[f['id']]) == 'real'}


def noise(fs, f2c, verdict):
    return sum(1 for f in fs if _data.CM(f) and verdict.get(f2c[f['id']]) == 'not-a-defect')


def subsets(by_part, k):
    return list(itertools.combinations(sorted(by_part), k))


def curve(f2c, verdict, reviews, kmax):
    """Mean per review over every k-subset of the same reviewers."""
    out = {}
    for k in range(1, kmax + 1):
        real, noi, dup, tot = [], [], [], []
        for parts in reviews.values():
            for sub in subsets(parts, k):
                fs = [f for p in sub for f in parts[p]]
                claims = [f2c[f['id']] for f in fs]
                real.append(len(reached(fs, f2c, verdict)))
                noi.append(noise(fs, f2c, verdict))
                tot.append(len(fs))
                dup.append(1 - len(set(claims)) / len(claims) if claims else 0.0)
        out[k] = dict(real=st.mean(real), noise=st.mean(noi),
                      findings=st.mean(tot), dup=st.mean(dup))
    return out


def severe_misses(f2c, verdict, reviews, k, kmax):
    """Real claims the full panel reached that a k-subset misses, C/M-flagged only."""
    miss = []
    for parts in reviews.values():
        full = [f for p in parts for f in parts[p]]
        severe = {f2c[f['id']] for f in full if _data.CM(f)} & reached(full, f2c, verdict)
        for sub in subsets(parts, k):
            got = reached([f for p in sub for f in parts[p]], f2c, verdict)
            miss.append(len(severe - got))
    return st.mean(miss)


# ---------------------------------------------------------------------- report

def rule(title):
    print(f'\n{title}\n' + '-' * len(title))


def section_ledger(led):
    rule('1. What the rounds cost, in units that mean something')
    reviews = [r for r in led if r['role'] == 'review']
    rec = [r for r in led if r['reported']]
    err = st.median([abs(r['ctx_final'] - r['reported']) / r['reported'] for r in rec])
    print(f"""
Every token figure in the round READMEs is `subagent_tokens` from the task
notification. Reconciled against the transcripts, that number is the FINAL
REQUEST'S CONTEXT: median relative error {err:.4f} over the {len(rec)} agents that
reported one, with the notification running about {st.median([r['reported'] - r['ctx_final'] for r in rec]):.0f} tokens higher. It is
a peak-context measure - no re-sent context from earlier turns, no output at
all. It is not a consumption figure and the prior rounds' totals should not be
read as one.

  measure                          per review agent, round 22
  ctx_final   (what was reported)  {st.mean([r['ctx_final'] for r in led if r['round'] == 'round 22']) / 1000:8.1f}k
  sent        (uncached + cache writes){st.mean([r['uncached'] + r['cc5m'] + r['cc1h'] for r in led if r['round'] == 'round 22']) / 1000:6.1f}k
  re-sent     (cache reads)        {st.mean([r['cache_read'] for r in led if r['round'] == 'round 22']) / 1000:8.1f}k
  output                           {st.mean([r['output'] for r in led if r['round'] == 'round 22']) / 1000:8.1f}k
  cost-equivalent (1x/1.25x/0.1x/5x){st.mean([cost_eq(r) for r in led if r['round'] == 'round 22']) / 1000:6.1f}k
""")
    print(f'{"round":10s}{"agents":>7s}{"sent":>9s}{"re-sent":>9s}{"output":>8s}'
          f'{"cost-eq":>9s}{"ctx_final":>10s}{"round total":>13s}')
    for rnd in sorted({r['round'] for r in reviews}):
        g = [r for r in reviews if r['round'] == rnd]
        f = lambda k: st.mean([r[k] for r in g]) / 1000
        print(f'{rnd:10s}{len(g):7d}'
              f'{st.mean([r["uncached"] + r["cc5m"] + r["cc1h"] for r in g]) / 1000:9.1f}k'
              f'{f("cache_read"):8.1f}k{f("output"):7.1f}k'
              f'{st.mean([cost_eq(r) for r in g]) / 1000:8.1f}k{f("ctx_final"):9.1f}k'
              f'{sum(cost_eq(r) for r in g) / 1e6:11.1f}M')
    for rnd, stated in (('round 21', 4.53), ('round 22', 12.5)):
        g = [r for r in reviews if r['round'] == rnd]
        print(f'cross-check: {rnd} reviews sum to {sum(r["ctx_final"] for r in g) / 1e6:.2f}M by ctx_final, '
              f'against the {stated}M its README states')
    r22 = [r for r in reviews if r['round'] == 'round 22']
    ratio = st.mean([cost_eq(r) for r in r22]) / st.mean([r['ctx_final'] for r in r22])
    print(f'\nConsequence for the design audit, which priced future rounds at the reported\n'
          f'rate: cost-equivalent spend runs {ratio:.1f}x ctx_final, so the n-per-arm designs it\n'
          f'called unaffordable are {ratio:.1f}x more expensive than it stated. That strengthens\n'
          f'its "do not spend" conclusion and changes nothing else about it.')
    print('\nreviews are the production-shaped agents; the rest is evaluation machinery')
    print(f'{"role":12s}{"agents":>7s}{"cost-eq mean":>14s}{"total":>10s}')
    for role in ('review', 'adjudicate', 'cluster', 'seed', 'other'):
        g = [r for r in led if r['role'] == role]
        if not g:
            continue
        print(f'{role:12s}{len(g):7d}{st.mean([cost_eq(r) for r in g]) / 1000:13.1f}k'
              f'{sum(cost_eq(r) for r in g) / 1e6:9.1f}M')
    dupes = collections.Counter((r['round'], r['arm'], r['review'], r['part']) for r in reviews)
    retried = [k for k, v in dupes.items() if v > 1]
    print(f'\nre-runs (same arm/review/part launched twice): {len(retried)}'
          + (f' - {", ".join(f"{k[0]} {k[1]} r{k[2]}{k[3]}" for k in sorted(retried))}' if retried else ''))
    print('No Codex or Ollama agent ran in any of these rounds: the eval harness is '
          'Claude-only.\nThe production skill does call Ollama for seed findings before '
          'the reviewers,\nwhich costs zero Claude tokens and is not measured here.')


def section_composition(led):
    rule('2. Where a review agent\'s tokens go')
    g = [r for r in led if r['role'] == 'review' and r['round'] == 'round 22']
    n = len(g)
    b = {k: sum(r[f'bytes_{k}'] for r in g) / n for k in ('catalogue', 'diff', 'harness', 'other')}
    content = sum(b.values())
    sent = st.mean([r['uncached'] + r['cc5m'] + r['cc1h'] for r in g])
    out = st.mean([r['output'] for r in g])
    ce = st.mean([cost_eq(r) for r in g])
    print(f"""
Content the agent pulled in, measured as tool-result bytes ({n} round-22 agents):

  catalogue (digest, rules table, rule-detail pages) {b['catalogue'] / 1000:8.1f} kB {100 * b['catalogue'] / content:5.1f}%
  the diff under review                              {b['diff'] / 1000:8.1f} kB {100 * b['diff'] / content:5.1f}%
  harness (brief, wc -l handshake, writing output)   {b['harness'] / 1000:8.1f} kB {100 * b['harness'] / content:5.1f}%
  other                                              {b['other'] / 1000:8.1f} kB {100 * b['other'] / content:5.1f}%
  total                                              {content / 1000:8.1f} kB

Bytes are exact; the share of SPEND they carry is not, because the same content
is written into the cache repeatedly as the conversation grows. Measured:
{sent / 1000:.0f}k tokens ingested against {content / 1000:.0f} kB of tool-result content, i.e. about {sent / (content / 3.8):.1f}x
what the content alone would be at 3.8 bytes/token. This audit measures that
ratio; it does not establish its mechanism (cache-breakpoint placement versus
TTL expiry), though requests made more than 5 minutes after the previous one -
where the ephemeral cache has certainly expired - carry only {100 * sum(r['cc_after_gap'] for r in g) / sum(r['cc5m'] + r['cc1h'] for r in g):.0f}% of the
cache creation, so plain TTL expiry does not explain it.

In cost-equivalent terms the split is not content at all:

  cache writes  {st.mean([W_CC5M * r['cc5m'] + W_CC1H * r['cc1h'] for r in g]) / 1000:7.1f}k {100 * st.mean([W_CC5M * r['cc5m'] + W_CC1H * r['cc1h'] for r in g]) / ce:5.1f}%
  output        {W_OUT * out / 1000:7.1f}k {100 * W_OUT * out / ce:5.1f}%   ({out / 1000:.1f}k tokens at 5x)
  cache reads   {W_READ * st.mean([r['cache_read'] for r in g]) / 1000:7.1f}k {100 * W_READ * st.mean([r['cache_read'] for r in g]) / ce:5.1f}%
  uncached      {st.mean([r['uncached'] for r in g]) / 1000:7.1f}k

Two levers follow, and neither is the reviewer count: the catalogue is the
largest single body of content read, and output at 5x is the largest single
line of cost.""")


def section_k(led):
    rule('3. Reviewer-count replay')
    per_agent = {}
    for rnd in ('round 20', 'round 21', 'round 22'):
        g = [r for r in led if r['role'] == 'review' and r['round'] == rnd]
        per_agent[rnd] = st.mean([cost_eq(r) for r in g])
    print(f"""
Sub-sampling C(3,k) subsets of the same agents is only unbiased for identical
reviewers, which parts a/b/c are: same brief, same catalogue, no role split.
This is therefore a curve for "k generalists", and the shipped configuration is
three ROLE-SPECIALISED experts. No round measured the specialist curve.

Cost per reviewer is the round's own measured mean cost-equivalent per agent
(round 20 {per_agent['round 20'] / 1000:.0f}k, 21 {per_agent['round 21'] / 1000:.0f}k, 22 {per_agent['round 22'] / 1000:.0f}k), and k costs k x that. The three
reviewers of a review run against the same brief and the same catalogue, so a
shared prefix might have made the 2nd and 3rd cheaper; measured, they are not -
round 22 means by position are """
          + ', '.join(f'{p}={st.mean([cost_eq(r) for r in led if r["role"] == "review" and r["round"] == "round 22" and r["part"] == p]) / 1000:.0f}k'
                      for p in 'abc') + '.')
    for name in ('round 20', 'round 21', 'round 22'):
        for arm in ('W', 'W23'):
            f2c, verdict, reviews = arm_reviews(name, arm)
            c = curve(f2c, verdict, reviews, 3)
            print(f'\n{name}, arm {arm} ({len(reviews)} reviews)')
            print(f'{"k":>2s}{"real claims":>13s}{"marginal":>10s}{"C+M non-defect":>16s}'
                  f'{"dup rate":>10s}{"severe miss":>13s}{"cost-eq":>10s}{"per marginal claim":>20s}')
            prev = None
            for k in (1, 2, 3):
                v = c[k]
                cost = k * per_agent[name]
                marg = v['real'] - (prev['real'] if prev else 0)
                per = (per_agent[name] / marg) if marg > 0 else float('inf')
                print(f'{k:2d}{v["real"]:13.2f}{marg:10.2f}{v["noise"]:16.2f}'
                      f'{v["dup"]:10.2f}{severe_misses(f2c, verdict, reviews, k, 3):13.2f}'
                      f'{cost / 1000:9.0f}k'
                      + (f'{per / 1000:19.0f}k' if marg > 0 else f'{"-":>20s}'))
                prev = v
    f2c, verdict, reviews = round13()
    c = curve(f2c, verdict, reviews, 6)
    print(f"""
Round 13 (F9, 8 reviews x 6 identical generalists, one arm, a different fixture
and an earlier rule set) is shown separately and must not be pooled with the
above: different fixture, different inventory, no arm. Its own write-up already
recorded that three role-specialised experts reached what five of these
generalists reached, on a cross-round comparison that was context, not a
control.""")
    print(f'{"k":>2s}{"real claims":>13s}{"marginal":>10s}{"C+M non-defect":>16s}{"dup rate":>10s}')
    prev = 0.0
    for k in range(1, 7):
        v = c[k]
        print(f'{k:2d}{v["real"]:13.2f}{v["real"] - prev:10.2f}{v["noise"]:16.2f}{v["dup"]:10.2f}')
        prev = v['real']


SEQ_THRESHOLDS = (13, 14, 15, 16, 17)


def cm_count(fs):
    return sum(1 for f in fs if _data.CM(f))


def policies(f2c, verdict, reviews, unit):
    """Fixed-k, first-reviewer-triggered sequential, and an oracle upper bound.

    Sequential policies are averaged over all 3! orderings of the reviewers, so
    none of them benefits from which reviewer happened to be labelled 'a'.
    """
    out = {}
    for k in (1, 2, 3):
        c = curve(f2c, verdict, reviews, k)[k]
        out[f'always k={k}'] = dict(real=c['real'], noise=c['noise'], cost=k * unit, esc=None)
    for sense in ('>=', '<='):
        for thr in SEQ_THRESHOLDS:
            real, noi, cost, esc = [], [], [], []
            for parts in reviews.values():
                for order in itertools.permutations(sorted(parts)):
                    n = cm_count(parts[order[0]])
                    fire = n >= thr if sense == '>=' else n <= thr
                    k = 3 if fire else 1
                    fs = [f for p in order[:k] for f in parts[p]]
                    real.append(len(reached(fs, f2c, verdict)))
                    noi.append(noise(fs, f2c, verdict))
                    cost.append(k * unit)
                    esc.append(k == 3)
            out[f'seq: 1, then 3 if r1 C+M {sense} {thr}'] = dict(
                real=st.mean(real), noise=st.mean(noi), cost=st.mean(cost), esc=st.mean(esc))
    real, noi, cost, esc = [], [], [], []
    for parts in reviews.values():
        for order in itertools.permutations(sorted(parts)):
            full = reached([f for p in order for f in parts[p]], f2c, verdict)
            k = next((k for k in (1, 2, 3)
                      if reached([f for p in order[:k] for f in parts[p]], f2c, verdict) == full), 3)
            fs = [f for p in order[:k] for f in parts[p]]
            real.append(len(reached(fs, f2c, verdict)))
            noi.append(noise(fs, f2c, verdict))
            cost.append(k * unit)
            esc.append(k > 1)
    out['ORACLE (not implementable)'] = dict(real=st.mean(real), noise=st.mean(noi),
                                             cost=st.mean(cost), esc=st.mean(esc))
    return out


def trigger_signal(f2c, verdict, reviews):
    """Does reviewer 1's own output predict what reviewers 2-3 would add?"""
    xs, ys = [], []
    for parts in reviews.values():
        for order in itertools.permutations(sorted(parts)):
            first = reached(parts[order[0]], f2c, verdict)
            allr = reached([f for p in order for f in parts[p]], f2c, verdict)
            xs.append(cm_count(parts[order[0]]))
            ys.append(len(allr - first))
    return xs, ys, st.correlation(xs, ys)


def section_policies(led, arm='W'):
    rule('4. Adaptive policies, replayed on round 22')
    unit = st.mean([cost_eq(r) for r in led if r['role'] == 'review' and r['round'] == 'round 22'])
    f2c, verdict, reviews = arm_reviews('round 22', arm)
    xs, ys, r = trigger_signal(f2c, verdict, reviews)
    print(f"""
Fixed-k policies against a sequential one that decides from the FIRST
reviewer's own output only - the Critical/Major finding count it reports, which
a runtime harness can see without adjudication.

The oracle row picks the smallest k that reaches everything k=3 reaches. It
reads the later reviewers' results to decide whether to launch them, so it is
an upper bound on what any first-reviewer rule could reach, not a candidate.

Round 22, arm {arm} ({len(reviews)} reviews), cost-eq unit {unit / 1000:.0f}k per reviewer.

The trigger statistic barely varies: reviewer 1's C+M count runs {min(xs)}-{max(xs)}
(mean {st.mean(xs):.1f}, sd {st.stdev(xs):.1f}) across {len(xs)} (review, ordering) pairs - the Finding Floor
holds output shape nearly constant. Its correlation with the claims reviewers
2-3 go on to add is r = {r:+.2f}: NEGATIVE, so escalating when reviewer 1 finds a
LOT is backwards. Both directions are shown below.

That correlation is partly mechanical - a reviewer who reports more findings
has already reached more claims, leaving fewer for the others - so it is a
description of this sample, not evidence that the statistic is a good trigger.
""")
    print(f'{"policy":34s}{"real":>8s}{"C+M nd":>9s}{"cost-eq":>10s}{"escalated":>11s}{"vs k=3":>9s}')
    pol = policies(f2c, verdict, reviews, unit)
    base = pol['always k=3']['cost']
    for name, v in pol.items():
        esc = f'{100 * v["esc"]:10.0f}%' if v['esc'] is not None else f'{"-":>11s}'
        print(f'{name:34s}{v["real"]:8.2f}{v["noise"]:9.2f}{v["cost"] / 1000:9.0f}k'
              f'{esc}{100 * v["cost"] / base - 100:8.0f}%')
    return unit, f2c, verdict, reviews


def section_rules():
    rule('5. Rule-level ROI: not measured, and what it would take')
    total = mention = 0
    per_rule = collections.Counter()
    import re
    pat = re.compile(r'\b(R|RS|RT)(\d{1,2})\b')
    for f in csv.DictReader(open(f'{EVALS}/round-22/findings.tsv', newline=''), delimiter='\t'):
        total += 1
        ids = {m.group(0) for m in pat.finditer(f['title'] + ' ' + f['what_is_wrong'])}
        if ids:
            mention += 1
        per_rule.update(ids)
    print(f"""
`findings.tsv` has no rule column - its fields are id, arm, review, part,
severity, target, file, title, what_is_wrong. Nothing in the pipeline records
which catalogue row produced a finding, so unique-real-claim, non-defect and
trigger-frequency per rule CANNOT be computed from what was kept, and this
audit does not estimate them.

What is recoverable is weaker and is reported as such: {mention} of {total} round-22
findings ({100 * mention / total:.0f}%) name at least one rule ID somewhere in their text. A
mention is not an attribution - a finding can cite a rule it was not routed by,
and a routed finding need not cite anything - so this bounds what text mining
could reach at best, not what the rules did.

  most-mentioned IDs: """ + ', '.join(f'{k} x{v}' for k, v in per_rule.most_common(8)) + f"""

Minimum telemetry to make it measurable, all inside normal operation:
  1. the reviewer emits the rule IDs it routed to, once per run (it already
     extracts them with anchored rg - the list exists and is discarded);
  2. each finding carries the ID it was written against, or `none`;
  3. the run records its own token counts, so cost per rule is divisible.
(1) and (3) are free. (2) is one field in the output shape, and it is the only
one that turns a per-run list into a per-finding attribution.""")


def section_frontier(led, unit, f2c, verdict, reviews):
    rule('6. Pareto frontier, and the one candidate to test forward')
    cands = {k: (v['real'], v['noise'], v['cost'])
             for k, v in policies(f2c, verdict, reviews, unit).items()
             if k != 'ORACLE (not implementable)'}
    # A catalogue trim is a cost-only projection: it removes read bytes and
    # their transport, and asserts nothing about what it does to coverage.
    g = [r for r in led if r['role'] == 'review' and r['round'] == 'round 22']
    cat = st.mean([r['bytes_catalogue'] for r in g])
    tot = st.mean([sum(r[f'bytes_{k}'] for k in ('catalogue', 'diff', 'harness', 'other'))
                   for r in g])
    print(f"""
Axes: real claims reached (up), C+M not-a-defect (down), cost-equivalent tokens
(down). Dominated = another candidate costs no more, reaches no less, and is no
noisier, with at least one strict. Everything here is round 22, arm W, one
fixture: the frontier is descriptive of that sample and is not a claim about
fixtures in general.
""")
    print(f'{"candidate":36s}{"real":>8s}{"C+M nd":>9s}{"cost-eq":>10s}  verdict')
    items = sorted(cands.items(), key=lambda kv: kv[1][2])
    for name, (real, noi, cost) in items:
        dom = [o for o, (r2, n2, c2) in cands.items()
               if o != name and c2 <= cost and r2 >= real and n2 <= noi
               and (c2 < cost or r2 > real or n2 < noi)]
        print(f'{name:36s}{real:8.2f}{noi:9.2f}{cost / 1000:9.0f}k  '
              + (f'dominated by {dom[0]}' if dom else 'FRONTIER'))
    c = curve(f2c, verdict, reviews, 3)
    print(f"""
Every escalate-on-a-HIGH-count policy is dominated by an escalate-on-a-LOW-count
one at similar cost - the sign of the correlation in section 4, showing up in
the frontier. The fixed-k rungs all survive, k=3 included: it is on the frontier
as the only candidate that reaches the most claims. "Change nothing" is a live
option and nothing here argues against it.

THE DECISION RULE, APPLIED LITERALLY, IS DEGENERATE. It says: keep the
non-dominated candidates, then take the largest token cut. That selects
`always k=1` at -67% - and k=1 is on the frontier only because the dominance
test has no coverage floor, so a candidate that loses {100 * (1 - c[1]['real'] / c[3]['real']):.0f}% of the real claims
({c[3]['real']:.1f} to {c[1]['real']:.1f} per review) is never excluded. A forward test of k=1 would
measure something three rounds have already measured consistently. Reporting
that selection and stopping there would be following the rule off a cliff.

WHAT WOULD ACTUALLY BE WORTH RUNNING is not on the frontier, and cannot be:
cutting what each reviewer reads from the catalogue. It scores as no candidate
at all here because no round has ever varied it, so it has no coverage number
to be dominated on. Section 2 is the whole argument for it: the catalogue is
{cat / 1000:.0f} kB of the {tot / 1000:.0f} kB a reviewer reads ({100 * cat / tot:.0f}%), and it is a per-reviewer
multiplier - it multiplies through whatever k is chosen, which is exactly what
choosing k cannot do. Output at 5x ({100 * W_OUT * st.mean([r['output'] for r in g]) / st.mean([cost_eq(r) for r in g]):.0f}% of cost-equivalent spend) is the
same shape of lever and the same size of prize.

So the audit records two things rather than one:
  - the rule's own answer, `always k=1`, and why taking it would be a mistake;
  - the recommendation, a catalogue-routing trim at k=3 with the role split
    fixed, flagged as a DEVIATION from the rule because it is unscored.
Choosing between them is the repository owner's call, not this audit's. If the
trim is run, the coverage floor the frontier lacks has to be declared before it
starts - otherwise the forward test inherits the same defect.""")


def main():
    n = verify()
    led, digest = _ledger.load()
    print(f'inputs verified: {n} pinned repository files')
    print(f'cost ledger: {len(led)} agents, transcript manifest {digest[:12]}')
    section_ledger(led)
    section_composition(led)
    section_k(led)
    unit, f2c, verdict, reviews = section_policies(led)
    section_rules()
    section_frontier(led, unit, f2c, verdict, reviews)


if __name__ == '__main__':
    main()
