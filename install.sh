#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing Claude Code settings..."

# Create ~/.claude if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Install settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  echo "  ~/.claude/settings.json already exists. Backing up to settings.json.bak"
  cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak"
fi
cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
echo "  Installed settings.json"

# Install CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  echo "  ~/.claude/CLAUDE.md already exists. Backing up to CLAUDE.md.bak"
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "  Installed CLAUDE.md"

# Install hooks
if [ -d "$SCRIPT_DIR/hooks" ]; then
  mkdir -p "$CLAUDE_DIR/hooks"
  for hook_file in "$SCRIPT_DIR"/hooks/*.sh; do
    hook_name="$(basename "$hook_file")"
    if [ -f "$CLAUDE_DIR/hooks/$hook_name" ]; then
      echo "  ~/.claude/hooks/$hook_name already exists. Backing up to ${hook_name}.bak"
      cp "$CLAUDE_DIR/hooks/$hook_name" "$CLAUDE_DIR/hooks/${hook_name}.bak"
    fi
    cp "$hook_file" "$CLAUDE_DIR/hooks/$hook_name"
    chmod +x "$CLAUDE_DIR/hooks/$hook_name"
    echo "  Installed hook: $hook_name"
  done
fi

# Install skills
if [ -d "$SCRIPT_DIR/skills" ]; then
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    dest="$CLAUDE_DIR/skills/$skill_name"
    mkdir -p "$dest"
    if [ -f "$dest/SKILL.md" ]; then
      echo "  ~/.claude/skills/$skill_name/SKILL.md already exists. Backing up to SKILL.md.bak"
      cp "$dest/SKILL.md" "$dest/SKILL.md.bak"
    fi
    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
    echo "  Installed skill: $skill_name"
  done
fi

# Install rules
# Layered: common/ baseline + language-specific overlays. Claude references
# these via CLAUDE.md when editing matching files.
if [ -d "$SCRIPT_DIR/rules" ]; then
  for rule_dir in "$SCRIPT_DIR"/rules/*/; do
    rule_name="$(basename "$rule_dir")"
    dest="$CLAUDE_DIR/rules/$rule_name"
    if [ -d "$dest" ]; then
      echo "  ~/.claude/rules/$rule_name already exists. Backing up to ${rule_name}.bak"
      rm -rf "$dest.bak"
      cp -r "$dest" "$dest.bak"
    fi
    mkdir -p "$dest"
    cp "$rule_dir"*.md "$dest/"
    echo "  Installed rules: $rule_name"
  done
fi

echo "Done."
