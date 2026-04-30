# Global Rules

## Language Policy

- Communicate with the user in Japanese
- Code comments in English
- Commit messages in English
- Documentation (README, etc.) in English
- Git branch names in English

## Coding Style

- Keep code simple and readable
- Follow existing project conventions
- Do not add unnecessary comments, docstrings, or type annotations to unchanged code
- Only add comments where the logic is not self-evident

## Git Workflow

- Do not commit unless explicitly asked
- Do not push unless explicitly asked
- Write concise commit messages focusing on "why", not "what"
- Prefer creating new commits over amending existing ones

## Safety

- Never commit files containing secrets (.env, credentials, API keys)
- Read files before editing them
- Prefer editing existing files over creating new ones

## Rules Layer

Detailed coding-style, testing, and security guidance lives under `~/.claude/rules/`:

- `~/.claude/rules/common/` — language-agnostic baseline (always applicable)
- `~/.claude/rules/{lang}/` — language overlays (`typescript/`, `python/`, `golang/`, ...) that extend the baseline; each file declares matching globs in `paths:` frontmatter

When editing or reviewing a source file, consult `common/` plus the overlay whose `paths:` matches the file. Language overlays override common rules where idioms differ (e.g. Go mutability). These rules extend the Coding Style / Git Workflow / Safety sections above — they do not replace them.

## Model Routing Strategy

Use the appropriate model for each task based on complexity, cost, and latency:

### Claude Opus 4.6 (Main Orchestrator)

- Complex architectural decisions and system design
- Plan creation and final approval
- Orchestrating sub-agents and synthesizing results
- Resolving ambiguous or conflicting findings

### Claude Sonnet 4.6 (Sub-agent)

- Code exploration and codebase navigation
- Implementation of well-defined tasks
- Writing tests based on existing patterns
- Code review as a sub-agent

### Local LLM via Ollama

Available models and their use cases:

| Model           | Use case                                                                           |
| --------------- | ---------------------------------------------------------------------------------- |
| gpt-oss:20b     | Quick checks: lint, format validation, commit message review, simple summarization |
| gpt-oss:120b    | Code review pre-screening, security pattern detection, detailed analysis           |
| deepseek-r1:70b | Complex reasoning tasks, mathematical/logical verification                         |
| deepseek-r1:8b  | Fast classification, simple Q&A, tagging                                           |

### How to call local LLM

| Method | File access | Token cost | Use when |
| --- | --- | --- | --- |
| hooks (shell + curl) | Full (grep, sed, git diff) | None | Pre-screening, automated checks |
| MCP (`mcp__ollama__ollama_chat`) | None (text passed in prompt) | Opus tokens for prompt | Ad-hoc analysis of short text |

Prefer hooks over MCP when the task requires file access or runs automatically.

### Routing Rules

1. **Pre-screening with local LLM**: Use `~/.claude/hooks/pre-review.sh` before launching Claude sub-agents (reads files directly, no Claude tokens consumed)
2. **Offload repetitive checks**: Use gpt-oss:20b for mechanical validation (syntax, formatting, naming conventions)
3. **Escalation**: If local LLM confidence is low or the task is ambiguous, escalate to Claude
4. **Privacy-sensitive tasks**: Use local LLM for tasks involving sensitive data that should not leave the machine
5. **MCP fallback**: Use `mcp__ollama__ollama_chat` or `mcp__ollama__ollama_generate` only when passing short text that is already in context

## Tool Output Compression (RTK)

[RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk) is a CLI proxy registered as the first `PreToolUse` Bash hook in `settings.json`. It transparently rewrites common dev commands (`git status` -> `rtk git status`, `pytest` -> `rtk pytest`, etc.) so Claude sees filtered/compressed output instead of raw stdout. Reported savings: 60-90% on git/test/log-heavy operations.

Notes specific to this repo:
- The rewrite happens BEFORE the `block-*` deny hooks run, so Claude sees `rtk <verb>...` in `tool_input.command`. The R31 destructive-op regexes match against the substring (`git push --force`, `docker volume rm`, etc.), which is preserved across the rewrite — destructive blocks still fire correctly.
- `commit-msg-check.sh` was updated to accept the `rtk ` prefix on `git commit ...` so Ollama-based commit message review still runs after the rewrite.
- Override the rewrite for a single command with `rtk proxy <cmd>` (raw passthrough), or disable globally by removing the hook entry from `~/.claude/settings.local.json`.

### Privacy posture

Audited 2026-04-30 against rtk 0.38.0. Full report: [`docs/archive/audit/rtk-privacy-posture-2026-04-30.md`](./docs/archive/audit/rtk-privacy-posture-2026-04-30.md).

Headline findings:
- **Network exfiltration: NEGLIGIBLE.** Telemetry is OFF by default, and the v0.38.0 binary contains no collection endpoint (literal string in binary: `no telemetry endpoint configured`). Static-string scan turned up no posthog/sentry/datadog/amplitude markers — only docs URLs.
- **Local plaintext command history**: every command's full text + arguments + absolute project path is logged to `~/.local/share/rtk/history.db` (SQLite). Default retention was 90 days; **this repo ships with retention shortened to 14 days**.
- **Threat-model equivalent**: same shape as `~/.bash_history`. Disk encryption + non-shared user account remain the operative controls. Avoid passing secrets as CLI args (use env vars or `--from-file` instead).

Re-audit triggers (run on every `brew upgrade rtk`):
- `strings $(which rtk) | grep -E '^https?://' | grep -v 'github.com\|homebrew'` should remain empty.
- `rtk telemetry status` should show `enabled: no` and `device hash: (no salt file)` unless intentionally enabled.
- If a new endpoint URL or unfamiliar SaaS marker appears, evaluate before continuing use.

Defense-in-depth: export `RTK_TELEMETRY_DISABLED=1` in `~/.bashrc` to override any accidental opt-in regardless of config. Periodic purge: `rtk telemetry forget`.

@RTK.md
