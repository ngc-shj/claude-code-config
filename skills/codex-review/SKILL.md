---
name: codex-review
description: "Run a Codex diff review over the working changes, a branch, or a commit, then summarize the findings. Use this skill when: asked for a Codex review; asked for a second-opinion review from another model; asked to review uncommitted changes or a branch with codex; asked to cross-check a triangulate review against Codex."
---

# Codex Review Skill

Runs `codex review` over a chosen diff range and summarizes the findings. The
review itself runs on Codex's own model and quota, so it costs **zero Claude
tokens** — this skill is a thin orchestrator that picks the scope, invokes
`codex review`, and reports the result.

It complements the other review paths in this config:
- `triangulate` — Claude expert agents (functionality / security / testing)
- `pre-review.sh` — local Ollama pre-screening
- `codex-review` — an independent third model's perspective on the same diff

---

## Step 0: Preconditions

```bash
command -v codex >/dev/null || { echo "codex CLI not found — install it first"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
```

If `codex` is unavailable, tell the user and stop — there is no Ollama/Claude
fallback for this skill (use `triangulate` or `simplify` instead).

## Step 1: Determine Scope

Pick the `codex review` mode from the user's request:

| User instruction | Command |
|------------------|---------|
| No target / "my changes" / "working changes" (default) | `codex review --uncommitted` |
| "this branch" / "vs main" / PR-style review | `codex review --base <base>` |
| A specific commit | `codex review --commit <SHA>` |
| Focus area ("security only", "just the auth path") | append the focus as the `[PROMPT]` argument to any of the above |

Resolve the default base branch instead of hardcoding `main`:

```bash
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
BASE=${BASE:-main}
```

Confirm the scope with the user only if it is ambiguous (e.g. they say "review
this" with both uncommitted changes and unpushed commits present). Otherwise
proceed with the default.

## Step 2: Run the Review

Run the selected command and capture the output. `codex review` is
non-interactive and writes its findings to stdout.

```bash
# Examples — run exactly one, matching the scope from Step 1:
codex review --uncommitted
codex review --base "$BASE"
codex review --commit <SHA>

# With a focus prompt:
codex review --uncommitted "Focus on input validation and auth checks."
```

Do not pipe the command through `rtk` — `codex` is not a known rewrite target,
and its findings should be read verbatim.

## Step 3: Summarize and Present

Present Codex's findings to the user, grouped by severity. For each finding give:
- File and line (`path:line`)
- Severity / category as Codex reported it
- One-line summary of the issue and the suggested fix

Do not silently re-rank or drop findings. If Codex returned nothing, state
"Codex review found no issues" rather than inventing findings.

## Step 4: Cross-check with triangulate (optional)

When triangulate review artifacts exist for the same change, reconcile the two:

```bash
ls ./docs/archive/review/*-review.md ./docs/archive/review/*-code-review.md 2>/dev/null
```

For each Codex finding, classify it as:
- **Agreement** — also raised by triangulate (higher confidence, prioritize the fix)
- **Codex-only** — verify it is real before acting; a second model catching what
  Claude missed is the main value of this cross-check
- **Conflict** — Codex contradicts a triangulate conclusion; surface both to the
  user and do not override a test-verified behavior without re-verification

Report:

```
=== Codex Review Complete ===
Scope: [uncommitted | base <base> | commit <SHA>]
Findings: [total] ([n] high, [n] medium, [n] low)
Cross-check: [N agree, M Codex-only, K conflicts / no triangulate artifacts]
```

Applying fixes is out of scope for this skill — hand confirmed findings to the
user, or to `triangulate` Phase 2 / `simplify` for the actual edits.
