#!/bin/bash
# Backend-agnostic local-LLM layer (COMMON processing).
#
# This is the single entry point hooks source to reach a local LLM. It holds the
# processing that is NOT backend-specific:
#   - shared discovery helpers (_pick_round_robin, _models_have, _rr_suffix)
#   - backend selection      (llm_select_backend)
#   - logical->real mapping   (llm_model_for)
#   - the dispatcher          (llm_request)
#
# Backend-specific processing lives in the provider leaves, which this file
# sources AFTER defining the shared helpers (so the providers may use them
# without sourcing anything themselves):
#   - ollama-backend.sh   — Ollama provider (discovery, ollama_host_for_model,
#                           _ollama_generate via /api/generate)
#   - llamacpp-backend.sh — llama.cpp provider (discovery, llamacpp_host_for_model,
#                           _llamacpp_request via /v1/chat/completions)
#
# Backend selection: LLM_BACKEND (llamacpp|ollama) pins the choice; otherwise
# llama.cpp is auto-preferred when reachable, falling back to Ollama. Sourcing is
# side-effect-free for the dispatcher (the Ollama provider still runs its own
# discovery at source time, as it always has).

# No source guard: re-sourcing is intentional. The Ollama provider advances a
# round-robin counter on each source (load balancing across processes), and a
# guard would defeat that. Re-probe is already avoided by the providers' caches.

# --- shared discovery helpers (backend-agnostic) ---

# Per-user private state directory for host caches and round-robin counters.
# World-writable /tmp is off-limits: a predictable /tmp path lets any local user
# pre-create the cache and route prompts (diffs, source files) to their own
# server. Preference order: XDG_RUNTIME_DIR (0700, tmpfs) → XDG_CACHE_HOME →
# ~/.cache. Each candidate is accepted only if the resulting directory is a
# non-symlink directory owned by the current user; otherwise fall back to a
# per-process mktemp dir (safe, but no cross-process cache reuse).
_llm_state_dir() {
  local base dir
  for base in "${XDG_RUNTIME_DIR:-}" "${XDG_CACHE_HOME:-}" "${HOME:+${HOME}/.cache}"; do
    [ -n "$base" ] && [ -d "$base" ] || continue
    dir="$base/claude-llm-hooks"
    mkdir -p -m 0700 "$dir" 2>/dev/null || true
    if [ -d "$dir" ] && ! [ -L "$dir" ] && [ -O "$dir" ]; then
      chmod 0700 "$dir" 2>/dev/null || true
      printf '%s' "$dir"
      return 0
    fi
  done
  mktemp -d "${TMPDIR:-/tmp}/claude-llm-hooks-XXXXXX" 2>/dev/null
}

# Is $1 a state file we may trust? Regular file, not a symlink, owned by the
# current user. Guards every cache/counter read against files pre-created by
# another local user (mode alone is not enough — ownership is the invariant).
_llm_trusted_file() {
  [ -f "$1" ] && ! [ -L "$1" ] && [ -O "$1" ]
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
  if _llm_trusted_file "$rr_file"; then
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

# --- provider leaves (sourced after the helpers above are defined) ---
# shellcheck source=ollama-backend.sh
source "$(dirname "${BASH_SOURCE[0]}")/ollama-backend.sh"
# shellcheck source=llamacpp-backend.sh
source "$(dirname "${BASH_SOURCE[0]}")/llamacpp-backend.sh"

# --- backend selection + model mapping + dispatch (common) ---

# echo the active backend: "llamacpp" or "ollama". An invalid LLM_BACKEND value
# is ignored (falls through to auto) rather than failing the hook.
llm_select_backend() {
  case "${LLM_BACKEND:-}" in
    llamacpp|ollama) printf '%s' "$LLM_BACKEND"; return ;;
  esac
  if llamacpp_available; then
    printf 'llamacpp'
  else
    printf 'ollama'
  fi
}

# echo the real model id for a logical name under a backend. The Ollama backend
# uses identity; the llama.cpp mapping (incl. env overrides) is owned by the
# llama.cpp provider.
llm_model_for() {
  local logical="$1" backend="$2"
  if [ "$backend" = "llamacpp" ]; then
    llamacpp_model_for "$logical"
  else
    printf '%s' "$logical"
  fi
}

# Route a generate request to the active backend.
# Args: $1=logical_model $2=system $3=timeout $4=num_predict
# stdin = prompt. stdout = model text (empty on failure; exit 0).
llm_request() {
  local logical="$1" system="$2" timeout="$3" num_predict="${4:-}"
  local backend real
  backend=$(llm_select_backend)
  real=$(llm_model_for "$logical" "$backend")
  if [ "$backend" = "llamacpp" ]; then
    _llamacpp_request "$real" "$system" "$timeout" "$num_predict"
  else
    _ollama_generate "$real" "$system" "$timeout" "$num_predict"
  fi
}
