#!/usr/bin/env bats
# Tests for notify.sh / stop-notify.sh — the cross-platform (macOS + Linux)
# notification hooks. External tools (uname, afplay, osascript, paplay, aplay,
# notify-send) are stubbed on PATH so tests are deterministic and produce no
# real audio/desktop side effects. jq/cat resolve from the real PATH.

bats_require_minimum_version 1.5.0

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
NOTIFY="$REPO_DIR/hooks/notify.sh"
STOP_NOTIFY="$REPO_DIR/hooks/stop-notify.sh"

setup() {
  STUBBIN="$(mktemp -d)"
  STUB_LOG="$(mktemp)"
}

teardown() {
  rm -rf "$STUBBIN"
  rm -f "$STUB_LOG"
}

# Write an executable stub that logs its name+args and exits 0.
_stub() {
  local name="$1"
  cat > "$STUBBIN/$name" <<EOF
#!/bin/bash
echo "$name \$*" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "$STUBBIN/$name"
}

# uname stub forcing a given OS.
_stub_uname() {
  cat > "$STUBBIN/uname" <<EOF
#!/bin/bash
echo "$1"
EOF
  chmod +x "$STUBBIN/uname"
}

@test "notify: linux path dispatches notify-send and exits 0" {
  _stub_uname Linux; _stub paplay; _stub aplay; _stub notify-send
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$NOTIFY" <<< '{"notification_type":"permission_prompt"}'
  [ "$status" -eq 0 ]
  grep -q '^notify-send ' "$STUB_LOG"
}

@test "notify: macOS path dispatches osascript and exits 0" {
  _stub_uname Darwin; _stub afplay; _stub osascript
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$NOTIFY" <<< '{"notification_type":"idle_prompt"}'
  [ "$status" -eq 0 ]
  grep -q '^osascript ' "$STUB_LOG"
}

@test "notify: unknown notification_type is a no-op exit 0" {
  _stub_uname Linux; _stub paplay; _stub aplay; _stub notify-send
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$NOTIFY" <<< '{"notification_type":"bogus"}'
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "stop-notify: linux path dispatches notify-send and exits 0" {
  _stub_uname Linux; _stub paplay; _stub aplay; _stub notify-send
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$STOP_NOTIFY" <<< '{"stop_reason":"end_turn"}'
  [ "$status" -eq 0 ]
  grep -q '^notify-send ' "$STUB_LOG"
}

@test "stop-notify: max_tokens path exits 0 (critical urgency)" {
  _stub_uname Linux; _stub paplay; _stub aplay; _stub notify-send
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$STOP_NOTIFY" <<< '{"stop_reason":"max_tokens"}'
  [ "$status" -eq 0 ]
  grep -q 'critical' "$STUB_LOG"
}

# T2 regression: notify-send is backgrounded, so a hanging daemon must not
# stall the hook. A foreground call would make this time out (status 124).
@test "notify: a slow notify-send does not hang the hook" {
  _stub_uname Linux; _stub paplay; _stub aplay
  cat > "$STUBBIN/notify-send" <<'EOF'
#!/bin/bash
sleep 30
EOF
  chmod +x "$STUBBIN/notify-send"
  run env PATH="$STUBBIN:$PATH" timeout 3 bash "$NOTIFY" <<< '{"notification_type":"permission_prompt"}'
  [ "$status" -ne 124 ]
  [ "$status" -eq 0 ]
}

# T2 regression for the Stop hook as well.
@test "stop-notify: a slow notify-send does not hang the hook" {
  _stub_uname Linux; _stub paplay; _stub aplay
  cat > "$STUBBIN/notify-send" <<'EOF'
#!/bin/bash
sleep 30
EOF
  chmod +x "$STUBBIN/notify-send"
  run env PATH="$STUBBIN:$PATH" timeout 3 bash "$STOP_NOTIFY" <<< '{"stop_reason":"end_turn"}'
  [ "$status" -ne 124 ]
  [ "$status" -eq 0 ]
}

# F1/robustness regression: under `set -euo pipefail`, a failing tool (or an
# empty sound resolution) must not abort the hook. Stub the tools to exit
# non-zero and confirm the hook still exits 0. (The sound resolver runs against
# the real filesystem here; before the `return 0` fix it would abort the hook
# under set -e on a host with no matching sound file.)
@test "notify: a failing notify-send/paplay does not abort the hook" {
  _stub_uname Linux
  for t in paplay aplay notify-send; do
    printf '#!/bin/bash\nexit 1\n' > "$STUBBIN/$t"
    chmod +x "$STUBBIN/$t"
  done
  run env PATH="$STUBBIN:$PATH" timeout 5 bash "$NOTIFY" <<< '{"notification_type":"permission_prompt"}'
  [ "$status" -eq 0 ]
}
