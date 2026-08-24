#!/usr/bin/env python3
"""Compose what each of the three adjudicators receives, and refuse to leak.

The instrument is the repository's frozen `adjudication-brief.md`, rendered by
round 24's `briefs/render.py` — the same renderer the review and clustering
briefs went through, so `{N}` is checked against the claims file's real row count
rather than typed in. The envelope adds the output path and the delivery rules.

All three panellists receive the **same** claim-only input and the **same**
brief; only the output path differs. That is what makes their agreement
measurable rather than an artefact of who saw what.

What must not reach an adjudicator is checked here rather than assumed: a
verdict from the frozen inventory, a member id, a cluster's size, a severity, an
arm, or any finding text. The check is by path — the prompt may name the
claim-only input and the fixture, and nothing else that carries those columns.

`--register` reserves the three output paths and refuses if any exists. If the
claims file is empty there is no adjudication pass at all: nothing is registered
and no agent is composed, per the standing rule that a pass with nothing to judge
is not run.

Usage:
  round-24/compose-adjudicate-prompt.py --root <dir> --render
  round-24/compose-adjudicate-prompt.py --root <dir> --register
  round-24/compose-adjudicate-prompt.py --root <dir> --check
  round-24/compose-adjudicate-prompt.py --root <dir> --panel 1
  round-24/compose-adjudicate-prompt.py --root <dir> --panel 1 --verify-sent <id>
"""
import argparse
import csv
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RP = os.path.dirname(HERE)
CLAIMS = os.path.join(HERE, 'adjudicate-input.tsv')
ENVELOPE = os.path.join(HERE, 'adjudicate-envelope.md')
REGISTRY = os.path.join(HERE, 'adjudicate-outputs.tsv')
RENDERER = os.path.join(HERE, 'briefs', 'render.py')
INVENTORY = os.path.join(HERE, 'cluster-inventory.tsv')
FIXTURE = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                       'rule-ablation', 'fixtures', 'F10-webhooks.diff')
SEP = '\n---\n\n'
N_PANEL = 3
RENDER_DIR = 'briefs-adjudicate'
BRIEF = 'adjudicate-new.md'
# Files that carry a verdict, a member id, a size, a severity or an arm. None of
# them may be named in an adjudicator's prompt.
FORBIDDEN = ('findings.tsv', 'clusters.tsv', 'bridge-sample.tsv',
             'merge-verdicts.tsv', 'batches.tsv', 'reviews.tsv',
             'new-claims-raw.tsv', 'voided-index-05.tsv')


def die(msg):
    sys.exit(f'compose-adjudicate-prompt: {msg}')


def sha1(text):
    b = text.encode()
    return hashlib.sha1(b'blob %d\0' % len(b) + b).hexdigest()


def n_claims():
    with open(CLAIMS, newline='') as f:
        return max(0, sum(1 for _ in f) - 1)


def render(root):
    """Render the frozen adjudication brief through round 24's renderer."""
    n = n_claims()
    if n == 0:
        die('the claims file is empty — there is no adjudication pass to render')
    out = os.path.join(root, RENDER_DIR)
    r = subprocess.run(
        [sys.executable, RENDERER, '--out', out,
         '--cat-w', os.path.join(root, 'cat-W'),
         '--cat-n', os.path.join(root, 'cat-N'),
         '--inventory', INVENTORY, '--n-claims',
         str(max(0, sum(1 for _ in open(INVENTORY)) - 1)),
         '--new-claims', CLAIMS, '--n-new', str(n)],
        capture_output=True, text=True)
    if r.returncode:
        die(f'render.py failed:\n{r.stderr.strip()}')
    brief = os.path.join(out, BRIEF)
    if not os.path.exists(brief):
        die(f'{brief} was not produced')
    print(f'rendered {os.path.relpath(brief, root)} '
          f'(row count checked against the claims file by the renderer)')
    return brief


def register(root):
    if os.path.exists(REGISTRY):
        die('adjudicate-outputs.tsv exists; the panel assignment is not rewritten '
            'in passing')
    if n_claims() == 0:
        print('the claims file is empty: no adjudication pass, nothing registered')
        return
    rows = [(str(i), os.path.join(root, 'adjudications', f'panel-{i}.tsv'))
            for i in range(1, N_PANEL + 1)]
    for _, p in rows:
        if os.path.exists(p):
            die(f'{p} already exists, so this is not a reservation')
    os.makedirs(os.path.join(root, 'adjudications'), exist_ok=True)
    with open(REGISTRY, 'w') as f:
        f.write('panel\toutput\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    print(f'wrote round-24/adjudicate-outputs.tsv — {len(rows)} reservations, '
          f'none of their outputs existing')


def registry():
    if not os.path.exists(REGISTRY):
        die('adjudicate-outputs.tsv is missing — run --register first')
    rows = list(csv.DictReader(open(REGISTRY, newline=''), delimiter='\t'))
    if len(rows) != N_PANEL:
        die(f'{len(rows)} panellists registered, expected {N_PANEL}')
    if len({r['output'] for r in rows}) != N_PANEL:
        die('panellists share an output path')
    return rows


def compose(root, panel):
    brief_path = os.path.join(root, RENDER_DIR, BRIEF)
    if not os.path.exists(brief_path):
        die(f'{brief_path} is missing — run --render first')
    brief = open(brief_path).read()
    envelope = open(ENVELOPE).read()
    if SEP in brief or SEP in envelope:
        die('the separator already occurs inside the brief or the envelope')
    if re.search(r'\{[A-Z_]+\}', brief):
        die(f'the rendered brief still carries a slot: '
            f'{re.findall(r"{[A-Z_]+}", brief)[:3]}')

    row = next((r for r in registry() if r['panel'] == str(panel)), None)
    if row is None:
        die(f'panel {panel} is not registered')
    if envelope.count('{{OUTPUT_PATH}}') != 1:
        die('the envelope must name {{OUTPUT_PATH}} exactly once')
    filled = envelope.replace('{{OUTPUT_PATH}}', row['output'])
    if re.search(r'\{\{[A-Z_]+\}\}', filled):
        die('an envelope slot survived substitution')

    prompt = brief + SEP + filled
    if prompt.count(SEP) != 1:
        die('the prompt is not exactly brief + separator + envelope')
    named = [f for f in FORBIDDEN if f in prompt]
    if named:
        die(f'the prompt names a file carrying verdicts, members, sizes, '
            f'severities or arms: {named}')
    if CLAIMS not in prompt or FIXTURE not in prompt:
        die('the prompt does not name the claim-only input and the fixture')
    return prompt, row


def sent_prompt(agent_id):
    root = os.path.expanduser('~/.claude/projects/'
                              '-home-noguchi-ghq-github-com-ngc-shj-claude-code-config')
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
    ap.add_argument('--render', action='store_true')
    ap.add_argument('--register', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--panel')
    ap.add_argument('--verify-sent', metavar='AGENT_ID')
    a = ap.parse_args()

    if a.render:
        return render(a.root) and None
    if a.register:
        return register(a.root)

    if a.check:
        if n_claims() == 0:
            print('the claims file is empty: no adjudication pass, nothing to check')
            return
        rows = registry()
        prompts = {}
        for r in rows:
            p, _ = compose(a.root, r['panel'])
            prompts[r['panel']] = p
        bodies = {p.split(SEP)[0] for p in prompts.values()}
        if len(bodies) != 1:
            die('the three panellists would not receive the same brief')
        absent = [r['output'] for r in rows if not os.path.exists(r['output'])]
        print(f'{len(rows)} panellists compose cleanly; all three share one brief '
              f'and one claim-only input; only the output path differs')
        print(f'  no slot survives, exactly one separator, no forbidden file named')
        print(f'  outputs reserved and absent: {len(absent)} of {len(rows)}')
        for panel, p in sorted(prompts.items()):
            print(f'  panel {panel} composed sha1 {sha1(p)}')
        return

    if not a.panel:
        die('need --panel, --render, --register or --check')
    prompt, row = compose(a.root, a.panel)
    if a.verify_sent:
        got = sent_prompt(a.verify_sent)
        if got == prompt:
            print(f"{a.verify_sent}  panel {row['panel']}  RECEIVED EXACTLY THE "
                  f"COMPOSED PROMPT  {sha1(prompt)}")
            return
        die(f'{a.verify_sent} received a prompt that is not the composed one\n'
            f'  composed {sha1(prompt)} ({len(prompt)} chars)\n'
            f'  received {sha1(got)} ({len(got)} chars)')
    print(prompt)
    print(f"\n--- composed sha1 {sha1(prompt)}  output {row['output']}",
          file=sys.stderr)


if __name__ == '__main__':
    main()
