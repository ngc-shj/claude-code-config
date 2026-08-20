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
g1 = _load('gate1', os.path.join(HERE, os.pardir, 'routing-trim', 'gate1.py'))

AGENT = re.compile(r'^R22 review (W23|W)-(\d+)-([abc])$')
DEV_LAST = 10          # reviews 1-10 are dev; 11-25 are holdout. Fixed in `408e83d`.
CONTROL = 'W'          # `../GOAL.md`: W23 is the arm with clause 1 removed.
BAR = 20.0

# The compiler's own invocation. It is issued once and its result is the packet,
# and it is charged like a packet member because the protocol says this gate
# measures the command it actually issues.
COMMAND = ('python3 evals/rule-precision/packet-compiler/compiler.py '
           '--diff evals/rule-ablation/fixtures/F11-exports.diff '
           '--catalogue skills/triangulate')

# The inputs, pinned. Printing a hash is not checking one: a different catalogue
# or a different diff produced numbers just as happily until these were compared.
EXPECTED_CATALOGUE = 'b78f25e5e76c3c17aefa0d076a2644730ce9b6a0'
EXPECTED_DIFF = 'ff54f2e6afae8f26d250952acabaa10597116497'


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


def catalogue_manifest(root):
    """sha1 over `relative path + content hash` for every file in the catalogue."""
    lines = []
    for dirpath, _dirs, files in sorted(os.walk(root)):
        for name in sorted(files):
            full = os.path.join(dirpath, name)
            lines.append(f'{os.path.relpath(full, root)}  '
                         f'{hashlib.sha1(open(full, "rb").read()).hexdigest()}')
    return hashlib.sha1('\n'.join(sorted(lines)).encode()).hexdigest()


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
            after += (packet + len(COMMAND.encode('utf-8'))) / bpt
    return before - after


def main():
    root, diff_path = os.environ.get('CAT_W'), os.environ.get('F11_DIFF')
    if not root or not diff_path:
        raise SystemExit('set CAT_W (arm W catalogue) and F11_DIFF (the pinned diff)')
    cat_manifest = catalogue_manifest(root)
    diff = open(diff_path, encoding='utf-8').read()
    diff_sha = hashlib.sha1(diff.encode()).hexdigest()
    for label, got, want in (('catalogue', cat_manifest, EXPECTED_CATALOGUE),
                             ('diff', diff_sha, EXPECTED_DIFF)):
        if got != want:
            raise SystemExit(f'{label} manifest mismatch\n  expected {want}\n'
                             f'  got      {got}\n\nThese numbers were computed against a '
                             f'different {label}. Re-pin and re-run every figure if this '
                             f'is intended.')
    print(f'catalogue {root}\n  path+content manifest sha1 {cat_manifest} (matches)')
    print(f'diff {os.path.basename(diff_path)}  sha1 {diff_sha} (matches)  {len(diff)} bytes')

    corpus, data, keys, used, pages = [], [], [], {}, {}
    for path in g.agents():
        meta = json.load(open(path.replace('.jsonl', '.meta.json')))
        k = g1.agent_key(meta['description'])
        if k is None:
            raise SystemExit(f'{os.path.basename(path)} is not a round-22 review agent')
        corpus.append((hashlib.sha1(open(path, 'rb').read()).hexdigest(),
                       os.path.basename(path), k))
        got = c0.scan(path)
        if not got:
            continue
        keys.append(k)
        data.append(got)
        used[k] = used_rules(path)
        pages[k] = used_pages(path)
    # Which review each transcript IS decides which agents the control arm and the
    # holdout contain, so it is hashed with the bytes - `gate1.py` already does
    # exactly this and is imported rather than copied.
    g1.check_keys(keys)
    assert sum(1 for k in keys if k[0] == CONTROL) == g1.REVIEWS * len(g1.PARTS)
    got_manifest = g1.manifest_digest(corpus)
    if got_manifest != g1.EXPECTED_GATE1_MANIFEST:
        raise SystemExit(f'agent-to-review manifest mismatch\n'
                         f'  expected {g1.EXPECTED_GATE1_MANIFEST}\n'
                         f'  got      {got_manifest}\n\nThe transcripts, or which review '
                         f'each one is, are not what these numbers came from.')
    print(f'{len(data)} round-22 review agents; agent-to-review manifest sha1 '
          f'{got_manifest} (matches); {CONTROL} is complete at '
          f'{g1.REVIEWS} x {len(g1.PARTS)}')

    dev = [k for k in keys if k[1] <= DEV_LAST]
    hold = [k for k in keys if k[1] > DEV_LAST]
    # The primary is the control arm's holdout, and the covering packet for it is
    # built from those agents alone: a union that has seen the dev split is not a
    # bound on an unseen one.
    hold_w = [k for k in hold if k[0] == CONTROL]
    rows, pagetext = C.catalogue(root)

    union_w = set().union(*(used[k] for k in hold_w))
    union_w_pages = set().union(*(pages[k] for k in hold_w))
    union_all = set().union(*used.values())
    union_all_pages = set().union(*pages.values())
    blind, blind_pages = C.compile_packet(diff, root)
    whole, whole_pages = C.compile_packet(diff, root, everything=True)

    print(f'\nCoverage - a packet must carry every rule the review used '
          f'({CONTROL} holdout is {len(hold_w)} agents, of {len(keys)})')
    print(f'  {"packet":36s}{"rules":>7s}{"pages":>7s}{"kB":>8s}'
          f'{"W holdout":>12s}{"all 150":>10s}')
    packets = (('compiler.py, blind and unadjusted', blind, blind_pages),
               ('union over the W holdout (primary)', union_w, union_w_pages),
               ('union over all 150', union_all, union_all_pages),
               ('the whole catalogue', whole, whole_pages))
    sizes = {}
    for name, sel, pgs in packets:
        nbytes = (sum(len(rows[r].encode('utf-8')) for r in sel if r in rows)
                  + sum(len(pagetext[r].encode('utf-8')) for r in pgs if r in pagetext))
        sizes[name] = nbytes
        ok = lambda ks: sum(1 for k in ks if used[k] <= sel)
        print(f'  {name:36s}{len(sel):7d}{len(pgs):7d}{nbytes / 1000:8.2f}'
              f'{ok(hold_w):>8d}/{len(hold_w):<3d}{ok(keys):>6d}/{len(keys):<3d}')
    print(f'  ({len(union_all)} of the {len(rows)} catalogue rules were used by at least '
          f'one agent; mean {st.mean(len(v) for v in used.values()):.1f} per agent)')

    print('\nGate C1 - raw-token saving with a packet that covers the review')
    print(f'  {"packet":36s}{"B/tok":>7s}{"W holdout":>12s}{"W dev":>9s}{"all 150":>10s}')
    verdict = {}
    groups = (('W hold', hold_w), ('W dev', [k for k in dev if k[0] == CONTROL]),
              ('all', keys))
    for name, sel, pgs in packets:
        for bpt in g.BPT:
            share = {}
            for label, ks in groups:
                want = set(ks)
                idx = [i for i, k in enumerate(keys) if k in want]
                R = sum(g.raw_of(data[i]['usages']) for i in idx)
                S = sum(compiled_round(data[i], sizes[name], bpt) for i in idx)
                share[label] = 100 * S / R
            print(f'  {name if bpt == g.BPT[0] else "":36s}{bpt:7.1f}'
                  f'{share["W hold"]:11.2f}%{share["W dev"]:8.2f}%{share["all"]:9.2f}%')
            verdict.setdefault(name, []).append(share['W hold'])
        print()

    cover_name = 'union over the W holdout (primary)'
    best = max(verdict[cover_name])
    covered = all(used[k] <= union_w for k in hold_w)
    refuted = best < BAR
    print(f'VERDICT: Gate C1 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print(f'  cheapest packet covering every {CONTROL} holdout agent: '
          f'{min(verdict[cover_name]):.2f}-{best:.2f}%')
    print(f'  every {CONTROL} holdout agent covered by it: {covered}')
    print(f"""
The union is the smallest packet that can satisfy the coverage condition on those
agents, because one packet serves every review and must contain each agent's own
set. Any compiler that covers them emits at least this, so its saving is at most
this figure - whatever its selection rule. That is why the verdict does not depend
on how well `compiler.py` is written, and why no adjustment of it on the dev split
could change the answer.

The control is arm {CONTROL}; W23 is the arm with clause 1 removed and is reported
beside the primary rather than in it. `../GOAL.md` fixes that, and the protocol's
third amendment records that this figure was scoped after the first was computed.

{"Gate C1 ends the line of work: no compiler that carries what the review used clears the bar."
 if refuted else "Gate C1 cannot end the line of work."}""")


if __name__ == '__main__':
    main()
