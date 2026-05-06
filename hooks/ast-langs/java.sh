#!/bin/bash
# AST plugin: Java via JavaParser-compiled helper.

_AST_JAVA_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AST_JAVA_BUILD_DIR="${AST_JAVA_BUILD_DIR:-$_AST_JAVA_PLUGIN_DIR/../lib/java-build}"
_AST_JAVA_LIB_DIR="${AST_JAVA_LIB_DIR:-$_AST_JAVA_PLUGIN_DIR/../lib/java-lib}"

AST_LANG_EXTENSIONS[java]='java'

ast_java_available() {
  command -v java >/dev/null 2>&1 || return 1
  [ -f "$_AST_JAVA_BUILD_DIR/AstJavaRunner.class" ] || return 1
  compgen -G "$_AST_JAVA_LIB_DIR/*.jar" >/dev/null || return 1
  return 0
}
AST_LANG_AVAILABLE_FN[java]='ast_java_available'

ast_java_extract_signatures() {
  local file="$1"
  java -cp "$_AST_JAVA_BUILD_DIR:$_AST_JAVA_LIB_DIR/*" AstJavaRunner extract-signatures "$file"
}
AST_LANG_EXTRACT_SIGNATURES_FN[java]='ast_java_extract_signatures'

ast_java_diff_signatures() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_signatures_via_extract ast_java_extract_signatures "$base_file" "$head_file"
}
AST_LANG_DIFF_SIGNATURES_FN[java]='ast_java_diff_signatures'

ast_java_extract_enums() {
  local file="$1"
  java -cp "$_AST_JAVA_BUILD_DIR:$_AST_JAVA_LIB_DIR/*" AstJavaRunner extract-enums "$file"
}
AST_LANG_EXTRACT_ENUMS_FN[java]='ast_java_extract_enums'

ast_java_diff_enums() {
  local base_file="$1"
  local head_file="$2"
  ast_diff_enums_via_extract ast_java_extract_enums "$base_file" "$head_file"
}
AST_LANG_DIFF_ENUMS_FN[java]='ast_java_diff_enums'
