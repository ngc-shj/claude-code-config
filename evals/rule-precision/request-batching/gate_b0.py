#!/usr/bin/env python3
"""Gate B0 of `protocol.md`: what does batching the catalogue fetches save?

The routing trim was refuted on CONTENT - the strictest oracle rule saves
9.92-10.89% of the round against a 20% bar. This asks the other question. Keep
every catalogue byte the reviewer reads today and change only WHEN it arrives:
one turn issues every fetch, so one request ingests every result instead of
several. Nothing is dropped, so nothing about coverage moves.

Two terms, and the second one is a cost:

  trip        a request whose every ingested result is in scope is not made at
              all. A request that also carried the diff survives.
  early carry a result moved to an earlier request is in the context sooner, so
              every surviving request in between now re-sends it. A figure that
              omits this is not a saving.

Where the batch lands decides whether a request survives to hold it. Issuing the
fetches in a turn that was happening anyway - the one that reads the diff - lands
them in a request that survives for its own reasons, and then no catalogue-only
request is left standing. The pre-registered clause put the batch at the agent's
FIRST in-scope arrival and kept that request alive, which is not the maximum and
so was not a ceiling; the protocol carries the amendment. Both are reported.

The classifier is `gate0.py`'s, imported rather than restated: it is pinned by
`tests/gate0-classify.bats` and by the transcript manifest, and a second copy is
a second thing to get wrong. Gate 0's manifest is the only pin needed here -
unlike Gate 1, nothing in this gate asks which review a transcript is.

Usage:  request-batching/gate_b0.py
"""
import collections
import hashlib
import importlib.util
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'gate0', os.path.join(HERE, os.pardir, 'routing-trim', 'gate0.py'))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)

PRIMARY = 'the candidate, generous'
SCOPES = (PRIMARY, '  strict: rows + .md pages', 'the whole catalogue')
BAR = 20.0


def responses(path):
    """request index -> (tool calls it emitted, of which in each scope).

    A request is more than what it ingests. Its RESPONSE may issue work that has
    nothing to do with the catalogue - 143 of this corpus's removable requests
    emit the review `Write` - and that work does not disappear because the fetch
    it happened to sit next to moved. Batching relocates it; the output tokens
    are paid either way.
    """
    import json
    out = {}
    order, seen = [], None
    for line in open(path):
        if not line.strip():
            continue
        d = json.loads(line)
        rid = d.get('requestId')
        m = d.get('message') or {}
        if rid and (m.get('usage') or {}):
            if rid not in out:
                order.append(rid)
                out[rid] = [0, collections.Counter()]
            seen = rid
        if seen is None:
            continue
        for c in m.get('content') or []:
            if isinstance(c, dict) and c.get('type') == 'tool_use':
                t = g.tool_target(c.get('name', ''), c.get('input', {}))
                out[seen][0] += 1
                for sname, pred in g.SCOPES:
                    if pred(t):
                        out[seen][1][sname] += 1
    return {i: tuple(out[rid]) for i, rid in enumerate(order)}


def keeps_its_output(resp, req, name):
    """Would this request's response still have to be produced somewhere?

    True when every tool call it issued is a catalogue fetch that the batch
    absorbs. A response that also wrote the review, read the diff, or ran the
    change has work to relocate, and relocated output costs what it cost.

    A response that issued NO tool call at all - a final answer - is credited as
    vanishing, which it would not; that is the loose direction, and Gate B0
    refutes on the upper end.
    """
    total, in_scope_calls = resp.get(req, (0, collections.Counter()))
    return total == in_scope_calls.get(name, 0)


def in_scope(hits, name, n_req):
    """Scoped results that an actual request ingested, as (bytes, request).

    A tool call made by the final turn lands past the end of the transcript and
    is ingested by nothing, so it costs nothing today and batching cannot save
    or spend anything on it. Dropping those spends no penalty on them either,
    which is the loose direction - and Gate B0 refutes on the upper end.
    """
    return [(nbytes, req) for nbytes, req in hits[name] if req < n_req]


def batch_plan(usages, hits, n_results, n_scoped, name, colocate=True):
    """(host request, requests that disappear) for one agent under one scope.

    Every request whose ingested results are ALL in scope has nothing left to do
    once its fetches move into the batch - but the batch has to be ingested
    somewhere, and which request that is decides whether one of them survives.

    `colocate` is the arrangement the amended protocol prices: the fetches are
    issued in a turn that was happening anyway, so their results land in a
    request that survives for its own reasons - the one that reads the diff -
    and no catalogue-only request is left standing. Moving the batch earlier
    costs early carry, so the LATEST such request at or before the first
    catalogue arrival is the best one; if there is none, the first arrival hosts
    it and survives, which is what the pre-registered clause assumed everywhere.
    """
    res = in_scope(hits, name, len(usages))
    if not res:
        return None, frozenset()
    first = min(req for _nbytes, req in res)
    pure = frozenset(g.removable_requests(n_results, n_scoped[name], len(usages)))
    if colocate:
        # A request can only host the batch if it is a request that ingests tool
        # results at all: results are attributed to the request AFTER the one
        # whose response asked for them, so the first request ingests nothing and
        # cannot be where the batch lands.
        riders = [r for r in range(first + 1) if n_results.get(r, 0) and r not in pure]
        if riders:
            return max(riders), pure
    return first, pure - {first}


def context_of(u):
    """What a request carried IN: everything but what the model wrote back."""
    return (u.get('input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
            + u.get('cache_read_input_tokens', 0))


def saving(usages, hits, n_results, n_scoped, resp, name, bpt, colocate=True):
    """(trip, early-carry penalty) in tokens, for one agent under one scope.

        trip    = SUM over eliminated requests of (context + output IF that
                  response did nothing but fetch the catalogue)
        penalty = SUM over moved results of tok(result)
                  x |surviving requests in [host, arrival)|

    A removed request's context is genuinely never sent. Its OUTPUT is only saved
    when the response had no other work to do; otherwise the work relocates and
    is paid in whatever request ends up doing it. Crediting it as saved is what
    the first version of this gate did, and it was worth 4.45% of the round -
    enough to move the verdict across the bar.
    """
    host, gone = batch_plan(usages, hits, n_results, n_scoped, name, colocate)
    if host is None:
        return 0.0, 0.0
    trip = sum(context_of(usages[i])
               + (usages[i].get('output_tokens', 0) if keeps_its_output(resp, i, name) else 0)
               for i in gone)
    penalty = sum((nbytes / bpt) * sum(1 for r in range(host, req) if r not in gone)
                  for nbytes, req in in_scope(hits, name, len(usages)))
    return trip, penalty


def saving_reconstructed(usages, hits, n_results, n_scoped, resp, name, bpt, colocate=True):
    """The same number, built by costing the transformed round from scratch.

    Adds up what the batched round would cost - every surviving request's context
    plus the moved results now in it, every surviving response, and every
    relocated response of a request that no longer exists - and subtracts that
    from what the round did cost. It shares no term with `saving()`: that one
    subtracts what is removed, this one adds up what remains, and the relocated
    output appears here as a cost rather than there as a withheld credit.
    """
    host, gone = batch_plan(usages, hits, n_results, n_scoped, name, colocate)
    if host is None:
        return 0.0
    res = in_scope(hits, name, len(usages))
    before = sum(context_of(u) + u.get('output_tokens', 0) for u in usages)
    after = 0.0
    for r, u in enumerate(usages):
        if r in gone:
            # The request is gone; the work its response did is not, unless that
            # work was the fetch itself.
            if not keeps_its_output(resp, r, name):
                after += u.get('output_tokens', 0)
            continue
        after += context_of(u) + u.get('output_tokens', 0)
        after += sum(nbytes / bpt for nbytes, req in res if host <= r < req)
    return before - after


def main():
    corpus, data = [], []
    for path in g.agents():
        corpus.append(f'{hashlib.sha1(open(path, "rb").read()).hexdigest()}  {os.path.basename(path)}')
        got = g.read(path)
        if got:
            data.append(got + (responses(path),))
    digest = hashlib.sha1('\n'.join(sorted(corpus)).encode()).hexdigest()
    if digest != g.EXPECTED_MANIFEST:
        raise SystemExit(f'transcript manifest mismatch\n  expected {g.EXPECTED_MANIFEST}\n'
                         f'  got      {digest}\n\nThese results were computed against a '
                         f'different agent-file set. Re-pin EXPECTED_MANIFEST in gate0.py '
                         f'and re-run every number if this is intended.')
    print(f'{len(data)} round-22 review agents; transcript manifest sha1 {digest} (matches)')

    for name in SCOPES:
        for usages, hits, _f, n_results, n_scoped, resp in data:
            for bpt in g.BPT:
                for colo in (True, False):
                    trip, pen = saving(usages, hits, n_results, n_scoped, resp, name, bpt, colo)
                    rebuilt = saving_reconstructed(usages, hits, n_results, n_scoped, resp,
                                                   name, bpt, colo)
                    if abs((trip - pen) - rebuilt) > 1e-6:
                        raise SystemExit(f'self-check failed: closed form {trip - pen:.6f} vs '
                                         f'definition {rebuilt:.6f} ({name}, {bpt} B/tok, '
                                         f'colocate={colo})')
    print('self-check: the closed form and the rebuilt-from-definition total agree '
          'for every agent, scope and calibration')

    print('\nWhat there is to batch (primary scope)')
    spread, already, hosts = collections.Counter(), 0, []
    relocated = kept = 0
    for usages, hits, _f, n_results, n_scoped, resp in data:
        n_req = len(usages)
        reqs = {req for _b, req in in_scope(hits, PRIMARY, n_req)}
        spread[len(reqs)] += 1
        if len(reqs) <= 1:
            already += 1
        host, gone = batch_plan(usages, hits, n_results, n_scoped, PRIMARY)
        hosts.append((host, len(gone), n_req))
        for i in gone:
            if keeps_its_output(resp, i, PRIMARY):
                kept += 1
            else:
                relocated += 1
    print('  requests ingesting a catalogue result, per agent: '
          + ', '.join(f'{k}x{v}' for k, v in sorted(spread.items())))
    print(f'  agents with nothing to batch (all of it already lands in one request): {already}')
    print(f'  requests removed per agent: mean {st.mean(n for _h, n, _q in hosts):.1f}, '
          f'median {st.median(n for _h, n, _q in hosts):.0f}, '
          f'max {max(n for _h, n, _q in hosts)}')
    print(f'  batch lands at request index: mean {st.mean(h for h, _n, _q in hosts):.1f} '
          f'of {st.mean(q for _h, _n, q in hosts):.1f} requests')
    # Batching is not free for every agent: where the fetches are already close
    # together and one of them is late, the early carry outweighs what vanishes.
    print(f'  removed requests whose response also did work that is NOT a catalogue\n'
          f'   fetch, so its output relocates rather than vanishes: {relocated} of '
          f'{relocated + kept}')
    per_agent = [sum(x * s for x, s in zip(saving(u, h, nr, ns, rp, PRIMARY, g.BPT[0]), (1, -1)))
                 for u, h, _f, nr, ns, rp in data]
    worse = [v for v in per_agent if v < 0]
    print(f'  agents batching makes WORSE at {g.BPT[0]} B/tok: {len(worse)} '
          f'(worst {min(per_agent, default=0):.0f} tokens; best {max(per_agent, default=0):.0f})')

    print('\nGate B0 - one request ingests every catalogue result, nothing removed')
    print('  SAVING is the amended arrangement: the batch rides in a request that')
    print('  survives anyway. "as registered" kept a catalogue-only request alive to')
    print('  host it, which is not the maximum and therefore was not a ceiling.')
    print(f'  {"scope":26s}{"B/tok":>7s}{"trip":>8s}{"early carry":>13s}{"SAVING":>10s}'
          f'{"as registered":>14s}{"api-eq":>9s}')
    verdict = {}
    for name in SCOPES:
        for bpt in g.BPT:
            R = A = T = P = PA = 0.0
            for usages, hits, _f, n_results, n_scoped, resp in data:
                R += g.raw_of(usages)
                A += g.api_of(usages)
                trip, pen = saving(usages, hits, n_results, n_scoped, resp, name, bpt)
                T += trip
                P += pen
                _h, gone = batch_plan(usages, hits, n_results, n_scoped, name)
                PA += sum(g.api_of([usages[i]])
                          - (0 if keeps_its_output(resp, i, name)
                             else g.W_OUT * usages[i].get('output_tokens', 0))
                          for i in gone) - pen * g.W_READ
            pre = sum(x - y for x, y in (saving(u, h, nr, ns, rp, name, bpt, False)
                                        for u, h, _f, nr, ns, rp in data))
            print(f'  {name if bpt == g.BPT[0] else "":26s}{bpt:7.1f}{100 * T / R:7.2f}%'
                  f'{100 * P / R:12.2f}%{100 * (T - P) / R:9.2f}%{100 * pre / R:11.2f}%'
                  f'{100 * PA / A:8.2f}%')
            verdict.setdefault(name, []).append(100 * (T - P) / R)
        print()

    worst = min(verdict[PRIMARY])
    best = max(verdict[PRIMARY])
    refuted = best < BAR
    print(f'VERDICT: Gate B0 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print(f'  primary scope, rows + details + directory traffic: {worst:.2f}-{best:.2f}%')
    for name in SCOPES[1:]:
        print(f'  {name.strip():40s}{min(verdict[name]):.2f}-{max(verdict[name]):.2f}%')
    split = [n for n in SCOPES if (max(verdict[n]) < BAR) != refuted]
    if split:
        print('\n  THE VERDICT RESTS ON THE SCOPE. ' + ', '.join(n.strip() for n in split)
              + f'\n  {"falls" if refuted else "would fall"} on the other side of the bar. '
                'The primary scope is the one\n  protocol.md registered, and it is the one '
                'the verdict is read from - but\n  nothing here is insensitive to that choice.')
    print(f"""
Refutation needs the upper end below {BAR:.0f}% at every calibration.

Nothing here is a measurement of an implementable gate. The ceiling assumes ONE
turn issues every fetch, which assumes the reviewer could name all of them before
reading a row - and a detail page is mandatory because a row it has not read yet
says so. Gate B1 asks whether that set is predictable in advance, and prices the
two-round form if it is not.

{"Gate B0 ends the line of work." if refuted else
 "Gate B0 cannot end the line of work; it is not evidence that batching works."}""")


if __name__ == '__main__':
    main()
