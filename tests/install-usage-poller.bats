#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/install-usage-poller.sh"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_HOME/.claude/hooks" "$STUB_BIN"
  cp "$REPO_ROOT/hooks/claude-usage-poll.sh" "$TEST_HOME/.claude/hooks/"
  chmod +x "$TEST_HOME/.claude/hooks/claude-usage-poll.sh"

  cat > "$STUB_BIN/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_CALLS"
exit 0
SH
  chmod +x "$STUB_BIN/systemctl"

  export HOME="$TEST_HOME"
  export XDG_CONFIG_HOME="$TEST_HOME/config"
  export PATH="$STUB_BIN:$PATH"
  export SYSTEMCTL_CALLS="$BATS_TEST_TMPDIR/systemctl-calls"
}

mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

@test "installer installs both systemd user units and enables the timer on Linux" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  cmp -s "$REPO_ROOT/systemd/claude-usage-poll.service" \
    "$XDG_CONFIG_HOME/systemd/user/claude-usage-poll.service"
  cmp -s "$REPO_ROOT/systemd/claude-usage-poll.timer" \
    "$XDG_CONFIG_HOME/systemd/user/claude-usage-poll.timer"
  grep -qx -- '--user daemon-reload' "$SYSTEMCTL_CALLS"
  grep -qx -- '--user enable --now claude-usage-poll.timer' "$SYSTEMCTL_CALLS"
  ! grep -q -- 'start claude-usage-poll.service' "$SYSTEMCTL_CALLS"
}

@test "installer refuses a stale installed poller" {
  printf '\n# stale\n' >> "$TEST_HOME/.claude/hooks/claude-usage-poll.sh"
  run bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"installed poller is missing or stale"* ]]
  [ ! -e "$XDG_CONFIG_HOME/systemd/user/claude-usage-poll.timer" ]
  [ ! -e "$SYSTEMCTL_CALLS" ]
}

@test "installer uses a five-minute launchd agent on macOS" {
  cat > "$STUB_BIN/uname" <<'SH'
#!/usr/bin/env bash
printf 'Darwin\n'
SH
  cat > "$STUB_BIN/id" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = -u ] && printf '501\n'
SH
  cat > "$STUB_BIN/plutil" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PLUTIL_CALLS"
exit 0
SH
  cat > "$STUB_BIN/launchctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAUNCHCTL_CALLS"
exit 0
SH
  chmod +x "$STUB_BIN/uname" "$STUB_BIN/id" "$STUB_BIN/plutil" "$STUB_BIN/launchctl"
  export PLUTIL_CALLS="$BATS_TEST_TMPDIR/plutil-calls"
  export LAUNCHCTL_CALLS="$BATS_TEST_TMPDIR/launchctl-calls"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  agent="$HOME/Library/LaunchAgents/com.ngc-shj.claude-usage-poll.plist"
  [ -f "$agent" ]
  grep -qF "$HOME/.claude/hooks/claude-usage-poll.sh" "$agent"
  grep -qF '<integer>300</integer>' "$agent"
  ! grep -q '__HOME__' "$agent"
  grep -qx -- 'enable gui/501/com.ngc-shj.claude-usage-poll' "$LAUNCHCTL_CALLS"
  grep -qxF "bootstrap gui/501 $agent" "$LAUNCHCTL_CALLS"
  ! grep -q 'kickstart' "$LAUNCHCTL_CALLS"
  [ "$(mode_of "$HOME/.claude/state/usage-poll-launchd.log")" = 600 ]
}
