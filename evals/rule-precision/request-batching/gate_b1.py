#!/usr/bin/env python3
"""Gate B1 of `protocol.md`: batching, with the reviewer's own dependency order.

Gate B0 let one turn issue every catalogue fetch and got 25.25-25.60%. That is a
knowledge assumption, not a scheduling one: 79 of the 150 agents have B0's host at
the very request that ingests the digest, so landing the rows there means knowing
the candidate IDs before reading the digest that produces them.

Gate B1 rebuilds each agent as a chain. Stage 0 is the digest - out of scope,
never moved, and the floor. Stage 1 is everything derived from it, arriving no
earlier than the request after the digest. Per the fourth amendment the figure the
verdict is read from hands each agent the detail set it turned out to open, so the
chain is two-stage for all 150 and no derivation rule can beat it.

The causal window `[d+1, first in-scope arrival]` turns out to have size ONE for
every agent in this corpus - the first catalogue result always arrives exactly one
request after the digest - so the host is forced and there is nothing to choose.

Three figures are reported, because the first is not the largest:

  (a) as registered  the whole batch at the host, every fetch moved
  (b) move-subset    a form free to batch only the fetches worth batching: a
                     result whose request survives anyway gains no round trip and
                     only costs early carry
  (c) + deferred     (b), maximised over every host position at or after the
                     causal floor

(b) and (c) are not the fixed intervention - that one issues ALL the fetches in
one turn - but a claim that no batching form clears the bar has to cover them.

Usage:  request-batching/gate_b1.py
"""
import collections
import hashlib
import importlib.util
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'gate0', os.path.join(HERE, os.pardir, 'routing-trim', 'gate0.py'))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
_b0 = importlib.util.spec_from_file_location('gate_b0', os.path.join(HERE, 'gate_b0.py'))
b0 = importlib.util.module_from_spec(_b0)
_b0.loader.exec_module(b0)

DIGEST = 'common-rules.digest.md'
# The Finding Floor / Remedy Floor extraction is a fixed cost the intervention
# does not touch, and `protocol.md` puts it in the whole-catalogue superset only.
# A handful of commands run it in the same breath as a directory listing, and the
# call-level predicate then pulls the whole result into the primary scope.
FLOOR = re.compile(r'\bawk\b.*(Finding Floor|Remedy Floor)')
BAR = 20.0


class Res:
    __slots__ = ('cp', 'u8', 'req', 'cmd_cp', 'cmd_u8', 'floor_mixed')

    def __init__(self, cp, u8, req, cmd_cp, cmd_u8, floor_mixed):
        self.cp, self.u8, self.req = cp, u8, req
        self.cmd_cp, self.cmd_u8, self.floor_mixed = cmd_cp, cmd_u8, floor_mixed


def scan(path):
    """Everything Gate B1 needs, with bytes counted both ways.

    `gate0.read()` reports `len(text)` - code points. Here the carry penalty is
    the only term the bytes enter, so undercounting them makes the saving LARGER,
    and a near-bar verdict has to see both readings.
    """
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
    n_req = len(order)
    calls, results = {}, []
    n_results = collections.Counter()
    n_scoped = collections.Counter()
    digest, seen = [], 0
    for d in rows:
        m = d.get('message') or {}
        if d.get('requestId') in idx:
            seen = idx[d['requestId']]
        for c in m.get('content') or []:
            if not isinstance(c, dict):
                continue
            if c.get('type') == 'tool_use':
                t = g.tool_target(c.get('name', ''), c.get('input', {}))
                if DIGEST in t:
                    calls[c['id']] = ('digest', t)
                elif g.is_rows(t) or g.is_detail(t):
                    calls[c['id']] = ('scope', t)
            elif c.get('type') == 'tool_result':
                n_results[seen + 1] += 1
                if c.get('tool_use_id') not in calls:
                    continue
                kind, t = calls[c['tool_use_id']]
                if kind == 'digest':
                    if seen + 1 < n_req:
                        digest.append(seen + 1)
                    continue
                text = g.result_text(c)
                n_scoped[seen + 1] += 1
                results.append(Res(len(text), len(text.encode('utf-8')), seen + 1,
                                   len(t), len(t.encode('utf-8')),
                                   bool(FLOOR.search(t))))
    return dict(usages=[last[r] for r in order], results=results, n_results=n_results,
                n_scoped=n_scoped, digest=min(digest) if digest else None,
                resp=b0.responses(path))


def rebuilt(ag, bpt, name):
    """(a), built by costing the batched round instead of subtracting from it.

    Adds up every surviving request's context, the moved results now in it, every
    surviving response and every relocated response of a request that no longer
    exists, then subtracts that from what the round did cost. Shares no term with
    `figures()`: that one subtracts what goes, this one adds up what stays.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    res = [r for r in ag['results'] if r.req < n_req]
    if not res or ag['digest'] is None:
        return 0.0
    host = min(r.req for r in res)
    pure = {q for q in ag['n_scoped']
            if q < n_req and ag['n_results'].get(q, 0) == ag['n_scoped'][q]}
    gone = pure - {host}
    before = sum(b0.context_of(u) + u.get('output_tokens', 0) for u in usages)
    after = 0.0
    for q, u in enumerate(usages):
        if q in gone:
            if not b0.keeps_its_output(ag['resp'], q, name):
                after += u.get('output_tokens', 0)
            continue
        after += b0.context_of(u) + u.get('output_tokens', 0)
        after += sum(r.cp / bpt for r in res if host <= q < r.req)
    return before - after


def cost_of(ag, i, name):
    """What a request stops costing when it is not made: its context, and its
    output only if that response did nothing but fetch the catalogue."""
    u = ag['usages'][i]
    return b0.context_of(u) + (u.get('output_tokens', 0)
                               if b0.keeps_its_output(ag['resp'], i, name) else 0)


def figures(ag, bpt, name, utf8=False, drop_floor=False, charge_calls=False):
    """(a) as registered, (b) move-subset upper, (c) + deferred host.

    (b) is an upper bound over every subset of requests a batching form might
    move: a request contributes at most its own cost less the carry its results
    would pay, and carry is counted only over requests that certainly survive -
    the ones that ingest something out of scope - because eliminating others can
    only reduce it. Each request's decision is independent under that bound.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    res = [r for r in ag['results'] if r.req < n_req and not (drop_floor and r.floor_mixed)]
    if not res or ag['digest'] is None:
        return 0.0, 0.0, 0.0
    size = (lambda r: r.u8) if utf8 else (lambda r: r.cp)
    call = (lambda r: r.cmd_u8) if utf8 else (lambda r: r.cmd_cp)
    bytes_of = (lambda r: size(r) + call(r)) if charge_calls else size

    host = min(r.req for r in res)
    pure = {q for q in ag['n_scoped']
            if q < n_req and ag['n_results'].get(q, 0) == ag['n_scoped'][q]}
    if drop_floor:
        # A request whose only scoped results were dropped from the scope is no
        # longer a catalogue-only request.
        kept = collections.Counter(r.req for r in res)
        pure = {q for q in pure if kept.get(q, 0) == ag['n_results'].get(q, 0)}

    gone = pure - {host}
    a = (sum(cost_of(ag, i, name) for i in gone)
         - sum(bytes_of(r) / bpt * sum(1 for q in range(host, r.req) if q not in gone)
               for r in res))

    def subset_upper(h):
        by = collections.defaultdict(list)
        for r in res:
            if r.req >= h:
                by[r.req].append(r)
        total = 0.0
        for i in pure - {h}:
            if i < h:
                continue
            carry = sum(bytes_of(r) / bpt * sum(1 for q in range(h, i) if q not in pure)
                        for r in by.get(i, []))
            total += max(0.0, cost_of(ag, i, name) - carry)
        return total

    b = subset_upper(host)
    c = max(subset_upper(h) for h in range(ag['digest'] + 1, n_req))
    return a, b, c


def main():
    corpus, data = [], []
    for path in g.agents():
        corpus.append(f'{hashlib.sha1(open(path, "rb").read()).hexdigest()}  {os.path.basename(path)}')
        got = scan(path)
        if got:
            data.append(got)
    digest = hashlib.sha1('\n'.join(sorted(corpus)).encode()).hexdigest()
    if digest != g.EXPECTED_MANIFEST:
        raise SystemExit(f'transcript manifest mismatch\n  expected {g.EXPECTED_MANIFEST}\n'
                         f'  got      {digest}\n\nRe-pin EXPECTED_MANIFEST in gate0.py and '
                         f're-run every number if this is intended.')
    print(f'{len(data)} round-22 review agents; transcript manifest sha1 {digest} (matches)')

    name = b0.PRIMARY
    windows = collections.Counter()
    for ag in data:
        n_req = len(ag['usages'])
        res = [r for r in ag['results'] if r.req < n_req]
        if res and ag['digest'] is not None:
            windows[min(r.req for r in res) - ag['digest']] += 1
    print('  first catalogue arrival minus digest arrival: '
          + ', '.join(f'{k}x{v}' for k, v in sorted(windows.items()))
          + '\n  (a gap of 1 means the causal window has one position and the host is forced)')

    # Check 3: the host never sits after a result it is supposed to carry, and
    # every result therefore has a host it can move to. With one legal position
    # this is an assertion about the corpus, not about the formula.
    for ag in data:
        n_req = len(ag['usages'])
        res = [r for r in ag['results'] if r.req < n_req]
        if not res:
            continue
        host = min(r.req for r in res)
        assert ag['digest'] is not None and host == ag['digest'] + 1, (host, ag['digest'])
        assert all(host <= r.req for r in res)
    print(f'check: every one of the {sum(len([r for r in a["results"] if r.req < len(a["usages"])]) for a in data)} '
          f'ingested catalogue results has the host at or before it')

    # Check 2: the host is not taken on the strength of a closed-form rule. Every
    # position the batch could legally occupy is enumerated, and none of them
    # saves more than the figure reported for that agent.
    for ag in data:
        for bpt in g.BPT:
            a, _b, c = figures(ag, bpt, name)
            assert a <= c + 1e-9, (a, c)
    print('check: no host position beats the reported figure - (c) enumerates them all')

    # Check 1: the difference formula against a from-scratch costing of the
    # transformed round, for (a), every agent and every calibration.
    for ag in data:
        for bpt in g.BPT:
            a, _b, _c = figures(ag, bpt, name)
            if abs(a - rebuilt(ag, bpt, name)) > 1e-6:
                raise SystemExit(f'self-check failed: (a) is {a:.6f}, the round rebuilt '
                                 f'from scratch says {rebuilt(ag, bpt, name):.6f} at {bpt}')
    print('check: (a) equals the batched round costed from scratch, for every agent '
          'and calibration')

    # Check 4: with the causal floor removed and every result moved to B0's own
    # host, this must reproduce gate_b0.py's registered arrangement exactly.
    for bpt in g.BPT:
        mine = base = 0.0
        for ag, path in zip(data, g.agents()):
            got = g.read(path)
            usages, hits, _f, nr, ns = got
            trip, pen = b0.saving(usages, hits, nr, ns, ag['resp'], name, bpt, colocate=False)
            base += trip - pen
            mine += figures(ag, bpt, name)[0]
        if abs(mine - base) > 1e-6:
            raise SystemExit(f'self-check failed at {bpt} B/tok: Gate B1 (a) is {mine:.3f}, '
                             f'gate_b0.py as-registered is {base:.3f}. The causal window is '
                             f'one position wide, so the two must be the same number.')
    print('self-check: (a) reproduces gate_b0.py\'s registered arrangement to the token, '
          'as a one-position window requires')

    variants = (('as measured', dict()),
                ('+ UTF-8 bytes', dict(utf8=True)),
                ('+ floor extractions out', dict(utf8=True, drop_floor=True)),
                ('+ moved calls charged', dict(utf8=True, drop_floor=True, charge_calls=True)))
    print('\nGate B1 - the batch may arrive no earlier than the request after the digest')
    print('  (a) as registered   the whole batch at the forced host')
    print('  (b) move-subset     free to batch only what is worth batching')
    print('  (c) + deferred      (b) over every host position at or after the floor')
    print(f'  {"correction":28s}{"B/tok":>7s}{"(a)":>9s}{"(b)":>9s}{"(c)":>9s}')
    worst, fixed_form = {}, []
    for label, kw in variants:
        for bpt in g.BPT:
            R = A = B = C = 0.0
            for ag in data:
                R += g.raw_of(ag['usages'])
                a, b, c = figures(ag, bpt, name, **kw)
                A += a
                B += b
                C += c
            print(f'  {label if bpt == g.BPT[0] else "":28s}{bpt:7.1f}'
                  f'{100 * A / R:8.2f}%{100 * B / R:8.2f}%{100 * C / R:8.2f}%')
            worst.setdefault(label, []).append(100 * C / R)
            if label == 'as measured':
                fixed_form.append(100 * A / R)
        print()

    fixed = max(fixed_form)
    top = max(worst['as measured'])
    corrected = max(worst['+ moved calls charged'])
    refuted = fixed < BAR
    print(f'VERDICT: Gate B1 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print(f'  the fixed intervention (a), worst calibration:         {fixed:.2f}%')
    print(f'  largest of the two reported variants, as measured:     {top:.2f}%')
    print(f'  the same with every known approximation corrected:     {corrected:.2f}%')
    if (top < BAR) != refuted:
        print(f'\n  THE FAMILY CLAIM DOES NOT FOLLOW. The intervention this protocol fixed is\n'
              f'  refuted, but a form free to batch a subset and defer the host reaches\n'
              f'  {top:.2f}% as measured - over the bar by {top - BAR:.2f} points. Every known\n'
              f'  approximation in that count runs the same way and is worth {top - corrected:.2f}\n'
              f'  points together, which would put it at {corrected:.2f}%; they are estimates\n'
              f'  applied in the direction that favours refutation, so the verdict above does\n'
              f'  not lean on them. That form is a different candidate and needs its own\n'
              f'  protocol before anything is concluded about it.')
    print(f"""
The verdict is read from the UNCORRECTED (a): the intervention this protocol fixed
is one turn issuing every fetch, and its pre-registered figure is what Gate B1
decides on. Every correction in the table moves the figure DOWN - each was a way of
counting that credited the intervention with something it does not get - so the
uncorrected row is the one a refutation has to clear.

(b) and (c) are reported, not decided on. They are reformulations, which this
protocol voids itself for; they exist here to show what the refutation does NOT
cover, and the fifth amendment records that narrowing.

{"Gate B1 ends the line of work." if refuted else
 "Gate B1 cannot end the line of work. Nothing here says batching reaches the same claims."}""")


if __name__ == '__main__':
    main()
