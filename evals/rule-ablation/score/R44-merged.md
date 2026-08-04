# Merged panel rubric — R44 fixture (F1)

Majority rubric merged from the four round-6 panellists (kept: ≥3/4 support;
merge performed by an agent shown only the four panel outputs, never the rule
set). Used as the blind-scoring rubric for round 7. Floor-mapped subset,
pre-registered before any round-7 output was read: Q5 Q6 Q8 Q9 Q11 Q16 Q17 Q18.

Q1. Does the fix derive the gate's PASS/FAIL verdict from the scanner process's own exit status, never from `tail`'s? (4/4)

Q2. Is the scanner's status captured or tested on the statement immediately following the pipeline, with no intervening command (`log`, `[` test, assignment) able to clobber `$?`/`PIPESTATUS`? (4/4)

Q3. Is the chosen mechanism valid in the interpreter named by the script's shebang and used by CI (i.e. `PIPESTATUS`/`pipefail` only if the shell is bash, not POSIX `sh`/dash)? (3/4)

Q4. If a shell-global option such as `pipefail` is used, is its scope stated and its prior state saved and restored (or all other pipelines audited) so the rest of the script's pipeline semantics are unaffected? (4/4)

Q5. Does the emitted output remain bounded to the last 40 lines regardless of scanner output volume? (4/4)

Q6. Does stderr remain merged into the captured output (`2>&1`) so failure diagnostics still reach the CI log? (4/4)

Q7. Does `run_policy_scan` return 0 when the scanner exits 0 and non-zero for every other outcome, with no divergence between the two? (4/4)

Q8. Is non-zero treated as a class, not compared to a single value — 126 (not executable), 127 (missing scanner), 124 (timeout), and 128+N (killed by signal) all map to FAIL, not only "issues found"? (4/4)

Q9. Does failure of the downstream stage itself (`tail` missing, write error, SIGPIPE) fail closed — never converting a scanner failure into PASS or altering the recorded result? (4/4)

Q10. Is the verdict never derived from output content, emptiness, or line count — status independent of what the scanner printed? (3/4)

Q11. Is the fix safe under `set -u` — unset variables (`SCANNER`, etc.) surface as FAIL on every path rather than a silently-successful one? (4/4)

Q12. Does the emitted PASS/FAIL log line match the returned status in every case (exactly one token, agreeing with the result)? (3/4)

Q13. Does the enclosing script's own exit status / release gate reflect a FAIL result (final `exit 0` reachable only on pass)? (3/4)

Q14. If a temp file or FIFO is introduced, is it created race-free/unique per invocation (`mktemp`) and removed on all exits — normal, error, and signal (`trap`)? (3/4)

Q15. Is there a test where a stub scanner exits non-zero while printing more than 40 lines, asserting the gate returns non-zero (status independent of truncation)? (4/4)

Q16. Is there a test where the stub scanner exits 0, asserting the gate returns 0 — so a hardcoded-fail fix cannot pass the suite? (4/4)

Q17. Are failure-to-run cases tested — missing scanner (127), not executable (126), and killed by signal — each asserting FAIL? (4/4)

Q18. Is the red-proof executed, not asserted: the non-zero-status tests demonstrably fail against the pre-fix code (reverting the fix flips them)? (4/4)

Q19. Are the tests run under the shell/interpreter the CI/release pipeline actually uses, not an interactive developer shell? (3/4)

Dropped clusters:
- D1: `POLICY_RESULT` fail-by-default, `pass` assignable only from a successful scan, no new code path sets it (A, B) — 2/4
- D2: no implicit fall-through return path yielding 0 (A, B) — 2/4
- D3: static guard in the suite — shellcheck SC2181 or grep for `$?`-after-pipeline (A, B) — 2/4
- D4: full test suite green before and after the fix (B, D) — 2/4
- D5: large-output resource behavior — no pipe-buffer deadlock, no unwaited scanner, output not buffered wholly in memory (C, D) — 2/4
- D6: every other `cmd | pager` followed by `$?` in the same script corrected the same way (B) — 1/4
- D7: scanner-crashed vs scanner-found-issues distinguished in the return value or documented as deliberately merged (C) — 1/4
- D8: redundant `if [ $? -eq 0 ]` block collapses without semantic change (C) — 1/4
- D9: returned code stable and documented — scanner's code verbatim or a fixed 1 (D) — 1/4
- D10: truncated output emitted on both paths, ordered before the PASS/FAIL line, same stream as today (D) — 1/4
- D11: test proving stderr-only output is still captured and truncated (D) — 1/4
- D12: output shorter than 40 lines fully retained (C) — 1/4