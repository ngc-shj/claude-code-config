#!/bin/bash
# AST plugin: Python via stdlib ast module.

_AST_PY_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AST_PY_RUNNER="$_AST_PY_PLUGIN_DIR/../lib/ast-python-runner.py"

AST_LANG_EXTENSIONS[python]='py'

ast_python_available() {
  command -v python3 >/dev/null 2>&1 || return 1
  [ -f "$_AST_PY_RUNNER" ] || return 1
  return 0
}
AST_LANG_AVAILABLE_FN[python]='ast_python_available'

ast_python_extract_signatures() {
  local file="$1"
  python3 "$_AST_PY_RUNNER" extract-signatures "$file"
}
AST_LANG_EXTRACT_SIGNATURES_FN[python]='ast_python_extract_signatures'

ast_python_diff_signatures() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_signatures_via_extract ast_python_extract_signatures "$base_file" "$head_file"
}
AST_LANG_DIFF_SIGNATURES_FN[python]='ast_python_diff_signatures'

ast_python_extract_enums() {
  local file="$1"
  python3 "$_AST_PY_RUNNER" extract-enums "$file"
}
AST_LANG_EXTRACT_ENUMS_FN[python]='ast_python_extract_enums'

ast_python_diff_enums() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_enums_via_extract ast_python_extract_enums "$base_file" "$head_file"
}
AST_LANG_DIFF_ENUMS_FN[python]='ast_python_diff_enums'
