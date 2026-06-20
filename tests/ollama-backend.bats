#!/usr/bin/env bats
# Tests for hooks/ollama-backend.sh (the Ollama provider).
# Sourced via hooks/llm-utils.sh, which defines the shared discovery helpers
# (_models_have / _pick_round_robin / _rr_suffix) the provider relies on.
# Mocks curl and avahi-browse to avoid real network calls.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/hooks/llm-utils.sh"

# ---------------------------------------------------------------------------
# Helper: mock curl. Logs every probed URL. /api/version succeeds when the URL
# matches a CURL_SUCCEED_HOSTS substring. /api/tags returns a models JSON drawn
# from MOCK_MODELS (newline-separated "hostsubstr=modelA,modelB" lines), or an
# empty model list when no mapping matches.
# Usage: export CURL_SUCCEED_HOSTS="substr1 substr2"; setup_curl_mock
# ---------------------------------------------------------------------------
setup_curl_mock() {
  cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/bin/bash
LOG_FILE="${CURL_LOG_FILE:-/dev/null}"
URL=""
for arg in "$@"; do
  case "$arg" in
    http://*) URL="$arg"; echo "$arg" >> "$LOG_FILE" ;;
  esac
done

case "$URL" in
  */api/tags)
    models=""
    while IFS='=' read -r hsub mlist; do
      [ -z "$hsub" ] && continue
      if [[ "$URL" == *"$hsub"* ]]; then models="$mlist"; break; fi
    done <<< "${MOCK_MODELS:-}"
    printf '{"models":['
    if [ -n "$models" ]; then
      first=1
      IFS=',' read -ra arr <<< "$models"
      for m in "${arr[@]}"; do
        [ "$first" -eq 1 ] || printf ','
        printf '{"name":"%s"}' "$m"
        first=0
      done
    fi
    printf ']}'
    exit 0
    ;;
esac

SUCCEED_HOSTS_STR="${CURL_SUCCEED_HOSTS:-}"
for h in $SUCCEED_HOSTS_STR; do
  if [[ "$URL" == *"$h"* ]]; then
    printf '000'
    exit 0
  fi
done
printf '000'
exit 28
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# Mock curl that always fails (all hosts unreachable)
setup_curl_fail_mock() {
  export CURL_SUCCEED_HOSTS=""
  setup_curl_mock
}

# ---------------------------------------------------------------------------
# Helper: mock avahi-browse that emits hosts from AVAHI_DISCOVERED_HOSTS
# (space-separated). Always installed in setup() so real avahi-browse never runs.
# ---------------------------------------------------------------------------
setup_avahi_mock() {
  cat > "$BATS_TEST_TMPDIR/avahi-browse" <<'EOF'
#!/bin/bash
HOSTS="${AVAHI_DISCOVERED_HOSTS:-}"
for h in $HOSTS; do
  printf '=;eth0;IPv4;workstation;_workstation._tcp;local;%s;192.168.1.10;9;\n' "$h"
done
EOF
  chmod +x "$BATS_TEST_TMPDIR/avahi-browse"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

# Cross-platform: set file mtime to N seconds ago
set_mtime_ago() {
  local file="$1" seconds_ago="$2"
  local target_ts
  target_ts=$(( $(date +%s) - seconds_ago ))
  if touch -d "@$target_ts" "$file" 2>/dev/null; then
    return
  fi
  python3 -c "import os; os.utime('$file', ($target_ts, $target_ts))" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Helper: mock tailscale CLI. `tailscale status --json` emits an online peer
# per FQDN in TS_DISCOVERED_PEERS (space-separated). Always installed in setup()
# so the real tailscale CLI never runs from tests.
# ---------------------------------------------------------------------------
setup_tailscale_mock() {
  cat > "$BATS_TEST_TMPDIR/tailscale" <<'EOF'
#!/bin/bash
# Only `status --json` is exercised.
printf '{"Peer":{'
first=1
i=0
for p in ${TS_DISCOVERED_PEERS:-}; do
  [ "$first" -eq 1 ] || printf ','
  printf '"k%d":{"Online":true,"DNSName":"%s.","HostName":"%s"}' "$i" "$p" "$p"
  first=0
  i=$((i+1))
done
printf '}}'
EOF
  chmod +x "$BATS_TEST_TMPDIR/tailscale"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  export _OLLAMA_HOST_CACHE="$BATS_TEST_TMPDIR/.ollama-host-cache"
  export CURL_LOG_FILE="$BATS_TEST_TMPDIR/curl-calls.log"
  unset OLLAMA_HOST
  unset OLLAMA_HOSTS
  unset AVAHI_DISCOVERED_HOSTS
  unset TS_DISCOVERED_PEERS
  setup_avahi_mock
  setup_tailscale_mock
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# ===========================================================================
# OLLAMA_HOST env var takes precedence
# ===========================================================================

@test "env var: OLLAMA_HOST set returns it directly without probing" {
  export OLLAMA_HOST="http://custom:9999"
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://custom:9999" ]
}

@test "env var: OLLAMA_HOST set also sets OLLAMA_HOSTS to that one server" {
  export OLLAMA_HOST="http://custom:9999"
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$result" = "http://custom:9999" ]
}

@test "env var: OLLAMA_HOST set does not create cache file" {
  export OLLAMA_HOST="http://custom:9999"
  source "$SCRIPT"
  [ ! -f "$_OLLAMA_HOST_CACHE" ]
}

# ===========================================================================
# Probe-based discovery (name-independent)
# ===========================================================================

@test "discovery: any reachable host is recognized regardless of name prefix" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$result" = "http://gx10-a9c0:11434 http://ul9c-r49:11434" ]
}

@test "discovery: only hosts that answer /api/version join the pool" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local printer.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  # printer never answers -> excluded
  [ "$result" = "http://gx10-a9c0:11434 http://ul9c-r49:11434" ]
}

@test "discovery: bare name preferred, .local not double-probed when bare answers" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  # bare answers on first probe -> .local is never tried (no .local URL logged)
  run grep -c '\.local' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "discovery: falls back to .local when bare is unreachable" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0.local"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0.local:11434" ]
}

@test "discovery: discovery cap bounds probe fan-out" {
  export AVAHI_DISCOVERED_HOSTS="h1.local h2.local h3.local h4.local h5.local h6.local h7.local h8.local"
  export OLLAMA_DISCOVERY_MAX=3
  setup_curl_fail_mock
  source "$SCRIPT"
  # 3 capped hosts (bare fails -> .local) = 6 probes + 1 localhost fallback probe
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 7 ]
}

@test "discovery: unresolved (+) avahi lines do not trigger probes" {
  cat > "$BATS_TEST_TMPDIR/avahi-browse" <<'EOF'
#!/bin/bash
echo "+;eth0;IPv4;gx10-ghost;_workstation._tcp;local"
EOF
  chmod +x "$BATS_TEST_TMPDIR/avahi-browse"
  setup_curl_fail_mock
  source "$SCRIPT"
  # only the localhost fallback probe
  run cat "$CURL_LOG_FILE"
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "http://localhost:11434/api/version" ]
}

@test "discovery: missing avahi-browse probes only localhost" {
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "avahi-browse" ]; then
      return 1
    fi
    builtin command "$@"
  }
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

# ===========================================================================
# OLLAMA_EXTRA_HOSTS (hosts mDNS cannot see, e.g. Tailscale peers)
# ===========================================================================

@test "extra hosts: a reachable extra host joins the pool" {
  export OLLAMA_EXTRA_HOSTS="ul9c-r49"
  export CURL_SUCCEED_HOSTS="ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49:11434" ]
}

@test "extra hosts: probed before mDNS hosts (explicit priority)" {
  export OLLAMA_EXTRA_HOSTS="ul9c-r49"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="ul9c-r49 gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49:11434 http://gx10-a9c0:11434" ]
}

@test "extra hosts: host:port form is honored" {
  export OLLAMA_EXTRA_HOSTS="ul9c-r49:11500"
  export CURL_SUCCEED_HOSTS="ul9c-r49:11500"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49:11500" ]
}

@test "extra hosts: full URL form is honored" {
  export OLLAMA_EXTRA_HOSTS="http://ul9c-r49:11434"
  export CURL_SUCCEED_HOSTS="ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49:11434" ]
}

@test "extra hosts: unreachable extra host is excluded" {
  export OLLAMA_EXTRA_HOSTS="ul9c-r49"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "extra hosts: duplicate of an mDNS host is not double-counted" {
  export OLLAMA_EXTRA_HOSTS="gx10-a9c0"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

# ===========================================================================
# Tailscale peer auto-discovery (no hardcoded hostnames)
# ===========================================================================

@test "tailscale: an online peer hosting Ollama joins the pool" {
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net iphone.ts.net"
  export CURL_SUCCEED_HOSTS="ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  # iphone never answers /api/version -> excluded; only ul9c-r49 remains
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434" ]
}

@test "tailscale: TAILSCALE_BIN override resolves the CLI path (macOS app-bundle case)" {
  # Simulate the macOS app bundle: a `Tailscale` binary at a non-PATH location.
  mkdir -p "$BATS_TEST_TMPDIR/app"
  printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/app/Tailscale"
  chmod +x "$BATS_TEST_TMPDIR/app/Tailscale"
  export TAILSCALE_BIN="$BATS_TEST_TMPDIR/app/Tailscale"
  result=$(source "$SCRIPT" && _tailscale_bin)
  [ "$result" = "$BATS_TEST_TMPDIR/app/Tailscale" ]
}

@test "tailscale: a peer discovered via TAILSCALE_BIN override joins the pool" {
  # The PATH `tailscale` mock emits path-peer (which never answers /api/version);
  # the override binary emits override-peer (which does). Seeing override-peer in
  # the pool proves the override CLI was the one actually invoked.
  export TS_DISCOVERED_PEERS="path-peer.ts.net"
  mkdir -p "$BATS_TEST_TMPDIR/app"
  cat > "$BATS_TEST_TMPDIR/app/Tailscale" <<'EOF'
#!/bin/bash
printf '{"Peer":{"k0":{"Online":true,"DNSName":"override-peer.ts.net.","HostName":"override-peer"}}}'
EOF
  chmod +x "$BATS_TEST_TMPDIR/app/Tailscale"
  export TAILSCALE_BIN="$BATS_TEST_TMPDIR/app/Tailscale"
  export CURL_SUCCEED_HOSTS="override-peer.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://override-peer.ts.net:11434" ]
}

@test "tailscale: peers and mDNS hosts are both discovered and merged" {
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="ul9c-r49.ts.net gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  # Tailscale probed before mDNS
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "tailscale: no peers reachable falls through to mDNS/localhost" {
  export TS_DISCOVERED_PEERS="iphone.ts.net vps.ts.net"
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

# ===========================================================================
# macOS mDNS fallback (dns-sd) — Linux box can't run real dns-sd, so the parser
# is unit-tested against a mock emitting documented `dns-sd -B` output. The
# avahi-vs-dns-sd selection and live behavior are validated on macOS.
# ===========================================================================

@test "mDNS dns-sd fallback: parses _workstation Add rows into .local hostnames" {
  # Pin OLLAMA_HOST so sourcing skips discovery (avoids any real avahi-browse on
  # this box); then exercise the dns-sd parser directly.
  export OLLAMA_HOST="http://dummy:11434"
  cat > "$BATS_TEST_TMPDIR/dns-sd" <<'EOF'
#!/bin/bash
printf 'Browsing for _workstation._tcp.local.\n'
printf 'Timestamp     A/R Flags if Domain Service Type Instance Name\n'
printf '12:00:00.000  Add 2 en0 local. _workstation._tcp. gx10-a9c0 [aa:bb:cc:dd:ee:ff]\n'
printf '12:00:00.001  Add 2 en0 local. _workstation._tcp. plainhost\n'
printf '12:00:00.002  Rmv 2 en0 local. _workstation._tcp. gonehost [11:22:33:44:55:66]\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/dns-sd"
  export OLLAMA_MDNS_BROWSE_SECS=0
  source "$SCRIPT"
  result=$(_discover_mdns_hosts_dnssd)
  [ "$result" = "gx10-a9c0.local
plainhost.local" ]
}

# ===========================================================================
# localhost handling
# ===========================================================================

@test "localhost: excluded from pool when a remote server is reachable" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "localhost: used only when no remote server reachable" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
  [ "$OLLAMA_HOST" = "http://localhost:11434" ]
}

# ===========================================================================
# Load-balancing (round-robin selection)
# ===========================================================================

@test "round-robin: successive sources rotate through the pool" {
  echo "http://a:11434
http://b:11434
http://c:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  first=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  second=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  third=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  fourth=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$first" = "http://a:11434" ]
  [ "$second" = "http://b:11434" ]
  [ "$third" = "http://c:11434" ]
  [ "$fourth" = "http://a:11434" ]
}

@test "round-robin: single-server pool always returns that server" {
  echo "http://only:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  first=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  second=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$first" = "http://only:11434" ]
  [ "$second" = "http://only:11434" ]
  [ ! -f "$_OLLAMA_HOST_CACHE.rr" ]
}

@test "round-robin: OLLAMA_HOST is always a member of OLLAMA_HOSTS" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [[ " $OLLAMA_HOSTS " == *" $OLLAMA_HOST "* ]]
}

@test "round-robin: corrupt counter file is treated as zero" {
  echo "http://a:11434
http://b:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  echo "garbage" > "$_OLLAMA_HOST_CACHE.rr"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://a:11434" ]
}

# ===========================================================================
# Cache behavior
# ===========================================================================

@test "cache: fresh cache returns cached pool without probing" {
  echo "http://cached-a:11434
http://cached-b:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$result" = "http://cached-a:11434 http://cached-b:11434" ]
  [ ! -s "$CURL_LOG_FILE" ]
}

@test "cache: stale cache triggers re-probe" {
  echo "http://stale-host:11434" > "$_OLLAMA_HOST_CACHE"
  set_mtime_ago "$_OLLAMA_HOST_CACHE" 600
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://localhost:11434" ]
  [ -s "$CURL_LOG_FILE" ]
}

@test "cache: symlink cache is ignored" {
  echo "http://symlink-target:11434" > "$BATS_TEST_TMPDIR/real-cache"
  ln -s "$BATS_TEST_TMPDIR/real-cache" "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://localhost:11434" ]
}

@test "cache write: creates cache file listing the reachable pool" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [ -f "$_OLLAMA_HOST_CACHE" ]
  # Each line is "<url>\t<models>"; the URL field is what the pool is built from.
  run cut -f1 "$_OLLAMA_HOST_CACHE"
  [ "${lines[0]}" = "http://gx10-a9c0:11434" ]
  [ "${lines[1]}" = "http://ul9c-r49:11434" ]
}

@test "cache write: does not create cache on fallback to localhost" {
  setup_curl_fail_mock
  source "$SCRIPT"
  [ ! -f "$_OLLAMA_HOST_CACHE" ]
}

# ===========================================================================
# Fallback
# ===========================================================================

@test "fallback: nothing reachable returns localhost for both vars" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  setup_curl_fail_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOST" = "http://localhost:11434" ]
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

# ===========================================================================
# Export
# ===========================================================================

@test "export: OLLAMA_HOST and OLLAMA_HOSTS are exported after sourcing" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  run bash -c 'echo "$OLLAMA_HOST|$OLLAMA_HOSTS"'
  [ "$output" = "http://gx10-a9c0:11434|http://gx10-a9c0:11434" ]
}

# ===========================================================================
# Idempotent sourcing within the cache window
# ===========================================================================

@test "idempotent: second source within window does not re-probe" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  after_first=$(wc -l < "$CURL_LOG_FILE")
  source "$SCRIPT"
  after_second=$(wc -l < "$CURL_LOG_FILE")
  # Second source hits the fresh cache — adds no probes.
  [ "$after_first" -eq "$after_second" ]
}

# ===========================================================================
# Model-aware routing (ollama_host_for_model)
# ===========================================================================

@test "model routing: only servers hosting the model are candidates" {
  printf 'http://big:11434\tgpt-oss:120b gpt-oss:20b\nhttp://small:11434\tgpt-oss:20b\n' \
    > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  # 120b lives only on big — every pick must be big
  a=$(ollama_host_for_model "gpt-oss:120b")
  b=$(ollama_host_for_model "gpt-oss:120b")
  [ "$a" = "http://big:11434" ]
  [ "$b" = "http://big:11434" ]
}

@test "model routing: shared model round-robins across hosts that have it" {
  printf 'http://big:11434\tgpt-oss:120b gpt-oss:20b\nhttp://small:11434\tgpt-oss:20b\n' \
    > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  first=$(ollama_host_for_model "gpt-oss:20b")
  second=$(ollama_host_for_model "gpt-oss:20b")
  [ "$first" != "$second" ]
}

@test "model routing: unknown model yields empty (caller skips)" {
  printf 'http://big:11434\tgpt-oss:120b\n' > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "llama3:70b")
  [ -z "$result" ]
}

@test "model routing: wildcard (unknown inventory) matches any model" {
  # A server whose models could not be enumerated is stored as '*'.
  printf 'http://mystery:11434\t*\n' > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "anything:latest")
  [ "$result" = "http://mystery:11434" ]
}

@test "model routing: tag-less request matches a tagged model" {
  printf 'http://big:11434\tgpt-oss:120b\n' > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "gpt-oss")
  [ "$result" = "http://big:11434" ]
}

@test "model routing: pinned OLLAMA_HOST ignores model filtering" {
  export OLLAMA_HOST="http://pinned:9999"
  source "$SCRIPT"
  result=$(ollama_host_for_model "any-model")
  [ "$result" = "http://pinned:9999" ]
}

@test "model routing: model inventory is captured from /api/tags into cache" {
  export OLLAMA_EXTRA_HOSTS="big small"
  export CURL_SUCCEED_HOSTS="big small"
  export MOCK_MODELS="big=gpt-oss:120b,gpt-oss:20b
small=gpt-oss:20b"
  setup_curl_mock
  source "$SCRIPT"
  # 120b only on big
  [ "$(ollama_host_for_model "gpt-oss:120b")" = "http://big:11434" ]
}
