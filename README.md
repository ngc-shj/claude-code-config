# claude-code

Safe default settings for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with agentic multi-model architecture.

## Repository structure

```text
claude-code/
├── .editorconfig                  # Editor formatting rules
├── .gitignore                     # Ignore .DS_Store, *.bak, etc.
├── LICENSE                        # MIT License
├── README.md                      # This file
├── CLAUDE.md                      # Global behavior rules + model routing strategy
├── settings.json                  # Permissions + hooks configuration
├── install.sh                     # Installer script
├── hooks/
│   ├── block-sensitive-files.sh   # Block edits to secrets/lock files
│   ├── commit-msg-check.sh       # Commit message validation via local LLM
│   ├── pre-review.sh             # Code/plan pre-screening via local LLM
│   ├── notify.sh                 # Desktop notifications (macOS)
│   └── stop-notify.sh            # Task completion notifications
└── skills/
    └── multi-agent-review/
        └── SKILL.md              # Multi-agent review workflow
```

## Agentic architecture

```text
┌──────────────────────────────────────────────────┐
│  Claude Opus 4.6 (Main Orchestrator)             │
│  Complex design, planning, final decisions       │
└──┬────────────────┬─────────────────┬────────────┘
   │                │                 │
   ▼                ▼                 ▼
┌────────┐  ┌─────────────┐  ┌──────────────────┐
│Sonnet  │  │gpt-oss:120b │  │gpt-oss:20b       │
│4.6     │  │(Ollama)     │  │(Ollama)          │
│        │  │             │  │                  │
│Explore │  │Code review  │  │Commit msg check  │
│Implement│ │pre-screening│  │Quick validation  │
│Test    │  │Security scan│  │Summarization     │
└────────┘  └─────────────┘  └──────────────────┘
```

### Model routing

| Model | Role | Use case |
| --- | --- | --- |
| Claude Opus 4.6 | Main orchestrator | Architecture, planning, final decisions |
| Claude Sonnet 4.6 | Sub-agent | Exploration, implementation, testing |
| gpt-oss:120b | Local pre-screening | Code review, security analysis (before Claude) |
| gpt-oss:20b | Local quick checks | Commit messages, lint, format, classification |
| deepseek-r1:70b | Local reasoning | Complex logical verification |
| deepseek-r1:8b | Local fast tasks | Simple Q&A, tagging |

Local LLMs run via [Ollama](https://ollama.com/) — **no API cost, no data leaves your machine**.
Called via hooks (shell + curl) for file-aware tasks, or MCP for ad-hoc text analysis.

## Permission design

Commands are categorized into three levels:

- **deny** — Blocked unconditionally (destructive, exfiltration, irreversible)
- **allow** — Auto-approved (read-only, local-only, safe for development)
- **ask** — Requires user confirmation each time (side effects but needed for development)

### deny (examples)

- `rm -rf`, `sudo`, `chmod 777`, `dd`
- `git push --force`, `git reset --hard`, `git clean -fd`
- `curl -X POST/PUT/DELETE`, `curl --data`
- `docker system prune`, `docker push`, `docker login`
- `npm publish`, `eval`, `source`, `xargs`

### allow (examples)

- Read-only: `ls`, `cat`, `grep`, `find`, `head`, `tail`, `wc`, `diff`
- Git (safe): `status`, `log`, `diff`, `add`, `commit`, `checkout`, `switch`, `fetch`, `pull`
- Docker (safe): `ps`, `images`, `logs`, `inspect`, `build`, `compose up`, `exec`, `run`
- npm: `list`, `run`, `test`, `install`, `ci`

### ask (examples)

- `git push`, `rm`, `mv`, `kill`
- `docker stop`, `docker rm`, `docker rmi`, `docker compose down`
- `gh pr merge`, `gh pr close`

## Hooks

### block-sensitive-files.sh (PreToolUse)

Blocks Edit/Write/MultiEdit operations on:

- Environment files: `.env`, `.env.local`, `.env.production`, etc.
- Credential files: `credentials.json`, `secrets.yaml`, `*.pem`, `*.key`
- Lock files: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, etc.
- Git internals: `.git/*`

### commit-msg-check.sh (PreToolUse)

Validates commit messages using local LLM (`gpt-oss:20b` via Ollama):

- Checks for conventional commit format (feat/fix/refactor/docs/test/chore)
- Verifies the message is in English and concise
- Provides improvement suggestions if needed
- Gracefully skips if Ollama is unavailable

### pre-review.sh (Utility — called by skills)

Pre-screening for code review and plan review using local LLM (`gpt-oss:120b` via Ollama):

```bash
# Review plan
PLAN_FILE=path/to/plan.md bash ~/.claude/hooks/pre-review.sh plan

# Review code changes
bash ~/.claude/hooks/pre-review.sh code
```

- Reads files directly via shell (git diff, cat) — no Claude tokens consumed
- Configurable via `OLLAMA_HOST` and `REVIEW_MODEL` environment variables
- Gracefully skips if Ollama is unavailable

### notify.sh (Notification)

macOS desktop notifications when:

- **permission_prompt**: Claude needs permission approval — plays sound + notification
- **idle_prompt**: Claude is waiting for input — plays sound + notification

> Linux users: replace `afplay`/`osascript` with `paplay`/`notify-send`.

### stop-notify.sh (Stop)

Notifies when Claude finishes a response:

- **end_turn**: Task complete — plays Glass sound + notification
- **max_tokens**: Token limit reached — plays alert sound + warning notification

## Skills

### multi-agent-review

A development workflow skill with three phases:

1. **Plan creation & review** — Local LLM pre-screening + 3 Claude expert agents
2. **Coding** — Implementation with deviation tracking
3. **Code review** — Local LLM pre-screening + 3 Claude expert agents

Each review phase uses local LLM (`gpt-oss:120b`) to catch obvious issues before launching Claude sub-agents, reducing API cost while maintaining quality.

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Ollama](https://ollama.com/) installed (optional, for local LLM features)

### Setup

```bash
git clone https://github.com/ngc-shj/claude-code.git
cd claude-code
bash install.sh
```

Existing files are backed up with `.bak` extension before overwriting.

### Install local models (optional)

```bash
ollama pull gpt-oss:20b
ollama pull gpt-oss:120b
```

### What gets installed

| Source              | Destination                   |
| ------------------- | ----------------------------- |
| `settings.json`     | `~/.claude/settings.json`     |
| `CLAUDE.md`         | `~/.claude/CLAUDE.md`         |
| `hooks/*.sh`        | `~/.claude/hooks/`            |
| `skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` |

## Customization

- Edit `settings.json` to adjust permission rules and hooks
- Edit `CLAUDE.md` to change global behavior rules and model routing
- Add/remove hook scripts in `hooks/`
- Add/remove skills in `skills/`
- For project-specific rules, create a `CLAUDE.md` in the project root

## License

MIT
