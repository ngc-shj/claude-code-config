#!/bin/bash
# Language plugin: Java
# Category: hybrid — imports name a specific class (category-1-like for our
# import-aware counting purposes) but body references use qualifier syntax
# (`Foo.method()`). For symbol-usage counting we only need to count import
# statements, which directly name the class.
#
# Coverage:
#   - Exports: column-0 `public (static|final|abstract|sealed)* (class|interface|enum|record) NAME`.
#     Method-level exports (public static methods/fields inside a class) are
#     NOT extracted — they're nested and need class-context tracking. The
#     class itself appearing in import statements is the practical R1/R2
#     anchor.
#   - Imports: `import (static)? FQDN.NAME;` — captures the trailing
#     identifier. For `import static com.example.Foo.bar;` the trailing
#     identifier is `bar` (the static member). For `import com.example.*;`
#     the trailing token is `*` and is dropped — wildcard imports cannot
#     enumerate which classes are pulled in without a Java-aware analyzer.
#
# Plugin contract: see top of build-codebase-fingerprint.sh.

FP_EXTENSIONS[java]='java'

# Conventional entry points and overridden Object methods that pattern-match
# as exports but don't belong in a shared-utility ranking. Test classes are
# usually filtered by the project test-dir layout (`src/test/java/`).
FP_DENYLIST[java]='^(Main|Application|App|toString|hashCode|equals|clone|finalize)$'

FP_CATEGORY[java]=1

fp_java_extract_exports() {
  list_source_files_for_lang java | while IFS= read -r f; do
    grep -nE '^[[:space:]]*public[[:space:]]+([a-z]+[[:space:]]+)*(class|interface|enum|record)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[java]}" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            if (match(line, /(class|interface|enum|record)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
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
FP_EXPORTS_FN[java]='fp_java_extract_exports'

fp_java_extract_imports() {
  local files_list="$1"
  local tmp_filtered
  tmp_filtered=$(mktemp -p "$_FP_TMPDIR")
  _filter_files_by_ext "$files_list" java > "$tmp_filtered"
  [ -s "$tmp_filtered" ] || return 0
  if command -v rg >/dev/null 2>&1; then
    xargs -d '\n' -a "$tmp_filtered" rg --no-heading -N --color=never \
      '^\s*import\s+(static\s+)?[A-Za-z_][A-Za-z0-9_.]*\s*;' 2>/dev/null
  else
    xargs -d '\n' -a "$tmp_filtered" grep -HnE \
      '^[[:space:]]*import[[:space:]]+(static[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*;' 2>/dev/null
  fi | awk -F: '
    {
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      if (match(content, /^[0-9]+:/)) content = substr(content, RLENGTH + 1)
      sub(/^[[:space:]]*import[[:space:]]+(static[[:space:]]+)?/, "", content)
      sub(/[[:space:]]*;.*$/, "", content)
      gsub(/[[:space:]]/, "", content)
      # content is now "com.example.Foo" or "com.example.*" — extract the
      # last dotted segment as the imported symbol name
      n = split(content, parts, ".")
      if (n < 1) next
      sym = parts[n]
      if (sym == "*" || sym == "") next
      if (sym ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print file "\t" sym
    }'
}
FP_IMPORTS_FN[java]='fp_java_extract_imports'
