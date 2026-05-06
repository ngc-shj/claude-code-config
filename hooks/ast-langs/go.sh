#!/bin/bash
# AST plugin: Go via go/parser + go/ast.

_AST_GO_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AST_GO_RUNNER="$_AST_GO_PLUGIN_DIR/../lib/ast-go-runner.go"

AST_LANG_EXTENSIONS[go]='go'

ast_go_available() {
  command -v go >/dev/null 2>&1 || return 1
  [ -f "$_AST_GO_RUNNER" ] || return 1
  return 0
}
AST_LANG_AVAILABLE_FN[go]='ast_go_available'

ast_go_extract_signatures() {
  local file="$1"
  go run "$_AST_GO_RUNNER" extract-signatures "$file"
}
AST_LANG_EXTRACT_SIGNATURES_FN[go]='ast_go_extract_signatures'

ast_go_diff_signatures() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_signatures_via_extract ast_go_extract_signatures "$base_file" "$head_file"
}
AST_LANG_DIFF_SIGNATURES_FN[go]='ast_go_diff_signatures'

ast_go_extract_enums() {
  local file="$1"
  go run "$_AST_GO_RUNNER" extract-enums "$file"
}
AST_LANG_EXTRACT_ENUMS_FN[go]='ast_go_extract_enums'

ast_go_diff_enums() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_enums_via_extract ast_go_extract_enums "$base_file" "$head_file"
}
AST_LANG_DIFF_ENUMS_FN[go]='ast_go_diff_enums'
