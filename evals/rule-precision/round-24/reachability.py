#!/usr/bin/env python3
"""Read the reachability probe's TOOL CALLS, and structurally refuse to read more.

Round 7's lesson is that ablating a section nobody reads measures nothing. The
gate that answers "did the manipulation arrive" must therefore look at what the
probe agents *did*, not at what they *found* — and the protocol says so:

    Only the traces are inspected. No finding, severity, or count from these
    three agents is read, and none of them enters any metric.

A promise is not a mechanism. This script emits `tool_use` blocks only.
Assistant `text` and `thinking` blocks — where a review's findings live — and
`tool_result` content — where the bytes an agent read come back — are dropped
before anything is printed. The tool inputs that are printed are reduced to a
path or a matched marker rather than echoed, and the only thing ever taken from
a `tool_result` is its `is_error` flag. There is no flag to turn that off.

**The three transcripts are named, not searched for.** `reachability-manifest.tsv`
pins the session, the three agent ids and each transcript's sha1. A `--since`
timestamp was the first draft and cannot survive the round: once 72 review agents
have run in the same session, "everything after time T" no longer selects the
probe. Naming them also makes the analysis re-runnable by anyone holding the
transcripts, and makes an edited transcript fail rather than pass quietly.

**Issuing the extraction is not executing it.** A `Bash` call that names the
Finding Floor and then fails still put the command in the trace. Each `tool_use`
is joined to the `tool_result` carrying its id, and only a result with
`is_error` false counts.

The gate, per the protocol's table:

    3/3 executed  -> proceed
    1-2/3         -> STOP. W is an uncontrolled mixture; investigate the wiring
    0/3           -> STOP. Wiring investigation; the ablation would measure nothing

"Executed" is the **Finding Floor extraction** — the `awk` the digest prescribes
— because that is the quantity chapter 4 reports as W 18/18 against N 0/18, and
the one that is zero when the wiring is dead. Reading the digest at all is
reported beside it as the weaker precondition.

Usage:
  round-24/reachability.py [--manifest <path>] [--transcript-dir <dir>]
"""
import argparse
import csv
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'
ROOT = os.path.expanduser(f'~/.claude/projects/{PROJECT}')
MANIFEST = os.path.join(HERE, 'reachability-manifest.tsv')

DIGEST = 'common-rules.digest.md'
FLOOR = '### Finding Floor'          # the marker the digest's awk anchors on
GATE_N = 3

FAILED = []


def die(msg):
    sys.exit(f'reachability: {msg}')


def sha1(path):
    with open(path, 'rb') as f:
        body = f.read()
    return hashlib.sha1(b'blob %d\0' % len(body) + body).hexdigest()


def read_manifest(path):
    if not os.path.exists(path):
        die(f'{os.path.relpath(path, HERE)} is missing — the probe transcripts '
            f'are named, not searched for')
    with open(path, newline='') as f:
        rows = [r for r in csv.DictReader(f, delimiter='\t')]
    if len(rows) != GATE_N:
        die(f'{len(rows)} agents in the manifest, expected exactly {GATE_N}')
    sessions = {r['session'] for r in rows}
    if len(sessions) != 1:
        die(f'the probe must be one session; manifest names {sorted(sessions)}')
    if len({r['agent_id'] for r in rows}) != GATE_N:
        die('duplicate agent_id in the manifest')
    return rows


def summarise(inp):
    """A path or a marker — never the payload, never a result."""
    for key in ('file_path', 'path', 'pattern', 'command', 'notebook_path'):
        val = inp.get(key)
        if isinstance(val, str):
            if FLOOR in val:
                return f'<names {FLOOR!r}>'
            if DIGEST in val:
                return f'<reads {DIGEST}>'
            return os.path.basename(val.split()[-1]) if key == 'command' else val
    return '<no path>'


def trace(path):
    """(tool, summary, ok) per tool_use, joined to its result by tool_use_id.

    `ok` is None when no result carries that id — an issued call whose outcome
    is unknown, which is not an execution either.
    """
    calls, results = [], {}
    with open(path) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            msg = rec.get('message') or {}
            content = msg.get('content')
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get('type') == 'tool_use':
                    calls.append((block.get('id'), block.get('name', '?'),
                                  summarise(block.get('input') or {})))
                elif block.get('type') == 'tool_result':
                    # the flag, and nothing else from this block, ever
                    results[block.get('tool_use_id')] = bool(block.get('is_error'))
    out = []
    for cid, name, s in calls:
        ok = None if cid not in results else (not results[cid])
        out.append((name, s, ok))
    return out


def executed(calls, marker):
    """Did a call naming `marker` come back without an error?"""
    return any(marker in s and ok for _, s, ok in calls)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', default=MANIFEST)
    ap.add_argument('--transcript-dir', default=ROOT,
                    help='project transcript root; the manifest supplies the session')
    a = ap.parse_args()
    rows = read_manifest(a.manifest)

    print('REACHABILITY PROBE — tool calls only. No finding, severity, count or\n'
          'review text is read by this script or printed by it. Only the three\n'
          'agents named in the manifest are analysed.\n')

    n_ok = 0
    for i, row in enumerate(rows, 1):
        path = os.path.join(a.transcript_dir, row['session'], 'subagents',
                            f'agent-{row["agent_id"]}.jsonl')
        if not os.path.exists(path):
            FAILED.append(f'{row["agent_id"]}: transcript missing')
            print(f'agent {i}  {row["agent_id"][:8]}…  TRANSCRIPT MISSING')
            continue
        got = sha1(path)
        if got != row['sha1']:
            FAILED.append(f'{row["agent_id"]}: transcript sha1 moved')
            print(f'agent {i}  {row["agent_id"][:8]}…  SHA1 MISMATCH  '
                  f'pinned {row["sha1"][:12]}  found {got[:12]}')
            continue

        calls = trace(path)
        floor = executed(calls, FLOOR)
        digest = executed(calls, DIGEST)
        n_ok += floor
        print(f'agent {i}  {row["agent_id"][:8]}…  {len(calls)} tool calls  '
              f'digest={"yes" if digest else "NO"}  '
              f'FindingFloor={"YES" if floor else "no"}')
        for name, s, ok in calls:
            state = 'ok' if ok else ('ERROR' if ok is False else 'no-result')
            print(f'          {name:12s} {state:9s} {s}')

    print(f'\nFinding Floor extraction, issued AND returning without error: '
          f'{n_ok}/{len(rows)}')
    if FAILED:
        print('*** ' + '\n*** '.join(FAILED))
        sys.exit(2)
    if n_ok == GATE_N:
        print('GATE: 3/3 — proceed. The manipulation arrives.')
        sys.exit(0)
    print(f'GATE: {n_ok}/3 — STOP.' + (
        ' W is an uncontrolled mixture; investigate the wiring.' if n_ok
        else ' Wiring investigation; the ablation would measure nothing.'))
    sys.exit(1)


if __name__ == '__main__':
    main()
