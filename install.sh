#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# This repo is the source of truth for everything it manages. No .bak files
# are created — git history is the rollback mechanism. Any *.bak that already
# exists under ~/.claude/{,hooks,skills,rules}/ is removed so that stale skill
# backups do not shadow or duplicate the live skill in Claude Code's loader.

echo "Installing Claude Code settings..."

# Pre-flight: validate settings.json is well-formed before touching anything.
# A malformed settings.json silently breaks the harness on next launch
# (hooks stop firing, permissions revert to defaults). Catching this at
# install time, before we overwrite the live ~/.claude/settings.json,
# preserves the previous good copy.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for install-time settings.json validation but is not on PATH." >&2
  exit 1
fi
if ! jq empty "$SCRIPT_DIR/settings.json" 2>/dev/null; then
  echo "ERROR: $SCRIPT_DIR/settings.json is not valid JSON. Refusing to install — fix the source file first." >&2
  echo "Run: jq empty $SCRIPT_DIR/settings.json   # to see the parse error." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

# Install settings.json
cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
rm -f "$CLAUDE_DIR/settings.json.bak"
echo "  Installed settings.json"

# Install CLAUDE.md
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
rm -f "$CLAUDE_DIR/CLAUDE.md.bak"
echo "  Installed CLAUDE.md"

# Install hooks
if [ -d "$SCRIPT_DIR/hooks" ]; then
  mkdir -p "$CLAUDE_DIR/hooks"
  rm -f "$CLAUDE_DIR/hooks"/*.bak
  for hook_file in "$SCRIPT_DIR"/hooks/*.sh; do
    hook_name="$(basename "$hook_file")"
    cp "$hook_file" "$CLAUDE_DIR/hooks/$hook_name"
    chmod +x "$CLAUDE_DIR/hooks/$hook_name"
    # Post-install verify: the hook is executable. A non-executable hook
    # fails silently at PreToolUse time (Claude Code may either skip it or
    # error inconsistently across versions); fail loudly here instead.
    if [ ! -x "$CLAUDE_DIR/hooks/$hook_name" ]; then
      echo "ERROR: $CLAUDE_DIR/hooks/$hook_name is not executable after chmod +x" >&2
      exit 1
    fi
    echo "  Installed hook: $hook_name"
  done
  # Hook plugin subdirectories (e.g. fingerprint-langs/). Each subdir is
  # mirrored as-is. Stale destination contents are wiped before copy so
  # plugins removed upstream don't linger as shadow registrations.
  for plugin_subdir in "$SCRIPT_DIR"/hooks/*/; do
    [ -d "$plugin_subdir" ] || continue
    subdir_name="$(basename "$plugin_subdir")"
    rm -rf "$CLAUDE_DIR/hooks/$subdir_name"
    mkdir -p "$CLAUDE_DIR/hooks/$subdir_name"
    for plugin_file in "$plugin_subdir"*.sh; do
      [ -e "$plugin_file" ] || continue
      plugin_name="$(basename "$plugin_file")"
      cp "$plugin_file" "$CLAUDE_DIR/hooks/$subdir_name/$plugin_name"
      chmod +x "$CLAUDE_DIR/hooks/$subdir_name/$plugin_name"
    done
    echo "  Installed hook plugins: $subdir_name/"
  done
fi

# Install skills
# Skills are directory trees. Stale .bak directories must be removed — they
# contain SKILL.md and get loaded as shadow skills otherwise.
if [ -d "$SCRIPT_DIR/skills" ]; then
  mkdir -p "$CLAUDE_DIR/skills"
  rm -rf "$CLAUDE_DIR/skills"/*.bak
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    dest="$CLAUDE_DIR/skills/$skill_name"
    rm -rf "$dest"
    cp -r "${skill_dir%/}" "$CLAUDE_DIR/skills/"
    echo "  Installed skill: $skill_name"
  done
fi

# Install rules
# Layered: common/ baseline + language-specific overlays. Claude references
# these via CLAUDE.md when editing matching files.
if [ -d "$SCRIPT_DIR/rules" ]; then
  mkdir -p "$CLAUDE_DIR/rules"
  rm -rf "$CLAUDE_DIR/rules"/*.bak
  for rule_dir in "$SCRIPT_DIR"/rules/*/; do
    rule_name="$(basename "$rule_dir")"
    dest="$CLAUDE_DIR/rules/$rule_name"
    rm -rf "$dest"
    cp -r "${rule_dir%/}" "$CLAUDE_DIR/rules/"
    echo "  Installed rules: $rule_name"
  done
fi

echo "Done."
