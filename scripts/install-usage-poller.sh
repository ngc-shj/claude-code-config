#!/usr/bin/env bash
# Install the native per-user scheduler for claude-usage-poll.sh:
# systemd on Linux, launchd on macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POLLER="$HOME/.claude/hooks/claude-usage-poll.sh"

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || {
      echo "ERROR: $command_name is required by this installer." >&2
      exit 1
    }
  done
}

require_commands cmp install uname

# install.sh owns ~/.claude/hooks. Keep a single source-of-truth path rather
# than copying one hook differently from every other managed hook.
if [ ! -x "$POLLER" ] ||
   ! cmp -s "$SCRIPT_DIR/hooks/claude-usage-poll.sh" "$POLLER"; then
  echo "ERROR: installed poller is missing or stale; run: bash $SCRIPT_DIR/install.sh" >&2
  exit 1
fi

install_linux() {
  local user_unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  require_commands systemctl

  mkdir -p "$user_unit_dir"
  install -m 0644 "$SCRIPT_DIR/systemd/claude-usage-poll.service" \
    "$user_unit_dir/claude-usage-poll.service"
  install -m 0644 "$SCRIPT_DIR/systemd/claude-usage-poll.timer" \
    "$user_unit_dir/claude-usage-poll.timer"

  systemctl --user daemon-reload
  systemctl --user enable --now claude-usage-poll.timer

  echo "Claude usage poller enabled with systemd (5min interval)."
  systemctl --user --no-pager status claude-usage-poll.timer || true
}

install_macos() {
  local label="com.ngc-shj.claude-usage-poll"
  local agent_dir="$HOME/Library/LaunchAgents"
  local agent_file="$agent_dir/$label.plist"
  local state_dir="$HOME/.claude/state"
  local generated_plist user_id

  require_commands id launchctl plutil sed
  # HOME is substituted into XML and a sed replacement. Reject the unusual
  # characters that would need a general-purpose XML encoder.
  case "$HOME" in
    *'&'*|*'<'*|*'>'*|*'|'*|*\\*)
      echo "ERROR: HOME contains a character unsupported by the launchd installer." >&2
      exit 1
      ;;
  esac

  mkdir -p "$agent_dir" "$state_dir"
  chmod 700 "$state_dir"
  : > "$state_dir/usage-poll-launchd.log"
  chmod 600 "$state_dir/usage-poll-launchd.log"

  generated_plist="$(mktemp)"
  trap 'rm -f "$generated_plist"' EXIT
  sed "s|__HOME__|$HOME|g" \
    "$SCRIPT_DIR/launchd/com.ngc-shj.claude-usage-poll.plist.in" \
    > "$generated_plist"
  plutil -lint "$generated_plist" >/dev/null
  install -m 0644 "$generated_plist" "$agent_file"
  rm -f "$generated_plist"
  trap - EXIT

  user_id="$(id -u)"
  launchctl bootout "gui/$user_id/$label" >/dev/null 2>&1 || true
  launchctl enable "gui/$user_id/$label"
  # RunAtLoad performs the initial fetch; do not kickstart again and create an
  # immediate duplicate request against the rate-limited internal endpoint.
  launchctl bootstrap "gui/$user_id" "$agent_file"

  echo "Claude usage poller enabled with launchd (5min interval)."
  launchctl print "gui/$user_id/$label" || true
}

case "$(uname -s)" in
  Linux)  install_linux ;;
  Darwin) install_macos ;;
  *)
    echo "ERROR: unsupported OS; use cron or another scheduler for $POLLER" >&2
    exit 1
    ;;
esac
