#!/bin/bash
# Detect event/notification dispatch asymmetry in newly added mutations.
#
# R4 (Event/notification dispatch gaps) fired 32 times in the passwd-sso
# review survey — a new mutation function was added in a peer group where
# sibling mutations dispatch a domain event, but the new one does not.
# The signal is NOT "this mutation does not emit" (stateless mutations
# would all false-positive); the signal IS "this mutation breaks an
# established convention in its peer group."
#
# Detection
#   1. Scan each changed source file at HEAD for mutation-shaped function
#      definitions (verb-prefix names: create / update / delete / cancel /
#      publish / archive / approve / ...). For each, capture: enclosing
#      scope (class / Go-receiver / Python-class / file fallback), name,
#      start line, body span, and whether the body contains a dispatch
#      verb call (emit / publish / dispatch / notify / broadcast / fire /
#      sendEvent / ...).
#   2. Identify which mutations are NEW: their start_line falls on a `+`
#      line in the diff.
#   3. Group all mutations by (file, scope). For each new mutation that
#      does NOT dispatch, if its peer group contains ≥1 sibling that DOES
#      dispatch, emit Major finding — peer group has established the
#      event convention; the new mutation breaks it.
#
# Output includes the dispatching siblings (file:line + the dispatch verb)
# so the reviewer sees the asymmetry directly and can verify whether a
# corresponding event is needed.
#
# Severity
#   - Major. Asymmetric dispatch is a high-confidence signal: a peer that
#     emits proves the convention exists, a new sibling that does not
#     emit is a candidate gap.
#   - Reviewer escalates to Critical only if the missing event is in a
#     security-relevant audit / authz / authn flow (manual call).
#
# Out of scope
#   - Cross-file peer groups. A mutation in service-a.ts and one in
#     service-b.ts are not compared even if they touch the same entity.
#     Peer = same file (and same class within the file when detectable).
#   - Event-bus call graphs (tx/outbox-pattern indirection). When a
#     mutation calls a helper that dispatches, we see no dispatch verb
#     on the line and may flag a false positive. Mitigation: helpers
#     that wrap dispatch should be added to EXTRA_DISPATCH_VERBS.
#   - Pure helper / private mutations (names ending in Internal / Helper /
#     Utils, or starting with underscore) are skipped.
#
# Usage: bash check-event-dispatch.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   EXTRA_MUTATION_VERBS — pipe-separated additional verb prefixes
#   EXTRA_DISPATCH_VERBS — pipe-separated additional dispatch identifiers
#                          (project-specific event-bus method names)
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

# Mutation verb prefixes (lowercase; compared case-insensitive). The set
# was chosen against the passwd-sso review history's recurring verb
# population — covers the common CRUD plus state-machine transitions
# (cancel/approve/reject/archive/restore) that historically forget events.
MUTATION_VERBS_RE='create|update|delete|insert|remove|save|upsert|patch|set|toggle|reset|approve|reject|cancel|publish|archive|restore|grant|revoke|enable|disable|rotate|terminate|finalize|complete|sync|mark|assign|unassign|attach|detach|invite|expire|suspend|resume|lock|unlock|ban|unban|deactivate|activate'
[ -n "${EXTRA_MUTATION_VERBS:-}" ] && MUTATION_VERBS_RE="${MUTATION_VERBS_RE}|${EXTRA_MUTATION_VERBS}"

# Dispatch verbs — function names that emit an event in any common
# event-bus / outbox / message-queue convention. Compared case-insensitive
# as a complete identifier (word-boundary). Project-specific event helpers
# (e.g. `logAuditAsync`, `recordAuditEvent`, custom outbox wrappers) MUST
# be added via EXTRA_DISPATCH_VERBS — without them the hook will be
# silent for codebases that do not use the universal verbs below.
DISPATCH_VERBS_RE='emit|publish|dispatch|notify|broadcast|trigger|fire|sendEvent|raiseEvent|recordEvent|enqueueEvent|emitEvent|fireEvent|raise_event|send_event|dispatch_event|publishEvent|publish_event|writeOutbox|write_outbox|appendEvent|append_event|recordAuditEvent|record_audit_event'
[ -n "${EXTRA_DISPATCH_VERBS:-}" ] && DISPATCH_VERBS_RE="${DISPATCH_VERBS_RE}|${EXTRA_DISPATCH_VERBS}"
# gawk warns on `\.` inside dynamic regex (treats it as literal `.`). User
# input may contain `auditLog\.create` style; rewrite to `[.]` to silence.
DISPATCH_VERBS_RE="${DISPATCH_VERBS_RE//\\./[.]}"

# Names we exclude from mutation classification — internal helpers and
# private impl details that are not the author of the user-visible event.
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

echo "=== Event-Dispatch Symmetry Check (R4) ==="
echo "Base: $BASE_REF"
echo "Source files in diff: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "  (no source files in diff; nothing to check)"
  echo "=== End Event-Dispatch Symmetry Check ==="
  exit 0
fi

# Inventory format (TSV):
#   file <TAB> scope <TAB> name <TAB> start_line <TAB> end_line <TAB>
#   dispatches <TAB> dispatch_verb <TAB> dispatch_arg <TAB> is_new
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

  # Names of mutation-shaped tokens removed in this diff (per file). When a
  # mutation function's body is edited (not added), the `-` line contains
  # the same definition; the function is still a body-edit, not a fresh
  # mutation. Without this, every body-edit on a non-dispatching mutation
  # would re-flag forever.
  removed_names_file="$NEW_LINES_DIR/$enc.removednames"
  git diff "$BASE_REF...HEAD" --unified=0 -- "$f" 2>/dev/null \
    | awk '/^-[^-]/' \
    | grep -oEi "\\b(${MUTATION_VERBS_RE})[A-Za-z0-9_]*" 2>/dev/null \
    | sort -u > "$removed_names_file"

  ext="${f##*.}"
  case "$ext" in
    go)         lang=go ;;
    py)         lang=python ;;
    rb)         lang=ruby ;;
    *)          lang=cfamily ;;
  esac

  # Single awk pass per file: extract mutation function records with body
  # spans + dispatch detection. Output rows are appended to INVENTORY.
  awk -v file="$f" \
      -v lang="$lang" \
      -v mut_re="^(${MUTATION_VERBS_RE})([A-Z_]|$)" \
      -v disp_inner="${DISPATCH_VERBS_RE}" \
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

    function emit_record(rec_file, rec_scope, rec_name, rec_start, rec_end, rec_body,    n, lines, i, line, m, after, has_disp, disp_verb, disp_arg, is_new, saved_ic) {
      has_disp = 0
      disp_verb = ""
      disp_arg = ""
      # Case-insensitive only for dispatch detection — Go uses PascalCase
      # (Emit / Publish), JS uses camelCase (emit / publish), Python uses
      # snake_case (raise_event). disp_inner is lowercase only.
      saved_ic = IGNORECASE
      IGNORECASE = 1
      n = split(rec_body, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        # Word-bounded dispatch verb call. Build regex dynamically from
        # disp_inner to avoid gawk warning on literal \< / \> in -v vars.
        if (match(line, "(^|[^A-Za-z0-9_])(" disp_inner ")[[:space:]]*\\(")) {
          has_disp = 1
          m = substr(line, RSTART, RLENGTH)
          # Strip leading non-identifier char (if any) and trailing "(...".
          sub(/^[^A-Za-z_]+/, "", m)
          sub(/[[:space:]]*\(.*$/, "", m)
          disp_verb = m
          # Capture short event-name argument.
          after = substr(line, RSTART + RLENGTH - 1)
          if (match(after, /\(\s*[\x27"`]([A-Za-z_][A-Za-z0-9_.:-]{1,80})[\x27"`]/)) {
            disp_arg = substr(after, RSTART, RLENGTH)
            gsub(/^\(\s*[\x27"`]/, "", disp_arg)
            gsub(/[\x27"`].*$/, "", disp_arg)
          } else if (match(after, /\(\s*([A-Za-z_][A-Za-z0-9_.]{1,80})\s*[,)]/)) {
            disp_arg = substr(after, RSTART, RLENGTH)
            gsub(/^\(\s*/, "", disp_arg)
            gsub(/\s*[,)].*$/, "", disp_arg)
          }
          break
        }
      }
      IGNORECASE = saved_ic
      # is_new gates: start line newly added AND name not seen on a `-`
      # line in the diff. The latter rules out body-edits to existing
      # mutations.
      is_new = ((rec_start in added) && !(rec_name in removed_names)) ? 1 : 0
      printf "%s\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%d\n", \
             rec_file, rec_scope, rec_name, rec_start, rec_end, has_disp, disp_verb, disp_arg, is_new
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

      if (func_name != "" && func_name ~ mut_re && func_name !~ skip_re) {
        # Open a function-record window: collect the body until brace
        # depth returns to brace_depth_before (start-of-line depth).
        if (open_func) {
          # Edge case: nested mutation function inside a body — close the
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
      # func (r *T) Name(...)
      if (match(raw, /^func[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\*?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\)[[:space:]]+[A-Z][A-Za-z0-9_]*/)) {
        seg = substr(raw, RSTART, RLENGTH)
        # Receiver: extract from "(...)" — last identifier (Type).
        recv = seg
        match(recv, /\([^)]*\)/)
        recv_full = substr(recv, RSTART + 1, RLENGTH - 2)  # drop outer parens
        # recv_full e.g. "s *InventoryService" → take last identifier.
        if (match(recv_full, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) {
          recv = substr(recv_full, RSTART, RLENGTH)
          gsub(/[[:space:]]/, "", recv)
        } else {
          recv = ""
        }
        nm = seg; sub(/.*\)[[:space:]]+/, "", nm); sub(/[[:space:](].*/, "", nm)
        # Lowercase first letter for mutation-verb match.
        lname = tolower(substr(nm, 1, 1)) substr(nm, 2)
        if (lname ~ mut_re && nm !~ skip_re) {
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
      # func Name(...)  (package-level)
      if (match(raw, /^func[[:space:]]+([A-Z][A-Za-z0-9_]*)/)) {
        seg = substr(raw, RSTART, RLENGTH)
        nm = seg; sub(/^func[[:space:]]+/, "", nm); sub(/[[:space:]].*/, "", nm)
        lname = tolower(substr(nm, 1, 1)) substr(nm, 2)
        if (lname ~ mut_re && nm !~ skip_re) {
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
      # def name(...) — possibly inside a class.
      if (match(raw, /^([[:space:]]*)((async[[:space:]]+)?def[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/)) {
        seg = substr(raw, RSTART, RLENGTH)
        ws = seg; sub(/[^[:space:]].*/, "", ws); fn_ind = length(ws)
        nm = seg; sub(/.*def[[:space:]]+/, "", nm); sub(/[[:space:]]*\(.*/, "", nm)
        if (nm ~ mut_re && nm !~ skip_re) {
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
        if (nm ~ mut_re && nm !~ skip_re) {
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
  echo "  (no mutation-shaped functions detected in changed files)"
  echo "=== End Event-Dispatch Symmetry Check ==="
  exit 0
fi

# --- Transitive dispatch detection ---
# A non-dispatching mutation that CALLS a same-file dispatcher counts as
# a transitive dispatcher. Suppresses the common indirect-dispatch FP:
# `revokeAll(...)` that loops over `revokeOne(...)` where `revokeOne`
# emits the audit event per iteration.
INVENTORY_AUG="$_CED_TMPDIR/inventory.aug.tsv"
awk -F'\t' -v OFS='\t' '
  NR==FNR {
    if ($6+0 == 1) {
      key = $1
      disp_names[key] = (key in disp_names) ? disp_names[key] "|" $3 : $3
    }
    next
  }
  {
    if ($6+0 == 0 && ($1 in disp_names)) {
      f = $1; sl = $4+0; el = $5+0
      names = disp_names[f]
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

# --- Asymmetry analysis ---
# For each (file, scope) peer group:
#   - count dispatchers (dispatches=1) and non-dispatchers (dispatches=0)
#   - if ≥1 dispatcher AND ≥1 NEW non-dispatcher → emit findings for the
#     non-dispatchers, citing dispatchers as evidence.

echo "## Mutation peer groups with asymmetric dispatch"
echo ""

awk -F'\t' '
  {
    # row: file, scope, name, start, end, dispatches, verb, arg, is_new
    f = $1; s = $2; n = $3; sl = $4; el = $5; d = $6 + 0; v = $7; a = $8; nw = $9 + 0
    key = f "\t" s
    if (d) {
      grp_disp_count[key]++
      # Save up to 3 dispatcher exemplars per group.
      if (grp_disp_count[key] <= 3) {
        idx = grp_disp_count[key]
        disp_n[key, idx] = n
        disp_l[key, idx] = sl
        disp_v[key, idx] = v
        disp_a[key, idx] = a
      }
    } else {
      grp_nond_count[key]++
      # Stash only NEW non-dispatchers — those are the candidates.
      if (nw) {
        ni = ++nondisp_new_count[key]
        nd_n[key, ni] = n
        nd_l[key, ni] = sl
      }
    }
  }
  END {
    findings = 0
    # Sort keys for stable output.
    n = 0
    for (k in grp_disp_count) keys[n++] = k
    for (k in nondisp_new_count) {
      if (!(k in grp_disp_count)) keys[n++] = k
    }
    # Output ordering: simple string sort over keys.
    asort(keys)
    for (i = 1; i <= n; i++) {
      k = keys[i]
      if (!(k in grp_disp_count)) continue
      if (!(k in nondisp_new_count)) continue
      # Found asymmetric group with new non-dispatchers.
      split(k, kp, "\t")
      file = kp[1]; scope = kp[2]
      printf "  Group: %s :: %s (dispatchers=%d, non-dispatchers=%d)\n", \
             file, scope, grp_disp_count[k], grp_nond_count[k]
      # New non-dispatcher findings.
      for (j = 1; j <= nondisp_new_count[k]; j++) {
        nm  = nd_n[k, j]
        ln  = nd_l[k, j]
        printf "    [Major] %s:%d — new mutation %s::%s does not dispatch; peer group emits — verify event symmetry (R4)\n", \
               file, ln, scope, nm
        findings++
      }
      printf "    Peer evidence (dispatchers in same group):\n"
      cap = (grp_disp_count[k] < 3) ? grp_disp_count[k] : 3
      for (j = 1; j <= cap; j++) {
        v = disp_v[k, j]; a = disp_a[k, j]
        if (a != "") {
          printf "      - %s at %s:%d → %s(%s)\n", disp_n[k, j], file, disp_l[k, j], v, a
        } else {
          printf "      - %s at %s:%d → %s(...)\n", disp_n[k, j], file, disp_l[k, j], v
        }
      }
      printf "\n"
    }
    if (findings == 0) print "  (no asymmetric peer groups with new non-dispatchers found)"
    printf "\nTotal findings: %d\n", findings
  }
' "$INVENTORY"

echo ""
echo "=== End Event-Dispatch Symmetry Check ==="
