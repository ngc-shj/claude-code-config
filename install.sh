#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# This repo is the source of truth for everything it manages. CLAUDE.md, hooks,
# skills, and rules are overwritten on install — git history is the rollback
# mechanism, so no .bak files are kept for them. Any *.bak that already exists
# under ~/.claude/{,hooks,skills,rules}/ is removed so that stale skill backups
# do not shadow or duplicate the live skill in Claude Code's loader.
#
# settings.json is the exception: it is MERGED rather than overwritten, so that
# user-managed top-level keys the template does not own (mcpServers, etc.) are
# preserved. A timestamped backup is written before each merge.

echo "Installing Claude Code settings..."

# Pre-flight: validate settings.json is well-formed before touching anything.
# A malformed settings.json silently breaks the harness on next launch
# (hooks stop firing, permissions revert to defaults). Catching this at
# install time, before we touch the live ~/.claude/settings.json, preserves
# the previous good copy.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for settings.json validation and merge but is not on PATH." >&2
  exit 1
fi
if ! jq empty "$SCRIPT_DIR/settings.json" 2>/dev/null; then
  echo "ERROR: $SCRIPT_DIR/settings.json is not valid JSON. Refusing to install — fix the source file first." >&2
  echo "Run: jq empty $SCRIPT_DIR/settings.json   # to see the parse error." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

# Install settings.json by MERGING into the existing live file:
#   jq -s '.[1] as $t | (.[0] * .[1]) | .permissions = $t.permissions | .hooks = $t.hooks'
#   - The user's top-level keys the template does not own (mcpServers, ...) are kept.
#   - `permissions` and `hooks` are template-owned: they are replaced WHOLESALE
#     (not deep-merged), so a stale user sub-key or an unmanaged hook event in
#     the live file cannot survive into the merged result.
#   - Local-only overrides belong in ~/.claude/settings.local.json, which this
#     installer never touches.
# Only a valid JSON OBJECT is merged; an empty/garbage/non-object live file is
# backed up and replaced (jq `*` errors on null/array operands). A timestamped
# backup is written first so the operation is always reversible.
LIVE_SETTINGS="$CLAUDE_DIR/settings.json"
backup_live_settings() {
  backup="$LIVE_SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$LIVE_SETTINGS" "$backup"
  chmod 600 "$backup" 2>/dev/null || true  # may carry mcpServers env secrets
}
if [ -f "$LIVE_SETTINGS" ] && jq -e 'type == "object"' "$LIVE_SETTINGS" >/dev/null 2>&1; then
  backup_live_settings
  tmp="$(mktemp)"
  if jq -s '.[1] as $t | (.[0] * .[1]) | .permissions = $t.permissions | .hooks = $t.hooks' \
       "$LIVE_SETTINGS" "$SCRIPT_DIR/settings.json" > "$tmp"; then
    mv "$tmp" "$LIVE_SETTINGS"
    echo "  Merged settings.json (backup: $backup)"
  else
    rm -f "$tmp"
    echo "ERROR: jq merge failed. Live settings.json left untouched; backup at $backup" >&2
    exit 1
  fi
elif [ -f "$LIVE_SETTINGS" ]; then
  # Present but not a usable JSON object — preserve it, then install fresh.
  backup_live_settings
  cp "$SCRIPT_DIR/settings.json" "$LIVE_SETTINGS"
  echo "  Replaced non-object settings.json (backup: $backup)"
else
  cp "$SCRIPT_DIR/settings.json" "$LIVE_SETTINGS"
  echo "  Installed settings.json"
fi

# Install CLAUDE.md
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
rm -f "$CLAUDE_DIR/CLAUDE.md.bak"
echo "  Installed CLAUDE.md"

# Install hooks
if [ -d "$SCRIPT_DIR/hooks" ]; then
  mkdir -p "$CLAUDE_DIR/hooks"
  rm -f "$CLAUDE_DIR/hooks"/*.bak
  # Source-of-truth sync: remove any top-level installed hook script that no
  # longer exists in the source, so renamed/deleted hooks do not linger as stale
  # dead files (e.g. an old ollama-utils.sh after it became llm-commands.sh).
  # Only top-level *.sh are managed here; hooks/lib/ and subdirs are handled below.
  for live_hook in "$CLAUDE_DIR/hooks"/*.sh; do
    [ -e "$live_hook" ] || continue
    if [ ! -f "$SCRIPT_DIR/hooks/$(basename "$live_hook")" ]; then
      rm -f "$live_hook"
      echo "  Removed stale hook: $(basename "$live_hook")"
    fi
  done
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
  # hooks/lib/ — shared library directory (AST runner + bash dispatch).
  # Distinct from plugin subdirs because it carries non-shell content
  # (.js + package.json) and a Node-managed node_modules/. Handled before
  # the generic plugin-subdir loop so that loop can skip it.
  if [ -d "$SCRIPT_DIR/hooks/lib" ]; then
    rm -rf "$CLAUDE_DIR/hooks/lib"
    mkdir -p "$CLAUDE_DIR/hooks/lib"
    # Copy every helper except node_modules — runtimes may include JS,
    # Python, Go, and Java helper sources. Dependencies are rebuilt on
    # the target host so architecture/runtime versions stay aligned.
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

    # Provision Node deps. node + npm are OPTIONAL — if missing, the
    # AST-based hook categories silently skip at runtime and the regex
    # categories still run. We deliberately do NOT fail the install,
    # because users who don't need AST features should still be able to
    # install hooks/skills/rules.
    if [ -f "$CLAUDE_DIR/hooks/lib/package.json" ]; then
      if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        echo "  Installing AST library deps (npm)..."
        if ! (cd "$CLAUDE_DIR/hooks/lib" && npm install --silent --no-audit --no-fund --omit=dev >/dev/null 2>&1); then
          echo "  WARN: npm install failed — AST-based hooks will be skipped at runtime"
        fi
      else
        echo "  INFO: node/npm not on PATH — AST-based hooks will be skipped at runtime"
      fi
    fi

    # Provision a compiled Go helper when Go is available. Fallback stays
    # `go run` so non-Go hosts still degrade gracefully.
    if [ -f "$CLAUDE_DIR/hooks/lib/ast-go-runner.go" ]; then
      if command -v go >/dev/null 2>&1; then
        mkdir -p "$CLAUDE_DIR/hooks/lib/go-build"
        echo "  Building Go AST helper..."
        if ! go build -o "$CLAUDE_DIR/hooks/lib/go-build/ast-go-runner" "$CLAUDE_DIR/hooks/lib/ast-go-runner.go" >/dev/null 2>&1; then
          echo "  WARN: go build failed — Go AST hooks will fall back to go run at runtime"
        fi
      else
        echo "  INFO: go not on PATH — Go AST hooks will use go run when available"
      fi
    fi

    # Provision JavaParser support for Java AST extraction. Java is
    # OPTIONAL — compile only when java/javac/maven are all present.
    # Maven and javac stderr are captured to a log so failures can be
    # diagnosed (silencing them previously hid environment-specific
    # compile errors entirely).
    if [ -d "$CLAUDE_DIR/hooks/lib/java-src" ] && [ -f "$CLAUDE_DIR/hooks/lib/java-support/pom.xml" ]; then
      if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 && command -v mvn >/dev/null 2>&1; then
        mkdir -p "$CLAUDE_DIR/hooks/lib/java-lib" "$CLAUDE_DIR/hooks/lib/java-build"
        echo "  Installing Java AST deps (maven)..."
        echo "  INFO: first-time Maven download may take a moment"
        java_provision_log="$(mktemp)"
        if ! (cd "$CLAUDE_DIR/hooks/lib/java-support" \
              && mvn -q dependency:copy-dependencies -DoutputDirectory="$CLAUDE_DIR/hooks/lib/java-lib") \
              >"$java_provision_log" 2>&1; then
          echo "  WARN: Maven dependency download failed — Java AST hooks will be skipped at runtime"
          echo "  ---- Maven output ----"
          sed 's/^/    /' "$java_provision_log"
          echo "  ----------------------"
        elif ! javac -cp "$CLAUDE_DIR/hooks/lib/java-lib/*" \
               -d "$CLAUDE_DIR/hooks/lib/java-build" \
               "$CLAUDE_DIR/hooks/lib/java-src/AstJavaRunner.java" \
               >"$java_provision_log" 2>&1; then
          echo "  WARN: javac failed — Java AST hooks will be skipped at runtime"
          echo "  ---- javac output ----"
          sed 's/^/    /' "$java_provision_log"
          echo "  ----------------------"
        fi
        rm -f "$java_provision_log"
      else
        echo "  INFO: java/javac/mvn not fully available — Java AST hooks will be skipped at runtime"
      fi
    fi
    echo "  Installed hook lib: lib/"
  fi

  # Hook plugin subdirectories (e.g. fingerprint-langs/, ast-langs/). Each
  # subdir is mirrored as-is. Stale destination contents are wiped before
  # copy so plugins removed upstream don't linger as shadow registrations.
  for plugin_subdir in "$SCRIPT_DIR"/hooks/*/; do
    [ -d "$plugin_subdir" ] || continue
    subdir_name="$(basename "$plugin_subdir")"
    # `lib/` is handled separately above (mixed-content directory + npm
    # provisioning). Skip here to avoid the rm -rf clobbering its
    # node_modules.
    [ "$subdir_name" = "lib" ] && continue
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

# Retrospect state directory. User-owned durable state (high-water cursors)
# lives here; the installer only guarantees the directory exists with safe
# permissions — it never writes, copies, or removes anything inside it, and
# never installs the retrospect config (that file is user-created by copying
# retrospect.config.json.example).
mkdir -p -m 0700 "$CLAUDE_DIR/state"
if [ ! -f "$CLAUDE_DIR/retrospect.config.json" ]; then
  echo "  Note: retrospective mining is disabled — to enable, copy retrospect.config.json.example to $CLAUDE_DIR/retrospect.config.json and edit it (see README)"
fi

echo "Done."
