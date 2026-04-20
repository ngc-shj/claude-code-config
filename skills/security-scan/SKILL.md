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

**Step 2 is tuned for high recall, not precision.** False positives are expected — most get filtered when Step 3 runs the findings past `gpt-oss:120b` for contextual triage, or when Claude synthesizes the final report. Do not suppress findings at this stage. The danger is missing a real issue, not over-reporting.

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

Classify wildcard entries by the command they authorize, not by the mere presence of `*`. `Bash(git commit *)` is scoped (fixed command, variable args); `Bash(rm *)` is dangerous (destructive command, any target).

```bash
# Tunable danger list — destructive or privilege-escalating commands.
DANGEROUS_CMDS='^Bash\((sudo|rm|rmdir|dd|chmod|chown|mkfs|mount|umount|kill|pkill|shutdown|reboot|eval|source|exec)( |\*|:)'
# Tunable network/exfiltration list — narrow wildcards acceptable, but worth visibility.
NETWORK_CMDS='^Bash\((curl|wget|ssh|scp|rsync|nc|ncat|socat)( |\*|:)'

for f in ~/.claude/settings.json ~/.claude/settings.local.json ./.claude/settings.json ./.claude/settings.local.json; do
  [ -f "$f" ] || continue
  command -v jq >/dev/null || continue

  # CRITICAL — Bash(*) or Bash(*:*) grants effectively unrestricted shell.
  jq -r --arg f "$f" '.permissions.allow // [] | .[] | select(test("^Bash\\(\\*\\)$|^Bash\\([^)]*:\\*\\)$")) | "[CRITICAL] \($f) — unrestricted: \(.)"' "$f"

  # HIGH — wildcards on destructive commands.
  jq -r --arg f "$f" --arg re "$DANGEROUS_CMDS" '.permissions.allow // [] | .[] | select(test($re)) | "[HIGH] \($f) — dangerous command with wildcard: \(.)"' "$f"

  # MEDIUM — wildcards on network / exfiltration-capable commands.
  jq -r --arg f "$f" --arg re "$NETWORK_CMDS" '.permissions.allow // [] | .[] | select(test($re)) | "[MEDIUM] \($f) — network command with wildcard: \(.)"' "$f"

  # HIGH — deny list missing entirely.
  jq -e '.permissions.deny' "$f" >/dev/null 2>&1 || echo "[HIGH] $f — no permissions.deny list defined"

  # CRITICAL — dangerous env escape hatches.
  jq -r --arg f "$f" '.env // {} | to_entries[] | select(.value | tostring | test("dangerous|skip-permissions|bypass"; "i")) | "[CRITICAL] \($f) — env bypass: \(.key)=\(.value)"' "$f"
done
```

Narrow wildcards on common dev tooling (`Bash(git commit *)`, `Bash(gh pr *)`, `Bash(npm run *)`, `Bash(docker compose *)`, `Bash(python *)`) intentionally produce **no finding** — they are the expected shape of a working dev config.

### 2c. Hook injection risks

Uses `find` rather than glob expansion so the check works under both bash and zsh without relying on `shopt`/`setopt`.

```bash
find ~/.claude/hooks ./.claude/hooks -maxdepth 1 -name '*.sh' -type f 2>/dev/null | while IFS= read -r f; do
  # CRITICAL — curl piped to shell (supply-chain vector).
  grep -nE 'curl[^|]*\|\s*(bash|sh|zsh)' "$f" \
    | sed "s|^|[CRITICAL] $f — curl-to-shell: |"

  # CRITICAL — redirect into ssh config or system dirs.
  grep -nE '>\s*(~/\.ssh|/etc/|/usr/|/bin/|/sbin/)' "$f" \
    | sed "s|^|[CRITICAL] $f — sensitive-path write: |"

  # HIGH — unquoted variable expansion where the value becomes argv to a shell.
  grep -nE '(eval|bash -c|sh -c)\s+[^"\x27]*\$[A-Za-z_]' "$f" \
    | sed "s|^|[HIGH] $f — unquoted eval/bash -c arg: |"

  # MEDIUM — error suppression AFTER a destructive command.
  # Generic `cmd 2>/dev/null` is usually defensive (file-existence probe, graceful
  # Ollama-unavailable fallback). Only flag suppression paired with rm/mv/chmod etc.
  grep -nE '\b(rm|rmdir|mv|chmod|chown|dd|kill)\b[^|&;]*\s+(2>/dev/null|\|\|\s*(true|:))' "$f" \
    | sed "s|^|[MEDIUM] $f — suppression after destructive cmd: |"

  # INFO — generic silent-suppression count. Not listed per-line; likely benign defense.
  count=$(grep -cE '2>/dev/null|\|\|\s*(true|:)' "$f" 2>/dev/null); count=${count:-0}
  [ "$count" -gt 5 ] 2>/dev/null && echo "[INFO] $f — $count silent-suppression hits (most are usually defensive; review if unexpected)"
done
```

Rationale for the split: running the original rule against a mature hook collection produces dozens of hits on `[ -f "$f" ] 2>/dev/null` and `|| true` used for graceful fallback — none of which are security issues. The narrowed rule only flags suppression paired with a command that can destroy state, while the generic count is demoted to INFO.

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
{
  find ~/.claude/agents ./.claude/agents -maxdepth 1 -name '*.md' -type f 2>/dev/null
  find ~/.claude/skills ./.claude/skills -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f 2>/dev/null
} | while IFS= read -r f; do
  # Extract tools line from frontmatter only.
  awk '/^---$/{fm=!fm; next} fm && /^tools:/ {print FILENAME":"NR": "$0}' "$f"
done
```

Severity: MEDIUM. Review whether the agent / skill actually needs Bash or Edit/Write. No output means no agent/skill restricts its tools via frontmatter — this is not inherently a problem (the default tool set is what Claude Code supplies), just something to be aware of.

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
