---
name: context-budget
description: "Audit Claude Code context window consumption across skills, rules, agents, hooks, CLAUDE.md, and MCP servers. Reports token overhead and prioritized savings. Use this skill when: asked about context usage; asked to audit skill/rule/MCP bloat; after adding multiple skills or rules; before adding more components."
origin: "Adapted from everything-claude-code (github.com/affaan-m/everything-claude-code), skills/context-budget/"
---

# Context Budget Skill

Audits the token overhead of every component loaded into a Claude Code session and reports prioritized savings.

Inventory is deterministic (pure shell, zero Claude tokens). Claude is only used for classification and the final recommendation synthesis.

---

## Step 1: Inventory (Shell Only, Zero Claude Tokens)

Scan every component directory and emit raw counts. Always check user-level (`~/.claude/`) and project-level (`./.claude/` if present). Missing directories are fine — skip silently.

```bash
# Token estimation helper — words × 1.3 for prose, chars / 4 for JSON/code
est_tokens() {
  local f="$1"
  local words chars
  read -r words < <(wc -w < "$f")
  read -r chars < <(wc -c < "$f")
  # pick the larger of the two estimates
  local w=$(( words * 13 / 10 ))
  local c=$(( chars / 4 ))
  echo $(( w > c ? w : c ))
}

scan_dir() {
  local label="$1" pattern="$2"
  shift 2
  local total=0 count=0
  for root in "$@"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' f; do
      local t
      t=$(est_tokens "$f")
      total=$(( total + t ))
      count=$(( count + 1 ))
      echo "$label | $t | $(wc -l < "$f") | $f"
    done < <(find "$root" -type f -name "$pattern" -print0)
  done
  echo "TOTAL | $label | count=$count tokens=$total"
}

echo "=== Agents ==="
scan_dir agents '*.md' ~/.claude/agents ./.claude/agents

echo "=== Skills ==="
scan_dir skills 'SKILL.md' ~/.claude/skills ./.claude/skills

echo "=== Rules ==="
scan_dir rules '*.md' ~/.claude/rules ./rules ./.claude/rules

echo "=== CLAUDE.md chain ==="
for f in ~/.claude/CLAUDE.md ./CLAUDE.md; do
  [ -f "$f" ] || continue
  echo "CLAUDE.md | $(est_tokens "$f") | $(wc -l < "$f") | $f"
done
```

## Step 2: MCP Inventory (Shell Only)

MCP tool schemas are the single largest context driver (~500 tokens per tool). Detect configured servers from every source Claude Code reads.

```bash
# Project-level .mcp.json
for f in ./.mcp.json ~/.claude/mcp.json; do
  [ -f "$f" ] || continue
  echo "=== MCP config: $f ==="
  # Show server names and tool counts if jq is available
  if command -v jq >/dev/null; then
    jq -r '.mcpServers // {} | keys[]' "$f" 2>/dev/null
  else
    grep -E '^\s*"[^"]+"\s*:\s*\{' "$f" | head -20
  fi
done

# Claude CLI-registered servers (authoritative if present)
if command -v claude >/dev/null; then
  claude mcp list 2>/dev/null || true
fi
```

For each connected server, record the number of tools it exposes. If the server is not currently connected (e.g. Ollama is down), note it as "inactive" rather than counting tools as zero.

## Step 3: Hooks Note (Not Context Overhead)

Hooks in `~/.claude/hooks/` do **not** load into the prompt. They execute out-of-band. Report their count for completeness but do not include their tokens in the overhead total.

```bash
ls ~/.claude/hooks/*.sh 2>/dev/null | wc -l
```

## Step 4: Classification

For each component surfaced by Step 1, place it in one of three buckets using the criteria below. Use the component's `description` frontmatter when present — that is the only part guaranteed to load into every Task tool invocation.

| Bucket | Criteria | Action |
|--------|----------|--------|
| **Always needed** | Referenced by CLAUDE.md, backs a slash command in active use, or matches the current project's language/framework | Keep |
| **Sometimes needed** | Domain-specific (e.g. language rules for a language not in this project), not referenced anywhere | Consider on-demand activation — move under a directory that is not auto-loaded, or gate behind a command |
| **Rarely needed** | No reference from CLAUDE.md or commands, overlapping content with another component, or no plausible use in this project | Remove or lazy-load |

## Step 5: Detect Bloat Patterns

Flag each of the following if present:

- **Bloated descriptions** — any frontmatter `description` longer than 30 words. Descriptions load into every Task invocation, so verbosity compounds.
- **Heavy skill files** — `SKILL.md` over 400 lines.
- **Heavy agents** — agent `*.md` over 200 lines.
- **Heavy rule files** — single rule file over 100 lines (split into smaller overlays).
- **Redundant components** — skills that duplicate an agent's role, rule files that restate CLAUDE.md, agent descriptions that restate their own system prompt.
- **MCP oversubscription** — more than 10 active servers, or any server that wraps a CLI tool already allowed in `settings.json` (e.g. a `git` / `gh` / `npm` MCP is pure overhead when those commands are in the allow list).
- **CLAUDE.md bloat** — combined CLAUDE.md chain over 300 lines; extract detailed guidance into `rules/` instead.

## Step 6: Report

Emit the report in Japanese (per Language Policy). Use this shape:

```
Context Budget Report
=====================

推定オーバーヘッド合計: 約 XX,XXX tokens
コンテキストモデル: Claude Sonnet (200K window)
実効残量: 約 XXX,XXX tokens (XX%)

内訳:
| Component  | Count | Tokens  |
|------------|-------|---------|
| Agents     | N     | ~X,XXX  |
| Skills     | N     | ~X,XXX  |
| Rules      | N     | ~X,XXX  |
| MCP tools  | N     | ~XX,XXX |
| CLAUDE.md  | N     | ~X,XXX  |

検出された問題 (N 件):
  [savings 降順]

Top 3 最適化:
  1. [action] → 約 X,XXX tokens 削減
  2. [action] → 約 X,XXX tokens 削減
  3. [action] → 約 X,XXX tokens 削減

潜在削減量: 約 XX,XXX tokens (現オーバーヘッドの XX%)
```

Verbose mode (`--verbose` or "詳細" requested): additionally print the per-file table from Step 1, the full MCP tool list with per-tool schema size estimates, and side-by-side overlap between redundant components.

## Best Practices

- **MCP is the biggest lever** — each tool schema costs ~500 tokens. A 30-tool server alone exceeds most skill collections.
- **Agent descriptions always load** — even agents never invoked in a session contribute their description to every Task call.
- **Hooks are free** — they execute but do not consume context. Prefer hooks over skills when the work is deterministic shell logic.
- **Audit after each additive change** — run this skill after adding a skill, rule, agent, or MCP server to catch creep early.
- **200K is not usable space** — reserve at least 40% for conversation and tool output. Overhead above 30% of the window starts degrading quality.
