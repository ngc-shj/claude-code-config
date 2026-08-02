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

# Split a table row into cells[1..n]. Returns n; cells[1] is the ID and cells[n]
# the severity.
#
# A pipe is a DELIMITER only when the run of backslashes immediately before it is
# EVEN. `\|` is an escaped pipe and belongs to the cell; `\\|` is a literal
# backslash followed by a real delimiter; `\\\|` is a literal backslash then an
# escaped pipe. Counting the run is the whole point — a `/\\\|/` match treats
# `\\|` as escaped too, which merges the last two cells so a Procedure cell's
# text is read as the severity. That direction is the dangerous one: a procedure
# mentioning "Critical" would then satisfy a ceiling check that never looked at
# the severity, in both this generator's output and the linter comparing against
# it. Hence a character walk rather than a regex.
function md_cells(line, cells,   i, len, ch, run, cur, raw, n, lo, hi, k) {
  sub(/[[:space:]]+$/, "", line)
  len = length(line); n = 0; cur = ""; run = 0
  for (i = 1; i <= len; i++) {
    ch = substr(line, i, 1)
    if (ch == "\\") { run++; cur = cur ch; continue }
    if (ch == "|" && run % 2 == 0) { raw[++n] = cur; cur = "" }
    else { cur = cur ch }
    run = 0
  }
  raw[++n] = cur
  # A table row opens with `|`, so raw[1] is empty, and usually closes with one,
  # so raw[n] is too. Drop those sentinels. A row missing its closing pipe still
  # yields the right cells; whether that is an error is the caller's policy.
  lo = 1; hi = n
  if (raw[lo] ~ /^[[:space:]]*$/) lo++
  if (hi >= lo && raw[hi] ~ /^[[:space:]]*$/) hi--
  k = 0
  for (i = lo; i <= hi; i++) cells[++k] = raw[i]
  return k
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
