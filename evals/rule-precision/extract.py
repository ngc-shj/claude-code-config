#!/usr/bin/env python3
"""Turn a round's review files into findings.tsv, structurally.

Rounds 18 and 19 each lost findings to a heading the previous round's regex did
not admit — `### Minor (question, per Finding Floor): ...`, then
`### Minor question: ...` — and each time the loss was in the arm carrying the
Finding Floor, because clause 2 tells a reviewer to file an ungrounded
requirement as a Minor question and the brief's template has no slot for one.
Widening the pattern each round is a losing game: the next arm invents the next
shape.

So this does not pattern-match punctuation. It reads the document's structure:

  A `###` heading opens a BLOCK. A block is a FINDING if and only if it contains
  a `File:` field, which the brief requires of every finding and which no
  section heading ("Cross-cutting verification", "Codebase awareness") carries.
  Severity is whichever severity word appears in the heading; the title is what
  is left after it. A block with a File: field and no severity word is reported,
  not guessed at, and not dropped.

Fields are multi-line. One round-19 agent hard-wrapped 446 of its field lines
while every other agent in that round wrapped at most five, and taking a field's
first line only truncated its sentences mid-clause. A field therefore runs until
the next field label, the next heading, or a blank line.

Reproduces `round-19/findings.tsv` byte-for-byte from that round's review files.

Usage:  extract.py <dir-of-review-files> <output.tsv>
        review files are named <ARM>-<review>-<part>.md
"""
import collections
import csv
import pathlib
import re
import sys

SEVERITIES = ('Critical', 'Major', 'Minor')
HEADING = re.compile(r'^###\s+(.*)$')
FIELD = re.compile(r'^\s*(?:[-*]\s*)?(?:\**)(File|What is wrong|What breaks in production|Fix)(?:\**)\s*:\s*(.*)$', re.I)
SEVERITY = re.compile(r'\b(Critical|Major|Minor)\b', re.I)
KEEP = {'file': 'file', 'what is wrong': 'what_is_wrong'}
FIELDS = ['id', 'arm', 'review', 'part', 'severity', 'target', 'file', 'title', 'what_is_wrong']


def target(s):
    """The changed file a finding is about, for splitting the clustering work."""
    m = re.search(r'[\w/\.\-]+\.(py|sql|txt|cfg|toml|ini|md|yaml|yml)', s)
    return m.group(0).lstrip('`') if m else '(other)'


def blocks(text):
    """(heading, {field: value}) for every ### heading in the document."""
    out, heading, fields, key = [], None, {}, None
    for line in text.splitlines():
        h = HEADING.match(line)
        if h:
            if heading is not None:
                out.append((heading, fields))
            heading, fields, key = h.group(1).strip(), {}, None
            continue
        if heading is None:
            continue
        f = FIELD.match(line)
        if f:
            key = f.group(1).lower()
            fields[key] = f.group(2).strip()
        elif key and line.strip():
            fields[key] = (fields[key] + ' ' + line.strip()).strip()
        elif not line.strip():
            key = None
    if heading is not None:
        out.append((heading, fields))
    return out


def parse(path):
    """Findings from one review file, plus blocks that could not be classified."""
    arm, review, part = path.stem.split('-')
    rows, odd = [], []
    for heading, fields in blocks(path.read_text()):
        if 'file' not in fields:                 # a section heading, not a finding
            continue
        m = SEVERITY.search(heading)
        if not m:
            odd.append((path.name, heading))
            continue
        title = heading[m.end():].strip()
        # A qualifier the reviewer put between the severity and the colon —
        # "(question, per Finding Floor)" or a bare "question" — is not part of
        # the title. Take it off before the separator, not after, or its closing
        # bracket survives into the title.
        if title.startswith('('):
            close = title.find(')')
            title = title[close + 1:] if close != -1 else title
        title = re.sub(r'^[^:]{0,40}:', '', title, count=1) if ':' in title[:41] else title
        title = title.lstrip(' :-—').strip()
        rows.append({'arm': arm, 'review': review, 'part': part,
                     'severity': m.group(1).capitalize(),
                     'title': title,
                     'file': fields.get('file', ''),
                     'what_is_wrong': fields.get('what is wrong', '')})
    return rows, odd


def main():
    src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    rows, odd, skipped = [], [], []
    for p in sorted(src.glob('*.md')):
        if len(p.stem.split('-')) != 3:
            continue
        got, bad = parse(p)
        rows.extend(got)
        odd.extend(bad)
        headings = sum(1 for l in p.read_text().splitlines() if l.startswith('### '))
        if headings != len(got):
            skipped.append((p.name, headings, len(got)))

    # IDs come from an order derived from the finding's own text, so the
    # identifier a clustering agent sees carries no signal about its arm.
    rows.sort(key=lambda r: (target(r['file']), r['title'], r['what_is_wrong']))
    for i, r in enumerate(rows, 1):
        r['id'] = f'F{i:04d}'
        r['target'] = target(r['file'])

    with open(dest, 'w', newline='') as fh:
        w = csv.DictWriter(fh, delimiter='\t', fieldnames=FIELDS)
        w.writeheader()
        w.writerows({k: r[k] for k in FIELDS} for r in rows)

    print(f'{len(rows)} findings -> {dest}')
    print('severity:', dict(collections.Counter(r['severity'] for r in rows)))
    print('arm     :', dict(collections.Counter(r['arm'] for r in rows)))
    print('empty File:', sum(1 for r in rows if not r['file']),
          ' empty what_is_wrong:', sum(1 for r in rows if not r['what_is_wrong']))
    print('blocks with a File: field but no severity word:', odd or 'none')
    print('headings not parsed as findings (expect section headings only):')
    for name, h, g in skipped:
        print(f'  {name}: {h} headings, {g} findings')


if __name__ == '__main__':
    main()
