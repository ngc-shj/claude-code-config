#!/usr/bin/env bash
# Fetch the current Claude.ai subscription utilization without sending a model
# prompt, then feed it through statusline-usage.sh so both writers share one
# lock, monotonic frontier, privacy policy, and JSONL format.
#
# This endpoint is used by Claude Code itself but is not a documented public
# API. Keep the fetch isolated here so a schema or authentication change fails
# closed instead of corrupting the log.
set -u

CREDENTIALS="${CLAUDE_USAGE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
API_URL="${CLAUDE_USAGE_API_URL:-https://api.anthropic.com/api/oauth/usage}"
STATUSLINE="${CLAUDE_USAGE_STATUSLINE:-$(cd "$(dirname "$0")" && pwd)/statusline-usage.sh}"
BACKOFF_FILE="${CLAUDE_USAGE_BACKOFF_FILE:-$HOME/.claude/state/usage-poll-not-before}"
LOCK="${CLAUDE_USAGE_POLL_LOCK:-$HOME/.claude/state/usage-poll.lock}"

warn() { printf 'claude-usage-poll: %s\n' "$*" >&2; }

for command_name in awk curl jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    warn "$command_name is required"
    exit 1
  }
done
[ -x "$STATUSLINE" ] || { warn "statusline logger is not executable: $STATUSLINE"; exit 1; }
[ -r "$CREDENTIALS" ] || { warn "OAuth credentials are not readable: $CREDENTIALS"; exit 1; }

mkdir -p "$(dirname "$BACKOFF_FILE")" "$(dirname "$LOCK")" 2>/dev/null || {
  warn "cannot create poll state directory"
  exit 1
}
umask 077

# systemd and launchd do not overlap starts of the same job. An optional flock
# also suppresses a simultaneous manual run, without leaving a stale lock
# directory behind after a crash. macOS has no flock by default, so it relies
# on the scheduler and the shared logger's portable lock.
if command -v flock >/dev/null 2>&1; then
  : > "$LOCK" 2>/dev/null || { warn "cannot create poll lock"; exit 1; }
  chmod 600 "$LOCK" 2>/dev/null || { warn "cannot protect poll lock"; exit 1; }
  exec 9>"$LOCK"
  flock -n 9 || exit 0
fi

tmp_headers="$(mktemp)" || exit 1
tmp_body="$(mktemp)" || {
  rm -f "$tmp_headers"
  exit 1
}
backoff_tmp="${BACKOFF_FILE}.tmp.$$"
cleanup() {
  rm -f "$tmp_headers" "$tmp_body" "$backoff_tmp"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

now_epoch="$(date +%s)"
not_before=""
if [ -s "$BACKOFF_FILE" ]; then
  read -r not_before _ < "$BACKOFF_FILE" || not_before=""
fi
case "$not_before" in
  ''|*[!0-9]*) ;;
  *) [ "$now_epoch" -lt "$not_before" ] && exit 0 ;;
esac

token="$(jq -er '.claudeAiOauth.accessToken | select(type == "string" and length > 0)' \
  "$CREDENTIALS" 2>/dev/null)" || {
  warn "no Claude.ai OAuth access token"
  exit 1
}
# A newline would inject another curl config directive. OAuth tokens emitted by
# Claude Code use this conservative alphabet; reject anything else.
case "$token" in
  *[!A-Za-z0-9._~-]*) warn "OAuth access token has an unexpected shape"; exit 1 ;;
esac

# Put Authorization in curl's config stdin, never argv, environment, or a temp
# file. Process listings therefore contain only the non-secret endpoint URL.
http_code="$({
  printf 'header = "Authorization: Bearer %s"\n' "$token"
  printf 'header = "anthropic-beta: oauth-2025-04-20"\n'
  printf 'header = "Content-Type: application/json"\n'
  printf 'silent\nshow-error\nmax-time = 5\n'
} | curl --config - --url "$API_URL" \
         --dump-header "$tmp_headers" --output "$tmp_body" \
         --write-out '%{http_code}')" || {
  warn "request failed"
  exit 1
}
unset token

case "$http_code" in
  200) ;;
  401|403)
    warn "OAuth authentication failed (HTTP $http_code); run claude auth login if it persists"
    exit 1
    ;;
  429)
    # Trim the header's trailing CR with a POSIX class rather than matching \r
    # in the pattern: \r inside a regex is a GNU/mawk extension, and this hook
    # is meant to run under the awk macOS ships.
    retry_after="$(awk 'tolower($1) == "retry-after:" {
        value = $2; sub(/[[:space:]]*$/, "", value)
        if (value ~ /^[0-9]+$/) { print value; exit }
      }' "$tmp_headers" 2>/dev/null)"
    case "$retry_after" in ''|*[!0-9]*) retry_after=300 ;; esac
    # The internal endpoint has emitted Retry-After: 0 while continuing to
    # reject the next minute's request. Avoid a retry loop regardless of that
    # unusable hint; longer server-requested delays are still honoured.
    [ "$retry_after" -lt 300 ] && retry_after=300
    if ! printf '%s\n' "$((now_epoch + retry_after))" 2>/dev/null > "$backoff_tmp" ||
       ! mv -f "$backoff_tmp" "$BACKOFF_FILE" 2>/dev/null; then
      warn "cannot persist rate-limit backoff"
      exit 1
    fi
    warn "rate limited; backing off for ${retry_after}s"
    exit 0
    ;;
  *)
    warn "usage endpoint returned HTTP $http_code"
    exit 1
    ;;
esac

# The observed endpoint uses UTC ISO timestamps with fractional seconds. Keep
# conversion deliberately narrow: an unrecognised future shape is an error,
# never a guessed reset boundary.
payload="$(jq -ce '
  def percent:
    tonumber
    | if . >= 0 and . <= 100 then .
      else error("utilization outside 0..100") end;
  def epoch:
    if type == "number" then floor
    elif type == "string" then
      (sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+00:00$"; "Z")
       | sub("\\+00:00$"; "Z") | fromdateiso8601)
    else error("invalid resets_at") end
    | if . > 0 then . else error("invalid resets_at") end;
  def window($w):
    if ($w | type) == "object"
       and $w.utilization != null and $w.resets_at != null then
      {used_percentage: ($w.utilization | percent),
       resets_at: ($w.resets_at | epoch)}
    else null end;
  {model:{display_name:"usage-poller"},
   rate_limits:{five_hour: window(.five_hour), seven_day: window(.seven_day)}}
  | select(.rate_limits.five_hour != null or .rate_limits.seven_day != null)
' "$tmp_body" 2>/dev/null)" || {
  warn "unexpected usage response schema"
  exit 1
}
[ -n "$payload" ] || { warn "usage response contained no supported window"; exit 1; }

status_output="$(printf '%s\n' "$payload" | bash "$STATUSLINE")" || {
  warn "statusline logger failed"
  exit 1
}
case "$status_output" in
  *usage-log!*) warn "statusline logger could not append"; exit 1 ;;
esac

rm -f "$BACKOFF_FILE"
exit 0
