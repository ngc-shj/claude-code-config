#!/bin/bash
# llama.cpp backend provider (llama.cpp-specific processing only).
#
# Sourced by llm-utils.sh AFTER it defines the shared helpers (_models_have,
# _pick_round_robin, _rr_suffix); this file uses them but does not define or
# source them. Defining functions only — no side effects on source. The common
# dispatcher (llm_request / llm_select_backend / llm_model_for) lives in
# llm-utils.sh; this file is a pure backend leaf.
#
# llama.cpp's llama-server speaks the OpenAI surface (/v1/chat/completions,
# /v1/models) and does NOT implement Ollama's /api/generate or /api/tags, so it
# needs its own discovery + request path.
#
# Discovery is single-host by default (localhost:8080). Multi-host mDNS/Tailscale
# discovery like the Ollama pool is intentionally out of scope (see plan SC1);
# LLAMACPP_HOST / LLAMACPP_HOSTS are the manual escape hatches.

_LLAMACPP_CACHE_FILE="${_LLAMACPP_HOST_CACHE:-/tmp/.llamacpp-host-cache-$(id -u)}"
# Field separator between a cached server's URL and its model list. Kept in a
# variable (not a literal tab) so editors/linters cannot silently mangle it.
_LLAMACPP_TAB=$'\t'

# Default logical->real model mapping (env-overridable). 8080 has no 120b-class
# model; the heavy slot maps to Qwen3.6-35B-A3B (top local coding-benchmark model)
# on its MTP speculative-decoding preset for speed.
#
# NOTE the quant tag is `Q4_K_XL`, not `UD-Q4_K_XL`: llama-server strips the
# unsloth-Dynamic `UD-` prefix, so a model loaded from `...:UD-Q4_K_XL` is
# exposed in /v1/models — and must be requested — as `...:Q4_K_XL`. Using the
# UD- form here would fail discovery (no /v1/models id matches it).
_LLAMACPP_MODEL_SMALL="${LLAMACPP_MODEL_SMALL:-unsloth/gpt-oss-20b-GGUF:F16}"
_LLAMACPP_MODEL_LARGE="${LLAMACPP_MODEL_LARGE:-unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL}"

# --- discovery ---

# Probe one base URL's /v1/models. Returns 0 if it answers like an OpenAI server.
_is_llamacpp_up() {
  curl -sf --connect-timeout 1 --max-time 2 "$1/v1/models" >/dev/null 2>&1
}

# Fetch a server's model ids as a space-separated list. Emits '*' (wildcard —
# eligible for any model) when the inventory cannot be determined (no jq,
# /v1/models unreachable, or empty) so a server is never WRONGLY excluded.
_llamacpp_fetch_models() {
  command -v jq >/dev/null 2>&1 || { printf '*'; return; }
  local body
  body=$(curl -sf --connect-timeout 1 --max-time 3 "$1/v1/models" 2>/dev/null) || true
  [ -z "$body" ] && { printf '*'; return; }
  local models
  models=$(printf '%s' "$body" | jq -r '.data[]?.id' 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  [ -z "$models" ] && { printf '*'; return; }
  printf '%s' "$models"
}

# Candidate hosts, in order: LLAMACPP_HOST (pin) | LLAMACPP_HOSTS | localhost:8080.
_llamacpp_candidates() {
  if [ -n "${LLAMACPP_HOST:-}" ]; then
    printf '%s\n' "$LLAMACPP_HOST"
  elif [ -n "${LLAMACPP_HOSTS:-}" ]; then
    local h
    for h in $LLAMACPP_HOSTS; do
      [ -n "$h" ] && printf '%s\n' "$h"
    done
  else
    printf '%s\n' "http://localhost:8080"
  fi
}

# Normalize a candidate (full URL | host:port | bare host) to a reachable base
# URL (empty if down). Bare names default to port 8080.
_llamacpp_probe_entry() {
  local entry="$1"
  case "$entry" in
    http://*|https://*) _is_llamacpp_up "$entry" && echo "$entry" ;;
    *:*)                _is_llamacpp_up "http://$entry" && echo "http://$entry" ;;
    *)                  _is_llamacpp_up "http://${entry}:8080" && echo "http://${entry}:8080" ;;
  esac
}

# Emit one TAB-separated record per reachable host: "<base_url>\t<models or '*'>".
_llamacpp_probe() {
  local records=() seen=" " url e
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    url=$(_llamacpp_probe_entry "$e")
    [ -z "$url" ] && continue
    case "$seen" in *" $url "*) continue;; esac
    seen="$seen$url "
    records+=("${url}${_LLAMACPP_TAB}$(_llamacpp_fetch_models "$url")")
  done < <(_llamacpp_candidates)

  [ "${#records[@]}" -gt 0 ] && printf '%s\n' "${records[@]}"
}

# Cached discovery records (regular file, symlink-guarded, 5-min TTL). A "down"
# result is not cached, so recovery is picked up on the next call.
_llamacpp_records() {
  # Explicit host override pins discovery to that host — probe it directly and
  # never consult or populate the shared cache, which may hold auto-discovered
  # defaults (e.g. localhost:8080) from a prior run. Mirrors the OLLAMA_HOST pin
  # in ollama-backend.sh.
  if [ -n "${LLAMACPP_HOST:-}" ] || [ -n "${LLAMACPP_HOSTS:-}" ]; then
    _llamacpp_probe
    return
  fi
  local cache="$_LLAMACPP_CACHE_FILE" blob=""
  if [ -f "$cache" ] && ! [ -L "$cache" ]; then
    local mtime
    mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
    if [ "$(( $(date +%s) - mtime ))" -lt 300 ]; then
      blob=$(cat "$cache")
    fi
  fi
  if [ -z "$blob" ]; then
    blob=$(_llamacpp_probe)
    if [ -n "$blob" ] && ! [ -L "$cache" ]; then
      local tmp
      tmp=$(mktemp "${cache}.XXXXXX" 2>/dev/null) || true
      if [ -n "${tmp:-}" ]; then
        printf '%s\n' "$blob" > "$tmp"
        mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
      fi
    fi
  fi
  # Emit with a trailing newline so a single-record (no-newline) result is not
  # skipped by `while read` in llamacpp_host_for_model. Stay empty when down.
  [ -n "$blob" ] && printf '%s\n' "$blob"
}

# Public: echo a reachable base URL hosting <real_model>, round-robin among all
# servers that have it. Empty output means none — caller skips gracefully.
llamacpp_host_for_model() {
  local want="$1"
  local candidates=() line url models
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "${line%%"$_LLAMACPP_TAB"*}" = "$line" ]; then
      url="$line"; models='*'
    else
      url="${line%%"$_LLAMACPP_TAB"*}"; models="${line#*"$_LLAMACPP_TAB"}"
    fi
    _models_have "$models" "$want" && candidates+=("$url")
  done < <(_llamacpp_records)

  [ "${#candidates[@]}" -eq 0 ] && return
  _pick_round_robin "${_LLAMACPP_CACHE_FILE}.rr.$(_rr_suffix "$want")" "${candidates[@]}"
}

# --- request ---

# Send a prompt to llama.cpp's /v1/chat/completions.
# Args: $1=real_model $2=system $3=timeout $4=num_predict(max_tokens, default 16384)
# stdin = user prompt. stdout = model text (empty on any failure; exit 0).
_llamacpp_request() {
  local model="$1" system="$2" timeout="$3" num_predict="${4:-16384}"
  # Treat empty OR 0 as "use default" — max_tokens:0 means "generate nothing" on
  # the OpenAI surface, which no caller intends.
  case "$num_predict" in ''|0) num_predict=16384 ;; esac
  local content
  content=$(cat)
  [ -z "$content" ] && return

  local host
  host=$(llamacpp_host_for_model "$model")
  if [ -z "$host" ]; then
    echo "Warning: no reachable llama.cpp server hosts model '$model'" >&2
    return
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  # Double-quoted so $tmpdir expands now; a single-quoted trap would reference
  # the local var at EXIT time, when it is unbound under set -euo pipefail.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  printf '%s' "$system" > "$tmpdir/system"
  printf '%s' "$content" > "$tmpdir/prompt"

  # Include the system message only when non-empty.
  if [ -n "$system" ]; then
    jq -n \
      --arg model "$model" \
      --rawfile system "$tmpdir/system" \
      --rawfile prompt "$tmpdir/prompt" \
      --argjson max_tokens "$num_predict" \
      '{model: $model,
        messages: [{role: "system", content: $system}, {role: "user", content: $prompt}],
        stream: false, max_tokens: $max_tokens}' \
      > "$tmpdir/request.json"
  else
    jq -n \
      --arg model "$model" \
      --rawfile prompt "$tmpdir/prompt" \
      --argjson max_tokens "$num_predict" \
      '{model: $model,
        messages: [{role: "user", content: $prompt}],
        stream: false, max_tokens: $max_tokens}' \
      > "$tmpdir/request.json"
  fi

  local http_code
  http_code=$(curl -s --max-time "$timeout" -w '%{http_code}' \
    -o "$tmpdir/response.json" \
    -H 'Content-Type: application/json' \
    "$host/v1/chat/completions" \
    -d @"$tmpdir/request.json" 2>/dev/null) || true

  if [ "$http_code" = "000" ] || [ ! -s "$tmpdir/response.json" ]; then
    echo "Warning: llama.cpp unavailable at $host" >&2
    return
  fi

  if [ "$http_code" != "200" ]; then
    echo "Warning: llama.cpp returned HTTP $http_code" >&2
    # Do not dump response body — it may contain echoed request with user code.
    echo "  (response body suppressed — check llama.cpp server logs for details)" >&2
    return
  fi

  # Prefer the content; reasoning models (gpt-oss) may only fill reasoning_content.
  local response
  response=$(jq -r '
    .choices[0].message as $m
    | ($m.content // "") as $c
    | ($m.reasoning_content // $m.reasoning // "") as $r
    | if $c != "" then $c elif $r != "" then $r else empty end
    ' "$tmpdir/response.json" 2>/dev/null)

  if [ -n "$response" ]; then
    printf '%s\n' "$response"
  fi
}

# llamacpp_records availability for the backend selector. Exposed so llm-utils.sh
# can decide whether to auto-prefer llama.cpp without duplicating discovery.
llamacpp_available() {
  [ -n "$(_llamacpp_records)" ]
}

# Map a logical model name to its llama.cpp real id (env-overridable defaults
# above). Unknown logical names pass through unchanged. The Ollama mapping
# (identity) and backend selection live in llm-utils.sh.
llamacpp_model_for() {
  case "$1" in
    gpt-oss:20b)  printf '%s' "$_LLAMACPP_MODEL_SMALL" ;;
    gpt-oss:120b) printf '%s' "$_LLAMACPP_MODEL_LARGE" ;;
    *)            printf '%s' "$1" ;;
  esac
}
