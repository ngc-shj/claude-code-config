#!/usr/bin/env bats
# Tests for hooks/block-sensitive-files.sh — verifies the harness-config
# perimeter (~/.claude/hooks/*.sh, settings.json, CLAUDE.md) is denied
# while settings.local.json (the documented override path) remains
# editable, plus the existing secret/lock/.git protections.
#
# JSON whitespace contract (asymmetric, shared by all 7 block-*.sh hooks):
#   - approve decisions are emitted as `{"decision": "approve"}` (spaced)
#   - block decisions are emitted as `{"decision":"block","reason":...}` (compact)
# The asymmetry exists because block uses `printf` with a JSON template
# while approve uses bare `echo` of a hand-written literal. All 7 block-*.bats
# files (this one included) substring-match against this exact spacing.
# A future refactor that unifies the emit format (e.g., pipes both through
# jq) MUST update all 7 test files in the same diff — silently switching
# either format breaks the assertions here. The cleaner long-term fix is
# to parse `$output` via `jq -r '.decision'` in a helper, but that touches
# 7 files and was scoped out of the original fix.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/block-sensitive-files.sh"

run_hook() {
  local tool_name="$1"
  local file_path="$2"
  local input
  input=$(jq -nc --arg n "$tool_name" --arg p "$file_path" \
    '{tool_name:$n, tool_input:{file_path:$p}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

# ============================================================
# Existing protections (regression checks)
# ============================================================

@test "deny: .env file edit" {
  run run_hook Edit "/repo/project/.env"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve: .env.example (template)" {
  run run_hook Edit "/repo/project/.env.example"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: credentials.json" {
  run run_hook Write "/repo/project/credentials.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: *.pem" {
  run run_hook Edit "/etc/ssl/server.pem"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: package-lock.json" {
  run run_hook Edit "/repo/project/package-lock.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: file inside .git/" {
  run run_hook Write "/repo/project/.git/config"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# New protections — harness config perimeter (M6)
# ============================================================

@test "deny: ~/.claude/hooks/<name>.sh (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "deny: ~/.claude/hooks/block-destructive-docker.sh" {
  run run_hook Write "$HOME/.claude/hooks/block-destructive-docker.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/settings.json (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/settings.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/CLAUDE.md (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/CLAUDE.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/hooks/<name>.sh (un-expanded tilde)" {
  run run_hook Edit "~/.claude/hooks/commit-msg-check.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/settings.json (un-expanded tilde)" {
  run run_hook Edit "~/.claude/settings.json"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# Override exception — settings.local.json must stay editable (M6 design)
# ============================================================

@test "approve: ~/.claude/settings.local.json (override path)" {
  run run_hook Edit "$HOME/.claude/settings.local.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: literal ~/.claude/settings.local.json (un-expanded tilde)" {
  run run_hook Edit "~/.claude/settings.local.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# Approve cases — non-harness paths must not be blocked
# ============================================================

@test "approve: regular source file" {
  run run_hook Edit "/repo/project/src/main.go"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: README.md anywhere" {
  run run_hook Write "/repo/project/README.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: settings.json NOT under ~/.claude/ (e.g., a project's vscode settings)" {
  run run_hook Edit "/repo/project/.vscode/settings.json"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: hooks/<name>.sh NOT under ~/.claude/ (e.g., the source repo's hooks/)" {
  run run_hook Edit "/repo/claude-code-config/hooks/block-destructive-docker.sh"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: empty file_path (defensive default)" {
  run run_hook Edit ""
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve: non-Edit tool (Bash falls through unchanged)" {
  # block-sensitive-files.sh only inspects file_path; other tool inputs
  # without a file_path approve by default.
  local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  run bash -c "printf '%s' '$input' | bash '$SCRIPT'"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# Installed skill perimeter (C6) — ~/.claude/skills/ is not a mirror of
# the repo's skills/, so editing the installed copy directly must be
# blocked the same way ~/.claude/hooks|settings.json|CLAUDE.md are.
# ============================================================

@test "deny: ~/.claude/skills/<name>/... (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision":"block"'* ]]
  # Splits by concern from the unmanaged-skill fixture below: that one pins the
  # message branch, this one pins the arm and the repo-managed half of the text.
  [[ "$output" == *"edit it in the claude-code-config repo"* ]]
}

# The guarded set is install.sh's write set. skills/ and rules/ are installed by
# byte-for-byte the same `rm -rf "$dest"; cp -r` loop, and RTK.md /
# model-routing.md are copied alongside CLAUDE.md — covering one and not the
# others is the class-membership miss this suite exists to make loud.
@test "deny: ~/.claude/rules/<name>/... (absolute HOME path)" {
  run run_hook Edit "$HOME/.claude/rules/common/security.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/rules/<name>/... (un-expanded tilde)" {
  run run_hook Edit "~/.claude/rules/common/security.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/hooks/lib/<name> regardless of extension" {
  # install.sh rm -rf's and re-copies hooks/lib/ wholesale, and ast-runner.js
  # is the AST engine the detection hooks call — a .sh-only arm left the most
  # tripwire-adjacent file in the tree editable.
  run run_hook Edit "$HOME/.claude/hooks/lib/ast-runner.js"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/RTK.md (a CLAUDE.md-cited ref)" {
  run run_hook Edit "$HOME/.claude/RTK.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/model-routing.md (a CLAUDE.md-cited ref)" {
  run run_hook Edit "$HOME/.claude/model-routing.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

# T5: the literal-tilde arm carries the same member set as the expanded one, and
# three of its patterns had no fixture — two of them added by this change. A
# pattern nothing reaches is a pattern a later edit can delete silently.
@test "deny: literal ~/.claude/CLAUDE.md (un-expanded tilde)" {
  run run_hook Edit "~/.claude/CLAUDE.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/RTK.md (un-expanded tilde)" {
  run run_hook Edit "~/.claude/RTK.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: literal ~/.claude/model-routing.md (un-expanded tilde)" {
  run run_hook Edit "~/.claude/model-routing.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

# T6: ${HOME:?} pins the fail direction when HOME is unset. Without a fixture,
# nothing distinguishes "aborts with a stated precondition" from "falls through
# and approves" — and for a guard, that difference is the whole point.
@test "unset HOME aborts with a stated precondition rather than approving" {
  run bash -c 'unset HOME; printf "%s" "$1" | bash "$2"' _     '{"tool_name":"Edit","tool_input":{"file_path":"/anywhere/x.sh"}}' "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" != *'"decision": "approve"'* ]]
  [[ "$output" == *"HOME"* ]]
}

@test "approve: ~/.claude/projects/<slug>/memory/*.md is not install-managed" {
  # Auto-memory is written by the running session and never overwritten by
  # install.sh; a guard that swept the whole of ~/.claude would break it.
  run run_hook Edit "$HOME/.claude/projects/some-slug/memory/feedback_example.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: literal ~/.claude/skills/<name>/... (un-expanded tilde)" {
  run run_hook Edit "~/.claude/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: ~/.claude/skills/<name>/SKILL.md for a skill with no repo source names the unmanaged case" {
  # install.sh only removes/re-copies the skill directories it is about to
  # write (skills/*/ in the repo), so a skill absent from the repo (e.g.
  # "improve") survives every install untouched. Reusing the repo-managed
  # "edit there and run install.sh" message would be unfollowable guidance
  # here, so the skills arm must say so explicitly — asserting only that a
  # block occurred would not distinguish this branch from fixture 1's.
  run run_hook Edit "$HOME/.claude/skills/improve/SKILL.md"
  [[ "$output" == *'"decision":"block"'* ]]
  echo "$output" | grep -qF "If it has no repo source (install.sh only removes and re-copies the skills it manages, so an unmanaged skill survives every install untouched), add it to the repo's skills/ directory, or exempt it via ~/.claude/settings.local.json."
}

@test "approve: repo's own skills/ directory stays editable (not ~/.claude/skills/)" {
  # The whole "edit the repo, run install.sh" workflow — and this fix's own
  # implementation — depends on the repo copy never being caught by the
  # ~/.claude/skills/ arms above.
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  run run_hook Edit "$repo_root/skills/triangulate/phases/phase-3-review.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: ~/.claude/skills/... still blocked when HOME has a trailing slash" {
  # Regression for the fail-open bug: without normalizing $HOME, a
  # trailing-slash HOME turns "$HOME/.claude/..." into "…//.claude/…",
  # which never matches the single-slash path the tool reports, and the
  # guard silently approves instead of blocking. None of the fixtures
  # above can see this failure mode since they inherit the ambient $HOME.
  local input
  input=$(jq -nc --arg n "Edit" --arg p "$HOME/.claude/skills/triangulate/phases/phase-3-review.md" \
    '{tool_name:$n, tool_input:{file_path:$p}}')
  run bash -c "HOME='$HOME/' bash '$SCRIPT'" <<< "$input"
  [[ "$output" == *'"decision":"block"'* ]]
}

# ============================================================
# Path-equivalence — a literal `case` compares strings, and these all name a
# guarded file while spelling it differently. Each was an approve before the
# normalization pass.
# ============================================================

@test "deny: a doubled slash inside the protected path" {
  run run_hook Edit "$HOME/.claude//skills/triangulate/SKILL.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: a /./ component inside the protected path" {
  run run_hook Edit "$HOME/.claude/./skills/triangulate/SKILL.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: a literal-tilde path with a /./ component" {
  # Cannot be resolved against the filesystem, so the lexical pass is the only
  # thing that reaches it.
  run run_hook Edit "~/.claude/./skills/triangulate/SKILL.md"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: an intermediate .. that lands back inside the protected tree" {
  run run_hook Edit "$HOME/.claude/projects/../hooks/block-sensitive-files.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: a not-yet-created file under a protected directory" {
  # The resolver walks up to the deepest EXISTING ancestor and re-attaches the
  # rest, so a first write to a new file is matched too.
  run run_hook Write "$HOME/.claude/hooks/does-not-exist-yet.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve: .. that leaves the protected tree is not blocked by it" {
  run run_hook Edit "$HOME/.claude/hooks/../../scratch/notes.md"
  [[ "$output" == *'"decision": "approve"'* ]]
}

# ============================================================
# Bash tool — the other door to the same files. install.sh overwrites the
# installed tree, and a session that rewrites its own hooks can disable the
# tripwires meant to catch it, so a write verb aimed at a protected path is
# refused. Heuristic by construction: read-only work on the same paths, and
# writes anywhere else, must stay free.
# ============================================================

run_bash_hook() {
  local cmd="$1" input
  input=$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  printf '%s' "$input" | bash "$SCRIPT"
}

@test "deny (Bash): sed -i against an installed hook" {
  run run_bash_hook 'sed -i "s/x/y/" ~/.claude/hooks/block-sensitive-files.sh'
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"install.sh overwrites that tree"* ]]
}

@test "deny (Bash): redirect into the installed hooks directory" {
  run run_bash_hook 'echo x > $HOME/.claude/hooks/evil.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): cp over an installed skill file" {
  run run_bash_hook 'cp /tmp/x ~/.claude/skills/triangulate/SKILL.md'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): tee into an installed rules file" {
  run run_bash_hook 'cat /tmp/x | tee ~/.claude/rules/common/security.md'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): rm of an installed hook" {
  run run_bash_hook 'rm ~/.claude/hooks/check-rule-sync.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): append to the installed CLAUDE.md by absolute path" {
  run run_bash_hook 'printf x >> /home/someone/.claude/CLAUDE.md'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve (Bash): running an installed hook" {
  # The guard must not make the hooks unusable — every skill invokes them.
  run run_bash_hook 'bash ~/.claude/hooks/check-rule-sync.sh'
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve (Bash): reading and grepping protected paths" {
  run run_bash_hook 'cat ~/.claude/skills/triangulate/SKILL.md'
  [[ "$output" == *'"decision": "approve"'* ]]
  run run_bash_hook 'grep -rn END-OF-PHASE ~/.claude/skills/'
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve (Bash): install.sh itself" {
  # The sanctioned writer. It names no protected path on the command line —
  # blocking it would make the documented workflow impossible.
  run run_bash_hook 'bash ./install.sh'
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "approve (Bash): a write verb aimed somewhere else" {
  run run_bash_hook 'cp hooks/x.sh /tmp/y.sh'
  [[ "$output" == *'"decision": "approve"'* ]]
}

# --- Bypasses closed after review (each reproduced before the fix) ---

@test "deny (Bash): sed --in-place long flag" {
  # The matcher keyed on `-[a-zA-Z]*i`, so the long spelling walked past.
  run run_bash_hook 'sed --in-place "s/x/y/" ~/.claude/hooks/block-sensitive-files.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): perl -pi in-place edit" {
  # perl/ruby/awk spell in-place their own way; only sed was covered.
  run run_bash_hook 'perl -pi -e "s/x/y/" ~/.claude/hooks/block-sensitive-files.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): quoted \$HOME expands to the guarded tree" {
  # `"$HOME"/.claude/...` did not match the literal-path regex.
  run run_bash_hook 'cp /tmp/x "$HOME"/.claude/hooks/block-sensitive-files.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): doubled slash in the guarded path" {
  # `~/.claude//hooks/` names the same directory the single-slash arm guards.
  run run_bash_hook 'echo x > ~/.claude//hooks/evil.sh'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny (Bash): mv OUT of the tree is a deletion from it" {
  # mv mutates its source, so moving a guarded file away removes it — unlike
  # cp, which only reads the source.
  run run_bash_hook 'mv ~/.claude/hooks/x.sh /tmp/'
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve (Bash): cp OUT of the tree is a read-only backup" {
  # Previously blocked: the path matched and `cp` was a write verb, with no
  # check of which side was the destination.
  run run_bash_hook 'cp ~/.claude/hooks/block-sensitive-files.sh /tmp/backup.sh'
  [[ "$output" == *'"decision": "approve"'* ]]
}

@test "deny: relative path resolving into the installed tree" {
  # The hook runs in the session cwd, so a relative path names a real file;
  # it was not made absolute before matching.
  local rel
  rel=$(python3 -c "import os,sys; print(os.path.relpath(os.path.expanduser('~/.claude/hooks/block-sensitive-files.sh'), os.getcwd()))")
  run run_hook "Write" "$rel"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: symlink whose target is an installed hook" {
  # `cd -P` resolves symlinked DIRECTORY components; a symlinked leaf survived
  # as its own path and was judged on that.
  ln -sf "$HOME/.claude/hooks/block-sensitive-files.sh" "$BATS_TEST_TMPDIR/alias.sh"
  run run_hook "Write" "$BATS_TEST_TMPDIR/alias.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: symlink CHAIN whose terminus is an installed hook" {
  # One readlink hop is defeated by two links.
  ln -sf "$HOME/.claude/hooks/block-sensitive-files.sh" "$BATS_TEST_TMPDIR/hop2.sh"
  ln -sf "$BATS_TEST_TMPDIR/hop2.sh" "$BATS_TEST_TMPDIR/hop1.sh"
  run run_hook "Write" "$BATS_TEST_TMPDIR/hop1.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: a directory symlink crossed by .. lands back inside the guarded tree" {
  # `a/b/../c` is `a/c` only when b is a real directory. Through a symlink, `..`
  # names the parent of the TARGET — so a link to ~/.claude/skills plus `..`
  # resolves into ~/.claude/hooks. Collapsing `..` lexically before resolving
  # sent this somewhere else entirely and approved the write.
  ln -sfn "$HOME/.claude/skills" "$BATS_TEST_TMPDIR/skill-link"
  run run_hook Edit "$BATS_TEST_TMPDIR/skill-link/../hooks/block-sensitive-files.sh"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "deny: a physical path under a symlinked HOME" {
  # CANON_PATH is fully resolved, so the guarded root has to be resolved too —
  # otherwise the arms hold the symlinked spelling, the path holds the real one,
  # and every resolved path misses.
  real="$BATS_TEST_TMPDIR/home-real"
  mkdir -p "$real/.claude/hooks"
  ln -sfn "$real" "$BATS_TEST_TMPDIR/home-link"
  input=$(jq -nc --arg p "$real/.claude/hooks/x.sh" \
    '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run env HOME="$BATS_TEST_TMPDIR/home-link" bash -c "printf '%s' '$input' | bash '$SCRIPT'"
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "approve: symlink pointing somewhere harmless" {
  # Chain resolution must not over-block: a link to an unguarded file stays
  # editable.
  echo x > "$BATS_TEST_TMPDIR/plain.txt"
  ln -sf "$BATS_TEST_TMPDIR/plain.txt" "$BATS_TEST_TMPDIR/plain-alias.txt"
  run run_hook "Write" "$BATS_TEST_TMPDIR/plain-alias.txt"
  [[ "$output" == *'"decision": "approve"'* ]]
}
