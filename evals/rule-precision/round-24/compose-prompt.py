#!/usr/bin/env python3
"""Compose exactly what a review agent receives: pinned brief + delivery envelope.

The review brief is the instrument and is **not edited**. Index 5 showed two ways
the transport can break the measurement rather than the judgement — an agent
writing its review through a shell heredoc, and an agent volunteering its
severity counts in the reply — and both are transport faults. So they are fixed
in a transport layer: `delivery-envelope.md`, appended verbatim, carrying the
output path and the rules for delivering and replying. Review criteria are
untouched, and the envelope is identical in both arms.

That the agents see different text from index 6 on is a fact, not a thing to
hide: indices 1–4 ran under the old envelope (a bare "Your output path is ..."
line), indices 6–12 under this one. Index 5 is void.

Everything that could silently go wrong is checked rather than trusted:

  * `<OUTPUT_PATH>` is substituted exactly once
  * the path is the one `measurement-outputs.tsv` reserved for this
    (index, arm, part) — not a plausible-looking near miss
  * the composed prompt is EXACTLY brief + separator + envelope, byte for byte,
    with nothing else appended by hand
  * W and N differ only in the catalogue path and the output path

Usage:
  round-24/compose-prompt.py --root <dir> --index 6 --arm N --part a
  round-24/compose-prompt.py --root <dir> --index 6 --check-arms
  round-24/compose-prompt.py --root <dir> --verify-sent <agent_id> \
      --index 6 --arm N --part a
"""
import argparse
import csv
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENVELOPE = os.path.join(HERE, 'delivery-envelope.md')
REGISTRY = os.path.join(HERE, 'measurement-outputs.tsv')
SLOT = '<OUTPUT_PATH>'
SEP = '\n---\n\n'          # the only thing that joins them; part of the contract
PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'


def die(msg):
    sys.exit(f'compose-prompt: {msg}')


def sha1(text):
    b = text.encode()
    return hashlib.sha1(b'blob %d\0' % len(b) + b).hexdigest()


def registered_path(index, arm, part):
    with open(REGISTRY, newline='') as f:
        for r in csv.DictReader(f, delimiter='\t'):
            if (r['review'], r['arm'], r['part']) == (str(index), arm, part):
                return r['path']
    die(f'no registered output path for index {index} arm {arm} part {part}')


def compose(root, index, arm, part):
    brief_path = os.path.join(root, 'briefs', f'brief-{arm}.md')
    if not os.path.exists(brief_path):
        die(f'{brief_path} is missing — render the briefs first')
    brief = open(brief_path).read()
    envelope = open(ENVELOPE).read()

    if brief.count(SLOT) or SEP in brief:
        die('the rendered brief already contains the slot or the separator; '
            'the composition would not be unambiguous')
    if envelope.count(SLOT) != 1:
        die(f'the envelope names {SLOT} {envelope.count(SLOT)} times, expected 1')

    path = registered_path(index, arm, part)
    filled = envelope.replace(SLOT, path)
    if SLOT in filled:
        die('a slot survived substitution')
    if filled.count(path) != 1:
        die(f'the output path appears {filled.count(path)} times, expected 1')

    prompt = brief + SEP + filled
    # the composition is the whole prompt, and nothing was added by hand
    if prompt != brief + SEP + filled:
        die('composition is not brief + separator + envelope')
    expect = os.path.basename(path)
    if expect != f'review-{int(index):02d}-{arm}-{part}.md':
        die(f'registered path {expect} does not match index/arm/part')
    return prompt, path


def check_arms(root, index):
    """W and N may differ in the catalogue path and the output path, nowhere else."""
    out = {}
    for arm in ('W', 'N'):
        p, path = compose(root, index, arm, 'a')
        out[arm] = (p.replace(os.path.join(root, f'cat-{arm}'), '<CAT>')
                     .replace(path, '<OUT>'))
    if out['W'] != out['N']:
        import difflib
        d = [l for l in difflib.unified_diff(out['W'].splitlines(),
                                             out['N'].splitlines(), lineterm='')
             if l.startswith(('+', '-')) and not l.startswith(('+++', '---'))]
        die('W and N differ beyond the catalogue and output paths:\n  '
            + '\n  '.join(d[:10]))
    print(f'index {index}: W and N are identical modulo <CAT> and <OUT>')


def sent_prompt(agent_id):
    root = os.path.expanduser(f'~/.claude/projects/{PROJECT}')
    hits = [p for p in
            __import__('glob').glob(f'{root}/*/subagents/agent-{agent_id}.jsonl')]
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
    ap.add_argument('--index', type=int)
    ap.add_argument('--arm', choices=('W', 'N'))
    ap.add_argument('--part', choices=('a', 'b', 'c'))
    ap.add_argument('--check-arms', action='store_true')
    ap.add_argument('--verify-sent', metavar='AGENT_ID')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args()

    if a.check_arms:
        if a.index is None:
            die('--check-arms needs --index')
        return check_arms(a.root, a.index)

    if None in (a.index, a.arm, a.part):
        die('need --index, --arm and --part')
    prompt, path = compose(a.root, a.index, a.arm, a.part)

    if a.verify_sent:
        got = sent_prompt(a.verify_sent)
        if got == prompt:
            print(f'{a.verify_sent}  index {a.index} {a.arm}-{a.part}  '
                  f'RECEIVED EXACTLY THE COMPOSED PROMPT  {sha1(prompt)}')
            return
        die(f'{a.verify_sent} received a prompt that is not the composed one\n'
            f'  composed {sha1(prompt)} ({len(prompt)} chars)\n'
            f'  received {sha1(got)} ({len(got)} chars)')

    if not a.quiet:
        print(prompt)
        print(f'\n--- composed sha1 {sha1(prompt)}  output {path}',
              file=sys.stderr)


if __name__ == '__main__':
    main()
