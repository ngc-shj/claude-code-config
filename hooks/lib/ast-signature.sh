#!/bin/bash
# Generic AST signature extraction. Sources every plugin under
# hooks/ast-langs/, dispatches by file extension.
#
# Plugin contract (each ast-langs/<lang>.sh registers):
#   AST_LANG_EXTENSIONS[lang]='ext1 ext2 ...'
#   AST_LANG_AVAILABLE_FN[lang]='function returning 0/1'
#   AST_LANG_EXTRACT_SIGNATURES_FN[lang]='function emitting JSON sig array'
#
# Emitted signature schema (per element):
#   { name, owner, line, kind, params: [{name,type,optional,rest,hasDefault}],
#     returnType }
#
# Callers use jq (or equivalent) to consume. Schema is intentionally
# language-agnostic — Python / Go plugins emit the same shape.

# Idempotent guard: ast-signature.sh may be sourced from multiple hooks.
if [ -z "${_AST_SIGNATURE_SOURCED:-}" ]; then
  _AST_SIGNATURE_SOURCED=1

  declare -gA AST_LANG_EXTENSIONS
  declare -gA AST_LANG_AVAILABLE_FN
  declare -gA AST_LANG_EXTRACT_SIGNATURES_FN
  declare -gA AST_LANG_DIFF_SIGNATURES_FN
  declare -gA AST_LANG_EXTRACT_ENUMS_FN
  declare -gA AST_LANG_DIFF_ENUMS_FN

  _AST_LANGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ast-langs"

  if [ -d "$_AST_LANGS_DIR" ]; then
    for _ast_plugin in "$_AST_LANGS_DIR"/*.sh; do
      [ -f "$_ast_plugin" ] || continue
      # shellcheck disable=SC1090
      source "$_ast_plugin"
    done
    unset _ast_plugin
  fi
fi

# ast_lang_for_file <file> → echoes the lang key that handles this file's
# extension, or returns 1 if no plugin matches.
ast_lang_for_file() {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}"
  local lang e
  for lang in "${!AST_LANG_EXTENSIONS[@]}"; do
    for e in ${AST_LANG_EXTENSIONS[$lang]}; do
      if [ "$e" = "$ext" ]; then
        echo "$lang"
        return 0
      fi
    done
  done
  return 1
}

# ast_available <file> → 0 if the matching plugin's runtime is provisioned.
ast_available() {
  local file="$1"
  local lang
  lang=$(ast_lang_for_file "$file") || return 1
  local fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn"
}

# ast_extract_signatures <file> → JSON array of signatures on stdout.
# Returns 1 if no plugin matches or runtime unavailable.
ast_extract_signatures() {
  local file="$1"
  local lang
  lang=$(ast_lang_for_file "$file") || return 1
  local avail_fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$avail_fn" ] && "$avail_fn" || return 1
  local fn="${AST_LANG_EXTRACT_SIGNATURES_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn" "$file"
}

# ast_diff_signatures <baseFile> <headFile> → JSON array of changed
# signatures (see ast-runner.js diff-signatures op for schema). Plugin is
# selected by the head file's extension; base file is assumed to be the
# same language. Returns 1 if no plugin matches or runtime unavailable.
ast_diff_signatures() {
  local base_file="$1"
  local head_file="$2"
  local lang
  lang=$(ast_lang_for_file "$head_file") || return 1
  local avail_fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$avail_fn" ] && "$avail_fn" || return 1
  local fn="${AST_LANG_DIFF_SIGNATURES_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn" "$base_file" "$head_file"
}

# ast_extract_enums <file> → JSON array of enum declarations on stdout
# (schema: see ast-runner.js extract-enums op). Returns 1 if unavailable.
ast_extract_enums() {
  local file="$1"
  local lang
  lang=$(ast_lang_for_file "$file") || return 1
  local avail_fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$avail_fn" ] && "$avail_fn" || return 1
  local fn="${AST_LANG_EXTRACT_ENUMS_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn" "$file"
}

# ast_diff_enums <baseFile> <headFile> → JSON array of enum member
# changes (schema: see ast-runner.js diff-enums op). Used by R12 C5.
ast_diff_enums() {
  local base_file="$1"
  local head_file="$2"
  local lang
  lang=$(ast_lang_for_file "$head_file") || return 1
  local avail_fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$avail_fn" ] && "$avail_fn" || return 1
  local fn="${AST_LANG_DIFF_ENUMS_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn" "$base_file" "$head_file"
}
