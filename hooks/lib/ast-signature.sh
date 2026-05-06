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
  declare -gA AST_LANG_FIND_REFERENCES_BATCH_FN

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

# Generic jq-based diff helpers reused by non-TS plugins. Plugins only need
# to implement extract-* in their native parser/runtime; diff-* stays
# language-agnostic as long as the emitted schema matches the contract above.
_ast_write_json_tmp() {
  mktemp "${TMPDIR:-/tmp}/ast-signature.XXXXXX.json"
}

ast_diff_signatures_via_extract() {
  local extract_fn="$1"
  local base_file="$2"
  local head_file="$3"

  command -v jq >/dev/null 2>&1 || return 1

  local base_json head_json
  base_json=$(_ast_write_json_tmp) || return 1
  head_json=$(_ast_write_json_tmp) || {
    rm -f "$base_json"
    return 1
  }

  if ! "$extract_fn" "$base_file" >"$base_json"; then
    rm -f "$base_json" "$head_json"
    return 1
  fi
  if ! "$extract_fn" "$head_file" >"$head_json"; then
    rm -f "$base_json" "$head_json"
    return 1
  fi

  jq -c -n --slurpfile base "$base_json" --slurpfile head "$head_json" '
    def sig_key($s): (($s.owner // "") + "::" + $s.name);
    def sig_label($s):
      if (($s.owner // "") | length) > 0 then "\($s.owner).\($s.name)" else $s.name end;
    def first_by_key($items):
      reduce $items[] as $item
        ({};
         if has(sig_key($item)) then . else . + {(sig_key($item)): $item} end);
    def param_detail($before; $after; $idx):
      [
        if $before.type != $after.type then "type \($before.type) → \($after.type)" else empty end,
        if $before.optional != $after.optional then "optional \($before.optional) → \($after.optional)" else empty end,
        if $before.rest != $after.rest then "rest \($before.rest) → \($after.rest)" else empty end,
        if $before.hasDefault != $after.hasDefault then "default \($before.hasDefault) → \($after.hasDefault)" else empty end
      ]
      | map(select(. != null and . != ""))
      | if length > 0 then "#\($idx + 1) " + join(", ") else empty end;

    ($base[0] // []) as $baseSigs
    | ($head[0] // []) as $headSigs
    | first_by_key($baseSigs) as $baseByKey
    | first_by_key($headSigs) as $headByKey
    | [
        $baseByKey
        | to_entries[]
        | .key as $key
        | .value as $baseSig
        | ($headByKey[$key] // null) as $headSig
        | if $headSig == null then
            {
              name: $baseSig.name,
              owner: $baseSig.owner,
              kind: $baseSig.kind,
              line: $baseSig.line,
              changes: ["removed"],
              detail: "\(sig_label($baseSig)) removed",
              severity: "Major"
            }
          else
            ($baseSig.params | length) as $baseLen
            | ($headSig.params | length) as $headLen
            | (
                if $baseLen != $headLen then
                  {
                    changes: ["param-count"],
                    details: ["params \($baseLen) → \($headLen)"],
                    major:
                      if $headLen > $baseLen then
                        ($headSig.params[$baseLen:]
                          | map((.optional | not) and (.hasDefault | not) and (.rest | not))
                          | any)
                      else
                        false
                      end
                  }
                else
                  ([
                    range(0; $baseLen)
                    | param_detail($baseSig.params[.]; $headSig.params[.]; .)
                  ] | map(select(. != null and . != ""))) as $shapeDetails
                  | {
                      changes: (if ($shapeDetails | length) > 0 then ["param-shape"] else [] end),
                      details: $shapeDetails,
                      major: false
                    }
                end
              ) as $paramDiff
            | (
                if $baseSig.returnType != $headSig.returnType
                then ["return-type"]
                else []
                end
              ) as $returnChanges
            | (
                if $baseSig.returnType != $headSig.returnType
                then ["return \($baseSig.returnType) → \($headSig.returnType)"]
                else []
                end
              ) as $returnDetails
            | ($paramDiff.changes + $returnChanges) as $changes
            | if ($changes | length) == 0 then
                empty
              else
                {
                  name: $headSig.name,
                  owner: $headSig.owner,
                  kind: $headSig.kind,
                  line: $headSig.line,
                  changes: $changes,
                  detail: (($paramDiff.details + $returnDetails) | join("; ")),
                  severity: (if $paramDiff.major then "Major" else "Minor" end)
                }
              end
          end
      ]
  '

  local status=$?
  rm -f "$base_json" "$head_json"
  return "$status"
}

ast_diff_enums_via_extract() {
  local extract_fn="$1"
  local base_file="$2"
  local head_file="$3"

  command -v jq >/dev/null 2>&1 || return 1

  local base_json head_json
  base_json=$(_ast_write_json_tmp) || return 1
  head_json=$(_ast_write_json_tmp) || {
    rm -f "$base_json"
    return 1
  }

  if ! "$extract_fn" "$base_file" >"$base_json"; then
    rm -f "$base_json" "$head_json"
    return 1
  fi
  if ! "$extract_fn" "$head_file" >"$head_json"; then
    rm -f "$base_json" "$head_json"
    return 1
  fi

  jq -c -n --slurpfile base "$base_json" --slurpfile head "$head_json" '
    def first_by_name($items):
      reduce $items[] as $item
        ({};
         if has($item.name) then . else . + {($item.name): $item} end);

    ($base[0] // []) as $baseEnums
    | ($head[0] // []) as $headEnums
    | first_by_name($baseEnums) as $baseByName
    | first_by_name($headEnums) as $headByName
    | [
        $baseByName
        | to_entries[]
        | .key as $name
        | .value as $baseEnum
        | ($headByName[$name] // null) as $headEnum
        | select($headEnum != null)
        | ($baseEnum.members | map(.name)) as $baseMembers
        | ($headEnum.members | map(.name)) as $headMembers
        | {
            name: $headEnum.name,
            line: $headEnum.line,
            added: ($headMembers - $baseMembers),
            removed: ($baseMembers - $headMembers)
          }
        | select((.added | length) > 0 or (.removed | length) > 0)
      ]
  '

  local status=$?
  rm -f "$base_json" "$head_json"
  return "$status"
}

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

# ast_find_references_batch <inputJsonFile> → JSON array of resolved
# references (schema: see ast-runner.js find-references-batch op). The
# language is selected by the FIRST query's declFile extension; mixed-
# language batches are not supported in v1 (queries should be grouped by
# language at the call site). Non-TS plugins intentionally do not register
# this handler yet — symbol resolution for Python / Go / Java is deferred to
# follow-up work with language-specific tooling. Returns 1 if unavailable.
ast_find_references_batch() {
  local input_json_file="$1"
  # Peek at the first query to determine language. Falls back to
  # inspecting the file via jq if available; otherwise relies on the
  # caller having already filtered by language.
  local sample_decl=""
  if command -v jq >/dev/null 2>&1; then
    sample_decl=$(jq -r '.[0].declFile // empty' "$input_json_file" 2>/dev/null)
  fi
  [ -z "$sample_decl" ] && return 1
  local lang
  lang=$(ast_lang_for_file "$sample_decl") || return 1
  local avail_fn="${AST_LANG_AVAILABLE_FN[$lang]:-}"
  [ -n "$avail_fn" ] && "$avail_fn" || return 1
  local fn="${AST_LANG_FIND_REFERENCES_BATCH_FN[$lang]:-}"
  [ -n "$fn" ] || return 1
  "$fn" "$input_json_file"
}
