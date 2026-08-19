#!/usr/bin/env python3
"""Gate C0 of `protocol.md`: what does a compiled review packet save?

Two candidates died on this fixture before this one. Trimming WHAT the reviewer
reads reached 9.92-10.89%; moving WHEN its own fetches arrive reached
19.32-19.52%, and the reason it stopped there is measured: the window between the
digest arriving and the first catalogue result arriving is one request wide in all
150 agents, so anything that leaves the model in the selection loop has to cross a
gap it cannot cross.

This gate prices taking the selection out of the loop. The digest is not read, the
rows and pages the agent turned out to need arrive once as a packet, and the round
is rebuilt around that:

  removed   the digest's bytes, everywhere they were re-sent
  trip      a request whose every ingested result is now in the packet is not
            made - context always, output only if that response did nothing but
            fetch what the packet replaces
  carry     each packet member is re-sent by every surviving request between the
            packet and where it used to arrive, its command payload with it

That last charge is a cost the intervention does not actually pay - the model
issues no `rg`, no `cat`, no listing, because one compiler command replaces them -
so what this gate computes is a conservative WITNESS, not a ceiling. A witness
above the bar shows the perfect form clears it. A witness below the bar would show
nothing, and Gate C0 could not have refuted on one; the protocol's first amendment
records that.

The packet is an ORACLE: it is exactly what that agent turned out to need, which
no compiler can know in advance. Gate C1 writes the compiler and prices what it
actually produces; this gate only asks whether the perfect version is worth
looking at.

Bytes are UTF-8 here. The gates before this one counted code points, which
understates the carry - the loose direction there, and not obviously loose here,
because removing the digest is a saving denominated in the same bytes.

Usage:  packet-compiler/gate_c0.py
"""
import collections
import hashlib
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_g = importlib.util.spec_from_file_location(
    'gate0', os.path.join(HERE, os.pardir, 'routing-trim', 'gate0.py'))
g = importlib.util.module_from_spec(_g)
_g.loader.exec_module(g)
_b0 = importlib.util.spec_from_file_location(
    'gate_b0', os.path.join(HERE, os.pardir, 'request-batching', 'gate_b0.py'))
b0 = importlib.util.module_from_spec(_b0)
_b0.loader.exec_module(b0)

DIGEST = 'common-rules.digest.md'
BAR = 20.0


def scan(path):
    """Per agent: usages, the digest results, the catalogue results, composition.

    A result is `packet` if the compiler would have supplied it (rows, detail
    pages, directory listings) and `digest` if it is the digest itself. Both stop
    being fetched; only the first is still delivered.
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
    calls = {}
    packet, digest = [], []
    n_results, n_gone = collections.Counter(), collections.Counter()
    seen = 0
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
                    calls[c['id']] = ('packet', t)
            elif c.get('type') == 'tool_result':
                n_results[seen + 1] += 1
                if c.get('tool_use_id') not in calls:
                    continue
                kind, t = calls[c['tool_use_id']]
                if seen + 1 >= n_req:
                    continue
                text = g.result_text(c)
                n_gone[seen + 1] += 1
                (packet if kind == 'packet' else digest).append(
                    (len(text.encode('utf-8')), len(t.encode('utf-8')), seen + 1))
    return dict(usages=[last[r] for r in order], packet=packet, digest=digest,
                n_results=n_results, n_gone=n_gone, resp=b0.responses(path))


def saving(ag, bpt, where=None):
    """(removed digest, trip, carry) in tokens, for one agent - a WITNESS.

    The carry includes each historical fetch's command payload, which the compiled
    form does not issue, so this is one arrangement the intervention can reach
    rather than the best one. See the protocol's first amendment.

    `where` is the request the packet is ingested by; the protocol fixes it at the
    digest's own arrival and the caller may pass any legal position instead.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    if not ag['packet'] or not ag['digest']:
        return 0.0, 0.0, 0.0
    home = min(r for _b, _c, r in ag['digest'])
    host = home if where is None else where
    # A request stops happening when everything it ingested is a fetch the packet
    # replaces - the digest included, since it is not read either.
    gone = {q for q in ag['n_gone']
            if q < n_req and ag['n_results'].get(q, 0) == ag['n_gone'][q]} - {host}
    trip = sum(b0.context_of(usages[q])
               + (usages[q].get('output_tokens', 0)
                  if b0.keeps_its_output(ag['resp'], q, b0.PRIMARY) else 0)
               for q in gone)
    # The digest is not delivered at all, so it is saved wherever it was re-sent.
    removed = sum(nbytes / bpt * sum(1 for q in range(req, n_req) if q not in gone)
                  for nbytes, _cmd, req in ag['digest'])
    # The packet is delivered, earlier, and its members are re-sent in between.
    carry = sum((nbytes + cmd) / bpt * sum(1 for q in range(host, req) if q not in gone)
                for nbytes, cmd, req in ag['packet'])
    return removed, trip, carry


def legal_positions(ag):
    """Every request the packet could be ingested by.

    No later than the request that first ingested a catalogue result - the
    reviewer used it there - and no earlier than the first request that ingests
    anything at all, since a result cannot be delivered to a request that predates
    every tool call.
    """
    if not ag['packet'] or not ag['digest']:
        return []
    first_use = min(r for _b, _c, r in ag['packet'])
    floor = min(ag['n_results']) if ag['n_results'] else first_use
    return [q for q in range(floor, first_use + 1) if q < len(ag['usages'])]


def rebuilt(ag, bpt, where=None):
    """The same total, by costing the compiled round instead of subtracting.

    Adds up every surviving request's context minus the digest it no longer
    carries plus the packet it now does, every surviving response, and every
    relocated response of a request that no longer exists.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    if not ag['packet'] or not ag['digest']:
        return 0.0
    home = min(r for _b, _c, r in ag['digest'])
    host = home if where is None else where
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
        after += sum((nbytes + cmd) / bpt
                     for nbytes, cmd, req in ag['packet'] if host <= q < req)
    return before - after


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

    for ag in data:
        for bpt in g.BPT:
            got = sum(x * s for x, s in zip(saving(ag, bpt), (1, 1, -1)))
            if abs(got - rebuilt(ag, bpt)) > 1e-6:
                raise SystemExit(f'self-check failed: difference form {got:.6f}, round '
                                 f'rebuilt from scratch {rebuilt(ag, bpt):.6f} at {bpt}')
    print('self-check: the difference form and the compiled round costed from scratch '
          'agree for every agent and calibration')

    print('\nWhat the packet replaces')
    sizes = [sum(b for b, _c, _r in ag['packet']) for ag in data]
    dig = [sum(b for b, _c, _r in ag['digest']) for ag in data]
    calls = [len(ag['packet']) for ag in data]
    import statistics as st
    print(f'  packet bytes per agent: mean {st.mean(sizes)/1000:.1f} kB, '
          f'median {st.median(sizes)/1000:.1f} kB, max {max(sizes)/1000:.0f} kB')
    print(f'  digest bytes no longer read: mean {st.mean(dig)/1000:.1f} kB')
    print(f'  fetches folded into it: mean {st.mean(calls):.1f}, max {max(calls)}')
    def removed(ag):
        home = min(r for _b, _c, r in ag['digest']) if ag['digest'] else None
        return {q for q in ag['n_gone']
                if q < len(ag['usages'])
                and ag['n_results'].get(q, 0) == ag['n_gone'][q]} - {home}
    per = [len(removed(ag)) for ag in data]
    hosted = sum(1 for ag in data if ag['digest']
                 and min(r for _b, _c, r in ag['digest']) not in removed(ag)
                 and ag['n_results'].get(min(r for _b, _c, r in ag['digest']), 0)
                 > ag['n_gone'][min(r for _b, _c, r in ag['digest'])])
    print(f'  requests removed per agent: mean {st.mean(per):.1f}, median {st.median(per):.0f}, '
          f'max {max(per)} (of {st.mean([len(a["usages"]) for a in data]):.1f})')
    print(f'  agents where the packet rides in a request that survives anyway: {hosted}')

    print('\nGate C0 - the digest is not read and the packet arrives once')
    print('  WITNESS, not a ceiling: the carry charges every historical fetch command,')
    print('  which the compiled form does not issue. It understates the saving.')
    print(f'  {"":26s}{"B/tok":>7s}{"digest":>9s}{"trip":>8s}{"carry":>8s}{"WITNESS":>10s}'
          f'{"best host":>11s}')
    verdict, best_all = [], []
    for bpt in g.BPT:
        R = D = T = C = 0.0
        best = 0.0
        for ag in data:
            R += g.raw_of(ag['usages'])
            d, t, c = saving(ag, bpt)
            D, T, C = D + d, T + t, C + c
            best += max((sum(x * s for x, s in zip(saving(ag, bpt, p), (1, 1, -1)))
                         for p in legal_positions(ag)), default=0.0)
        total = D + T - C
        print(f'  {"as fixed (packet at the digest)" if bpt == g.BPT[0] else "":26s}'
              f'{bpt:7.1f}{100 * D / R:8.2f}%{100 * T / R:7.2f}%{100 * C / R:7.2f}%'
              f'{100 * total / R:9.2f}%{100 * best / R:10.2f}%')
        verdict.append(100 * total / R)
        best_all.append(100 * best / R)

    top = max(max(verdict), max(best_all))
    refuted = top < BAR
    print(f'\nVERDICT: Gate C0 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print(f'  witness as fixed, worst calibration:          {min(verdict):.2f}%')
    print(f'  best legal packet position, best calibration: {max(best_all):.2f}%')
    print(f"""
A witness at or above {BAR:.0f}% shows the perfect form clears the bar. One below it would
have shown nothing - the figure carries a cost the intervention does not pay - so
Gate C0 could only ever pass on this arithmetic, never refute. The position the
protocol fixed is still not assumed to be the best one: every legal position is
enumerated and the larger is reported.

The packet is an oracle - exactly what that agent turned out to need, which no
compiler knows in advance. Gate C1 writes the compiler, feeds it only the pinned
diff and catalogue, and prices what it actually produces; a packet that misses a
rule the review used is a refutation there, and pages nobody read are charged.

{"Gate C0 ends the line of work." if refuted else
 "Gate C0 cannot end the line of work; it is not evidence that a compiler works."}""")


if __name__ == '__main__':
    main()
