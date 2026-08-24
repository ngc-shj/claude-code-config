#!/usr/bin/env python3
"""Compose what each bridge panellist receives — and keep the answers away from it.

The bridge asks whether today's panel agrees with the panel of 2026-08-08 on the
same 24 claims. That number means nothing if the panellist can see the earlier
verdict, so the risk here is not a malformed prompt but a well-formed prompt
pointing at the wrong file. Two files hold the same 24 claims:

  bridge-input.tsv   cluster_id and claim text     <- what the panel reads
  bridge-sample.tsv  the same ids WITH the frozen verdict attached

`briefs/render.py` already refuses to render a bridge brief from anything whose
hash is not the committed `bridge-input.tsv`, so the substitution cannot pick up
its sibling. This composer checks the finished prompt as well, by path: naming
`bridge-sample.tsv`, the new-claim panels' sheets, or anything else carrying a
verdict, a member id, a severity or an arm is refused outright.

Outputs land in `bridge/`, never in `adjudications/`: `measure.py` reads the
whole of `adjudications/` as the new-claim panel, and a bridge sheet dropped
there would be counted as a verdict on a claim it never judged.

Usage:
  round-24/compose-bridge-prompt.py --root <dir> --render
  round-24/compose-bridge-prompt.py --root <dir> --register
  round-24/compose-bridge-prompt.py --root <dir> --check
  round-24/compose-bridge-prompt.py --root <dir> --panel 1 [--verify-sent <id>]
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
CLAIMS = os.path.join(HERE, 'bridge-input.tsv')
SAMPLE = os.path.join(HERE, 'bridge-sample.tsv')
ENVELOPE = os.path.join(HERE, 'bridge-envelope.md')
REGISTRY = os.path.join(HERE, 'bridge-outputs.tsv')
RENDERER = os.path.join(HERE, 'briefs', 'render.py')
INVENTORY = os.path.join(HERE, 'cluster-inventory.tsv')
FIXTURE = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                       'rule-ablation', 'fixtures', 'F10-webhooks.diff')
SEP = '\n---\n\n'
N_PANEL = 3
N_BRIDGE = 24
RENDER_DIR = 'briefs-bridge'
BRIEF = 'adjudicate-bridge.md'
# Anything holding a verdict, a member id, a size, a severity or an arm — plus
# the new-claim pass's own inputs and sheets, which are a different question.
FORBIDDEN = ('bridge-sample.tsv', 'findings.tsv', 'clusters.tsv',
             'merge-verdicts.tsv', 'batches.tsv', 'reviews.tsv',
             'new-claims-raw.tsv', 'voided-index-05.tsv', 'cluster-inventory.tsv',
             'adjudicate-input.tsv', 'adjudications/')
# NOT a bare 'panel-': the panellist's OWN output is bridge/panel-N.tsv, so that
# token matches the one path the prompt is required to name. The new-claim
# sheets are reached by 'adjudications/', which is the directory that matters.


def die(msg):
    sys.exit(f'compose-bridge-prompt: {msg}')


def sha1(text):
    b = text.encode()
    return hashlib.sha1(b'blob %d\0' % len(b) + b).hexdigest()


def rows(path):
    with open(path, newline='') as f:
        return max(0, sum(1 for _ in f) - 1)


def render(root):
    n = rows(CLAIMS)
    if n != N_BRIDGE:
        die(f'{CLAIMS} holds {n} rows, expected {N_BRIDGE}')
    out = os.path.join(root, RENDER_DIR)
    r = subprocess.run(
        [sys.executable, RENDERER, '--out', out,
         '--cat-w', os.path.join(root, 'cat-W'),
         '--cat-n', os.path.join(root, 'cat-N'),
         '--inventory', INVENTORY, '--n-claims', str(rows(INVENTORY)),
         '--bridge-claims', CLAIMS, '--n-bridge', str(N_BRIDGE)],
        capture_output=True, text=True)
    if r.returncode:
        die(f'render.py failed:\n{r.stderr.strip()}')
    brief = os.path.join(out, BRIEF)
    if not os.path.exists(brief):
        die(f'{brief} was not produced')
    if SAMPLE in open(brief).read():
        die('the rendered bridge brief names bridge-sample.tsv')
    print(f'rendered {os.path.relpath(brief, root)} — the renderer accepted only '
          f'the committed bridge-input.tsv')
    return brief


def sample_is_refused(root):
    """The renderer must reject the verdict-bearing sibling. Exercised, not assumed."""
    out = os.path.join(root, RENDER_DIR + '-probe')
    r = subprocess.run(
        [sys.executable, RENDERER, '--out', out,
         '--cat-w', os.path.join(root, 'cat-W'),
         '--cat-n', os.path.join(root, 'cat-N'),
         '--inventory', INVENTORY, '--n-claims', str(rows(INVENTORY)),
         '--bridge-claims', SAMPLE, '--n-bridge', str(N_BRIDGE)],
        capture_output=True, text=True)
    ok = r.returncode != 0 and 'not the committed bridge input' in (
        r.stdout + r.stderr)
    if os.path.isdir(out):
        for f in os.listdir(out):
            os.remove(os.path.join(out, f))
        os.rmdir(out)
    return ok


def register(root):
    if os.path.exists(REGISTRY):
        die('bridge-outputs.tsv exists; the panel assignment is not rewritten in '
            'passing')
    rows_ = [(str(i), os.path.join(root, 'bridge', f'panel-{i}.tsv'))
             for i in range(1, N_PANEL + 1)]
    for _, p in rows_:
        if 'adjudications' in p:
            die('a bridge output must not land in adjudications/')
        if os.path.exists(p):
            die(f'{p} already exists, so this is not a reservation')
    os.makedirs(os.path.join(root, 'bridge'), exist_ok=True)
    with open(REGISTRY, 'w') as f:
        f.write('panel\toutput\n')
        for r in rows_:
            f.write('\t'.join(r) + '\n')
    print(f'wrote round-24/bridge-outputs.tsv — {len(rows_)} reservations under '
          f'bridge/, none existing')


def registry():
    if not os.path.exists(REGISTRY):
        die('bridge-outputs.tsv is missing — run --register first')
    r = list(csv.DictReader(open(REGISTRY, newline=''), delimiter='\t'))
    if len(r) != N_PANEL:
        die(f'{len(r)} panellists registered, expected {N_PANEL}')
    if len({x['output'] for x in r}) != N_PANEL:
        die('panellists share an output path')
    if any('adjudications' in x['output'] for x in r):
        die('a registered bridge output lands in adjudications/')
    return r


def compose(root, panel):
    brief_path = os.path.join(root, RENDER_DIR, BRIEF)
    if not os.path.exists(brief_path):
        die(f'{brief_path} is missing — run --render first')
    brief = open(brief_path).read()
    envelope = open(ENVELOPE).read()
    if SEP in brief or SEP in envelope:
        die('the separator already occurs inside the brief or the envelope')
    if re.search(r'\{[A-Z_]+\}', brief):
        die('the rendered brief still carries a slot')

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
        die(f'the prompt names a file that would carry the answer or the wrong '
            f'question: {named}')
    if CLAIMS not in prompt or FIXTURE not in prompt:
        die('the prompt does not name the claim-only bridge input and the fixture')
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
        render(a.root)
        return
    if a.register:
        return register(a.root)

    if a.check:
        reg = registry()
        prompts = {r['panel']: compose(a.root, r['panel'])[0] for r in reg}
        if len({p.split(SEP)[0] for p in prompts.values()}) != 1:
            die('the three panellists would not receive the same brief')
        absent = [r['output'] for r in reg if not os.path.exists(r['output'])]
        print(f'{len(reg)} panellists compose cleanly; one brief, one claim-only '
              f'input; only the output path differs')
        print(f'  no slot survives, exactly one separator, no forbidden file named')
        print(f'  outputs under bridge/, reserved and absent: {len(absent)} of '
              f'{len(reg)}')
        print(f'  renderer refuses bridge-sample.tsv: '
              f'{"yes" if sample_is_refused(a.root) else "NO"}')
        for panel, p in sorted(prompts.items()):
            print(f'  panel {panel} composed sha1 {sha1(p)}')
        return

    if not a.panel:
        die('need --panel, --render, --register or --check')
    prompt, row = compose(a.root, a.panel)
    if a.verify_sent:
        got = sent_prompt(a.verify_sent)
        if got == prompt:
            print(f"{a.verify_sent}  bridge panel {row['panel']}  RECEIVED EXACTLY "
                  f"THE COMPOSED PROMPT  {sha1(prompt)}")
            return
        die(f'{a.verify_sent} received a prompt that is not the composed one\n'
            f'  composed {sha1(prompt)} ({len(prompt)} chars)\n'
            f'  received {sha1(got)} ({len(got)} chars)')
    print(prompt)
    print(f"\n--- composed sha1 {sha1(prompt)}  output {row['output']}",
          file=sys.stderr)


if __name__ == '__main__':
    main()
