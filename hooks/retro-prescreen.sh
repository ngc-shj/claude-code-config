#!/bin/bash
# Zero-Claude-token candidate discovery for the retrospect skill.
#
# Reads config ONLY via `retro-state.sh config --json` and state ONLY via
# `retro-state.sh show --json` — never opens the config/state files directly
# (that trust gate lives exclusively in retro-state.sh).
#
# Usage: retro-prescreen.sh <artifacts|github|transcripts|scout|scrub> [--json]
#
# --json is the ONLY machine-consumed interface (S2): one JSON document
#   {"source": <name>, "candidates": [...], "high_water": <json|null>,
#    "deferred": <bool>}
# built exclusively with jq --arg/-R so untrusted strings (filenames, PR
# titles, comment bodies) cannot break out of their encoded fields. Without
# --json, stdout is an advisory human report only — never parsed by callers.
#
# `scrub` deviates from every other mode: pure stdin->stdout redaction
# filter, no config/state read, no --json. It is the single shared artifact
# invoked by every source that emits free-text content (github comment
# bodies, artifacts LLM summaries, transcripts distilled lessons) AND by the
# skill's folding gate (C6), so redaction logic exists in exactly one place.
#
# Exit codes: 0 on every degraded path (missing gh/curl/LLM -> stderr
# warning + empty candidates); 2 on unknown mode or missing config.
#
# Privacy invariant: raw transcript content must never reach stdout or
# stderr, in any branch, including jq parse errors on malformed input.

set -u

HOOK_DIR="$(dirname "${BASH_SOURCE[0]}")"
RETRO_STATE_CLI="$HOOK_DIR/retro-state.sh"

command -v jq >/dev/null 2>&1 || { echo "retro-prescreen: jq is required" >&2; exit 2; }

# ---------------------------------------------------------------------------
# shared helpers
# ---------------------------------------------------------------------------

_config_json() {
  bash "$RETRO_STATE_CLI" config --json 2>/dev/null
}

_state_high_water() {
  local source="$1"
  bash "$RETRO_STATE_CLI" show --json 2>/dev/null \
    | jq -c --arg s "$source" '.sources[$s].high_water // null' 2>/dev/null
}

# Portable path-containment primitive (no realpath(1) dependency — absent on
# older macOS): resolve the file's FINAL real location and confirm it is
# contained within the given root's resolved form. A symlink whose target
# escapes the root is rejected even though its containing directory is inside
# the root — the check must follow the link to its terminal file, not stop at
# the directory holding the link. Emits the resolved path on success; empty
# on rejection.
_resolve_contained() {
  local file="$1" root="$2" dir base resolved_dir resolved_root
  dir=$(dirname "$file")
  base=$(basename "$file")
  case "$base" in
    *[[:cntrl:]]*)
      echo "retro-prescreen: rejecting filename with control characters in $dir" >&2
      return 1
      ;;
  esac
  resolved_root=$(cd -P -- "$root" 2>/dev/null && pwd -P) || return 1

  # Chase the ENTIRE symlink chain to its terminal real file, re-resolving the
  # containing directory at every hop. A single readlink only catches a
  # one-hop escape (D4); an attacker who plants two links inside the (untrusted)
  # repo — link A -> link B (both inside) -> target (outside) — would slip
  # past a one-hop check because A's immediate target B still sits inside the
  # root. Loop until the entry is no longer a symlink, capped at 40 hops so a
  # symlink cycle terminates instead of spinning.
  local cur="$file" hops=0 link_dest
  while [ -L "$cur" ] && [ "$hops" -lt 40 ]; do
    link_dest=$(readlink "$cur" 2>/dev/null) || return 1
    case "$link_dest" in
      /*) cur="$link_dest" ;;
      *)  cur="$(dirname "$cur")/$link_dest" ;;
    esac
    hops=$((hops + 1))
  done
  [ -L "$cur" ] && return 1   # still a link after the cap: refuse (likely a cycle)

  dir=$(dirname "$cur")
  base=$(basename "$cur")
  resolved_dir=$(cd -P -- "$dir" 2>/dev/null && pwd -P) || return 1

  case "$resolved_dir" in
    "$resolved_root"|"$resolved_root"/*) ;;
    *) return 1 ;;
  esac
  printf '%s/%s' "$resolved_dir" "$base"
}

# Emit an empty machine document for a degraded/error path.
_json_empty() {
  local source="$1" deferred="${2:-false}"
  jq -nc --arg s "$source" --argjson d "$([ "$deferred" = "true" ] && echo true || echo false)" \
    '{source: $s, candidates: [], high_water: null, deferred: $d}'
}

# ---------------------------------------------------------------------------
# scrub — shared deterministic redaction filter (stdin -> stdout)
# ---------------------------------------------------------------------------
#
# Redacts, in order: email addresses; IP addresses; /home/<user>/... paths;
# user-specific ~/... paths EXCEPT tokens under the repo-canonical prefixes
# ~/.claude/hooks/, ~/.claude/skills/, ~/.claude/rules/ (the exemption is
# scoped to the tilde-path class only — the email/IP//home//secret passes
# still run over the full text, including inside an allowlisted token);
# secret-shaped strings (20+ char base64/hex-ish tokens, AWS-style keys); and
# caps line length at 2000 chars. Replacement marker: [REDACTED].
cmd_scrub() {
  local input
  input=$(cat)

  # Cap line length first so later passes operate on bounded input.
  input=$(printf '%s' "$input" | awk '{ if (length($0) > 2000) print substr($0, 1, 2000); else print }')

  # Email addresses.
  input=$(printf '%s' "$input" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED]/g')

  # IPv4 addresses.
  input=$(printf '%s' "$input" | sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[REDACTED]/g')

  # IPv6 addresses. Two shapes: (a) a `::`-compressed form (the double colon is
  # a strong IPv6 signal that clock times `12:34:56` and `host:port` prose lack)
  # and (b) a full 8-group form. The hex-only groups and the `::`/8-group
  # requirement keep this off ordinary `key:value` text; allowlisted
  # `~/.claude/…` tokens and `owner/repo` keys carry neither shape.
  input=$(printf '%s' "$input" | sed -E '
    s/([0-9a-fA-F]{1,4}:)*([0-9a-fA-F]{1,4})?::([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4})*)?/[REDACTED]/g;
    s/([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}/[REDACTED]/g
  ')

  # /home/<user>/... paths (any depth).
  input=$(printf '%s' "$input" | sed -E 's#/home/[A-Za-z0-9_.-]+(/[^[:space:]]*)?#[REDACTED]#g')

  # AWS-style access key IDs (checked before the generic secret-shaped pass
  # so the AKIA prefix is not partially matched by the broader class first).
  input=$(printf '%s' "$input" | sed -E 's/\bAKIA[0-9A-Z]{16}\b/[REDACTED]/g')

  # User-specific ~/... paths, allowlisting the three repo-canonical
  # prefixes. Implemented token-by-token: only a bare `~/...` token whose
  # path does NOT start with one of the allowlisted prefixes is redacted.
  input=$(printf '%s' "$input" | perl -pe '
    s{(~/\S*)}{
      my $tok = $1;
      ($tok =~ m{^~/\.claude/(?:hooks|skills|rules)/}) ? $tok : "[REDACTED]"
    }ge
  ')

  # Secret-shaped strings: 20+ char runs of base64/hex-ish characters. `/`
  # is deliberately EXCLUDED from the class (unlike full base64 alphabet)
  # so a long allowlisted hook/skill/rule path is never mistaken for one
  # long secret token — path segments are separated by `/`, and each
  # individual segment (e.g. ".claude", "hooks", "example.sh") falls well
  # under the 20-char threshold. Run LAST so it does not eat an
  # already-redacted [REDACTED] marker's surroundings.
  input=$(printf '%s' "$input" | sed -E 's/[A-Za-z0-9+_=-]{20,}/[REDACTED]/g')

  printf '%s\n' "$input"
}

# ---------------------------------------------------------------------------
# artifacts
# ---------------------------------------------------------------------------

cmd_artifacts() {
  local as_json="$1" cfg hw source="artifacts"
  cfg=$(_config_json)
  if [ -z "$cfg" ]; then
    echo "retro-prescreen: no config; nothing to do" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi

  local glob repos allow_remote
  glob=$(jq -r '.sources.artifacts.glob // "docs/archive/review/*.md"' <<<"$cfg")
  repos=$(jq -r '.sources.artifacts.repos // [] | .[]' <<<"$cfg")
  allow_remote=$(jq -r '.sources.artifacts.allow_remote_llm // false' <<<"$cfg")

  # Egress gate for sending RAW artifact text to the LLM summarizer — decided
  # ONCE (not per file). Without a loopback backend (or explicit consent) the
  # raw artifacts are never sent; summarization is skipped and the source
  # falls back to file-list-only, which is still fully usable by the mining
  # sub-agent (it Reads the files locally). See _summarize_artifact.
  # shellcheck source=llm-utils.sh
  source "$HOOK_DIR/llm-utils.sh" 2>/dev/null
  local artifacts_llm_ok=0
  if _raw_llm_egress_ok "$allow_remote"; then
    artifacts_llm_ok=1
  else
    echo "retro-prescreen: artifacts LLM summarization skipped (no loopback backend / no allow_remote_llm consent) — emitting file list only" >&2
  fi

  local candidates='[]' hw_map='{}'
  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    local expanded
    expanded="${repo/#\~/$HOME}"
    [ -d "$expanded" ] || continue

    local repo_hw
    repo_hw=$(_state_high_water "$source" | jq -r --arg r "$repo" '.[$r] // "1970-01-01T00:00:00Z"' 2>/dev/null)
    [ -n "$repo_hw" ] && [ "$repo_hw" != "null" ] || repo_hw="1970-01-01T00:00:00Z"

    local glob_dir glob_pat
    glob_dir="$expanded/$(dirname "$glob")"
    glob_pat="$(basename "$glob")"
    [ -d "$glob_dir" ] || continue

    local repo_max="$repo_hw"
    local f
    while IFS= read -r -d '' f; do
      local resolved
      resolved=$(_resolve_contained "$f" "$expanded") || continue
      [ -n "$resolved" ] || continue

      local mtime_iso
      mtime_iso=$(jq -nr --argjson n "$(stat -c %Y "$resolved" 2>/dev/null || stat -f %m "$resolved" 2>/dev/null || echo 0)" '$n | todate')
      if [[ "$mtime_iso" > "$repo_max" ]]; then
        repo_max="$mtime_iso"
      fi

      local summary=""
      summary=$(_summarize_artifact "$resolved" "$artifacts_llm_ok")

      if [ -n "$summary" ]; then
        candidates=$(jq -c --arg p "$resolved" --arg s "$summary" '. + [{path: $p, summary: $s}]' <<<"$candidates")
      else
        candidates=$(jq -c --arg p "$resolved" '. + [{path: $p, summary: null}]' <<<"$candidates")
      fi
    done < <(find "$glob_dir" -maxdepth 1 -name "$glob_pat" -newermt "$repo_hw" -print0 2>/dev/null)

    hw_map=$(jq -c --arg r "$repo" --arg v "$repo_max" '. + {($r): $v}' <<<"$hw_map")
  done <<<"$repos"

  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c, high_water: $hw, deferred: false}'
  else
    echo "artifacts: $(jq 'length' <<<"$candidates") candidate file(s)"
    jq -r '.[] | "  - " + .path' <<<"$candidates"
  fi
}

# Summarize one artifact file to Symptom/Root-cause bullets via the local LLM.
# $2 is the egress-ok flag the caller computed ONCE via _raw_llm_egress_ok:
# when it is not "1", the raw artifact is NOT sent anywhere (the caller falls
# back to file-list-only). This mirrors the transcripts loopback gate — a
# review artifact carries the same untrusted internal content (paths,
# identifiers, vulnerability detail, secrets) and must not leave the machine
# to a non-loopback LLM without explicit allow_remote_llm consent, since the
# scrub only runs on the LLM's RESPONSE, never on the artifact sent to it.
# Every summary passes the shared scrub before it may enter candidates (T17).
_summarize_artifact() {
  local file="$1" egress_ok="$2"
  [ "$egress_ok" = "1" ] || return 0
  command -v llm_request >/dev/null 2>&1 || return 0

  local raw
  raw=$(llm_request "gpt-oss:120b" \
    "You extract failure patterns from a code-review artifact. Output concise Symptom/Root-cause bullets. If the document has no actionable failure pattern, output exactly: NONE." \
    30 1024 < "$file" 2>/dev/null)
  [ -n "$raw" ] || return 0
  [ "$raw" = "NONE" ] && return 0

  cmd_scrub <<<"$raw"
}

# ---------------------------------------------------------------------------
# github
# ---------------------------------------------------------------------------

cmd_github() {
  local as_json="$1" cfg source="github"
  cfg=$(_config_json)
  if [ -z "$cfg" ]; then
    echo "retro-prescreen: no config; nothing to do" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "retro-prescreen: gh CLI not found; skipping github source" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "retro-prescreen: gh is not authenticated; skipping github source" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    return 0
  fi

  local repos
  repos=$(jq -r '.sources.github.repos // [] | .[]' <<<"$cfg")

  local candidates='[]' hw_map='{}'
  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    local cursor
    cursor=$(_state_high_water "$source" | jq -r --arg r "$repo" '.[$r] // "1970-01-01T00:00:00Z"' 2>/dev/null)
    [ -n "$cursor" ] && [ "$cursor" != "null" ] || cursor="1970-01-01T00:00:00Z"

    local prs
    prs=$(gh pr list -R "$repo" --state merged --limit 200 \
      --search "updated:>=${cursor} sort:updated-asc" \
      --json number,title,updatedAt 2>/dev/null) || prs='[]'
    [ -n "$prs" ] || prs='[]'

    local count
    count=$(jq 'length' <<<"$prs" 2>/dev/null)
    [ -n "$count" ] || count=0
    if [ "$count" -eq 200 ]; then
      echo "retro-prescreen: github $repo returned 200 (limit) merged PRs; more may remain for next run" >&2
    fi

    local repo_max="$cursor"
    local pr_num
    while IFS= read -r pr_num; do
      [ -n "$pr_num" ] || continue
      local title updated_at
      title=$(jq -r --arg n "$pr_num" '.[] | select((.number|tostring) == $n) | .title' <<<"$prs")
      updated_at=$(jq -r --arg n "$pr_num" '.[] | select((.number|tostring) == $n) | .updatedAt' <<<"$prs")
      if [[ -n "$updated_at" ]] && [[ "$updated_at" > "$repo_max" ]]; then
        repo_max="$updated_at"
      fi

      # Emit one base64 line PER COMMENT (not per body line): a review comment
      # routinely spans multiple lines, and `--jq '.[].body'` newline-separates
      # them so line-splitting would shred one comment into several unrelated
      # candidates and drop interior blank lines. @base64 keeps each whole
      # comment (newlines and all) intact across the shell boundary.
      local bodies_raw scrubbed_bodies
      bodies_raw=$(gh api "repos/${repo}/pulls/${pr_num}/comments" --jq '.[].body | @base64' 2>/dev/null) || bodies_raw=""
      scrubbed_bodies='[]'
      if [ -n "$bodies_raw" ]; then
        local b64 body clean
        while IFS= read -r b64; do
          [ -n "$b64" ] || continue
          body=$(printf '%s' "$b64" | base64 -d 2>/dev/null) || continue
          [ -n "$body" ] || continue
          clean=$(cmd_scrub <<<"$body")
          scrubbed_bodies=$(jq -c --arg b "$clean" '. + [$b]' <<<"$scrubbed_bodies")
        done <<<"$bodies_raw"
      fi

      candidates=$(jq -c --arg repo "$repo" --arg n "$pr_num" --arg t "$title" --argjson bodies "$scrubbed_bodies" \
        '. + [{repo: $repo, number: ($n|tonumber), title: $t, comment_bodies: $bodies}]' <<<"$candidates")
    done < <(jq -r '.[].number' <<<"$prs")

    hw_map=$(jq -c --arg r "$repo" --arg v "$repo_max" '. + {($r): $v}' <<<"$hw_map")
  done <<<"$repos"

  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c, high_water: $hw, deferred: false}'
  else
    echo "github: $(jq 'length' <<<"$candidates") merged PR(s) with review comments"
    jq -r '.[] | "  - #" + (.number|tostring) + " " + .title' <<<"$candidates"
  fi
}

# ---------------------------------------------------------------------------
# transcripts
# ---------------------------------------------------------------------------

# Is every host in the active backend's resolved host list loopback
# (127.0.0.1 / ::1 / localhost)? Accepts full URLs, host:port, or bare
# hostnames — strips scheme/port before comparing. Empty list -> not
# loopback (nothing reachable means Stage 2 cannot run anyway; the caller
# treats that the same as LLM-offline).
_hosts_all_loopback() {
  local host stripped any=0
  while IFS= read -r host; do
    [ -n "$host" ] || continue
    any=1
    stripped="${host#http://}"
    stripped="${stripped#https://}"
    stripped="${stripped%%/*}"
    stripped="${stripped%%:*}"
    case "$stripped" in
      127.0.0.1|::1|localhost) ;;
      *) return 1 ;;
    esac
  done <<<"$1"
  [ "$any" -eq 1 ]
}

# Shared egress+reachability gate for sending RAW (pre-scrub) corpus text to
# the LLM. Both the transcripts distiller and the artifacts summarizer feed
# untrusted internal documents (review artifacts, transcript excerpts) to
# llm_request, so both MUST clear the same S3 egress boundary: the resolved
# backend must be loopback-only, OR the source's allow_remote_llm consent flag
# is set; and the backend must actually answer (else it is functionally
# offline). Returns 0 iff raw text may be sent. $1 = allow_remote value
# ("true"/other). Assumes llm-utils.sh is already sourced by the caller.
_raw_llm_egress_ok() {
  local allow_remote="$1" hosts egress_ok=0 probe
  command -v llm_resolved_hosts >/dev/null 2>&1 || return 1
  hosts=$(llm_resolved_hosts 2>/dev/null)
  if _hosts_all_loopback "$hosts"; then
    egress_ok=1
  elif [ "$allow_remote" = "true" ]; then
    egress_ok=1
  fi
  [ "$egress_ok" -eq 1 ] || return 1
  command -v llm_request >/dev/null 2>&1 || return 1
  probe=$(printf 'ping' | llm_request "gpt-oss:20b" "Reply with the single word: pong." 10 8 2>/dev/null)
  [ -n "$probe" ]
}

cmd_transcripts() {
  local as_json="$1" cfg source="transcripts"
  cfg=$(_config_json)
  if [ -z "$cfg" ]; then
    echo "retro-prescreen: no config; nothing to do" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi

  local root allow_remote markers
  root=$(jq -r '.sources.transcripts.root // "~/.claude/projects"' <<<"$cfg")
  root="${root/#\~/$HOME}"
  allow_remote=$(jq -r '.sources.transcripts.allow_remote_llm // false' <<<"$cfg")
  markers=$(jq -c '.correction_markers // []' <<<"$cfg")

  [ -d "$root" ] || { [ "$as_json" -eq 1 ] && _json_empty "$source"; return 0; }

  local cursor
  cursor=$(_state_high_water "$source" | jq -r '. // "1970-01-01T00:00:00Z"' 2>/dev/null)
  [ -n "$cursor" ] && [ "$cursor" != "null" ] || cursor="1970-01-01T00:00:00Z"

  # --- gather processed (non-excluded) files ---
  local now_epoch
  now_epoch=$(date +%s)
  local files=()
  local f base f_epoch
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
      [ "$base" = "${CLAUDE_SESSION_ID}.jsonl" ] && continue
    else
      f_epoch=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      [ $(( now_epoch - f_epoch )) -lt 300 ] && continue
    fi
    files+=("$f")
  done < <(find "$root" -name '*.jsonl' -newermt "$cursor" -print0 2>/dev/null)

  if [ "${#files[@]}" -eq 0 ]; then
    if [ "$as_json" -eq 1 ]; then
      jq -nc --arg s "$source" '{source: $s, candidates: [], high_water: null, deferred: false}'
    else
      echo "transcripts: no new sessions"
    fi
    return 0
  fi

  # --- Stage 1: structural extraction (jq), per file ---
  # Raw excerpt text lives ONLY in shell locals within this function and is
  # never echoed on its own — it is either fed to the LLM (stdin) or folded
  # into an aggregate count. jq errors on malformed input are suppressed and
  # rewrapped into a generic warning so a corrupt line can never leak raw
  # bytes onto stderr.
  local excerpts=() counts='{}' max_hw="$cursor"
  for f in "${files[@]}"; do
    local mtime_iso
    mtime_iso=$(jq -nr --argjson n "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)" '$n | todate')
    if [[ "$mtime_iso" > "$max_hw" ]]; then
      max_hw="$mtime_iso"
    fi

    # Parse each line independently so a single malformed or blank line
    # (transcripts routinely contain blank separators) cannot discard the
    # whole file's events. `jq -c` reads the line from stdin; parse errors on
    # that one line are suppressed to /dev/null so no raw bytes leak, and the
    # loop simply moves on. Only structurally-matching events survive.
    local file_events=""
    local line filtered
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      filtered=$(printf '%s' "$line" | jq -c --argjson markers "$markers" '
        # Normalize a user message body to a plain string. Real Claude Code
        # transcripts store .message.content as an ARRAY of content blocks
        # ([{type:"text",text:"…"}]), not a string; older/other shapes use a
        # bare string. `test` on an array throws, so a naive `.content | test`
        # silently drops every real user event (the correction-marker signal).
        def as_text:
          if type == "array" then ([.[]? | (.text? // (if type=="string" then . else "" end))] | join(" "))
          elif type == "string" then .
          else "" end;
        select(
          (.type? == "tool_result" and .is_error? == true)
          or (.hook_event?.decision? == "block")
          or (.decision? == "block")
          or (.type? == "user" and (
                ((.message.content? // .content? // "") | as_text) as $t
                | any($markers[]?; . as $m | $t | test($m))
              ))
        )
      ' 2>/dev/null) || continue
      [ -n "$filtered" ] || continue
      if [ -z "$file_events" ]; then
        file_events="$filtered"
      else
        file_events="$file_events"$'\n'"$filtered"
      fi
    done < "$f"

    local n
    n=$(printf '%s\n' "$file_events" | grep -c . || true)
    counts=$(jq -c --arg f "$(basename "$f")" --argjson n "$n" '. + {($f): $n}' <<<"$counts")

    if [ -n "$file_events" ] && [ "$file_events" != "" ]; then
      while IFS= read -r ev; do
        [ -n "$ev" ] || continue
        excerpts+=("$ev")
      done <<<"$file_events"
    fi
  done

  # --- S3 loopback egress gate + reachability probe (shared with artifacts) ---
  # shellcheck source=llm-utils.sh
  source "$HOOK_DIR/llm-utils.sh" 2>/dev/null
  local stage2_allowed=0
  if _raw_llm_egress_ok "$allow_remote"; then
    stage2_allowed=1
  fi

  if [ "$stage2_allowed" -ne 1 ]; then
    # Fail-closed: counts only, no content, deferred=true, high_water null
    # (cursor not advanced so nothing is skipped next run).
    if [ "$as_json" -eq 1 ]; then
      jq -nc --arg s "$source" --argjson counts "$counts" \
        '{source: $s,
          candidates: ($counts | to_entries | map({file: .key, event_count: .value})),
          high_water: null, deferred: true}'
    else
      echo "transcripts: LLM unavailable or non-loopback — deferred (counts only, no content)"
      jq -r 'to_entries[] | "  - " + .key + ": " + (.value|tostring) + " event(s)"' <<<"$counts"
    fi
    return 0
  fi

  # --- Stage 2: distillation + scrub ---
  local lessons='[]'
  local ev
  for ev in "${excerpts[@]}"; do
    local lesson
    lesson=$(llm_request "gpt-oss:20b" \
      "Distill this event into a single project-neutral lesson. Remove all paths, code, identifiers, and specifics. Output one sentence. If nothing actionable, output exactly: NONE." \
      20 256 <<<"$ev" 2>/dev/null)
    [ -n "$lesson" ] || continue
    [ "$lesson" = "NONE" ] && continue
    local clean
    clean=$(cmd_scrub <<<"$lesson")
    lessons=$(jq -c --arg l "$clean" '. + [$l]' <<<"$lessons")
  done

  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$lessons" --arg hw "$max_hw" \
      '{source: $s, candidates: $c, high_water: $hw, deferred: false}'
  else
    echo "transcripts: $(jq 'length' <<<"$lessons") distilled lesson(s)"
    jq -r '.[] | "  - " + .' <<<"$lessons"
  fi
}

# ---------------------------------------------------------------------------
# scout
# ---------------------------------------------------------------------------

cmd_scout() {
  local as_json="$1" cfg source="scout"
  cfg=$(_config_json)
  if [ -z "$cfg" ]; then
    echo "retro-prescreen: no config; nothing to do" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "retro-prescreen: curl not found; skipping scout source" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    return 0
  fi

  local urls
  urls=$(jq -r '.sources.scout.urls // [] | .[]' <<<"$cfg")
  local prior_hw
  prior_hw=$(_state_high_water "$source")
  [ -n "$prior_hw" ] && [ "$prior_hw" != "null" ] || prior_hw='{}'

  local candidates='[]' hw_map='{}'
  local url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    local body hash prior
    body=$(curl -s --proto '=https' --proto-redir '=https' --max-time 30 \
      --max-filesize 5242880 --max-redirs 3 "$url" 2>/dev/null)
    [ -n "$body" ] || continue
    hash=$(printf '%s' "$body" | sha256sum | awk '{print $1}')
    prior=$(jq -r --arg u "$url" '.[$u] // ""' <<<"$prior_hw")
    if [ "$hash" != "$prior" ]; then
      candidates=$(jq -c --arg u "$url" '. + [$u]' <<<"$candidates")
    fi
    hw_map=$(jq -c --arg u "$url" --arg h "$hash" '. + {($u): $h}' <<<"$hw_map")
  done <<<"$urls"

  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c, high_water: $hw, deferred: false}'
  else
    echo "scout: $(jq 'length' <<<"$candidates") changed URL(s)"
    jq -r '.[] | "  - " + .' <<<"$candidates"
  fi
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage: retro-prescreen.sh <artifacts|github|transcripts|scout|scrub> [--json]
  artifacts    find new review artifacts per configured repo
  github       find merged PRs + review comments since the last cursor
  transcripts  mine own session transcripts for failure signatures
  scout        hash-diff whitelisted URLs
  scrub        stdin->stdout deterministic redaction filter (no config/state)
EOF
}

MODE="${1:-}"
[ -n "$MODE" ] || { usage; exit 2; }
shift || true

AS_JSON=0
for arg in "$@"; do
  case "$arg" in
    --json) AS_JSON=1 ;;
  esac
done

case "$MODE" in
  scrub)
    cmd_scrub
    ;;
  artifacts)
    cmd_artifacts "$AS_JSON"
    ;;
  github)
    cmd_github "$AS_JSON"
    ;;
  transcripts)
    cmd_transcripts "$AS_JSON"
    ;;
  scout)
    cmd_scout "$AS_JSON"
    ;;
  *)
    usage
    exit 2
    ;;
esac
