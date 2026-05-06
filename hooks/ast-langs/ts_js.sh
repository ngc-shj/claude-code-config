#!/bin/bash
# AST plugin: TypeScript / JavaScript via TypeScript Compiler API.
#
# Mirrors fingerprint-langs/ plugin contract: registers handlers in shared
# associative arrays. The actual parsing happens in lib/ast-runner.js (Node);
# this file is the bash dispatch surface.
#
# Why TS Compiler API: parses every TS construct (generics, overloads,
# destructured / rest / optional / default params, satisfies, conditional
# types) without a regex maintenance burden. Pure JS dep — no native build.

# Resolve script-relative paths. BASH_SOURCE[0] is this plugin file.
_AST_TS_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AST_TS_RUNNER="$_AST_TS_PLUGIN_DIR/../lib/ast-runner.js"
_AST_TS_NODE_MODULES="$_AST_TS_PLUGIN_DIR/../lib/node_modules"

AST_LANG_EXTENSIONS[ts_js]='ts tsx js jsx mjs cjs'

# Returns 0 if the runtime is available, 1 otherwise. Callers use this to
# decide whether to skip AST analysis silently and let regex fallbacks run.
ast_ts_js_available() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "$_AST_TS_RUNNER" ] || return 1
  [ -d "$_AST_TS_NODE_MODULES/typescript" ] || return 1
  return 0
}
AST_LANG_AVAILABLE_FN[ts_js]='ast_ts_js_available'

ast_ts_js_extract_signatures() {
  local file="$1"
  NODE_PATH="$_AST_TS_NODE_MODULES" node "$_AST_TS_RUNNER" extract-signatures "$file"
}
AST_LANG_EXTRACT_SIGNATURES_FN[ts_js]='ast_ts_js_extract_signatures'

ast_ts_js_diff_signatures() {
  local base_file="$1"
  local head_file="$2"
  NODE_PATH="$_AST_TS_NODE_MODULES" node "$_AST_TS_RUNNER" diff-signatures "$base_file" "$head_file"
}
AST_LANG_DIFF_SIGNATURES_FN[ts_js]='ast_ts_js_diff_signatures'

ast_ts_js_extract_enums() {
  local file="$1"
  NODE_PATH="$_AST_TS_NODE_MODULES" node "$_AST_TS_RUNNER" extract-enums "$file"
}
AST_LANG_EXTRACT_ENUMS_FN[ts_js]='ast_ts_js_extract_enums'

ast_ts_js_diff_enums() {
  local base_file="$1"
  local head_file="$2"
  NODE_PATH="$_AST_TS_NODE_MODULES" node "$_AST_TS_RUNNER" diff-enums "$base_file" "$head_file"
}
AST_LANG_DIFF_ENUMS_FN[ts_js]='ast_ts_js_diff_enums'

ast_ts_js_find_references_batch() {
  local input_json_file="$1"
  NODE_PATH="$_AST_TS_NODE_MODULES" node "$_AST_TS_RUNNER" find-references-batch "$input_json_file"
}
AST_LANG_FIND_REFERENCES_BATCH_FN[ts_js]='ast_ts_js_find_references_batch'
