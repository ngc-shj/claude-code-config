#!/bin/bash
# Scan codebase for shared utilities, helpers, and constants
# Usage: bash ~/.claude/hooks/scan-shared-utils.sh [project-root]
# Output: Inventory of shared modules for sub-agents to reference
# No LLM required — pure grep/find based.
# Language-agnostic: auto-detects project language(s).

set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# --- Language detection ---
detect_languages() {
  local langs=""
  # Check for language indicators (files in root or src/)
  [ -f "package.json" ] || [ -f "tsconfig.json" ] && langs="$langs ts_js"
  [ -f "go.mod" ] && langs="$langs go"
  [ -f "Cargo.toml" ] && langs="$langs rust"
  [ -f "setup.py" ] || [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] && langs="$langs python"
  [ -f "Gemfile" ] && langs="$langs ruby"
  [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] && langs="$langs java"
  [ -f "composer.json" ] && langs="$langs php"
  [ -f "mix.exs" ] && langs="$langs elixir"
  # Fallback: check for common file extensions
  if [ -z "$langs" ]; then
    find . -maxdepth 3 -type f \( -name '*.ts' -o -name '*.js' \) -not -path '*/node_modules/*' | head -1 | grep -q . && langs="$langs ts_js"
    find . -maxdepth 3 -type f -name '*.go' | head -1 | grep -q . && langs="$langs go"
    find . -maxdepth 3 -type f -name '*.py' | head -1 | grep -q . && langs="$langs python"
    find . -maxdepth 3 -type f -name '*.rs' | head -1 | grep -q . && langs="$langs rust"
    find . -maxdepth 3 -type f -name '*.rb' | head -1 | grep -q . && langs="$langs ruby"
    find . -maxdepth 3 -type f -name '*.java' | head -1 | grep -q . && langs="$langs java"
    find . -maxdepth 3 -type f -name '*.php' | head -1 | grep -q . && langs="$langs php"
    find . -maxdepth 3 -type f \( -name '*.ex' -o -name '*.exs' \) | head -1 | grep -q . && langs="$langs elixir"
  fi
  # Shell scripts are always included
  langs="$langs shell"
  echo "$langs"
}

# Language-specific config
# Returns: file_globs export_pattern constant_pattern
lang_file_globs() {
  case "$1" in
    ts_js)  echo '*.ts *.tsx *.js *.jsx *.mjs' ;;
    go)     echo '*.go' ;;
    python) echo '*.py' ;;
    rust)   echo '*.rs' ;;
    ruby)   echo '*.rb' ;;
    java)   echo '*.java' ;;
    php)    echo '*.php' ;;
    elixir) echo '*.ex *.exs' ;;
    shell)  echo '*.sh' ;;
  esac
}

lang_export_pattern() {
  case "$1" in
    ts_js)  echo '^\s*export\s+(function|const|class|type|interface|enum|default)' ;;
    go)     echo '^func\s+[A-Z]|^type\s+[A-Z]|^var\s+[A-Z]' ;;
    python) echo '^(def |class |[A-Z_]{3,}\s*=)' ;;
    rust)   echo '^\s*pub\s+(fn|struct|enum|trait|const|type|mod)' ;;
    ruby)   echo '^\s*(def |class |module |[A-Z_]{3,}\s*=)' ;;
    java)   echo '^\s*public\s+(static\s+)?(class|interface|enum|[a-zA-Z<>]+\s+\w+\s*\()' ;;
    php)    echo '^\s*(public\s+)?(function|class|const|interface)' ;;
    elixir) echo '^\s*(def |defmodule |@\w+)' ;;
    shell)  echo '^[a-zA-Z_]+\(\)\s*\{|^function\s+\w+' ;;
  esac
}

lang_constant_pattern() {
  case "$1" in
    ts_js)  echo 'export\s+const\s+[A-Z_]{3,}' ;;
    go)     echo '^\s*(const|var)\s+[A-Z]' ;;
    python) echo '^[A-Z_]{3,}\s*=' ;;
    rust)   echo '^\s*pub\s+const\s+[A-Z_]{3,}' ;;
    ruby)   echo '^\s*[A-Z_]{3,}\s*=' ;;
    java)   echo 'static\s+final\s+\w+\s+[A-Z_]{3,}' ;;
    php)    echo '^\s*const\s+[A-Z_]{3,}' ;;
    elixir) echo '@[a-z_]+\s+' ;;
    shell)  echo '^[A-Z_]{3,}=' ;;
  esac
}

# Common event/dispatch patterns per language
lang_event_pattern() {
  case "$1" in
    ts_js)  echo 'dispatchEvent|dispatch\(|emit\(|\.fire\(|postMessage|BroadcastChannel|\.on\(|\.once\(' ;;
    go)     echo 'chan\s|<-\s|Publish\(|Subscribe\(|Notify\(|Emit\(' ;;
    python) echo 'emit\(|signal\.|send\(|publish\(|dispatch\(|\.connect\(' ;;
    rust)   echo 'emit\(|send\(|publish\(|tx\.|channel\(\)' ;;
    ruby)   echo 'emit\(|broadcast\(|publish\(|trigger\(|ActiveSupport::Notifications' ;;
    java)   echo 'publish\(|fire\w+Event|notify\(|addEventListener|EventBus' ;;
    php)    echo 'dispatch\(|fire\(|emit\(|event\(' ;;
    elixir) echo 'GenServer\.cast|Phoenix\.PubSub|broadcast\(' ;;
    shell)  echo '' ;; # N/A
  esac
}

# Directories to exclude from all searches
EXCLUDE_DIRS="node_modules .next .git .claude dist build target __pycache__ .tox .venv venv vendor"

build_exclude_args() {
  local args=""
  for d in $EXCLUDE_DIRS; do
    args="$args --exclude-dir=$d"
  done
  echo "$args"
}

GREP_EXCLUDE=$(build_exclude_args)

# Shared module directory candidates (language-agnostic)
SHARED_DIRS="lib utils shared common helpers internal pkg core services
  src/lib src/utils src/shared src/common src/helpers src/internal src/pkg src/core src/services
  app/lib app/helpers app/services"

LANGS=$(detect_languages)

echo "=== Shared Utility Inventory ==="
echo "# NOTE: Pattern-based scan — verify function purpose manually before flagging R1"
echo "Project: $ROOT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Languages: $LANGS"
echo ""

# --- 1. Find shared module directories ---
echo "## Shared Module Directories"
found_dirs=""
for dir in $SHARED_DIRS; do
  if [ -d "$dir" ]; then
    echo "  $dir/"
    found_dirs="$found_dirs $dir"
    for lang in $LANGS; do
      globs=$(lang_file_globs "$lang")
      export_pat=$(lang_export_pattern "$lang")
      find_args=()
      first=true
      for g in $globs; do
        $first || find_args+=(-o)
        find_args+=(-name "$g")
        first=false
      done
      find "$dir" -maxdepth 3 -type f \( "${find_args[@]}" \) 2>/dev/null | sort | while read -r f; do
        exports=$(grep -cE "$export_pat" "$f" 2>/dev/null || true)
        exports="${exports:-0}"
        exports=$(echo "$exports" | head -1)
        if [ "$exports" -gt 0 ]; then
          echo "    $f ($exports exports)"
        fi
      done
    done
  fi
done
if [ -z "$found_dirs" ]; then
  echo "  (no shared directories found)"
fi
echo ""

# --- 2. Find exported helper functions in shared directories ---
echo "## Key Exported Functions"
found_any=false
for lang in $LANGS; do
  globs=$(lang_file_globs "$lang")
  export_pat=$(lang_export_pattern "$lang")
  include_args=""
  for g in $globs; do
    include_args="$include_args --include=$g"
  done
  for dir in $found_dirs; do
    # shellcheck disable=SC2086
    results=$(grep -rn $include_args $GREP_EXCLUDE -E "$export_pat" "$dir" 2>/dev/null | head -50) || true
    if [ -n "$results" ]; then
      found_any=true
      echo "$results" | sed 's/^/  /'
    fi
  done
done
if ! $found_any; then
  echo "  (none found)"
fi
echo ""

# --- 3. Find shared constants ---
echo "## Shared Constants & Validation"
found_any=false
for lang in $LANGS; do
  globs=$(lang_file_globs "$lang")
  const_pat=$(lang_constant_pattern "$lang")
  [ -z "$const_pat" ] && continue
  include_args=""
  for g in $globs; do
    include_args="$include_args --include=$g"
  done
  for dir in $found_dirs; do
    # shellcheck disable=SC2086
    files=$(grep -rl $include_args $GREP_EXCLUDE -E "$const_pat" "$dir" 2>/dev/null | sort -u) || true
    for f in $files; do
      found_any=true
      echo "  $f:"
      grep -n -E "$const_pat" "$f" 2>/dev/null | head -20 | sed 's/^/    /'
    done
  done
done
if ! $found_any; then
  echo "  (none found)"
fi
echo ""

# --- 4. Find common infrastructure patterns ---
echo "## Common Patterns (rate limiters, validators, encoders, crypto)"
GENERIC_PATTERNS=(
  'rate.?limit|throttle'
  'validat(e|or|ion)|sanitiz(e|er)'
  'encod(e|er|ing)|decod(e|er|ing)|base64|serialize|deserialize'
  'timingSafeEqual|constant.?time|hmac|hash|encrypt|decrypt'
  'middleware|interceptor'
  'retry|backoff|circuit.?break'
)
for pattern in "${GENERIC_PATTERNS[@]}"; do
  include_args=""
  for lang in $LANGS; do
    for g in $(lang_file_globs "$lang"); do
      include_args="$include_args --include=$g"
    done
  done
  # shellcheck disable=SC2086
  matches=$(grep -rli $include_args $GREP_EXCLUDE -E "$pattern" 2>/dev/null | grep -v 'node_modules\|\.next\|dist\|build\|target\|__pycache__' | head -20) || true
  if [ -n "$matches" ]; then
    echo "  Pattern: $pattern"
    echo "$matches" | sed 's/^/    /'
  fi
done
echo ""

# --- 5. Find event dispatch patterns ---
echo "## Event Dispatch Patterns"
found_any=false
for lang in $LANGS; do
  event_pat=$(lang_event_pattern "$lang")
  [ -z "$event_pat" ] && continue
  globs=$(lang_file_globs "$lang")
  include_args=""
  for g in $globs; do
    include_args="$include_args --include=$g"
  done
  # shellcheck disable=SC2086
  results=$(grep -rn $include_args $GREP_EXCLUDE -E "$event_pat" 2>/dev/null | head -50) || true
  if [ -n "$results" ]; then
    found_any=true
    echo "$results" | sed 's/^/  /'
  fi
done
if ! $found_any; then
  echo "  (none found)"
fi
echo ""

echo "=== End Inventory ==="
