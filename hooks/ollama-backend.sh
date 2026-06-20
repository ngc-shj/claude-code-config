#!/bin/bash
# Ollama backend provider (Ollama-specific processing). Sourced by llm-utils.sh
# AFTER it defines the shared helpers (_models_have, _pick_round_robin,
# _rr_suffix); this file uses them and must not be sourced standalone.
#
# Resolve Ollama server(s): honor env var, otherwise auto-detect every reachable
# server on the LAN and load-balance across them — model-aware, so a request is
# only ever routed to a server that actually hosts the requested model (the
# servers are NOT guaranteed to hold the same model set). Also provides the
# _ollama_generate primitive (/api/generate) used by the llm-utils.sh dispatcher.
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
#   TAILSCALE_BIN      — path/name of the tailscale CLI. Defaults to `tailscale` on
#                        PATH, then the macOS app bundle
#                        (/Applications/Tailscale.app/Contents/MacOS/Tailscale).
#   OLLAMA_MDNS_SERVICE     — (macOS dns-sd fallback) service type to browse
#                        (default `_workstation._tcp`).
#   OLLAMA_MDNS_BROWSE_SECS — (macOS dns-sd fallback) browse window in seconds
#                        (default 2). dns-sd streams until killed.
#
# Must NOT read stdin (sourced via llm-utils.sh before INPUT=$(cat) in
# commit-msg-check.sh). Safe under set -euo pipefail — all fallible commands
# guarded with || true.

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
#
# Linux uses avahi-browse (-t terminates, fully parseable). macOS has no avahi;
# its dns-sd has no "all services" flag and streams until killed, so the fallback
# browses one service type for a bounded window and derives each host's .local
# name. Default service _workstation._tcp — what avahi-advertising Ollama boxes
# expose; macOS hosts advertise other types, so set OLLAMA_MDNS_SERVICE for them.
_discover_mdns_hosts() {
  local max="${OLLAMA_DISCOVERY_MAX:-6}"
  if command -v avahi-browse >/dev/null 2>&1; then
    avahi-browse -atrp 2>/dev/null \
      | awk -F';' '$1 == "=" && $7 != "" { print $7 }' \
      | sort -u \
      | head -n "$max"
    return 0
  fi
  command -v dns-sd >/dev/null 2>&1 || return 0
  { _discover_mdns_hosts_dnssd | sort -u | head -n "$max"; } 2>/dev/null || true
}

# Run a streaming dns-sd browse for a bounded window, then stop it. dns-sd never
# exits on its own, so background it, wait the window, kill. Always returns 0 —
# the kill/wait must not trip `set -e` in the sourcing hook.
_dnssd_browse() {
  local secs="$1" svc="$2" pid
  dns-sd -B "$svc" local. &
  pid=$!
  sleep "$secs"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 0
}

# macOS mDNS: turn `dns-sd -B` "Add" rows into <host>.local names. The instance
# name is fields 7..end (it may contain spaces); for _workstation the avahi
# convention is "<host> [<mac>]", so strip a trailing " [..]" and append .local.
_discover_mdns_hosts_dnssd() {
  local secs="${OLLAMA_MDNS_BROWSE_SECS:-2}"
  local svc="${OLLAMA_MDNS_SERVICE:-_workstation._tcp}"
  _dnssd_browse "$secs" "$svc" \
    | awk '/ Add / { s=""; for (i=7;i<=NF;i++) s=s (i>7?" ":"") $i; if (s!="") print s }' \
    | sed -E 's/[[:space:]]*\[[0-9A-Fa-f:]+\][[:space:]]*$//' \
    | sed -E 's/[[:space:]]+$//' \
    | awk 'NF { print $0 ".local" }'
}

# Resolve the tailscale CLI. Order: $TAILSCALE_BIN override → on PATH → the macOS
# GUI app bundle. The Mac App Store / standalone Tailscale.app ships its CLI at
# /Applications/Tailscale.app/Contents/MacOS/Tailscale and does NOT add it to
# PATH, so a bare `command -v tailscale` silently misses it on macOS. Empty
# output (return 1) means no usable CLI was found.
_tailscale_bin() {
  if [ -n "${TAILSCALE_BIN:-}" ]; then
    if command -v "$TAILSCALE_BIN" >/dev/null 2>&1 || [ -x "$TAILSCALE_BIN" ]; then
      printf '%s' "$TAILSCALE_BIN"; return 0
    fi
    return 1
  fi
  if command -v tailscale >/dev/null 2>&1; then
    printf 'tailscale'; return 0
  fi
  local mac_app="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  [ -x "$mac_app" ] && { printf '%s' "$mac_app"; return 0; }
  return 1
}

# Discover online Tailscale peers by their MagicDNS FQDN. Same essence-driven
# model as mDNS — a peer is only kept downstream if it answers /api/version, so
# probing the iPhone or a VPS is harmless. Peers without a DNSName (funnel infra
# nodes) are ignored. Requires the tailscale CLI + jq; silently skipped if
# either is missing. This removes any need to hardcode off-LAN hostnames.
_discover_tailscale_hosts() {
  local ts
  ts=$(_tailscale_bin) || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local max="${OLLAMA_DISCOVERY_MAX:-6}"
  "$ts" status --json 2>/dev/null \
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

# Generic discovery helpers (_pick_round_robin, _models_have, _rr_suffix) are
# backend-agnostic and live in llm-utils.sh, which defines them before sourcing
# this file. This file (the Ollama provider) is only ever sourced via llm-utils.sh.

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

# Ollama provider generate primitive: send a prompt to Ollama's /api/generate and
# print the response. The model arg is already the real (backend-resolved) id.
# The llm-utils.sh dispatcher calls this for the Ollama backend.
# Args: $1=model $2=system_prompt $3=timeout $4=num_predict
# stdin = prompt. stdout = model text (empty on any failure; exit 0).
_ollama_generate() {
  local model="$1" system="$2" timeout="$3" num_predict="${4:-16384}"
  # Treat empty OR 0 as "use default" (0 would request a zero-token generation).
  case "$num_predict" in ''|0) num_predict=16384 ;; esac
  local content
  content=$(cat)

  if [ -z "$content" ]; then
    return
  fi

  # Route to a server that actually hosts this model (the pool's servers do not
  # necessarily share the same model set). Empty => skip rather than 404.
  local host
  host=$(ollama_host_for_model "$model")
  if [ -z "$host" ]; then
    echo "Warning: no reachable Ollama server hosts model '$model'" >&2
    return
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  # Use double quotes so $tmpdir is expanded now, not at EXIT time.
  # Single-quoted trap would fail with set -euo pipefail because $tmpdir
  # is a local variable and becomes unbound when evaluated at script EXIT.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  printf '%s' "$system" > "$tmpdir/system"
  printf '%s' "$content" > "$tmpdir/prompt"

  jq -n \
    --arg model "$model" \
    --rawfile system "$tmpdir/system" \
    --rawfile prompt "$tmpdir/prompt" \
    --argjson num_predict "$num_predict" \
    '{model: $model, system: $system, prompt: $prompt, stream: false,
      options: {num_predict: $num_predict}}' \
    > "$tmpdir/request.json"

  local http_code
  http_code=$(curl -s --max-time "$timeout" -w '%{http_code}' \
    -o "$tmpdir/response.json" \
    "$host/api/generate" \
    -d @"$tmpdir/request.json" 2>/dev/null) || true

  if [ "$http_code" = "000" ] || [ ! -s "$tmpdir/response.json" ]; then
    echo "Warning: Ollama unavailable at $host" >&2
    return
  fi

  if [ "$http_code" != "200" ]; then
    echo "Warning: Ollama returned HTTP $http_code" >&2
    # Do not dump response body — it may contain echoed request with user code
    echo "  (response body suppressed — check Ollama server logs for details)" >&2
    return
  fi

  # Support thinking models: prefer .response, fall back to .thinking
  local response
  response=$(jq -r '
    if (.response // "") != "" then .response
    elif (.thinking // "") != "" then .thinking
    else empty
    end' "$tmpdir/response.json")

  if [ -n "$response" ]; then
    printf '%s\n' "$response"
  fi
}
