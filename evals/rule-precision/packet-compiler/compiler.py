#!/usr/bin/env python3
"""The review-packet compiler: diff + catalogue in, packet out. Nothing else in.

Written blind, per the protocol's second amendment: no opened-rule set was
consulted before the first version of this file was scored. Its runtime inputs are
the pinned diff and arm W's catalogue as round 22 pinned it, and the selection
rule is derived from the catalogue's own text - each rule row states what triggers
it, and the tokens it states are what this matches against the change.

  select   a rule fires when a distinctive token from its own row occurs in the
           diff. Tokens are the backticked spans the row uses to say what it looks
           for; generic shell and prose words are dropped, because a rule that
           fires on `the` selects the whole catalogue.
  follow   a fired rule's detail page joins the packet when its row points at one,
           which is the same condition the reviewer's instructions give.
  emit     the compact rows of the fired rules, plus those pages.

The whole-catalogue packet is also available as a baseline: it cannot miss a rule
by construction, and it pays for that in bytes.

Usage:  packet-compiler/compiler.py [--all]   (prints the packet's rule set)
"""
import os
import re
import sys

# Backticked spans are how a row names what it looks for. A token has to be long
# enough and specific enough to mean something in a diff: `id` and `set` occur in
# every change ever written, and a rule that fires on them has not selected.
TOKEN = re.compile(r'`([^`\n]{3,60})`')
CODEY = re.compile(r'^[A-Za-z_][A-Za-z0-9_./*-]*$')
GENERIC = {
    'true', 'false', 'null', 'none', 'nil', 'error', 'err', 'test', 'tests',
    'file', 'files', 'name', 'names', 'type', 'types', 'value', 'values', 'data',
    'code', 'line', 'lines', 'call', 'calls', 'user', 'users', 'time', 'date',
    'list', 'map', 'set', 'get', 'new', 'old', 'add', 'run', 'use', 'and', 'or',
    'not', 'the', 'for', 'with', 'from', 'into', 'this', 'that', 'when', 'then',
    'grep', 'rg', 'awk', 'sed', 'find', 'cat', 'echo', 'git', 'diff', 'main',
}
# A row that points at its own detail page says so in one of these ways.
FOLLOW = re.compile(r'Extended obligations|full normative procedure|rule-details')
ROW = re.compile(r'^\|\s*((?:R|RS|RT)\d+)\s*\|(.*)$')


def catalogue(root):
    """(rows by ID, detail page text by ID) from a pinned catalogue directory."""
    rows = {}
    for line in open(os.path.join(root, 'common-rules.md'), encoding='utf-8'):
        m = ROW.match(line)
        if m and not line.startswith('| ID '):
            rows[m.group(1)] = line
    pages = {}
    details = os.path.join(root, 'rule-details')
    if os.path.isdir(details):
        for name in os.listdir(details):
            if name.endswith('.md'):
                pages[name[:-3]] = open(os.path.join(details, name), encoding='utf-8').read()
    return rows, pages


def tokens_of(row):
    """The distinctive things a row says it looks for."""
    out = set()
    for span in TOKEN.findall(row):
        for piece in re.split(r'[\s,;|]+', span):
            piece = piece.strip('.,:;()[]{}\'"')
            if len(piece) >= 4 and CODEY.match(piece) and piece.lower() not in GENERIC:
                out.add(piece)
    return out


def compile_packet(diff, root, everything=False):
    """(selected rule IDs, page IDs) for one change.

    `everything` is the baseline that selects the whole catalogue: it cannot miss
    a rule, and Gate C1 prices what that costs.
    """
    rows, pages = catalogue(root)
    if everything:
        return set(rows), set(pages)
    fired = set()
    for rid, row in rows.items():
        if any(tok in diff for tok in tokens_of(row)):
            fired.add(rid)
    followed = {rid for rid in fired if rid in pages and FOLLOW.search(rows[rid])}
    return fired, followed


def packet_bytes(selected, followed, root):
    rows, pages = catalogue(root)
    n = sum(len(rows[r].encode('utf-8')) for r in selected)
    return n + sum(len(pages[r].encode('utf-8')) for r in followed)


def main():
    root = os.environ.get('CAT_W', '')
    diff = open(os.environ['F11_DIFF'], encoding='utf-8').read()
    selected, followed = compile_packet(diff, root, everything='--all' in sys.argv)
    print(f'{len(selected)} rules, {len(followed)} detail pages, '
          f'{packet_bytes(selected, followed, root) / 1000:.1f} kB')
    print(' '.join(sorted(selected)))


if __name__ == '__main__':
    main()
