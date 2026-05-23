#!/bin/bash
# Resolve Ollama host: honor OLLAMA_HOST env var, otherwise default to localhost.
# Source this file to set and export OLLAMA_HOST.
# Must NOT read stdin (sourced before INPUT=$(cat) in commit-msg-check.sh).
# Safe under set -euo pipefail.

_resolve_ollama_host() {
  if [ -n "${OLLAMA_HOST:-}" ]; then
    echo "$OLLAMA_HOST"
    return
  fi
  echo "http://localhost:11434"
}

OLLAMA_HOST="$(_resolve_ollama_host)"
export OLLAMA_HOST
