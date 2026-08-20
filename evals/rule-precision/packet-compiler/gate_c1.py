#!/usr/bin/env python3
"""Gate C1 of `protocol.md`: what a compiler that actually covers the review costs.

Gate C0 handed each agent the packet IT turned out to need - a different packet
per agent, and no compiler can produce that, because a compiler sees the change
and not the reviewer. A real compiler emits ONE packet for the fixture, and the
protocol's coverage condition says it must carry every rule any review used.

That makes the verdict independent of how well any particular selection rule is
written. One packet covering every agent must contain the UNION of what the agents
used, so the union is the cheapest packet that satisfies the condition, and its
cost is a bound on every compiler's cost from below - a bound on the saving from
above. If the union fails the bar, no compiler passes it.

`compiler.py`'s own selection is reported beside it, blind and unadjusted, because
the protocol required that number recorded before anything was fitted.

Costing follows Gate C0: the digest goes, the historical catalogue fetches go, the
packet is ingested once at the request the digest used to arrive at, and it is
carried by every surviving request from there on. Bytes are UTF-8.

Usage:  packet-compiler/gate_c1.py     (env: CAT_W, F11_DIFF)
"""
import collections
import hashlib
import importlib.util
import json
import os
import re
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g = _load('gate0', os.path.join(HERE, os.pardir, 'routing-trim', 'gate0.py'))
b0 = _load('gate_b0', os.path.join(HERE, os.pardir, 'request-batching', 'gate_b0.py'))
c0 = _load('gate_c0', os.path.join(HERE, 'gate_c0.py'))
C = _load('compiler', os.path.join(HERE, 'compiler.py'))

AGENT = re.compile(r'^R22 review (W23|W)-(\d+)-([abc])$')
DEV_LAST = 10          # reviews 1-10 are dev; 11-25 are holdout. Fixed in `408e83d`.
BAR = 20.0


def used_rules(path):
    """Every rule this agent fetched a row for or opened a page of."""
    out = set()
    for line in open(path):
        if not line.strip():
            continue
        d = json.loads(line)
        for c in (d.get('message') or {}).get('content') or []:
            if isinstance(c, dict) and c.get('type') == 'tool_use':
                t = g.tool_target(c.get('name', ''), c.get('input', {}))
                if g.is_rows(t):
                    out |= set(g.RULE_ID.findall(t))
                out |= g.page_ids(t)
    return out


def used_pages(path):
    out = set()
    for line in open(path):
        if not line.strip():
            continue
        d = json.loads(line)
        for c in (d.get('message') or {}).get('content') or []:
            if isinstance(c, dict) and c.get('type') == 'tool_use':
                out |= g.page_ids(g.tool_target(c.get('name', ''), c.get('input', {})))
    return out


def compiled_round(ag, packet, bpt):
    """Raw tokens saved when THIS packet replaces the digest and the fetches.

    Costed from scratch, as in Gate C0's `rebuilt()`: every surviving request pays
    its own context, minus the digest and the catalogue results it no longer
    carries, plus the packet once it has arrived. The packet is one object for the
    whole fixture, so every surviving request from the host onward carries all of
    it - not, as in C0, each member from where it happened to arrive.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    if not ag['packet'] or not ag['digest']:
        return 0.0
    host = min(r for _b, _c, r in ag['digest'])
    gone = {q for q in ag['n_gone']
            if q < n_req and ag['n_results'].get(q, 0) == ag['n_gone'][q]} - {host}
    before = sum(b0.context_of(u) + u.get('output_tokens', 0) for u in usages)
    after = 0.0
    for q, u in enumerate(usages):
        if q in gone:
            if not b0.keeps_its_output(ag['resp'], q, b0.PRIMARY):
                after += u.get('output_tokens', 0)
            continue
        after += b0.context_of(u) + u.get('output_tokens', 0)
        after -= sum(nbytes / bpt for nbytes, _c, req in ag['digest'] if req <= q)
        after -= sum(nbytes / bpt for nbytes, _c, req in ag['packet'] if req <= q)
        if q >= host:
            after += packet / bpt
    return before - after


def main():
    root, diff_path = os.environ.get('CAT_W'), os.environ.get('F11_DIFF')
    if not root or not diff_path:
        raise SystemExit('set CAT_W (arm W catalogue) and F11_DIFF (the pinned diff)')
    cat_manifest = hashlib.sha1(b''.join(
        open(os.path.join(dp, f), 'rb').read()
        for dp, _d, fs in sorted(os.walk(root)) for f in sorted(fs))).hexdigest()
    diff = open(diff_path, encoding='utf-8').read()
    print(f'catalogue {root}\n  content sha1 {cat_manifest}')
    print(f'diff {os.path.basename(diff_path)}  '
          f'sha1 {hashlib.sha1(diff.encode()).hexdigest()}  {len(diff)} bytes')

    corpus, data, keys, used, pages = [], [], [], {}, {}
    for path in g.agents():
        meta = json.load(open(path.replace('.jsonl', '.meta.json')))
        m = AGENT.match(meta['description'])
        corpus.append(f'{hashlib.sha1(open(path, "rb").read()).hexdigest()}  {os.path.basename(path)}')
        got = c0.scan(path)
        if not got:
            continue
        k = (m.group(1), int(m.group(2)), m.group(3))
        keys.append(k)
        data.append(got)
        used[k] = used_rules(path)
        pages[k] = used_pages(path)
    digest = hashlib.sha1('\n'.join(sorted(corpus)).encode()).hexdigest()
    if digest != g.EXPECTED_MANIFEST:
        raise SystemExit(f'transcript manifest mismatch\n  expected {g.EXPECTED_MANIFEST}\n'
                         f'  got      {digest}')
    print(f'{len(data)} round-22 review agents; transcript manifest sha1 {digest} (matches)')

    dev = [k for k in keys if k[1] <= DEV_LAST]
    hold = [k for k in keys if k[1] > DEV_LAST]
    rows, pagetext = C.catalogue(root)

    union = set().union(*used.values())
    union_pages = set().union(*pages.values())
    blind, blind_pages = C.compile_packet(diff, root)
    whole, whole_pages = C.compile_packet(diff, root, everything=True)

    print('\nCoverage - a packet must carry every rule the review used')
    print(f'  {"packet":34s}{"rules":>7s}{"pages":>7s}{"kB":>8s}'
          f'{"dev":>10s}{"holdout":>10s}')
    packets = (('compiler.py, blind and unadjusted', blind, blind_pages),
               ('the union of what agents used', union, union_pages),
               ('the whole catalogue', whole, whole_pages))
    sizes = {}
    for name, sel, pgs in packets:
        nbytes = (sum(len(rows[r].encode('utf-8')) for r in sel if r in rows)
                  + sum(len(pagetext[r].encode('utf-8')) for r in pgs if r in pagetext))
        sizes[name] = nbytes
        ok = lambda ks: sum(1 for k in ks if used[k] <= sel)
        print(f'  {name:34s}{len(sel):7d}{len(pgs):7d}{nbytes / 1000:8.1f}'
              f'{ok(dev):>7d}/{len(dev):<3d}{ok(hold):>7d}/{len(hold):<3d}')
    print(f'  ({len(union)} of the {len(rows)} catalogue rules were used by at least one '
          f'agent; mean {st.mean(len(v) for v in used.values()):.1f} per agent)')

    print('\nGate C1 - raw-token saving with a packet that covers the review')
    print(f'  {"packet":34s}{"B/tok":>7s}{"all 150":>10s}{"dev":>9s}{"holdout":>9s}')
    verdict = {}
    for name, sel, pgs in packets:
        for bpt in g.BPT:
            share = {}
            for label, ks in (('all', keys), ('dev', dev), ('hold', hold)):
                idx = [i for i, k in enumerate(keys) if k in set(ks)]
                R = sum(g.raw_of(data[i]['usages']) for i in idx)
                S = sum(compiled_round(data[i], sizes[name], bpt) for i in idx)
                share[label] = 100 * S / R
            print(f'  {name if bpt == g.BPT[0] else "":34s}{bpt:7.1f}'
                  f'{share["all"]:9.2f}%{share["dev"]:8.2f}%{share["hold"]:8.2f}%')
            verdict.setdefault(name, []).append(share['hold'])
        print()

    cover_name = 'the union of what agents used'
    best = max(verdict[cover_name])
    covered = all(used[k] <= union for k in hold)
    refuted = best < BAR
    print(f'VERDICT: Gate C1 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print(f'  cheapest packet that covers every holdout agent: {min(verdict[cover_name]):.2f}'
          f'-{best:.2f}% (holdout)')
    print(f'  every holdout agent covered by it: {covered}')
    print(f"""
The union is the smallest packet that can satisfy the coverage condition, because
one packet serves every review and must contain each agent's own set. Any compiler
that covers the review emits at least this, so its saving is at most this figure -
whatever its selection rule. That is why the verdict does not depend on how well
`compiler.py` is written, and why no amount of adjusting it on the dev split could
change the answer.

{"Gate C1 ends the line of work: no compiler that carries what the review used clears the bar."
 if refuted else "Gate C1 cannot end the line of work."}""")


if __name__ == '__main__':
    main()
