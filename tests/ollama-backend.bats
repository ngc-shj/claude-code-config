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


# Write a host-cache file valid for the CURRENT trust config (discovery off,
# no extra hosts — the setup() default) by prepending the fingerprint header
# the production reader requires. stdin = records.
write_cache() {
  printf '#cfg mdns=0 ts=0 extra=\n' > "$_OLLAMA_HOST_CACHE"
  cat >> "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
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
  unset OLLAMA_DISCOVERY
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
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$result" = "http://gx10-a9c0:11434 http://ul9c-r49:11434" ]
}

@test "discovery: only hosts that answer /api/version join the pool" {
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local printer.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  # printer never answers -> excluded
  [ "$result" = "http://gx10-a9c0:11434 http://ul9c-r49:11434" ]
}

@test "discovery: bare name preferred, .local not double-probed when bare answers" {
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0.local"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0.local:11434" ]
}

@test "discovery: discovery cap bounds probe fan-out" {
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="h1.local h2.local h3.local h4.local h5.local h6.local h7.local h8.local"
  export OLLAMA_DISCOVERY_MAX=3
  setup_curl_fail_mock
  source "$SCRIPT"
  # 3 capped hosts (bare fails -> .local) = 6 probes + 1 localhost fallback probe
  call_count=$(wc -l < "$CURL_LOG_FILE")
  [ "$call_count" -eq 7 ]
}

@test "discovery: unresolved (+) avahi lines do not trigger probes" {
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
  export OLLAMA_EXTRA_HOSTS="ul9c-r49"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "extra hosts: duplicate of an mDNS host is not double-counted" {
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=tailscale
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
  export OLLAMA_DISCOVERY=tailscale
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
  export OLLAMA_DISCOVERY=1
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="ul9c-r49.ts.net gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  # Tailscale probed before mDNS
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "tailscale: no peers reachable falls through to mDNS/localhost" {
  export OLLAMA_DISCOVERY=tailscale
  export TS_DISCOVERED_PEERS="iphone.ts.net vps.ts.net"
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

# ===========================================================================
# localhost handling
# ===========================================================================

@test "localhost: excluded from pool when a remote server is reachable" {
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "localhost: used only when no remote server reachable" {
  export OLLAMA_DISCOVERY=mdns
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
  write_cache <<'CACHE'
http://a:11434
http://b:11434
http://c:11434
CACHE
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
  write_cache <<'CACHE'
http://only:11434
CACHE
  setup_curl_fail_mock
  first=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  second=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$first" = "http://only:11434" ]
  [ "$second" = "http://only:11434" ]
  [ ! -f "$_OLLAMA_HOST_CACHE.rr" ]
}

@test "round-robin: OLLAMA_HOST is always a member of OLLAMA_HOSTS" {
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [[ " $OLLAMA_HOSTS " == *" $OLLAMA_HOST "* ]]
}

@test "round-robin: corrupt counter file is treated as zero" {
  write_cache <<'CACHE'
http://a:11434
http://b:11434
CACHE
  echo "garbage" > "$_OLLAMA_HOST_CACHE.rr"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  [ "$result" = "http://a:11434" ]
}

# ===========================================================================
# Cache behavior
# ===========================================================================

@test "cache: fresh cache returns cached pool without probing" {
  write_cache <<'CACHE'
http://cached-a:11434
http://cached-b:11434
CACHE
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$result" = "http://cached-a:11434 http://cached-b:11434" ]
  [ ! -s "$CURL_LOG_FILE" ]
}

@test "cache: stale cache triggers re-probe" {
  write_cache <<'CACHE'
http://stale-host:11434
CACHE
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
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local ul9c-r49.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [ -f "$_OLLAMA_HOST_CACHE" ]
  # Line 1 is the trust-fingerprint header; records follow. Each record is
  # "<url>\t<models>"; the URL field is what the pool is built from.
  run head -1 "$_OLLAMA_HOST_CACHE"
  [ "$output" = "#cfg mdns=1 ts=0 extra=" ]
  run cut -f1 "$_OLLAMA_HOST_CACHE"
  [ "${lines[1]}" = "http://gx10-a9c0:11434" ]
  [ "${lines[2]}" = "http://ul9c-r49:11434" ]
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
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
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
  export OLLAMA_DISCOVERY=mdns
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
    | write_cache
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
    | write_cache
  setup_curl_fail_mock
  source "$SCRIPT"
  first=$(ollama_host_for_model "gpt-oss:20b")
  second=$(ollama_host_for_model "gpt-oss:20b")
  [ "$first" != "$second" ]
}

@test "model routing: unknown model yields empty (caller skips)" {
  printf 'http://big:11434\tgpt-oss:120b\n' | write_cache
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "llama3:70b")
  [ -z "$result" ]
}

@test "model routing: wildcard (unknown inventory) matches any model" {
  # A server whose models could not be enumerated is stored as '*'.
  printf 'http://mystery:11434\t*\n' | write_cache
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "anything:latest")
  [ "$result" = "http://mystery:11434" ]
}

@test "model routing: tag-less request matches a tagged model" {
  printf 'http://big:11434\tgpt-oss:120b\n' | write_cache
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

# ===========================================================================
# Trust boundary: auto-discovery is opt-in (S1)
# ===========================================================================

@test "trust: mDNS host is ignored by default (no OLLAMA_DISCOVERY)" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
  # The mDNS candidate must never even be probed
  run grep -c 'gx10-a9c0' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: tailscale peer is ignored by default (no OLLAMA_DISCOVERY)" {
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="ul9c-r49.ts.net localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
  run grep -c 'ul9c-r49' "$CURL_LOG_FILE"
  [ "$output" -eq 0 ]
}

@test "trust: OLLAMA_DISCOVERY=mdns enables mDNS only" {
  export OLLAMA_DISCOVERY=mdns
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://gx10-a9c0:11434" ]
}

@test "trust: OLLAMA_DISCOVERY=tailscale enables tailscale only" {
  export OLLAMA_DISCOVERY=tailscale
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434" ]
}

@test "trust: OLLAMA_DISCOVERY='mdns tailscale' enables both" {
  export OLLAMA_DISCOVERY="mdns tailscale"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  # Tailscale probed before mDNS
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "trust: OLLAMA_DISCOVERY=off disables both sources" {
  export OLLAMA_DISCOVERY=off
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

@test "trust: extra hosts work without any discovery opt-in" {
  export OLLAMA_EXTRA_HOSTS="ul9c-r49"
  export CURL_SUCCEED_HOSTS="ul9c-r49"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49:11434" ]
}

# ===========================================================================
# Trust boundary: cache lives in a user-private state dir (S2)
# ===========================================================================

@test "state dir: default cache path is under XDG_RUNTIME_DIR, mode 0700, not /tmp" {
  unset _OLLAMA_HOST_CACHE
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  mkdir -p "$XDG_RUNTIME_DIR"
  export OLLAMA_EXTRA_HOSTS="gx10-a9c0"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ -f "$XDG_RUNTIME_DIR/claude-llm-hooks/ollama-host-cache" ]
  mode=$(stat -c %a "$XDG_RUNTIME_DIR/claude-llm-hooks" 2>/dev/null \
    || stat -f %Lp "$XDG_RUNTIME_DIR/claude-llm-hooks")
  [ "$mode" = "700" ]
}

@test "state dir: falls back to XDG_CACHE_HOME when XDG_RUNTIME_DIR unset" {
  unset _OLLAMA_HOST_CACHE
  unset XDG_RUNTIME_DIR
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$XDG_CACHE_HOME"
  export OLLAMA_EXTRA_HOSTS="gx10-a9c0"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  source "$SCRIPT"
  [ -f "$XDG_CACHE_HOME/claude-llm-hooks/ollama-host-cache" ]
}

@test "state dir: symlinked claude-llm-hooks dir is rejected, next base used" {
  unset _OLLAMA_HOST_CACHE
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" "$BATS_TEST_TMPDIR/evil"
  ln -s "$BATS_TEST_TMPDIR/evil" "$XDG_RUNTIME_DIR/claude-llm-hooks"
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(_llm_state_dir)
  [ "$result" = "$XDG_CACHE_HOME/claude-llm-hooks" ]
}

@test "trust: OLLAMA_DISCOVERY=on enables both sources" {
  export OLLAMA_DISCOVERY=on
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "trust: OLLAMA_DISCOVERY=all enables both sources" {
  export OLLAMA_DISCOVERY=all
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "trust: OLLAMA_DISCOVERY=none disables both sources" {
  export OLLAMA_DISCOVERY=none
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

@test "trust: OLLAMA_DISCOVERY='mdns,tailscale' (comma form) enables both" {
  export OLLAMA_DISCOVERY="mdns,tailscale"
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export TS_DISCOVERED_PEERS="ul9c-r49.ts.net"
  export CURL_SUCCEED_HOSTS="gx10-a9c0 ul9c-r49.ts.net"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://ul9c-r49.ts.net:11434 http://gx10-a9c0:11434" ]
}

@test "trust: symlinked rr counter file is not trusted (idx treated as 0)" {
  write_cache <<'CACHE'
http://a:11434
http://b:11434
CACHE
  echo "1" > "$BATS_TEST_TMPDIR/attacker-rr"
  ln -s "$BATS_TEST_TMPDIR/attacker-rr" "$_OLLAMA_HOST_CACHE.rr"
  setup_curl_fail_mock
  result=$(source "$SCRIPT" && echo "$OLLAMA_HOST")
  # Untrusted counter must be ignored: idx stays 0 -> first pool member
  [ "$result" = "http://a:11434" ]
}

@test "state dir: falls back to ~/.cache when both XDG vars are unset" {
  setup_curl_fail_mock
  export OLLAMA_HOST="http://pinned:9999"
  source "$SCRIPT"
  result=$(
    unset XDG_RUNTIME_DIR XDG_CACHE_HOME
    HOME="$BATS_TEST_TMPDIR/home"; export HOME
    mkdir -p "$HOME/.cache"
    _llm_state_dir
  )
  [ "$result" = "$BATS_TEST_TMPDIR/home/.cache/claude-llm-hooks" ]
  [ -d "$result" ]
}

@test "state dir: falls back to a private mktemp dir when no base dir is usable" {
  setup_curl_fail_mock
  export OLLAMA_HOST="http://pinned:9999"
  source "$SCRIPT"
  result=$(
    unset XDG_RUNTIME_DIR XDG_CACHE_HOME HOME
    TMPDIR="$BATS_TEST_TMPDIR"; export TMPDIR
    _llm_state_dir
  )
  case "$result" in
    "$BATS_TEST_TMPDIR/claude-llm-hooks-"*) ;;
    *) echo "unexpected state dir: $result"; return 1 ;;
  esac
  [ -d "$result" ]
  mode=$(stat -c %a "$result" 2>/dev/null || stat -f %Lp "$result")
  [ "$mode" = "700" ]
}

# ===========================================================================
# Trust boundary: cache is bound to the trust configuration (S3)
# ===========================================================================

@test "trust: cached discovery pool is not reused after OLLAMA_DISCOVERY is revoked" {
  export AVAHI_DISCOVERED_HOSTS="evil.local"
  export CURL_SUCCEED_HOSTS="evil localhost"
  setup_curl_mock
  first=$(export OLLAMA_DISCOVERY=mdns; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$first" = "http://evil:11434" ]
  # Opt-in revoked (OLLAMA_DISCOVERY unset): the still-fresh cache written
  # under the opt-in must NOT be served
  second=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$second" = "http://localhost:11434" ]
}

@test "trust: cached pool is invalidated when the discovery source set changes" {
  export AVAHI_DISCOVERED_HOSTS="evil.local"
  export TS_DISCOVERED_PEERS="good.ts.net"
  export CURL_SUCCEED_HOSTS="evil good.ts.net"
  setup_curl_mock
  first=$(export OLLAMA_DISCOVERY=mdns; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$first" = "http://evil:11434" ]
  second=$(export OLLAMA_DISCOVERY=tailscale; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$second" = "http://good.ts.net:11434" ]
}

@test "trust: cached pool is invalidated when OLLAMA_EXTRA_HOSTS is removed" {
  export CURL_SUCCEED_HOSTS="extra1 localhost"
  setup_curl_mock
  first=$(export OLLAMA_EXTRA_HOSTS="extra1"; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$first" = "http://extra1:11434" ]
  second=$(source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$second" = "http://localhost:11434" ]
}

@test "trust: alias spellings of the same source set share the cache" {
  export AVAHI_DISCOVERED_HOSTS="gx10-a9c0.local"
  export CURL_SUCCEED_HOSTS="gx10-a9c0"
  setup_curl_mock
  first=$(export OLLAMA_DISCOVERY=1; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$first" = "http://gx10-a9c0:11434" ]
  probes_after_first=$(wc -l < "$CURL_LOG_FILE")
  # 1 vs all: same effective source set -> normalized fingerprint matches,
  # cache reused, no re-probe
  second=$(export OLLAMA_DISCOVERY=all; source "$SCRIPT" && echo "$OLLAMA_HOSTS")
  [ "$second" = "http://gx10-a9c0:11434" ]
  [ "$(wc -l < "$CURL_LOG_FILE")" -eq "$probes_after_first" ]
}

@test "trust: model routing ignores a cache written under a different trust config" {
  printf '#cfg mdns=1 ts=0 extra=\nhttp://evil:11434\t*\n' > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "gpt-oss:20b")
  [ "$result" = "http://localhost:11434" ]
}

@test "trust: legacy cache without fingerprint header is not reused" {
  echo "http://legacy:11434" > "$_OLLAMA_HOST_CACHE"
  touch "$_OLLAMA_HOST_CACHE"
  export CURL_SUCCEED_HOSTS="localhost"
  setup_curl_mock
  source "$SCRIPT"
  [ "$OLLAMA_HOSTS" = "http://localhost:11434" ]
}

@test "model routing: stale cache is not reused; falls back to default host" {
  printf 'http://big:11434\tgpt-oss:120b\n' | write_cache
  set_mtime_ago "$_OLLAMA_HOST_CACHE" 600
  setup_curl_fail_mock
  source "$SCRIPT"
  result=$(ollama_host_for_model "gpt-oss:120b")
  [ "$result" = "http://localhost:11434" ]
}
