# Shared extraction for the triangulate rule table's Markdown rows.
#
# A rule row is `| ID | Pattern | Procedure… | Severity |`. Two traps make a
# naive split wrong, and both have bitten:
#
#   * Procedure cells legitimately contain literal pipes (regexes, code spans),
#     so the severity is the LAST cell, never a fixed index.
#   * An ESCAPED pipe (`\|`) is ONE Markdown cell, not a delimiter. A severity
#     written `Critical \| Major` is a single cell containing "Critical"; a bare
#     split reads the trailing "Major" and silently loses the ceiling.
#
# Both the digest generator and the rule-sync linter parse these rows. They had
# two copies of the split, the linter learned about escaped pipes and the
# generator did not — so the generator emitted a digest with the escalation
# missing, and the linter's staleness check compared that digest against the
# same wrong generator output and agreed. One implementation, consulted by both,
# is what stops that (R1 / RT9).
#
# Usage:
#   awk -v want=rows               -f md-rule-rows.awk <file>
#       → one normalized `| ID | Pattern | Severity |` line per rule row
#   awk -v want=severity -v id=R36 -f md-rule-rows.awk <file>
#       → that row's severity cell, lowercased, or nothing if the row is absent
#
# Row shape is NOT policed here: a row missing its closing pipe still parses.
# Whether a malformed row is an error is the caller's policy, and the linter
# asserts it separately so the two obligations can fail independently.

function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }

# Split a table row into cells[1..n], honouring backslash-escaped pipes.
# Returns n. cells[1] is the ID, cells[n] the severity.
function md_cells(line, cells,   n, i) {
  gsub(/\\\|/, SUBSEP, line)          # protect escaped pipes from the split
  sub(/[[:space:]]+$/, "", line)
  sub(/\|$/, "", line)                # drop the row's closing pipe, if present
  sub(/^\|/, "", line)                # and its opening pipe
  n = split(line, cells, "[|]")
  for (i = 1; i <= n; i++) gsub(SUBSEP, "\\|", cells[i])
  return n
}

/^\| (R[0-9]+|RS[0-9]+|RT[0-9]+) [|]/ {
  n = md_cells($0, c)
  if (n < 3) next
  row_id = trim(c[1])
  row_pattern = trim(c[2])
  row_severity = trim(c[n])
  if (want == "rows") {
    print "| " row_id " | " row_pattern " | " row_severity " |"
  } else if (want == "severity" && row_id == id) {
    print tolower(row_severity)
    exit
  }
}
