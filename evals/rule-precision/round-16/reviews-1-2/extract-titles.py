#!/usr/bin/env python3
"""Build each review's titles-only stimulus from its three base replies.

This is a script and not an agent on purpose. The stimulus T and TS read IS the
treatment, so anything that summarised, reworded, ranked or dropped a title
would be varying the treatment between reviews without recording it. A regex
cannot do any of those things.

The rule is the whole of it: take the text after `### <Severity>: ` from every
finding heading, in the order the replies were written, and drop nothing.
Duplicates between reviewers are KEPT — two reviewers wording the same defect
differently is two lines, because deciding they are the same defect is a
judgement, and a judgement here would be selection.

Output matches round 15's stimulus byte-for-byte in its header, so T reads the
same kind of file it read there.
"""
import glob
import os
import re
import sys

SP = '/tmp/claude-1000/-home-noguchi-ghq-github-com-ngc-shj-claude-code-config/e392c887-68cf-492b-a61c-d5d0f9838aa9/scratchpad/r16'
HEADING = re.compile(r'^###\s+(Critical|Major|Minor)\s*:\s*(.+?)\s*$')

HEADER = """# Findings already reported on this change

Three reviewers have already read this diff. These are the titles of what they \
reported — titles only, deliberately.

"""

reviews = sorted({os.path.basename(p).split('-')[1]
                  for p in glob.glob(f'{SP}/out/base-*-*.md')}, key=int)
if not reviews:
    sys.exit('no base replies found')

for k in reviews:
    parts = sorted(glob.glob(f'{SP}/out/base-{k}-*.md'))
    titles, no_findings = [], 0
    for p in parts:
        body = open(p).read()
        found = [m.group(2) for line in body.split('\n')
                 for m in [HEADING.match(line)] if m]
        if not found and re.search(r'^\s*No findings\s*$', body, re.M):
            no_findings += 1
        titles.extend(found)

    with open(f'{SP}/base/titles-{k}.md', 'w') as fh:
        fh.write(HEADER + '\n'.join(f'- {t}' for t in titles) + '\n')

    print(f'review {k}: {len(parts)} replies, {len(titles)} titles'
          + (f', {no_findings} replies said No findings' if no_findings else ''))
    per = [len([1 for line in open(p) if HEADING.match(line)]) for p in parts]
    print(f'           per reply: {per}')
