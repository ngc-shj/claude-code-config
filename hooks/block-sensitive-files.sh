#!/bin/bash
# PreToolUse hook: Block Edit/Write to sensitive files
# Prevents accidental modification of secrets, lock files, and git internals

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

emit_block_early() {
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$1" | jq -Rs .)"
}

# Bash reaches the same files by a different door. The arms below inspect
# tool_input.file_path, which a shell command does not have, so `sed -i`, a `>`
# redirect, `cp`, `tee` and friends walked straight past every protection here —
# including a rewrite of this hook, after which anything is permitted.
#
# This is a TRIPWIRE, not a parser: deciding what an arbitrary shell command
# writes is undecidable in general (variables, eval, subshells, here-docs), and
# the other block-*.sh hooks in this directory are the same shape — substring
# matches on a dangerous verb near a dangerous target. It raises the cost of an
# accident and of a careless rewrite; it does not stop a determined bypass, and
# `~/.claude/settings.local.json` remains the sanctioned escape.
#
# Two conditions must BOTH hold, so read-only work on these paths stays free:
# the command names a protected path, and it carries a write verb.
if [ "$(echo "$INPUT" | jq -r '.tool_name // empty')" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  CLAUDE_DIR_RE='(\$HOME|~|/[Uu]sers/[^/ ]+|/home/[^/ ]+)/\.claude/(hooks|skills|rules)/|(\$HOME|~|/[Uu]sers/[^/ ]+|/home/[^/ ]+)/\.claude/(settings\.json|CLAUDE\.md|RTK\.md|model-routing\.md)'
  WRITE_RE='(^|[|;&[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|cp|mv|install|tee|truncate|rsync|chmod|chown|rm|ln|touch|dd)([[:space:]]|$)|>>?[[:space:]]*[^|;&]*\.claude/'
  if printf '%s' "$CMD" | grep -qE "$CLAUDE_DIR_RE" && printf '%s' "$CMD" | grep -qE "$WRITE_RE"; then
    emit_block_early "Blocked: this command writes into the installed harness under ~/.claude/. install.sh overwrites that tree, so the edit is reverted on the next install — and a session that rewrites its own hooks can disable the tripwires meant to catch it. Edit the repo claude-code-config and run \`bash ./install.sh\`; use ~/.claude/settings.local.json for local overrides. (This is a heuristic guard on the Bash tool: it pairs a protected path with a write verb, so reading, grepping and running these files is unaffected.)"
    exit 0
  fi
  echo '{"decision": "approve"}'
  exit 0
fi

if [ -z "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

# Emit a block decision with the reason JSON-encoded by jq. Direct shell
# interpolation of `$BASENAME` into the reason string is unsafe: a crafted
# tool_input.file_path containing `"` characters produces malformed JSON,
# and a fail-open harness would then bypass this hook entirely. Mirrors the
# pattern used by the other block-*.sh hooks in this directory.
emit_block() {
  local reason="$1"
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$reason" | jq -Rs .)"
}

# Block patterns
case "$BASENAME" in
  .env|.env.local|.env.production|.env.staging)
    emit_block "Blocked: editing environment file ${BASENAME} which may contain secrets"
    exit 0
    ;;
  .env.*)
    # Allow .env.example (template without secrets)
    if [ "$BASENAME" = ".env.example" ]; then
      echo '{"decision": "approve"}'
      exit 0
    fi
    emit_block "Blocked: editing environment file ${BASENAME} which may contain secrets"
    exit 0
    ;;
  credentials.json|secrets.yaml|secrets.yml|*.pem|*.key|id_rsa|id_ed25519)
    emit_block "Blocked: editing credential/key file ${BASENAME}"
    exit 0
    ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|bun.lock)
    emit_block "Blocked: lock files should only be modified by package managers, not edited directly"
    exit 0
    ;;
esac

# Block .git internals
case "$FILE_PATH" in
  */.git/*|.git/*)
    emit_block "Blocked: editing git internals is dangerous"
    exit 0
    ;;
esac

# Block Claude Code harness configuration that is repo-managed. A session
# that edits its own hook script can no-op a tripwire (e.g.,
# block-destructive-docker.sh) and then issue the destructive operation
# the hook was meant to catch. The repo at ~/ghq/github.com/ngc-shj/
# claude-code-config/ is the source of truth — edits belong there, then
# `bash ./install.sh` syncs into ~/.claude/.
#
# Intentionally NOT blocked: ~/.claude/settings.local.json — that is the
# documented override path (it is NOT overwritten by install.sh) and is
# the only sanctioned way to disable a hook locally without modifying
# the repo. See block-destructive-docker.sh's reason message for the
# canonical override workflow.
#
# Normalize $HOME once, for every arm below: a trailing slash in $HOME
# (e.g. HOME=/home/user/) would otherwise turn "$HOME/.claude/..." into
# "…//.claude/…", which never matches the single-slash path the tool
# reports, so the guard silently fails open. ${HOME:?} turns an unset
# $HOME into a stated precondition instead of a mid-case crash under
# `set -euo pipefail`.
CLAUDE_HOME="${HOME:?}"; CLAUDE_HOME="${CLAUDE_HOME%/}/.claude"
# One copy, used by both the expanded and the literal-tilde arm. The two
# harness-config arms below carry deliberately different wording, but an
# identical message duplicated across arms drifts silently — and only the arm a
# fixture happens to exercise would catch it.
SKILLS_BLOCK_REASON="Blocked: editing an installed skill under ~/.claude/skills/ directly. If this skill is repo-managed, edit it in the claude-code-config repo and run \`bash ./install.sh\`. If it has no repo source (install.sh only removes and re-copies the skills it manages, so an unmanaged skill survives every install untouched), add it to the repo's skills/ directory, or exempt it via ~/.claude/settings.local.json."
# The guarded set is DERIVED from install.sh's write set, not from the paths
# that happened to come up. install.sh overwrites, unconditionally:
#   :79  CLAUDE.md            :84-85   RTK.md, model-routing.md
#   :106 hooks/*.sh           :122-133 hooks/lib/* (any type)
#   :210-218 hooks/<plugin-subdir>/*   :233-235 skills/<name>/
#   :248-250 rules/<name>/    settings.json
# hooks/ is matched without a .sh restriction because install.sh rm -rf's and
# re-copies hooks/lib/ wholesale — ast-runner.js and its siblings are the AST
# engine behind the detection hooks, i.e. exactly the "a session that edits its
# own hook script can no-op a tripwire" case this guard's comment cites.
# rules/ is the same `rm -rf "$dest"; cp -r` shape as skills/, and
# rules/common/*.md is auto-injected into every session — a session editing it
# rewrites the standing instructions it runs under, and the edit vanishes at the
# next install. Note what is deliberately NOT here: ~/.claude/projects/*/memory/
# and settings.local.json are not install-managed, so blocking them would break
# legitimate writes.
# Match the canonical path as well as the raw one. A literal `case` comparison
# treats `//`, `/./`, an intermediate `..`, and a symlink alias as different
# strings from the path they name, so each was an approve on a file the arms
# below are meant to guard — reproduced for all four forms. Resolve the deepest
# existing ancestor physically (`cd -P`, which also chases symlinks) and
# re-attach the part that does not exist yet, so a write to a not-yet-created
# file under a guarded directory is still matched. `realpath -m` would be
# shorter but is GNU-only; this shape is the one hooks/retro-prescreen.sh
# already uses. Relative paths cannot be resolved here — the hook is not told
# the tool's working directory — so they fall through to the literal arms.
# Lexical pass first, so the literal-tilde arms (which can never be resolved
# against the filesystem) also see `~/.claude/./skills/...` as what it names.
LEX_PATH=$(printf '%s' "$FILE_PATH" | awk '
  {
    gsub(/\/+/, "/")            # //  -> /
    while (sub(/\/\.\//, "/")) {}   # /./ -> /
    sub(/\/\.$/, "/")
    while (match($0, /\/[^\/]+\/\.\.(\/|$)/)) {   # a/b/../c -> a/c, lexically
      pre = substr($0, 1, RSTART - 1)
      post = substr($0, RSTART + RLENGTH - 1)
      if (post == "/") post = ""
      $0 = pre post
      if ($0 == "") $0 = "/"
    }
    print
  }')
[ -n "$LEX_PATH" ] || LEX_PATH="$FILE_PATH"

CANON_PATH=""
case "$LEX_PATH" in
  /*)
    _dir="$LEX_PATH"; _tail=""
    while [ -n "$_dir" ] && [ "$_dir" != "/" ] && [ ! -d "$_dir" ]; do
      _tail="$(basename -- "$_dir")${_tail:+/$_tail}"
      _dir="$(dirname -- "$_dir")"
    done
    if _res="$(cd -P -- "$_dir" 2>/dev/null && pwd -P)"; then
      _res="${_res%/}"
      CANON_PATH="${_res}${_tail:+/$_tail}"
    fi
    ;;
esac
# Never let an unresolvable path silently become the empty string and match
# nothing meaningful; fall back to the raw path so the arms still see something.
[ -n "$CANON_PATH" ] || CANON_PATH="$FILE_PATH"

case "$LEX_PATH" in
  "$CLAUDE_HOME/hooks/"*|"$CLAUDE_HOME/settings.json"|"$CLAUDE_HOME/CLAUDE.md"|"$CLAUDE_HOME/rules/"*|"$CLAUDE_HOME/RTK.md"|"$CLAUDE_HOME/model-routing.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly. The repo claude-code-config is the source of truth — edit there and run \`bash ./install.sh\`. To override a hook locally, use ~/.claude/settings.local.json (which is NOT blocked)."
    exit 0
    ;;
  "$CLAUDE_HOME/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
  "~/.claude/hooks/"*|"~/.claude/settings.json"|"~/.claude/CLAUDE.md"|"~/.claude/rules/"*|"~/.claude/RTK.md"|"~/.claude/model-routing.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly. Edit the repo claude-code-config and run \`bash ./install.sh\`. Use ~/.claude/settings.local.json for local overrides."
    exit 0
    ;;
  "~/.claude/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
esac

# Second pass over the canonical form. Kept as a separate case rather than
# `case "$FILE_PATH$CANON_PATH"` so each arm stays a plain literal a reader can
# check against install.sh's write set.
case "$CANON_PATH" in
  "$CLAUDE_HOME/hooks/"*|"$CLAUDE_HOME/settings.json"|"$CLAUDE_HOME/CLAUDE.md"|"$CLAUDE_HOME/rules/"*|"$CLAUDE_HOME/RTK.md"|"$CLAUDE_HOME/model-routing.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly (path resolves under the installed harness). The repo claude-code-config is the source of truth — edit there and run \`bash ./install.sh\`. To override a hook locally, use ~/.claude/settings.local.json (which is NOT blocked)."
    exit 0
    ;;
  "$CLAUDE_HOME/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
esac

echo '{"decision": "approve"}'
