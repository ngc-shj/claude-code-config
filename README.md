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
│   ├── llm-utils.sh             # Common local-LLM layer: backend select + dispatch
│   ├── llm-commands.sh          # Backend-agnostic LLM command library for skills
│   ├── ollama-backend.sh        # Ollama provider: discover/load-balance + generate
│   ├── llamacpp-backend.sh      # llama.cpp provider: OpenAI /v1 discovery + request
│   ├── notify.sh                 # Desktop notifications (macOS + Linux)
│   └── stop-notify.sh            # Task completion notifications
├── skills/
│   ├── triangulate/
│   │   └── SKILL.md              # Triangulate: 3-phase × 3-expert review workflow
│   ├── simplify/
│   │   └── SKILL.md              # Code simplification and cleanup
│   ├── test-gen/
│   │   └── SKILL.md              # Automatic test generation
│   ├── pr-create/
│   │   └── SKILL.md              # Pull request creation with auto-description
│   ├── agent-review/
│   │   ├── SKILL.md              # Backend-agnostic diff review (ollama/codex/claude, local-first)
│   │   ├── review-backend.sh     # Reviewer-backend contract: detect + run (+ --adversarial)
│   │   └── schemas/
│   │       └── review-output.schema.json  # Canonical structured findings shape
│   ├── explore/
│   │   └── SKILL.md              # Deep codebase exploration and Q&A
│   ├── context-budget/
│   │   └── SKILL.md              # Audit context window consumption and surface savings
│   └── security-scan/
│       └── SKILL.md              # Audit Claude Code config for secrets, injection, MCP risks
└── rules/
    ├── common/                   # Language-agnostic baseline (always applied)
    │   ├── coding-style.md
    │   ├── testing.md
    │   └── security.md
    ├── typescript/               # Overlays common/ for *.ts, *.tsx, *.js, *.jsx
    ├── python/                   # Overlays common/ for *.py
    └── golang/                   # Overlays common/ for *.go
```

## Agentic architecture

```text
┌──────────────────────────────────────────────────┐
│  Claude Opus 4.8 (Main Orchestrator)             │
│  Complex design, planning, final decisions       │
└──┬────────────────┬─────────────────┬────────────┘
   │                │                 │
   ▼                ▼                 ▼
┌────────┐  ┌─────────────┐  ┌──────────────────┐
│Sonnet  │  │gpt-oss:120b │  │gpt-oss:20b       │
│4.6     │  │(local)      │  │(local)           │
│        │  │             │  │                  │
│Explore │  │Code review  │  │Commit msg check  │
│Implement│ │pre-screening│  │Quick validation  │
│Test    │  │Security scan│  │Summarization     │
└────────┘  └─────────────┘  └──────────────────┘
```

### Model routing

| Model | Role | Use case |
| --- | --- | --- |
| Claude Opus 4.8 | Main orchestrator | Architecture, planning, final decisions |
| Claude Sonnet 4.6 | Sub-agent | Exploration, implementation, testing |
| gpt-oss:120b | Local pre-screening | Code review, security analysis (before Claude) |
| gpt-oss:20b | Local quick checks | Commit messages, lint, format, classification |

The two local logical names (`gpt-oss:120b`, `gpt-oss:20b`) are what the hooks
request; the active backend resolves them to a real model. Run via
[llama.cpp](https://github.com/ggml-org/llama.cpp) or [Ollama](https://ollama.com/)
(auto-selected by the `llm-utils.sh` dispatcher, llama.cpp preferred) — **no API
cost, no data leaves your machine**. Called via hooks (shell + curl) for
file-aware tasks, or MCP for ad-hoc text analysis.

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

Validates commit messages using the local LLM (logical model `gpt-oss:20b`, via the `llm-utils.sh` dispatcher — llama.cpp or Ollama):

- Checks for conventional commit format (feat/fix/refactor/docs/test/chore)
- Verifies the message is in English and concise
- Provides improvement suggestions if needed
- Gracefully skips if no local LLM backend is reachable

### pre-review.sh (Utility — called by skills)

Pre-screening for code review and plan review using the local LLM (logical model `gpt-oss:120b`, via the `llm-utils.sh` dispatcher — llama.cpp or Ollama):

```bash
# Review plan
PLAN_FILE=path/to/plan.md bash ~/.claude/hooks/pre-review.sh plan

# Review code changes
bash ~/.claude/hooks/pre-review.sh code
```

- Reads files directly via shell (git diff, cat) — no Claude tokens consumed
- Configurable via `REVIEW_MODEL`, `LLM_BACKEND`, and the backend host vars (`LLAMACPP_HOST` / `OLLAMA_HOST`)
- Gracefully skips if no local LLM backend is reachable

#### Local-LLM backend layer (`llm-utils.sh`)

Hooks and skills reach a local LLM through a single backend-agnostic layer,
`llm-utils.sh`, which holds the common processing (shared discovery helpers,
backend selection, logical→real model mapping, and the `llm_request`
dispatcher) and sources two backend providers:

- `ollama-backend.sh` — Ollama (native `/api/generate`, multi-server discovery)
- `llamacpp-backend.sh` — llama.cpp's OpenAI surface (`/v1/chat/completions`, `/v1/models`)

Backend selection: `LLM_BACKEND=llamacpp|ollama` pins the choice; otherwise
llama.cpp is **auto-preferred** when its `/v1/models` endpoint is reachable
(default `localhost:8080`, overridable via `LLAMACPP_HOST`/`LLAMACPP_HOSTS`),
falling back to Ollama. Hooks always pass logical model names (`gpt-oss:20b`,
`gpt-oss:120b`); for llama.cpp these map to `unsloth/gpt-oss-20b-GGUF:F16` and
`unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL` (8080 has no 120b-class model, so the
heavy slot maps to Qwen3.6-35B-A3B; note llama-server strips the unsloth `UD-`
prefix, so the `UD-Q4_K_XL` build is addressed as `Q4_K_XL`),
overridable via `LLAMACPP_MODEL_SMALL`/`LLAMACPP_MODEL_LARGE`. The
command library (`llm-commands.sh`) and the direct-caller hooks
(`pre-review.sh`, `commit-msg-check.sh`) source only `llm-utils.sh`.

#### Multi-server load balancing (`ollama-backend.sh`)

The Ollama provider probes the configured Ollama servers and load-balances
across them:

- **Trust model (read this first)** — prompts sent to a pool member include
  git diffs and **full source-file contents**, so every host in the pool is a
  potential exfiltration sink. The pool is therefore built from hosts you
  explicitly name (`OLLAMA_HOST` pin or `OLLAMA_EXTRA_HOSTS` list). Requests
  travel over plain HTTP with no server authentication — use hosts on networks
  you control (or a Tailscale tailnet, which encrypts and authenticates the
  transport).
- **Opt-in auto-discovery** (`OLLAMA_DISCOVERY`, default **off**) — setting
  `OLLAMA_DISCOVERY=1` (both sources) or a list like
  `OLLAMA_DISCOVERY="tailscale"` / `"mdns tailscale"` enables automatic
  candidate enumeration: online Tailscale peers (MagicDNS FQDNs) and/or
  mDNS-advertised LAN hosts. Any candidate that answers `/api/version` joins
  the pool, regardless of hostname. **mDNS candidates are unauthenticated: any
  device on the LAN that mimics the Ollama API will receive your code — enable
  `mdns` only on networks where every host is trusted.** Tailscale peers are
  tailnet-authenticated, but shared or compromised nodes still receive code,
  hence opt-in as well.
- **Cross-platform discovery** — mDNS auto-discovery uses `avahi-browse` (Linux
  only). macOS has no avahi and its `dns-sd` service-browse does not reliably
  surface plain Ollama hosts, so on macOS list your LAN host name(s) in
  `OLLAMA_EXTRA_HOSTS` — the OS resolver answers `.local`, so the probe reaches
  them anyway. Tailscale discovery works on both: the CLI is resolved from PATH,
  then the macOS app bundle
  (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`), then `$TAILSCALE_BIN`.
- **Model-aware routing** — servers do **not** have to host the same models. At
  probe time each server's `/api/tags` inventory is cached, and a request is
  routed (round-robin) only among servers that actually have the requested
  model. A model present nowhere makes the caller skip gracefully rather than
  hit a 404. Callers resolve their target with the exported
  `ollama_host_for_model <model>` function.
- **Load balancing** — `OLLAMA_HOST` (one server, round-robin, model-agnostic
  default) and `OLLAMA_HOSTS` (full pool) are exported for back-compat. Existing
  callers that read only `$OLLAMA_HOST` keep working.
- **Overrides** — `OLLAMA_HOST` pins to a single server (skips probing);
  `OLLAMA_DISCOVERY_MAX` caps probe fan-out per source (default 6);
  `OLLAMA_EXTRA_HOSTS` is the primary multi-server configuration (space-separated
  bare host, `host:port`, or URL). Probe results are cached for 5 minutes in a
  per-user private state dir (`$XDG_RUNTIME_DIR/claude-llm-hooks`, falling back
  to `~/.cache/claude-llm-hooks` — never world-writable `/tmp`). The cache is
  bound to the trust configuration (`OLLAMA_DISCOVERY` + `OLLAMA_EXTRA_HOSTS`)
  that produced it, so revoking or changing an opt-in takes effect on the next
  call — a host admitted under a since-revoked setting is never served from
  cache. localhost is used only when no remote server is reachable.
- **Configuration example** — hooks inherit Claude Code's process environment,
  so the most reliable place for these variables is the `env` block of
  `~/.claude/settings.local.json` (machine-specific, works for both IDE and
  CLI launches; a shell-profile `export` also works for terminal launches):

  ```json
  {
    "env": {
      "OLLAMA_EXTRA_HOSTS": "gx10-a9c0 ul9c-r49.tailnet-example.ts.net"
    }
  }
  ```

  To restore zero-config auto-discovery instead (after reading the trust
  model above), set `"OLLAMA_DISCOVERY": "tailscale"` (tailnet only) or
  `"1"` (also mDNS — trusted networks only).

### llm-commands.sh (Utility — called by skills)

Backend-agnostic local-LLM command library for skills and hooks (routes through
`llm-utils.sh`, so commands run on whichever backend is active):

```bash
# Generate a kebab-case slug from task description
echo "Add user authentication" | bash ~/.claude/hooks/llm-commands.sh generate-slug

# Summarize a git diff
git diff main...HEAD | bash ~/.claude/hooks/llm-commands.sh summarize-diff

# Merge and deduplicate review findings from multiple agents
cat findings1.txt findings2.txt | bash ~/.claude/hooks/llm-commands.sh merge-findings

# Classify changed files (feature/fix/refactor/docs/test/chore)
git diff --name-only | bash ~/.claude/hooks/llm-commands.sh classify-changes

# Classify a user question into an explore query type (explanation / usage-search / architecture / location / data-flow)
echo "How does the request router work?" | bash ~/.claude/hooks/llm-commands.sh classify-query

# Analyze a diff from an expert perspective (functionality / security / testing)
# Used by triangulate Phase 3 to seed Claude sub-agents with findings
# instead of each sub-agent reading the full diff — reduces Claude token usage.
git diff main...HEAD | bash ~/.claude/hooks/llm-commands.sh analyze-functionality
git diff main...HEAD | bash ~/.claude/hooks/llm-commands.sh analyze-security
git diff main...HEAD | bash ~/.claude/hooks/llm-commands.sh analyze-testing

# Pre-screen reuse candidates (shared-utils inventory + diff) for the simplify skill
{ bash ~/.claude/hooks/scan-shared-utils.sh; echo '=== OLLAMA-INPUT-SEPARATOR ==='; \
  git diff main...HEAD; } | bash ~/.claude/hooks/llm-commands.sh score-utility-match

# Audit mock return values in a test file against the real type definitions
{ cat tests/foo.test.ts; echo '=== OLLAMA-INPUT-SEPARATOR ==='; \
  cat src/types/foo.ts; } | bash ~/.claude/hooks/llm-commands.sh verify-mock-shapes

# Generate a PR title from classify-changes + summarize-diff output
{ echo "$CATEGORY"; echo '=== OLLAMA-INPUT-SEPARATOR ==='; echo "$SUMMARY"; } \
  | bash ~/.claude/hooks/llm-commands.sh generate-pr-title

# Generate a PR body from commits + diff stat + ALL review artifacts (mirrors the pr-create skill invocation)
{ echo '=== COMMIT LOG ==='; git log main...HEAD --oneline; \
  echo; echo '=== DIFF STAT ==='; git diff main...HEAD --stat; \
  for f in ./docs/archive/review/*-plan.md ./docs/archive/review/*-review.md \
           ./docs/archive/review/*-deviation.md ./docs/archive/review/*-code-review.md; do \
    [ -f "$f" ] || continue; echo; echo "=== $f ==="; cat "$f"; done; } \
  | bash ~/.claude/hooks/llm-commands.sh generate-pr-body

# Generate a deviation log delta from plan + existing log + diff (three sections)
{ cat plan.md; echo '=== OLLAMA-INPUT-SEPARATOR ==='; \
  cat existing-deviation.md 2>/dev/null || echo '# new'; \
  echo '=== OLLAMA-INPUT-SEPARATOR ==='; git diff main...HEAD; } \
  | bash ~/.claude/hooks/llm-commands.sh generate-deviation-log  # output = delta entries; APPEND to existing log

# Generate a commit body (subject line still hand-written)
git diff --cached | bash ~/.claude/hooks/llm-commands.sh generate-commit-body

# Generate a resolution-status entry from finding + fix commit
{ echo "$FINDING"; echo '=== OLLAMA-INPUT-SEPARATOR ==='; git show HEAD; } \
  | bash ~/.claude/hooks/llm-commands.sh generate-resolution-entry

# Summarize a round-to-round change for review artifacts
{ git log r1..HEAD --oneline; echo '=== OLLAMA-INPUT-SEPARATOR ==='; cat findings.txt; } \
  | bash ~/.claude/hooks/llm-commands.sh summarize-round-changes

# Propose plan edits for a finding (anchor + insertion pairs)
{ cat plan.md; echo '=== OLLAMA-INPUT-SEPARATOR ==='; echo "$FINDING"; } \
  | bash ~/.claude/hooks/llm-commands.sh propose-plan-edits
```

- All commands read stdin, write stdout — composable with pipes
- Backend-agnostic: routed through `llm-utils.sh` (llama.cpp auto-preferred, else Ollama)
- Gracefully returns empty output if no local LLM backend is reachable
- Supports reasoning/thinking models (Ollama `.response`→`.thinking`; llama.cpp `content`→`reasoning_content`)

### notify.sh (Notification)

Cross-platform desktop notifications (macOS via `afplay`/`osascript`, Linux via `paplay`/`aplay` + `notify-send`) when:

- **permission_prompt**: Claude needs permission approval — plays sound + notification
- **idle_prompt**: Claude is waiting for input — plays sound + notification

> Linux sounds resolve from the freedesktop theme; all calls are best-effort and skip silently if the tools or audio are unavailable.

### stop-notify.sh (Stop)

Notifies when Claude finishes a response:

- **end_turn**: Task complete — plays Glass sound + notification
- **max_tokens**: Token limit reached — plays alert sound + warning notification

## Skills

### triangulate

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

### agent-review

Backend-agnostic diff review: a *reviewer* is treated as any agent that takes a diff and returns findings headlessly, so the review path never depends on one CLI (this subsumes the former `codex-review` skill — Codex is now just one selectable backend):
- Auto-detects available backends in preference order — `ollama` (free; sends the diff only to your explicitly configured local-LLM hosts via the `llm-utils.sh` dispatcher — llama.cpp when reachable, else Ollama; see the ollama-backend trust model above) → `codex` (external second opinion, `codex review`) → `claude` (fresh headless context, spends tokens)
- Defaults to the free local backend, reusing `llm-commands.sh` (functionality / security / testing) — zero Claude tokens when a local backend (llama.cpp or Ollama) is reachable
- Review scope: uncommitted changes, a base branch, or a specific commit; optionally cross-checks findings against `triangulate` review artifacts
- `--adversarial` mode challenges the design/approach/failure-modes instead of a line-by-line pass (ollama gets a dedicated `adversarial-review` pass; codex/claude get an approach-challenging prompt)
- Normalizes every backend's output into a canonical structured shape (`schemas/review-output.schema.json`: verdict / findings / next_steps), and backgrounds slow reviews via the harness's `run_in_background`
- Data flow varies by backend — `ollama` stays on the local/LAN host, `codex`/`claude` send the diff to their servers; do not run an external backend on a diff that stages secrets
- Add a backend by extending one branch in `review-backend.sh`; the skill steps stay identical
- Borrows its structured-findings, background-job, and adversarial-review ideas from OpenAI's `codex-plugin-cc`, adapted to a single multi-backend skill

### explore

Deep codebase exploration and Q&A:
- Local LLM extracts search keywords and builds file relevance map (zero Claude tokens)
- Sonnet sub-agent traces code paths and builds structured answers
- Supports: explanation, usage search, architecture, location, data flow queries

### context-budget

Audits token overhead across agents, skills, rules, CLAUDE.md, and MCP servers, then surfaces prioritized savings:
- Inventory phase is pure shell (word count, line count) — zero Claude tokens
- Claude classifies components as always/sometimes/rarely needed and ranks optimizations
- Flags bloated descriptions, heavy files, MCP oversubscription, CLAUDE.md creep
- Adapted from [everything-claude-code](https://github.com/affaan-m/everything-claude-code) (`skills/context-budget/`)

### security-scan

Audits Claude Code configuration for common security misconfigurations — zero external dependencies:
- Deterministic pattern checks (grep + jq) for secrets, `Bash(*)` wildcards, hook injection, MCP supply chain, prompt-injection surface in CLAUDE.md
- Optional deep analysis via `gpt-oss:120b` through `llm-commands.sh analyze-security` (zero Claude tokens)
- Graded A/F report with severity-classified findings
- Concept borrowed from [everything-claude-code](https://github.com/affaan-m/everything-claude-code) (`skills/security-scan/`, which wraps the AgentShield npm package); reimplemented here as a self-contained shell + local-LLM workflow

## Rules

Layered coding-style / testing / security guidance, consulted when editing matching files.

- `rules/common/` — language-agnostic baseline (KISS/DRY/YAGNI, test minimums, secrets handling). Always applied.
- `rules/{lang}/` — language overlays that extend the baseline and override where the language idiom differs (e.g. Go mutability). Each file declares `paths:` in YAML frontmatter.

Currently shipped: `typescript/`, `python/`, `golang/`. Extend by dropping a new `rules/{lang}/` directory with at least `coding-style.md` and a `paths:` frontmatter.

Rules are referenced, not auto-injected — Claude reads them via the directive in `CLAUDE.md` when the file type matches.

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Ollama](https://ollama.com/) and/or [llama.cpp](https://github.com/ggml-org/llama.cpp) (optional, for local LLM features — when both are reachable, llama.cpp is auto-preferred)

### Setup

```bash
git clone https://github.com/ngc-shj/claude-code-config.git
cd claude-code-config
bash install.sh
```

The installer overwrites `CLAUDE.md`, hooks, skills, and rules — this repo is the source of truth and `git` history is the rollback mechanism, so no `.bak` files are kept for them. Any stale `.bak` under `~/.claude/{hooks,skills,rules}/` from earlier installs is removed on the next run (stale skill backups otherwise load as shadow skills).

`settings.json` is the exception: it is **merged** into any existing live file rather than overwritten, so user-managed top-level keys the template does not own (e.g. `mcpServers`) survive. `permissions` and `hooks` are template-owned and replaced wholesale, so a stale user sub-key or unmanaged hook event in the live file does not leak through. A non-object/garbage live file is backed up and replaced instead of merged. A timestamped `settings.json.bak.<ts>` (mode 600) is written first. Backups are not auto-pruned — purge old ones periodically.

For local customizations that should survive installs, use `~/.claude/settings.local.json` instead of editing `~/.claude/settings.json` directly.

### Install local models (optional)

**Ollama backend** — the logical names are the real model tags:

```bash
ollama pull gpt-oss:20b
ollama pull gpt-oss:120b
```

**llama.cpp backend** — run `llama-server` (default `localhost:8080`); the logical
names map to these real model ids (override with `LLAMACPP_MODEL_SMALL` /
`LLAMACPP_MODEL_LARGE`):

| Logical | llama.cpp model id (default) |
| --- | --- |
| `gpt-oss:20b` | `unsloth/gpt-oss-20b-GGUF:F16` |
| `gpt-oss:120b` | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL` (8080 has no 120b-class model; llama-server strips the unsloth `UD-` prefix, so the `UD-Q4_K_XL` build is requested as `Q4_K_XL`) |

When both backends are reachable, llama.cpp is auto-preferred; pin with
`LLM_BACKEND=ollama` or `LLM_BACKEND=llamacpp`.

### What gets installed

| Source              | Destination                   |
| ------------------- | ----------------------------- |
| `settings.json`     | `~/.claude/settings.json`     |
| `CLAUDE.md`         | `~/.claude/CLAUDE.md`         |
| `hooks/*.sh`        | `~/.claude/hooks/`            |
| `skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` |
| `rules/*/*.md`      | `~/.claude/rules/*/*.md`      |

## Customization

- Edit `settings.json` to adjust permission rules and hooks
- Edit `CLAUDE.md` to change global behavior rules and model routing
- Add/remove hook scripts in `hooks/`
- Add/remove skills in `skills/`
- Add language-specific rules in `rules/{lang}/` — each file carries a `paths:` frontmatter indicating which file globs it applies to
- For project-specific rules, create a `CLAUDE.md` in the project root

## License

MIT
