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
#
# === Language plugin architecture ===
#
# Per-language logic lives in `hooks/fingerprint-langs/<lang>.sh`. Each plugin
# is sourced at startup and registers itself by writing into associative
# array tables (FP_EXTENSIONS / FP_DENYLIST / FP_CATEGORY / FP_POST_FILTER_RE
# / FP_EXPORTS_FN / FP_IMPORTS_FN). The core script discovers plugins via
# directory scan — adding a new language is one new plugin file, no edits to
# this file.
#
# Languages cluster by import idiom:
#   (1) Named-import — TS named, Python `from M import X`, Rust `use M::X`.
#       Symbol is explicit in the import statement; regex extraction is a
#       1-pass match. IMPLEMENTED for TS/JS and Python.
#   (2) Qualifier-reference — Go `pkg.X`, Ruby `Mod::X`, PHP `Foo::method`,
#       Elixir `Mod.X`. Symbol appears as a qualified reference in the file
#       body, not in the import statement. Extraction is a 1-pass
#       `<alias>.<Symbol>` regex. Alias resolution is approximate — false
#       positives from local-var-method calls are filtered downstream by the
#       aggregator's def_file lookup (a reference whose name is not in the
#       project's exports table is silently dropped). IMPLEMENTED for Go as
#       a reference to validate the contract works for category (2).
#   (1.5) Hybrid (named-import / qualifier-reference) — Java
#       `import com.example.Foo;` names the class explicitly in the import
#       statement (category-1-shaped), but body references use qualifier
#       syntax (`Foo.method()`). For symbol-usage counting we only need the
#       import statement, which directly names the class — same shape as
#       category-1. IMPLEMENTED for Java.
#   (3) Path-resolved — TS default `import X from 'path'`, Python `import M`
#       + `M.X` references. Requires module-path → file-path mapping
#       (tsconfig paths, Python __init__.py resolution, etc.). NOT
#       SUPPORTED — surface via scan-shared-utils.sh's structural inventory
#       + manual review instead.
#
# Plugin contract (see `hooks/fingerprint-langs/ts_js.sh` for a reference):
#
#   FP_EXTENSIONS[<lang>] = "ext1 ext2 ..."
#     Required. Space-separated list of file extensions (no leading dot).
#
#   FP_DENYLIST[<lang>] = '^(...)$'
#     Optional. Regex matched against extracted symbol names; matches are
#     dropped from the symbol section. Defaults to no filtering when unset.
#
#   FP_CATEGORY[<lang>] = 1 | 2 | 3
#     Optional. Idiom category (informational; see above).
#
#   FP_POST_FILTER_RE[<lang>] = '\.d\.ts$'
#     Optional. Additional regex applied to the file list after the shared
#     EXCLUDE_DIRS_RE / TEST_FILE_RE filters. Files matching this regex are
#     dropped (e.g. ts_js drops *.d.ts type-declaration files).
#
#   fp_<lang>_extract_exports()
#     Required. Reads files via `list_source_files_for_lang <lang>`. Emits
#     one row per module-level public symbol: NAME<TAB>file:line
#     Apply ${FP_DENYLIST[<lang>]} filter and SYMBOL_MIN_LENGTH gate.
#   FP_EXPORTS_FN[<lang>] = 'fp_<lang>_extract_exports'
#
#   fp_<lang>_extract_imports(files_list)
#     Required. Reads the master files_list. Emits one row per
#     (file, imported_symbol) pair: file<TAB>NAME
#     Use _filter_files_by_ext to restrict the master list to this language's
#     own files. Per-file deduplication is handled later by count_symbol_usage,
#     so over-emitting is harmless; under-emitting drops real R1 anchors.
#   FP_IMPORTS_FN[<lang>] = 'fp_<lang>_extract_imports'
#
# After dropping a new plugin file in the directory, no changes to this
# script are needed. detect_languages must already recognize the language's
# manifest or extension (extend it once for the language family if needed).
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

EXCLUDE_DIRS_RE='(/node_modules/|/\.next/|/\.git/|/dist/|/build/|/target/|/__pycache__/|/\.tox/|/\.venv/|/venv/|/vendor/|/coverage/|/out/|/load-test/|/load-tests/|/perf-tests?/|/e2e/|/cypress/|/playwright/|/\.pytest_cache/|/\.mypy_cache/|/\.ruff_cache/|/site-packages/)'
TEST_FILE_RE='(\.test\.|\.spec\.|/__tests__/|/test/|/tests/|/fixtures/|\.fixture\.|\.stories\.|\.e2e\.|/test_[^/]*\.py$|/[^/]*_test\.py$|/conftest\.py$)'

SYMBOL_MIN_LENGTH=2

# --- Plugin registry (associative arrays populated by hooks/fingerprint-langs/*.sh) ---
# Each language plugin sources into the shell and writes into these tables.
# See `hooks/fingerprint-langs/ts_js.sh` for a reference implementation.
declare -A FP_EXTENSIONS FP_DENYLIST FP_CATEGORY FP_POST_FILTER_RE FP_EXPORTS_FN FP_IMPORTS_FN

# --- Resolve plugin directory and shared helpers ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/fingerprint-langs"

# Helpers that plugins call from inside their extractor functions. Defined
# before plugin sourcing so plugins can reference them at definition time
# (function bodies are only evaluated at call time, but keeping order
# explicit prevents subtle source-order bugs if plugins ever do top-level work).
_filter_files_by_ext() {
  # Read the master files list and emit only paths whose extension matches
  # any of the given extensions. Used by per-language import extractors to
  # scope the master list to their own files.
  local files_list="$1"; shift
  local ext_re
  ext_re=$(printf '%s|' "$@" | sed 's/|$//')
  grep -E "\\.($ext_re)\$" "$files_list" || true
}

# --- Source language plugins ---
source_lang_plugins() {
  local plugin
  if [ ! -d "$PLUGIN_DIR" ]; then
    echo "Warning: language plugin dir not found at $PLUGIN_DIR — symbol section will be empty for all languages." >&2
    return 0
  fi
  for plugin in "$PLUGIN_DIR"/*.sh; do
    [ -e "$plugin" ] || continue
    # shellcheck disable=SC1090
    source "$plugin"
  done
}
source_lang_plugins

# --- Language detection (mirrors scan-shared-utils.sh) ---
detect_languages() {
  local langs=""
  [ -f "package.json" ] || [ -f "tsconfig.json" ] && langs="$langs ts_js"
  [ -f "setup.py" ] || [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] && langs="$langs python"
  [ -f "go.mod" ] && langs="$langs go"
  [ -f "Cargo.toml" ] && langs="$langs rust"
  [ -f "Gemfile" ] && langs="$langs ruby"
  [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] && langs="$langs java"
  [ -f "composer.json" ] && langs="$langs php"
  [ -f "mix.exs" ] && langs="$langs elixir"
  # Fallback: extension-based scan when no manifest matched.
  if [ -z "$langs" ]; then
    find . -maxdepth 3 -type f \( -name '*.ts' -o -name '*.js' \) -not -path '*/node_modules/*' 2>/dev/null | head -1 | grep -q . && langs="$langs ts_js"
    find . -maxdepth 3 -type f -name '*.py' -not -path '*/.venv/*' 2>/dev/null | head -1 | grep -q . && langs="$langs python"
    find . -maxdepth 3 -type f -name '*.go' 2>/dev/null | head -1 | grep -q . && langs="$langs go"
    find . -maxdepth 3 -type f -name '*.rs' 2>/dev/null | head -1 | grep -q . && langs="$langs rust"
    find . -maxdepth 3 -type f -name '*.rb' 2>/dev/null | head -1 | grep -q . && langs="$langs ruby"
    find . -maxdepth 3 -type f -name '*.java' 2>/dev/null | head -1 | grep -q . && langs="$langs java"
    find . -maxdepth 3 -type f -name '*.php' 2>/dev/null | head -1 | grep -q . && langs="$langs php"
    find . -maxdepth 3 -type f \( -name '*.ex' -o -name '*.exs' \) 2>/dev/null | head -1 | grep -q . && langs="$langs elixir"
  fi
  # Trim leading whitespace; emit empty string if nothing detected.
  echo "$langs" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

LANGS=$(detect_languages)

warn_unsupported_langs_once() {
  # Emit a single stderr warning per detected-but-unimplemented language so
  # the user knows numeric/string sections still cover those files but the
  # symbol section will not. Implementation status is read from the plugin
  # registry — a language is "supported" only when it has registered both
  # extract_exports and extract_imports functions.
  local lang
  for lang in $LANGS; do
    if [ -z "${FP_EXPORTS_FN[$lang]:-}" ] || [ -z "${FP_IMPORTS_FN[$lang]:-}" ]; then
      echo "Warning: language '$lang' detected but no symbol extractor registered — symbol section will skip $lang files. Numeric and string sections still include them." >&2
    fi
  done
}
warn_unsupported_langs_once

_default_lang_extensions() {
  # Fallback file-extension list for languages that detect_languages
  # recognizes via manifest/extension scan but have no plugin registered.
  # Numeric and string sections still need to enumerate files for these
  # languages — only the symbol section is plugin-gated. Plugins override
  # this by setting FP_EXTENSIONS[<lang>].
  case "$1" in
    ts_js)  echo 'ts tsx js jsx mjs' ;;
    python) echo 'py' ;;
    go)     echo 'go' ;;
    rust)   echo 'rs' ;;
    ruby)   echo 'rb' ;;
    java)   echo 'java' ;;
    php)    echo 'php' ;;
    elixir) echo 'ex exs' ;;
  esac
}

list_source_files_for_lang() {
  local lang="$1"
  local exts="${FP_EXTENSIONS[$lang]:-$(_default_lang_extensions "$lang")}"
  [ -z "$exts" ] && return 0
  local find_args=() first=true
  for e in $exts; do
    $first || find_args+=(-o)
    find_args+=(-name "*.$e")
    first=false
  done
  local post_filter="${FP_POST_FILTER_RE[$lang]:-}"
  if [ -n "$post_filter" ]; then
    find . -type f \( "${find_args[@]}" \) 2>/dev/null \
      | grep -vE "$EXCLUDE_DIRS_RE" \
      | grep -vE "$TEST_FILE_RE" \
      | grep -vE "$post_filter" \
      || true
  else
    find . -type f \( "${find_args[@]}" \) 2>/dev/null \
      | grep -vE "$EXCLUDE_DIRS_RE" \
      | grep -vE "$TEST_FILE_RE" \
      || true
  fi
}

list_source_files() {
  # Concatenates files from every detected language into a single list.
  # Numeric / string sections consume this directly (language-agnostic); the
  # symbol section dispatches per-language via extract_exports_for_lang and
  # extract_imports_for_lang.
  local lang
  for lang in $LANGS; do
    list_source_files_for_lang "$lang"
  done
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
  # Output: NAME<TAB>file:line  (concatenated across detected languages).
  # Per-language extractors live in hooks/fingerprint-langs/<lang>.sh and
  # register themselves into FP_EXPORTS_FN at source time. Unregistered
  # languages were already warned about at startup; here we just skip them.
  local lang fn
  for lang in $LANGS; do
    fn="${FP_EXPORTS_FN[$lang]:-}"
    [ -n "$fn" ] && "$fn"
  done
}

extract_imports() {
  # Output: file<TAB>imported_name  (concatenated across detected languages).
  # Per-language extractors live in hooks/fingerprint-langs/<lang>.sh and
  # register themselves into FP_IMPORTS_FN at source time. Counting via real
  # import/re-export references avoids the word-boundary collision problem
  # (a generic export name like `error` or `success` does NOT inflate when
  # other files happen to use a local variable of the same name — they have
  # to actually import it).
  local files_list="$1"
  local lang fn
  for lang in $LANGS; do
    fn="${FP_IMPORTS_FN[$lang]:-}"
    [ -n "$fn" ] && "$fn" "$files_list"
  done
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
# Cache key: TRUSTED_ROOT + knob values + detected languages + plugin file
# mtimes + source-file mtimes/sizes/paths. A manifest change (e.g. adding
# pyproject.toml to a previously-pure TS repo) shifts LANGS, a plugin file
# edit shifts the plugin mtime block, and a source file edit shifts the
# bottom block — any one of these forces a rebuild.
cache_signature() {
  echo "$TRUSTED_ROOT"
  echo "LANGS=$LANGS"
  echo "TOP_N=$TOP_N LITERAL_MIN_FILES=$LITERAL_MIN_FILES SYMBOL_MIN_USAGE=$SYMBOL_MIN_USAGE SYMBOL_MIN_LENGTH=$SYMBOL_MIN_LENGTH"
  if [ -d "$PLUGIN_DIR" ]; then
    find "$PLUGIN_DIR" -name '*.sh' -type f 2>/dev/null \
      | sort | xargs -d '\n' stat -c '%Y %s %n' 2>/dev/null
  fi
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
  echo "Languages: ${LANGS:-(none detected)}"
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
