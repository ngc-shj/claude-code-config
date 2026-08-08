#!/usr/bin/env python3
"""Turn the merge agent's clusters into the blind adjudication input.

Three things happen here and each is a pre-registered property of the seed:

  1. id conservation is CHECKED, not trusted — every input entry appears in
     exactly one cluster and the n column agrees with member_ids.
  2. clusters below the >=3/5 panellist threshold are dropped from the seed.
  3. what reaches the adjudicators is claim text only, shuffled, with the
     cluster's panellist and member counts withheld. Popularity is not
     evidence, so a claim four panellists made must be indistinguishable from
     one a single panellist made.

The shuffle uses a fixed seed so the order the adjudicators saw is
reconstructible from the checked-in files rather than being lost with the run.
"""
import csv
import random
import sys

SP = '/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/e392c887-68cf-492b-a61c-d5d0f9838aa9/scratchpad/r16'
SHUFFLE_SEED = 16
THRESHOLD = 3

rows = list(csv.DictReader(open(f'{SP}/all.tsv', newline=''), delimiter='\t'))
clusters = list(csv.DictReader(open(f'{SP}/clusters/seed.tsv', newline=''), delimiter='\t'))

# 1. id conservation
seen, dupes, bad_n, bad_p = {}, [], [], []
for c in clusters:
    ids = [i.strip() for i in c['member_ids'].split(',') if i.strip()]
    if int(c['n']) != len(ids):
        bad_n.append((c['cluster_id'], c['n'], len(ids)))
    if int(c['panellists']) != len({i[0] for i in ids}):
        bad_p.append((c['cluster_id'], c['panellists'], len({i[0] for i in ids})))
    for i in ids:
        if i in seen:
            dupes.append((i, seen[i], c['cluster_id']))
        seen[i] = c['cluster_id']

allids = {r['id'] for r in rows}
missing = sorted(allids - set(seen))
unknown = sorted(set(seen) - allids)

print(f'{len(rows)} entries -> {len(clusters)} clusters')
for label, bad in (('duplicated ids', dupes), ('dropped ids', missing),
                   ('ids not in the input', unknown),
                   ('n disagrees with member_ids', bad_n),
                   ('panellists disagrees with member_ids', bad_p)):
    print(f'  {label:36s}{len(bad)}' + (f'  {bad[:6]}' if bad else ''))

if dupes or missing or unknown or bad_n or bad_p:
    print('\nFAIL: the merge is not id-conserving. Do not build the seed from it.')
    sys.exit(1)

# 2. the >=3/5 threshold
kept = [c for c in clusters if int(c['panellists']) >= THRESHOLD]
dropped = len(clusters) - len(kept)
by_p = {}
for c in clusters:
    by_p[int(c['panellists'])] = by_p.get(int(c['panellists']), 0) + 1
print(f'\npanellist agreement: ' +
      '  '.join(f'{k}/5: {by_p[k]}' for k in sorted(by_p, reverse=True)))
print(f'seed keeps {len(kept)} clusters at >={THRESHOLD}/5; {dropped} fall below and are '
      f'not part of the seed')

# 3. blind, shuffled, counts withheld
order = list(kept)
random.Random(SHUFFLE_SEED).shuffle(order)
with open(f'{SP}/new-claims.tsv', 'w', newline='') as fh:
    w = csv.writer(fh, delimiter='\t', lineterminator='\n')
    w.writerow(['cluster_id', 'claim'])
    for c in order:
        w.writerow([c['cluster_id'], c['claim']])
print(f'\nwrote {SP}/new-claims.tsv — {len(order)} rows, claim text only, '
      f'shuffled with seed {SHUFFLE_SEED}')
