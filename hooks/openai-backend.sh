#!/bin/bash
# OpenAI-compatible backend provider (llama.cpp, vLLM, and any server exposing
# the OpenAI surface /v1/models + /v1/chat/completions).
#
# Sourced by llm-utils.sh AFTER it defines the shared helpers (_models_have,
# _pick_round_robin, _rr_suffix); this file uses them but does not define or
# source them. Defining functions only — no side effects on source. The common
# dispatcher (llm_request / llm_select_backend / llm_model_for) lives in
# llm-utils.sh; this file is a pure backend leaf.
#
# These servers speak the OpenAI surface (/v1/chat/completions, /v1/models) and
# do NOT implement Ollama's /api/generate or /api/tags, so this provider needs
# its own discovery + request path.
#
# Candidates: OPENAI_HOST pins one server; OPENAI_HOSTS is an exclusive
# OpenAI-backend-only list; otherwise the shared LLM_TRUSTED_HOSTS plus
# localhost. Bare names are probed on each port in LLM_OPENAI_PORTS (default
# "8080 8000" — llama.cpp's 8080 and vLLM's 8000), so one host running both
# servers joins the pool once per reachable port. Membership is decided by
# behavior: a candidate joins this pool only if it answers /v1/models.
# Unauthenticated mDNS/Tailscale auto-discovery like the Ollama opt-in is
# intentionally out of scope (see plan SC1).

# Host cache lives in the per-user private state dir (_llm_state_dir,
# llm-utils.sh) — never in world-writable /tmp, where a predictable name lets
# another local user pre-seed the pool with their own server.
_OPENAI_CACHE_FILE="${_OPENAI_HOST_CACHE:-$(_llm_state_dir)/openai-host-cache}"
# Field separator between a cached server's URL and its model list. Kept in a
# variable (not a literal tab) so editors/linters cannot silently mangle it.
_OPENAI_TAB=$'\t'

# Default logical->real model mapping (env-overridable). 8080 has no 120b-class
# model; the heavy slot maps to Qwen3.6-35B-A3B (top local coding-benchmark model)
# on its MTP speculative-decoding preset for speed.
#
# NOTE the quant tag is `Q4_K_XL`, not `UD-Q4_K_XL`: llama-server strips the
# unsloth-Dynamic `UD-` prefix, so a model loaded from `...:UD-Q4_K_XL` is
# exposed in /v1/models — and must be requested — as `...:Q4_K_XL`. Using the
# UD- form here would fail discovery (no /v1/models id matches it).
_OPENAI_MODEL_SMALL="${OPENAI_MODEL_SMALL:-unsloth/gpt-oss-20b-GGUF:F16}"
_OPENAI_MODEL_LARGE="${OPENAI_MODEL_LARGE:-unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL}"
# DeepSeek-V4 served by vLLM on :8000 (logical names ds4:flash / ds4:pro).
_OPENAI_MODEL_DS4_FLASH="${OPENAI_MODEL_DS4_FLASH:-deepseek-v4-flash}"
_OPENAI_MODEL_DS4_PRO="${OPENAI_MODEL_DS4_PRO:-deepseek-v4-pro}"

# Ports probed for a bare/`.local` host name (space-separated). Default covers
# llama.cpp (8080) and vLLM (8000); override to add/remove OpenAI-surface ports.
_OPENAI_PORTS="${LLM_OPENAI_PORTS:-8080 8000}"

# --- discovery ---

# Probe one base URL's /v1/models. Returns 0 if it answers like an OpenAI server.
_is_openai_up() {
  curl -sf --connect-timeout 1 --max-time 2 "$1/v1/models" >/dev/null 2>&1
}

# Fetch a server's model ids as a space-separated list. Emits '*' (wildcard —
# eligible for any model) when the inventory cannot be determined (no jq,
# /v1/models unreachable, or empty) so a server is never WRONGLY excluded.
_openai_fetch_models() {
  command -v jq >/dev/null 2>&1 || { printf '*'; return; }
  local body
  body=$(curl -sf --connect-timeout 1 --max-time 3 "$1/v1/models" 2>/dev/null) || true
  [ -z "$body" ] && { printf '*'; return; }
  local models
  models=$(printf '%s' "$body" | jq -r '.data[]?.id' 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  [ -z "$models" ] && { printf '*'; return; }
  printf '%s' "$models"
}

# Candidate hosts, in order: OPENAI_HOST (pin) | OPENAI_HOSTS (exclusive
# list) | LLM_TRUSTED_HOSTS + localhost. Bare candidates (incl. localhost) are
# multi-port-probed downstream; the probe's dedup drops a trusted entry that
# resolves to the same URL as localhost.
_openai_candidates() {
  if [ -n "${OPENAI_HOST:-}" ]; then
    printf '%s\n' "$OPENAI_HOST"
  elif [ -n "${OPENAI_HOSTS:-}" ]; then
    _llm_split_hosts "$OPENAI_HOSTS"
  else
    _llm_split_hosts "${LLM_TRUSTED_HOSTS:-}"
    printf '%s\n' "localhost"
  fi
}

# Fingerprint of the trust configuration that shapes the unpinned candidate
# set (normalized: whitespace collapsed). Includes the probe-port set, so
# changing LLM_TRUSTED_HOSTS OR LLM_OPENAI_PORTS invalidates the cache on the
# next call — same revocation semantics as the Ollama pool. Pinned configs
# (OPENAI_HOST / OPENAI_HOSTS) bypass the cache entirely and need no fingerprint.
_openai_trust_fingerprint() {
  printf '#cfg hosts=%s ports=%s' \
    "$(_llm_join_hosts "${LLM_TRUSTED_HOSTS:-}")" \
    "$(_llm_join_hosts "$_OPENAI_PORTS")"
}

# Normalize a candidate to reachable base URL(s), one per line (empty if none
# reachable). A full URL or host:port is probed as given; a bare/`.local` name
# is probed on every port in $_OPENAI_PORTS and every reachable port is emitted,
# so a host running both llama.cpp (:8080) and vLLM (:8000) contributes both.
_openai_probe_entry() {
  local entry="$1" p
  case "$entry" in
    http://*|https://*) _is_openai_up "$entry" && echo "$entry" ;;
    *:*)                _is_openai_up "http://$entry" && echo "http://$entry" ;;
    *)
      # Word-split the port list glob-safely (same guard _llm_split_hosts
      # applies to host lists — a stray metachar must not expand against CWD).
      local p
      while IFS= read -r p; do
        [ -n "$p" ] && _is_openai_up "http://${entry}:${p}" && echo "http://${entry}:${p}"
      done < <(_llm_split_hosts "$_OPENAI_PORTS") ;;
  esac
}

# Emit one TAB-separated record per reachable URL: "<base_url>\t<models or '*'>".
# A single candidate entry can yield several URLs (one per reachable probe
# port), so each is deduped and recorded independently.
_openai_probe() {
  local records=() seen=" " url e
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    while IFS= read -r url; do
      [ -z "$url" ] && continue
      case "$seen" in *" $url "*) continue;; esac
      seen="$seen$url "
      records+=("${url}${_OPENAI_TAB}$(_openai_fetch_models "$url")")
    done < <(_openai_probe_entry "$e")
  done < <(_openai_candidates)

  [ "${#records[@]}" -gt 0 ] && printf '%s\n' "${records[@]}"
}

# Cached discovery records (trusted file, fingerprint-bound, 5-min TTL). A
# "down" result is not cached, so recovery is picked up on the next call.
_openai_records() {
  # Explicit host override pins discovery to that host — probe it directly and
  # never consult or populate the shared cache, which may hold trusted-host
  # defaults (e.g. localhost:8080) from a prior run. Mirrors the OLLAMA_HOST pin
  # in ollama-backend.sh.
  if [ -n "${OPENAI_HOST:-}" ] || [ -n "${OPENAI_HOSTS:-}" ]; then
    _openai_probe
    return
  fi
  local cache="$_OPENAI_CACHE_FILE" blob=""
  blob=$(_llm_cached_records "$cache" "$(_openai_trust_fingerprint)")
  if [ -z "$blob" ]; then
    blob=$(_openai_probe)
    _llm_write_cache "$cache" "$(_openai_trust_fingerprint)" "$blob"
  fi
  # Emit with a trailing newline so a single-record (no-newline) result is not
  # skipped by `while read` in openai_host_for_model. Stay empty when down.
  [ -n "$blob" ] && printf '%s\n' "$blob"
}

# Public: echo a reachable base URL hosting <real_model>, round-robin among all
# servers that have it. Empty output means none — caller skips gracefully.
openai_host_for_model() {
  local want="$1"
  local candidates=() line url models
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "${line%%"$_OPENAI_TAB"*}" = "$line" ]; then
      url="$line"; models='*'
    else
      url="${line%%"$_OPENAI_TAB"*}"; models="${line#*"$_OPENAI_TAB"}"
    fi
    _models_have "$models" "$want" && candidates+=("$url")
  done < <(_openai_records)

  [ "${#candidates[@]}" -eq 0 ] && return
  _pick_round_robin "${_OPENAI_CACHE_FILE}.rr.$(_rr_suffix "$want")" "${candidates[@]}"
}

# --- request ---

# Send a prompt to the OpenAI-compatible /v1/chat/completions endpoint.
# Args: $1=real_model $2=system $3=timeout $4=num_predict(max_tokens, default 16384)
# stdin = user prompt. stdout = model text (empty on any failure; exit 0).
_openai_request() {
  local model="$1" system="$2" timeout="$3" num_predict="${4:-16384}"
  # Treat empty OR 0 as "use default" — max_tokens:0 means "generate nothing" on
  # the OpenAI surface, which no caller intends.
  case "$num_predict" in ''|0) num_predict=16384 ;; esac
  local content
  content=$(cat)
  [ -z "$content" ] && return

  local host
  host=$(openai_host_for_model "$model")
  if [ -z "$host" ]; then
    echo "Warning: no reachable OpenAI-compatible server hosts model '$model'" >&2
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
    echo "Warning: OpenAI-compatible server unavailable at $host" >&2
    return
  fi

  if [ "$http_code" != "200" ]; then
    echo "Warning: OpenAI-compatible server returned HTTP $http_code" >&2
    # Do not dump response body — it may contain echoed request with user code.
    echo "  (response body suppressed — check the server logs for details)" >&2
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

# openai_records availability for the backend selector. Exposed so llm-utils.sh
# can decide whether to auto-prefer the OpenAI backend without duplicating discovery.
openai_available() {
  [ -n "$(_openai_records)" ]
}

# Map a logical model name to its real /v1/models id on the OpenAI backend
# (env-overridable defaults above). Unknown logical names pass through
# unchanged. The Ollama mapping (identity) and backend selection live in
# llm-utils.sh.
openai_model_for() {
  case "$1" in
    gpt-oss:20b)  printf '%s' "$_OPENAI_MODEL_SMALL" ;;
    gpt-oss:120b) printf '%s' "$_OPENAI_MODEL_LARGE" ;;
    ds4:flash)    printf '%s' "$_OPENAI_MODEL_DS4_FLASH" ;;
    ds4:pro)      printf '%s' "$_OPENAI_MODEL_DS4_PRO" ;;
    *)            printf '%s' "$1" ;;
  esac
}
