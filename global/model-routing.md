# Model Routing Strategy

Reference detail for choosing where a task runs. Read this when deciding
whether to delegate to a sub-agent or a local LLM; the one-line summary in
`CLAUDE.md` is enough for routine work.

## Claude Opus 5 (`claude-opus-5`) — main orchestrator

- Complex architectural decisions and system design
- Plan creation and final approval
- Orchestrating sub-agents and synthesizing results
- Resolving ambiguous or conflicting findings

## Claude Sonnet 5 (`claude-sonnet-5`) — sub-agent

- Code exploration and codebase navigation
- Implementation of well-defined tasks
- Writing tests based on existing patterns
- Code review as a sub-agent

## Claude Fable 5 (`claude-fable-5`) — hardest problems only

Anthropic's most capable widely released model, for the most demanding reasoning
and long-horizon agentic work. Priced above Opus tier, so reach for it
deliberately rather than as the default upgrade — Opus 5 is the standard choice.
Claude Haiku 4.5 (`claude-haiku-4-5`) remains the fast, cheap tier.

## Local LLM (OpenAI-compatible backend or Ollama)

Hooks reach a local LLM through the `llm-utils.sh` dispatcher: `LLM_BACKEND`
pins the backend, otherwise the OpenAI-compatible backend
(`/v1/chat/completions`; llama.cpp on 8080 and/or vLLM on 8000 via
`LLM_OPENAI_PORTS`) is auto-preferred when reachable, else Ollama
(`/api/generate`). Hooks pass logical model names; each backend resolves them
to a real model (OpenAI backend via `OPENAI_MODEL_SMALL`/`OPENAI_MODEL_LARGE`,
and `ds4:flash`/`ds4:pro` for DeepSeek-V4 on vLLM).

| Logical model | Use case                                                                           |
| ------------- | ---------------------------------------------------------------------------------- |
| gpt-oss:20b   | Quick checks: lint, format validation, commit message review, simple summarization |
| gpt-oss:120b  | Code review pre-screening, security pattern detection, detailed analysis           |

## How to call a local LLM

| Method | File access | Token cost | Use when |
| --- | --- | --- | --- |
| hooks (shell + curl) | Full (grep, sed, git diff) | None | Pre-screening, automated checks |
| MCP (`mcp__ollama__ollama_chat`) | None (text passed in prompt) | Opus tokens for prompt | Ad-hoc analysis of short text |

Prefer hooks over MCP when the task needs file access or runs automatically.

## Routing rules

1. **Pre-screen with the local LLM**: `~/.claude/hooks/pre-review.sh` reads files directly and costs no Claude tokens — run it before launching Claude sub-agents.
2. **Offload mechanical checks** (syntax, formatting, naming) to gpt-oss:20b.
3. **Escalate to Claude** when local-LLM confidence is low or the task is ambiguous.
4. **Keep sensitive data local**: anything that should not leave the machine goes to the local LLM.
5. **MCP is the fallback**, for short text already in context.
