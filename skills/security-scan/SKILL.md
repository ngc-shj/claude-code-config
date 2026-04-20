---
name: security-scan
description: "Audit Claude Code configuration for security issues: hardcoded secrets, overly permissive allow lists, hook injection risks, MCP supply chain, auto-run instructions. Use this skill when: setting up a new project; after modifying settings.json / CLAUDE.md / .mcp.json / hooks; before committing config changes; onboarding to a repo with existing Claude Code config."
origin: "Independent reimplementation inspired by everything-claude-code skills/security-scan (which wraps AgentShield / ecc-agentshield). This version is self-contained: grep + jq + Ollama, no npm dependency."
---

# Security Scan Skill

Audit Claude Code configuration for common misconfigurations using deterministic pattern checks, with optional local-LLM deep analysis.

Inventory and pattern matching are pure shell (zero Claude tokens). Ollama (`gpt-oss:120b` via `ollama-utils.sh analyze-security`) provides optional depth. Claude only synthesizes the final report.

---

## Step 1: Scope

| User instruction | Scope |
|-----------------|-------|
| No target | Both `~/.claude/` and project `./.claude/` / repo config |
| "Scan user config" | `~/.claude/` only |
| "Scan this repo" | Project files only (`./.claude/`, `./.mcp.json`, `./CLAUDE.md`) |
| A specific path | That path only |

## Step 2: Deterministic Pattern Checks (Shell Only, Zero Claude Tokens)

Run each check; collect findings into `$FINDINGS` for the report. A finding is `[SEVERITY] path:line — problem`.

### 2a. Hardcoded secrets

```bash
# Scan CLAUDE.md, settings.json, .mcp.json, hooks, skills, rules
TARGETS=$(find ~/.claude ./.claude ./CLAUDE.md ./.mcp.json 2>/dev/null -type f \
  \( -name '*.md' -o -name '*.json' -o -name '*.sh' \) 2>/dev/null)

# Common secret patterns — require a value, not just the key name
grep -nE '(api[_-]?key|token|secret|password|bearer|authorization)\s*[:=]\s*["\x27][^"\x27]{16,}' $TARGETS
grep -nE 'sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|xox[baprs]-[a-zA-Z0-9-]{10,}' $TARGETS
# AWS: access key id + secret access key
grep -nE 'AKIA[0-9A-Z]{16}' $TARGETS
```

Severity: **CRITICAL**. Any match — rotate the secret, do not just remove the line.

### 2b. Overly permissive allow list in settings.json

```bash
for f in ~/.claude/settings.json ./.claude/settings.json; do
  [ -f "$f" ] || continue
  # Wildcard Bash
  jq -r '.permissions.allow // [] | .[] | select(test("^Bash\\(\\*\\)$|^Bash\\(.*:\\*\\)$"))' "$f"
  # Any .* wildcard in allow
  jq -r '.permissions.allow // [] | .[] | select(test("\\*"))' "$f"
  # Missing deny list entirely
  jq -e '.permissions.deny' "$f" >/dev/null 2>&1 || echo "$f: no deny list defined"
  # --dangerously-skip-permissions or similar escape hatches in env
  jq -r '.env // {} | to_entries[] | select(.value | tostring | test("dangerous|skip-permissions|bypass"))' "$f"
done
```

Severity: **HIGH** for `Bash(*)` or missing deny list, **MEDIUM** for narrower wildcards.

### 2c. Hook injection risks

```bash
for f in ~/.claude/hooks/*.sh ./.claude/hooks/*.sh 2>/dev/null; do
  [ -f "$f" ] || continue
  # Unquoted variable expansion in command context (most common injection vector)
  grep -nE '(bash|sh|eval|exec|system)\s+[^"\x27]*\$[A-Za-z_][A-Za-z0-9_]*' "$f"
  # Silent error suppression
  grep -nE '2>/dev/null|\|\| true|\|\| :' "$f"
  # curl piped to shell (supply chain)
  grep -nE 'curl.*\|\s*(bash|sh)' "$f"
  # Writes to ~/.ssh or /etc
  grep -nE '>\s*~/.ssh|>\s*/etc/' "$f"
done
```

Severity: CRITICAL for curl-to-shell or ssh write; HIGH for unquoted expansion; MEDIUM for silent suppression.

### 2d. MCP server supply chain

```bash
for f in ~/.claude/mcp.json ./.mcp.json 2>/dev/null; do
  [ -f "$f" ] || continue
  if command -v jq >/dev/null; then
    # npx with -y flag = auto-install without prompt
    jq -r '.mcpServers // {} | to_entries[] | select(.value.command == "npx" and (.value.args // [] | any(. == "-y"))) | .key' "$f"
    # Hardcoded env values that look like secrets
    jq -r '.mcpServers // {} | to_entries[] | .value.env // {} | to_entries[] | select(.value | tostring | test("^[A-Za-z0-9+/=]{20,}$")) | "[secret in env] \(.key)"' "$f"
  fi
done
```

Severity: MEDIUM for `npx -y`, CRITICAL for hardcoded env secrets.

### 2e. CLAUDE.md prompt-injection surface

```bash
for f in ~/.claude/CLAUDE.md ./CLAUDE.md 2>/dev/null; do
  [ -f "$f" ] || continue
  # "Always run" / "automatically execute" style instructions
  grep -niE 'always\s+(run|execute|commit|push)|automatically\s+(run|execute)' "$f"
  # Credentials or paths that should not be in CLAUDE.md
  grep -niE 'password|api[_-]?key.*=|secret.*=' "$f"
done
```

Severity: HIGH for auto-run instructions (LLM can be tricked into invoking them via malicious inputs), CRITICAL for credentials.

### 2f. Skill / agent tool over-reach

```bash
# Agents or skills declaring unrestricted tool access
for f in ~/.claude/agents/*.md ~/.claude/skills/*/SKILL.md ./.claude/skills/*/SKILL.md 2>/dev/null; do
  [ -f "$f" ] || continue
  # tools field with Bash and no restriction, or missing entirely
  awk '/^---$/{fm=!fm; next} fm && /^tools:/ {print FILENAME":"NR": "$0}' "$f"
done
```

Severity: MEDIUM. Review whether the agent / skill actually needs Bash or Edit/Write.

## Step 3: Optional Ollama Deep Analysis

Pipe the surfaced findings plus the raw config content to `gpt-oss:120b` for contextual analysis — zero Claude tokens.

```bash
# Example: analyze settings.json for anything Step 2 missed
{
  echo "=== settings.json ==="
  cat ~/.claude/settings.json
  echo "=== pattern-scan findings ==="
  echo "$FINDINGS"
} | bash ~/.claude/hooks/ollama-utils.sh analyze-security
```

The hook returns freeform text. Merge unique findings back into `$FINDINGS`. Skip this step if Ollama is unavailable — the deterministic checks alone are useful.

## Step 4: Claude Synthesis and Report

Group findings by severity, deduplicate, and emit the report in Japanese (per Language Policy).

```
Security Scan Report
====================

対象: [scanned paths]
合計検出: [N] 件 (Critical: [x] / High: [y] / Medium: [z] / Info: [w])

Critical:
  - [path:line] [problem]
    推奨対応: [action]

High:
  ...

Medium:
  ...

Info:
  ...

Grade: [A/B/C/D/F based on severity distribution]
```

Grading heuristic (purely advisory):

| Grade | Criteria |
|-------|----------|
| A | No Critical/High, ≤2 Medium |
| B | No Critical, 0-1 High, ≤5 Medium |
| C | 0-1 Critical, 2-3 High, or ≤10 Medium |
| D | 2+ Critical, or 4+ High |
| F | Any CRITICAL with plaintext secrets, curl-to-shell, or Bash(*) in allow |

## Best Practices

- **Pattern checks are the floor, not the ceiling.** They catch the obvious. Ollama finds contextual issues (e.g. a prohibition in CLAUDE.md negated by a later sentence). Use both when possible.
- **Rotate, don't just remove.** If a secret was committed, rotating it is mandatory — deleting the line keeps it in git history.
- **`settings.local.json` customizations are in scope.** If the user has machine-local settings, scan them too.
- **Hooks are the highest-leverage injection target.** They execute with the user's full shell; a single unquoted variable can become a remote code execution path.
