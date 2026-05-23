#!/bin/bash
# Linux-adapted installer for claude-code-config.
#
# Differences from upstream ngc-shj/claude-code-config:
#   - settings.json is MERGED into ~/.claude/settings.json, not overwritten.
#     The template's `permissions` and `hooks` win; the user's other top-level
#     keys (mcpServers, agentPushNotifEnabled, etc.) are preserved. A timestamped
#     backup is written before the merge so rollback is always possible.
#   - CLAUDE.md and skills/rules/hooks are still treated as repo-managed
#     (overwrite on install) — git history is the rollback mechanism for those.
#   - Skipped on Linux: macOS-only assets. (notify.sh / stop-notify.sh have
#     been rewritten to use paplay + notify-send.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-code-config (Linux fork)..."

# --- Pre-flight ---------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for settings.json merge but is not on PATH." >&2
  echo "       Install with: sudo apt install jq" >&2
  exit 1
fi

if ! jq empty "$SCRIPT_DIR/settings.json" 2>/dev/null; then
  echo "ERROR: $SCRIPT_DIR/settings.json is not valid JSON. Refusing to install." >&2
  echo "       Run: jq empty $SCRIPT_DIR/settings.json" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

# --- settings.json: MERGE not overwrite ---------------------------------------
#
# Strategy: deep-merge with `jq -s '.[0] * .[1]' existing template`.
#   - User's top-level keys (mcpServers, agentPushNotifEnabled, ...) are kept.
#   - Template's `permissions` and `hooks` objects replace the user's (their
#     subkeys are arrays/objects that the template owns entirely).
#   - User-specific overrides should live in ~/.claude/settings.local.json,
#     which install.sh never touches.

LIVE_SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE_SETTINGS="$SCRIPT_DIR/settings.json"

if [ -f "$LIVE_SETTINGS" ]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="$LIVE_SETTINGS.bak.$ts"
  cp "$LIVE_SETTINGS" "$backup"
  echo "  Backed up existing settings.json -> $backup"

  tmp="$(mktemp)"
  if jq -s '.[0] * .[1]' "$LIVE_SETTINGS" "$TEMPLATE_SETTINGS" > "$tmp"; then
    mv "$tmp" "$LIVE_SETTINGS"
    echo "  Merged template into settings.json (existing MCP/keys preserved)"
  else
    rm -f "$tmp"
    echo "ERROR: jq merge failed. Live settings.json untouched; backup at $backup" >&2
    exit 1
  fi
else
  cp "$TEMPLATE_SETTINGS" "$LIVE_SETTINGS"
  echo "  Installed settings.json (no prior file found)"
fi

# --- CLAUDE.md ----------------------------------------------------------------
# Repo-managed. If the user wants their own additions, they should append into
# ~/.claude/CLAUDE.local.md (Claude Code reads both) rather than editing here.

if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && ! cmp -s "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"; then
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak.$ts"
  echo "  Backed up existing CLAUDE.md -> CLAUDE.md.bak.$ts"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "  Installed CLAUDE.md"

# --- hooks --------------------------------------------------------------------

if [ -d "$SCRIPT_DIR/hooks" ]; then
  mkdir -p "$CLAUDE_DIR/hooks"
  for hook_file in "$SCRIPT_DIR"/hooks/*.sh; do
    [ -e "$hook_file" ] || continue
    hook_name="$(basename "$hook_file")"
    cp "$hook_file" "$CLAUDE_DIR/hooks/$hook_name"
    chmod +x "$CLAUDE_DIR/hooks/$hook_name"
    if [ ! -x "$CLAUDE_DIR/hooks/$hook_name" ]; then
      echo "ERROR: $CLAUDE_DIR/hooks/$hook_name is not executable after chmod +x" >&2
      exit 1
    fi
  done
  echo "  Installed top-level hooks/*.sh"

  # hooks/lib/ — shared AST runner library. Mixed content (sh + js + py + go +
  # java). node_modules excluded; npm install runs locally to provision deps
  # matched to the target host's arch/runtime.
  if [ -d "$SCRIPT_DIR/hooks/lib" ]; then
    rm -rf "$CLAUDE_DIR/hooks/lib"
    mkdir -p "$CLAUDE_DIR/hooks/lib"
    for f in "$SCRIPT_DIR"/hooks/lib/*; do
      [ -e "$f" ] || continue
      [ "$(basename "$f")" = "node_modules" ] && continue
      if [ -d "$f" ]; then
        cp -r "$f" "$CLAUDE_DIR/hooks/lib/"
      else
        cp "$f" "$CLAUDE_DIR/hooks/lib/$(basename "$f")"
      fi
    done
    chmod +x "$CLAUDE_DIR/hooks/lib"/*.sh "$CLAUDE_DIR/hooks/lib"/*.js "$CLAUDE_DIR/hooks/lib"/*.py 2>/dev/null || true

    if [ -f "$CLAUDE_DIR/hooks/lib/package.json" ]; then
      if command -v npm >/dev/null 2>&1; then
        echo "  Installing AST library deps (npm)..."
        if ! (cd "$CLAUDE_DIR/hooks/lib" && npm install --silent --no-audit --no-fund --omit=dev >/dev/null 2>&1); then
          echo "  WARN: npm install failed — AST-based hooks will be skipped at runtime"
        fi
      else
        echo "  INFO: npm not on PATH — AST-based JS/TS hooks will be skipped at runtime"
      fi
    fi

    if [ -f "$CLAUDE_DIR/hooks/lib/ast-go-runner.go" ] && command -v go >/dev/null 2>&1; then
      mkdir -p "$CLAUDE_DIR/hooks/lib/go-build"
      go build -o "$CLAUDE_DIR/hooks/lib/go-build/ast-go-runner" \
        "$CLAUDE_DIR/hooks/lib/ast-go-runner.go" >/dev/null 2>&1 \
        || echo "  WARN: go build failed — Go AST hooks will fall back to 'go run' at runtime"
    fi

    # Java AST helper: skipped unless java + javac + mvn are all present.
    if [ -d "$CLAUDE_DIR/hooks/lib/java-src" ] && [ -f "$CLAUDE_DIR/hooks/lib/java-support/pom.xml" ] \
       && command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 && command -v mvn >/dev/null 2>&1; then
      mkdir -p "$CLAUDE_DIR/hooks/lib/java-lib" "$CLAUDE_DIR/hooks/lib/java-build"
      echo "  Installing Java AST deps (maven)..."
      log="$(mktemp)"
      if ! (cd "$CLAUDE_DIR/hooks/lib/java-support" \
            && mvn -q dependency:copy-dependencies -DoutputDirectory="$CLAUDE_DIR/hooks/lib/java-lib") \
            >"$log" 2>&1; then
        echo "  WARN: Maven dependency download failed — Java AST hooks will be skipped at runtime"
      elif ! javac -cp "$CLAUDE_DIR/hooks/lib/java-lib/*" \
             -d "$CLAUDE_DIR/hooks/lib/java-build" \
             "$CLAUDE_DIR/hooks/lib/java-src/AstJavaRunner.java" >"$log" 2>&1; then
        echo "  WARN: javac failed — Java AST hooks will be skipped at runtime"
      fi
      rm -f "$log"
    fi
    echo "  Installed hook lib"
  fi

  # Other hook subdirectories (ast-langs/, fingerprint-langs/).
  for plugin_subdir in "$SCRIPT_DIR"/hooks/*/; do
    [ -d "$plugin_subdir" ] || continue
    subdir_name="$(basename "$plugin_subdir")"
    [ "$subdir_name" = "lib" ] && continue
    rm -rf "$CLAUDE_DIR/hooks/$subdir_name"
    mkdir -p "$CLAUDE_DIR/hooks/$subdir_name"
    for plugin_file in "$plugin_subdir"*.sh; do
      [ -e "$plugin_file" ] || continue
      cp "$plugin_file" "$CLAUDE_DIR/hooks/$subdir_name/$(basename "$plugin_file")"
      chmod +x "$CLAUDE_DIR/hooks/$subdir_name/$(basename "$plugin_file")"
    done
    echo "  Installed hook plugins: $subdir_name/"
  done
fi

# --- skills -------------------------------------------------------------------
# Repo-managed. Built-in colliding names (simplify/explore/security-scan) have
# already been removed from the repo; if a user has manually added a skill of
# that name under ~/.claude/skills/, this loop does NOT touch it.

if [ -d "$SCRIPT_DIR/skills" ]; then
  mkdir -p "$CLAUDE_DIR/skills"
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest="$CLAUDE_DIR/skills/$skill_name"
    rm -rf "$dest"
    cp -r "${skill_dir%/}" "$CLAUDE_DIR/skills/"
    echo "  Installed skill: $skill_name"
  done
fi

# --- rules --------------------------------------------------------------------

if [ -d "$SCRIPT_DIR/rules" ]; then
  mkdir -p "$CLAUDE_DIR/rules"
  for rule_dir in "$SCRIPT_DIR"/rules/*/; do
    [ -d "$rule_dir" ] || continue
    rule_name="$(basename "$rule_dir")"
    dest="$CLAUDE_DIR/rules/$rule_name"
    rm -rf "$dest"
    cp -r "${rule_dir%/}" "$CLAUDE_DIR/rules/"
    echo "  Installed rules: $rule_name"
  done
fi

echo "Done."
echo ""
echo "Next steps:"
echo "  - Verify Ollama is running:    curl -sf http://localhost:11434/api/version"
echo "  - Pull pre-screening model:    ollama pull gpt-oss:120b"
echo "  - Override settings locally:   edit ~/.claude/settings.local.json"
