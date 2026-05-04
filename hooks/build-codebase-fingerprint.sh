#!/bin/bash
# Build a usage-frequency fingerprint of the codebase.
# Output: top-N high-frequency numeric literals (R2 candidates) + exported
# symbols by file-usage count (R1 candidates).
#
# Use case: pre-filter so reviewers/implementers see "this is established,
# reuse it" instead of grepping per-PR. Complements scan-shared-utils.sh,
# which gives a structural inventory without frequency ranking.
#
# No LLM required — pure grep / awk / sort.
# Prototype scope: TS/JS/TSX/JSX/MJS only. Extend per-language later.
#
# Usage: bash build-codebase-fingerprint.sh [project-root]
# Env knobs:
#   TOP_N (default: 30)              — max rows per section
#   LITERAL_MIN_FILES (default: 3)   — literal must appear in >= N files
#   SYMBOL_MIN_USAGE  (default: 3)   — symbol must be referenced from >= N files

# -e and pipefail intentionally OFF: data-collection pipelines use grep
# (returns 1 on no-match) and head (SIGPIPEs the producer); both are
# expected and harmless. We use -u to catch unset-var bugs.
set -u

# --- Trusted root resolution (same pattern as scan-shared-utils.sh) ---
TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRUSTED_ROOT=$(realpath -e -- "$TRUSTED_ROOT" 2>/dev/null || echo "$TRUSTED_ROOT")

if [ -n "${1:-}" ]; then
  ROOT_ABS=$(realpath -e -- "$1" 2>/dev/null) || {
    echo "Error: path '$1' does not exist or is not accessible" >&2
    exit 1
  }
  case "$ROOT_ABS/" in
    "$TRUSTED_ROOT/"*) ;;
    *)
      echo "Error: path '$1' is outside TRUSTED_ROOT='$TRUSTED_ROOT'" >&2
      exit 1
      ;;
  esac
  ROOT="$ROOT_ABS"
else
  ROOT="$TRUSTED_ROOT"
fi
cd "$ROOT"

TOP_N="${TOP_N:-30}"
LITERAL_MIN_FILES="${LITERAL_MIN_FILES:-3}"
SYMBOL_MIN_USAGE="${SYMBOL_MIN_USAGE:-3}"

EXCLUDE_DIRS_RE='(/node_modules/|/\.next/|/\.git/|/dist/|/build/|/target/|/__pycache__/|/\.tox/|/\.venv/|/venv/|/vendor/|/coverage/|/out/|/load-test/|/load-tests/|/perf-tests?/|/e2e/|/cypress/|/playwright/)'
TEST_FILE_RE='(\.test\.|\.spec\.|/__tests__/|/test/|/tests/|/fixtures/|\.fixture\.|\.stories\.|\.e2e\.)'

# Symbols that pattern-match as exports but should not be ranked as shared
# helpers — typically framework-conventional per-file exports (e.g., Next.js
# App Router HTTP method handlers in route.ts) or single-letter aliases.
SYMBOL_DENYLIST_RE='^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|default|metadata|generateMetadata|generateStaticParams|loader|action|config|runtime|dynamic|revalidate|fetchCache|preferredRegion|maxDuration)$'
SYMBOL_MIN_LENGTH=2

list_source_files() {
  # Excludes test files, build/dep dirs, and *.d.ts type-declaration files
  # (the latter only carry type exports, not real implementations — including
  # them inflates "X is exported / shared" counts with namespace declarations
  # that have no runtime presence).
  find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \) 2>/dev/null \
    | grep -vE "$EXCLUDE_DIRS_RE" \
    | grep -vE "$TEST_FILE_RE" \
    | grep -vE '\.d\.ts$' \
    || true
}

# --- 1. Numeric literal frequency ---
# Per file: extract integers >=2 digits, deduplicate within file, then count
# files per value. Per-file dedup keeps a single file from inflating the count.

is_noise_numeric() {
  local n="$1"
  # Leading-zero values typically come from date/time string fragments,
  # zero-padded counters, or octal-looking literals — all noise for R2.
  case "$n" in
    0[0-9]*) return 0 ;;
  esac
  case "$n" in
    # HTTP status codes (common subset)
    200|201|202|204|301|302|303|304|307|308) return 0 ;;
    400|401|402|403|404|405|406|409|410|412|413|415|418|422|423|425|429|431|451) return 0 ;;
    500|501|502|503|504|505|511) return 0 ;;
    # Years 1900-2099
    19[0-9][0-9]|20[0-9][0-9]) return 0 ;;
    # Powers of 10
    10|100|1000|10000|100000|1000000) return 0 ;;
    # Common UI sizes (px / Tailwind scale)
    12|16|20|24|32|40|48|56|64|80|96|128|256|512) return 0 ;;
    # Common percent-ish or angle values
    50|90|180|270|360) return 0 ;;
  esac
  return 1
}

is_noise_string() {
  local s="$1"
  # Path-like prefixes (import paths, relative/absolute paths, URL schemes)
  case "$s" in
    ./*|../*|/*|@/*|~/*) return 0 ;;
    http://*|https://*|file://*|data:*|blob:*|mailto:*) return 0 ;;
  esac
  # Module-system directives that legitimately repeat per-file
  case "$s" in
    "use client"|"use server"|"use strict") return 0 ;;
  esac
  # CSS utility-class noise (Tailwind / similar atomic-CSS frameworks):
  # these are R8 (UI consistency) territory, not R2 (constants), and they
  # otherwise dominate the top of the section.
  #
  # Two filters:
  # (i)  Multi-token, all-lowercase clusters (e.g. "flex items-center gap-2").
  # (ii) Single-token strings starting with a known Tailwind utility prefix
  #      AND containing no uppercase (so e.g. "Content-Type" survives). We
  #      gate on no-uppercase to keep real lowercase domain strings like
  #      `passwd-sso`, `no-store`, `utf-8` from being swept up — those don't
  #      match any Tailwind prefix.
  case "$s" in
    *' '*)
      local _tw_re='^[a-z][a-z0-9. /:-]*$'
      if [[ "$s" =~ $_tw_re ]]; then
        return 0
      fi
      ;;
    *[A-Z_]*) ;;
    space-*|gap-*|gap-x-*|gap-y-*|text-*|bg-*|border-*|rounded*|shadow*|font-*|leading-*|tracking-*|whitespace-*|\
    w-*|h-*|min-w-*|min-h-*|max-w-*|max-h-*|size-*|\
    m-*|mx-*|my-*|mt-*|mb-*|ml-*|mr-*|\
    p-*|px-*|py-*|pt-*|pb-*|pl-*|pr-*|\
    flex|flex-*|grid|grid-*|inline-*|block|hidden|invisible|visible|\
    items-*|justify-*|self-*|place-*|content-*|order-*|\
    overflow-*|truncate|opacity-*|z-*|cursor-*|select-*|pointer-events-*|\
    transition*|duration-*|ease-*|delay-*|animate-*|\
    transform|translate-*|rotate-*|scale-*|skew-*|origin-*|\
    absolute|relative|fixed|sticky|static|\
    top-*|bottom-*|left-*|right-*|inset-*|\
    ring-*|outline-*|divide-*|\
    fill-*|stroke-*|aspect-*|object-*|backdrop-*|\
    shrink-*|grow-*|basis-*|\
    aria-*|data-*)
      return 0
      ;;
  esac
  # Common single-word lowercase tokens that show up everywhere as type
  # discriminator strings (`'string' | 'number'`), event names (`'click'`,
  # `'change'`), HTTP methods, and so on. Heuristic: no separators and
  # length below a threshold → almost certainly a discriminator.
  case "$s" in
    *[\ \./_:\-]*) ;;     # has a separator → keep
    *)
      if [ "${#s}" -lt 12 ]; then
        return 0
      fi
      ;;
  esac
  return 1
}

emit_string_section() {
  echo "## Top string literals (>=$LITERAL_MIN_FILES files; paths/directives/short-tokens excluded)"
  echo ""
  printf '  %-7s  %s\n' "Files" "Literal"
  printf '  %-7s  %s\n' "-----" "-------"

  local tmp_per_file_strings tmp_counts
  tmp_per_file_strings=$(mktemp)
  tmp_counts=$(mktemp)

  # Extract candidate string literals per file. Per-file dedup happens here so
  # a single file repeating "/api/users" 50 times doesn't inflate its file
  # count. Length floor 4 (inside the quotes); template literals (backticks)
  # only when they have no `${}` interpolation (those are not literal-equal
  # candidates anyway). 200-char ceiling drops large message blobs / code
  # snippets that aren't useful R2 anchors.
  #
  # Pre-strip module-spec strings before extraction so package names like
  # `next/server`, `@prisma/client`, `node:crypto` (which come from `from`
  # clauses, dynamic `import('...')`, and `require('...')`) don't pollute
  # the literal frequency. Those are TS/JS module identifiers, not R2
  # candidates.
  local prestrip='s/from[[:space:]]+'"'"'[^'"'"']*'"'"'//g; s/from[[:space:]]+"[^"]*"//g; s/require\([[:space:]]*'"'"'[^'"'"']*'"'"'[[:space:]]*\)//g; s/require\([[:space:]]*"[^"]*"[[:space:]]*\)//g; s/import\([[:space:]]*'"'"'[^'"'"']*'"'"'[[:space:]]*\)//g; s/import\([[:space:]]*"[^"]*"[[:space:]]*\)//g'
  if command -v rg >/dev/null 2>&1; then
    local rg_pattern='"[^"\n]{4,200}"|'"'"'[^'"'"'\n]{4,200}'"'"'|`[^`$\n]{4,200}`'
    list_source_files | while IFS= read -r f; do
      sed -E "$prestrip" "$f" 2>/dev/null \
        | rg -oN --no-heading --color=never -e "$rg_pattern" 2>/dev/null \
        | sort -u
    done > "$tmp_per_file_strings"
  else
    list_source_files | while IFS= read -r f; do
      sed -E "$prestrip" "$f" 2>/dev/null \
        | grep -hoE '"[^"]{4,200}"|'"'"'[^'"'"']{4,200}'"'"'|`[^`]{4,200}`' 2>/dev/null \
        | sort -u
    done > "$tmp_per_file_strings"
  fi

  sort "$tmp_per_file_strings" | uniq -c | sort -rn > "$tmp_counts"

  awk '
    {
      count = $1
      $1 = ""
      sub(/^[[:space:]]+/, "")
      # Strip outer quote chars (matched pair only)
      first = substr($0, 1, 1)
      last = substr($0, length($0), 1)
      if (first == last && (first == "\"" || first == "'\''" || first == "`")) {
        body = substr($0, 2, length($0) - 2)
      } else {
        body = $0
      }
      print count "\t" body
    }
  ' "$tmp_counts" \
    | while IFS=$'\t' read -r count body; do
        [ "$count" -ge "$LITERAL_MIN_FILES" ] || continue
        is_noise_string "$body" && continue
        # Truncate display at 80 chars to keep the section scannable
        display="$body"
        if [ "${#display}" -gt 80 ]; then
          display="${display:0:77}..."
        fi
        printf '  %-7d  %s\n' "$count" "$display"
      done | head -"$TOP_N"

  rm -f "$tmp_per_file_strings" "$tmp_counts"
  echo ""
}

emit_numeric_section() {
  echo "## Top numeric literals (>=$LITERAL_MIN_FILES files; HTTP/year/UI-size noise excluded)"
  echo ""
  printf '  %-7s  %s\n' "Files" "Literal"
  printf '  %-7s  %s\n' "-----" "-------"
  local tmp_pairs
  tmp_pairs=$(mktemp)
  list_source_files | while IFS= read -r f; do
    # Strip dotted-decimal sequences (versions like 1.0.0, IPs like 127.0.0.1,
    # any X.Y[.Z…] form) before extracting integer tokens, so the constituent
    # parts of those sequences don't pollute the literal frequency.
    sed -E 's/[0-9]+(\.[0-9]+)+/_DOTTED_/g' "$f" 2>/dev/null \
      | grep -hoE '\b[0-9]+\b' \
      | awk 'length($0) >= 2' \
      | sort -u
  done > "$tmp_pairs"
  sort "$tmp_pairs" | uniq -c | sort -rn \
    | while read -r count value; do
        is_noise_numeric "$value" && continue
        [ "$count" -ge "$LITERAL_MIN_FILES" ] || continue
        printf '  %-7d  %s\n' "$count" "$value"
      done | head -"$TOP_N"
  rm -f "$tmp_pairs"
  echo ""
}

# --- 2. Exported symbol usage frequency ---
# Extract `export {function|const|class|type|interface|enum} NAME` definitions,
# then count how many other files reference each NAME (word-boundary match,
# excluding the defining file). Approximate — comments / strings can hit.

extract_exports() {
  # Output: NAME<TAB>file:line  (one per export)
  # Filtered: SYMBOL_DENYLIST_RE (framework-conventional names) and names
  # shorter than SYMBOL_MIN_LENGTH.
  list_source_files | while IFS= read -r f; do
    grep -nE '^[[:space:]]*export[[:space:]]+(function|const|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="$SYMBOL_DENYLIST_RE" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            if (match(line, /export[[:space:]]+(function|const|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
              tok = substr(line, RSTART, RLENGTH)
              n = split(tok, parts, /[[:space:]]+/)
              name = parts[n]
              if (length(name) < minlen) next
              if (name ~ denylist) next
              print name "\t" file ":" lineno
            }
          }'
  done
}

extract_imports() {
  # Output: file<TAB>imported_name  (one row per imported / re-exported name per file)
  # Captures `import { X, Y as Z, type W } from '...'` and the equivalent
  # `export { X } from '...'` re-export form. Single-line only — multi-line
  # imports across `\n` are missed for now (covers ~5% of cases in typical TS
  # projects; acceptable noise floor for v2).
  # Counting via real import/re-export references avoids the word-boundary
  # collision problem (a generic export name like `error` or `success` does
  # NOT inflate when other files happen to use a local variable of the same
  # name — they have to actually import it).
  local files_list="$1"
  local engine
  if command -v rg >/dev/null 2>&1; then
    engine=rg
  else
    engine=grep
  fi
  if [ "$engine" = "rg" ]; then
    xargs -d '\n' -a "$files_list" rg --no-heading -N --color=never \
      '^\s*(?:import|export)\s+(?:type\s+)?\{[^}]+\}\s+from' 2>/dev/null
  else
    xargs -d '\n' -a "$files_list" grep -HnE \
      '^[[:space:]]*(import|export)[[:space:]]+(type[[:space:]]+)?\{[^}]+\}[[:space:]]+from' 2>/dev/null
  fi | awk -F: '
    {
      # Reconstruct file from first colon (file paths in this scan rarely have :)
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      # Strip leading line-number column when grep emitted "file:lineno:..."
      if (match(content, /^[0-9]+:/)) content = substr(content, RLENGTH + 1)
      if (match(content, /\{[^}]+\}/)) {
        body = substr(content, RSTART + 1, RLENGTH - 2)
        n = split(body, parts, /,/)
        for (i = 1; i <= n; i++) {
          s = parts[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          # individual `type` / `typeof` qualifier
          sub(/^type[[:space:]]+/, "", s)
          sub(/^typeof[[:space:]]+/, "", s)
          # rename `X as Y` — count the original imported name X
          sub(/[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$/, "", s)
          if (s ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print file "\t" s
        }
      }
    }'
}

count_symbol_usage() {
  local symbols_tsv="$1"
  local files_list="$2"

  [ ! -s "$symbols_tsv" ] && { echo "(no exports found)"; return; }

  # Build (file, imported_name) pairs across the codebase, deduplicate.
  local tmp_pairs
  tmp_pairs=$(mktemp)
  extract_imports "$files_list" \
    | awk -F'\t' '!seen[$1 SUBSEP $2]++' > "$tmp_pairs"

  awk -F'\t' '
    NR == FNR { def_file[$1] = $2; next }
    {
      f = $1; sym = $2
      def_loc = def_file[sym]
      if (def_loc == "") next  # not one of our exports
      df = def_loc; sub(/:[0-9]+$/, "", df)
      if (f == df || f == "./" df) next  # exclude the defining file
      count[sym]++
    }
    END {
      for (s in count) print count[s] "\t" s "\t" def_file[s]
    }
  ' "$symbols_tsv" "$tmp_pairs" \
    | sort -t$'\t' -k1,1 -rn \
    | awk -F'\t' -v min="$SYMBOL_MIN_USAGE" -v top="$TOP_N" '
        $1 >= min { n++; if (n > top) exit; printf "  %-7d  %-40s  %s\n", $1, $2, $3 }'
  rm -f "$tmp_pairs"
}

emit_symbol_section() {
  echo "## Top exported symbols by file-usage (>=$SYMBOL_MIN_USAGE files)"
  echo ""
  printf '  %-7s  %-40s  %s\n' "Files" "Symbol" "Defined at"
  printf '  %-7s  %-40s  %s\n' "-----" "------" "----------"
  local symbols_tsv files_list
  symbols_tsv=$(mktemp)
  files_list=$(mktemp)
  extract_exports > "$symbols_tsv"
  list_source_files > "$files_list"
  count_symbol_usage "$symbols_tsv" "$files_list"
  rm -f "$symbols_tsv" "$files_list"
  echo ""
}

# --- Main with cache ---
# Cache key: TRUSTED_ROOT + knob values + source-file mtimes/sizes/paths.
# When any of those change the signature shifts and the fingerprint rebuilds.
cache_signature() {
  echo "$TRUSTED_ROOT"
  echo "TOP_N=$TOP_N LITERAL_MIN_FILES=$LITERAL_MIN_FILES SYMBOL_MIN_USAGE=$SYMBOL_MIN_USAGE SYMBOL_MIN_LENGTH=$SYMBOL_MIN_LENGTH"
  list_source_files | sort | xargs -d '\n' stat -c '%Y %s %n' 2>/dev/null
}

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-config/codebase-fingerprint"
ROOT_HASH=$(printf '%s' "$TRUSTED_ROOT" | sha256sum | cut -c1-16)
CACHE_FILE="$CACHE_DIR/$ROOT_HASH.md"
SIG_FILE="$CACHE_DIR/$ROOT_HASH.sig"

NOCACHE="${NOCACHE:-0}"
if [ "$NOCACHE" != "1" ] && [ -f "$CACHE_FILE" ] && [ -f "$SIG_FILE" ]; then
  current_sig=$(cache_signature | sha256sum | cut -c1-16)
  cached_sig=$(cat "$SIG_FILE" 2>/dev/null || true)
  if [ "$current_sig" = "$cached_sig" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

mkdir -p "$CACHE_DIR"

build_fingerprint() {
  echo "=== Codebase Fingerprint ==="
  echo "Project: $ROOT"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Source files scanned: $(list_source_files | wc -l)"
  echo "Knobs: TOP_N=$TOP_N LITERAL_MIN_FILES=$LITERAL_MIN_FILES SYMBOL_MIN_USAGE=$SYMBOL_MIN_USAGE"
  echo "Engine: $(command -v rg >/dev/null 2>&1 && echo 'ripgrep' || echo 'grep')"
  echo ""
  emit_numeric_section
  emit_string_section
  emit_symbol_section
  echo "=== End Fingerprint ==="
}

build_fingerprint > "$CACHE_FILE"
cache_signature | sha256sum | cut -c1-16 > "$SIG_FILE"
cat "$CACHE_FILE"
