# Coding Deviation Log: triangulate-r43-rt9-failsafe-lessons

## D1 — Direct orchestrator implementation (Step 2-2 fallback path)

- **Plan said**: Step 2-2 delegates implementation batches to Sonnet sub-agents.
- **Actual**: the orchestrator applied all edits directly via the Edit tool.
- **Reason**: every edit is a verbatim paste of a locked contract body from the plan; delegation would re-transcribe long single-line table rows through a second model (transcription risk) with no parallelism benefit for a 5-file sequential markdown change. The skill sanctions direct implementation as the fallback path; R21-equivalent verification was performed by the orchestrator itself (acceptance greps + full bats suite 548/548 + install parity ×5).

## D2 — Acceptance-criterion command miscalibration in C1 (plan bug, not implementation bug)

- **Plan said**: C1 acceptance includes `grep -c 'R43 (' skills/triangulate/common-rules.md` ≥ 2 (table row + template line).
- **Actual**: the table row is spelled `| R43 | …` (cell syntax, no parenthesis), so the grep counts only the template line (= 1). Row existence and integrity were verified by the equivalent checks the plan also specifies: `grep '^| R43 ' | awk -F'|' '{print NF}'` → 6, and the template-line grep → 1.
- **Disposition**: implementation matches the contract's substance; the miscalibrated command is superseded by the equivalent checks. No skill-file change needed.
