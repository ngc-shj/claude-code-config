#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# This repo is the source of truth for everything it manages. No .bak files
# are created — git history is the rollback mechanism. Any *.bak that already
# exists under ~/.claude/{,hooks,skills,rules}/ is removed so that stale skill
# backups do not shadow or duplicate the live skill in Claude Code's loader.

echo "Installing Claude Code settings..."

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
    echo "  Installed hook: $hook_name"
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
