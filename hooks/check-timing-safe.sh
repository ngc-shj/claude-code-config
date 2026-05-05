#!/bin/bash
# Detect non-constant-time comparisons of credential-shaped values.
#
# RS1 (Timing-safe comparison) fired 32 times in the passwd-sso review
# survey — credential / token / hash / signature compared with `===` or
# `!==` instead of a constant-time helper, leaking byte-by-byte timing
# information that a network-adjacent attacker can use to learn the
# secret one byte at a time. Manual review catches most cases; this
# hook automates the rest.
#
# Detection
#   For each `+` line in the diff:
#     1. Line contains an equality / inequality operator (`==` / `===` /
#        `!=` / `!==`).
#     2. ONE side of the operator is an identifier whose name matches a
#        credential-shape pattern (token / hash / secret / signature / ...).
#     3. The OTHER side is NOT a nullish / empty / numeric literal — those
#        are presence checks or length comparisons, not credential bytes.
#     4. The line does NOT already use a constant-time helper
#        (`timingSafeEqual`, `crypto.timingSafeEqual`, `hmac.compare_digest`,
#        `secrets.compare_digest`, `subtle.ConstantTimeCompare`, etc.).
#   When all four hold, emit a Critical finding.
#
# Severity: Critical. RS1 is a classic timing-attack vector — a wrong
# comparison turns the credential into a byte-oracle for any caller that
# can observe response timing.
#
# Out of scope (would need types or call-graph)
#   - Method calls returning a credential (`getToken() === expected`)
#     where the LHS is a function call, not an identifier.
#   - Comparison via library wrappers that shadow `===` semantics.
#
# Usage: bash check-timing-safe.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.

set -u

_CTS_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CTS_TMPDIR'" EXIT

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

# Identifier substrings that strongly suggest a credential / secret. Any
# token containing one of these as a word component is treated as
# credential-shaped. The set comes from the existing review history's
# usual flagged identifiers.
CRED_KEYWORD_RE='(token|secret|password|passwd|credential|signature|verifier|hmac|digest|fingerprint|cookie|nonce|salt|csrf|xsrf|jwt|apikey|bearer|otp|totp|hash)'

# Identifiers we want to exclude despite a substring match — these names
# exist for reasons unrelated to credential comparison and produce noise.
SKIP_NAME_RE='(hashCode|hashMap|hashSet|hashable|nonceStr|tokenize|tokenizer|tokenizers|tokenCount|tokensUsed|hashFunction|tokenizes|tokenLike|hashInfo|hashOnly|saltLen|saltLength|salt:|hash:|tokenization|tokenURI)'

# Constant-time-comparison helpers — when present on the line, the
# comparison is already correct; skip.
SAFE_HELPER_RE='(timingSafeEqual|timing_safe_compare|compare_digest|ConstantTimeCompare|constantTimeCompare|safeCompare|tsCompare)'

# Source-code whitelist (mirrors check-propagation.sh and friends).
SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|kts|scala|cs|fs|vb|swift|m|mm|c|h|hpp|hxx|cpp|cc|cxx|php|pl|pm|ex|exs|erl|hrl|elm|clj|cljs|cljc|edn|lua|sh|bash|zsh|fish|graphql|gql)$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/)|.+\.generated\.|.+_generated\.|.+\.gen\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

# Build the diff `+` line file with file:line:content.
ADDED="$_CTS_TMPDIR/added.tsv"
git diff "$BASE_REF...HEAD" --unified=0 2>/dev/null \
  | awk -v src_re="${SOURCE_EXT_RE//\\/\\\\}" -v exclude_re="${EXCLUDE_PATH_RE//\\/\\\\}" '
      /^\+\+\+ b\// {
        sub(/^\+\+\+ b\//, "")
        file = $0
        in_source = (file ~ src_re && file !~ exclude_re)
        next
      }
      /^\+\+\+ \/dev\/null/ { in_source = 0; next }
      /^@@/ {
        if (match($0, /\+[0-9]+/)) {
          lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
        }
        next
      }
      /^\+/ {
        # Skip the diff header itself.
        if ($0 ~ /^\+\+\+/) next
        # Increment lineno for EVERY `+` line (including empty ones); print
        # only when in_source AND content is non-empty.
        if (in_source) {
          content = substr($0, 2)
          if (content != "") print file "\t" lineno "\t" content
        }
        lineno++
      }
    ' > "$ADDED"

CHANGED_COUNT=$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null | wc -l)

echo "=== Timing-Safe Comparison Check (RS1) ==="
echo "Base: $BASE_REF"
echo "Changed files: $CHANGED_COUNT"
echo ""

if [ ! -s "$ADDED" ]; then
  echo "  (no source-file diff lines to inspect)"
  exit 0
fi

# Detection. The bash regex steps:
#   - Skip lines using a constant-time helper.
#   - Look for identifier...== or ==identifier patterns where the
#     identifier matches CRED_KEYWORD_RE and not SKIP_NAME_RE.
#   - Skip when the OTHER side is null / undefined / numeric / empty
#     string (not a credential-byte comparison).
hits_emitted=0
echo "## Candidate timing-attack-vulnerable comparisons"
echo ""

while IFS=$'\t' read -r file lineno content; do
  # Skip lines that already use a constant-time helper.
  if [[ "$content" =~ $SAFE_HELPER_RE ]]; then
    continue
  fi
  # Skip comment-only lines (line-doc, hash-comment, block-comment).
  trimmed="${content#"${content%%[![:space:]]*}"}"
  if [[ "$trimmed" =~ ^(//|#|/\*|\*[[:space:]/]) ]]; then
    continue
  fi
  # Quick gate: line must contain an equality operator.
  if ! [[ "$content" =~ (==|!=) ]]; then
    continue
  fi
  # Find a credential-shaped identifier. Scan word-bounded tokens.
  cred=""
  for tok in $(echo "$content" | grep -oE '\b[A-Za-z_][A-Za-z0-9_]*\b' | sort -u); do
    # Lowercase comparison to keep CRED_KEYWORD_RE simple.
    lower=$(echo "$tok" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" =~ $CRED_KEYWORD_RE ]] && ! [[ "$tok" =~ $SKIP_NAME_RE ]]; then
      cred="$tok"
      break
    fi
  done
  [ -z "$cred" ] && continue
  # Now confirm the credential identifier appears on either side of
  # an equality operator, and the other operand is NOT a nullish /
  # numeric / empty-string literal.
  cred_op_re="\\b${cred}\\b[[:space:]]*(===|!==|==|!=)[[:space:]]*([^=!&|;,) ]+)"
  op_cred_re="([^=!&|<>] |^)([^=!&|;,( ]+)[[:space:]]*(===|!==|==|!=)[[:space:]]*\\b${cred}\\b"
  other=""
  if [[ "$content" =~ $cred_op_re ]]; then
    other="${BASH_REMATCH[2]}"
  elif [[ "$content" =~ $op_cred_re ]]; then
    other="${BASH_REMATCH[2]}"
  fi
  [ -z "$other" ] && continue
  # Strip trailing punctuation that can leak into BASH_REMATCH.
  other=$(echo "$other" | sed -E 's/[);,]$//; s/^[(]+//')
  # Skip nullish / numeric / empty-string / boolean comparisons.
  case "$other" in
    null|undefined|None|nil|true|false|True|False|''|'""'|"''"|0) continue ;;
    [0-9]*) continue ;;
  esac
  # Skip when both sides are credential-shaped (test fixtures comparing
  # two stored hashes against each other in non-security contexts).
  lower_other=$(echo "$other" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower_other" =~ $CRED_KEYWORD_RE ]] && ! [[ "$other" =~ $SKIP_NAME_RE ]]; then
    : # both sides credential-shaped; still likely a comparison worth flagging
  fi
  # Suppress when the same line is clearly a length / size check
  # (e.g., `token.length === 32`, `len(hash) == 64`). Regex stored in a
  # variable so bash's quote processing doesn't mangle the backslashes.
  _len_re='\.length[[:space:]]*(===|!==|==|!=)'
  _lenfn_re='^[[:space:]]*len\('
  if [[ "$content" =~ $_len_re ]] || [[ "$content" =~ $_lenfn_re ]]; then
    continue
  fi
  printf '  [Critical] %s:%s — `%s` compared with non-constant-time operator (use timingSafeEqual / compare_digest / equivalent)\n' \
    "$file" "$lineno" "$cred"
  hits_emitted=$((hits_emitted + 1))
done < "$ADDED"

[ "$hits_emitted" -eq 0 ] && echo "  (no candidates found)"
echo ""
echo "=== End Timing-Safe Comparison Check ==="
