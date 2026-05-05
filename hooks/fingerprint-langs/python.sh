#!/bin/bash
# Language plugin: Python
# Category: (1) Named-import. Symbols are explicit in `from M import X`.
#
# Coverage:
#   - Exports: module-level `def NAME` / `class NAME` / `UPPERCASE_CONST = ...`.
#     Indented entries (methods, locals) are excluded by the leading-^ anchor.
#   - Imports: `from MODULE import NAME[, NAME [as ALIAS] ...]` — single-line
#     AND multi-line `from X import (\n a,\n b\n)` blocks. Sed pre-collapses
#     multi-line parenthesized blocks before the bulk grep.
#     Plain `import M` and `import M as N` are NOT counted: those import a
#     module object, not a symbol from the exports table, and resolving
#     `M.func` references back to the originally-defined function would
#     require alias tracking beyond grep (category-3, not implemented).
#
# Plugin contract: see top of build-codebase-fingerprint.sh.

FP_EXTENSIONS[python]='py'

# Dunders are method/attr conventions, not shared helpers; main / setup are
# conventional entry points (CLI / packaging); test_* would only appear if
# test-file exclusion missed something.
FP_DENYLIST[python]='^(__[A-Za-z0-9_]+__|main|setup|test_.*)$'

FP_CATEGORY[python]=1

fp_python_extract_exports() {
  list_source_files_for_lang python | while IFS= read -r f; do
    grep -nE '^(def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|[A-Z_][A-Z0-9_]*[[:space:]]*=)' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[python]}" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            name = ""
            if (match(line, /^(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
              tok = substr(line, RSTART, RLENGTH)
              n = split(tok, parts, /[[:space:]]+/)
              name = parts[n]
            } else if (match(line, /^[A-Z_][A-Z0-9_]*/)) {
              name = substr(line, RSTART, RLENGTH)
            }
            if (name == "") next
            if (length(name) < minlen) next
            if (name ~ denylist) next
            print name "\t" file ":" lineno
          }'
  done
}
FP_EXPORTS_FN[python]='fp_python_extract_exports'

fp_python_extract_imports() {
  local files_list="$1"
  local tmp_filtered
  tmp_filtered=$(mktemp -p "$_FP_TMPDIR")
  _filter_files_by_ext "$files_list" py > "$tmp_filtered"
  [ -s "$tmp_filtered" ] || return 0

  # Pre-collapse multi-line parenthesized imports — Python permits
  # `from X import (\n a,\n b,\n)` blocks across lines. Sed loops while the
  # buffer contains an opened-but-not-closed `from … import (`. After the
  # closing `)` arrives, embedded newlines collapse to spaces; the existing
  # awk parser strips the parens and splits by comma as before.
  local sed_collapse=':a; /^[[:space:]]*from[[:space:]]+\S+[[:space:]]+import[[:space:]]*\([^)]*$/{ N; ba; }; s/\n/ /g'

  while IFS= read -r f; do
    sed -E "$sed_collapse" "$f" 2>/dev/null \
      | grep -E '^[[:space:]]*from[[:space:]]+\S+[[:space:]]+import[[:space:]]+' \
      | sed "s|^|${f}:|"
  done < "$tmp_filtered" \
    | awk -F: '
    {
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      if (match(content, /^[0-9]+:/)) content = substr(content, RLENGTH + 1)
      sub(/^[[:space:]]*from[[:space:]]+\S+[[:space:]]+import[[:space:]]+/, "", content)
      gsub(/[()]/, "", content)
      sub(/[[:space:]]*#.*$/, "", content)
      n = split(content, parts, /,/)
      for (i = 1; i <= n; i++) {
        s = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        sub(/[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$/, "", s)
        if (s ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print file "\t" s
      }
    }'
}
FP_IMPORTS_FN[python]='fp_python_extract_imports'
