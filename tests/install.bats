#!/usr/bin/env bats
# Tests for install.sh — focus on M8: pre-flight settings.json JSON
# validation and post-install hook executability check.

bats_require_minimum_version 1.5.0

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"

# install.sh writes to $HOME/.claude. We isolate by setting HOME to a
# temp dir per test, then run install.sh from a SCRIPT_DIR copy that
# we can mutate (e.g., to inject a malformed settings.json).

setup() {
  TEST_HOME="$(mktemp -d)"
  STAGING="$(mktemp -d)"
  # Stage a minimal SCRIPT_DIR layout matching install.sh expectations.
  cp "$REPO_DIR/install.sh" "$STAGING/install.sh"
  chmod +x "$STAGING/install.sh"
  mkdir -p "$STAGING/global"
  cp "$REPO_DIR/global/CLAUDE.md" "$STAGING/global/CLAUDE.md"
  cp "$REPO_DIR/global/RTK.md" "$STAGING/global/RTK.md"
  cp "$REPO_DIR/global/model-routing.md" "$STAGING/global/model-routing.md"
  cp "$REPO_DIR/settings.json" "$STAGING/settings.json"
  mkdir -p "$STAGING/hooks"
  # Copy at least one hook so the for-loop executes.
  cp "$REPO_DIR/hooks/block-sensitive-files.sh" "$STAGING/hooks/"
  # rules/common/ is auto-injected into every session, so its delivery is
  # asserted below; language overlays are load-on-demand and not staged.
  mkdir -p "$STAGING/rules/common"
  cp "$REPO_DIR"/rules/common/*.md "$STAGING/rules/common/"
  # Skip skills/ for speed — independent of the tests here, except for the one
  # case below that stages skills/triangulate/ explicitly.
}

teardown() {
  rm -rf "$TEST_HOME" "$STAGING"
}

@test "install: well-formed settings.json proceeds and installs" {
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed settings.json"* ]]
  [[ "$output" == *"Installed hook: block-sensitive-files.sh"* ]]
  [[ "$output" == *"Done."* ]]
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
}

@test "install: the installed phase files keep their manifest and terminator" {
  # The whole truncation protocol is a property of the bytes the runtime loads,
  # i.e. the INSTALLED copy. Nothing asserted that install.sh preserves them —
  # the front matter is at byte 0 and the terminator is the last line, exactly
  # the two positions a copy step is most likely to disturb.
  mkdir -p "$STAGING/skills"
  cp -r "$REPO_DIR/skills/triangulate" "$STAGING/skills/"
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  installed="$TEST_HOME/.claude/skills/triangulate/phases/phase-3-review.md"
  [ -f "$installed" ]
  [ "$(head -n 1 "$installed")" = "---" ]
  [ "$(sed '/^[[:space:]]*$/d' "$installed" | tail -n 1)" = "## END-OF-PHASE-3" ]
  [ "$(sed '/^[[:space:]]*$/d' "$TEST_HOME/.claude/skills/triangulate/common-rules.digest.md" | tail -n 1)" = "## END-OF-DIGEST" ]
}

@test "install: malformed settings.json (trailing comma) is rejected before install" {
  # Inject a malformed settings.json into the staging copy.
  printf '{"permissions":{"deny":["Bash(foo)",]}}' > "$STAGING/settings.json"
  # Pre-create a sentinel so we can verify it survives the failed install.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"sentinel":true}' > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]] || [[ "$output" == *"Refusing to install"* ]]
  # Sentinel survived — the malformed file did NOT clobber the previous good copy.
  grep -q sentinel "$TEST_HOME/.claude/settings.json"
}

@test "install: malformed settings.json (unclosed brace) is rejected" {
  printf '{"permissions":{"deny":[' > "$STAGING/settings.json"
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "install: merges into existing settings.json, preserving user top-level keys" {
  # Pre-existing live settings with a user-managed key the template does not own.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"mcpServers":{"ollama":{"command":"x"}},"permissions":{"deny":["Bash(stale)"]}}' \
    > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged settings.json"* ]]

  # User's mcpServers survived the merge.
  run jq -e '.mcpServers.ollama.command == "x"' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  # Template's permissions replaced the user's stale entry (template wins).
  run jq -e '.permissions.deny | index("Bash(stale)") == null' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  # A timestamped backup of the pre-merge file was written.
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  [ -f "${backups[0]}" ]
}

@test "install: merge replaces hooks wholesale (unmanaged event does not survive)" {
  # An attacker-seeded / stale live file with a hook event the template does
  # not own must NOT leak through the merge — permissions and hooks are
  # template-owned.
  mkdir -p "$TEST_HOME/.claude"
  printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"evil.sh"}]}]}}' \
    > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  # The unmanaged PostToolUse event is gone; the merged hooks equal the template's.
  run jq -e '.hooks | has("PostToolUse")' "$TEST_HOME/.claude/settings.json"
  [ "$status" -ne 0 ]
}

@test "install: empty live settings.json is backed up and replaced, not aborted" {
  # Regression: jq `*` errors on a null/empty operand. An empty live file must
  # route to replace (exit 0), not abort the whole install.
  mkdir -p "$TEST_HOME/.claude"
  : > "$TEST_HOME/.claude/settings.json"   # zero-byte

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-object settings.json"* ]]
  run jq -e '.permissions' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  [ -f "${backups[0]}" ]
}

@test "install: non-object live settings.json (array) is backed up and replaced" {
  mkdir -p "$TEST_HOME/.claude"
  printf '[1,2,3]' > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-object settings.json"* ]]
  # Replaced with the template (an object with permissions), original preserved in backup.
  run jq -e 'type == "object"' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  backups=("$TEST_HOME"/.claude/settings.json.bak.*)
  grep -q '1,2,3' "${backups[0]}"
}

@test "install: hook chmod +x is verified post-install" {
  # Standard install path — verify executability is asserted.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  for hook in "$TEST_HOME/.claude/hooks"/*.sh; do
    [ -x "$hook" ]
  done
}

@test "install: removes a stale top-level hook not present in source" {
  # Source-of-truth sync: a renamed-away hook left in the live dir is purged.
  mkdir -p "$TEST_HOME/.claude/hooks"
  printf '#!/bin/bash\n' > "$TEST_HOME/.claude/hooks/ollama-utils.sh"
  chmod +x "$TEST_HOME/.claude/hooks/ollama-utils.sh"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed stale hook: ollama-utils.sh"* ]]
  [ ! -e "$TEST_HOME/.claude/hooks/ollama-utils.sh" ]
  # The source hook still installs.
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
}

@test "install: keeps a live hook that still exists in source" {
  # A hook present in the source must be overwritten, never removed by the sync.
  mkdir -p "$TEST_HOME/.claude/hooks"
  printf 'stale-content\n' > "$TEST_HOME/.claude/hooks/block-sensitive-files.sh"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Removed stale hook: block-sensitive-files.sh"* ]]
  [ -x "$TEST_HOME/.claude/hooks/block-sensitive-files.sh" ]
  # Content came from source (the staged copy), not the stale live one.
  ! grep -q 'stale-content' "$TEST_HOME/.claude/hooks/block-sensitive-files.sh"
}

# ============================================================
# Retrospect additions (C7/C8): state dir, config non-install,
# SessionStart registration survival
# ============================================================

@test "install: creates ~/.claude/state with mode 0700" {
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/.claude/state" ]
  perms=$(stat -c %a "$TEST_HOME/.claude/state" 2>/dev/null || stat -f %Lp "$TEST_HOME/.claude/state")
  [ "$perms" = "700" ]
}

@test "install: does NOT install retrospect.config.json and prints the opt-in hint" {
  cp "$REPO_DIR/retrospect.config.json.example" "$STAGING/retrospect.config.json.example"
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/.claude/retrospect.config.json" ]
  [[ "$output" == *"retrospective mining is disabled"* ]]
}

@test "install: leaves an existing retrospect config and state untouched on re-install" {
  mkdir -p "$TEST_HOME/.claude/state"
  printf '{"user":"config"}' > "$TEST_HOME/.claude/retrospect.config.json"
  printf '{"user":"state"}' > "$TEST_HOME/.claude/state/retrospect.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  grep -q '"user":"config"' "$TEST_HOME/.claude/retrospect.config.json"
  grep -q '"user":"state"' "$TEST_HOME/.claude/state/retrospect.json"
  [[ "$output" != *"retrospective mining is disabled"* ]]
}

@test "install: SessionStart registration survives the settings merge" {
  mkdir -p "$TEST_HOME/.claude"
  printf '{"mcpServers":{"keepme":{}}}' > "$TEST_HOME/.claude/settings.json"

  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  run jq -e '.hooks.SessionStart[0].hooks[0].command | test("session-retrospect-check")' \
    "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "install: CLAUDE.md is delivered to ~/.claude/CLAUDE.md" {
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed CLAUDE.md"* ]]
  [ -f "$TEST_HOME/.claude/CLAUDE.md" ]
  diff "$STAGING/global/CLAUDE.md" "$TEST_HOME/.claude/CLAUDE.md"
}

@test "repo root CLAUDE.md does not duplicate the global one" {
  # A root CLAUDE.md is auto-loaded as this repo's project instructions on
  # top of the installed global copy. Keeping the global content out of it
  # is what prevents every line loading twice in sessions opened here.
  ! diff -q "$REPO_DIR/CLAUDE.md" "$REPO_DIR/global/CLAUDE.md" >/dev/null
  # The heaviest global-only sections must not reappear at the root.
  ! grep -q '^## Model Routing' "$REPO_DIR/CLAUDE.md"
  ! grep -q 'Privacy posture' "$REPO_DIR/CLAUDE.md"
  ! grep -q '^@RTK.md' "$REPO_DIR/CLAUDE.md"
}

@test "install: CLAUDE.md carries the Rules Layer pointer to rules/" {
  # The only reference tying the model to ~/.claude/rules/ is prose in
  # CLAUDE.md — no hook or settings entry injects it. Losing this section
  # silently severs the rules layer, so assert it survives installation.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  grep -q '^## Rules Layer' "$TEST_HOME/.claude/CLAUDE.md"
  grep -q 'rules/common/' "$TEST_HOME/.claude/CLAUDE.md"
}

@test "install: CLAUDE.md carries the option-proposal guidance" {
  # skills/triangulate/common-rules.md already encodes this lesson, but it
  # loads only during a review — the failure it prevents happens earlier, when
  # options are first proposed. Delivery has to be always-on to reach that
  # moment, so assert it survives installation.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  grep -q '^## Proposing options' "$TEST_HOME/.claude/CLAUDE.md"
}

@test "install: CLAUDE.md carries the Opus 5 output-length and delegation guidance" {
  # Anthropic documents that Opus 5 answers longer, writes longer files, and
  # delegates more readily than prior models — none of which effort settings fix,
  # so the correction has to be prompt text. It only reaches a session through the
  # installed copy, hence a delivery assertion rather than a source grep.
  #
  # The delegation sentence is asserted verbatim: it is one qualifier away from
  # reading as "skip verifying subagent work", which would silently undercut the
  # triangulate R21 obligation on every session. Pinning the reviewed wording is
  # what keeps a future reword from drifting past review.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  grep -q '^## Output length' "$TEST_HOME/.claude/CLAUDE.md"
  grep -qF 'Delegate a whole slice of work, not the checking of work already done.' \
    "$TEST_HOME/.claude/CLAUDE.md"
}

@test "install: every reference file CLAUDE.md points at is delivered" {
  # CLAUDE.md cites these by path rather than @-importing them, keeping them
  # out of the always-loaded context. A missing file makes the pointer dangle
  # silently — the failure mode RTK.md already shipped with once.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  while IFS= read -r ref; do
    [ -f "$TEST_HOME/.claude/$ref" ] || {
      echo "CLAUDE.md cites ~/.claude/$ref but install did not deliver it"
      return 1
    }
  done < <(grep -oE '~/\.claude/[A-Za-z0-9_.-]+\.md' "$TEST_HOME/.claude/CLAUDE.md" \
             | sed 's|~/\.claude/||' | sort -u)
}

@test "install: CLAUDE.md keeps heavy reference detail out of the always-loaded prompt" {
  # Progressive disclosure: the model table and RTK audit live in cited files,
  # not inline. Re-inlining them silently doubles the per-session cost.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  ! grep -q '^@RTK.md' "$TEST_HOME/.claude/CLAUDE.md"
  ! grep -q 'gpt-oss:120b' "$TEST_HOME/.claude/CLAUDE.md"
  ! grep -q 'telemetry' "$TEST_HOME/.claude/CLAUDE.md"
  grep -q 'model-routing.md' "$TEST_HOME/.claude/CLAUDE.md"
  grep -q 'RTK.md' "$TEST_HOME/.claude/CLAUDE.md"
}

@test "install: rules/common/ files install without paths: frontmatter" {
  # No paths: is what keeps common/ auto-injected in every session. Adding
  # one would silently drop the baseline rules out of context.
  run env HOME="$TEST_HOME" bash "$STAGING/install.sh"
  [ "$status" -eq 0 ]
  for f in coding-style testing security; do
    [ -f "$TEST_HOME/.claude/rules/common/$f.md" ]
    run grep -c '^paths:' "$TEST_HOME/.claude/rules/common/$f.md"
    [ "$output" -eq 0 ]
  done
}

# Matches any invocation of the linter; `ok` additionally requires an accepted
# trailing form. Whitelist, not denylist: a spelling nobody anticipated raises
# `tot` without raising `ok`, so the assertion fires. A denylist of terminators
# is open by construction — the first version of this test enumerated three and
# caught none of ten plausible bare spellings.
RULE_SYNC_ANY='(bash |\./)[^ ]*check-rule-sync\.sh'
RULE_SYNC_OK='(bash |\./)[^ ]*check-rule-sync\.sh( skills/triangulate| \*\))'

@test "retrospect: the rule-sync gate is prescribed with an explicit skill directory" {
  # Without the directory argument, check-rule-sync.sh resolves its target
  # relative to its own location, so the installed ~/.claude copy is linted
  # instead of the repo — and it prints the same OK line either way. Every
  # file that prescribes the gate must carry the argument, or a retro round's
  # first green has the wrong subject (R50).
  #
  # The accepted forms are `... check-rule-sync.sh skills/triangulate` and the
  # settings.json allow-pattern `Bash(bash hooks/check-rule-sync.sh *)`, which
  # folding.md quotes while explaining why it is deliberately NOT added.

  # Derive the subject set rather than hardcoding it, so a third file that
  # starts prescribing the gate is claimed automatically (R42). An empty set
  # would make every assertion below vacuous, so assert it is non-empty.
  local files
  files=$(cd "$REPO_DIR" && grep -rlE "$RULE_SYNC_ANY" skills/ global/ 2>/dev/null)
  [ -n "$files" ]

  local f tot ok
  while IFS= read -r f; do
    [ -f "$REPO_DIR/$f" ]
    tot=$(grep -oE "$RULE_SYNC_ANY" "$REPO_DIR/$f" | wc -l | tr -d ' ')
    ok=$(grep -oE "$RULE_SYNC_OK" "$REPO_DIR/$f" | wc -l | tr -d ' ')
    [ "$tot" -gt 0 ]
    [ "$tot" -eq "$ok" ]
  done <<< "$files"
}

@test "retrospect: the rule-sync gate matcher rejects bare invocations" {
  # The allow case for the matcher above. Without it the whitelist is never
  # exercised against a string it must catch, so a typo in the pattern leaves
  # the guard green forever — a deny-only guard on absence, which is the R50
  # shape the guard itself exists to prevent (RT10 clause 1 / obligation 17a).
  local fixture="$BATS_TEST_TMPDIR/bare.md"
  cat > "$fixture" <<'EOF'
bash hooks/check-rule-sync.sh && bats tests/
bash hooks/check-rule-sync.sh; bats tests/
bash hooks/check-rule-sync.sh > /dev/null
bash "$REPO/hooks/check-rule-sync.sh"
bash 'hooks/check-rule-sync.sh'
(bash hooks/check-rule-sync.sh)
./hooks/check-rule-sync.sh
bash hooks/check-rule-sync.sh --help
bash hooks/check-rule-sync.sh,
bash hooks/check-rule-sync.sh.
EOF
  local tot ok
  tot=$(grep -oE "$RULE_SYNC_ANY" "$fixture" | wc -l | tr -d ' ')
  ok=$(grep -oE "$RULE_SYNC_OK" "$fixture" | wc -l | tr -d ' ')
  # Every line is an invocation, and none of them is an accepted form.
  [ "$tot" -eq 10 ]
  [ "$ok" -eq 0 ]

  # Boundary-adjacent allow case: the same spelling WITH the argument is
  # accepted, so the matcher is not simply refusing everything.
  printf 'bash hooks/check-rule-sync.sh skills/triangulate\n' > "$fixture"
  tot=$(grep -oE "$RULE_SYNC_ANY" "$fixture" | wc -l | tr -d ' ')
  ok=$(grep -oE "$RULE_SYNC_OK" "$fixture" | wc -l | tr -d ' ')
  [ "$tot" -eq 1 ]
  [ "$ok" -eq 1 ]
}
