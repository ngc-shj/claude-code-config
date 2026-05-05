#!/bin/bash
# Language plugin: TypeScript / JavaScript
# Category: (1) Named-import. Symbols are explicit in `import { X } from 'y'`.
#
# Coverage:
#   - Exports: top-level `export {function|const|class|type|interface|enum} NAME`.
#   - Imports/re-exports: single-line `import { X[, Y as Z, type W] } from 'pkg'`
#     and the equivalent `export { X } from 'pkg'`. The pre-strip in
#     emit_string_section drops `from '...'` clauses so package specifiers
#     don't pollute the string section.
#   - Default-export-from-path resolution (TS `import X from 'path'`) is
#     deliberately not implemented — tracking it requires tsconfig paths +
#     module-path-to-file-path mapping, which exceeds the contract scope.
#
# Plugin contract: see top of build-codebase-fingerprint.sh.

FP_EXTENSIONS[ts_js]='ts tsx js jsx mjs'

# Framework-conventional per-file exports (Next.js App Router HTTP method
# handlers, route metadata, etc.) and single-letter aliases that pollute the
# symbol section if counted as shared utilities.
FP_DENYLIST[ts_js]='^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|default|metadata|generateMetadata|generateStaticParams|loader|action|config|runtime|dynamic|revalidate|fetchCache|preferredRegion|maxDuration)$'

FP_CATEGORY[ts_js]=1

# *.d.ts files declare types only; their exports inflate symbol counts with
# namespace declarations that have no runtime presence.
FP_POST_FILTER_RE[ts_js]='\.d\.ts$'

fp_ts_js_extract_exports() {
  list_source_files_for_lang ts_js | while IFS= read -r f; do
    grep -nE '^[[:space:]]*export[[:space:]]+(function|const|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[ts_js]}" -v minlen="$SYMBOL_MIN_LENGTH" '
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
FP_EXPORTS_FN[ts_js]='fp_ts_js_extract_exports'

fp_ts_js_extract_imports() {
  local files_list="$1"
  local tmp_filtered
  tmp_filtered=$(mktemp)
  _filter_files_by_ext "$files_list" ts tsx js jsx mjs > "$tmp_filtered"
  if [ ! -s "$tmp_filtered" ]; then rm -f "$tmp_filtered"; return 0; fi
  if command -v rg >/dev/null 2>&1; then
    xargs -d '\n' -a "$tmp_filtered" rg --no-heading -N --color=never \
      '^\s*(?:import|export)\s+(?:type\s+)?\{[^}]+\}\s+from' 2>/dev/null
  else
    xargs -d '\n' -a "$tmp_filtered" grep -HnE \
      '^[[:space:]]*(import|export)[[:space:]]+(type[[:space:]]+)?\{[^}]+\}[[:space:]]+from' 2>/dev/null
  fi | awk -F: '
    {
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      if (match(content, /^[0-9]+:/)) content = substr(content, RLENGTH + 1)
      if (match(content, /\{[^}]+\}/)) {
        body = substr(content, RSTART + 1, RLENGTH - 2)
        n = split(body, parts, /,/)
        for (i = 1; i <= n; i++) {
          s = parts[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          sub(/^type[[:space:]]+/, "", s)
          sub(/^typeof[[:space:]]+/, "", s)
          sub(/[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$/, "", s)
          if (s ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print file "\t" s
        }
      }
    }'
  rm -f "$tmp_filtered"
}
FP_IMPORTS_FN[ts_js]='fp_ts_js_extract_imports'
