#!/bin/bash
# Detect event/notification dispatch asymmetry in newly added mutation sites.
#
# R4 (Event/notification dispatch gaps) fired 32 times in the passwd-sso
# review survey. The signal is NOT "this function does not emit" (stateless
# functions would all false-positive); the signal IS "this mutation breaks
# an established dispatch convention in its peer group."
#
# Mutation-site classification (3-axis OR — any axis suffices)
#   Axis 1 — Name proxy: function name has a mutation verb prefix
#     (create / update / delete / cancel / approve / revoke / archive / ...).
#   Axis 2 — HTTP semantics: function name is an HTTP mutation verb
#     (POST / PUT / PATCH / DELETE) — catches NextJS / Hono / Express
#     route handlers where the verb lives in the export name.
#   Axis 3 — Behavior: function body contains a DB-write primitive call
#     (`<obj>.create/update/delete/upsert/insert/destroy/save/remove/
#     truncate(...)` patterns common to Prisma / Mongoose / Sequelize /
#     TypeORM / Drizzle / Knex), or raw SQL `INSERT INTO` / `UPDATE...SET`
#     / `DELETE FROM`. Catches functions whose names do not advertise
#     mutation but whose behavior commits state.
#
# Detection pipeline
#   1. For each changed source file at HEAD, walk every named function
#      definition (any name that is not a private/internal helper) at a
#      valid declaration depth: top-level for cfamily, class-body for
#      class methods, function-level for Go (receiver / package), indent-
#      relative for Python / Ruby.
#   2. Classify each function: mutation site (3-axis OR) AND/OR dispatcher
#      (body scans for emit / publish / dispatch / notify / broadcast /
#      fire / sendEvent / ...). Drop records that are neither, retain
#      mutation sites for analysis.
#   3. Mark NEW mutation sites: start_line in diff `+` and name absent
#      from diff `-` lines (the latter rules out body-edits to existing
#      mutations).
#   4. Group by (file, scope). For each NEW mutation site that is NOT a
#      dispatcher, if its peer group contains ≥1 sibling that IS, emit
#      Major — the peer group has established a dispatch convention and
#      the new mutation breaks it. Output includes dispatching siblings
#      (file:line + verb + event arg) as evidence.
#
# Anti-FP measures
#   - Body-edit suppression: function names appearing on diff `-` lines
#     are treated as existing, not new.
#   - Transitive dispatch: a non-dispatching mutation that calls another
#     same-file mutation that dispatches is auto-promoted to dispatcher
#     (`revokeAll(...)` looping over `revokeOne(...)` where `revokeOne`
#     emits per iteration).
#   - DB-write skip list: JS standard methods (`Object.create`,
#     `Set.delete`, `Map.delete`, etc.) are excluded by default.
#   - Helper / private skip: names ending in `Internal` / `Helper` /
#     `Utils` / `Impl` / `Private` or starting `_` are dropped.
#   - Test exclusion: `__tests__/`, `*.test.*`, `*_test.*`, `*.spec.*`,
#     `spec/` are out of scope.
#
# Severity
#   - Major. Reviewer escalates to Critical only if the missing event is
#     in a security-relevant audit / authz / authn flow (manual call).
#
# Out of scope
#   - Cross-file peer groups. Peer = same file (with same class within
#     the file when detectable). A mutation in service-a.ts and one in
#     service-b.ts are not compared even if they touch the same entity.
#   - Indirect dispatch via cross-file helpers. Helpers that wrap
#     dispatch should be added to EXTRA_DISPATCH_VERBS.
#   - File-routing patterns where the export name does not include
#     either a mutation verb prefix or an HTTP verb (e.g. `handler`,
#     `default`). Behavior-axis catches these when the body has a
#     DB-write primitive; otherwise manual review at the directory level.
#
# Usage: bash check-event-dispatch.sh [base-ref]
#   base-ref defaults to 'main'. The diff is base-ref..HEAD.
#
# Env knobs:
#   EXTRA_MUTATION_VERBS — pipe-separated additional verb prefixes (axis 1)
#   EXTRA_DISPATCH_VERBS — pipe-separated additional dispatch identifiers
#                          (project-specific event-bus method names)
#   EXTRA_MUTATION_PRIMITIVES — pipe-separated additional DB-write call
#                          patterns (project-specific repository wrappers)
#   EXTRA_NON_MUTATION_PRIMITIVES — pipe-separated patterns to skip from
#                          axis 3 (project-specific false-positive helpers)
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

# Names we exclude from analysis entirely — internal helpers and private
# impl details that are not the author of any user-visible event.
SKIP_NAME_RE='([Ii]nternal|[Hh]elper|[Uu]tils?|Impl|[Pp]rivate)$|^_'

# Axis 2 — HTTP mutation verbs as function names. Standard NextJS App
# Router exports `POST` / `PUT` / `PATCH` / `DELETE` directly; many
# codebases wrap with a `handle*` prefix (`handlePOST`) before delegating
# to the export. Both forms are matched.
HTTP_MUT_RE='^(handle)?(POST|PUT|PATCH|DELETE)$'

# Axis 3 — DB-write primitive patterns. Default set covers common ORMs:
# Prisma (`prisma.<m>.create/update/delete/upsert/*Many`), Mongoose
# (`<Model>.create/save/findOneAndUpdate`), Sequelize (`<Model>.create/
# update/destroy`), TypeORM (`repo.save/insert/update/delete/remove`),
# Drizzle (`db.insert/update/delete().values()`), Knex (`knex(...).insert/
# update/delete`), plus raw SQL. Match: dotted access ending in a write
# verb followed by `(`, OR raw SQL keywords.
# `update` is split out from the broad list because `.update(` collides
# with Node crypto API (`createHash(...).update(bytes)`, `hmac.update(...)`).
# The split form requires `{` after `.update(` — matches Prisma's
# `{ where, data }` argument shape and reliably distinguishes ORM updates
# from crypto chains. ORMs without object-literal arg shape (Drizzle,
# Knex) lose recall on axis 3 but axis 1 (verb-prefix function names like
# `updateX`) still catches them.
DB_WRITE_PRIMITIVES_RE='[.](create|delete|upsert|insert|destroy|save|remove|truncate)(Many|One|All)?[[:space:]]*[(]|[.]update(Many|One|All)?[[:space:]]*[(][[:space:]]*[{]|\b(INSERT[[:space:]]+INTO|UPDATE[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+SET|DELETE[[:space:]]+FROM)\b'
[ -n "${EXTRA_MUTATION_PRIMITIVES:-}" ] && DB_WRITE_PRIMITIVES_RE="${DB_WRITE_PRIMITIVES_RE}|${EXTRA_MUTATION_PRIMITIVES}"
DB_WRITE_PRIMITIVES_RE="${DB_WRITE_PRIMITIVES_RE//\\./[.]}"
DB_WRITE_PRIMITIVES_RE="${DB_WRITE_PRIMITIVES_RE//\\(/[(]}"

# Axis 3 deny-list: JS / TS / Java standard-library methods that match
# the DB-write shape but are not state mutations. `Object.create(proto)`
# is the prototype builder; `Set.delete` / `Map.delete` are in-memory
# collection mutations, not persistence.
DB_WRITE_SKIP_RE='\b(Object|Set|Map|WeakMap|WeakSet|Reflect|Symbol|JSON|Buffer|Array|Promise|String|Number|Date|RegExp|Math|Error|Proxy)[.](create|delete|update|insert|save|remove)\b'
[ -n "${EXTRA_NON_MUTATION_PRIMITIVES:-}" ] && DB_WRITE_SKIP_RE="${DB_WRITE_SKIP_RE}|${EXTRA_NON_MUTATION_PRIMITIVES}"
DB_WRITE_SKIP_RE="${DB_WRITE_SKIP_RE//\\./[.]}"

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
      -v http_mut_re="$HTTP_MUT_RE" \
      -v db_write_re="$DB_WRITE_PRIMITIVES_RE" \
      -v db_write_skip_re="$DB_WRITE_SKIP_RE" \
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

    # 3-axis mutation-site classification. ANY axis suffices.
    function is_mutation_site(name, body,    n, lines, i, line, lname) {
      # Axis 1: name has mutation verb prefix. Lowercase the first letter
      # so Go-style PascalCase (`ArchiveItem`) compares against the
      # lowercase verb regex; JS/Python/Ruby names are already lowercase
      # at position 1 so this is a no-op for them.
      lname = tolower(substr(name, 1, 1)) substr(name, 2)
      if (lname ~ mut_re) return 1
      # Axis 2: name is HTTP mutation verb (route handler)
      if (name ~ http_mut_re) return 1
      # Axis 3: body contains DB-write primitive (and not a denied stdlib call)
      n = split(body, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line ~ db_write_re && !(line ~ db_write_skip_re)) return 1
      }
      return 0
    }

    function emit_record(rec_file, rec_scope, rec_name, rec_start, rec_end, rec_body,    n, lines, i, line, m, after, has_disp, disp_verb, disp_arg, is_new, saved_ic) {
      # Drop non-mutation functions before any further work.
      if (!is_mutation_site(rec_name, rec_body)) return
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
