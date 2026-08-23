#!/usr/bin/env python3
"""Read the reachability probe's TOOL CALLS, and structurally refuse to read more.

Round 7's lesson is that ablating a section nobody reads measures nothing. The
gate that answers "did the manipulation arrive" must therefore look at what the
probe agents *did*, not at what they *found* — and the protocol says so:

    Only the traces are inspected. No finding, severity, or count from these
    three agents is read, and none of them enters any metric.

A promise is not a mechanism. This script parses each agent's transcript and
emits `tool_use` blocks only. Assistant `text` blocks — where a review's
findings live — and `tool_result` blocks — where the file contents the agent
read come back — are dropped before anything is printed, and the tool inputs
that are printed are reduced to a path or a matched marker rather than echoed.
There is no flag to turn that off.

The gate, per the protocol's table:

    3/3 executed  -> proceed
    1-2/3         -> STOP. W is an uncontrolled mixture; investigate the wiring
    0/3           -> STOP. Wiring investigation; the ablation would measure nothing

"Executed" is the **Finding Floor extraction** — the `awk` the digest prescribes
— because that is the quantity chapter 4 reports as W 18/18 against N 0/18, and
the one that is zero when the wiring is dead. Reading the digest at all is
reported beside it as the weaker precondition.

Usage:
  round-24/reachability.py --session <uuid> [--since <ISO8601>]
"""
import argparse
import glob
import json
import os
import sys

PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'
ROOT = os.path.expanduser(f'~/.claude/projects/{PROJECT}')

DIGEST = 'common-rules.digest.md'
FLOOR = '### Finding Floor'          # the marker the digest's awk anchors on
GATE_N = 3


def tool_calls(path):
    """Every tool_use in one transcript, as (tool, one-line input summary).

    Nothing else leaves this function. `text` blocks and `tool_result` blocks
    are not returned, not logged, and not counted.
    """
    out = []
    with open(path) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            msg = rec.get('message') or {}
            if msg.get('role') != 'assistant':
                continue
            content = msg.get('content')
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get('type') != 'tool_use':
                    continue
                out.append((block.get('name', '?'), summarise(block.get('input') or {})))
    return out


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


def verdict(calls):
    floor = any(FLOOR in s for _, s in calls)
    digest = any(DIGEST in s for _, s in calls)
    return floor, digest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--session', required=True)
    ap.add_argument('--since', default='', help='ISO timestamp; ignore older files')
    a = ap.parse_args()

    pattern = os.path.join(ROOT, a.session, 'subagents', '*.jsonl')
    paths = sorted(glob.glob(pattern), key=os.path.getmtime)
    if a.since:
        import datetime
        cut = datetime.datetime.fromisoformat(a.since).timestamp()
        paths = [p for p in paths if os.path.getmtime(p) >= cut]
    if not paths:
        sys.exit(f'no subagent transcripts under {os.path.dirname(pattern)}')

    print('REACHABILITY PROBE — tool calls only. No finding, severity, count or\n'
          'review text is read by this script or printed by it.\n')
    executed = 0
    for i, path in enumerate(paths, 1):
        calls = tool_calls(path)
        floor, digest = verdict(calls)
        executed += floor
        print(f'agent {i}  {os.path.basename(path)[:8]}…  {len(calls)} tool calls  '
              f'digest={"yes" if digest else "NO"}  '
              f'FindingFloor={"YES" if floor else "no"}')
        for name, s in calls:
            print(f'          {name:12s} {s}')

    n = len(paths)
    print(f'\nFinding Floor extraction: {executed}/{n}')
    if n != GATE_N:
        print(f'*** {n} transcripts, expected {GATE_N}. The gate is defined over '
              f'exactly {GATE_N} probe agents.')
        sys.exit(2)
    if executed == GATE_N:
        print('GATE: 3/3 — proceed. The manipulation arrives.')
        sys.exit(0)
    print(f'GATE: {executed}/3 — STOP.' + (
        ' W is an uncontrolled mixture; investigate the wiring.' if executed
        else ' Wiring investigation; the ablation would measure nothing.'))
    sys.exit(1)


if __name__ == '__main__':
    main()
