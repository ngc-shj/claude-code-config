#!/usr/bin/env python3
"""Compose what a clustering agent receives: pinned brief + cluster envelope.

Same shape as `compose-prompt.py`, for the other fan-out. The rendered clustering
brief is the instrument and is not edited; the envelope carries the three things
that vary per agent — which packet it is given, which prefix it may mint, where
it writes — and the delivery rules that index 5 taught the round to enforce in
transport rather than in the brief.

`--register` derives the eight assignments once and commits them to
`cluster-outputs.tsv`, refusing to overwrite an existing registry. Everything
after that reads the registry, so the packet a given agent gets, and the prefix
it is allowed to mint, are facts on disk rather than arguments on a command line.

Prefixes are derived from the changed file and then CHECKED against the frozen
94-claim inventory: a prefix that collides with an existing cluster id would let
a new claim be mistaken for a recorded one, which is the failure the whole
append-only rule exists to prevent.

Usage:
  round-24/compose-cluster-prompt.py --root <dir> --register
  round-24/compose-cluster-prompt.py --root <dir> --target <changed/file.py>
  round-24/compose-cluster-prompt.py --root <dir> --check
  round-24/compose-cluster-prompt.py --root <dir> --target <f> --verify-sent <id>
"""
import argparse
import csv
import glob
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RP = os.path.dirname(HERE)
ENVELOPE = os.path.join(HERE, 'cluster-envelope.md')
REGISTRY = os.path.join(HERE, 'cluster-outputs.tsv')
INVENTORY = os.path.join(HERE, 'cluster-inventory.tsv')
FIXTURE = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                       'rule-ablation', 'fixtures', 'F10-webhooks.diff')
SEP = '\n---\n\n'
# Doubled braces, not angle brackets: the rendered clustering brief names
# `<PREFIX>-01` in its own prose, so an angle-bracket slot could not be told
# apart from the instrument's text.
SLOTS = ('{{GROUP_FILE}}', '{{PREFIX}}', '{{OUTPUT_PATH}}')
N_TARGETS = 8
PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'


def die(msg):
    sys.exit(f'compose-cluster-prompt: {msg}')


def sha1(text):
    b = text.encode()
    return hashlib.sha1(b'blob %d\0' % len(b) + b).hexdigest()


def changed_files():
    import importlib.util
    s = importlib.util.spec_from_file_location(
        'sc', os.path.join(RP, 'split_clusters.py'))
    sc = importlib.util.module_from_spec(s)
    s.loader.exec_module(sc)
    files = sc.changed_files(open(FIXTURE).read())
    if len(files) != N_TARGETS:
        die(f'the fixture names {len(files)} changed files, pre-registered {N_TARGETS}')
    return files, sc.slug


def prefixes(files):
    """R24 + letters of the basename, disambiguated by directory when they clash.

    `docs/webhooks.md` and `migrations/0042_webhook_delivery.sql` both reduce to
    WEB on the basename alone, so a basename-only rule is not injective over this
    fixture. The directory is what distinguishes them, and it is deterministic:
    same fixture, same prefixes, every run. Every candidate is then checked
    against the frozen 94-claim inventory, because a prefix that shadows an
    existing cluster id would let a new claim pass as a recorded one — the exact
    failure the append-only rule exists to prevent.
    """
    letters = lambda s: re.sub(r'[^A-Za-z]', '', s).upper()
    existing = [r['cluster_id'] for r in
                csv.DictReader(open(INVENTORY, newline=''), delimiter='\t')]
    out = {}
    for path in files:
        base = letters(os.path.basename(path).split('.')[0])[:3]
        parent = letters(os.path.dirname(path).split('/')[-1])[:3]
        for cand in ('R24' + base, 'R24' + parent + base):
            if cand in out.values():
                continue
            clash = next((c for c in existing if c.startswith(cand)), None)
            if clash:
                die(f'prefix {cand} shadows existing cluster id {clash}')
            out[path] = cand
            break
        else:
            die(f'{path}: no distinct prefix from its basename or directory')
    if len(set(out.values())) != len(files):
        die('prefixes are not distinct')
    return out


def register(root):
    if os.path.exists(REGISTRY):
        die(f'{os.path.relpath(REGISTRY, HERE)} exists; the clustering assignment '
            f'is not rewritten in passing')
    files, slug = changed_files()
    pref = prefixes(files)
    rows = []
    for path in files:
        rows.append((path, os.path.join(root, 'packets', f'{slug(path)}.tsv'),
                     pref[path],
                     os.path.join(root, 'clusters', f'{slug(path)}.tsv')))
    for _, packet, _, out in rows:
        if not os.path.exists(packet):
            die(f'{packet} does not exist — run split_clusters.py first')
        if os.path.exists(out):
            die(f'{out} already exists, so this is not a reservation')
    with open(REGISTRY, 'w') as f:
        f.write('target\tpacket\tprefix\toutput\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    print(f'wrote {os.path.relpath(REGISTRY, os.path.dirname(HERE))} — '
          f'{len(rows)} assignments, none of their outputs existing')


def registry():
    if not os.path.exists(REGISTRY):
        die('cluster-outputs.tsv is missing — run --register first')
    rows = list(csv.DictReader(open(REGISTRY, newline=''), delimiter='\t'))
    if len(rows) != N_TARGETS:
        die(f'{len(rows)} assignments, expected {N_TARGETS}')
    for key in ('target', 'packet', 'prefix', 'output'):
        if len({r[key] for r in rows}) != N_TARGETS:
            die(f'{key} is not distinct across assignments')
    return rows


def compose(root, target):
    brief_path = os.path.join(root, 'briefs', 'brief-cluster.md')
    if not os.path.exists(brief_path):
        die(f'{brief_path} is missing — render the briefs first')
    brief = open(brief_path).read()
    envelope = open(ENVELOPE).read()
    if SEP in brief or any(s in brief for s in SLOTS):
        die('the rendered brief already contains a slot or the separator')
    # A slot may legitimately appear more than once — the prefix is declared and
    # then used in the numbering instruction — so the invariant is not "once" but
    # "every occurrence is substituted, and none is invented".
    want = {s: envelope.count(s) for s in SLOTS}
    missing = [s for s, n in want.items() if n < 1]
    if missing:
        die(f'the envelope never names {missing}')

    row = next((r for r in registry() if r['target'] == target), None)
    if row is None:
        die(f'{target} is not a registered clustering target')
    if not os.path.exists(row['packet']):
        die(f"{row['packet']} does not exist")
    values = {'{{GROUP_FILE}}': row['packet'], '{{PREFIX}}': row['prefix'],
              '{{OUTPUT_PATH}}': row['output']}
    filled = envelope
    for slot, value in values.items():
        filled = filled.replace(slot, value)
    if any(s in filled for s in SLOTS):
        die('a slot survived substitution')
    for slot, value in values.items():
        if filled.count(value) != want[slot]:
            die(f'{value} appears {filled.count(value)} times, expected '
                f'{want[slot]} — the slot count and the substitution disagree')
    return brief + SEP + filled, row


def sent_prompt(agent_id):
    root = os.path.expanduser(f'~/.claude/projects/{PROJECT}')
    hits = glob.glob(f'{root}/*/subagents/agent-{agent_id}.jsonl')
    if not hits:
        die(f'no transcript for agent {agent_id}')
    for line in open(hits[0]):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        msg = rec.get('message') or {}
        if msg.get('role') != 'user':
            continue
        c = msg.get('content')
        return c if isinstance(c, str) else ''.join(
            b.get('text', '') for b in c if isinstance(b, dict))
    die(f'agent {agent_id}: no user message in the transcript')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--register', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--target')
    ap.add_argument('--verify-sent', metavar='AGENT_ID')
    a = ap.parse_args()

    if a.register:
        return register(a.root)

    if a.check:
        rows = registry()
        files, _ = changed_files()
        if [r['target'] for r in rows] != files:
            die('the registry targets are not the fixture\'s changed files, in order')
        for r in rows:
            compose(a.root, r['target'])
        print(f'{len(rows)} assignments compose cleanly; targets match the fixture; '
              f'prefixes distinct and free of the frozen inventory')
        return

    if not a.target:
        die('need --target, --register or --check')
    prompt, row = compose(a.root, a.target)
    if a.verify_sent:
        got = sent_prompt(a.verify_sent)
        if got == prompt:
            print(f"{a.verify_sent}  {row['target']}  RECEIVED EXACTLY THE COMPOSED "
                  f"PROMPT  {sha1(prompt)}")
            return
        die(f'{a.verify_sent} received a prompt that is not the composed one\n'
            f'  composed {sha1(prompt)} ({len(prompt)} chars)\n'
            f'  received {sha1(got)} ({len(got)} chars)')
    print(prompt)
    print(f"\n--- composed sha1 {sha1(prompt)}  prefix {row['prefix']}  "
          f"output {row['output']}", file=sys.stderr)


if __name__ == '__main__':
    main()
