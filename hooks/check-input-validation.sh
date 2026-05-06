#!/bin/bash
# Detect schema-validation gaps in newly added HTTP mutation boundaries.
#
# RS3 (Input validation at boundaries) fires when a new mutation endpoint
# accepts user input without schema-level validation, while sibling
# endpoints in the same peer group do validate. The signal is asymmetric
# validation in a peer group of HTTP boundaries — analogous to R4's
# asymmetric dispatch signal but for input safety instead of event emission.
#
# Boundary classification
#   A function is a boundary site when its name matches an HTTP mutation
#   verb (POST / PUT / PATCH / DELETE), with optional `handle` prefix.
#   This catches NextJS / Hono / Express / SvelteKit-style route handlers
#   where the verb lives in the function/export name. Read-only verbs
#   (GET / HEAD / OPTIONS) are excluded from v1 — read endpoints have
#   higher false-positive rate (raw `searchParams.get(...)` without
#   schema parsing is common and not always wrong); RS3 prioritizes
#   write endpoints where unvalidated input flows into state changes.
#
# Validation classification
#   A boundary is a validator when its body contains a schema-validation
#   primitive call:
#     - Generic schema methods: `<schema>.parse(`, `.safeParse(`,
#       `.validate(`, `.decode(`, `.check(` (Zod / Yup / Joi / io-ts /
#       runtypes / valibot conventions).
#     - Library factories: `z.<type>(...)` (Zod), `Joi.<type>(...)`,
#       `Yup.<type>(...)`, `v.<type>(...)` (valibot), `t.<type>(...)`
#       (io-ts).
#     - class-validator decorators: `@IsString` / `@IsNumber` /
#       `@IsArray` / `@ValidateNested` / etc.
#   The skip list excludes `JSON.parse`, `Date.parse`, `Number.parseInt`,
#   `URL.parse`, etc. — stdlib methods that share the `.parse(` shape but
#   do not perform schema validation.
#
# Detection pipeline (mirrors check-event-dispatch.sh)
#   1. For each changed source file at HEAD, walk every named function
#      at a valid declaration depth.
#   2. Classify boundary (HTTP mutation verb) AND validator. Drop records
#      that are not boundaries.
#   3. Mark NEW boundaries: start_line in diff `+` and name absent from
#      diff `-` lines.
#   4. Group by (file, scope) AND by `<dir:parent-of-verb-dir>` for
#      route-style files at leaf verb directories. For each NEW
#      non-validating boundary, if its peer group contains ≥1 sibling
#      that IS a validator, emit Major — peer group has established a
#      validation convention and the new boundary breaks it.
#
# Anti-FP measures
#   - Body-edit suppression: boundary names on diff `-` lines treated as
#     existing, not new.
#   - Transitive validation: a non-validating boundary that calls another
#     same-file boundary which validates is auto-promoted (mirrors R4
#     transitive-dispatch handling).
#   - Validation skip list: stdlib `parse` / `validate` methods that
#     do not perform schema validation are excluded.
#   - Helper / private skip and test-path exclusion as in R4.
#   - Leaf-verb-dir gate: directory promotion only when the file's parent
#     directory has no subdirectories and no other source files apart
#     from `route.<ext>` and `route.{test,spec}.<ext>`.
#
# Severity
#   - Major. Reviewer escalates to Critical only if the unvalidated
#     boundary is in a security-relevant authn / authz / consent flow
#     (manual call).
#
# Out of scope
#   - Middleware-based validation (validation done in a wrapping HOF or
#     handler chain rather than the handler body). When the project
#     uses such middleware, set EXTRA_VALIDATION_PRIMITIVES to include
#     the wrapper signature so its presence in handler files counts as
#     validation.
#   - Read endpoints (GET / HEAD / OPTIONS).
#   - GraphQL / gRPC / message-queue boundaries; HTTP only in v1.
#
# Usage: bash check-input-validation.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   EXTRA_VALIDATION_PRIMITIVES — pipe-separated additional patterns that
#                          count as schema validation (project-specific
#                          wrappers, e.g. `validateBody|withSchema`)
#   EXTRA_NON_VALIDATION_PRIMITIVES — pipe-separated patterns to skip
#                          from validation classification
#   EXTRA_EXCLUDE_PATH_RE — additional paths to drop from analysis
#   BODY_LINE_CAP (default 120) — max lines scanned per function body
#
# Output: human-scannable findings with peer-evidence rows. Exit 0 always.

set -u

_CED_TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$_CED_TMPDIR'" EXIT

BASE_REF="${1:-main}"
BODY_LINE_CAP="${BODY_LINE_CAP:-120}"

TRUSTED_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$TRUSTED_ROOT"

git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1 || {
  echo "Error: '$BASE_REF' is not a valid git ref" >&2
  exit 1
}

# HTTP mutation verbs — function names that mark a write boundary. Same
# regex as check-event-dispatch.sh's HTTP_MUT_RE; covers NextJS / Hono /
# Express / SvelteKit route exports. Read-only verbs (GET / HEAD /
# OPTIONS) are intentionally excluded — RS3 prioritizes write endpoints
# where unvalidated input flows into state changes.
HTTP_MUT_RE='^(handle)?(POST|PUT|PATCH|DELETE)$'

# Schema-validation primitive patterns. Default set is intentionally
# narrow — only patterns with high precision:
#   - Zod-style generic methods: `<schema>.parse(`, `.safeParse(`. The
#     `.parse(` shape collides with `JSON.parse` / `Date.parse` / etc.,
#     suppressed by VALIDATION_SKIP_RE on the same line.
#   - Library factories at body level: `z.<type>(`, `Joi.<type>(`,
#     `Yup.<type>(`, `v.<type>(` (valibot), `t.<type>(` (io-ts). When a
#     handler defines its schema inline (`const Body = z.object({...})`),
#     this catches it even if the `.parse(` call lives in a helper.
#   - class-validator decorators: `@IsString` / `@IsNumber` /
#     `@ValidateNested` / etc.
#
# Patterns INTENTIONALLY excluded from defaults — too many FPs without
# context: `.validate(` (collides with `auth.validate()`,
# `permission.validate()`, etc.), `.decode(` (io-ts factory `t.type(`
# already covers), `.check(` (collides with `policy.check()`,
# `permission.check()`, `guard.check()`, etc.).
# Codebases that rely on these can add via EXTRA_VALIDATION_PRIMITIVES.
VALIDATION_PRIMITIVES_RE='[.](parse|safeParse)[[:space:]]*[(]|\bz[.](object|string|number|boolean|array|union|literal|enum|nativeEnum|infer|date|bigint|tuple|record|map|optional|nullable)\b|\bJoi[.](object|string|number|boolean|array|alternatives|symbol|date|any)\b|\bYup[.](object|string|number|boolean|array|date)\b|\bv[.](object|string|number|boolean|array|parse|safeParse)\b|\bt[.](type|partial|interface|exact|union|intersection|readonly)\b|@(IsString|IsNumber|IsBoolean|IsArray|IsEmail|IsOptional|IsEnum|IsUUID|IsDateString|IsObject|IsDate|IsNotEmpty|MinLength|MaxLength|Matches|Min|Max|Length|ValidateNested|Type)[(]'
[ -n "${EXTRA_VALIDATION_PRIMITIVES:-}" ] && VALIDATION_PRIMITIVES_RE="${VALIDATION_PRIMITIVES_RE}|${EXTRA_VALIDATION_PRIMITIVES}"
# gawk treats `\b` in regex as a backspace character, not a word boundary.
# Rewrite to gawk's `\y` word boundary. The replacement must be `\\y`
# (literally 2 backslashes + y) so awk's string-unescape produces `\y`
# in the regex. Plus silence other gawk escape warnings (`\.`, `\(`).
VALIDATION_PRIMITIVES_RE="${VALIDATION_PRIMITIVES_RE//\\b/\\\\y}"
VALIDATION_PRIMITIVES_RE="${VALIDATION_PRIMITIVES_RE//\\./[.]}"
VALIDATION_PRIMITIVES_RE="${VALIDATION_PRIMITIVES_RE//\\(/[(]}"

# Validation deny-list: stdlib methods that share the `.parse(` shape
# but do not perform schema validation. JSON.parse parses a string,
# doesn't shape-check. Date.parse / Number.parseInt / URL.parse are
# coercions, not validation.
VALIDATION_SKIP_RE='\b(JSON|Date|Number|URL|Url|querystring|qs|path|process|crypto|jwt|JWT)[.](parse|safeParse|parseInt|parseFloat)\b|\bparseInt[(]|\bparseFloat[(]'
[ -n "${EXTRA_NON_VALIDATION_PRIMITIVES:-}" ] && VALIDATION_SKIP_RE="${VALIDATION_SKIP_RE}|${EXTRA_NON_VALIDATION_PRIMITIVES}"
VALIDATION_SKIP_RE="${VALIDATION_SKIP_RE//\\b/\\\\y}"
VALIDATION_SKIP_RE="${VALIDATION_SKIP_RE//\\./[.]}"
VALIDATION_SKIP_RE="${VALIDATION_SKIP_RE//\\(/[(]}"

# Names we exclude from analysis entirely — internal helpers and private
# impl details that are not user-facing route boundaries.
SKIP_NAME_RE='([Ii]nternal|[Hh]elper|[Uu]tils?|Impl|[Pp]rivate)$|^_'

# Source-code whitelist. Tests are intentionally excluded — R4 is about
# production mutation symmetry, not test-double coverage.
SOURCE_EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|kts|scala|cs|swift|php)$'
EXCLUDE_PATH_RE='^(.+/)?(migrations?/|migrate/|versions/|vendor/|node_modules/|__tests__/|test/|tests/|spec/|specs/)|.+\.generated\.|.+_generated\.|.+\.gen\.|.+\.test\.|.+_test\.|.+\.spec\.|.+_spec\.'
[ -n "${EXTRA_EXCLUDE_PATH_RE:-}" ] && EXCLUDE_PATH_RE="${EXCLUDE_PATH_RE}|${EXTRA_EXCLUDE_PATH_RE}"

CHANGED_FILES="$_CED_TMPDIR/changed.txt"
git diff --name-only "$BASE_REF...HEAD" 2>/dev/null \
  | grep -E "$SOURCE_EXT_RE" \
  | grep -vE "$EXCLUDE_PATH_RE" \
  > "$CHANGED_FILES"

CHANGED_COUNT=$(wc -l < "$CHANGED_FILES")

echo "=== Input-Validation Boundary Check (RS3) ==="
echo "Base: $BASE_REF"
echo "Source files in diff: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "  (no source files in diff; nothing to check)"
  echo "=== End Input-Validation Boundary Check ==="
  exit 0
fi

# Inventory format (TSV):
#   file <TAB> scope <TAB> name <TAB> start_line <TAB> end_line <TAB>
#   validates <TAB> validation_match <TAB> _unused <TAB> is_new
INVENTORY="$_CED_TMPDIR/inventory.tsv"
: > "$INVENTORY"

# Per-file added-line set (line numbers added in this diff, file-scoped).
NEW_LINES_DIR="$_CED_TMPDIR/added"
mkdir -p "$NEW_LINES_DIR"

# Encode file path safely as a filename.
_safe_fname() { echo "$1" | tr '/' '_' | tr -c 'A-Za-z0-9_.-' '_'; }

# Build inventory + added-lines set per changed file.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ ! -f "$f" ] && continue  # deleted file; skip

  # Added lines for this file.
  enc=$(_safe_fname "$f")
  added_file="$NEW_LINES_DIR/$enc.added"
  git diff "$BASE_REF...HEAD" --unified=0 -- "$f" 2>/dev/null \
    | awk '
        /^@@/ {
          if (match($0, /\+[0-9]+/)) {
            lineno = substr($0, RSTART + 1, RLENGTH - 1) + 0
          }
          next
        }
        /^\+\+\+/ { next }
        /^\+/ { print lineno; lineno++ }
      ' > "$added_file"

  # Names of HTTP-boundary tokens removed in this diff (per file). When a
  # boundary function's body is edited (not added), the `-` line contains
  # the same definition; the boundary is still a body-edit, not a fresh
  # boundary. Without this, every body-edit on a non-validating boundary
  # would re-flag forever.
  removed_names_file="$NEW_LINES_DIR/$enc.removednames"
  git diff "$BASE_REF...HEAD" --unified=0 -- "$f" 2>/dev/null \
    | awk '/^-[^-]/' \
    | grep -oE "\\b(handle)?(POST|PUT|PATCH|DELETE)\\b" 2>/dev/null \
    | sort -u > "$removed_names_file"

  ext="${f##*.}"
  case "$ext" in
    go)         lang=go ;;
    py)         lang=python ;;
    rb)         lang=ruby ;;
    *)          lang=cfamily ;;
  esac

  # Single awk pass per file: extract HTTP-boundary function records with
  # body spans + validation detection. Output rows are appended to INVENTORY.
  awk -v file="$f" \
      -v lang="$lang" \
      -v http_mut_re="$HTTP_MUT_RE" \
      -v val_re="$VALIDATION_PRIMITIVES_RE" \
      -v val_skip_re="$VALIDATION_SKIP_RE" \
      -v skip_re="$SKIP_NAME_RE" \
      -v body_cap="$BODY_LINE_CAP" \
      -v added_file="$added_file" \
      -v removed_names_file="$removed_names_file" '
    BEGIN {
      IGNORECASE = 0
      # Load added-line set for this file.
      while ((getline ln < added_file) > 0) added[ln+0] = 1
      close(added_file)
      # Load removed-name set: function names that appeared on `-` lines of
      # this diff for this file. A function with name in this set is a
      # body-edit, not a fresh mutation.
      while ((getline ln < removed_names_file) > 0) removed_names[ln] = 1
      close(removed_names_file)

      # Class scope tracking for cfamily. brace_depth = current { nesting.
      # class_open[d] = name of class opened at depth d (or empty).
      brace_depth = 0
      cur_class = ""

      # Function-record buffer: when we detect a function start, we open
      # a record and accumulate its body text, closing when the brace
      # balance returns to the start depth (cfamily/go) or indent drops
      # to/below def indent (python/ruby).
      open_func = 0
    }

    # Boundary classification: HTTP mutation verb in name. Read verbs
    # (GET / HEAD / OPTIONS) intentionally excluded — RS3 v1 covers
    # write boundaries only.
    function is_boundary_site(name) {
      return (name ~ http_mut_re)
    }

    function emit_record(rec_file, rec_scope, rec_name, rec_start, rec_end, rec_body,    n, lines, i, line, has_val, val_match, is_new) {
      # Drop non-boundary functions before any further work.
      if (!is_boundary_site(rec_name)) return
      has_val = 0
      val_match = ""
      n = split(rec_body, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        # Skip if the line is a stdlib coercion (JSON.parse / Date.parse /
        # parseInt / parseFloat / etc.) before checking validation match.
        if (line ~ val_skip_re) {
          # Strip the stdlib match and re-check; if the line ALSO has a
          # genuine validation primitive elsewhere, count it.
          stripped_line = line
          gsub(val_skip_re, "", stripped_line)
          if (stripped_line ~ val_re) {
            has_val = 1
            if (match(stripped_line, val_re)) {
              val_match = substr(stripped_line, RSTART, RLENGTH)
              gsub(/^[[:space:]]+/, "", val_match)
              gsub(/[[:space:]]+$/, "", val_match)
            }
            break
          }
          continue
        }
        if (line ~ val_re) {
          has_val = 1
          if (match(line, val_re)) {
            val_match = substr(line, RSTART, RLENGTH)
            gsub(/^[[:space:]]+/, "", val_match)
            gsub(/[[:space:]]+$/, "", val_match)
          }
          break
        }
      }
      # is_new gate: start line newly added AND name not seen on a `-`
      # line in the diff (rules out body-edits to existing boundaries).
      is_new = ((rec_start in added) && !(rec_name in removed_names)) ? 1 : 0
      printf "%s\t%s\t%s\t%d\t%d\t%d\t%s\t\t%d\n", \
             rec_file, rec_scope, rec_name, rec_start, rec_end, has_val, val_match, is_new
    }

    # Strip line/string context for class tracking + brace counting in
    # cfamily. Preserves enough structure for shallow detection.
    function strip_cfamily(s,    out) {
      out = s
      sub(/\/\/.*$/, "", out)
      gsub(/"[^"\\]*(\\.[^"\\]*)*"/, "\"\"", out)
      gsub(/'\''[^'\''\\]*(\\.[^'\''\\]*)*'\''/, "''", out)
      return out
    }

    # ---------------- cfamily (TS/JS/Java/Kotlin/Scala/C#/Swift/PHP/Rust) ----------------
    lang == "cfamily" {
      raw = $0
      lineno = NR
      stripped = strip_cfamily(raw)

      # Class-name latch: when a `class X` token appears, remember it; at
      # next `{` we push it onto the scope stack at the current depth.
      if (match(stripped, /\<class[[:space:]]+([A-Z_][A-Za-z0-9_]*)/) ||
          match(stripped, /\<interface[[:space:]]+([A-Z_][A-Za-z0-9_]*)/) ||
          match(stripped, /\<impl[[:space:]]+([A-Z_][A-Za-z0-9_]*)/) ||
          match(stripped, /\<object[[:space:]]+([A-Z_][A-Za-z0-9_]*)/)) {
        # Extract the captured name (awk lacks RSTART for groups; re-extract).
        tmp = substr(stripped, RSTART, RLENGTH)
        sub(/^[^[:space:]]+[[:space:]]+/, "", tmp)
        pending_class = tmp
      }

      # Count braces on stripped line. Open first then close — class push
      # happens on the open count of the latch line.
      open_n = gsub(/\{/, "{", stripped)
      close_n = gsub(/\}/, "}", stripped)

      if (pending_class != "" && open_n > 0) {
        scope_stack[brace_depth + 1] = pending_class
        pending_class = ""
      }
      brace_depth_before = brace_depth
      brace_depth += open_n

      # Determine current scope = innermost non-empty in scope_stack[]
      # whose key ≤ brace_depth_before+1.
      cur_class = ""
      for (d = brace_depth; d >= 1; d--) {
        if (d in scope_stack && scope_stack[d] != "") {
          cur_class = scope_stack[d]
          break
        }
      }
      cur_scope = (cur_class != "") ? cur_class : "<file>"

      # Mutation function detection. Multiple shapes; keep regex narrow
      # to suppress generic identifier matches.
      func_name = ""
      # 1. function name(...)  /  async function name(...)
      if (match(raw, /(^|[^A-Za-z0-9_])(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/)) {
        seg = substr(raw, RSTART, RLENGTH)
        if (match(seg, /function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
          tok = substr(seg, RSTART, RLENGTH); sub(/function[[:space:]]+/, "", tok)
          func_name = tok
        }
      }
      # 2. const/let/var name = (..) =>  /  const name = async (..) =>
      else if (match(raw, /(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(/)) {
        seg = substr(raw, RSTART, RLENGTH)
        if (match(seg, /(const|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
          tok = substr(seg, RSTART, RLENGTH); sub(/(const|let|var)[[:space:]]+/, "", tok)
          func_name = tok
        }
      }
      # 3. Class method shorthand: optional async/static + name(args) {
      #    Require leading whitespace to avoid matching top-level expr stmts.
      else if (match(raw, /^[[:space:]]+((async|static|public|private|protected|override)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/)) {
        seg = substr(raw, RSTART, RLENGTH)
        if (match(seg, /([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/)) {
          tok = substr(seg, RSTART, RLENGTH); sub(/[[:space:]]*\($/, "", tok)
          # Reject control-flow / common lexical keywords that match the shape.
          if (tok ~ /^(if|for|while|switch|catch|return|throw|new|typeof|delete|void|yield|await|case|of|in)$/) {
            tok = ""
          }
          func_name = tok
        }
      }

      # Restrict function-def detection to valid declaration depths:
      # top-level (brace_depth_before == 0) or directly inside a class
      # body (brace_depth_before is a key in scope_stack). Method-body
      # function-call lines like `someThing(x);` syntactically match
      # the method-shorthand pattern but are deeper than any class
      # scope; excluding them avoids false-positive function records.
      if (func_name != "" && func_name !~ skip_re) {
        valid_depth = (brace_depth_before == 0) || (brace_depth_before in scope_stack)
        if (!valid_depth) func_name = ""
      } else {
        func_name = ""
      }

      if (func_name != "") {
        # Open a function-record window: collect the body until brace
        # depth returns to brace_depth_before (start-of-line depth).
        if (open_func) {
          # Edge case: nested function inside a body — close the
          # outer first.
          emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
          open_func = 0
        }
        of_scope = cur_scope
        of_name = func_name
        of_start = lineno
        of_start_depth = brace_depth_before
        of_body = raw
        of_lines = 1
        open_func = 1
      } else if (open_func) {
        of_body = of_body "\n" raw
        of_lines++
        # If body cap exceeded without finding close, force-close.
        if (of_lines > body_cap) {
          emit_record(file, of_scope, of_name, of_start, lineno, of_body)
          open_func = 0
        }
      }

      brace_depth -= close_n

      # Pop scope_stack entries whose depth has been exited.
      for (d in scope_stack) {
        if (d > brace_depth) delete scope_stack[d]
      }

      # If open_func and brace_depth has returned to of_start_depth, close.
      if (open_func && brace_depth <= of_start_depth) {
        emit_record(file, of_scope, of_name, of_start, lineno, of_body)
        open_func = 0
      }
      next
    }

    # ---------------- Go ----------------
    lang == "go" {
      lineno = NR
      raw = $0
      # func (r *T) Name(...) — accept any name (exported or not); is_mutation_site
      # at emit_record handles classification.
      if (match(raw, /^func[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\*?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        seg = substr(raw, RSTART, RLENGTH)
        # Receiver: extract from "(...)" — last identifier (Type).
        recv = seg
        match(recv, /\([^)]*\)/)
        recv_full = substr(recv, RSTART + 1, RLENGTH - 2)
        if (match(recv_full, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) {
          recv = substr(recv_full, RSTART, RLENGTH)
          gsub(/[[:space:]]/, "", recv)
        } else {
          recv = ""
        }
        nm = seg; sub(/.*\)[[:space:]]+/, "", nm); sub(/[[:space:](].*/, "", nm)
        if (nm != "" && nm !~ skip_re) {
          if (open_func) {
            emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
          }
          of_scope = recv
          of_name = nm
          of_start = lineno
          of_start_depth = 0
          of_body = raw
          of_lines = 1
          of_brace = 0
          for (i = 1; i <= length(raw); i++) {
            c = substr(raw, i, 1)
            if (c == "{") of_brace++
            else if (c == "}") of_brace--
          }
          open_func = (of_brace > 0) ? 1 : 0
          if (!open_func) emit_record(file, of_scope, of_name, of_start, lineno, of_body)
        }
        next
      }
      # func Name(...) (package-level) — accept any name; classify at emit.
      if (match(raw, /^func[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/)) {
        seg = substr(raw, RSTART, RLENGTH)
        nm = seg; sub(/^func[[:space:]]+/, "", nm); sub(/[[:space:]].*/, "", nm)
        if (nm != "" && nm !~ skip_re) {
          if (open_func) {
            emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
          }
          of_scope = "<file>"
          of_name = nm
          of_start = lineno
          of_body = raw
          of_lines = 1
          of_brace = 0
          for (i = 1; i <= length(raw); i++) {
            c = substr(raw, i, 1)
            if (c == "{") of_brace++
            else if (c == "}") of_brace--
          }
          open_func = (of_brace > 0) ? 1 : 0
          if (!open_func) emit_record(file, of_scope, of_name, of_start, lineno, of_body)
        }
        next
      }
      if (open_func) {
        of_body = of_body "\n" raw
        of_lines++
        for (i = 1; i <= length(raw); i++) {
          c = substr(raw, i, 1)
          if (c == "{") of_brace++
          else if (c == "}") of_brace--
        }
        if (of_brace <= 0 || of_lines > body_cap) {
          emit_record(file, of_scope, of_name, of_start, lineno, of_body)
          open_func = 0
        }
      }
      next
    }

    # ---------------- Python ----------------
    lang == "python" {
      lineno = NR
      raw = $0
      # Track class scope by indent.
      if (match(raw, /^([[:space:]]*)class[[:space:]]+([A-Z_][A-Za-z0-9_]*)/)) {
        cls_indent_str = substr(raw, RSTART, RLENGTH)
        # Indent length = leading whitespace.
        ws = cls_indent_str; sub(/[^[:space:]].*/, "", ws); cls_ind = length(ws)
        cn = cls_indent_str; sub(/^[[:space:]]*class[[:space:]]+/, "", cn); sub(/[[:space:](:].*/, "", cn)
        py_class[cls_ind] = cn
        # Drop deeper class entries.
        for (k in py_class) if (k+0 > cls_ind) delete py_class[k]
      }
      # def name(...) — possibly inside a class. Accept any name; classify at emit.
      if (match(raw, /^([[:space:]]*)((async[[:space:]]+)?def[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/)) {
        seg = substr(raw, RSTART, RLENGTH)
        ws = seg; sub(/[^[:space:]].*/, "", ws); fn_ind = length(ws)
        nm = seg; sub(/.*def[[:space:]]+/, "", nm); sub(/[[:space:]]*\(.*/, "", nm)
        if (nm != "" && nm !~ skip_re) {
          if (open_func) {
            emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
          }
          # Enclosing class = py_class[k] with largest k < fn_ind.
          best_k = -1; best_v = ""
          for (k in py_class) if (k+0 < fn_ind && k+0 > best_k) { best_k = k+0; best_v = py_class[k] }
          of_scope = (best_v != "") ? best_v : "<file>"
          of_name = nm
          of_start = lineno
          of_start_indent = fn_ind
          of_body = raw
          of_lines = 1
          open_func = 1
          next
        }
      }
      if (open_func) {
        # Close when a non-blank line appears at indent ≤ start indent.
        nb = raw
        sub(/[[:space:]]+$/, "", nb)
        if (nb != "" && raw !~ /^[[:space:]]*#/) {
          ws = raw; sub(/[^[:space:]].*/, "", ws); cur_ind = length(ws)
          if (cur_ind <= of_start_indent) {
            emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
            open_func = 0
            next
          }
        }
        of_body = of_body "\n" raw
        of_lines++
        if (of_lines > body_cap) {
          emit_record(file, of_scope, of_name, of_start, lineno, of_body)
          open_func = 0
        }
      }
      next
    }

    # ---------------- Ruby ----------------
    lang == "ruby" {
      lineno = NR
      raw = $0
      if (match(raw, /^([[:space:]]*)class[[:space:]]+([A-Z_][A-Za-z0-9_]*)/)) {
        seg = substr(raw, RSTART, RLENGTH)
        cn = seg; sub(/^[[:space:]]*class[[:space:]]+/, "", cn); sub(/[[:space:]<].*/, "", cn)
        rb_class_stack[++rb_top] = cn
      }
      if (match(raw, /^([[:space:]]*)def[[:space:]]+(self\.)?([a-z_][A-Za-z0-9_]*[!?=]?)/)) {
        seg = substr(raw, RSTART, RLENGTH)
        nm = seg; sub(/^[[:space:]]*def[[:space:]]+(self\.)?/, "", nm); sub(/[[:space:](].*/, "", nm)
        if (nm != "" && nm !~ skip_re) {
          if (open_func) {
            emit_record(file, of_scope, of_name, of_start, lineno - 1, of_body)
          }
          of_scope = (rb_top > 0) ? rb_class_stack[rb_top] : "<file>"
          of_name = nm
          of_start = lineno
          of_body = raw
          of_lines = 1
          open_func = 1
          next
        }
      }
      if (open_func) {
        of_body = of_body "\n" raw
        of_lines++
        if (raw ~ /^[[:space:]]*end[[:space:]]*$/ || of_lines > body_cap) {
          emit_record(file, of_scope, of_name, of_start, lineno, of_body)
          open_func = 0
        }
      }
      # End of file: close any pending function.
      next
    }

    END {
      if (open_func) {
        emit_record(file, of_scope, of_name, of_start, NR, of_body)
      }
    }
  ' "$f" >> "$INVENTORY"
done < "$CHANGED_FILES"

if [ ! -s "$INVENTORY" ]; then
  echo "  (no HTTP-boundary functions detected in changed files)"
  echo "=== End Input-Validation Boundary Check ==="
  exit 0
fi

# --- Transitive validation detection ---
# A non-validating boundary that CALLS a same-file validating boundary
# counts as a transitive validator. Suppresses indirect-validation FPs
# where one handler delegates to another that already validates.
INVENTORY_AUG="$_CED_TMPDIR/inventory.aug.tsv"
awk -F'\t' -v OFS='\t' '
  NR==FNR {
    if ($6+0 == 1) {
      key = $1
      val_names[key] = (key in val_names) ? val_names[key] "|" $3 : $3
    }
    next
  }
  {
    if ($6+0 == 0 && ($1 in val_names)) {
      f = $1; sl = $4+0; el = $5+0
      names = val_names[f]
      pat = "(^|[^A-Za-z0-9_])(" names ")[[:space:]]*\\("
      body = ""; ln = ""; lineno = 0
      while ((getline ln < f) > 0) {
        lineno++
        if (lineno >= sl && lineno <= el) body = body "\n" ln
        if (lineno > el) break
      }
      close(f)
      if (body ~ pat) { $6 = 1; $7 = "<transitive>"; $8 = "" }
    }
    print
  }
' "$INVENTORY" "$INVENTORY" > "$INVENTORY_AUG"
mv "$INVENTORY_AUG" "$INVENTORY"

# --- Directory-scope auto-promotion for leaf-verb route directories ---
# Some codebases organize HTTP handlers as `<entity>/<verb>/route.<ext>`
# (one operation per file). File-scope peer detection misses cross-file
# peers in this layout. The entity grouping is structural — sibling
# `<verb>/route.<ext>` files under the same parent operate on the same
# entity.
#
# Promotion criteria (repo-agnostic; structural-only signals — no path-
# component-count heuristic, which over-grouped distinct entities at the
# router root in mixed layouts):
#   (a) The mutation's file matches `*/route.<ts|tsx|js|jsx|mjs|cjs>$`.
#   (b) The file's parent directory is a LEAF verb dir — i.e. it has no
#       subdirectories AND no other source files apart from `route.<ext>`
#       and `route.{test,spec}.<ext>`. Entity dirs that mix a top-level
#       `route.<ext>` with nested resource subdirectories therefore are
#       NOT promoted.
#   (c) The file holds exactly ONE operation, where operation count uses
#       canonical names (strip leading `handle` prefix) so the common
#       `export async function handlePOST(...)` + thin `POST` delegation
#       wrapper counts as one operation, not two. NextJS-native multi-
#       verb files (`POST` + `DELETE` in one file) are NOT promoted —
#       file-scope already applies.
#
# When all three hold, emit one synthetic row with scope re-keyed to
# `<dir:dirname(parent_dir)>`. The synthetic row participates in
# asymmetry analysis alongside the file-scope rows.
PROMOTABLE="$_CED_TMPDIR/promotable.txt"
: > "$PROMOTABLE"

# Pass 1: list candidate files (route.<ext> appearing in inventory whose
# parent dir is a leaf verb dir) and the per-file mutation count.
PER_FILE_COUNTS="$_CED_TMPDIR/per_file_counts.txt"
awk -F'\t' '
  { ucount[$1]++ }
  END { for (f in ucount) print ucount[f] "\t" f }
' "$INVENTORY" > "$PER_FILE_COUNTS"

# For files with mutation count == 1 AND a route filename, verify the
# parent dir is a leaf verb dir via filesystem inspection. Cache per
# parent_dir to avoid repeating find.
declare -A _CED_LEAF_CACHE 2>/dev/null || true
while IFS=$'\t' read -r ucount file; do
  [ "$ucount" = "1" ] || continue
  case "$file" in
    */route.ts|*/route.tsx|*/route.js|*/route.jsx|*/route.mjs|*/route.cjs) ;;
    *) continue ;;
  esac
  parent=$(dirname "$file")
  [ -d "$parent" ] || continue
  cached="${_CED_LEAF_CACHE[$parent]:-}"
  if [ -z "$cached" ]; then
    if [ -n "$(find "$parent" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)" ]; then
      cached=0
    elif [ -n "$(find "$parent" -mindepth 1 -maxdepth 1 -type f 2>/dev/null \
                  | grep -vE '/route\.(ts|tsx|js|jsx|mjs|cjs)$' \
                  | grep -vE '/route\.(test|spec)\.(ts|tsx|js|jsx|mjs|cjs)$' \
                  | head -n 1)" ]; then
      cached=0
    else
      cached=1
    fi
    _CED_LEAF_CACHE[$parent]="$cached"
  fi
  [ "$cached" = "1" ] || continue
  echo "$file" >> "$PROMOTABLE"
done < "$PER_FILE_COUNTS"

# Pass 2: for each promotable file, append a synthetic row with the
# directory-promoted scope key.
INVENTORY_AUG2="$_CED_TMPDIR/inventory.dirpromoted.tsv"
awk -F'\t' -v OFS='\t' -v promotable="$PROMOTABLE" '
  BEGIN {
    while ((getline ln < promotable) > 0) prom[ln] = 1
    close(promotable)
  }
  {
    print
    if (($1 in prom)) {
      n = split($1, parts, "/")
      if (n >= 3) {
        promoted = parts[1]
        for (i = 2; i <= n - 2; i++) promoted = promoted "/" parts[i]
        $2 = "<dir:" promoted ">"
        print
      }
    }
  }
' "$INVENTORY" > "$INVENTORY_AUG2"
mv "$INVENTORY_AUG2" "$INVENTORY"

# --- Asymmetry analysis ---
# For each (file, scope) peer group:
#   - count dispatchers (dispatches=1) and non-dispatchers (dispatches=0)
#   - if ≥1 validating peer AND ≥1 NEW non-validating boundary → emit
#     findings for the non-validators, citing validators as evidence.

echo "## HTTP boundary peer groups with asymmetric input validation"
echo ""

awk -F'\t' '
  {
    # row: file, scope, name, start, end, validates, val_match, _unused, is_new
    f = $1; s = $2; nm = $3; sl = $4; el = $5; d = $6 + 0; v = $7; nw = $9 + 0
    is_dir = (s ~ /^<dir:/)
    if (is_dir) key = s
    else        key = f "\t" s
    grp_is_dir[key] = is_dir
    grp_scope[key] = s
    if (!(key in grp_first_file)) grp_first_file[key] = f
    if (d) {
      grp_val_count[key]++
      if (grp_val_count[key] <= 3) {
        idx = grp_val_count[key]
        val_f[key, idx] = f
        val_n[key, idx] = nm
        val_l[key, idx] = sl
        val_v[key, idx] = v
      }
    } else {
      grp_inv_count[key]++
      if (nw) {
        ni = ++inv_new_count[key]
        inv_f[key, ni] = f
        inv_n[key, ni] = nm
        inv_l[key, ni] = sl
      }
    }
  }
  END {
    findings = 0
    nk = 0
    for (k in grp_val_count) keys[nk++] = k
    for (k in inv_new_count) {
      if (!(k in grp_val_count)) keys[nk++] = k
    }
    asort(keys)
    for (i = 1; i <= nk; i++) {
      k = keys[i]
      if (!(k in grp_val_count)) continue
      if (!(k in inv_new_count)) continue
      is_dir = grp_is_dir[k]
      scope = grp_scope[k]
      if (is_dir) {
        printf "  Group: %s [cross-file peer; validators=%d, non-validators=%d]\n", \
               scope, grp_val_count[k], grp_inv_count[k]
      } else {
        split(k, kp, "\t")
        file = kp[1]
        printf "  Group: %s :: %s (validators=%d, non-validators=%d)\n", \
               file, scope, grp_val_count[k], grp_inv_count[k]
      }
      for (j = 1; j <= inv_new_count[k]; j++) {
        f2 = inv_f[k, j]
        nm2 = inv_n[k, j]
        ln  = inv_l[k, j]
        if (is_dir) {
          printf "    [Major] %s:%d — new boundary %s does not validate input; peer group validates — verify schema-validation symmetry (RS3)\n", \
                 f2, ln, nm2
        } else {
          printf "    [Major] %s:%d — new boundary %s::%s does not validate input; peer group validates — verify schema-validation symmetry (RS3)\n", \
                 f2, ln, scope, nm2
        }
        findings++
      }
      printf "    Peer evidence (validators in same group):\n"
      cap = (grp_val_count[k] < 3) ? grp_val_count[k] : 3
      for (j = 1; j <= cap; j++) {
        f2 = val_f[k, j]
        match_text = val_v[k, j]
        if (match_text != "") {
          printf "      - %s at %s:%d → %s\n", val_n[k, j], f2, val_l[k, j], match_text
        } else {
          printf "      - %s at %s:%d (validation primitive in body)\n", val_n[k, j], f2, val_l[k, j]
        }
      }
      printf "\n"
    }
    if (findings == 0) print "  (no asymmetric peer groups with new non-validating boundaries found)"
    printf "\nTotal findings: %d\n", findings
  }
' "$INVENTORY"

echo ""
echo "=== End Input-Validation Boundary Check ==="
