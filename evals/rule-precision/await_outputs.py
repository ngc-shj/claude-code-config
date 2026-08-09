#!/usr/bin/env python3
"""Wait for agent outputs to exist AND stop changing. Never decide by hand.

A completion notice is not evidence about a file. Rounds 17, 18 and 20 each hit
a version of this and the third one cost a needless rerun:

  round 17  DONE fired before the write; a reply was missing and found late
  round 18  DONE fired twice and the FIRST report was wrong
  round 20  DONE fired before the write, a single `ls` found nothing, and the
            work was relaunched — the file landed a minute later

The rule those rounds wrote down was "check the file on disk". That rule is not
enough, because a check has a *time*, and a single check cannot tell "not yet"
from "never". This distinguishes them: poll until every expected path exists and
its size has stopped changing, or until the deadline, and then say precisely
which of the two happened.

Usage:
  await_outputs.py <timeout_seconds> <path> [<path> ...]

Exit 0 when all paths exist and are stable. Exit 1 on timeout, naming what is
missing and what was still growing — a growing file means give it longer, a
missing one at deadline means the agent really did not write it.
"""
import os
import sys
import time

POLL = 5.0
STABLE_FOR = 10.0     # a size unchanged this long counts as finished


def sizes(paths):
    out = {}
    for p in paths:
        try:
            out[p] = os.path.getsize(p)
        except OSError:
            out[p] = None
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: await_outputs.py <timeout_seconds> <path> ...')
    timeout = float(sys.argv[1])
    paths = sys.argv[2:]
    deadline = time.monotonic() + timeout
    last, unchanged_since = sizes(paths), {}

    while True:
        now = sizes(paths)
        stable = []
        for p in paths:
            if now[p] is None or now[p] == 0:
                unchanged_since.pop(p, None)
                continue
            if now[p] == last.get(p):
                unchanged_since.setdefault(p, time.monotonic())
                if time.monotonic() - unchanged_since[p] >= STABLE_FOR:
                    stable.append(p)
            else:
                unchanged_since[p] = time.monotonic()
        last = now

        if len(stable) == len(paths):
            print(f'all {len(paths)} outputs present and stable')
            for p in paths:
                with open(p, errors='replace') as fh:
                    print(f'  {sum(1 for _ in fh):6d} lines  {p}')
            return 0

        if time.monotonic() >= deadline:
            missing = [p for p in paths if now[p] in (None, 0)]
            growing = [p for p in paths if p not in stable and p not in missing]
            print(f'TIMEOUT after {timeout:.0f}s — {len(stable)}/{len(paths)} stable')
            if growing:
                print('  still being written (give it longer, do NOT relaunch):')
                for p in growing:
                    print(f'    {p}')
            if missing:
                print('  absent at the deadline (this is the case that needs a relaunch):')
                for p in missing:
                    print(f'    {p}')
            return 1

        time.sleep(POLL)


if __name__ == '__main__':
    sys.exit(main())
