#!/usr/bin/env python3
"""Gate 1 of `protocol.md`: counterfactual replay under four oracle rules.

Gate 0 removed 100% of the scope and could not refute the candidate. Gate 1 asks
the next cheapest question: how much survives when the gate has to KEEP the rules
the agent actually used? Four retention rules are pre-registered, from strictest
to most generous:

    G1  IDs cited in one of this agent's own findings
    G2  G1, plus IDs whose detail page this agent opened
    G3  G2 unioned across the three reviewers of the same review
    G4  G3 unioned across both arms at the same review index

All four decide from what the agent did AFTER reading the row, which a real
evidence gate cannot see. They bound a perfect gate from above; the intervention
can only do worse. **Gate 1 can refute or fail to refute - never confirm.**

Refutation needs an UPPER bound below the bar, so every unattributable quantity
is resolved in the direction that makes the saving larger. Results that split are
split exactly (a row line names its own rule, a `for` loop writes a per-page
separator); results that do not split are carried as a lower/upper band, and only
the upper end can refute.

The arithmetic is `gate0.py`'s, and this script imports it rather than restating
it: a second copy of the classifier is a second thing to get wrong. With
`retained` empty for every agent, Gate 1 reduces to Gate 0's generous scope, and
`self_check()` asserts exactly that against `gate0.read()` before any Gate 1
number is printed.

Findings come from `../design-audit/_data.py`, whose `verify_inputs()` pins them
by hash; deriving them again here would let two audits disagree about the same
sheet.

Usage:  routing-trim/gate1.py
"""
import collections
import hashlib
import importlib.util
import json
import os
import re
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g = _load('gate0', os.path.join(HERE, 'gate0.py'))
_data = _load('_data', os.path.join(HERE, os.pardir, 'design-audit', '_data.py'))

AGENT_NAME = re.compile(r'^R22 review (W23|W)-(\d+)-([abc])$')
# `307:| R1 | Shared utility reimplementation | ...` - the ID a row line is ABOUT
# is the one in the anchored column, not any of the IDs its prose cross-refers
# to. 833 of the 3070 returned lines name more than one rule, so reading the IDs
# out of the line as a set attributes those lines to the wrong rules.
ROW_LINE = re.compile(r'^\s*\d+[:-]\|\s*((?:R|RS|RT)\d+)\s*\|')
ECHO_ARG = re.compile(r'\becho\s+(?:-\w+\s+)*("[^"]*"|\'[^\']*\'|[^\s;&|]+)')
ID_IN_SEP = re.compile(r'((?:R|RS|RT)\d+)(?:\.md)?')
SHELL_VAR = re.compile(r'\$\{(\w+)\}|\$(\w+)')
BAR = 20.0

# Round 22 is a full factorial: two arms, 25 reviews, three reviewers each.
ARMS, REVIEWS, PARTS = ('W', 'W23'), 25, ('a', 'b', 'c')

# The agent-file set AND the review each file is. Gate 0 pins the bytes, which is
# all it needs - its scopes never ask which review a transcript belongs to. Gate 1
# does: G1 reads that agent's findings out of the sheet, G3 unions its two
# co-reviewers and G4 the other arm, so exchanging the descriptions of two
# transcripts leaves the bytes identical and moves every retention set. This
# digest covers `sha1  basename  key`, so that exchange breaks it.
EXPECTED_GATE1_MANIFEST = 'c9c89ad7728d3cc062fe1f5e1f5bdcb7d6dc7cee'


class Result:
    """One tool result inside the intervention's scope.

    `ids` is a SET: a single call fetches several pages (57 do) and a row result
    carries every ID in its `rg` alternation. `parts` is the exact byte split
    when the result carries its own boundaries, and None when it does not - the
    band case, where the lower end keeps the result whole and the upper end
    removes all of it.
    """

    __slots__ = ('nbytes', 'req', 'kind', 'ids', 'parts')

    def __init__(self, nbytes, req, kind, ids, parts):
        self.nbytes, self.req, self.kind, self.ids, self.parts = nbytes, req, kind, ids, parts


def row_parts(text):
    """Row results split exactly: one line per matched rule, each naming its own."""
    return [(m.group(1) if (m := ROW_LINE.match(line)) else None, len(line))
            for line in text.splitlines(keepends=True)]


def separators(cmd):
    """Regexes for the per-page markers a command writes into its own output.

    Two forms carry a marker and both are in the corpus:

        for f in R3 R49; do echo "##### $f"; cat $f.md; done   -> `##### R3`
        ls && echo "---R3---" && cat R3.md && echo "---RS3---" -> `---R3---`

    Built from the COMMAND, not guessed from the output: a page body opens with
    `# R3 - ...` and cross-refers to other rules, so any line-shaped heuristic
    over the result text splits pages at their own prose.
    """
    pats = []
    for raw in ECHO_ARG.findall(cmd):
        s = raw[1:-1] if raw[:1] in ('"', "'") else raw
        var = SHELL_VAR.search(s)
        if var:
            head, tail = s[:var.start()], s[var.end():]
            tail = re.sub(r'^\.md\b', '', tail)
            pats.append(re.compile(re.escape(head.strip()) + r'\s*((?:R|RS|RT)\d+)(?:\.md)?\s*'
                                   + re.escape(tail.strip())))
        elif (m := ID_IN_SEP.search(s)):
            pats.append(re.compile(re.escape(s[:m.start()]) + r'((?:R|RS|RT)\d+)(?:\.md)?'
                                   + re.escape(s[m.end():])))
    return pats


def page_parts(text, cmd, ids):
    """Byte split of a detail result, or None when it cannot be split.

    A single-page result attributes wholly to its page. A multi-page result
    splits only where the command wrote a marker per page and every page it
    claims to carry actually appears; `cat R3.md R40.md` writes nothing and is a
    band. Bytes before the first marker (an `ls` listing, say) stay
    unattributed and land in the band term.
    """
    if len(ids) == 1:
        return [(next(iter(ids)), len(text))]
    pats = separators(cmd)
    if not pats:
        return None
    segs = []
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        hit = next((m.group(1) for m in (p.fullmatch(stripped) for p in pats) if m), None)
        if hit:
            segs.append([hit, len(line)])
        elif segs:
            segs[-1][1] += len(line)
        else:
            segs.append([None, len(line)])
    if not ids <= {i for i, _ in segs if i}:
        return None
    return [(i, b) for i, b in segs]


def scan(path):
    """Everything Gate 1 needs from one agent transcript.

    Mirrors `gate0.read()` - same request ordering, same attribution of a result
    to the request AFTER the one that asked for it - and adds the ID set, the
    byte split, and the pages this agent opened.
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
    calls, results = {}, []
    n_results = collections.Counter()
    opened, candidates = set(), set()
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
                if g.is_rows(t):
                    ids = set(g.RULE_ID.findall(t))
                    candidates |= ids
                    calls[c['id']] = ('rows', t, ids)
                elif g.is_detail_page(t):
                    ids = g.page_ids(t)
                    opened |= ids
                    calls[c['id']] = ('page', t, ids)
                elif g.is_detail(t):
                    # Touches the directory without naming a page: no rule can
                    # retain or drop it on its merits.
                    calls[c['id']] = ('dir', t, set())
            elif c.get('type') == 'tool_result':
                n_results[seen + 1] += 1
                if c.get('tool_use_id') not in calls:
                    continue
                kind, t, ids = calls[c['tool_use_id']]
                text = g.result_text(c)
                parts = (row_parts(text) if kind == 'rows'
                         else page_parts(text, t, ids) if kind == 'page' else None)
                results.append(Result(len(text), seen + 1, kind, ids, parts))
    return dict(usages=[last[r] for r in order], results=results, n_results=n_results,
                opened=opened, candidates=candidates)


def removal(r, retained):
    """(lower bytes removed, upper bytes removed, is the whole result gone).

    The third value is what decides a round trip, and it is the same at both
    ends: a result is wholly gone only when every ID it carries is dropped, which
    no band can change. A partially retained result keeps its request whichever
    end is read - the retained IDs still have to be fetched there.
    """
    if not r.ids:
        # A directory call carries no ID, so it goes only when nothing is kept.
        return (r.nbytes, r.nbytes, True) if not retained else (0, 0, False)
    drop = r.ids - retained
    if not drop:
        return 0, 0, False
    if drop == r.ids:
        return r.nbytes, r.nbytes, True
    if r.parts is None:
        return 0, r.nbytes, False
    lower = sum(b for i, b in r.parts if i is not None and i not in retained)
    unattributed = sum(b for i, b in r.parts if i is None)
    return lower, lower + unattributed, False


def consolidated_rows(results, retained):
    """The one row result a consolidating gate still fetches, if any.

    The protocol's consolidated form fetches "the retained IDs ... in one `rg`",
    so an agent that issued two row calls issues one - the later fetches go
    whole, whatever they carried. Six results in this corpus are affected: five
    agents fetch rows more than once.

    The survivor is the first fetch that carries a retained ID. Retained IDs that
    appear only in a later fetch ride it for free, which credits a saving the
    consolidated `rg` would have had to pay a few bytes for; that is the loose
    direction, and Gate 1 refutes on the upper end.
    """
    return next((r for r in results if r.kind == 'rows' and r.ids & retained), None)


def evaluate(ag, retained, bpt, gate0_mode=False, consolidate=True):
    """(trip, {end: content}, {end: api-eq}) in tokens, for one agent.

    Content is credited exactly as in Gate 0: the removed bytes at the request
    that ingested them plus every later request that would still have re-sent
    them, capped by what that agent actually transported. Where the ingesting
    request itself disappears, its first ingestion is already inside the trip
    term and is not added twice.

    `consolidate` selects between the protocol's two variants. With it, the
    retained rows arrive in one `rg` and the trip term is available; without it,
    the number of calls is whatever the reviewer happened to make, the trip term
    is not identifiable, and the caller reports the content term alone.

    `gate0_mode` drops the first ingestion even where the request survives, which
    is what `gate0.py` computes. It exists for `self_check()`: Gate 0's ceiling
    is that much smaller than the protocol's stated crediting rule, and a bound
    understated in a knowable direction is the direction that refutes too easily.
    """
    usages, n_req = ag['usages'], len(ag['usages'])
    carried = sum(u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
                  for u in usages)
    keeper = consolidated_rows(ag['results'], retained) if consolidate else None
    fully = collections.Counter()
    removed = {'lower': [], 'upper': []}
    for r in ag['results']:
        if consolidate and r.kind == 'rows' and r is not keeper:
            lo, hi, whole = r.nbytes, r.nbytes, True
        else:
            lo, hi, whole = removal(r, retained)
        if whole:
            fully[r.req] += 1
        removed['lower'].append((lo, r.req))
        removed['upper'].append((hi, r.req))
    gone = g.removable_requests(ag['n_results'], fully, n_req)
    trip = g.raw_of([usages[i] for i in gone])
    content, api = {}, {}
    for end, items in removed.items():
        c = a = 0.0
        for nbytes, req in items:
            if not nbytes:
                continue
            tok = nbytes / bpt
            later = max(0, n_req - req - 1)
            c += min(tok * (1 + later), tok + carried)
            # The first ingestion is withheld only when something else already
            # counts it: the trip term. Without consolidation there is no trip
            # term to report, so withholding it there would drop the saving
            # outright.
            if gate0_mode or (consolidate and req in gone):
                c -= tok
            a += tok * g.W_READ * later
        content[end] = c
        api[end] = a + g.api_of([usages[i] for i in gone])
    return trip, content, api


def self_check(paths, scanned):
    """With nothing retained, Gate 1 must BE Gate 0's generous scope.

    Two independently written scans of the same transcripts, reduced to the same
    degenerate case: if the byte totals, the eliminated requests or the crediting
    differ by a token, one of them is wrong. Cheaper than trusting that the
    reimplementation of `read()` kept every rule of the original.
    """
    for bpt in g.BPT:
        mine = base = 0.0
        for path, ag in zip(paths, scanned):
            trip, content, _api = evaluate(ag, set(), bpt, gate0_mode=True)
            mine += trip + content['upper']
            usages, hits, _facts, n_results, n_scoped = g.read(path)
            n_req = len(usages)
            carried = sum(u.get('cache_read_input_tokens', 0)
                          + u.get('cache_creation_input_tokens', 0) for u in usages)
            name = 'the candidate, generous'
            c = 0.0
            for nbytes, first in hits[name]:
                tok = nbytes / bpt
                later = max(0, n_req - first - 1)
                c += min(tok * (1 + later), tok + carried) - tok
            goneq = g.removable_requests(n_results, n_scoped[name], n_req)
            base += c + g.raw_of([usages[i] for i in goneq])
        if abs(mine - base) > 1e-6:
            raise SystemExit(f'self-check failed at {bpt} B/tok: Gate 1 with nothing '
                             f'retained is {mine:.3f} tokens, Gate 0 generous is '
                             f'{base:.3f}. One of the two scans is wrong.')
    return True


def cited_ids():
    """Rule IDs each agent cited in its own findings, from the pinned sheet.

    `_data.verify_inputs()` checks the hash of every file it reads, so this is
    the same findings sheet the design audit scored - not a re-extraction that
    could drift from it.
    """
    rd, verdict, _n = _data.ROUNDS['round 22']
    _f2c, by = _data.load(rd, verdict)
    out = collections.defaultdict(set)
    for arm in by:
        for review in by[arm]:
            for part, findings in by[arm][review].items():
                for f in findings:
                    out[(arm, review, part)] |= set(
                        g.RULE_ID.findall(f['title'] + ' ' + f['what_is_wrong']))
    return out


def retention(keys, scanned, cited):
    """The four pre-registered retention rules, as {rule: {agent key: id set}}.

    Each is a superset of the one before it, so the savings fall monotonically
    from G1 to G4. Nothing here looks at the numbers: the rules were fixed in
    `protocol.md` before this script existed.
    """
    by_key = dict(zip(keys, scanned))
    g1 = {k: set(cited.get(k, set())) for k in keys}
    g2 = {k: g1[k] | by_key[k]['opened'] for k in keys}
    review = collections.defaultdict(set)
    both = collections.defaultdict(set)
    for k in keys:
        arm, idx, _part = k
        review[(arm, idx)] |= g2[k]
        both[idx] |= g2[k]
    g3 = {k: review[(k[0], k[1])] for k in keys}
    g4 = {k: both[k[1]] for k in keys}
    return {'G1 cited in own findings': g1, 'G2 + pages it opened': g2,
            'G3 + the other two reviewers': g3, 'G4 + the other arm': g4}


def agent_key(description):
    """(arm, review index, part) for a round-22 review agent, or None."""
    m = AGENT_NAME.match(description)
    return (m.group(1), int(m.group(2)), m.group(3)) if m else None


def manifest_digest(entries):
    """sha1 over `sha1  basename  key` lines, order-independent.

    The key is in the line because it is an input to every Gate 1 number, and an
    input that is not hashed is an input that can change silently.
    """
    return hashlib.sha1('\n'.join(
        sorted(f'{h}  {b}  {a}-{i}-{p}' for h, b, (a, i, p) in entries)).encode()).hexdigest()


def check_keys(keys):
    """The keys are exactly the round: two arms x 25 reviews x three parts.

    Completeness and uniqueness are not implied by the digest - a corpus missing
    an agent hashes to something, and that something can be re-pinned without
    anyone noticing the arm is a reviewer short. G3 and G4 union across a review
    and across arms, so a gap changes what the other agents retain, not only what
    the missing one would have.
    """
    want = {(a, i, p) for a in ARMS for i in range(1, REVIEWS + 1) for p in PARTS}
    seen = collections.Counter(keys)
    bad = ([f'DUPLICATE {k}' for k, n in sorted(seen.items()) if n > 1]
           + [f'MISSING   {k}' for k in sorted(want - set(seen))]
           + [f'UNEXPECTED {k}' for k in sorted(set(seen) - want)])
    if bad:
        raise SystemExit('agent key set is not the round:\n  ' + '\n  '.join(bad)
                         + f'\n\nExpected {len(want)} unique keys, {len(ARMS)} arms x '
                           f'{REVIEWS} reviews x {len(PARTS)} parts.')
    return len(seen)


def main():
    corpus, keys, scanned, paths = [], [], [], []
    for path in g.agents():
        meta = json.load(open(path.replace('.jsonl', '.meta.json')))
        key = agent_key(meta['description'])
        if key is None:
            raise SystemExit(f'{os.path.basename(path)} is not a round-22 review agent: '
                             f'{meta["description"]!r}. gate0.agents() and AGENT_NAME '
                             f'disagree about what belongs in this corpus.')
        corpus.append((hashlib.sha1(open(path, 'rb').read()).hexdigest(),
                       os.path.basename(path), key))
        got = scan(path)
        if not got:
            continue
        paths.append(path)
        keys.append(key)
        scanned.append(got)
    check_keys(keys)
    gate1_digest = manifest_digest(corpus)
    if gate1_digest != EXPECTED_GATE1_MANIFEST:
        raise SystemExit(f'Gate 1 manifest mismatch\n  expected {EXPECTED_GATE1_MANIFEST}\n'
                         f'  got      {gate1_digest}\n\nThe transcripts, or which review '
                         f'each one is, are not what these numbers were computed against. '
                         f'Re-pin EXPECTED_GATE1_MANIFEST and re-run every number if this '
                         f'is intended.')
    # Gate 0's own manifest as well, so a corpus that drifted from the one Gate 0
    # reported on is caught here rather than in the self-check's arithmetic.
    digest = hashlib.sha1('\n'.join(sorted(f'{h}  {b}' for h, b, _k in corpus)).encode()).hexdigest()
    if digest != g.EXPECTED_MANIFEST:
        raise SystemExit(f'transcript manifest mismatch\n  expected {g.EXPECTED_MANIFEST}\n'
                         f'  got      {digest}\n\nThese results were computed against a '
                         f'different agent-file set. Re-pin EXPECTED_MANIFEST in gate0.py '
                         f'and re-run every number if this is intended.')
    npinned = _data.verify_inputs()
    print(f'{len(scanned)} round-22 review agents; transcript manifest sha1 {digest} (matches)')
    print(f'agent-to-review manifest sha1 {gate1_digest} (matches); '
          f'{len(ARMS)} arms x {REVIEWS} reviews x {len(PARTS)} parts, complete and unique')
    print(f'findings from the design audit\'s pinned sheet ({npinned} files hash-checked)')
    self_check(paths, scanned)
    print('self-check: with nothing retained, Gate 1 reproduces Gate 0\'s generous '
          'ceiling exactly')

    print('\nHow the scope splits (the band is what cannot be attributed)')
    kinds = collections.Counter()
    band = collections.Counter()
    for ag in scanned:
        for r in ag['results']:
            kinds[r.kind] += 1
            if r.parts is None and r.ids:
                band[r.kind] += 1
    print(f'  {"":24s}{"results":>9s}{"unsplittable":>14s}')
    for k in ('rows', 'page', 'dir'):
        print(f'  {k:24s}{kinds[k]:9d}{band[k]:14d}')
    print('  (a dir call carries no ID at all, so it is not a band - it goes only when\n'
          '   the agent retains nothing)')

    cited = cited_ids()
    rules = retention(keys, scanned, cited)
    print('\nWhat each rule retains, per agent')
    print(f'  {"":30s}{"mean":>7s}{"median":>8s}{"max":>6s}{"empty":>8s}')
    cand = [len(a['candidates']) for a in scanned]
    print(f'  {"candidates in the rg pattern":30s}{st.mean(cand):7.1f}{st.median(cand):8.1f}'
          f'{max(cand):6d}{"-":>8s}')
    for name, keep in rules.items():
        v = [len(keep[k]) for k in keys]
        empty = sum(1 for x in v if not x)
        print(f'  {name:30s}{st.mean(v):7.1f}{st.median(v):8.1f}{max(v):6d}{empty:8d}')

    print('\nGate 1 - the saving under each oracle rule, as a share of the round')
    print('  trip     = requests whose EVERY ingested result is removed (available only')
    print('             to a gate that also consolidates what it retains)')
    print('  content  = removed bytes, at their own request and in every later re-send')
    print('  LOWER/UPPER bracket the results that cannot be split; only UPPER can refute')
    print(f'  {"rule":30s}{"B/tok":>7s}{"trip":>8s}{"content":>17s}{"WITH consol.":>21s}'
          f'{"content only":>21s}{"api-eq":>9s}')
    verdict, as_gate0 = {}, {}
    for name, keep in rules.items():
        for bpt in g.BPT:
            R = A = T = G0 = 0.0
            C = {'lower': 0.0, 'upper': 0.0}
            U = {'lower': 0.0, 'upper': 0.0}
            AE = {'lower': 0.0, 'upper': 0.0}
            for k, ag in zip(keys, scanned):
                R += g.raw_of(ag['usages'])
                A += g.api_of(ag['usages'])
                trip, content, api = evaluate(ag, keep[k], bpt)
                T += trip
                for end in C:
                    C[end] += content[end]
                    AE[end] += api[end]
                _t, c0, _a = evaluate(ag, keep[k], bpt, gate0_mode=True)
                G0 += trip + c0['upper']
                # The other pre-registered variant: the reviewer makes whatever
                # calls it makes, so no row fetch is merged into another and the
                # trip term is not identifiable at all.
                _t, cu, _a = evaluate(ag, keep[k], bpt, consolidate=False)
                for end in U:
                    U[end] += cu[end]
            lo, hi = (100 * (T + C[e]) / R for e in ('lower', 'upper'))
            colo, cohi = (100 * C[e] / R for e in ('lower', 'upper'))
            ulo, uhi = (100 * U[e] / R for e in ('lower', 'upper'))
            print(f'  {name if bpt == g.BPT[0] else "":30s}{bpt:7.1f}{100 * T / R:7.2f}%'
                  f'{colo:8.2f}-{cohi:6.2f}%{lo:11.2f}-{hi:7.2f}%'
                  f'{ulo:12.2f}-{uhi:7.2f}%{100 * AE["upper"] / A:8.2f}%')
            verdict.setdefault(name, []).append(hi)
            as_gate0.setdefault(name, []).append(100 * G0 / R)
        print()

    # Where G1's saving comes from, since the rule that decides is the one worth
    # taking apart: an agent whose findings cite no rule at all retains nothing,
    # and for it G1 is Gate 0's generous ceiling rather than a replay of a gate.
    name, keep = next(iter(rules.items()))
    R = 0.0
    parts = collections.Counter()
    for k, ag in zip(keys, scanned):
        R += g.raw_of(ag['usages'])
        trip, content, _api = evaluate(ag, keep[k], g.BPT[0])
        parts['no rule cited' if not keep[k] else 'at least one cited'] += trip + content['upper']
    print(f'\n  where {name} comes from, at {g.BPT[0]} B/tok:')
    for label, v in parts.most_common():
        n_ag = sum(1 for k in keys if bool(keep[k]) == (label == 'at least one cited'))
        print(f'    {label:22s}{v / R * 100:6.2f}%  ({n_ag} agents)')

    worst = {n: max(v) for n, v in verdict.items()}
    refuted = all(v < BAR for v in worst.values())
    print(f'\nVERDICT: Gate 1 {"REFUTES" if refuted else "does NOT refute"} the candidate.\n')
    print('  upper end, with consolidation, worst calibration:')
    for n, v in worst.items():
        print(f'    {n:30s}{v:7.2f}%   {"below" if v < BAR else "at or above"} the {BAR:.0f}% bar')
    # Gate 1 credits the removed bytes at the request that ingested them, which is
    # what its own clause says and what gate0.py's ceiling leaves out for every
    # request that survives. The difference is shown rather than argued: if the
    # two crediting rules disagreed about the bar, the verdict would rest on it.
    alt = {n: max(v) for n, v in as_gate0.items()}
    if all(v < BAR for v in alt.values()) == refuted:
        print(f'\n  (on gate0.py\'s narrower crediting - first ingestion dropped even where '
              f'the request\n   survives - the same four read '
              + ', '.join(f'{v:.2f}%' for v in alt.values()) + ', and the verdict is the same)')
    else:
        print('\n  WARNING: the two crediting rules disagree about the bar. gate0.py\'s '
              'narrower form\n  reads ' + ', '.join(f'{v:.2f}%' for v in alt.values())
              + ', which is a different verdict. The wider form is the one\n  Gate 1 '
                'pre-registered, and it is the upper bound; but the gate turns on this.')
    print(f"""
Refutation needs the UPPER end below {BAR:.0f}% for every rule at every calibration.
G1 saves the most and is therefore the rule that decides: a bound that keeps only
what the agent cited is the loosest constraint an oracle can put on the gate.

{"Gate 1 ends the line of work." if refuted else
 "Gate 1 cannot end the line of work; it does not follow that the intervention works."}""")


if __name__ == '__main__':
    main()
