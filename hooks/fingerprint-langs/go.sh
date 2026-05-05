#!/bin/bash
# Language plugin: Go
# Category: (2) Qualifier-reference. Symbols appear as `pkg.Symbol` in the
# file body, NOT in the import statement. Reference implementation that
# validates the contract works for category-2 languages.
#
# Coverage:
#   - Exports: column-0 `func|type|var|const|interface NAME` where NAME
#     starts with an uppercase letter (Go's public-API convention).
#     Receiver methods (`func (r Recv) Foo`) are excluded — they need
#     receiver-type tracking the contract does not capture. Block
#     declarations like `var (\n  Foo = 1\n)` are also not extracted (would
#     need a state-machine awk pass; documented limitation).
#   - Imports: `<lowercase-id>.<Capitalized-id>` references in the file body.
#     The aggregator filters references whose Symbol is not in the project's
#     exports table, so stdlib references like `fmt.Println` are silently
#     dropped. False-positive risk: a local variable named the same as a
#     package alias, calling a method whose name happens to be a project
#     export. Acceptable v1 approximation — the alternative is per-file
#     import-block parsing with alias resolution, which is roughly an order
#     of magnitude more code.
#
# Plugin contract: see top of build-codebase-fingerprint.sh.

FP_EXTENSIONS[go]='go'

# Capitalized package-level names are exports by convention, but a few are
# conventional entry points / interface-method names that don't belong in a
# shared-utility ranking. Test_* / Benchmark_* / Example_* would only appear
# if test-file exclusion missed something.
FP_DENYLIST[go]='^(Main|Init|TestMain|Test_.*|Benchmark.*|Example.*|String|Error|MarshalJSON|UnmarshalJSON|ServeHTTP)$'

FP_CATEGORY[go]=2

fp_go_extract_exports() {
  list_source_files_for_lang go | while IFS= read -r f; do
    grep -nE '^(func|type|var|const|interface)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[go]}" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            if (match(line, /^(func|type|var|const|interface)[[:space:]]+[A-Z][A-Za-z0-9_]*/)) {
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
FP_EXPORTS_FN[go]='fp_go_extract_exports'

fp_go_extract_imports() {
  local files_list="$1"
  local tmp_filtered
  tmp_filtered=$(mktemp)
  _filter_files_by_ext "$files_list" go > "$tmp_filtered"
  if [ ! -s "$tmp_filtered" ]; then rm -f "$tmp_filtered"; return 0; fi
  if command -v rg >/dev/null 2>&1; then
    xargs -d '\n' -a "$tmp_filtered" rg --no-heading -N --color=never \
      -o '\b[a-z][a-zA-Z0-9_]*\.[A-Z][A-Za-z0-9_]*' 2>/dev/null
  else
    xargs -d '\n' -a "$tmp_filtered" grep -hoE \
      '\b[a-z][a-zA-Z0-9_]*\.[A-Z][A-Za-z0-9_]*' 2>/dev/null
  fi | awk -F: '
    {
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      dot = index(content, ".")
      if (dot == 0) next
      sym = substr(content, dot + 1)
      if (sym ~ /^[A-Z][A-Za-z0-9_]*$/) print file "\t" sym
    }'
  rm -f "$tmp_filtered"
}
FP_IMPORTS_FN[go]='fp_go_extract_imports'
