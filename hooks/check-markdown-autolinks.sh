#!/bin/bash
# Detect bare Markdown autolink tokens that GitHub-flavored Markdown
# would auto-resolve to issue / PR / user / commit references.
#
# R30 (Markdown autolink footguns) fired 29 times in the passwd-sso
# survey. The classic shape: a PR body or doc edit references "tenet
# #6" or "see commit f4d4068" intending plain text, but GFM renders
# the bare `#6` as a link to issue/PR #6 and the SHA-shaped hex as a
# commit link. The unintended links create disclosure noise (watchers
# of #6 get notified about the new artifact) and confusion.
#
# Detection
#   For each `+` line in the diff that's inside a Markdown file:
#     1. `(^|[^a-zA-Z0-9_])#[0-9]+\b`        — bare issue/PR reference
#     2. `(^|[^a-zA-Z0-9_/])@[A-Za-z0-9-]+\b` — bare user mention
#     3. `(^|[^a-zA-Z0-9_])[0-9a-f]{7,40}\b` — commit-SHA-shaped hex
#   Skip when the same line uses backtick quoting (` `#6` `, ` `@name` `)
#   or escape (`\#6`, `\@name`) — heuristic: if there's a backtick
#   anywhere on the line, suppress, since users who care enough to
#   wrap one autolink-prone token usually wrap them all.
#
# Severity: Minor. R30 is a footgun, not a bug — the page still renders
# something; it's just the wrong link.
#
# Usage: bash check-markdown-autolinks.sh [base-ref]

set -u

_CMA_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CMA_TMPDIR'" EXIT

BASE_REF="${1:-main}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

# Markdown surfaces only — README / docs / changelog / templates.
MD_EXT_RE='\.md$|\.markdown$|/CHANGELOG$|/README$'

ADDED="$_CMA_TMPDIR/added.tsv"
git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
  | awk -v md_re="${MD_EXT_RE//\\/\\\\}" '
      /^\+\+\+ b\// {
        sub(/^\+\+\+ b\//, "")
        file = $0
        in_md = (file ~ md_re)
        next
      }
      /^\+\+\+ \/dev\/null/ { in_md = 0; next }
      /^@@/ {
        if (match($0, /\+[0-9]+/)) {
          lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
        }
        next
      }
      /^\+/ {
        if ($0 ~ /^\+\+\+/) next
        if (in_md) {
          content = substr($0, 2)
          if (content != "") print file "\t" lineno "\t" content
        }
        lineno++
      }
    ' > "$ADDED"

CHANGED_COUNT=$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null | wc -l)
MD_LINE_COUNT=$(wc -l < "$ADDED")

echo "=== Markdown Autolink Footgun Check (R30) ==="
echo "Base: $BASE_REF"
echo "Changed files: $CHANGED_COUNT  Markdown diff lines: $MD_LINE_COUNT"
echo ""

if [ "$MD_LINE_COUNT" -eq 0 ]; then
  echo "  (no markdown diff lines to inspect)"
  exit 0
fi

hits_emitted=0
echo "## Bare autolink-prone tokens"
echo ""

while IFS=$'\t' read -r file lineno content; do
  # Heuristic: if the line has any backticks, assume the user is using
  # them to escape autolink-prone tokens; suppress to reduce false
  # positives. Catches the common idiom `tenet \`#6\`` / `see \`f4d4068\``.
  if [[ "$content" == *'`'* ]]; then
    continue
  fi
  # Skip code-fence delimiters and indented code blocks.
  case "$content" in
    '```'*|'    '*|$'\t'*) continue ;;
  esac
  # Skip URL-only lines and Markdown links / images.
  if [[ "$content" =~ ^https?:// ]] || [[ "$content" =~ \[.*\]\(.*\) ]]; then
    : # has links — could still have bare tokens elsewhere; continue checks
  fi

  # 1. Bare #<number>
  if [[ "$content" =~ (^|[^a-zA-Z0-9_])#([0-9]+) ]]; then
    num="${BASH_REMATCH[2]}"
    printf '  [Minor] %s:%s — bare `#%s` will autolink to issue/PR #%s; wrap in backticks or escape with backslash\n' \
      "$file" "$lineno" "$num" "$num"
    hits_emitted=$((hits_emitted + 1))
  fi

  # 2. Bare @<handle>. Skip email addresses (handle preceded by alphanumeric).
  if [[ "$content" =~ (^|[^a-zA-Z0-9_/])@([A-Za-z0-9][A-Za-z0-9_-]+) ]]; then
    handle="${BASH_REMATCH[2]}"
    # Filter common false positives: @-decorators in code embedded in markdown
    # would be inside backticks — already filtered above. Still skip a few
    # known non-handles.
    case "$handle" in
      param|return|returns|throws|deprecated|see|since|version|author|todo|fixme) ;;
      *)
        printf '  [Minor] %s:%s — bare `@%s` will autolink as a GitHub user mention; wrap in backticks or rephrase\n' \
          "$file" "$lineno" "$handle"
        hits_emitted=$((hits_emitted + 1))
        ;;
    esac
  fi

  # 3. Commit-SHA-shaped hex (7-40 hex digits, bounded by non-word chars).
  # Skip if the hex is part of a longer identifier or a UUID segment.
  if [[ "$content" =~ (^|[^a-zA-Z0-9_])([0-9a-f]{7,40})($|[^a-zA-Z0-9_]) ]]; then
    sha="${BASH_REMATCH[2]}"
    # Filter: skip pure-numeric (years, version numbers) and obvious UUIDs.
    if [[ "$sha" =~ ^[0-9]+$ ]]; then
      :
    elif [[ "$content" =~ ${sha}-[0-9a-f]{4} ]]; then
      : # part of a UUID, not a SHA
    else
      printf '  [Minor] %s:%s — bare `%s` (SHA-shaped) will autolink as a commit reference; wrap in backticks\n' \
        "$file" "$lineno" "$sha"
      hits_emitted=$((hits_emitted + 1))
    fi
  fi
done < "$ADDED"

[ "$hits_emitted" -eq 0 ] && echo "  (no candidates found)"
echo ""
echo "=== End Markdown Autolink Check ==="
