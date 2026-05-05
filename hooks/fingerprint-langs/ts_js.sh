#!/bin/bash
# Language plugin: TypeScript / JavaScript
# Category: (1) Named-import. Symbols are explicit in `import { X } from 'y'`.
#
# Coverage:
#   - Exports: top-level
#       export (function|const|class|type|interface|enum) NAME
#       export default (async)? (function\*?|class) NAME            (named default)
#       export { foo[, bar [as baz]] };                              (local re-export)
#     `export default <expr>` (anonymous default) is unrecoverable and skipped.
#   - Imports/re-exports:
#       import { X[, Y as Z, type W] } from 'pkg'
#       import NAME from 'pkg'                       (default import)
#       import NAME, { X } from 'pkg'                (mixed default + named)
#       export { X } from 'pkg'                      (re-export)
#     Single-line AND multi-line — sed pre-collapses multi-line
#     `import {\n a,\n b\n} from` blocks before the bulk grep so a single
#     regex covers both shapes. Default imports are name-counted only —
#     module-path → file-path resolution is NOT performed (tsconfig paths,
#     index file resolution, etc., would be required). Same false-positive
#     surface as named imports: two modules exporting the same name compete
#     for the single def_file slot in the aggregator.
#   - `import * as NS from 'pkg'` (namespace import) is NOT counted —
#     it imports a module object, not a symbol from the exports table.
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
    # Pass 1: declaration-form exports — covers both regular and named
    # default exports (`export function NAME`, `export default function NAME`,
    # `export default async function* NAME`, `export default class NAME`,
    # plus const/type/interface/enum). Awk's whitespace-split picks the last
    # token, which is always NAME regardless of how many keywords precede.
    grep -nE '^[[:space:]]*export[[:space:]]+(default[[:space:]]+(async[[:space:]]+)?(function\*?|class)|function|const|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[ts_js]}" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            if (match(line, /export[[:space:]]+(default[[:space:]]+(async[[:space:]]+)?(function\*?|class)|function|const|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
              tok = substr(line, RSTART, RLENGTH)
              n = split(tok, parts, /[[:space:]]+/)
              name = parts[n]
              if (length(name) < minlen) next
              if (name ~ denylist) next
              print name "\t" file ":" lineno
            }
          }'

    # Pass 2: local re-export — `export { foo[, bar [as baz]] };` with NO
    # `from` clause. The end-of-line anchor distinguishes from `export {...}
    # from '...'` (which is a re-export from another module — already counted
    # on the import side). For `export { local as exposed }` the EXPORT name
    # (`exposed`, after `as`) is what consumers will import, so we keep that.
    grep -nE '^[[:space:]]*export[[:space:]]*\{[^}]+\}[[:space:]]*;?[[:space:]]*$' "$f" 2>/dev/null \
      | awk -v file="$f" -v denylist="${FP_DENYLIST[ts_js]}" -v minlen="$SYMBOL_MIN_LENGTH" '
          {
            line = $0
            sub(/:.*/, "", $1); lineno = $1
            sub(/^[0-9]+:[[:space:]]*/, "", line)
            if (match(line, /\{[^}]+\}/)) {
              body = substr(line, RSTART + 1, RLENGTH - 2)
              n = split(body, parts, /,/)
              for (i = 1; i <= n; i++) {
                s = parts[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                sub(/^type[[:space:]]+/, "", s)
                # Keep the EXPORTED name: strip everything up to and including " as "
                sub(/^.*[[:space:]]+as[[:space:]]+/, "", s)
                if (s !~ /^[A-Za-z_][A-Za-z0-9_]*$/) continue
                if (length(s) < minlen) continue
                if (s ~ denylist) continue
                print s "\t" file ":" lineno
              }
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

  # Pre-collapse multi-line `import {\n a,\n b\n} from` blocks via sed before
  # grep, so a single-line regex covers both shapes. The sed loop accumulates
  # lines while the buffer starts with import/export-brace AND has no closing
  # `}`; once `}` appears the loop exits and embedded newlines collapse to
  # spaces. Single-line imports are unaffected (the pattern doesn't match
  # them, no accumulation happens).
  local sed_collapse=':a; /^[[:space:]]*(import|export)[[:space:]]+(type[[:space:]]+)?\{[^}]*$/{ N; ba; }; s/\n/ /g'

  # Grep pattern matches both shapes:
  #   import { X } from / export { X } from / import type { X } from
  #   import NAME from / import NAME, { X } from
  # The default-NAME shape pairs with `export default function NAME` on the
  # define side: without it the round-trip would never close and default
  # exports would not surface in the symbol section. Path resolution is NOT
  # performed — we just emit (file, NAME) and let count_symbol_usage's
  # def_file lookup drop references to names not in the project's exports
  # table. Same false-positive surface as named imports (two modules
  # exporting the same name compete for the def_file slot).
  local grep_pat='^[[:space:]]*(import|export)[[:space:]]+(type[[:space:]]+)?(\{[^}]+\}|[A-Za-z_][A-Za-z0-9_]*([[:space:]]*,[[:space:]]*\{[^}]+\})?)[[:space:]]+from'

  while IFS= read -r f; do
    sed -E "$sed_collapse" "$f" 2>/dev/null \
      | grep -E "$grep_pat" \
      | sed "s|^|${f}:|"
  done < "$tmp_filtered" \
    | awk -F: '
    {
      idx = index($0, ":")
      if (idx == 0) next
      file = substr($0, 1, idx - 1)
      content = substr($0, idx + 1)
      if (match(content, /^[0-9]+:/)) content = substr(content, RLENGTH + 1)
      # Strip leading whitespace + import/export keyword + optional `type`
      sub(/^[[:space:]]*(import|export)[[:space:]]+/, "", content)
      sub(/^type[[:space:]]+/, "", content)
      # Default-import name (if present): an identifier before `from` or `,`
      if (match(content, /^[A-Za-z_][A-Za-z0-9_]*/)) {
        name = substr(content, RSTART, RLENGTH)
        rest = substr(content, RSTART + RLENGTH)
        if (rest ~ /^([[:space:]]+from|[[:space:]]*,)/) {
          print file "\t" name
        }
        # Strip the default name + optional comma so the named-imports block
        # is exposed for the next match() call.
        sub(/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*,?[[:space:]]*/, "", content)
      }
      # Named imports: `{ X, Y as Z, type W }`
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
