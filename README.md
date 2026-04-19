# claude-code-config

Safe default settings for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with agentic multi-model architecture.

## Repository structure

```text
claude-code-config/
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
│   ├── ollama-utils.sh           # Shared Ollama utility commands for skills
│   ├── notify.sh                 # Desktop notifications (macOS)
│   └── stop-notify.sh            # Task completion notifications
└── skills/
    ├── multi-agent-review/
    │   └── SKILL.md              # Multi-agent review workflow
    ├── simplify/
    │   └── SKILL.md              # Code simplification and cleanup
    ├── test-gen/
    │   └── SKILL.md              # Automatic test generation
    ├── pr-create/
    │   └── SKILL.md              # Pull request creation with auto-description
    └── explore/
        └── SKILL.md              # Deep codebase exploration and Q&A
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

### ollama-utils.sh (Utility — called by skills)

Shared Ollama utility commands for skills and hooks:

```bash
# Generate a kebab-case slug from task description
echo "Add user authentication" | bash ~/.claude/hooks/ollama-utils.sh generate-slug

# Summarize a git diff
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh summarize-diff

# Merge and deduplicate review findings from multiple agents
cat findings1.txt findings2.txt | bash ~/.claude/hooks/ollama-utils.sh merge-findings

# Classify changed files (feature/fix/refactor/docs/test/chore)
git diff --name-only | bash ~/.claude/hooks/ollama-utils.sh classify-changes

# Analyze a diff from an expert perspective (functionality / security / testing)
# Used by multi-agent-review Phase 3 to seed Claude sub-agents with findings
# instead of each sub-agent reading the full diff — reduces Claude token usage.
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-functionality
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-security
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-testing

# Generate a PR body from commits + diff stat + ALL review artifacts (mirrors the pr-create skill invocation)
{ echo '=== COMMIT LOG ==='; git log main...HEAD --oneline; \
  echo; echo '=== DIFF STAT ==='; git diff main...HEAD --stat; \
  for f in ./docs/archive/review/*-plan.md ./docs/archive/review/*-review.md \
           ./docs/archive/review/*-deviation.md ./docs/archive/review/*-code-review.md; do \
    [ -f "$f" ] || continue; echo; echo "=== $f ==="; cat "$f"; done; } \
  | bash ~/.claude/hooks/ollama-utils.sh generate-pr-body

# Generate a deviation log delta from plan + existing log + diff (three sections)
{ cat plan.md; echo '=== OLLAMA-INPUT-SEPARATOR ==='; \
  cat existing-deviation.md 2>/dev/null || echo '# new'; \
  echo '=== OLLAMA-INPUT-SEPARATOR ==='; git diff main...HEAD; } \
  | bash ~/.claude/hooks/ollama-utils.sh generate-deviation-log  # output = delta entries; APPEND to existing log

# Generate a commit body (subject line still hand-written)
git diff --cached | bash ~/.claude/hooks/ollama-utils.sh generate-commit-body

# Generate a resolution-status entry from finding + fix commit
{ echo "$FINDING"; echo '=== OLLAMA-INPUT-SEPARATOR ==='; git show HEAD; } \
  | bash ~/.claude/hooks/ollama-utils.sh generate-resolution-entry

# Summarize a round-to-round change for review artifacts
{ git log r1..HEAD --oneline; echo '=== OLLAMA-INPUT-SEPARATOR ==='; cat findings.txt; } \
  | bash ~/.claude/hooks/ollama-utils.sh summarize-round-changes

# Propose plan edits for a finding (anchor + insertion pairs)
{ cat plan.md; echo '=== OLLAMA-INPUT-SEPARATOR ==='; echo "$FINDING"; } \
  | bash ~/.claude/hooks/ollama-utils.sh propose-plan-edits
```

- All commands read stdin, write stdout — composable with pipes
- Gracefully returns empty output if Ollama is unavailable
- Supports thinking models (`.response` → `.thinking` fallback)

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
2. **Coding** — Sonnet sub-agent implementation with deviation tracking
3. **Code review** — Local LLM pre-screening + 3 Claude expert agents

Each review phase uses local LLM (`gpt-oss:120b`) to catch obvious issues before launching Claude sub-agents. Implementation is delegated to Sonnet sub-agents while Opus orchestrates, reducing API cost while maintaining quality.

### simplify

Reviews changed code for reuse, quality, and efficiency improvements:
- Local LLM pre-analysis for complexity hotspots and duplication (zero Claude tokens)
- Sonnet sub-agent explores codebase for concrete before/after proposals
- User selects which proposals to apply

### test-gen

Generates tests for specified or changed code:
- Auto-detects test framework and conventions
- Local LLM generates test case outlines (zero Claude tokens)
- Sonnet sub-agent implements and verifies tests with fix loop (max 3 iterations)

### pr-create

Creates a pull request with auto-generated description:
- Local LLM summarizes diff and classifies change type (zero Claude tokens)
- Local LLM composes PR body with summary, motivation, and test plan (zero Claude tokens)
- User reviews draft before `gh pr create`

### explore

Deep codebase exploration and Q&A:
- Local LLM extracts search keywords and builds file relevance map (zero Claude tokens)
- Sonnet sub-agent traces code paths and builds structured answers
- Supports: explanation, usage search, architecture, location, data flow queries

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Ollama](https://ollama.com/) installed (optional, for local LLM features)

### Setup

```bash
git clone https://github.com/ngc-shj/claude-code-config.git
cd claude-code-config
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
