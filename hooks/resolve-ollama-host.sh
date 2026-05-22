#!/bin/bash
# Resolve Ollama host: honor env var, otherwise auto-detect reachable host.
# Source this file to set and export OLLAMA_HOST.
# Must NOT read stdin (sourced before INPUT=$(cat) in commit-msg-check.sh).
# Safe under set -euo pipefail — all fallible commands guarded with || true.

# Discover mDNS hosts whose names start with gx10-. Emits up to 3 hostnames,
# deduplicated. Silent if avahi-browse is missing or nothing matches.
# Cap exists so a LAN advertising many gx10-* records cannot stall the hook
# (each candidate costs up to --max-time 2 s of curl probe time).
_discover_gx10_hosts() {
  command -v avahi-browse >/dev/null 2>&1 || return 0
  # -a: all service types, -t: terminate after cache dump, -r: resolve,
  # -p: parseable. Resolved lines start with '=' and put the hostname in
  # field 7.
  avahi-browse -atrp 2>/dev/null \
    | awk -F';' '$1 == "=" && $7 ~ /^gx10-/ { print $7 }' \
    | sort -u \
    | head -n 3
}

_resolve_ollama_host() {
  if [ -n "${OLLAMA_HOST:-}" ]; then
    echo "$OLLAMA_HOST"
    return
  fi

  local cache_file="${_OLLAMA_HOST_CACHE:-/tmp/.ollama-host-cache-$(id -u)}"

  # Use cache if it exists, is a regular file (not symlink), and fresh (< 5 min)
  if [ -f "$cache_file" ] && ! [ -L "$cache_file" ]; then
    local mtime
    mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
    if [ "$(( $(date +%s) - mtime ))" -lt 300 ]; then
      cat "$cache_file"
      return
    fi
  fi

  # Probe discovered gx10-* hosts first (bare form for /etc/hosts/DNS, then
  # .local for pure mDNS), then localhost as the final candidate. This
  # preserves the historical preference for the user's primary inference host
  # (gx10) over localhost; an explicit OLLAMA_HOST env var overrides this.
  local candidates=()
  local h
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    if [ "$h" = "${h%.local}" ]; then
      # avahi normally returns .local FQDNs; this branch covers edge cases
      # (mDNS misconfig, future avahi behaviour) without emitting a duplicate.
      candidates+=("http://${h}:11434")
    else
      candidates+=("http://${h%.local}:11434" "http://${h}:11434")
    fi
  done < <(_discover_gx10_hosts)
  candidates+=("http://localhost:11434")

  for host in "${candidates[@]}"; do
    if curl -sf --connect-timeout 1 --max-time 2 "$host/api/version" >/dev/null 2>&1; then
      # Atomic write: skip if path is a symlink
      if ! [ -L "$cache_file" ]; then
        local tmp
        tmp=$(mktemp "${cache_file}.XXXXXX" 2>/dev/null) || true
        if [ -n "${tmp:-}" ]; then
          echo "$host" > "$tmp"
          mv "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
        fi
      fi
      echo "$host"
      return
    fi
  done

  # Fallback if nothing reachable
  echo "http://localhost:11434"
}

OLLAMA_HOST="$(_resolve_ollama_host)"
export OLLAMA_HOST
