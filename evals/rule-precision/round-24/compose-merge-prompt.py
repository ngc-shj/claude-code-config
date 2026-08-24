#!/usr/bin/env python3
"""Compose what the merge agent receives: rendered merge brief + merge envelope.

Third and last of the composers, same contract as the review and clustering ones.
The instrument is round 22's `brief-merge.md`; `briefs/merge.template.md` is that
file with five runtime slots and nothing else changed — four of them the paths
and the clustering agent count, the fifth the reply rule.

The reply rule is a slot because round 22's version ends "run `wc -l` … reply
with `DONE <n>`", and that count is a count of new claims. It decides nothing
about the merge, changes no input and changes no output row; it is a delivery
acknowledgement, and this round's acknowledgement is a bare DONE. Substituting it
leaves the merge criteria, the inputs and the output TSV identical.

Paths come from `merge-outputs.tsv`, so what the agent is told to read and where
it is told to write are facts on disk rather than arguments typed at a prompt.

Usage:
  round-24/compose-merge-prompt.py --root <dir>
  round-24/compose-merge-prompt.py --root <dir> --check
  round-24/compose-merge-prompt.py --root <dir> --verify-sent <agent_id>
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
TEMPLATE = os.path.join(HERE, 'briefs', 'merge.template.md')
ENVELOPE = os.path.join(HERE, 'merge-envelope.md')
MANIFEST = os.path.join(HERE, 'merge-outputs.tsv')
FIXTURE = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                       'rule-ablation', 'fixtures', 'F10-webhooks.diff')
CLUSTER_REGISTRY = os.path.join(HERE, 'cluster-outputs.tsv')
SEP = '\n---\n\n'
BRIEF_SLOT = re.compile(r'\{[A-Z_]+\}')
ENV_SLOT = re.compile(r'\{\{[A-Z_]+\}\}')
REPLY_RULE = ('After writing the file successfully, reply with the single word '
              'DONE. Do not include any count or claim information.')
PROJECT = '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config'


def die(msg):
    sys.exit(f'compose-merge-prompt: {msg}')


def sha1(text):
    b = text.encode()
    return hashlib.sha1(b'blob %d\0' % len(b) + b).hexdigest()


def manifest():
    rows = list(csv.DictReader(open(MANIFEST, newline=''), delimiter='\t'))
    if len(rows) != 1:
        die(f'{len(rows)} merge rows in the manifest, expected 1')
    return rows[0]


def compose():
    row = manifest()
    for key in ('input_new_claims', 'input_existing_claims'):
        if not os.path.exists(row[key]):
            die(f'{row[key]} does not exist — generate the merge inputs first')
    n_agents = len(list(csv.DictReader(open(CLUSTER_REGISTRY, newline=''),
                                       delimiter='\t')))

    brief = open(TEMPLATE).read()
    envelope = open(ENVELOPE).read()
    if SEP in brief or SEP in envelope:
        die('the separator already occurs inside the template or the envelope')

    values = {'{NEW_CLAIMS}': row['input_new_claims'],
              '{EXISTING_CLAIMS}': row['input_existing_claims'],
              '{DIFF}': FIXTURE,
              '{N_CLUSTER_AGENTS}': str(n_agents),
              '{REPLY_RULE}': REPLY_RULE}
    want = {s: brief.count(s) for s in values}
    missing = [s for s, n in want.items() if n < 1]
    if missing:
        die(f'the template never names {missing}')
    rendered = brief
    for slot, value in values.items():
        rendered = rendered.replace(slot, value)
    if BRIEF_SLOT.search(rendered):
        die(f'a slot survived substitution: {BRIEF_SLOT.findall(rendered)[:3]}')

    if envelope.count('{{OUTPUT_PATH}}') != 1:
        die('the envelope must name {{OUTPUT_PATH}} exactly once')
    filled = envelope.replace('{{OUTPUT_PATH}}', row['output'])
    if ENV_SLOT.search(filled):
        die('an envelope slot survived substitution')

    # The brief must not ASK for a line count. The envelope names `wc -l` too,
    # to forbid it, so this looks at the rendered brief rather than the whole
    # prompt — a substring test over both cannot tell an instruction from its
    # prohibition.
    if 'wc -l' in rendered:
        die('the rendered brief still asks for a line count')
    if 'wc -l' not in filled:
        die('the envelope no longer forbids a line count')

    prompt = rendered + SEP + filled
    # Nothing may be added by hand: the prompt is exactly these three pieces.
    if prompt != rendered + SEP + filled or prompt.count(SEP) != 1:
        die('the prompt is not exactly template + separator + envelope')
    return prompt, row


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
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--verify-sent', metavar='AGENT_ID')
    a = ap.parse_args()
    prompt, row = compose()

    if a.check:
        base = open(TEMPLATE).read()
        print(f'composes cleanly; no slot survives; exactly one separator; '
              f'no line-count instruction')
        print(f'  template slots  {sorted(set(BRIEF_SLOT.findall(base)))}')
        print(f'  output reserved {"absent" if not os.path.exists(row["output"]) else "PRESENT"}')
        print(f'  composed sha1   {sha1(prompt)}')
        return

    if a.verify_sent:
        got = sent_prompt(a.verify_sent)
        if got == prompt:
            print(f'{a.verify_sent}  merge  RECEIVED EXACTLY THE COMPOSED PROMPT  '
                  f'{sha1(prompt)}')
            return
        die(f'{a.verify_sent} received a prompt that is not the composed one\n'
            f'  composed {sha1(prompt)} ({len(prompt)} chars)\n'
            f'  received {sha1(got)} ({len(got)} chars)')

    print(prompt)
    print(f'\n--- composed sha1 {sha1(prompt)}  output {row["output"]}',
          file=sys.stderr)


if __name__ == '__main__':
    main()
