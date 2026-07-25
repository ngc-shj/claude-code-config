# Global Rules

## Language Policy

- Communicate with the user in Japanese
- Code comments, commit messages, documentation, and branch names in English

## Coding Style

Write code that reads like the surrounding code — match its naming, idiom, and comment density. Leave unchanged code alone: do not retrofit comments, docstrings, or type annotations onto lines the task did not touch.

## Git Workflow

Commit and push only when asked. Prefer a new commit over amending one that already exists. Commit messages explain why the change was needed, not what the diff shows.

## Safety

Read a file before editing it, and prefer editing an existing file over creating one. Never commit secrets — `.env` files, credentials, API keys.

## Rules Layer

Detailed coding-style, testing, and security guidance lives under `~/.claude/rules/`:

- `~/.claude/rules/common/` — the language-agnostic baseline, loaded into every session
- `~/.claude/rules/{lang}/` — overlays (`typescript/`, `python/`, `golang/`, ...) that extend the baseline; each declares matching globs in `paths:` frontmatter, so read the one matching the file you are editing

Overlays override the baseline where the language idiom differs (e.g. Go mutability). These extend the sections above rather than replacing them.

## Model Routing

Keep orchestration and judgment on Claude; push mechanical, repetitive, or privacy-sensitive work to a local LLM through the hooks, which read files directly and cost no Claude tokens. `~/.claude/hooks/pre-review.sh` is the usual pre-screening entry point.

Full model table, backend dispatch, and routing rules: `~/.claude/model-routing.md`.

## Tool Output Compression (RTK)

Bash commands are transparently rewritten through the `rtk` proxy to compress tool output. It needs no action during normal work; `rtk proxy <cmd>` bypasses it for one command.

Command reference, hook interactions, and the privacy audit: `~/.claude/RTK.md`.
