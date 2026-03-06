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
