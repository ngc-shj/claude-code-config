#!/bin/bash
# Resolve Ollama server(s): honor env var, otherwise auto-detect every reachable
# server on the LAN and load-balance across them — model-aware, so a request is
# only ever routed to a server that actually hosts the requested model (the
# servers are NOT guaranteed to hold the same model set).
#
# Sourcing this file sets and exports:
#   OLLAMA_HOSTS — space-separated list of ALL reachable Ollama base URLs
#   OLLAMA_HOST  — ONE server picked round-robin from OLLAMA_HOSTS (model-agnostic
#                  default, kept for back-compat)
# …and defines the function:
#   ollama_host_for_model <model> — echo a reachable base URL that hosts <model>,
#                  picked round-robin; empty if no reachable server has it.
#
# Generate callers should resolve their target with ollama_host_for_model so a
# server missing the model is never selected. Callers reading only $OLLAMA_HOST
# keep working but may hit a server lacking their model.
#
# Inputs (env):
#   OLLAMA_HOST        — if set, pins to that one server; discovery is skipped.
#   OLLAMA_EXTRA_HOSTS — manual escape hatch: space-separated hosts to probe in
#                        ADDITION to auto-discovery, for hosts that neither mDNS
#                        nor Tailscale can enumerate. Normally unneeded — online
#                        Tailscale peers are discovered automatically. Each entry
#                        is a bare hostname, host:port, or URL.
#   OLLAMA_DISCOVERY_MAX — cap on candidates probed per discovery source (default 6).
#
# Must NOT read stdin (sourced before INPUT=$(cat) in commit-msg-check.sh).
# Safe under set -euo pipefail — all fallible commands guarded with || true.

_OLLAMA_CACHE_FILE="${_OLLAMA_HOST_CACHE:-/tmp/.ollama-host-cache-$(id -u)}"
# Field separator between a cached server's URL and its model list. Kept in a
# variable (not a literal tab) so editors/linters cannot silently mangle it.
_OLLAMA_TAB=$'\t'

# Discover mDNS hostnames advertised on the LAN. Name-independent by design:
# an Ollama server is identified by a live /api/version response (see
# _probe_servers), NOT by a hostname prefix — so any host that actually serves
# Ollama is picked up, whatever it is named. Capped so a LAN advertising many
# hosts cannot stall the hook (each candidate costs up to --max-time 2 s of
# curl probe time on a cache miss). Override the cap with OLLAMA_DISCOVERY_MAX.
_discover_mdns_hosts() {
  command -v avahi-browse >/dev/null 2>&1 || return 0
  local max="${OLLAMA_DISCOVERY_MAX:-6}"
  avahi-browse -atrp 2>/dev/null \
    | awk -F';' '$1 == "=" && $7 != "" { print $7 }' \
    | sort -u \
    | head -n "$max"
}

# Discover online Tailscale peers by their MagicDNS FQDN. Same essence-driven
# model as mDNS — a peer is only kept downstream if it answers /api/version, so
# probing the iPhone or a VPS is harmless. Peers without a DNSName (funnel infra
# nodes) are ignored. Requires the tailscale CLI + jq; silently skipped if
# either is missing. This removes any need to hardcode off-LAN hostnames.
_discover_tailscale_hosts() {
  command -v tailscale >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local max="${OLLAMA_DISCOVERY_MAX:-6}"
  tailscale status --json 2>/dev/null \
    | jq -r '.Peer[]? | select(.Online == true) | select(.DNSName != "") | .DNSName' 2>/dev/null \
    | sed 's/\.$//' \
    | sort -u \
    | head -n "$max"
}

# Probe one base URL's /api/version. Returns 0 if it answers like Ollama.
_is_ollama_up() {
  curl -sf --connect-timeout 1 --max-time 2 "$1/api/version" >/dev/null 2>&1
}

# Fetch a server's installed model names as a space-separated list. Emits '*'
# (wildcard — eligible for any model) when the inventory cannot be determined
# (no jq, /api/tags unreachable, or empty) so a server is never WRONGLY excluded;
# model filtering only drops a server when its known, non-empty list lacks the
# requested model.
_fetch_models() {
  command -v jq >/dev/null 2>&1 || { printf '*'; return; }
  local body
  body=$(curl -sf --connect-timeout 1 --max-time 3 "$1/api/tags" 2>/dev/null) || true
  [ -z "$body" ] && { printf '*'; return; }
  local models
  models=$(printf '%s' "$body" | jq -r '.models[]?.name' 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  [ -z "$models" ] && { printf '*'; return; }
  printf '%s' "$models"
}

# Resolve a single host entry to its reachable Ollama base URL (empty if down).
# Accepts a full URL, a host:port, or a bare/.local hostname. For a bare name
# the plain form is preferred over its .local form (one URL per host, never
# both) — avahi returns .local FQDNs, but bare covers /etc/hosts and DNS.
_probe_host_entry() {
  local entry="$1"
  case "$entry" in
    http://*|https://*)
      _is_ollama_up "$entry" && echo "$entry" ;;
    *:*)
      _is_ollama_up "http://$entry" && echo "http://$entry" ;;
    *)
      local bare="${entry%.local}"
      if _is_ollama_up "http://${bare}:11434"; then
        echo "http://${bare}:11434"
      elif [ "$bare" != "$entry" ] && _is_ollama_up "http://${entry}:11434"; then
        echo "http://${entry}:11434"
      fi ;;
  esac
}

# Discover every reachable Ollama server. Emits one TAB-separated record per
# physical host: "<base_url>\t<space-separated models or '*'>". Candidates come
# from three sources, probed in order:
#   1. OLLAMA_EXTRA_HOSTS — manual escape hatch for hosts neither mDNS nor
#      Tailscale can enumerate. Space-separated bare hostname, host:port, or URL.
#   2. Online Tailscale peers (MagicDNS FQDNs).
#   3. mDNS-advertised hosts on the local LAN.
# Duplicates (same base URL) are dropped. localhost is emitted only when NO
# remote server is reachable — the load-balance pool should target dedicated
# inference hosts, not the machine already running Claude.
_probe_servers() {
  local entries=()
  local e
  for e in ${OLLAMA_EXTRA_HOSTS:-}; do
    [ -n "$e" ] && entries+=("$e")
  done
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    entries+=("$e")
  done < <(_discover_tailscale_hosts)
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    entries+=("$e")
  done < <(_discover_mdns_hosts)

  local records=()
  local seen=" "
  local url
  for e in "${entries[@]:-}"; do
    [ -z "$e" ] && continue
    url=$(_probe_host_entry "$e")
    [ -z "$url" ] && continue
    case "$seen" in *" $url "*) continue;; esac
    seen="$seen$url "
    records+=("${url}${_OLLAMA_TAB}$(_fetch_models "$url")")
  done

  if [ "${#records[@]}" -gt 0 ]; then
    printf '%s\n' "${records[@]}"
    return
  fi

  # No remote inference host reachable — fall back to localhost.
  if _is_ollama_up "http://localhost:11434"; then
    printf '%s\t%s\n' "http://localhost:11434" "$(_fetch_models "http://localhost:11434")"
  fi
}

# Pick one URL round-robin and advance the shared counter. Best-effort and
# lock-free: a race between parallel processes only skews distribution slightly,
# which load balancing tolerates. Portable (no flock) so it works on macOS bash.
_pick_round_robin() {
  local rr_file="$1"; shift
  local pool=("$@")
  local n=${#pool[@]}
  if [ "$n" -eq 1 ]; then
    echo "${pool[0]}"
    return
  fi

  local idx=0
  if [ -f "$rr_file" ] && ! [ -L "$rr_file" ]; then
    idx=$(cat "$rr_file" 2>/dev/null || echo 0)
  fi
  case "$idx" in (''|*[!0-9]*) idx=0;; esac

  if ! [ -L "$rr_file" ]; then
    local tmp
    tmp=$(mktemp "${rr_file}.XXXXXX" 2>/dev/null) || true
    if [ -n "${tmp:-}" ]; then
      echo "$(( (idx + 1) % n ))" > "$tmp"
      mv "$tmp" "$rr_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    fi
  fi

  echo "${pool[$(( idx % n ))]}"
}

# Does a model list (space-separated, or '*') satisfy the requested model?
# Matches exact, "<want>:latest", and tag-less "<want>" against "<want>:*".
_models_have() {
  local list="$1" want="$2" m
  [ "$list" = "*" ] && return 0
  for m in $list; do
    [ "$m" = "$want" ] && return 0
    [ "$m" = "${want}:latest" ] && return 0
    case "$want" in
      *:*) ;;
      *) case "$m" in "${want}:"*) return 0;; esac ;;
    esac
  done
  return 1
}

# Sanitize a model name into a filename-safe round-robin counter suffix.
_rr_suffix() {
  local s="$1"
  printf '%s' "${s//[^a-zA-Z0-9]/_}"
}

# Public: echo a reachable base URL hosting <model>, picked round-robin among
# all servers that have it. Empty output means no reachable server has it — the
# caller should treat that as "model unavailable" and skip gracefully.
ollama_host_for_model() {
  local want="$1"

  # Pinned override or nothing discovered: defer to the single OLLAMA_HOST.
  if [ -n "${_OLLAMA_PINNED:-}" ]; then
    echo "${OLLAMA_HOST:-}"
    return
  fi
  local cache="$_OLLAMA_CACHE_FILE"
  if [ -z "${cache:-}" ] || ! [ -f "$cache" ] || [ -L "$cache" ]; then
    echo "${OLLAMA_HOST:-http://localhost:11434}"
    return
  fi

  local candidates=()
  local line url models
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "${line%%"$_OLLAMA_TAB"*}" = "$line" ]; then
      url="$line"; models='*'   # legacy/plain line (no TAB) → wildcard
    else
      url="${line%%"$_OLLAMA_TAB"*}"; models="${line#*"$_OLLAMA_TAB"}"
    fi
    _models_have "$models" "$want" && candidates+=("$url")
  done < "$cache"

  [ "${#candidates[@]}" -eq 0 ] && return
  _pick_round_robin "${cache}.rr.$(_rr_suffix "$want")" "${candidates[@]}"
}

_resolve_ollama_servers() {
  local cache_file="$_OLLAMA_CACHE_FILE"

  local records_blob=""
  # Use cache if it exists, is a regular file (not symlink), and fresh (< 5 min)
  if [ -f "$cache_file" ] && ! [ -L "$cache_file" ]; then
    local mtime
    mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
    if [ "$(( $(date +%s) - mtime ))" -lt 300 ]; then
      records_blob=$(cat "$cache_file")
    fi
  fi

  if [ -z "$records_blob" ]; then
    records_blob=$(_probe_servers)
    # Cache the discovered list (atomic write; skip if path is a symlink).
    if [ -n "$records_blob" ] && ! [ -L "$cache_file" ]; then
      local tmp
      tmp=$(mktemp "${cache_file}.XXXXXX" 2>/dev/null) || true
      if [ -n "${tmp:-}" ]; then
        printf '%s\n' "$records_blob" > "$tmp"
        mv "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
      fi
    fi
  fi

  local pool=()
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    pool+=("${line%%"$_OLLAMA_TAB"*}")
  done <<< "$records_blob"

  # Nothing reachable — fall back to localhost without caching.
  if [ "${#pool[@]}" -eq 0 ]; then
    OLLAMA_HOSTS="http://localhost:11434"
    OLLAMA_HOST="http://localhost:11434"
    return
  fi

  OLLAMA_HOSTS="${pool[*]}"
  OLLAMA_HOST="$(_pick_round_robin "${cache_file}.rr" "${pool[@]}")"
}

if [ -n "${OLLAMA_HOST:-}" ]; then
  # Explicit override: pin to the caller-supplied server, no discovery.
  OLLAMA_HOSTS="$OLLAMA_HOST"
  _OLLAMA_PINNED=1
else
  _resolve_ollama_servers
fi

export OLLAMA_HOST OLLAMA_HOSTS
