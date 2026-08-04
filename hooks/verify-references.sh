#!/bin/bash
# verify-references: Check file:line references in sub-agent output.
# Usage: echo "$output" | bash ~/.claude/hooks/verify-references.sh \
#          [--root <dir>] [--base <ref>] [--strict]
#
# Reads text on stdin, extracts path:line and path:line-line references,
# and reports which ones exist and which are stale. Zero Claude tokens.
#
# Output format (to stdout):
#   === Reference Verification ===
#   OK           path/to/file.ts:42
#   MISSING      path/to/gone.ts:10
#   OUT-OF-RANGE path/to/file.ts:9999 (file has 150 lines)
#   OUT-OF-ROOT  ../outside.txt:1
#   SHIFTED      path/to/file.ts:42 (line 42 differs from <base>; re-verify)
#   --- Summary: total=5, ok=1, issues=4, shifted=1 ---
#
# --base <ref>: a citation that EXISTS is not therefore still TRUE. Prose is
#   correct the moment it is written and rots when its subject moves, and
#   existence plus line-count are both blind to that: line 42 still being
#   present says nothing about whether line 42 is still the code the sentence
#   describes. With --base, a ref into a file this branch changed is re-read at
#   <ref> and reported SHIFTED when the cited line's text is no longer what it
#   was — the mechanical half of "re-verify every citation whose target you
#   edited". Unchanged files, and files that did not exist at <ref>, are cheap
#   no-ops, so the report fires on movement rather than on every edited file.
#   Semantics are BASE-relative: it answers "does this citation still point at
#   the same text it pointed at in <ref>", which is the question for a document
#   written early in a branch and re-read after later rounds edited its
#   subjects. A citation authored mid-branch against an intermediate state is
#   the false-positive direction — pass the ref it was written against.
#   Known blind spots, both fail-open: a RENAMED file is listed at its new path,
#   so `git show <ref>:<new path>` finds nothing and the ref reads as
#   "did not exist at base"; and only the START line of a range is compared, as
#   in the existence check above.
#
# --strict: exit 1 when any reference is an issue (the default exit is always 0,
#   because the original caller is an advisory post-pass over sub-agent text).
#   Gates that must be able to go red pass this.
#
# Security model:
#   stdin is UNTRUSTED (originates from sub-agent / LLM output, potentially
#   shaped by prompt-injection or hallucination). Path components are
#   canonicalized via realpath and must resolve inside ROOT — absolute paths
#   outside ROOT, `..`-traversal, and symlink escape are all rejected as
#   OUT-OF-ROOT. Without this containment the helper becomes an
#   existence/size oracle for any user-readable file.
#
# Exit 0 always (non-blocking helper).

set -euo pipefail

ROOT="."
BASE=""
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--root <dir>] [--base <ref>] [--strict]  (reads stdin)" >&2
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Canonicalize ROOT once. Missing ROOT is a configuration error, not a
# recoverable condition for a single ref — fail closed.
# `realpath -e` is GNU-only; macOS realpath rejects it outright, which made
# every ROOT look inaccessible. `cd -P && pwd -P` resolves symlinks on both
# and still fails when the directory is missing.
ROOT_ABS=$(cd -P -- "$ROOT" 2>/dev/null && pwd -P) || {
  echo "Error: ROOT '$ROOT' does not exist or is not accessible" >&2
  exit 1
}
# `pwd -P` returns "/" for the filesystem root, which would make the containment
# pattern below "//"* — matching nothing, so every path is refused including
# ones genuinely under ROOT. Empty it so the pattern reads "/"*. Over-refusal is
# the safe direction, but it is still wrong.
[ "$ROOT_ABS" = "/" ] && ROOT_ABS=""

# --base setup. Resolved once: a bad ref, or a ROOT outside any repository, is a
# configuration error for the whole run rather than a per-reference condition,
# and reporting every ref OK because the comparison silently never ran is the
# exact false-green this flag exists to remove (a gate that examined nothing and
# a gate that found nothing wrong print the same status otherwise).
REPO_TOP=""
CHANGED=""
NL=$'\n'
if [ -n "$BASE" ]; then
  if [ -z "$ROOT_ABS" ]; then
    echo "Error: --base needs a ROOT inside a repository, not the filesystem root" >&2
    exit 1
  fi
  # A leading dash would reach git as an OPTION rather than as the revision it
  # is meant to be. Refuse the shape outright instead of relying on each git
  # subcommand to reject it — `rev-parse` and `show` do not parse argv alike,
  # so "the validation call errored, therefore the value is safe" is a
  # conclusion about the wrong command.
  case "$BASE" in
    -*) echo "Error: --base must name a commit, not an option ('$BASE')" >&2; exit 1 ;;
  esac
  REPO_TOP=$(git -C "$ROOT_ABS" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: --base given but ROOT '$ROOT' is not inside a git repository" >&2
    exit 1
  }
  git -C "$REPO_TOP" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || {
    echo "Error: --base '$BASE' does not name a commit in $REPO_TOP" >&2
    exit 1
  }
  # Base-to-WORKTREE, not base-to-HEAD: the citing document is checked at the
  # moment the fixes land, and a fix that is still uncommitted has already moved
  # the line the prose points at.
  # core.quotePath=false because the membership test below is an exact string
  # match: with quoting on, a path holding a non-ASCII byte comes back wrapped in
  # quotes and escaped, matches nothing, and the ref is silently passed as OK —
  # a fail-open on exactly the paths a reader is least able to eyeball.
  CHANGED=$(git -C "$REPO_TOP" -c core.quotePath=false diff --name-only "$BASE" -- 2>/dev/null || true)
fi

INPUT=$(cat)
if [ -z "$INPUT" ]; then
  echo "=== Reference Verification ==="
  echo "--- Summary: total=0, ok=0, issues=0, shifted=0 ---"
  exit 0
fi

# Extract path:line refs.
#   Path may optionally begin with '/' (absolute). Line is a single number or
#   range (e.g., 42-51); only the start line is verified.
# Grep returns a stream of raw matches; we dedupe and sort afterward.
REFS=$(printf '%s' "$INPUT" \
  | grep -oE '(/?[A-Za-z0-9_.][A-Za-z0-9_./\-]*[A-Za-z0-9_]):[0-9]+(-[0-9]+)?' \
  | sort -u)

if [ -z "$REFS" ]; then
  echo "=== Reference Verification ==="
  echo "--- Summary: total=0, ok=0, issues=0, shifted=0 ---"
  exit 0
fi

TOTAL=0
OK_COUNT=0
ISSUE_COUNT=0
SHIFTED_COUNT=0
OUTPUT=""

while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  path="${ref%%:*}"
  linespec="${ref##*:}"
  start_line="${linespec%%-*}"

  # Skip refs whose path looks non-filesystem (e.g., 'http', 'localhost', bare words).
  # Heuristic: require a '/' (absolute or nested) OR a recognized file extension.
  if [[ "$path" != */* ]] && [[ ! "$path" =~ \.(ts|tsx|js|jsx|py|go|rs|sh|bash|md|json|yml|yaml|toml|rb|java|kt|c|h|cpp|hpp|cs|php|sql|bats)$ ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Resolve candidate path: absolute stays absolute; relative joins ROOT_ABS.
  # realpath -m resolves even when the final component does not exist, so we
  # can still classify MISSING while enforcing containment.
  if [[ "$path" = /* ]]; then
    candidate="$path"
  else
    candidate="$ROOT_ABS/$path"
  fi

  # `realpath -m` (resolve even when the last component is absent) is GNU-only.
  # Resolve the parent directory — which must exist for the file to be real —
  # and re-attach the basename, so a missing file still yields a canonical
  # path to run the containment check against.
  full_abs=$( d=$(cd -P -- "$(dirname -- "$candidate")" 2>/dev/null && pwd -P) \
              && printf '%s/%s' "$d" "$(basename -- "$candidate")" ) || full_abs=""
  # Parent-only resolution leaves a SYMLINK LEAF unresolved: a link inside ROOT
  # whose target is outside canonicalizes to its own in-ROOT path and passes
  # containment. Chase the ENTIRE chain, re-resolving the containing directory
  # at every hop — a single readlink only catches a one-hop escape, and two
  # links planted inside ROOT (A -> B, both inside -> target outside) slip past
  # it because A's immediate target still sits inside. Same shape and 40-hop cap
  # as `_containment_check` in retro-prescreen.sh, which closed this exact hole.
  # `cd -P` is the both-platform idiom used above (macOS realpath rejects the
  # GNU-only flags). A dangling link resolves the same way — only its target's
  # parent must exist — so one pointing outside ROOT reports OUT-OF-ROOT and one
  # inside falls through to MISSING below. No `--` on readlink: the argument is
  # always absolute (built from `pwd -P`), so it can never be read as an option,
  # and BSD readlink rejects `--`.
  hops=0
  while [ -n "$full_abs" ] && [ -L "$full_abs" ] && [ "$hops" -lt 40 ]; do
    link_target=$(readlink "$full_abs") || break
    [[ "$link_target" = /* ]] || link_target="$(dirname -- "$full_abs")/$link_target"
    resolved=$( d=$(cd -P -- "$(dirname -- "$link_target")" 2>/dev/null && pwd -P) \
                && printf '%s/%s' "$d" "$(basename -- "$link_target")" ) || resolved=""
    [ -z "$resolved" ] && break
    full_abs="$resolved"
    hops=$((hops + 1))
  done
  # Cap exhausted with a symlink still in hand: FAIL CLOSED. Leaving the
  # partially-resolved path is not safe, and the downstream existence check does
  # NOT save us — it only appears to for a cycle, which is dangling so `-f`
  # fails. When a chain longer than the cap ends at a REAL file outside ROOT,
  # the walk stops on an in-ROOT link, containment passes, and `-f`/`wc` let the
  # KERNEL follow the remaining hops to the outside file — our resolver stopping
  # does not stop the syscall. That reopens the size oracle, so the reference
  # must be refused outright.
  if [ -n "$full_abs" ] && [ -L "$full_abs" ] && [ "$hops" -ge 40 ]; then
    full_abs=""
  fi
  if [ -z "$full_abs" ]; then
    OUTPUT="${OUTPUT}MISSING      ${ref}
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  # Containment: canonical path must sit under ROOT_ABS. Catches directory
  # traversal (../), absolute-path escapes, and — given the chain resolution
  # above, at any depth up to the hop cap — symlink redirection, in a single
  # check.
  case "$full_abs/" in
    "$ROOT_ABS/"*) : ;;
    *)
      OUTPUT="${OUTPUT}OUT-OF-ROOT  ${ref}
"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
      continue
      ;;
  esac

  if [ ! -f "$full_abs" ]; then
    OUTPUT="${OUTPUT}MISSING      ${ref}
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  file_lines=$(wc -l < "$full_abs" 2>/dev/null | tr -d ' ')
  file_lines="${file_lines:-0}"

  if [ "$start_line" -gt "$file_lines" ]; then
    OUTPUT="${OUTPUT}OUT-OF-RANGE ${ref} (file has ${file_lines} lines)
"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    continue
  fi

  # The reference resolves. Whether it is still TRUE is a separate question, and
  # only --base can ask it.
  if [ -n "$BASE" ] && [ "$start_line" -ge 1 ]; then
    # Repo-root-relative, derived from the CANONICAL path — `git diff
    # --name-only` names paths from the repository root regardless of ROOT, and
    # the raw stdin spelling is untrusted besides. A path that canonicalizes
    # outside the repository (ROOT above the top level) has no base version to
    # compare and falls through to OK.
    rel=""
    case "$full_abs/" in
      "$REPO_TOP/"*) rel="${full_abs#"$REPO_TOP"/}" ;;
    esac
    # Cheap filter first: a file this branch never touched cannot have moved the
    # cited line, so it costs no `git show`.
    if [ -n "$rel" ] && case "$NL$CHANGED$NL" in *"$NL$rel$NL"*) true ;; *) false ;; esac; then
      if base_blob=$(git -C "$REPO_TOP" show "$BASE:$rel" 2>/dev/null); then
        base_line=$(printf '%s\n' "$base_blob" | sed -n "${start_line}p")
        cur_line=$(sed -n "${start_line}p" "$full_abs")
        if [ "$base_line" != "$cur_line" ]; then
          OUTPUT="${OUTPUT}SHIFTED      ${ref} (line ${start_line} differs from ${BASE}; re-verify)
"
          ISSUE_COUNT=$((ISSUE_COUNT + 1))
          SHIFTED_COUNT=$((SHIFTED_COUNT + 1))
          continue
        fi
      fi
      # `git show` failing means the path did not exist at BASE, so nothing it
      # once pointed at can have moved — not an issue.
    fi
  fi

  OUTPUT="${OUTPUT}OK           ${ref}
"
  OK_COUNT=$((OK_COUNT + 1))
done <<< "$REFS"

echo "=== Reference Verification ==="
printf '%s' "$OUTPUT"
echo "--- Summary: total=${TOTAL}, ok=${OK_COUNT}, issues=${ISSUE_COUNT}, shifted=${SHIFTED_COUNT} ---"

# Default exit stays 0 for the advisory caller. --strict is what makes this a
# gate rather than a report, and a gate that cannot return non-zero is one no
# caller can fail on.
if [ "$STRICT" -eq 1 ] && [ "$ISSUE_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
