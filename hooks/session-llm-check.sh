#!/bin/bash
# SessionStart hook — warns when the configured local-LLM slots resolve to no
# reachable server, so a broken configuration is visible at the top of the
# session instead of at the bottom of a stderr stream nobody reads.
#
# Why this exists: the model and the host list are separate env vars and
# nothing checks that they agree. Point OPENAI_HOSTS at a server that does not
# serve OPENAI_MODEL and every hook still "succeeds" — llm_request warns to
# stderr, returns empty, and each caller treats an empty response as "LLM
# unavailable, skip silently". Commit-message review and pre-review then pass
# without reviewing anything, indistinguishably from having nothing to say.
#
# Resolution only: this asks which host would serve each slot, using the same
# discovery the hooks use (and its 300s cache, so a warm session pays nothing).
# It sends no prompt — session-start latency budget, and a completion against a
# cold model server would stall the session for minutes.
#
# stdin:  Claude Code SessionStart JSON
# stdout: either nothing, or one hookSpecificOutput line naming the broken slots
#
# Any internal error degrades to silent exit 0 — a broken SessionStart hook
# must never block a session from starting.

set -u

HOOK_DIR="$(dirname "${BASH_SOURCE[0]}")"
LLM_UTILS="$HOOK_DIR/llm-utils.sh"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$LLM_UTILS" ] || exit 0

# Nothing configured is not a misconfiguration — a machine with no local LLM is
# a supported setup, and every caller already degrades cleanly. Only a pool that
# was asked for and cannot serve the slots is worth a word.
[ -n "${OPENAI_HOST:-}${OPENAI_HOSTS:-}${LLM_TRUSTED_HOSTS:-}${OLLAMA_HOST:-}${OLLAMA_HOSTS:-}" ] || exit 0

# shellcheck source=llm-utils.sh
source "$LLM_UTILS" >/dev/null 2>&1 || exit 0
command -v llm_select_backend >/dev/null 2>&1 || exit 0

BACKEND="$(llm_select_backend 2>/dev/null)" || exit 0

# The Ollama arm has no per-model host resolution to check here; its own
# discovery already fails closed, and probing it would cost a session-start
# round trip for the backend that is not preferred.
[ "$BACKEND" = "openai" ] || exit 0

BROKEN=""
for slot in llm:nothink llm:think; do
  real="$(llm_model_for "$slot" "$BACKEND" 2>/dev/null)" || continue
  [ -n "$real" ] || continue
  host="$(openai_host_for_model "$real" 2>/dev/null)"
  [ -n "$host" ] && continue
  BROKEN="${BROKEN}${BROKEN:+; }${slot} -> ${real}"
done

[ -n "$BROKEN" ] || exit 0

MESSAGE="Local LLM misconfigured: no reachable server serves ${BROKEN}. Hooks that use these slots (commit-msg-check, pre-review, retro-prescreen, llm-commands) will return empty and be skipped silently — they will not report an error. Tell the user, and check that the model name in the env block matches a model id the configured hosts actually serve (curl -s <host>/v1/models)."

jq -nc --arg ctx "$MESSAGE" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' \
  2>/dev/null || exit 0

exit 0
