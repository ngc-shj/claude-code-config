#!/usr/bin/env python3
"""Apply the merge verdicts to the eight cluster outputs, mechanically.

The clustering agents worked in parallel and could not see each other, so two of
them may have written separate new claims for one assertion; the merge agent said
which collapse into which. This folds those verdicts in and emits the round's
`clusters.tsv`, plus the claim-only file the adjudication panel reads.

Four cases, and nothing else happens to a row:

  existing            id, status and the inventory's canonical claim text
  new + keep          its own id and its own claim
  new -> existing     members fold into the existing target; the claim text is
                      the INVENTORY's, never the new row's
  new -> new keep     members fold into the keep target; the claim text is the
                      TARGET's

A row that merged away is gone from the output — it is not kept with a marker,
because `measure.py` counts rows and a marker row would be counted.

Member ids are sorted lexicographically, which is numeric order for the `F%04d`
ids `extract.py` mints, so the file is byte-reproducible from the same inputs.

**No unregistered exclusion happens here.** No popularity threshold, no minimum
member count, no dropping of singletons: every finding that entered clustering
leaves it inside exactly one cluster, and the verification below asserts that
rather than trusting it.

Usage:
  round-24/apply-merge.py --root <dir> [--out-dir <dir>]
"""
import argparse
import collections
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INVENTORY = os.path.join(HERE, 'cluster-inventory.tsv')
CLUSTER_REGISTRY = os.path.join(HERE, 'cluster-outputs.tsv')
VERDICTS = os.path.join(HERE, 'merge-verdicts.tsv')
FINDINGS = os.path.join(HERE, 'findings.tsv')
COLUMNS = ['cluster_id', 'status', 'n', 'member_ids', 'claim']


def die(msg):
    sys.exit(f'apply-merge: {msg}')


def tsv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))


def apply_verdicts(cluster_rows, verdicts, inventory):
    """(cluster_id -> (status, members, claim)) after folding every merge."""
    target = {r['cluster_id']: r['target'].strip()
              for r in verdicts if r['verdict'].strip() == 'merge'}
    for src, dst in target.items():
        if dst in target:
            die(f'{src} merges into {dst}, which itself merges — chains are not '
                f'applied, and the merge verification should have refused this')

    out = {}

    def add(cid, status, members, claim):
        if cid in out:
            kept_status, kept_members, kept_claim = out[cid]
            if kept_status != status:
                die(f'{cid} appears as both {kept_status} and {status}')
            out[cid] = (status, kept_members | members, kept_claim)
        else:
            out[cid] = (status, set(members), claim)

    for row in cluster_rows:
        cid = row['cluster_id'].strip()
        members = {m.strip() for m in row['member_ids'].split(',') if m.strip()}
        status = row['status'].strip()
        if status == 'existing':
            if cid not in inventory:
                die(f'{cid} is marked existing but is not in the inventory')
            add(cid, 'existing', members, inventory[cid])
            continue
        dst = target.get(cid)
        if dst is None:                                   # new + keep
            add(cid, 'new', members, row['claim'])
        elif dst in inventory:                            # new -> existing
            add(dst, 'existing', members, inventory[dst])
        else:                                             # new -> new keep
            add(dst, 'new', members, None)                # claim filled below
    # a new -> new keep target must exist in its own right; take its claim
    for row in cluster_rows:
        cid = row['cluster_id'].strip()
        if cid in out and out[cid][2] is None and row['status'].strip() == 'new' \
                and target.get(cid) is None:
            s, m, _ = out[cid]
            out[cid] = (s, m, row['claim'])
    unresolved = [c for c, v in out.items() if v[2] is None]
    if unresolved:
        die(f'{len(unresolved)} merge target(s) have no claim text — a target was '
            f'not itself a keep row')
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--out-dir', default=HERE)
    a = ap.parse_args()

    inventory = {r['cluster_id']: r['claim'] for r in tsv(INVENTORY)}
    verdicts = tsv(VERDICTS)
    rows = []
    for reg in tsv(CLUSTER_REGISTRY):
        if not os.path.exists(reg['output']):
            die(f"{reg['output']} does not exist")
        rows += tsv(reg['output'])

    merged = apply_verdicts(rows, verdicts, inventory)
    findings = [r['id'] for r in tsv(FINDINGS)]

    clusters = os.path.join(a.out_dir, 'clusters.tsv')
    with open(clusters, 'w', newline='') as f:
        # LF, not csv's default CRLF: round 17's committed clusters.tsv and
        # findings.tsv carry no CR, and a stray \r rides into the last column of
        # anything that splits on \n rather than parsing CSV.
        w = csv.DictWriter(f, delimiter='\t', fieldnames=COLUMNS,
                           extrasaction='ignore', lineterminator='\n')
        w.writeheader()
        for cid in sorted(merged):
            status, members, claim = merged[cid]
            ids = sorted(members)
            w.writerow({'cluster_id': cid, 'status': status, 'n': len(ids),
                        'member_ids': ','.join(ids), 'claim': claim})

    adj = os.path.join(a.out_dir, 'adjudicate-input.tsv')
    with open(adj, 'w', newline='') as f:
        w = csv.DictWriter(f, delimiter='\t', fieldnames=['cluster_id', 'claim'],
                           lineterminator='\n')
        w.writeheader()
        for cid in sorted(c for c, v in merged.items() if v[0] == 'new'):
            w.writerow({'cluster_id': cid, 'claim': merged[cid][2]})

    # ---- verification, reported as pass/fail only
    fails = []
    assigned = collections.Counter()
    for cid, (status, members, claim) in merged.items():
        for m in members:
            assigned[m] += 1
    if set(assigned) != set(findings):
        fails.append('finding ids in the final clusters differ from findings.tsv')
    if any(c != 1 for c in assigned.values()):
        fails.append('a finding id appears in more than one final cluster')
    rows_out = tsv(clusters)
    if len({r['cluster_id'] for r in rows_out}) != len(rows_out):
        fails.append('duplicate cluster id in clusters.tsv')
    for r in rows_out:
        if int(r['n']) != len([m for m in r['member_ids'].split(',') if m]):
            fails.append('n does not equal the member count')
            break
    for r in rows_out:
        if r['status'] == 'existing':
            if r['cluster_id'] not in inventory:
                fails.append('existing id not in the inventory'); break
            if r['claim'] != inventory[r['cluster_id']]:
                fails.append('existing claim text is not byte-identical to the '
                             'inventory'); break
    keep = {v['cluster_id'] for v in verdicts if v['verdict'].strip() == 'keep'}
    final_new = {r['cluster_id'] for r in rows_out if r['status'] == 'new'}
    if final_new != keep:
        fails.append('final new id set differs from the merge keep set')
    adj_rows = tsv(adj)
    if {r['cluster_id'] for r in adj_rows} != final_new:
        fails.append('adjudication input id set differs from the final new id set')
    with open(adj) as f:
        header = f.readline().rstrip('\n').split('\t')
    if header != ['cluster_id', 'claim']:
        fails.append('adjudication input carries columns beyond cluster_id/claim')

    checks = [
        'every finding id appears exactly once in the final clusters',
        'n equals the member count on every row',
        'no duplicate cluster id',
        'existing ids and claim text byte-identical to the 94-claim inventory',
        'final new id set equals the merge keep set',
        'adjudication input id set equals the final new id set',
        'adjudication input has only cluster_id and claim',
    ]
    print('APPLY VERIFICATION')
    for c in checks:
        print(f'  {"FAIL" if fails else "PASS"}  {c}')
    if fails:
        print('\nfailure classes:')
        for f_ in dict.fromkeys(fails):
            print(f'  {f_}')
        sys.exit(1)
    print(f'\nwrote {os.path.relpath(clusters, os.path.dirname(HERE))} and '
          f'{os.path.relpath(adj, os.path.dirname(HERE))} — contents not displayed')


if __name__ == '__main__':
    main()
