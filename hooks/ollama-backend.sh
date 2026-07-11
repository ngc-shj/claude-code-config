#!/bin/bash
# Ollama backend provider (Ollama-specific processing). Sourced by llm-utils.sh
# AFTER it defines the shared helpers (_models_have, _pick_round_robin,
# _rr_suffix); this file uses them and must not be sourced standalone.
#
# Resolve Ollama server(s): honor env var, otherwise probe the explicitly
# configured hosts (OLLAMA_EXTRA_HOSTS) and load-balance across them — model-aware,
# so a request is only ever routed to a server that actually hosts the requested
# model (the servers are NOT guaranteed to hold the same model set). Also provides
# the _ollama_generate primitive (/api/generate) used by the llm-utils.sh dispatcher.
#
# TRUST MODEL: prompts sent to a server include diffs and full source files, so
# every pool member is a data-exfiltration sink if untrusted. mDNS/Tailscale
# auto-discovery adds hosts on the sole evidence that they answer /api/version —
# any LAN device can fake that — so it is OFF by default and gated behind
# OLLAMA_DISCOVERY (explicit, informed opt-in). Explicitly configured hosts
# (OLLAMA_HOST / LLM_TRUSTED_HOSTS / OLLAMA_EXTRA_HOSTS) are trusted because
# the user named them.
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
#   LLM_TRUSTED_HOSTS  — primary multi-server configuration, shared with the
#                        llama.cpp backend: space-separated trusted hosts to
#                        probe. Each entry is a bare hostname (Ollama probes
#                        port 11434), host:port, or URL. Backend membership is
#                        decided by behavior — a listed host joins whichever
#                        backend's pool answers that backend's probe.
#   OLLAMA_EXTRA_HOSTS — Ollama-only additions to LLM_TRUSTED_HOSTS, for hosts
#                        that should not be probed by other backends.
#   OLLAMA_DISCOVERY   — opt-in for UNAUTHENTICATED auto-discovery sources.
#                        Unset/empty/"0"/"off"/"none" (default): no auto-discovery.
#                        "1"/"on"/"all": enable both sources. Or a space/comma
#                        list of sources: "mdns", "tailscale". Enabling mDNS
#                        means any device on the local network that mimics the
#                        Ollama API can receive your diffs and source files —
#                        enable it only on networks where every host is trusted.
#                        Tailscale peers are at least tailnet-authenticated, but
#                        still opt-in (shared/compromised nodes receive code).
#   OLLAMA_DISCOVERY_MAX — cap on candidates probed per discovery source (default 6).
#   TAILSCALE_BIN      — path/name of the tailscale CLI. Defaults to `tailscale` on
#                        PATH, then the macOS app bundle
#                        (/Applications/Tailscale.app/Contents/MacOS/Tailscale).
#
# Must NOT read stdin (sourced via llm-utils.sh before INPUT=$(cat) in
# commit-msg-check.sh). Safe under set -euo pipefail — all fallible commands
# guarded with || true.

# Host cache lives in the per-user private state dir (_llm_state_dir,
# llm-utils.sh) — never in world-writable /tmp, where a predictable name lets
# another local user pre-seed the pool with their own server.
_OLLAMA_CACHE_FILE="${_OLLAMA_HOST_CACHE:-$(_llm_state_dir)/ollama-host-cache}"
# Field separator between a cached server's URL and its model list. Kept in a
# variable (not a literal tab) so editors/linters cannot silently mangle it.
_OLLAMA_TAB=$'\t'

# Is auto-discovery source $1 ("mdns" | "tailscale") enabled? Default: no.
# Auto-discovered hosts are unauthenticated (see TRUST MODEL above), so each
# source requires explicit opt-in via OLLAMA_DISCOVERY.
_ollama_discovery_enabled() {
  local src="$1" cfg="${OLLAMA_DISCOVERY:-}"
  case "$cfg" in
    ''|0|off|none) return 1 ;;
    1|on|all)      return 0 ;;
  esac
  case " ${cfg//,/ } " in
    *" $src "*) return 0 ;;
    *)          return 1 ;;
  esac
}

# Discover mDNS hostnames advertised on the LAN. Name-independent by design:
# an Ollama server is identified by a live /api/version response (see
# _probe_servers), NOT by a hostname prefix — so any host that actually serves
# Ollama is picked up, whatever it is named. Capped so a LAN advertising many
# hosts cannot stall the hook (each candidate costs up to --max-time 2 s of
# curl probe time on a cache miss). Override the cap with OLLAMA_DISCOVERY_MAX.
#
# Linux only: uses avahi-browse. macOS has no avahi, and its dns-sd
# service-browse does not reliably surface plain Ollama hosts (they often publish
# only an mDNS A record, not a browsable service type). On macOS, set
# OLLAMA_EXTRA_HOSTS to the host name(s) instead — the OS resolver answers
# `.local` for the probe even when service-browse does not see the host.
_discover_mdns_hosts() {
  command -v avahi-browse >/dev/null 2>&1 || return 0
  local max="${OLLAMA_DISCOVERY_MAX:-6}"
  avahi-browse -atrp 2>/dev/null \
    | awk -F';' '$1 == "=" && $7 != "" { print $7 }' \
    | sort -u \
    | head -n "$max"
}

# Resolve the tailscale CLI to an executable we can invoke from this function.
# Order: $TAILSCALE_BIN override → an on-disk binary on PATH → the macOS GUI app
# bundle. Two macOS gotchas drive this:
#  1. Tailscale.app ships its CLI at /Applications/Tailscale.app/Contents/MacOS/
#     Tailscale and does NOT add it to PATH; users commonly `alias tailscale` to
#     it instead.
#  2. `command -v tailscale` returns success for that alias, but a quoted call
#     (`"$ts" status`) does NOT expand aliases and there is no real binary, so it
#     fails silently. We therefore use `type -P` (on-disk binary path only,
#     ignoring aliases/functions) and fall back to the app bundle's absolute path.
# Empty output (return 1) means no usable CLI was found.
_tailscale_bin() {
  if [ -n "${TAILSCALE_BIN:-}" ]; then
    if [ -x "$TAILSCALE_BIN" ] || command -v "$TAILSCALE_BIN" >/dev/null 2>&1; then
      printf '%s' "$TAILSCALE_BIN"; return 0
    fi
    return 1
  fi
  local p
  p=$(type -P tailscale 2>/dev/null)
  [ -n "$p" ] && { printf '%s' "$p"; return 0; }
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
#   1. LLM_TRUSTED_HOSTS then OLLAMA_EXTRA_HOSTS — explicitly trusted hosts
#      (primary configuration). Space-separated bare hostname, host:port, or URL.
#   2. Online Tailscale peers (MagicDNS FQDNs) — only with OLLAMA_DISCOVERY opt-in.
#   3. mDNS-advertised hosts on the local LAN — only with OLLAMA_DISCOVERY opt-in.
# Duplicates (same base URL) are dropped. localhost is emitted only when NO
# remote server is reachable — the load-balance pool should target dedicated
# inference hosts, not the machine already running Claude.
_probe_servers() {
  local entries=()
  local e
  while IFS= read -r e; do
    entries+=("$e")
  done < <(_llm_split_hosts "${LLM_TRUSTED_HOSTS:-}" "${OLLAMA_EXTRA_HOSTS:-}")
  if _ollama_discovery_enabled tailscale; then
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      entries+=("$e")
    done < <(_discover_tailscale_hosts)
  fi
  if _ollama_discovery_enabled mdns; then
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      entries+=("$e")
    done < <(_discover_mdns_hosts)
  fi

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
# One-line fingerprint of the trust-relevant configuration, stored as the
# cache's first line (consumed via _llm_cached_records / _llm_write_cache in
# llm-utils.sh). A cached pool is only valid for the exact allow-set that
# produced it: revoking an opt-in (OLLAMA_DISCOVERY) or editing the trusted
# host lists must take effect on the NEXT call, not after the 5-min TTL —
# otherwise a host admitted under a since-revoked opt-in keeps receiving
# prompts. Normalized to effective sources (so alias spellings 1/on/all don't
# needlessly invalidate) and to the effective candidate list (LLM_TRUSTED_HOSTS
# and OLLAMA_EXTRA_HOSTS joined in probe order, whitespace collapsed).
_ollama_trust_fingerprint() {
  local mdns=0 ts=0
  _ollama_discovery_enabled mdns && mdns=1
  _ollama_discovery_enabled tailscale && ts=1
  printf '#cfg mdns=%s ts=%s hosts=%s' "$mdns" "$ts" \
    "$(_llm_join_hosts "${LLM_TRUSTED_HOSTS:-}" "${OLLAMA_EXTRA_HOSTS:-}")"
}

# Emit the cached records iff the cache is trusted, fresh, and was written
# under the current trust configuration. Empty output otherwise.
_ollama_read_cache() {
  _llm_cached_records "$_OLLAMA_CACHE_FILE" "$(_ollama_trust_fingerprint)"
}

ollama_host_for_model() {
  local want="$1"

  # Pinned override or nothing discovered: defer to the single OLLAMA_HOST.
  if [ -n "${_OLLAMA_PINNED:-}" ]; then
    echo "${OLLAMA_HOST:-}"
    return
  fi
  local cache="$_OLLAMA_CACHE_FILE"
  local records
  records=$(_ollama_read_cache)
  if [ -z "$records" ]; then
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
  done <<< "$records"

  [ "${#candidates[@]}" -eq 0 ] && return
  _pick_round_robin "${cache}.rr.$(_rr_suffix "$want")" "${candidates[@]}"
}

_resolve_ollama_servers() {
  local cache_file="$_OLLAMA_CACHE_FILE"

  # Reuse the cache only when trusted, fresh, AND written under the current
  # trust configuration (see _ollama_read_cache).
  local records_blob
  records_blob=$(_ollama_read_cache)

  if [ -z "$records_blob" ]; then
    records_blob=$(_probe_servers)
    _llm_write_cache "$cache_file" "$(_ollama_trust_fingerprint)" "$records_blob"
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
