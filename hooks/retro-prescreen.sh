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
# Env seams: RETRO_PRESCREEN_NOW (epoch seconds) simulates the present instant
# for tests, and is kept separate from retro-state.sh's RETRO_NOW because the
# other operand here is a real file mtime. It governs three controls (the
# cursor heal, the future-mtime bound, the 5-minute transcript freshness rule),
# so it announces itself on every run in which it is set, and a value ahead of
# the system clock is refused.
#
# Exit codes: 0 on every degraded path (missing gh/curl/LLM -> stderr
# warning + empty candidates); 2 on unknown mode, missing config, or a required
# primitive being unavailable (a JSON document is still emitted).
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
  # Resolved BEFORE the control-character branch: that branch reports a path,
  # and under `set -u` an unassigned resolved_root would abort there instead.
  resolved_root=$(cd -P -- "$root" 2>/dev/null && pwd -P) || return 1
  dir=$(dirname "$file")
  base=$(basename "$file")
  case "$base" in
    *[[:cntrl:]]*)
      # `$dir` here descends from the caller's `$expanded/...` glob, so it is
      # LEXICAL — stripping the physical root off it is a no-op whenever the
      # repo root is a symlink, and the message would then fall back to a bare
      # directory basename. Strip the lexical root, which is the spelling this
      # operand actually carries. The trigger is a filename inside an untrusted
      # sibling repository, so this must not put $HOME on stderr.
      echo "retro-prescreen: rejecting filename with control characters in $(_repo_relative "$dir" "$root")" >&2
      return 1
      ;;
  esac

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
  # A REGULAR file, not merely a contained one. `find -type f` narrows the scan
  # but is not the containment authority — this is. A FIFO named *.md in an
  # untrusted sibling repo otherwise blocks the summarizer's `< "$file"` before
  # any timeout applies, and the hook exits with no document at all.
  [ -f "$cur" ] || return 1

  dir=$(dirname "$cur")
  base=$(basename "$cur")
  resolved_dir=$(cd -P -- "$dir" 2>/dev/null && pwd -P) || return 1

  case "$resolved_dir" in
    "$resolved_root"|"$resolved_root"/*) ;;
    *) return 1 ;;
  esac
  # Declared residual (R51). What this returns is a NAME, not a handle: the
  # containment verdict is bound to what the path denoted at this instant, and
  # every later step — the caller's `stat`, the summarizer's read, and above all
  # the mining sub-agent that Reads the emitted path minutes later — re-resolves
  # that name afresh. So the guarantee is "no link planted before the scan
  # escapes the root", NOT "the object read is the object checked". Closing the
  # latter needs a descriptor the shell cannot carry across these boundaries
  # (open once with symlink resolution refused, then operate descriptor-relative
  # one component at a time), so it is declared rather than claimed. Do NOT read
  # the window as bounded by trust in the repository's own directories — the
  # symlink chase above exists precisely because this function treats that repo
  # as untrusted. It is open to any principal that can write inside it during
  # the run, including entirely non-adversarial ones (a checkout or rebase in
  # that repo, a sync client, a second agent). The verdict does not travel with
  # the name: every consumer of the emitted path must re-establish containment
  # at its own moment of use.
  printf '%s/%s' "$resolved_dir" "$base"
}

# The epoch floor, in both spellings. A healed cursor resets HERE, not to the
# present: clamping a poisoned cursor forward suppresses every file that
# already exists (all have mtime <= now) and loses the backlog permanently,
# while resetting backward costs one re-mine. skills/retrospect/pipeline.md
# decided this for the same failure — "the minimum is the only value that is
# safe in the recovery direction".
EPOCH_FLOOR_ISO='1970-01-01T00:00:00Z'
LAG_MARGIN=86400   # GitHub's search index lag; see cmd_github.

# Render $1 relative to root $2, for a stderr diagnostic.
#
# The caller passes the root in the SAME SPELLING as the path.
# `_resolve_contained`'s output is physical (`cd -P; pwd -P`); the `$dir` it
# computes internally and the configured repo value are lexical. Stripping a
# physical prefix off a lexical path is a silent no-op the moment the repo root
# is a symlink, which is why the operand kind is the caller's to get right and
# not something this function can infer.
#
# Fails closed: if a leading `/` survives the strip, the basename is emitted
# instead, so no branch can put $HOME — and therefore the user name — on stderr.
_repo_relative() {
  local path="$1" root="$2" rel
  rel="${path#"${root%/}/"}"
  case "$rel" in
    /*) rel="${path##*/}" ;;
  esac
  printf '%s' "$rel"
}

# ISO-8601 <-> whole-second epoch. jq is the single codec at both boundaries,
# replacing the `date -j -f` (BSD) / `date -d` (GNU) fork entirely.
#
# The operand is passed with --arg and the program is a fixed single-quoted
# literal. The interpolated spelling `jq -nr "\"$iso\" | fromdate"` satisfies
# every other criterion here while letting the operand choose its own epoch
# (`x" | 4102444800 # ` -> 4102444800, re-creating the cursor poisoning this
# whole change exists to close) and read the process environment via jq's `env`.
#
# `_iso_to_epoch` accepts a strict SUBSET of the language _is_iso (retro-state.sh)
# defines, and says so rather than claiming equality: _is_iso is a syntactic
# regex, `fromdate` is strptime-backed and semantic. Date-only values are
# expanded here because _norm_iso runs only in `seed`, not on the mark-run path
# the pipeline uses, so a bare YYYY-MM-DD is a live persisted spelling.
#
# A NEGATIVE parse (a pre-1970 cursor, which _is_iso accepts) is clamped to the
# floor SILENTLY — a representable instant before the epoch is not corrupt, and
# warning about it would misreport a well-formed cursor. Empty is returned only
# on a parse failure, and only that case warrants the caller's warning.
_iso_to_epoch() {
  local iso="$1" e
  case "$iso" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) iso="${iso}T00:00:00Z" ;;
  esac
  e=$(jq -nr --arg s "$iso" '$s | fromdate' 2>/dev/null) || e=""
  case "$e" in
    -[0-9]*)
      case "${e#-}" in *[!0-9]*) return 0 ;; esac
      printf '0'   # pre-1970 but representable: floor it, without a warning
      ;;
    [0-9]*)
      case "$e" in *[!0-9]*) return 0 ;; esac
      printf '%s' "$e"
      ;;
  esac
}

# Epoch -> ISO, validated against _is_iso's OWN regex rather than against jq's
# notion of a date: `todate` happily emits 5- and 7-digit years
# (253402300800 -> 10000-01-01T00:00:00Z) that retro-state.sh's _validate_hw
# rejects — and it rejects the WHOLE high_water object on one bad value, so an
# out-of-range entry for one repo would freeze every repo's cursor.
_epoch_to_iso() {
  local iso
  case "$1" in
    ''|*[!0-9]*) return 0 ;;
  esac
  iso=$(jq -nr --argjson n "$1" '$n | todate' 2>/dev/null) || return 0
  case "$iso" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) printf '%s' "$iso" ;;
  esac
}

# Present instant as whole-second epoch, or empty.
#
# `RETRO_PRESCREEN_NOW` is this function's own seam, kept separate from
# `RETRO_NOW` on purpose: `RETRO_NOW` pins the scheduling clock, where both
# operands are simulated, while the operand here is a real file mtime — routing
# this through `RETRO_NOW` would classify every genuinely existing artifact as
# future-dated.
#
# The seam governs three controls (the heal, the future-mtime bound, and the
# 5-minute freshness rule), so it is ANNOUNCED whenever set: the
# numeric-but-absurd case is otherwise completely silent, and a value ahead of
# the real clock is REFUSED — the seam exists to pin the present downward
# relative to fixture mtimes, and a future value would disable the freshness
# rule and admit the in-flight session transcript into the Stage-2 egress set.
#
# Empty means "no heal available", never epoch 0: an unreadable clock must
# disable the bound loudly rather than pin every cursor at its floor.
_now_epoch() {
  local real n
  real=$(date -u +%s 2>/dev/null)
  case "$real" in ''|*[!0-9]*) real="" ;; esac
  if [ -n "${RETRO_PRESCREEN_NOW:-}" ]; then
    n="$RETRO_PRESCREEN_NOW"
    case "$n" in
      ''|*[!0-9]*)
        echo "retro-prescreen: RETRO_PRESCREEN_NOW is not numeric — heal and freshness bounds disabled this run" >&2
        return 0
        ;;
    esac
    # Refused also when the real clock is unreadable: without it the guard is
    # skipped exactly when nothing else can bound the seam, and a year-2100
    # value then disables the heal, the future-mtime bound and the freshness
    # rule at once.
    if [ -z "$real" ] || [ "$n" -gt "$real" ]; then
      echo "retro-prescreen: RETRO_PRESCREEN_NOW cannot be bounded against the system clock — refused" >&2
      return 0
    fi
    echo "retro-prescreen: RETRO_PRESCREEN_NOW is set ($n) — the present instant is simulated this run" >&2
    printf '%s' "$n"
    return 0
  fi
  printf '%s' "$real"
}

# Heal a persisted cursor that is ahead of the present, at READ-IN — one
# adjudicator, not two (R48). Integer comparison, never string: lexicographic
# `>` reports "999999999" as greater than "1784047446", so a `[[ > ]]`
# implementation would heal away every cursor written before 2001-09-09.
#
# The heal moves BACKWARD (to the epoch floor), never forward. Every fixture in
# this file's suite uses ten-digit epochs where the two comparisons agree, so
# the nine-digit case is the one that discriminates them.
_heal_cursor() {
  local value="$1" now="$2" source="$3" label="$4" shown
  if [ -n "$now" ] && [ "$value" -gt "$now" ]; then
    shown=$(_epoch_to_iso "$value"); [ -n "$shown" ] || shown="epoch $value"
    # No egress clause here: cmd_github has no equivalent of artifacts'
    # artifacts_llm_ok=0 / transcripts' stage2_allowed=0, so the two call sites
    # that DO suppress raw egress say so themselves.
    printf 'retro-prescreen: %s: %s cursor %s is past the present — reset to %s; this source will re-mine once\n' \
      "$source" "$label" "$shown" "$EPOCH_FLOOR_ISO" >&2
    printf '0'
    return 0
  fi
  printf '%s' "$value"
}

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
  input=$(printf '%s' "$input" | sed -E 's#/(home|Users)/[A-Za-z0-9_.-]+(/[^[:space:]]*)?#[REDACTED]#g')

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

  local glob repos_json allow_remote
  glob=$(jq -r '.sources.artifacts.glob // "docs/archive/review/*.md"' <<<"$cfg")
  # Empty elements are dropped here rather than skipped in the loop: an empty
  # string would otherwise become a "" key in the emitted map, and the shapes
  # retro-state.sh validates differ on whether that is accepted.
  repos_json=$(jq -c '[.sources.artifacts.repos // [] | .[] | select(. != null and . != "")]' <<<"$cfg")
  allow_remote=$(jq -r '.sources.artifacts.allow_remote_llm // false' <<<"$cfg")

  local now_epoch
  now_epoch=$(_now_epoch)
  [ -n "$now_epoch" ] || echo "retro-prescreen: $source: cannot read the present instant — heal and future-mtime bounds disabled this run" >&2

  # --- seed pass: every configured repo gets its healed cursor BEFORE the scan.
  #
  # Stated over the config array and the whole loop, not over a line. The scan
  # loop below has guards that skip a repo (root absent, archive dir absent),
  # and retro-state.sh writes `.high_water = $hw` as a WHOLE-OBJECT
  # REPLACEMENT — so a repo missing from the emitted map is DELETED from state,
  # reset to 1970, and re-mined in full on the next run it is visible. Seeding
  # here means no guard added later can re-open that.
  #
  # One `show --json` read for the run, not one per repo: N re-reads across the
  # loop can observe N different states if anything writes concurrently, and the
  # whole-object replacement would then persist the mixture.
  local state_hw
  state_hw=$(_state_high_water "$source")
  [ -n "$state_hw" ] && [ "$state_hw" != "null" ] || state_hw='{}'

  local hw_epoch='{}' reset_any=0 repo
  while IFS= read -r repo; do
    local persisted_iso persisted_epoch healed
    persisted_iso=$(jq -r --arg r "$repo" '.[$r] // ""' <<<"$state_hw" 2>/dev/null)
    persisted_epoch=$(_iso_to_epoch "$persisted_iso")
    # EVERY cause that puts a cursor back at the floor sets the flag, not just
    # the heal. The three are: an unparseable-but-_is_iso-valid persisted value
    # (_is_iso is a syntactic regex, fromdate is semantic, so `2026-13-01` is
    # storable through seed/mark-run and unreadable here), an absent state
    # entry, and a cursor ahead of the present. All three make the whole corpus
    # a candidate, which is the condition the egress gate below reacts to —
    # keying it on the heal alone left two of the three shipping raw text.
    if [ -z "$persisted_epoch" ]; then
      [ -n "$persisted_iso" ] && printf 'retro-prescreen: %s: unparseable persisted cursor for %s — reset to %s\n' \
        "$source" "${repo##*/}" "$EPOCH_FLOOR_ISO" >&2
      persisted_epoch=0
      reset_any=1
    elif [ -z "$persisted_iso" ]; then
      # No state entry AT ALL — distinct from a persisted `1970-01-01T00:00:00Z`,
      # which parses to the same epoch but is the ordinary never-mined steady
      # state, not an anomaly. Keying on the epoch conflated the two and
      # disabled egress on every first run.
      reset_any=1
    fi
    healed=$(_heal_cursor "$persisted_epoch" "$now_epoch" "$source" "persisted")
    [ "$healed" = "$persisted_epoch" ] || reset_any=1
    hw_epoch=$(jq -c --arg r "$repo" --argjson v "$healed" '. + {($r): $v}' <<<"$hw_epoch")
  done < <(jq -r '.[]' <<<"$repos_json")

  # Egress gate for sending RAW artifact text to the LLM summarizer — decided
  # ONCE for the run, and AFTER the seed pass so the heal verdict is known for
  # the WHOLE configured array. Deciding it per repo inside the scan loop would
  # send the raw bytes of every repo processed before the poisoned one.
  #
  # A heal resets a cursor to the floor, which makes the entire corpus a
  # candidate — and the heal's trigger is a cursor ahead of the present, whose
  # ordinary producers are backward clock movements (NTP step-back, RTC-local
  # dual boot, VM snapshot restore), not corruption. Widening the candidate set
  # must not widen the off-machine set with it. Recovery is unaffected: the
  # mining sub-agent Reads the files locally, and file-list-only is already the
  # documented degraded mode.
  # shellcheck source=llm-utils.sh
  source "$HOOK_DIR/llm-utils.sh" 2>/dev/null
  # The source above is stderr-suppressed, so a missing or unreadable
  # llm-utils.sh would leave _file_mtime_epoch undefined and every mtime
  # unreadable — every file a candidate, no cursor ever advancing, forever, and
  # exit 0. Refuse instead, with a document on stdout so the caller still parses
  # a well-formed reply.
  if ! command -v _file_mtime_epoch >/dev/null 2>&1; then
    echo "retro-prescreen: required primitive _file_mtime_epoch is unavailable (llm-utils.sh not sourced)" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi
  local artifacts_llm_ok=0
  if [ "$reset_any" -eq 1 ]; then
    echo "retro-prescreen: $source: a cursor was reset to the floor this run — raw artifact text is not sent off-machine on a resetting run" >&2
  elif _raw_llm_egress_ok "$allow_remote"; then
    artifacts_llm_ok=1
  else
    echo "retro-prescreen: artifacts LLM summarization skipped (no loopback backend / no allow_remote_llm consent) — emitting file list only" >&2
  fi

  local candidates='[]'
  while IFS= read -r repo; do
    local expanded
    expanded="${repo/#\~/$HOME}"
    if [ ! -d "$expanded" ]; then
      printf 'retro-prescreen: %s: skipping %s — repo root absent; its cursor is preserved\n' \
        "$source" "${repo##*/}" >&2
      continue
    fi

    local glob_dir glob_pat repo_phys
    glob_dir="$expanded/$(dirname "$glob")"
    glob_pat="$(basename "$glob")"
    # The physical root, for _repo_relative: _resolve_contained returns a
    # physical path while the configured value is only tilde-expanded, and the
    # two differ whenever the repo root is a symlink.
    repo_phys=$(cd -P -- "$expanded" 2>/dev/null && pwd -P) || repo_phys="$expanded"
    if [ ! -d "$glob_dir" ]; then
      printf 'retro-prescreen: %s: skipping %s — archive directory absent; its cursor is preserved\n' \
        "$source" "${repo##*/}" >&2
      continue
    fi

    local cursor_epoch repo_max
    cursor_epoch=$(jq -r --arg r "$repo" '.[$r]' <<<"$hw_epoch")
    repo_max="$cursor_epoch"

    # Per-file diagnostics are AGGREGATED. With the `-newer` pre-filter gone the
    # scan enumerates the whole corpus, so a per-file line scales with it — the
    # steady state on a healthy run, and the fixed point under a slow clock. The
    # heal announcement, the clock-disabled notice and the skipped-repo signal
    # are single lines on this same stream; burying them defeats them as surely
    # as omitting them.
    local n_sup=0 n_future=0 n_nostat=0 n_seen=0 future_example="" f
    while IFS= read -r -d '' f; do
      local resolved
      # The LEXICAL root: _resolve_contained resolves it itself for the
      # containment check, and its own diagnostic reports a lexical `$dir`, so
      # the operand kinds match on both sides. `$repo_phys` is for the physical
      # `resolved` paths below.
      resolved=$(_resolve_contained "$f" "$expanded") || continue
      [ -n "$resolved" ] || continue
      n_seen=$((n_seen + 1))

      local mtime_epoch
      mtime_epoch=$(_file_mtime_epoch "$resolved")
      if [ -n "$mtime_epoch" ]; then
        # Integer comparison against a whole-second cursor. Both operands come
        # from `%Y`, so a file mined in run N is strictly not greater in run
        # N+1 and the source drains. Declared residual: an artifact written
        # into the cursor's own second AFTER the run that recorded it is
        # skipped permanently — under one second, per repo, per run.
        if [ "$mtime_epoch" -le "$cursor_epoch" ]; then
          n_sup=$((n_sup + 1))
          continue
        fi
        if [ -z "$now_epoch" ]; then
          : # No clock: an increment cannot be judged, so it is not recorded.
        elif [ "$mtime_epoch" -gt "$now_epoch" ]; then
          n_future=$((n_future + 1))
          [ -n "$future_example" ] || future_example=$(_repo_relative "$resolved" "$repo_phys")
        elif [ "$mtime_epoch" -gt "$repo_max" ]; then
          repo_max="$mtime_epoch"
        fi
      else
        n_nostat=$((n_nostat + 1))
      fi

      local summary=""
      summary=$(_summarize_artifact "$resolved" "$artifacts_llm_ok")

      if [ -n "$summary" ]; then
        candidates=$(jq -c --arg p "$resolved" --arg s "$summary" '. + [{path: $p, summary: $s}]' <<<"$candidates")
      else
        candidates=$(jq -c --arg p "$resolved" '. + [{path: $p, summary: null}]' <<<"$candidates")
      fi
    done < <(find "$glob_dir" -maxdepth 1 -name "$glob_pat" -type f -print0 2>/dev/null)

    [ "$n_sup" -eq 0 ] || printf 'retro-prescreen: %s: %s: %d of %d at or below the cursor — suppressed\n' \
      "$source" "${repo##*/}" "$n_sup" "$n_seen" >&2
    [ "$n_future" -eq 0 ] || printf 'retro-prescreen: %s: %s: %d of %d future-dated (e.g. %s) — kept, cursor not advanced\n' \
      "$source" "${repo##*/}" "$n_future" "$n_seen" "$future_example" >&2
    [ "$n_nostat" -eq 0 ] || printf 'retro-prescreen: %s: %s: %d of %d with an unreadable mtime — kept, cursor not advanced\n' \
      "$source" "${repo##*/}" "$n_nostat" "$n_seen" >&2

    hw_epoch=$(jq -c --arg r "$repo" --argjson v "$repo_max" '. + {($r): $v}' <<<"$hw_epoch")
  done < <(jq -r '.[]' <<<"$repos_json")

  # Project to ISO at emission. A conversion that leaves the range _validate_hw
  # accepts re-emits the HEALED value for that key — never an empty string and
  # never a dropped key, either of which discards the whole object.
  local hw_map='{}'
  while IFS= read -r repo; do
    local e iso
    e=$(jq -r --arg r "$repo" '.[$r]' <<<"$hw_epoch")
    iso=$(_epoch_to_iso "$e")
    if [ -z "$iso" ]; then
      printf 'retro-prescreen: %s: %s: cursor %s is not representable — re-emitting %s\n' \
        "$source" "${repo##*/}" "$e" "$EPOCH_FLOOR_ISO" >&2
      iso="$EPOCH_FLOOR_ISO"
    fi
    hw_map=$(jq -c --arg r "$repo" --arg v "$iso" '. + {($r): $v}' <<<"$hw_map")
  done < <(jq -r '.[]' <<<"$repos_json")

  if [ "$as_json" -eq 1 ]; then
    # No configured repos -> null, never `{}`: an empty object passes
    # _validate_hw trivially and the whole-object replacement then wipes every
    # repo's cursor in one write.
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c,
        high_water: (if ($hw | length) == 0 then null else $hw end),
        deferred: false}'
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
  # Bounded like cmd_scout bounds its untrusted network input (--max-filesize
  # 5242880). This file comes from an untrusted sibling repository and is read
  # whole into a JSON request body before leaving the machine.
  raw=$(head -c 5242880 < "$file" 2>/dev/null | llm_request "gpt-oss:120b" \
    "You extract failure patterns from a code-review artifact. Output concise Symptom/Root-cause bullets. If the document has no actionable failure pattern, output exactly: NONE." \
    30 1024 2>/dev/null)
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

  # Empty elements dropped: an empty string would become a "" key, which
  # _validate_hw's github arm rejects (it requires owner/repo), discarding the
  # whole object and freezing every repo's cursor.
  local repos_json
  # Shape-filtered at the boundary, not just null/empty: the value becomes a
  # high_water KEY, and retro-state.sh's github arm requires owner/repo. One bad
  # element makes _validate_hw reject the whole object, which under the run-for-
  # its-own-status rule now aborts the entire retrospect run — a hand-edited
  # typo should skip one repo with a diagnostic instead.
  repos_json=$(jq -c '[.sources.github.repos // [] | .[]
                       | select(type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))]' <<<"$cfg")
  local dropped
  dropped=$(jq -r '[.sources.github.repos // [] | .[]
                    | select((type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) | not)
                    | tostring] | join(", ")' <<<"$cfg" 2>/dev/null) || dropped=""
  [ -z "$dropped" ] || printf 'retro-prescreen: %s: skipping malformed repo entries (need owner/repo): %s\n' \
    "$source" "$dropped" >&2

  # Seed and heal BEFORE the environment guards below. `gh` absent or
  # unauthenticated is a degraded run, not a reason to leave a poisoned cursor
  # unhealed and unannounced — and emitting an empty document there would make
  # the orchestrator skip mark-run entirely, so `last_run` would never advance
  # and the source would stay permanently due.
  local now_epoch
  now_epoch=$(_now_epoch)
  [ -n "$now_epoch" ] || echo "retro-prescreen: $source: cannot read the present instant — heal and future bounds disabled this run" >&2

  local state_hw
  state_hw=$(_state_high_water "$source")
  [ -n "$state_hw" ] && [ "$state_hw" != "null" ] || state_hw='{}'

  local hw_epoch='{}' repo
  while IFS= read -r repo; do
    local persisted_iso persisted_epoch
    persisted_iso=$(jq -r --arg r "$repo" '.[$r] // ""' <<<"$state_hw" 2>/dev/null)
    persisted_epoch=$(_iso_to_epoch "$persisted_iso")
    if [ -z "$persisted_epoch" ]; then
      [ -n "$persisted_iso" ] && printf 'retro-prescreen: %s: unparseable persisted cursor for %s — treating as %s\n' \
        "$source" "$repo" "$EPOCH_FLOOR_ISO" >&2
      persisted_epoch=0
    fi
    hw_epoch=$(jq -c --arg r "$repo" --argjson v "$(_heal_cursor "$persisted_epoch" "$now_epoch" "$source" "persisted")" \
      '. + {($r): $v}' <<<"$hw_epoch")
  done < <(jq -r '.[]' <<<"$repos_json")

  local candidates='[]'
  if ! command -v gh >/dev/null 2>&1; then
    echo "retro-prescreen: gh CLI not found; skipping github source" >&2
    _github_emit "$as_json" "$source" "$candidates" "$hw_epoch" "$repos_json"
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "retro-prescreen: gh is not authenticated; skipping github source" >&2
    _github_emit "$as_json" "$source" "$candidates" "$hw_epoch" "$repos_json"
    return 0
  fi

  while IFS= read -r repo; do
    local cursor_epoch bound_iso
    cursor_epoch=$(jq -r --arg r "$repo" '.[$r]' <<<"$hw_epoch")
    # The query bound is the healed cursor widened by LAG_MARGIN. GitHub's
    # search index lags, so a PR can be absent at query time and permanently
    # below an un-widened bound afterwards. The widening is free only because a
    # local suppression predicate now re-adjudicates what comes back — without
    # it the trailing window would be re-mined on every run, forever.
    bound_iso=$(_epoch_to_iso "$(( cursor_epoch > LAG_MARGIN ? cursor_epoch - LAG_MARGIN : 0 ))")
    [ -n "$bound_iso" ] || bound_iso="$EPOCH_FLOOR_ISO"

    local prs
    prs=$(gh pr list -R "$repo" --state merged --limit 200 \
      --search "updated:>=${bound_iso} sort:updated-asc" \
      --json number,title,updatedAt 2>/dev/null) || prs='[]'
    [ -n "$prs" ] || prs='[]'

    local count
    count=$(jq 'length' <<<"$prs" 2>/dev/null)
    [ -n "$count" ] || count=0
    if [ "$count" -eq 200 ]; then
      echo "retro-prescreen: github $repo returned 200 (limit) merged PRs; more may remain for next run" >&2
    fi

    local repo_max="$cursor_epoch" n_sup=0
    local pr_num
    while IFS= read -r pr_num; do
      [ -n "$pr_num" ] || continue
      local title updated_at updated_epoch
      # Scrubbed like the comment bodies below: a merged-PR title is free-text
      # from the same untrusted API, and it reaches the --json document, the
      # human report, the mining sub-agent and from there a committed doc.
      title=$(cmd_scrub <<<"$(jq -r --arg n "$pr_num" '.[] | select((.number|tostring) == $n) | .title' <<<"$prs")")
      updated_at=$(jq -r --arg n "$pr_num" '.[] | select((.number|tostring) == $n) | .updatedAt' <<<"$prs")
      updated_epoch=$(_iso_to_epoch "$updated_at")
      if [ -n "$updated_epoch" ]; then
        # The local adjudicator this source never had. Without it the server's
        # `updated:>=` filter is the only thing deciding membership, which is
        # the same shape as the `find -newer` pre-filter this change deletes.
        if [ "$updated_epoch" -le "$cursor_epoch" ]; then
          n_sup=$((n_sup + 1))
          continue
        fi
        if [ -z "$now_epoch" ]; then
          :
        elif [ "$updated_epoch" -gt "$now_epoch" ]; then
          printf 'retro-prescreen: %s: %s #%s is future-dated — kept, cursor not advanced\n' \
            "$source" "$repo" "$pr_num" >&2
        elif [ "$updated_epoch" -gt "$repo_max" ]; then
          repo_max="$updated_epoch"
        fi
      else
        printf 'retro-prescreen: %s: %s #%s has an unparseable updatedAt — kept, cursor not advanced\n' \
          "$source" "$repo" "$pr_num" >&2
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

    [ "$n_sup" -eq 0 ] || printf 'retro-prescreen: %s: %s: %d of %d at or below the cursor — suppressed\n' \
      "$source" "$repo" "$n_sup" "$count" >&2

    hw_epoch=$(jq -c --arg r "$repo" --argjson v "$repo_max" '. + {($r): $v}' <<<"$hw_epoch")
  done < <(jq -r '.[]' <<<"$repos_json")

  _github_emit "$as_json" "$source" "$candidates" "$hw_epoch" "$repos_json"
}

# Project the epoch-keyed cursor map to ISO and emit the document. One emitter
# for every exit path of cmd_github, so a degraded path cannot silently drop the
# healed cursors the way an `_json_empty` return did.
_github_emit() {
  local as_json="$1" source="$2" candidates="$3" hw_epoch="$4" repos_json="$5"
  local hw_map='{}' repo
  while IFS= read -r repo; do
    local e iso
    e=$(jq -r --arg r "$repo" '.[$r]' <<<"$hw_epoch")
    iso=$(_epoch_to_iso "$e")
    if [ -z "$iso" ]; then
      printf 'retro-prescreen: %s: %s: cursor %s is not representable — re-emitting %s\n' \
        "$source" "$repo" "$e" "$EPOCH_FLOOR_ISO" >&2
      iso="$EPOCH_FLOOR_ISO"
    fi
    hw_map=$(jq -c --arg r "$repo" --arg v "$iso" '. + {($r): $v}' <<<"$hw_map")
  done < <(jq -r '.[]' <<<"$repos_json")

  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c,
        high_water: (if ($hw | length) == 0 then null else $hw end),
        deferred: false}'
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

  # Sourced ABOVE the gather loop: _file_mtime_epoch lives in llm-utils.sh (it
  # has three consumers that never load this hook) and both adopter sites below
  # would otherwise run before it is defined. The source is stderr-suppressed,
  # so its failure has no other observer — hence the explicit guard.
  # shellcheck source=llm-utils.sh
  source "$HOOK_DIR/llm-utils.sh" 2>/dev/null
  if ! command -v _file_mtime_epoch >/dev/null 2>&1; then
    echo "retro-prescreen: required primitive _file_mtime_epoch is unavailable (llm-utils.sh not sourced)" >&2
    [ "$as_json" -eq 1 ] && _json_empty "$source"
    exit 2
  fi

  # One clock for the whole function. The 5-minute freshness rule used to read
  # `date +%s` directly while the cursor read its own — two adjudicators of
  # "what time is it", free to disagree.
  local now_epoch
  now_epoch=$(_now_epoch)
  [ -n "$now_epoch" ] || echo "retro-prescreen: $source: cannot read the present instant — heal and future bounds disabled this run" >&2

  local persisted_iso cursor
  persisted_iso=$(_state_high_water "$source" | jq -r '. // ""' 2>/dev/null)
  [ "$persisted_iso" != "null" ] || persisted_iso=""
  cursor=$(_iso_to_epoch "$persisted_iso")
  if [ -z "$cursor" ]; then
    [ -n "$persisted_iso" ] && printf 'retro-prescreen: %s: unparseable persisted cursor — treating as %s\n' \
      "$source" "$EPOCH_FLOOR_ISO" >&2
    cursor=0
  fi
  local healed
  healed=$(_heal_cursor "$cursor" "$now_epoch" "$source" "persisted")
  local healed_any=0
  [ "$healed" = "$cursor" ] || healed_any=1
  cursor="$healed"

  # The root can be absent on a fresh machine or a not-yet-created config path.
  # Emit the healed cursor even then: `_json_empty`'s null would make the
  # orchestrator skip mark-run, so `last_run` would never advance and the source
  # would stay permanently due while its poisoned cursor survived.
  if [ ! -d "$root" ]; then
    _transcripts_emit "$as_json" "$source" '[]' "$cursor" false "no root directory"
    return 0
  fi

  # --- gather processed (non-excluded) files ---
  # Index-aligned arrays rather than an associative one (bash 3.2 floor): the
  # gather loop already reads each mtime, so Stage 1 must not read it again —
  # C1 budgets one stat per file and two is the shape N-R2 measured and rejected.
  local files=() files_epoch=() f base f_epoch
  while IFS= read -r -d '' f; do
    base="${f##*/}"
    f_epoch=$(_file_mtime_epoch "$f")
    # The two exclusions are CUMULATIVE, not alternatives. The session id
    # excludes exactly THIS session's transcript and says nothing about any
    # other, so writing them as if/else meant that on the normal path — where
    # CLAUDE_SESSION_ID is set — a concurrent session's in-flight .jsonl was
    # enumerated, extracted and sent raw to the backend.
    if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
      [ "$base" = "${CLAUDE_SESSION_ID}.jsonl" ] && continue
    fi
    # BOTH operands validated. Under `set -u`, `$(( n - not-a-number ))` aborts
    # the shell mid-loop — no JSON document at all — and an empty `now_epoch`
    # makes the difference negative, excluding EVERY transcript as "too fresh".
    # Unknown either way keeps the file, the permissive direction.
    if [ -n "$now_epoch" ] && [ -n "$f_epoch" ]; then
      # Bounded on BOTH sides: a mtime in the future is not "written moments
      # ago", it is clock-skewed, and excluding it here would keep it from ever
      # reaching the future-mtime diagnostic that exists to report it.
      if [ "$f_epoch" -le "$now_epoch" ] && [ "$(( now_epoch - f_epoch ))" -lt 300 ]; then
        continue
      fi
    fi
    files+=("$f")
    files_epoch+=("$f_epoch")
  done < <(find "$root" -name '*.jsonl' -print0 2>/dev/null)

  if [ "${#files[@]}" -eq 0 ]; then
    _transcripts_emit "$as_json" "$source" '[]' "$cursor" false "no new sessions"
    return 0
  fi

  # --- Stage 1: structural extraction (jq), per file ---
  # Raw excerpt text lives ONLY in shell locals within this function and is
  # never echoed on its own — it is either fed to the LLM (stdin) or folded
  # into an aggregate count. jq errors on malformed input are suppressed and
  # rewrapped into a generic warning so a corrupt line can never leak raw
  # bytes onto stderr.
  local excerpts=() counts='{}'
  local max_hw="$cursor" ordinal=0
  local n_sup=0 n_future=0 n_nostat=0 n_seen=0
  local fi=-1
  for f in ${files[@]+"${files[@]}"}; do
    fi=$((fi + 1))
    n_seen=$((n_seen + 1))
    # Same whole-second cursor authority as cmd_artifacts: both operands come
    # from `%Y`, so a transcript mined in run N is not greater in run N+1 and
    # the source drains. Extraction is skipped along with the candidate, which
    # also stops re-feeding an already-mined transcript to the summarizer.
    local mtime_epoch pending_hw=""
    mtime_epoch="${files_epoch[$fi]}"
    if [ -n "$mtime_epoch" ]; then
      if [ "$mtime_epoch" -le "$cursor" ]; then
        n_sup=$((n_sup + 1))
        continue
      fi
      if [ -z "$now_epoch" ]; then
        :
      elif [ "$mtime_epoch" -gt "$now_epoch" ]; then
        n_future=$((n_future + 1))
      elif [ "$mtime_epoch" -gt "$max_hw" ]; then
        # STAGED, not committed. The open below can fail, and this loop then
        # `continue`s without extracting anything — advancing the cursor here
        # would carry that file's own mtime past itself and suppress it on every
        # later run. Committed after the descriptor closes.
        pending_hw="$mtime_epoch"
      fi
    else
      n_nostat=$((n_nostat + 1))
    fi

    # Parse each line independently so a single malformed or blank line
    # (transcripts routinely contain blank separators) cannot discard the
    # whole file's events. `jq -c` reads the line from stdin; parse errors on
    # that one line are suppressed to /dev/null so no raw bytes leak, and the
    # loop simply moves on. Only structurally-matching events survive.
    local file_events=""
    local line filtered
    # Open through an explicit descriptor rather than `done < "$f"`. The shell's
    # own redirection failure is NOT covered by the `2>/dev/null` on every jq /
    # stat / find in this loop, and it names the file — and a transcript path
    # carries the user name and the full repository location twice over, which
    # is exactly the shape cmd_scrub redacts. The declared privacy invariant at
    # the top of this file says "in any branch"; this was the branch.
    # The brace group is load-bearing: in `exec 3< "$f" 2>/dev/null` the
    # redirections are applied left to right, so the failing open reports to the
    # still-live stderr and prints the path before the suppression takes effect
    # (and the suppression would then persist for the rest of the script).
    if ! { exec 3< "$f"; } 2>/dev/null; then
      printf 'retro-prescreen: %s: a session file is unreadable — skipped\n' "$source" >&2
      continue
    fi
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
    done <&3
    exec 3<&-
    [ -z "$pending_hw" ] || max_hw="$pending_hw"

    local n
    n=$(printf '%s\n' "$file_events" | grep -c . || true)
    # Keyed by a per-run ORDINAL, not by the basename. A transcript's basename
    # is the session UUID, and `counts` is projected onto BOTH the --json
    # document and the human report, so keying it by identity leaks that
    # identity on both streams. F-R6 forbids a filename on either. Nothing
    # machine-readable consumes the key — the human run report needs
    # cardinality and per-session counts, and an ordinal carries both.
    ordinal=$((ordinal + 1))
    counts=$(jq -c --arg f "$ordinal" --argjson n "$n" '. + {($f): $n}' <<<"$counts")

    if [ -n "$file_events" ] && [ "$file_events" != "" ]; then
      while IFS= read -r ev; do
        [ -n "$ev" ] || continue
        excerpts+=("$ev")
      done <<<"$file_events"
    fi
  done

  [ "$n_sup" -eq 0 ] || printf 'retro-prescreen: %s: %d of %d at or below the cursor — suppressed\n' \
    "$source" "$n_sup" "$n_seen" >&2
  [ "$n_future" -eq 0 ] || printf 'retro-prescreen: %s: %d of %d future-dated — kept, cursor not advanced\n' \
    "$source" "$n_future" "$n_seen" >&2
  [ "$n_nostat" -eq 0 ] || printf 'retro-prescreen: %s: %d of %d with an unreadable mtime — kept, cursor not advanced\n' \
    "$source" "$n_nostat" "$n_seen" >&2

  # --- S3 loopback egress gate + reachability probe (shared with artifacts) ---
  local stage2_allowed=0
  if [ "$healed_any" -eq 1 ]; then
    # A heal makes the whole corpus a candidate. Stage 2 sends each excerpt raw
    # to the backend, so widening the candidate set must not widen the
    # off-machine set with it. Declared residual: this DEFERS the widened
    # egress by one run rather than preventing it — the deferred emitter
    # persists the healed cursor, so the next run's Stage 2 sees the same
    # widened corpus with no heal to suppress it. Only the artifacts arm, which
    # has a usable non-egress mining mode, prevents it outright.
    echo "retro-prescreen: $source: a cursor was healed this run — Stage 2 skipped; the NEXT run will send the widened corpus to the configured backend" >&2
  elif _raw_llm_egress_ok "$allow_remote"; then
    stage2_allowed=1
  fi

  if [ "$stage2_allowed" -ne 1 ]; then
    # Fail-closed: counts only, no content, deferred=true. The cursor emitted is
    # the HEALED read-in value, never `max_hw` — Stage 1 above runs to
    # completion and fully advances `max_hw` BEFORE this gate is consulted, so
    # emitting it here would record every scanned transcript as mined on a run
    # that distilled nothing. The healed value is <= the persisted one by
    # construction, so it records no progress while still carrying the heal to
    # the state file.
    if [ "$as_json" -eq 1 ]; then
      jq -nc --arg s "$source" --argjson counts "$counts" --arg hw "$(_epoch_to_iso "$cursor")" \
        '{source: $s,
          candidates: ($counts | to_entries | map({index: (.key|tonumber), event_count: .value})),
          high_water: $hw, deferred: true}'
    else
      echo "transcripts: LLM unavailable or non-loopback — deferred (counts only, no content)"
      jq -r 'to_entries[] | "  - session " + .key + ": " + (.value|tostring) + " event(s)"' <<<"$counts"
    fi
    return 0
  fi

  # --- Stage 2: distillation + scrub ---
  local lessons='[]'
  local ev
  # Guarded expansion: with the pre-filter gone the whole corpus is enumerated
  # and, on a drained source, every file is suppressed — so an EMPTY excerpts
  # array is the steady state on a healthy system, not an edge case. A bare
  # "${excerpts[@]}" is an unbound-variable abort there on the bash 3.2 floor.
  for ev in ${excerpts[@]+"${excerpts[@]}"}; do
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

  _transcripts_emit "$as_json" "$source" "$lessons" "$max_hw" false "distilled lesson(s)"
}

# The single emitter for cmd_transcripts' non-deferred exits. Every one of them
# carries the cursor — the healed read-in value on the paths that mined nothing,
# the running maximum on the path that mined. Emitting `null` anywhere makes the
# orchestrator skip mark-run entirely, so `last_run` never advances and the
# source stays permanently due while a poisoned cursor survives the run that
# announced it.
_transcripts_emit() {
  local as_json="$1" source="$2" candidates="$3" cursor_epoch="$4" deferred="$5" label="$6"
  local iso
  iso=$(_epoch_to_iso "$cursor_epoch")
  if [ -z "$iso" ]; then
    printf 'retro-prescreen: %s: cursor %s is not representable — re-emitting %s\n' \
      "$source" "$cursor_epoch" "$EPOCH_FLOOR_ISO" >&2
    iso="$EPOCH_FLOOR_ISO"
  fi
  if [ "$as_json" -eq 1 ]; then
    jq -nc --arg s "$source" --argjson c "$candidates" --arg hw "$iso" --argjson d "$deferred" \
      '{source: $s, candidates: $c, high_water: $hw, deferred: $d}'
  else
    echo "transcripts: $(jq 'length' <<<"$candidates") $label"
    jq -r '.[] | "  - " + (. | tostring)' <<<"$candidates"
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

  # Seeded from the configured URLs BEFORE the loop, carrying each prior hash,
  # for the same reason cmd_artifacts and cmd_github are: retro-state.sh writes
  # `.high_water = $hw` as a WHOLE-OBJECT REPLACEMENT, so a URL missing from the
  # emitted map is DELETED from state and reported as changed on the next run
  # that reaches it. A fetch failure — one unreachable host — used to drop the
  # key, and a run where every fetch failed emitted `{}`, which _validate_hw
  # accepts trivially (both its loops iterate zero times) and which then wiped
  # every persisted hash. This is the third member of that class in this file.
  local candidates='[]' hw_map='{}'
  local url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    hw_map=$(jq -c --arg u "$url" --arg h "$(jq -r --arg u "$url" '.[$u] // ""' <<<"$prior_hw")" \
      '. + {($u): $h}' <<<"$hw_map")
  done <<<"$urls"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    local body hash prior
    body=$(curl -s --proto '=https' --proto-redir '=https' --max-time 30 \
      --max-filesize 5242880 --max-redirs 3 "$url" 2>/dev/null)
    if [ -z "$body" ]; then
      printf 'retro-prescreen: %s: no response for a configured URL — its hash is preserved\n' "$source" >&2
      continue
    fi
    hash=$(printf '%s' "$body" | sha256sum | awk '{print $1}')
    prior=$(jq -r --arg u "$url" '.[$u] // ""' <<<"$prior_hw")
    if [ "$hash" != "$prior" ]; then
      candidates=$(jq -c --arg u "$url" '. + [$u]' <<<"$candidates")
    fi
    hw_map=$(jq -c --arg u "$url" --arg h "$hash" '. + {($u): $h}' <<<"$hw_map")
  done <<<"$urls"

  if [ "$as_json" -eq 1 ]; then
    # null, never `{}` — an empty object passes _validate_hw and the whole-object
    # replacement then wipes every URL's hash in one write.
    jq -nc --arg s "$source" --argjson c "$candidates" --argjson hw "$hw_map" \
      '{source: $s, candidates: $c,
        high_water: (if ($hw | length) == 0 then null else $hw end),
        deferred: false}'
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
# `"$@"` with no positional parameters is the same unbound-variable class as
# an unguarded array on the bash 3.2 floor, and this sits on the dispatch path
# every mode reaches — including `scrub`, which the header names as the single
# shared redaction artifact.
for arg in ${@+"$@"}; do
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
