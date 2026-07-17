#!/bin/bash
# PreToolUse hook: gate `git push` / `gh pr create` on the project's
# pre-PR script.
#
# Rationale: the /triangulate skill runs lint / test / build explicitly,
# but a project's `scripts/pre-pr.sh` often bundles repo-specific gates
# beyond that (forbidden-pattern greps, count checks, license-header
# validation, etc.). When the skill skips this script, CI-only failures
# leak through to push round and cost an iteration.
#
# Behavior:
#   - Fires only on Bash commands matching `git push` or `gh pr create`.
#   - Locates the project root via $CLAUDE_PROJECT_DIR (set by the harness),
#     falling back to `git rev-parse --show-toplevel` only when the env
#     var is unset. Falling back to git-cwd alone is a fail-open hole
#     when the user has `cd`'d into a non-repo directory before push.
#   - When `<repo>/scripts/pre-pr.sh` exists and is executable, runs the
#     script from the repo root.
#   - Pass: approve.
#   - Fail: block with the captured output (tail-limited) in the reason.
#   - No script present: approve (no-op for projects without the convention).
#
# Pass-cache (OPT-IN): a successful run's source-state fingerprint is
# recorded to a file inside the repo's git dir. A later invocation against
# a byte-identical state within TTL skips re-running the script entirely
# (stderr breadcrumb explains the skip). This is what lets the /triangulate
# skill's direct `run`-mode invocation, `git push`, and `gh pr create`
# collapse into a single execution when nothing changed between them.
#   - OPT-IN (external security review, 2026-07-17): an arbitrary
#     scripts/pre-pr.sh may read inputs the tree fingerprint cannot see
#     (ignored files like .env / generated gate state, dependencies,
#     environment). Caching is therefore OFF by default; it activates only
#     when (a) PRE_PR_CACHE_TTL is exported as a positive integer, or
#     (b) the project declares its extra gate inputs — a
#     `scripts/pre-pr.cache-paths` file (one repo-relative path per line;
#     may name ignored files; empty = "gate reads tree only") or an
#     exported PRE_PR_CACHE_EXTRA_PATHS (newline-separated, same format)
#     — which enables the default TTL 3600. Opting in asserts the gate's
#     inputs are covered by tree + declared extras.
#   - Fingerprint = sha256 over HEAD sha + one type-tagged line per path
#     (every tracked path, every untracked non-ignored path, every
#     declared extra path): regular files contribute exec-bit + REAL
#     worktree byte hash (never git's clean/textconv-filtered view, which
#     can hide worktree changes), symlinks contribute their target string
#     WITHOUT being followed (a hostile symlink to /dev/zero cannot hang
#     the hook), fifo/socket/device contribute a type marker, missing
#     paths a deletion marker. Regular files above
#     PRE_PR_CACHE_MAX_FILE_BYTES (default 100 MiB) abort fingerprinting.
#     Any failure yields no fingerprint, which is always treated as a
#     cache miss (full run) — the cache can only narrow the gate, never
#     widen it.
#   - Cache file: `$(git rev-parse --absolute-git-dir)/claude-pre-pr-pass`,
#     one line `<sha256-hex> <epoch-seconds>`, written atomically
#     (mktemp in the same dir + mv). Only trusted (regular, non-symlink,
#     owned by the current user) cache files are honored.
#   - PRE_PR_CACHE_TTL (seconds): freshness window when opted in.
#     Effective TTL is capped at 86400 (24h). TTL=0 disables both skip
#     and record. A malformed value is treated as unset (stderr note) and
#     falls back to the declaration-dependent default.
#   - Recording only happens when the fingerprint computed AFTER a passing
#     run equals the one computed BEFORE it (mutation guard) — pre-pr
#     scripts that run formatters/codegen and leave the tree different are
#     never cached, since the mutated tree itself was never validated.
#   - `check-pre-pr.sh run`: a direct-invocation entry point (used by the
#     /triangulate skill) that resolves the repo root the same way as hook
#     mode, participates in the same cache, and streams scripts/pre-pr.sh's
#     stdout/stderr straight through with no pipe or capture, exiting with
#     the script's own status (R44 exit-status integrity).
#
# Escape hatches:
#   - Set `SKIP_PRE_PR_GATE=1` in the env to bypass for a single session.
#     A stderr breadcrumb fires on every bypass so the operator notices an
#     accidentally-persistent export (e.g., in ~/.bashrc). Checked ahead of
#     all cache logic in both entry modes.
#   - `PRE_PR_CACHE_TTL=0` forces a run even against an identical tree.
#   - Disable globally by removing the hook entry from settings.json.
#
# Intentionally NOT gated:
#   - `git push --force` / `-f` family — already denied earlier by
#     block-vcs-history-rewrite.sh + permissions.deny.
#   - `git push --force-with-lease` / `--force-if-includes` — these still
#     push and DO trigger this gate (the safer-alternative semantics do
#     not exempt them from pre-PR validation).
#
# Timeout: registered at 1800s in settings.json. The hook itself has no
# internal timeout — pre-pr.sh aggregate scripts routinely run for minutes
# (full lint + test + build + repo-specific gates). 1800s is sized for
# the worst-case full run on a slow machine; a hung script (interactive
# prompt slipped past </dev/null, network stall) will still wait the full
# budget. If your project's pre-pr.sh is short, this is overhead-free.
#
# Secrets warning: combined stdout+stderr of pre-pr.sh is captured into
# the block reason that appears in the Claude Code conversation
# transcript. Authors of scripts/pre-pr.sh MUST avoid `set -x`, `env`
# dumps, and echoing secret-bearing tokens on failure paths — the
# transcript may be shared via /bug reports or session exports.

set -euo pipefail

# --- shared: fingerprint + cache (used by both hook mode and `run` mode) ---

# _cache_max_file_bytes -> stdout: per-file size cap for fingerprint
# hashing. A regular file above the cap aborts fingerprinting (no
# fingerprint -> full run), bounding worst-case hook latency against huge
# build artifacts. Env override exists primarily as a test seam.
_cache_max_file_bytes() {
  local raw="${PRE_PR_CACHE_MAX_FILE_BYTES:-104857600}"
  [[ "$raw" =~ ^[0-9]+$ ]] || raw=104857600
  printf '%s' "$((10#$raw))"
}

# _hash_path <./path>
# Emit one type-tagged fingerprint line for a path, lstat-first: symlinks
# are NEVER followed (their target STRING is the content — a hostile
# symlink to /dev/zero must not hang the hook), non-regular non-symlink
# entries (fifo/socket/device) contribute a type marker and are never
# opened, and a missing path (tracked-but-deleted, or a declared extra
# that does not exist) contributes a deletion marker so its
# appearance/disappearance changes the fingerprint. Regular files
# contribute exec-bit + content hash. Paths are `./`-prefixed by the
# caller: a bare dash-prefixed name (`--help`) would be parsed as a
# sha256sum option and a file literally named `-` would be read as stdin —
# either way that content would silently drop out of the fingerprint.
_hash_path() {
  local p="$1" target size xbit
  if [ -L "$p" ]; then
    target=$(readlink -- "$p") || return 1
    printf 'L %s\t%s\n' "$p" "$target"
  elif [ -f "$p" ]; then
    size=$(wc -c <"$p" 2>/dev/null) || return 1
    [ "$size" -le "$(_cache_max_file_bytes)" ] || return 1
    xbit='-'
    [ -x "$p" ] && xbit='x'
    { printf 'F %s ' "$xbit" && sha256sum -- "$p"; } || return 1
  elif [ ! -e "$p" ]; then
    printf 'D %s\n' "$p"
  else
    printf 'O %s\n' "$p"
  fi
}

# _declared_extra_paths_z <repo_root>
# Emit declared extra fingerprint inputs, NUL-separated. Sources:
#   - <repo_root>/scripts/pre-pr.cache-paths — one repo-relative path per
#     line; blank lines and #-comments skipped. May name IGNORED files
#     (.env, generated state, scanner DBs) — that is the point: the
#     project declares what its pre-PR gate reads beyond the tree.
#   - PRE_PR_CACHE_EXTRA_PATHS env — newline-separated, same format.
# Declarations are same-trust as scripts/pre-pr.sh itself (repo content /
# operator env); they add fingerprint inputs, never remove any.
_declared_extra_paths_z() {
  local repo_root="$1" line
  {
    if [ -f "$repo_root/scripts/pre-pr.cache-paths" ]; then
      cat "$repo_root/scripts/pre-pr.cache-paths"
      printf '\n'
    fi
    if [ -n "${PRE_PR_CACHE_EXTRA_PATHS:-}" ]; then
      printf '%s\n' "$PRE_PR_CACHE_EXTRA_PATHS"
    fi
  } 2>/dev/null | while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    printf '%s\0' "$line"
  done
  return 0
}

# _cache_declared <repo_root>
# Exit 0 iff the project or operator declared cache inputs. Setting
# PRE_PR_CACHE_EXTRA_PATHS to the empty string, or shipping an empty
# scripts/pre-pr.cache-paths, is a valid declaration meaning "my pre-PR
# gate reads nothing beyond the tracked + untracked tree".
_cache_declared() {
  local repo_root="$1"
  [ -n "${PRE_PR_CACHE_EXTRA_PATHS+x}" ] && return 0
  [ -f "$repo_root/scripts/pre-pr.cache-paths" ] && return 0
  return 1
}

# compute_fingerprint <repo_root>
# stdout: 64-char lowercase hex sha256 on success; empty + non-zero exit on
# any failure (not a repo, unborn HEAD, unreadable/oversized file, etc).
# Callers MUST guard the call (`fp=$(compute_fingerprint "$ROOT") || fp=""`)
# since this runs under `set -euo pipefail`.
#
# Real-content fingerprint (external security review, 2026-07-17): `git
# diff` output passes through .gitattributes clean/textconv filters, which
# can hide worktree changes the filters normalize away — while pre-pr.sh
# reads the REAL worktree bytes. Tracked paths are therefore hashed from
# their actual worktree state (bytes + exec bit + type + symlink target),
# never from git's filtered view. Inputs: HEAD sha, every tracked path,
# every untracked non-ignored path, every declared extra path.
compute_fingerprint() {
  local repo_root="$1" head_sha listing
  head_sha=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) || return 1
  # The hashing loop runs with cwd = repo_root regardless of the caller's
  # own cwd (I1-2: output depends only on repo content). sort -zu merges
  # the three NUL-separated sources deterministically and drops duplicate
  # paths (a declared extra that is also tracked hashes once).
  listing=$(
    { git -C "$repo_root" ls-files -z 2>/dev/null \
        && git -C "$repo_root" ls-files --others --exclude-standard -z 2>/dev/null \
        && _declared_extra_paths_z "$repo_root"; } \
      | LC_ALL=C sort -zu \
      | (cd "$repo_root" && while IFS= read -r -d '' f; do
          _hash_path "./$f" || exit 1
        done)
  ) || return 1
  printf '%s\n%s' "$head_sha" "$listing" | sha256sum | awk '{print $1}'
}

# cache_path <repo_root>
# stdout: absolute path to the cache file inside the worktree's git dir;
# non-zero exit when the git dir cannot be resolved.
cache_path() {
  local repo_root="$1" git_dir
  git_dir=$(git -C "$repo_root" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/claude-pre-pr-pass' "$git_dir"
}

# _cache_ttl <repo_root> -> stdout: effective TTL (base-10 normalized,
# capped at 86400).
#
# Opt-in model (external security review, 2026-07-17): an arbitrary
# scripts/pre-pr.sh may read inputs the tree fingerprint cannot see —
# ignored files (.env, generated gate state, scanner DBs), installed
# dependencies, environment. Caching therefore activates only on explicit
# opt-in:
#   - PRE_PR_CACHE_TTL set to a positive integer (operator opt-in), or
#   - a declaration exists (scripts/pre-pr.cache-paths file or exported
#     PRE_PR_CACHE_EXTRA_PATHS, possibly empty) -> default 3600.
# Otherwise TTL is 0 and the gate always runs. Opting in asserts the
# gate's inputs are covered by tree + declared extras. Malformed
# PRE_PR_CACHE_TTL is treated as unset (stderr note), which falls back to
# the declaration-dependent default — never a wider window than intended.
_cache_ttl() {
  local repo_root="$1" raw="${PRE_PR_CACHE_TTL:-}" ttl=''
  if [ -n "$raw" ]; then
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      # Base-10 normalize immediately: the regex accepts leading zeros
      # (e.g. "08"), which bash treats as invalid base-8 literals in
      # arithmetic/[[ ]] contexts and would abort the hook under `set -e`.
      ttl=$((10#$raw))
    else
      printf 'check-pre-pr: PRE_PR_CACHE_TTL='\''%s'\'' is not a non-negative integer; treating as unset\n' "$raw" >&2
    fi
  fi
  if [ -z "$ttl" ]; then
    if _cache_declared "$repo_root"; then
      ttl=3600
    else
      ttl=0
    fi
  fi
  if [ "$ttl" -gt 86400 ]; then
    ttl=86400
  fi
  printf '%s' "$ttl"
}

# cache_fresh <repo_root> <fingerprint>
# Exit 0 iff a trusted cache entry matches the fingerprint and its age is
# within TTL; exit 1 otherwise (missing, malformed, symlink, foreign-owned,
# mismatched, expired, future-dated, or TTL=0). On success, exports the
# validated age in CACHE_HIT_AGE so callers never re-read the cache file
# (a second read could race a concurrent replace and feed non-numeric data
# into arithmetic, crashing the hook under `set -e`).
CACHE_HIT_AGE=""
cache_fresh() {
  local repo_root="$1" fingerprint="$2" path ttl now line entry_fp entry_stamp age

  ttl=$(_cache_ttl "$repo_root")
  [ "$ttl" -gt 0 ] || return 1

  path=$(cache_path "$repo_root") || return 1
  [ -f "$path" ] || return 1
  [ -L "$path" ] && return 1
  [ -O "$path" ] || return 1

  line=$(head -n 1 "$path" 2>/dev/null) || return 1
  [[ "$line" =~ ^[0-9a-f]{64}\ [0-9]+$ ]] || return 1
  entry_fp="${line%% *}"
  entry_stamp="${line#* }"
  [ "$entry_fp" = "$fingerprint" ] || return 1

  now=$(date +%s)
  [ "$entry_stamp" -le "$now" ] || return 1
  age=$((now - entry_stamp))
  [ "$age" -le "$ttl" ] || return 1

  CACHE_HIT_AGE="$age"
  return 0
}

# cache_record <repo_root> <fingerprint>
# Best-effort atomic write of `<fingerprint> <now>`; any failure is a
# silent no-op (recording is an optimization, never allowed to crash the
# hook). No-op when TTL=0.
cache_record() {
  local repo_root="$1" fingerprint="$2" path dir tmp ttl
  ttl=$(_cache_ttl "$repo_root") || return 0
  [ "$ttl" -gt 0 ] || return 0
  path=$(cache_path "$repo_root" 2>/dev/null) || return 0
  dir=$(dirname "$path") || return 0
  tmp=$(mktemp "$dir/.claude-pre-pr-pass.XXXXXX" 2>/dev/null) || return 0
  if ! printf '%s %s\n' "$fingerprint" "$(date +%s)" >"$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi
  mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  return 0
}

# cache_breadcrumb <age>
# Shared stderr note emitted on every skip (hook mode and run mode).
cache_breadcrumb() {
  printf 'check-pre-pr: scripts/pre-pr.sh already passed for identical source state (%ss ago; PRE_PR_CACHE_TTL=0 to force) — skipping\n' "$1" >&2
}

# --- direct mode: `check-pre-pr.sh run` ---

run_direct() {
  if [ "${SKIP_PRE_PR_GATE:-0}" = "1" ]; then
    printf 'check-pre-pr: SKIP_PRE_PR_GATE=1 — bypassing scripts/pre-pr.sh gate\n' >&2
    exit 0
  fi

  local repo_root
  repo_root="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$repo_root" ]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  fi
  if [ -z "$repo_root" ]; then
    printf 'check-pre-pr: could not resolve repo root — gate not run\n' >&2
    exit 2
  fi

  local script="$repo_root/scripts/pre-pr.sh"
  if [ ! -x "$script" ]; then
    printf 'check-pre-pr: no scripts/pre-pr.sh at %s — nothing to run\n' "$script" >&2
    exit 0
  fi

  # Skip the (whole-tree) fingerprint computation entirely when caching is
  # not opted in — the default-off path must add no per-push cost.
  local fp_pre=""
  if [ "$(_cache_ttl "$repo_root")" -gt 0 ]; then
    fp_pre=$(compute_fingerprint "$repo_root") || fp_pre=""
  fi
  if [ -n "$fp_pre" ] && cache_fresh "$repo_root" "$fp_pre"; then
    cache_breadcrumb "$CACHE_HIT_AGE"
    exit 0
  fi

  # Guarded `if` so a failing script does not trip `set -e` before the
  # explicit status handling below — the wrapper's exit status must be the
  # script's own via the deliberate `exit "$status"` path, not an errexit
  # side effect.
  local status=0
  if (cd "$repo_root" && bash "$script" </dev/null); then
    status=0
  else
    status=$?
  fi

  if [ "$status" -eq 0 ]; then
    # Guarded so nothing here can alter the exit status or crash the
    # wrapper under `set -euo pipefail` — e.g. the script deleting `.git`
    # during its own run must still yield the script's exit 0 (T16).
    local fp_post=""
    fp_post=$(compute_fingerprint "$repo_root" 2>/dev/null) || fp_post=""
    if [ -n "$fp_pre" ] && [ -n "$fp_post" ] && [ "$fp_pre" = "$fp_post" ]; then
      cache_record "$repo_root" "$fp_post" || true
    fi
  fi

  exit "$status"
}

if [ "${1:-}" = "run" ] && [ $# -eq 1 ]; then
  run_direct
  # run_direct always exits; nothing reaches here.
elif [ $# -gt 0 ]; then
  # Covers unknown first args AND `run <extra-arg>` — C4's signature is
  # `run` with no other arguments; silently discarding extras would hide
  # caller mistakes behind a normal-looking exit 0.
  printf 'Usage: check-pre-pr.sh [run]\n' >&2
  exit 2
fi

# --- hook mode: default, stdin = PreToolUse JSON ---

INPUT=$(cat)

# Fail-open on malformed JSON: a hook that crashes (non-zero exit, no
# stdout) would otherwise block all Bash tool calls with a generic
# harness error. Approving on parse failure trades correctness for
# availability — the hook is a safety net, not the primary gate.
if ! PARSED=$(echo "$INPUT" | jq -rj '(.tool_name // ""), "", (.tool_input.command // "")' 2>/dev/null); then
  echo '{"decision": "approve"}'
  exit 0
fi
TOOL_NAME="${PARSED%%$'\x1f'*}"
COMMAND="${PARSED#*$'\x1f'}"

if [ "$TOOL_NAME" != "Bash" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

if [ -z "$COMMAND" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

if [ "${SKIP_PRE_PR_GATE:-0}" = "1" ]; then
  printf 'check-pre-pr: SKIP_PRE_PR_GATE=1 — bypassing scripts/pre-pr.sh gate\n' >&2
  echo '{"decision": "approve"}'
  exit 0
fi

# Detect push / PR-create verbs. Substring match against the full command
# catches `bash -c '...'` wrappers and `rtk git push ...` rewrites too.
# Boundaries use [^a-zA-Z0-9_-] (NOT just whitespace) so common shell
# separators like `;`, `|`, `&`, `(`, `)`, `<`, `>` are recognized as
# verb-edge — `git push;echo done` and `(git push)` are caught.
# Trailing-word-char exclusion preserves the `git pushd` false-positive
# avoidance (next char `d` is a word char, no match).
PUSH_REGEX='(^|[^a-zA-Z0-9_-])git[[:space:]]+push($|[^a-zA-Z0-9_-])|(^|[^a-zA-Z0-9_-])gh[[:space:]]+pr[[:space:]]+create($|[^a-zA-Z0-9_-])'

if ! echo "$COMMAND" | grep -qE "$PUSH_REGEX"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Prefer $CLAUDE_PROJECT_DIR (set by the harness to the session's project
# root) over git-cwd discovery. The git-rev-parse fallback alone would
# fail open when the user has `cd`'d into a non-repo directory before
# push — exactly the scenario where the gate matters most.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
if [ -z "$REPO_ROOT" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

SCRIPT="$REPO_ROOT/scripts/pre-pr.sh"
# `-x` (exists AND executable) matches the contract documented in the
# /triangulate skill phase docs. Projects shipping pre-pr.sh without an
# exec bit must `chmod +x` it; this is a one-time fix and avoids the
# "looks present but silently skipped" ambiguity of `-r`.
if [ ! -x "$SCRIPT" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Skip the (whole-tree) fingerprint computation entirely when caching is
# not opted in — the default-off path must add no per-push cost.
FP_PRE=""
if [ "$(_cache_ttl "$REPO_ROOT")" -gt 0 ]; then
  FP_PRE=$(compute_fingerprint "$REPO_ROOT") || FP_PRE=""
fi
if [ -n "$FP_PRE" ] && cache_fresh "$REPO_ROOT" "$FP_PRE"; then
  cache_breadcrumb "$CACHE_HIT_AGE"
  echo '{"decision": "approve"}'
  exit 0
fi

# Run the script with stdin closed to prevent interactive prompts from
# hanging the hook. Capture combined stdout+stderr for the block reason.
OUTPUT_FILE=$(mktemp -t pre-pr-gate.XXXXXX)
trap 'rm -f "$OUTPUT_FILE"' EXIT

if (cd "$REPO_ROOT" && bash "$SCRIPT" </dev/null) >"$OUTPUT_FILE" 2>&1; then
  FP_POST=$(compute_fingerprint "$REPO_ROOT") || FP_POST=""
  if [ -n "$FP_PRE" ] && [ -n "$FP_POST" ] && [ "$FP_PRE" = "$FP_POST" ]; then
    cache_record "$REPO_ROOT" "$FP_POST" || true
  fi
  echo '{"decision": "approve"}'
  exit 0
fi

# Tail-limit the captured output so the block reason stays readable.
TAIL_BYTES=4000
SIZE=$(wc -c <"$OUTPUT_FILE")
if [ "$SIZE" -gt "$TAIL_BYTES" ]; then
  # Use basename only in the user-visible note so the transcript does
  # not leak $TMPDIR layout (e.g., /var/folders/.../<username>/...).
  TRUNC_NOTE="(output truncated to last $TAIL_BYTES bytes; full log preserved in \$TMPDIR/$(basename "$OUTPUT_FILE"))"
  TAIL=$(tail -c "$TAIL_BYTES" "$OUTPUT_FILE")
  # Preserve the temp file for inspection on failure.
  trap - EXIT
else
  TRUNC_NOTE=""
  TAIL=$(cat "$OUTPUT_FILE")
fi

REASON=$(printf 'scripts/pre-pr.sh failed (exit non-zero) — push/PR blocked.\nFix the failures below and retry. To bypass for one session: export SKIP_PRE_PR_GATE=1\n%s\n--- pre-pr.sh output ---\n%s' "$TRUNC_NOTE" "$TAIL")
printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$REASON" | jq -Rs .)"
exit 0
