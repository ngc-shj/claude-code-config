---
name: agent-review
description: "Run a diff review with whatever review agent is available — a local zero-cost Ollama model, Codex, or a fresh headless Claude — then return structured findings. Use this skill when: asked for a Codex review or a second-opinion review from another model; asked for a free/local/offline review; asked to review changes without spending Claude tokens; asked for an adversarial review that challenges the design/approach; asked to review uncommitted changes, a branch, or a commit with an external reviewer; asked to cross-check a triangulate review against another model."
---

# Agent Review Skill

Reviews a diff using a **backend-agnostic** reviewer and summarizes the findings.

The essence: a *reviewer* is any agent that takes a diff and returns findings
headlessly. This skill picks an available reviewer, runs it over a chosen diff
range, and reports the result — so the review path never depends on a single CLI
being installed or on spending Claude tokens.

It complements the other review paths in this config:
- `triangulate` — Claude expert agents across three phases (functionality / security / testing)
- `pre-review.sh` — local Ollama pre-screening inside a hook
- `agent-review` — *this* skill: the same diff, reviewed by whichever backend is available (Ollama / Codex / headless Claude), defaulting to a free local one

Reference backends, in default preference order:

| Backend | Cost | Privacy | Notes |
|---------|------|---------|-------|
| `ollama` | **free** | sent to your configured local-LLM hosts (plain HTTP; see README "Multi-server load balancing" trust model) | gpt-oss:120b via `~/.claude/hooks/llm-commands.sh` (functionality / security / testing) |
| `codex` | Codex quota | sent to Codex servers | independent external model via `codex review` |
| `claude` | Claude tokens | sent to Claude servers | fresh headless context, no conversation bias; run with `--tools ""` (read-only, cannot edit/run) |

Adding a backend means adding a branch in `review-backend.sh` — the steps below
stay identical.

---

## Step 0: Preconditions

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
bash ~/.claude/skills/agent-review/review-backend.sh detect
```

`detect` prints the available backends, one per line, in preference order. If it
prints nothing, no reviewer is reachable — tell the user (e.g. "start Ollama on
localhost:11434, or install codex") and stop.

## Step 1: Determine Scope

Pick the scope from the user's request:

| User instruction | Scope argument |
|------------------|----------------|
| No target / "my changes" / "working changes" (default) | `uncommitted` |
| "this branch" / "vs main" / PR-style review | `base:<branch>` |
| A specific commit | `commit:<SHA>` |
| Focus area ("security only", "the auth path") | pass as the trailing `[focus]` argument |
| "challenge the design", "adversarial", "pressure-test the approach" | add the `--adversarial` flag |

Resolve the default base instead of hardcoding `main`:

```bash
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
BASE=${BASE:-main}
```

Confirm the scope with the user only if it is ambiguous (both uncommitted
changes and unpushed commits present). Otherwise proceed with the default.

## Step 2: Select the Backend

- If the user named a backend ("review locally", "use Ollama", "use codex"),
  use it — but first confirm it appears in the `detect` output. If not, say so
  and fall back to the top of the `detect` list.
- Otherwise use the **first** backend from `detect` (free + local wins by
  default, matching this config's local-first routing strategy).

State which backend was chosen and why before running, e.g. "No Codex installed
and Ollama is reachable → reviewing with Ollama (free, runs on your configured
local-LLM hosts)."

## Step 3: Wait or Background

A review can be slow — the `ollama` backend runs three gpt-5-class passes, and
any backend on a large diff takes minutes. Decide foreground vs background:

- If the user said `--wait`, run in the foreground.
- If the user said `--background`, run in a background task.
- Otherwise estimate the size first (`git diff --shortstat <range>`, plus
  `git status --short` for untracked work). Recommend **wait** only when it is
  clearly tiny (~1-2 files); recommend **background** in every other case,
  including the `ollama` backend and any unclear size. Then ask **once** with
  `AskUserQuestion` ("Wait for results" / "Run in background"), recommended
  option first.

For background, launch the Step 4 command with `Bash(run_in_background: true)`,
tell the user "review started in the background", and present the results when
the task notification arrives (read the task output) — do not block this turn.

## Step 4: Run the Review

```bash
# scope is one of: uncommitted | base:<branch> | commit:<SHA>
# append --adversarial to challenge the approach instead of a line-by-line pass
bash ~/.claude/skills/agent-review/review-backend.sh run <backend> <scope> ["focus text"] [--adversarial]
```

> **Data flow** depends on the backend:
> - `ollama` — the diff stays on the local/LAN Ollama host. Nothing leaves your network.
> - `codex` — the diff is sent to Codex's servers (the user's authenticated account).
> - `claude` — the diff is sent to Claude's servers and spends tokens.
>
> Do not run any external backend on a diff that stages secrets.

The `ollama` backend reviews the full diff and ignores the `focus` argument (the
underlying passes are fixed); `codex` and `claude` honor it. With
`--adversarial`, `ollama` switches to its `adversarial-review` pass and
`codex`/`claude` get an approach-challenging prompt.

## Step 5: Normalize and Present

Normalize the backend's raw output into the canonical shape in
[`schemas/review-output.schema.json`](schemas/review-output.schema.json) — this
is the one place where each backend's wording converges, so callers and the
triangulate cross-check see a uniform result. Map honestly:

- `severity` → Critical / Major / Minor (the ollama backend already emits these;
  fold any backend-specific levels in, e.g. high→Major, low→Minor).
- `verdict` → `needs-attention` if any Critical/Major finding exists, else `approve`.
- `confidence` → include **only** if the backend reported one; never fabricate it.
- Do not silently re-rank or drop findings. If the backend returned nothing (or
  "No findings"), emit `verdict: approve` with an empty `findings` array rather
  than inventing findings.

Then present a human-readable summary grouped by severity (file:line, one-line
problem + fix per finding), followed by the JSON object:

```
=== Agent Review Complete ===
Backend: [ollama | codex | claude]  Mode: [standard | adversarial]
Scope:   [uncommitted | base <base> | commit <SHA>]
Verdict: [approve | needs-attention]
Findings: [total] ([n] Critical, [n] Major, [n] Minor)
```

## Step 6: Cross-check with triangulate (optional)

When triangulate review artifacts exist for the same change, reconcile the two:

```bash
ls ./docs/archive/review/*-review.md ./docs/archive/review/*-code-review.md 2>/dev/null
```

For each finding, classify it as **Agreement** (also raised by triangulate —
higher confidence), **Backend-only** (verify before acting; catching what Claude
missed is the value of an independent reviewer), or **Conflict** (surface both;
do not override a test-verified behavior without re-verification).

Applying fixes is out of scope for this skill — hand confirmed findings to the
user, or to `triangulate` Phase 2 / `simplify` for the actual edits.
