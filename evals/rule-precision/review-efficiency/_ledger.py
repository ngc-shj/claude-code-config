"""Build `cost-ledger.tsv` from the session transcripts the eval rounds ran in.

The transcripts are NOT in this repository — they live under
`~/.claude/projects/<project>/<session>/subagents/` and are not redistributable
(they contain full agent conversations). What this script writes out is counts
only: no prompt, no reply, no file content. `audit.py` reads the committed
ledger; this script is how the ledger is re-derived, and `--verify` re-derives it
and diffs against the committed copy.

Usage accounting, the part that is easy to get wrong: a `message.usage` block is
written on interim streaming rows as well as on the final row of the same
`requestId`. Summing every row double-counts (x1.63 for subagents, measured).
Key by `requestId`, keep the last row.
"""
import collections
import csv
import glob
import hashlib
import json
import os
import re
import sys

PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'
ROOT = os.path.expanduser(f'~/.claude/projects/{PROJECT}')
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, 'cost-ledger.tsv')

# The three sessions the adjudicated rounds ran in. Rounds 18 and 19 share one
# session AND one description scheme ("N review 3 part a" occurs in both), so
# they are separated by their batch times: round 18 ran 06:41-07:08 on 08-09,
# round 19 at 11:08-11:39, round 20 from 12:20.
SESSIONS = ('e392c887-68cf-492b-a61c-d5d0f9838aa9',
            'e5fcdaef-52e1-475a-bbcb-2116588f0282',
            '15767388-c891-4ea8-b689-89f8506a0299')
R18_END = '2026-08-09T09:00:00'

COLS = ['round', 'role', 'arm', 'review', 'part', 'session', 'agent', 't0',
        'requests', 'tools', 'uncached', 'cc5m', 'cc1h', 'cache_read', 'output',
        'ctx_final', 'reported', 'cc_after_gap', 'bytes_catalogue', 'bytes_diff',
        'bytes_harness', 'bytes_other']


def reported_tokens(sid):
    """`subagent_tokens` as the task notification reported it, per agent id.

    This is the number every round README's cost table is built from, so the
    ledger carries it next to the measured counts and the audit reconciles the
    two rather than asserting what it means.
    """
    out = {}
    path = f'{ROOT}/{sid}.jsonl'
    if not os.path.exists(path):
        return out
    for line in open(path):
        if 'subagent_tokens' not in line:
            continue
        for m in re.finditer(r'<task-id>(\w+)</task-id>.*?<subagent_tokens>(\d+)</subagent_tokens>', line):
            out[m[1]] = int(m[2])
        for m in re.finditer(r'agentId: (\w+) .*?subagent_tokens: (\d+)', line):
            out[m[1]] = int(m[2])
    return out


def classify(session, desc, t0):
    """(round, role, arm, review, part) from the label the orchestrator gave."""
    m = re.match(r'^R22 review (W23|W)-(\d+)-([abc])$', desc)
    if m:
        return 'round 22', 'review', m[1], int(m[2]), m[3]
    m = re.match(r'^Review (W23|W)-(\d+)-([abc])$', desc)
    if m:
        return 'round 21', 'review', m[1], int(m[2]), m[3]
    m = re.match(r'^(W23|W12|W2|W) r(\d+) ([abc])$', desc)
    if m and session == SESSIONS[1]:
        return 'round 20', 'review', m[1], int(m[2]), m[3]
    m = re.match(r'^(N|W) r(\d+) ([abc])$', desc)
    if m and session == SESSIONS[0]:
        return 'round 17', 'review', m[1], int(m[2]), m[3]
    m = re.match(r'^(N|W2|W) review (\d+) part ([abc])$', desc)
    if m:
        return ('round 18' if t0 < R18_END else 'round 19'), 'review', m[1], int(m[2]), m[3]
    low = desc.lower()
    role = ('adjudicate' if 'adjudicat' in low else
            'cluster' if low.startswith('cluster') or low.startswith('assign') else
            'seed' if low.startswith('seed') else 'other')
    return '', role, '', 0, ''


def bucket(name, tool_input):
    """Which material a tool call pulled into the agent's context."""
    s = json.dumps(tool_input)
    if 'common-rules.digest.md' in s or 'rule-details/' in s \
            or 'common-rules.md' in s or 'SKILL.md' in s or '/cat-' in s:
        return 'catalogue'
    if re.search(r'\.diff\b', s):
        return 'diff'
    if 'brief' in s or 'wc -l' in s or name == 'Write':
        return 'harness'
    return 'other'


def seconds_between(a, b):
    if not a or not b:
        return 0.0
    from datetime import datetime
    fmt = lambda s: datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    return fmt(b) - fmt(a)


def result_bytes(block):
    c = block.get('content')
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        return sum(len(i.get('text', '')) if isinstance(i, dict) else len(str(i)) for i in c)
    return 0


def read_agent(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    last, order, when = {}, [], {}
    calls, by_bucket, tools = {}, collections.Counter(), 0
    for d in rows:
        msg = d.get('message') or {}
        rid, usage = d.get('requestId'), msg.get('usage')
        if usage and rid:
            if rid not in last:
                order.append(rid)
                when[rid] = d.get('timestamp', '')
            last[rid] = usage
        for c in msg.get('content') or []:
            if not isinstance(c, dict):
                continue
            if c.get('type') == 'tool_use':
                calls[c.get('id')] = bucket(c.get('name', ''), c.get('input', {}))
                tools += 1
            elif c.get('type') == 'tool_result':
                by_bucket[calls.get(c.get('tool_use_id'), 'other')] += result_bytes(c)
    if not order:
        return None
    agg = collections.Counter()
    for rid in order:
        u = last[rid]
        cc = u.get('cache_creation') or {}
        agg['uncached'] += u.get('input_tokens', 0)
        agg['cache_read'] += u.get('cache_read_input_tokens', 0)
        agg['cc5m'] += cc.get('ephemeral_5m_input_tokens', u.get('cache_creation_input_tokens', 0))
        agg['cc1h'] += cc.get('ephemeral_1h_input_tokens', 0)
        agg['output'] += u.get('output_tokens', 0)
    # Cache creation on a request that follows a gap longer than the 5-minute
    # ephemeral TTL: the part of re-creation that simple expiry would explain.
    for prev, rid in zip(order, order[1:]):
        if seconds_between(when.get(prev, ''), when.get(rid, '')) > 300:
            agg['cc_after_gap'] += last[rid].get('cache_creation_input_tokens', 0)
    fin = last[order[-1]]
    agg['ctx_final'] = (fin.get('input_tokens', 0)
                        + fin.get('cache_creation_input_tokens', 0)
                        + fin.get('cache_read_input_tokens', 0))
    agg['requests'] = len(order)
    agg['tools'] = tools
    for b in ('catalogue', 'diff', 'harness', 'other'):
        agg[f'bytes_{b}'] = by_bucket[b]
    return agg, (when[order[0]] or '')


def build():
    out, manifest = [], []
    for sid in SESSIONS:
        reported = reported_tokens(sid)
        for meta in sorted(glob.glob(f'{ROOT}/{sid}/subagents/*.meta.json')):
            jl = meta[:-len('.meta.json')] + '.jsonl'
            if not os.path.exists(jl):
                continue
            got = read_agent(jl)
            if not got:
                continue
            agg, t0 = got
            desc = json.load(open(meta)).get('description', '')
            aid = os.path.basename(jl)[6:-6]
            rnd, role, arm, review, part = classify(sid, desc, t0)
            out.append(dict(round=rnd, role=role, arm=arm, review=review, part=part,
                            session=sid[:8], agent=aid, t0=t0,
                            reported=reported.get(aid, 0), **agg))
            manifest.append(f'{hashlib.sha1(open(jl, "rb").read()).hexdigest()}  {sid[:8]}/{os.path.basename(jl)}')
    out.sort(key=lambda r: (r['t0'], r['agent']))
    digest = hashlib.sha1('\n'.join(sorted(manifest)).encode()).hexdigest()
    return out, digest


def write(rows, digest):
    with open(LEDGER, 'w', newline='') as f:
        f.write(f'# per-agent token counts, derived by _ledger.py from session transcripts\n')
        f.write(f'# transcript manifest sha1: {digest}  ({len(rows)} agents)\n')
        f.write('# uncached/cc5m/cc1h/cache_read/output: summed over requests, final row per requestId.\n')
        f.write('# ctx_final: the last request\'s context — this is what a task notification reports.\n')
        f.write('# reported: subagent_tokens as the task notification stated it (0 = not found).\n')
        f.write('# cc_after_gap: cache creation on a request >5min after the previous one.\n')
        f.write('# bytes_*: tool-result bytes by the material the call pulled in (not tokens).\n')
        w = csv.DictWriter(f, fieldnames=COLS, delimiter='\t', extrasaction='ignore')
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, 0) for c in COLS})


def load():
    """The committed ledger, plus the transcript-manifest sha1 it was built from."""
    digest = ''
    with open(LEDGER, newline='') as f:
        lines = []
        for line in f:
            if line.startswith('#'):
                m = re.search(r'manifest sha1: (\w+)', line)
                if m:
                    digest = m[1]
                continue
            lines.append(line)
    rows = list(csv.DictReader(lines, delimiter='\t'))
    for r in rows:
        for k in COLS:
            if k not in ('round', 'role', 'arm', 'part', 'session', 'agent', 't0'):
                r[k] = int(r[k])
    return rows, digest


if __name__ == '__main__':
    rows, digest = build()
    if '--verify' in sys.argv:
        old, old_digest = load()
        print(f'committed: {len(old)} agents, manifest {old_digest}')
        print(f'rebuilt:   {len(rows)} agents, manifest {digest}')
        print('MATCH' if old_digest == digest and len(old) == len(rows) else 'DIFFERS')
    else:
        write(rows, digest)
        print(f'{len(rows)} agents -> {LEDGER}\nmanifest sha1 {digest}')
