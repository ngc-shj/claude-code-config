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
#   - openai-backend.sh — OpenAI-compatible provider (llama.cpp, vLLM, …;
#                           discovery, openai_host_for_model,
#                           _openai_request via /v1/chat/completions)
#
# Backend selection: LLM_BACKEND (openai|ollama) pins the choice; otherwise
# the OpenAI-compatible backend is auto-preferred when reachable, falling back
# to Ollama. Sourcing is
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

# Word-split the given host-list argument strings on IFS WITHOUT filename
# globbing, emitting one non-empty host per line. A host entry containing `*`,
# `?`, or `[...]` (typo, or a misguided "trust everything" wildcard) must be
# treated literally — never expanded against the hook's current directory,
# which would balloon the candidate/fingerprint into CWD-dependent garbage.
_llm_split_hosts() {
  local had_f=0 h
  case $- in *f*) had_f=1 ;; esac
  set -f
  # shellcheck disable=SC2048,SC2086 -- intentional word-split, globbing disabled
  set -- $*
  [ "$had_f" -eq 1 ] || set +f
  for h in "$@"; do
    [ -n "$h" ] && printf '%s\n' "$h"
  done
}

# Same split, joined into a single space-normalized line (for fingerprints).
_llm_join_hosts() {
  _llm_split_hosts "$@" | tr '\n' ' ' | sed 's/ *$//'
}

# Emit the records of cache file $1 iff it is a trusted file, fresh (< 5 min),
# AND its first line equals fingerprint $2 — the trust configuration that
# produced it. Empty output otherwise, so callers re-probe. Binding the cache
# to its fingerprint makes revoking/changing a trust setting take effect on
# the NEXT call, not after the TTL — a host admitted under a since-revoked
# setting must never be served from cache.
_llm_cached_records() {
  local cache="$1" fingerprint="$2"
  [ -n "${cache:-}" ] || return 0
  _llm_trusted_file "$cache" || return 0
  local mtime
  mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
  [ "$(( $(date +%s) - mtime ))" -lt 300 ] || return 0
  local header
  IFS= read -r header < "$cache"
  [ "$header" = "$fingerprint" ] || return 0
  tail -n +2 "$cache"
}

# Atomically write records blob $3 to cache file $1, stamped with fingerprint
# $2 as the first line. No-op when the blob is empty or the path is a symlink.
_llm_write_cache() {
  local cache="$1" fingerprint="$2" blob="$3"
  [ -n "$blob" ] || return 0
  if [ -L "$cache" ]; then
    return 0
  fi
  local tmp
  tmp=$(mktemp "${cache}.XXXXXX" 2>/dev/null) || return 0
  printf '%s\n%s\n' "$fingerprint" "$blob" > "$tmp"
  mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  return 0
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
# shellcheck source=openai-backend.sh
source "$(dirname "${BASH_SOURCE[0]}")/openai-backend.sh"

# --- backend selection + model mapping + dispatch (common) ---

# echo the active backend: "openai" or "ollama". An invalid LLM_BACKEND value
# is ignored (falls through to auto) rather than failing the hook.
llm_select_backend() {
  case "${LLM_BACKEND:-}" in
    openai|ollama) printf '%s' "$LLM_BACKEND"; return ;;
  esac
  if openai_available; then
    printf 'openai'
  else
    printf 'ollama'
  fi
}

# echo the real model id for a logical name under a backend. The Ollama backend
# uses identity; the OpenAI-backend mapping (incl. env overrides) is owned by
# the openai provider.
llm_model_for() {
  local logical="$1" backend="$2"
  if [ "$backend" = "openai" ]; then
    openai_model_for "$logical"
  else
    printf '%s' "$logical"
  fi
}

# echo the candidate host list (one per line, as URLs or host:port exactly as
# the backends hold them) that llm_request would use for the ACTIVE backend —
# reusing the SAME discovery code path (openai: _openai_candidates, the
# candidate-entry source _openai_request resolves through; ollama:
# OLLAMA_HOSTS, the list _ollama_generate resolves from). No behavior change
# for existing callers — read-only introspection. Used by C4's loopback gate
# to decide whether a distillation request would leave the loopback interface.
llm_resolved_hosts() {
  local backend
  backend=$(llm_select_backend)
  if [ "$backend" = "openai" ]; then
    _openai_candidates
  else
    _llm_split_hosts "${OLLAMA_HOSTS:-}"
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
  if [ "$backend" = "openai" ]; then
    _openai_request "$real" "$system" "$timeout" "$num_predict"
  else
    _ollama_generate "$real" "$system" "$timeout" "$num_predict"
  fi
}
