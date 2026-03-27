#!/bin/bash
# Resolve Ollama host: honor env var, otherwise auto-detect reachable host.
# Source this file to set and export OLLAMA_HOST.
# Must NOT read stdin (sourced before INPUT=$(cat) in commit-msg-check.sh).
# Safe under set -euo pipefail — all fallible commands guarded with || true.

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

  for host in "http://gx10-a9c0:11434" "http://gx10-a9c0.local:11434" "http://localhost:11434"; do
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
  echo "http://gx10-a9c0:11434"
}

OLLAMA_HOST="$(_resolve_ollama_host)"
export OLLAMA_HOST
