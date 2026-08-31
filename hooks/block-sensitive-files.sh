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
# This is a TRIPWIRE, not a security boundary. Deciding what an arbitrary shell
# command writes is undecidable in general, and the gap is not academic — all of
# these reach a guarded file and NONE is detected here:
#
#   VAR=~/.claude/hooks/x.sh; echo y > "$VAR"     # indirection through a variable
#   eval "$(printf 'ec%s' 'ho y > ~/.claude/hooks/x.sh')"   # eval / constructed
#   bash -c 'cat > ~/.claude/hooks/x.sh <<< y'    # nested interpreter
#   python3 -c 'open("...","w").write("y")'       # any language's file API
#   cd ~/.claude/hooks && echo y > x.sh           # cwd-relative, no path match
#
# The matcher below closes the *spellings that came up in review* (long and
# bundled in-place flags, `$HOME` and `~` forms, `//`, and cp/mv write
# direction). It raises the cost of an accident and of a careless self-rewrite.
# It does NOT stop a determined bypass, and must not be relied on as though it
# did: the real containment is that install.sh overwrites this tree, so any edge
# case that slips through is reverted at the next install.
# A project's `.claude/settings.local.json` remains the sanctioned escape — the
# user-level spelling of that filename is not a settings source at all.
#
# Two conditions must BOTH hold, so read-only work on these paths stays free:
# the command names a protected path, and it carries a write verb — except for
# cp/mv/ln/rsync/install, where only a guarded DESTINATION counts, so reading
# out of the tree is not a false positive.
if [ "$(echo "$INPUT" | jq -r '.tool_name // empty')" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  # Normalize before matching, so trivial spellings of the same path are not
  # separate holes: `"$HOME"/.claude/...` and `~/.claude//hooks/...` both named
  # a guarded file and both were approve. Quote removal is deliberately crude —
  # it is a tripwire input, not a shell parse.
  NCMD=$(printf '%s' "$CMD" \
    | sed -e 's/"\$HOME"/$HOME/g; s/'"'"'\$HOME'"'"'/$HOME/g; s/${HOME}/$HOME/g' \
    | sed -e "s#\\\$HOME#${HOME%/}#g" \
    | sed -e 's#//*#/#g')
  CLAUDE_DIR_RE='(\$HOME|~|/[Uu]sers/[^/ ]+|/home/[^/ ]+)/\.claude/(hooks|skills|rules)/|(\$HOME|~|/[Uu]sers/[^/ ]+|/home/[^/ ]+)/\.claude/(settings\.json|CLAUDE\.md|RTK\.md|model-routing\.md)'
  # In-place editors: the flag may be long (`--in-place`), bundled (`-pi`), or
  # carry a backup suffix (`-i.bak`), and perl/ruby/python spell it their own
  # way. Anchored on the interpreter name so a bare `-i` elsewhere is not a hit.
  INPLACE_RE='(^|[|;&[:space:]])(sed|perl|ruby|gawk|awk)([[:space:]]+-[^[:space:]]*)*[[:space:]]+(-[a-zA-Z]*i[a-zA-Z]*([.=][^[:space:]]*)?|--in-place([=][^[:space:]]*)?)([[:space:]]|$)'
  WRITE_RE='(^|[|;&[:space:]])(mv|install|tee|truncate|rsync|chmod|chown|rm|ln|touch|dd|shred|split|patch|unzip|tar)([[:space:]]|$)|>>?[[:space:]]*[^|;&]*\.claude/'
  # cp/ln/rsync/install write to their LAST argument, so a read-only backup OUT
  # of the guarded tree (`cp ~/.claude/hooks/x.sh /tmp/`) was blocked while a
  # write IN was missed once the source made the path match. Judge direction:
  # only a guarded final argument counts. Options and the source list are
  # ignored. `mv` is deliberately NOT in this set — it mutates its SOURCE too,
  # so moving a guarded file out is a deletion from the tree, and it stays in
  # WRITE_RE where either side triggers.
  DEST_HIT=0
  if printf '%s' "$NCMD" | grep -qE '(^|[|;&[:space:]])(cp|ln|rsync|install)([[:space:]]|$)'; then
    # Split on shell separators; for each segment starting with one of these
    # verbs, test only its final word.
    while IFS= read -r _seg; do
      case "$(printf '%s' "$_seg" | awk '{print $1}')" in
        cp|ln|rsync|install)
          _last=$(printf '%s' "$_seg" | awk '{print $NF}')
          if printf '%s' "$_last" | grep -qE "$CLAUDE_DIR_RE"; then DEST_HIT=1; fi
          ;;
      esac
    done <<EOF
$(printf '%s' "$NCMD" | tr '|;&' '\n\n\n' | sed 's/^[[:space:]]*//')
EOF
  fi
  if { printf '%s' "$NCMD" | grep -qE "$CLAUDE_DIR_RE" \
       && { printf '%s' "$NCMD" | grep -qE "$WRITE_RE" || printf '%s' "$NCMD" | grep -qE "$INPLACE_RE"; }; } \
     || [ "$DEST_HIT" -eq 1 ]; then
    emit_block_early "Blocked: this command writes into the installed harness under ~/.claude/. install.sh overwrites that tree, so the edit is reverted on the next install — and a session that rewrites its own hooks can disable the tripwires meant to catch it. Edit the repo claude-code-config and run \`bash ./install.sh\`; use a project .claude/settings.local.json for local overrides — a user-level settings.local.json is not a settings source, and machine-wide env belongs in the user settings.json, which the install merge preserves. (This is a heuristic guard on the Bash tool: it pairs a protected path with a write verb, so reading, grepping and running these files is unaffected.)"
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
# Intentionally NOT blocked: ~/.claude/settings.local.json — install.sh does
# not manage it, so blocking it would serve nothing. Note that Claude Code does
# not READ a settings.local.json at the user level either (it resolves user
# ~/.claude/settings.json, project .claude/settings.json, and project-local
# .claude/settings.local.json), so the local override that actually takes
# effect is the project-scoped one. See block-destructive-docker.sh's reason
# message for the canonical override workflow.
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
SKILLS_BLOCK_REASON="Blocked: editing an installed skill under ~/.claude/skills/ directly. If this skill is repo-managed, edit it in the claude-code-config repo and run \`bash ./install.sh\`. If it has no repo source (install.sh only removes and re-copies the skills it manages, so an unmanaged skill survives every install untouched), add it to the repo's skills/ directory, or exempt it via a project .claude/settings.local.json (the user-level spelling of that filename is not read)."
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
# already uses. A RELATIVE path is made absolute against the hook's own working
# directory first: the harness runs the hook in the session's cwd, so
# `../../../../.claude/hooks/x.sh` names a real installed hook and was an
# approve.
#
# A leading `~` is EXPANDED here rather than treated as unresolvable. Earlier
# revisions kept literal-tilde paths out of physical resolution and judged them
# by string alone, which cost both directions at once: `~/alias.sh` pointing at
# an installed hook was an approve, and `~/.claude/skills/out-link/../x` whose
# link leaves the tree was a block. The tilde has exactly one meaning — `$HOME`
# — and this hook accepts the spelling as valid input, so expanding it is not a
# guess. With every form absolute, resolution answers every question and the
# string-matching pass that used to exist alongside it is gone.
#
# `~user/...` is deliberately NOT expanded: resolving another account's home
# needs a passwd lookup, the tool does not emit that form, and leaving it
# unmatched is the conservative direction for a path this guard has no business
# reasoning about.
ABS_PATH="$FILE_PATH"
case "$ABS_PATH" in
  "~")   ABS_PATH="${HOME%/}" ;;
  "~/"*) ABS_PATH="${HOME%/}/${ABS_PATH#\~/}" ;;
  "~"*)  : ;;
  /*)    : ;;
  *)     ABS_PATH="$(pwd -P)/$ABS_PATH" ;;
esac

# Physical resolution runs on ABS_PATH, NOT on the lexically-collapsed form.
# `a/b/../c` equals `a/c` only when `b` is a real directory: if `b` is a
# symlink, `..` names the parent of its TARGET, so collapsing first rewrites
# the path to a different file. Reproduced — a link to `~/.claude/skills`
# followed by `..` resolves into `~/.claude/hooks`, while the collapsed form
# pointed at the link's own parent and approved the write. `cd -P` gets this
# right for free because the kernel resolves each component in order, so the
# un-collapsed path is both the correct input and the simpler one — and, once
# the tilde is expanded above, the only one: there is no longer a form the
# filesystem cannot answer, so no lexical pass survives beside this.
CANON_PATH=""
case "$ABS_PATH" in
  /*)
    _dir="$ABS_PATH"; _tail=""
    while [ -n "$_dir" ] && [ "$_dir" != "/" ] && [ ! -d "$_dir" ]; do
      _tail="$(basename -- "$_dir")${_tail:+/$_tail}"
      _dir="$(dirname -- "$_dir")"
    done
    if _res="$(cd -P -- "$_dir" 2>/dev/null && pwd -P)"; then
      _res="${_res%/}"
      CANON_PATH="${_res}${_tail:+/$_tail}"
      # `cd -P` resolves symlinked DIRECTORY components only; a symlinked LEAF
      # survives as its own path, so `/tmp/alias.sh -> ~/.claude/hooks/x.sh` was
      # an approve on a guarded file. Chase the whole chain, re-resolving the
      # containing directory each hop — one readlink is defeated by two links —
      # under a 40-hop cap. Same shape as `_containment_check` in
      # hooks/retro-prescreen.sh. Unlike a containment gate there is no
      # fail-closed direction to take here: a path we cannot resolve simply
      # keeps its last known form and is judged by the arms below.
      _hops=0
      while [ -L "$CANON_PATH" ] && [ "$_hops" -lt 40 ]; do
        _link="$(readlink "$CANON_PATH")" || break
        case "$_link" in
          /*) : ;;
          *) _link="$(dirname -- "$CANON_PATH")/$_link" ;;
        esac
        _ldir="$(dirname -- "$_link")"
        _lres="$(cd -P -- "$_ldir" 2>/dev/null && pwd -P)" || break
        [ -n "$_lres" ] || break
        CANON_PATH="${_lres%/}/$(basename -- "$_link")"
        _hops=$((_hops + 1))
      done
    fi
    ;;
esac
# Never let an unresolvable path silently become the empty string and match
# nothing meaningful; fall back to the raw path so the arms still see something.
[ -n "$CANON_PATH" ] || CANON_PATH="$FILE_PATH"

# The guarded root has to be physical too. CANON_PATH is fully resolved, so a
# symlinked $HOME (or a symlinked ~/.claude) leaves the arms holding one
# spelling and the path holding the other, and every resolved path misses.
# Both forms are matched below, since the tool may report either.
CLAUDE_HOME_PHYS="$CLAUDE_HOME"
if _res="$(cd -P -- "$CLAUDE_HOME" 2>/dev/null && pwd -P)"; then
  CLAUDE_HOME_PHYS="${_res%/}"
fi

# The resolved path is the single authority. There is no string-matching pass
# beside it any more: every input form is made absolute above, so the filesystem
# can answer for all of them, and two judges of the same question were how both
# the `~/alias` bypass and the `..`-through-a-symlink over-block survived. Kept as a separate case rather than
# `case "$FILE_PATH$CANON_PATH"` so each arm stays a plain literal a reader can
# check against install.sh's write set.
case "$CANON_PATH" in
  "$CLAUDE_HOME/hooks/"*|"$CLAUDE_HOME/settings.json"|"$CLAUDE_HOME/CLAUDE.md"|"$CLAUDE_HOME/rules/"*|"$CLAUDE_HOME/RTK.md"|"$CLAUDE_HOME/model-routing.md"|\
  "$CLAUDE_HOME_PHYS/hooks/"*|"$CLAUDE_HOME_PHYS/settings.json"|"$CLAUDE_HOME_PHYS/CLAUDE.md"|"$CLAUDE_HOME_PHYS/rules/"*|"$CLAUDE_HOME_PHYS/RTK.md"|"$CLAUDE_HOME_PHYS/model-routing.md")
    emit_block "Blocked: editing harness config under ~/.claude/ directly (path resolves under the installed harness). The repo claude-code-config is the source of truth — edit there and run \`bash ./install.sh\`. To override locally, use a project .claude/settings.local.json; a user-level settings.local.json is not read at all, and machine-wide env belongs in the user settings.json, which the install merge preserves."
    exit 0
    ;;
  "$CLAUDE_HOME/skills/"*|"$CLAUDE_HOME_PHYS/skills/"*)
    emit_block "$SKILLS_BLOCK_REASON"
    exit 0
    ;;
esac

echo '{"decision": "approve"}'
