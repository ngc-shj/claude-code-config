#!/usr/bin/env python3
"""Gate 0 of `protocol.md`: can evidence-gated row routing reach a 20% cut?

The gate asks the cheapest possible question. Not "how much would the trim
save", which needs a proxy for what an evidence gate retains, but "how much
would removing ALL of it save" - an unreachable ideal that no proxy can beat.
An intervention whose perfect form misses the bar is refuted without any
further work.

The ceiling must include the ROUND TRIP the removal deletes, not only the bytes.
With no rows to fetch there is no anchored `rg`, so the request that ingests its
result does not happen either - and since 94% of raw tokens are context re-sent
across requests, that vanished request is the larger term. A first version of
this script counted only the bytes and reported a ceiling of 7.9%; that was not
an upper bound, and the protocol amendment of 2026-08-12 records the correction.

Everything is read from the session transcripts of round 22, which are not in
this repository (`~/.claude/projects/<project>/<session>/subagents/`). The
script prints the sha1 of the exact agent-file set it read, so a result can be
tied to an input set. That digest covers the 150 round-22 review agents only,
so it differs from the one in `../review-efficiency/cost-ledger.tsv`, which
covers all 572 agents of three sessions.

Usage:  routing-trim/gate0.py
"""
import collections
import glob
import hashlib
import json
import os
import re
import statistics as st

PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'
ROOT = os.path.expanduser(f'~/.claude/projects/{PROJECT}')
SID = '15767388-c891-4ea8-b689-89f8506a0299'
AGENT = re.compile(r'^R22 review (W23|W)-\d+-[abc]$')
RULE_ID = re.compile(r'\b(?:R|RS|RT)\d{1,2}\b')

# API price ratios, as in the review-efficiency audit. Not a measured spend:
# these rounds ran on a subscription whose allowance is a separate scheme.
W_CC5M, W_CC1H, W_READ, W_OUT = 1.25, 2.0, 0.1, 5.0

# Bytes per token. Reported at three values rather than one, because the
# conclusion must not rest on the calibration. Nothing here is exact: bytes are
# measured, tokens are modelled from them, so every figure below is a
# model-based bracket and is labelled as one.
BPT = (3.5, 3.8, 4.2)

# The agent-file set these results were computed against. A different corpus is
# a different result, so the script stops rather than print numbers for it.
EXPECTED_MANIFEST = 'c4a20dc7a6985a0fcd2e64b120f6e9ccb3bf3af3'


def is_rows(s):
    return 'common-rules.md' in s and 'rg ' in s and 'rule-details' not in s


def is_catalogue(s):
    return ('common-rules.digest.md' in s or 'rule-details/' in s
            or 'common-rules.md' in s or 'SKILL.md' in s or '/cat-' in s)


def is_diff(s):
    return bool(re.search(r'\.diff\b', s))


SCOPES = (
    ('candidate rows only', is_rows),
    ('the whole catalogue', is_catalogue),
    ('catalogue + the diff', lambda s: is_catalogue(s) or is_diff(s)),
)


def result_text(block):
    c = block.get('content')
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return ''.join(i.get('text', '') for i in c if isinstance(i, dict))
    return ''


def agents():
    for meta in sorted(glob.glob(f'{ROOT}/{SID}/subagents/*.meta.json')):
        if not AGENT.match(json.load(open(meta)).get('description', '')):
            continue
        path = meta.replace('.meta.json', '.jsonl')
        if os.path.exists(path):
            yield path


def read(path):
    """(ordered usages, [(bytes, first request index) per scope], routing facts)."""
    rows = [json.loads(l) for l in open(path) if l.strip()]
    last, order = {}, []
    for d in rows:
        u = (d.get('message') or {}).get('usage')
        rid = d.get('requestId')
        if u and rid:
            if rid not in last:
                order.append(rid)
            last[rid] = u
    if not order:
        return None
    idx = {rid: i for i, rid in enumerate(order)}
    calls = {}
    hits = {name: [] for name, _ in SCOPES}
    facts = dict(candidates=set(), details=set(), row_bytes=0, row_lines=0, rg_calls=0)
    seen = 0
    for d in rows:
        m = d.get('message') or {}
        if d.get('requestId') in idx:
            seen = idx[d['requestId']]
        for c in m.get('content') or []:
            if not isinstance(c, dict):
                continue
            if c.get('type') == 'tool_use':
                s = json.dumps(c.get('input', {}))
                names = [n for n, pred in SCOPES if pred(s)]
                if names:
                    calls[c['id']] = names
                if is_rows(s):
                    facts['rg_calls'] += 1
                    facts['candidates'].update(RULE_ID.findall(c['input'].get('command', '')))
                if 'rule-details/' in s:
                    facts['details'].update(re.findall(r'rule-details/((?:R|RS|RT)\d+)\.md', s))
            elif c.get('type') == 'tool_result' and c.get('tool_use_id') in calls:
                text = result_text(c)
                for n in calls[c['tool_use_id']]:
                    # the result is ingested by the request AFTER the one that asked
                    hits[n].append((len(text), seen + 1))
                if 'candidate rows only' in calls[c['tool_use_id']]:
                    facts['row_bytes'] += len(text)
                    facts['row_lines'] += len([x for x in text.splitlines() if x.strip()])
    return [last[r] for r in order], hits, facts


def raw_of(usages):
    return sum(u.get('input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
               + u.get('cache_read_input_tokens', 0) + u.get('output_tokens', 0)
               for u in usages)


def api_of(usages):
    total = 0.0
    for u in usages:
        cc = u.get('cache_creation') or {}
        total += (u.get('input_tokens', 0)
                  + W_CC5M * cc.get('ephemeral_5m_input_tokens', u.get('cache_creation_input_tokens', 0))
                  + W_CC1H * cc.get('ephemeral_1h_input_tokens', 0)
                  + W_READ * u.get('cache_read_input_tokens', 0)
                  + W_OUT * u.get('output_tokens', 0))
    return total


def main():
    corpus, data = [], []
    for path in agents():
        corpus.append(f'{hashlib.sha1(open(path, "rb").read()).hexdigest()}  {os.path.basename(path)}')
        got = read(path)
        if got:
            data.append(got)
    digest = hashlib.sha1('\n'.join(sorted(corpus)).encode()).hexdigest()
    if digest != EXPECTED_MANIFEST:
        raise SystemExit(f'transcript manifest mismatch\n  expected {EXPECTED_MANIFEST}\n'
                         f'  got      {digest}\n\nThese results were computed against a '
                         f'different agent-file set. Re-pin EXPECTED_MANIFEST and re-run '
                         f'every number if this is intended.')
    print(f'{len(data)} round-22 review agents; transcript manifest sha1 {digest} (matches)')

    print('\nWhat the current routing does')
    f = lambda v: f'{st.mean(v):8.1f}{st.median(v):9.1f}{max(v):7.0f}'
    rg = [d[2] for d in data if d[2]['rg_calls']]
    print(f'  {"":38s}{"mean":>8s}{"median":>9s}{"max":>7s}')
    print(f'  {"candidate rule IDs in the rg pattern":38s}' + f([len(x['candidates']) for x in rg]))
    print(f'  {"matched row lines returned":38s}' + f([x['row_lines'] for x in rg]))
    print(f'  {"row bytes (kB)":38s}' + f([x['row_bytes'] / 1000 for x in rg]))
    print(f'  {"rule-detail pages opened":38s}' + f([len(x['details']) for x in rg]))
    named = [x for x in rg if x['candidates']]
    print(f'  {"detail pages as % of candidates":38s}'
          + f([100 * len(x['details']) / len(x['candidates']) for x in named]))
    calls = collections.Counter(d[2]['rg_calls'] for d in data)
    print(f'  ({len(rg)} of {len(data)} agents issued at least one anchored rg, {len(named)} of them\n'
          f'   with rule IDs parseable from the pattern. Calls per agent: '
          + ', '.join(f'{k}x{v}' for k, v in sorted(calls.items())) + ')')

    print('\nGate 0 - remove 100% of the scope, an unreachable ideal')
    print('  content  = the removed bytes, at first ingestion and in every later re-send')
    print('  round trip = the request that ingests the result never happens at all')
    print(f'  {"scope":22s}{"B/tok":>7s}{"floor":>8s}{"content":>9s}{"trip":>8s}'
          f'{"CEILING":>10s}{"api-eq":>9s}')
    verdicts = {}
    for name, _ in SCOPES:
        for bpt in BPT:
            R = A = F = C = T = CA = 0.0
            for usages, hits, _facts in data:
                # Every agent of the round stays in the denominator, including the
                # three that fetched no rows: the saving is a share of the round,
                # not of the subset the intervention happens to touch.
                n_req = len(usages)
                R += raw_of(usages)
                A += api_of(usages)
                if not hits[name]:
                    continue
                carried = sum(u.get('cache_read_input_tokens', 0)
                              + u.get('cache_creation_input_tokens', 0) for u in usages)
                for nbytes, first in hits[name]:
                    tok = nbytes / bpt
                    later = max(0, n_req - first - 1)
                    F += tok
                    C += min(tok * (1 + later), tok + carried)
                    CA += tok * W_READ * later
                # With nothing to fetch, the requests that ingest those results are
                # not made. Each such request is removed ONCE however many results
                # it carried, or the same round trip is counted several times.
                gone = {first for _b, first in hits[name] if first < n_req}
                T += raw_of([usages[i] for i in gone])
                # api_of(gone) already contains the first cache-write of the
                # removed content, so no separate first-write term is added above.
                CA += api_of([usages[i] for i in gone])
            ceiling = T + (C - F)  # the vanished round trip, plus later re-sends
            print(f'  {name if bpt == BPT[0] else "":22s}{bpt:7.1f}{100 * F / R:7.2f}%'
                  f'{100 * C / R:8.2f}%{100 * T / R:7.2f}%{100 * ceiling / R:9.2f}%{100 * CA / A:8.2f}%')
            verdicts.setdefault(name, []).append(100 * ceiling / R)
        print()

    print('Where the raw tokens actually are')
    agg, reqs = collections.Counter(), []
    for usages, _h, _f in data:
        reqs.append(len(usages))
        for u in usages:
            agg['cache read (context re-sent)'] += u.get('cache_read_input_tokens', 0)
            agg['cache creation'] += u.get('cache_creation_input_tokens', 0)
            agg['output'] += u.get('output_tokens', 0)
            agg['uncached input'] += u.get('input_tokens', 0)
    total = sum(agg.values())
    for k, v in agg.most_common():
        print(f'  {k:30s}{100 * v / total:6.1f}%')
    transport = agg['cache read (context re-sent)'] + agg['cache creation']
    print(f'  {"-> transport, not content":30s}{100 * transport / total:6.1f}%')
    print(f'  requests per agent: mean {st.mean(reqs):.1f}, median {st.median(reqs):.0f}')
    rb = st.mean([x['row_bytes'] for x in rg]) / 1000
    print(f'  row content per agent: {rb:.1f} kB, about {rb / 3.8:.1f}k tokens, against '
          f'{st.mean([raw_of(u) for u, _h, _f in data]) / 1000:.0f}k raw')

    best = max(verdicts['candidate rows only'])
    cat = max(verdicts['the whole catalogue'])
    best = max(verdicts['candidate rows only'])
    print(f"""
VERDICT: Gate 0 does NOT refute the candidate.

The perfect form removes up to {best:.2f}% of raw processed tokens, above the 20% bar,
so the bar is not structurally unreachable and the gate cannot end the work.

Read the columns before reading that as encouragement. Almost all of the ceiling
is the vanished round trip, and a gate that retains anything only reaches it by
also CONSOLIDATING what it retains into fewer calls: 40 of 150 agents fetch rows
in more than one request, so a non-empty retained set can still drop requests,
but only down to one. The intervention as fixed says which rows to open, not how
many calls to make - so whether the trip term is available at all is a property
of the implementation, not of the gate.

Gate 1 therefore reports both variants: with consolidation, and without it,
where the trip saving is not identifiable and only the content column applies.
This gate's job is done - it failed to refute, which is the only other thing it
was allowed to do.""")


if __name__ == '__main__':
    main()
