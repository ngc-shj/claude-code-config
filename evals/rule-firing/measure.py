#!/usr/bin/env python3
"""Measure how often each triangulate rule actually produces a finding.

The ablation harness next door asks whether a rule CHANGES a review. This asks
the cheaper question first: does the rule ever fire at all? A rule that is
routed to, considered, and answered "N/A" in hundreds of real reviews without
ever producing a finding costs routing attention on every review and has no
recorded return.

Two counts per rule, and the gap between them is the point:

  checked   reviews citing the rule anywhere — including the Recurring Issue
            Check list, where "R10: N/A" is the usual form
  findings  reviews citing the rule inside a finding block (a heading carrying
            [Critical|Major|Minor], or a line that carries one itself)

Opportunities are age-corrected: a rule added last week cannot have fired in a
review written last month, so `fire%` divides by the reviews that postdate the
rule's first appearance in common-rules.md.

Usage:
  evals/rule-firing/measure.py [--glob GLOB] [--catalogue PATH] [--tsv]

Defaults scan sibling repositories' `docs/archive/review/*-review.md` next to
this repo. Rule IDs are read from the catalogue rather than assumed, so the
tool stays correct as rules are added or renumbered.
"""
import argparse
import collections
import datetime
import glob as globmod
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_GLOB = os.path.join(os.path.dirname(REPO), '*/docs/archive/review/*-review.md')
DEFAULT_CATALOGUE = os.path.join(REPO, 'skills/triangulate/common-rules.md')

SEVERITY = re.compile(r'\[(?:Critical|Major|Minor)\]')

# Both guards were paid for in false positives, twice each.
#
# Left: a plain \b admits the requirement IDs these repos use — NF-R2, F-R5,
# Func-R2, T-R2 — because a hyphen is a word boundary. The lookbehind rejects
# any word char OR hyphen.
#
# Right: `R<n>-<anything>` is never a rule citation in this corpus. It is a
# range (`R1-R35`, `RS1-RS3` — "I checked this span", not "this rule fired") or
# a finding ID whose `R<n>` is the REVIEW ROUND (`R2-F1`, `R3-S1`, `R2-#1` —
# round 2 finding 1). The first version of this guard excluded only ranges,
# on the assumption that `R2-F1` meant rule R2; sampling the corpus showed it
# means round 2, and that reading inflated R2 by 88 heading occurrences and R3
# by 43. Validate any change to this pattern against sampled corpus contexts,
# never against invented examples.
RULE_ID = re.compile(r'(?<![\w-])(?:R|RS|RT)\d+\b(?!-\w)')
ROW_ID = re.compile(r'^\|\s*((?:R|RS|RT)\d+)\s*\|', re.M)


def catalogue_ids(path):
    """Rule IDs as the catalogue currently defines them — never a hardcoded range."""
    with open(path, encoding='utf-8') as fh:
        return set(ROW_ID.findall(fh.read()))


def first_seen(ids, catalogue, repo):
    """Date each rule's row first appeared, via git. None when git cannot say."""
    rel = os.path.relpath(catalogue, repo)
    out = {}
    for rule in sorted(ids):
        proc = subprocess.run(
            ['git', '-C', repo, 'log', '--reverse', '--format=%aI', '-S', f'| {rule} |', '--', rel],
            capture_output=True, text=True)
        lines = [ln for ln in proc.stdout.strip().split('\n') if ln]
        out[rule] = lines[0][:10] if lines else None
    return out


def repo_root(path):
    """The repository directory containing a docs/archive/review artifact."""
    parts = os.path.abspath(path).split(os.sep)
    if 'docs' in parts:
        return os.sep.join(parts[:parts.index('docs')])
    return os.path.dirname(path)


def review_dates(files):
    """Creation date per review file: git where the repo knows, mtime otherwise."""
    dates = {}
    by_repo = collections.defaultdict(list)
    for path in files:
        by_repo[repo_root(path)].append(path)

    for repo, paths in by_repo.items():
        if os.path.isdir(os.path.join(repo, '.git')):
            proc = subprocess.run(
                ['git', '-C', repo, 'log', '--diff-filter=A', '--format=C%aI', '--name-only',
                 '--', 'docs/archive/review'],
                capture_output=True, text=True)
            current = None
            for line in proc.stdout.split('\n'):
                if line.startswith('C'):
                    current = line[1:11]
                elif line.endswith('-review.md') and current:
                    dates.setdefault(os.path.join(repo, line), current)
        for path in paths:
            dates.setdefault(path, datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat())
    return dates


def scan(files, ids, dates, added):
    checked = collections.Counter()
    findings = collections.Counter()
    opportunities = collections.Counter()
    repos = collections.defaultdict(set)

    for path in files:
        when = dates.get(path)
        name = os.path.basename(repo_root(path))
        for rule in ids:
            if added.get(rule) and when and added[rule] <= when:
                opportunities[rule] += 1

        with open(path, encoding='utf-8', errors='replace') as fh:
            text = fh.read()
        cited, fired = set(), set()
        in_finding = False
        for line in text.split('\n'):
            if line.lstrip().startswith('#'):
                in_finding = bool(SEVERITY.search(line))
            hits = {m.group(0) for m in RULE_ID.finditer(line)} & ids
            if not hits:
                continue
            cited |= hits
            if in_finding or SEVERITY.search(line):
                fired |= hits
        for rule in cited:
            checked[rule] += 1
            repos[rule].add(name)
        for rule in fired:
            findings[rule] += 1
    return checked, findings, opportunities, repos


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--glob', default=DEFAULT_GLOB)
    ap.add_argument('--catalogue', default=DEFAULT_CATALOGUE)
    ap.add_argument('--tsv', action='store_true', help='machine-readable output')
    ap.add_argument('--json', metavar='PATH', help='also write the raw counts here')
    ap.add_argument('--mature', type=int, default=200,
                    help='opportunities needed before a zero counts as evidence (default 200)')
    args = ap.parse_args()

    ids = catalogue_ids(args.catalogue)
    if not ids:
        sys.exit(f'no rule rows found in {args.catalogue}')
    files = sorted(globmod.glob(args.glob))
    if not files:
        sys.exit(f'no review artifacts matched {args.glob}')

    added = first_seen(ids, args.catalogue, REPO)
    dates = review_dates(files)
    checked, findings, opportunities, repos = scan(files, ids, dates, added)

    rows = sorted(ids, key=lambda r: (findings[r], checked[r]))
    if args.tsv:
        print('rule\tadded\topportunities\tchecked\tfindings\tfire_pct\trepos')
        for r in rows:
            o = opportunities[r]
            pct = f'{findings[r] / o * 100:.2f}' if o else ''
            print(f'{r}\t{added.get(r) or ""}\t{o}\t{checked[r]}\t{findings[r]}\t{pct}\t{len(repos[r])}')
    else:
        print(f'{len(files)} review artifacts, {len(ids)} rules\n')
        print(f'{"rule":6s}{"added":12s}{"opps":>6s}{"checked":>9s}{"findings":>10s}{"fire%":>8s}')
        print('-' * 51)
        for r in rows:
            o = opportunities[r]
            pct = f'{findings[r] / o * 100:.2f}' if o else '-'
            print(f'{r:6s}{str(added.get(r) or "?"):12s}{o:6d}{checked[r]:9d}{findings[r]:10d}{pct:>8s}')

        dead = [r for r in rows if findings[r] == 0 and opportunities[r] >= args.mature]
        print(f'\nnever fired with >={args.mature} opportunities: {len(dead)}')
        for r in dead:
            print(f'  {r:6s} checked {checked[r]:4d} times across {len(repos[r])} repos, 0 findings')

    if args.json:
        with open(args.json, 'w') as fh:
            json.dump({'files': len(files), 'added': added,
                       'checked': dict(checked), 'findings': dict(findings),
                       'opportunities': dict(opportunities),
                       'repos': {k: sorted(v) for k, v in repos.items()}}, fh, indent=1)


if __name__ == '__main__':
    main()
