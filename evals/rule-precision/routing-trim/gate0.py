#!/usr/bin/env python3
"""Gate 0 of `protocol.md`: can evidence-gated row routing reach a 20% cut?

The gate asks the cheapest possible question. Not "how much would the trim
save", which needs a proxy for what an evidence gate retains, but "how much
would removing ALL of it save" - an unreachable ideal that no proxy can beat.
An intervention whose perfect form misses the bar is refuted without any
further work.

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
# conclusion must not rest on the calibration.
BPT = (3.5, 3.8, 4.2)


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
    print(f'{len(data)} round-22 review agents; transcript manifest sha1 {digest}')

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
    print(f'  ({len(rg)} of {len(data)} agents issued an anchored rg, {len(named)} of them with rule\n'
          f'   IDs parseable from the pattern; the rest routed differently)')

    print('\nGate 0 - remove 100% of the scope, an unreachable ideal')
    print(f'  {"scope":24s}{"bytes/token":>12s}{"floor":>9s}{"ceiling":>10s}{"api-eq ceiling":>16s}')
    verdicts = {}
    for name, _ in SCOPES:
        for bpt in BPT:
            R = A = F = C = CA = 0.0
            for usages, hits, _facts in data:
                if not hits[name]:
                    continue
                n_req = len(usages)
                R += raw_of(usages)
                A += api_of(usages)
                carried = sum(u.get('cache_read_input_tokens', 0)
                              + u.get('cache_creation_input_tokens', 0) for u in usages)
                for nbytes, first in hits[name]:
                    tok = nbytes / bpt
                    later = max(0, n_req - first)
                    F += tok
                    C += min(tok * (1 + later), tok + carried)
                    CA += tok * W_CC5M + tok * W_READ * later
            print(f'  {name if bpt == BPT[0] else "":24s}{bpt:12.1f}'
                  f'{100 * F / R:8.2f}%{100 * C / R:9.2f}%{100 * CA / A:15.2f}%')
            verdicts.setdefault(name, []).append(100 * C / R)
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
    print(f'  requests per agent: mean {st.mean(reqs):.1f}, median {st.median(reqs):.0f}')
    rb = st.mean([x['row_bytes'] for x in rg]) / 1000
    print(f'  row content per agent: {rb:.1f} kB, about {rb / 3.8:.1f}k tokens, against '
          f'{st.mean([raw_of(u) for u, _h, _f in data]) / 1000:.0f}k raw')

    worst = max(verdicts['candidate rows only'])
    cat = max(verdicts['the whole catalogue'])
    print(f'\nVERDICT: the perfect form of the intervention removes at most {worst:.1f}% of raw\n'
          f'processed tokens against a 20% bar, at every calibration tested. Gate 0 fails\n'
          f'and the line of work stops.\n\n'
          f'Removing the ENTIRE catalogue reaches at most {cat:.1f}%, so the failure is not specific\n'
          f'to this candidate. Note the difference in robustness: the candidate misses by\n'
          f'{20 - worst:.0f} points and the whole catalogue by {20 - cat:.1f}, so the broader claim - that no\n'
          f'catalogue-routing intervention clears 20% - holds under this model but would\n'
          f'not survive a materially more generous one. The candidate\'s own failure would.')


if __name__ == '__main__':
    main()
