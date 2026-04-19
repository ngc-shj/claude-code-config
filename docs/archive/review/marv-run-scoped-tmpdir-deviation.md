# Coding Deviation Log: marv-run-scoped-tmpdir
Created: 2026-04-19

## Deviations from Plan

### D1: Refined `grep` pattern for Implementation step 7.4 (umask check)
- **Plan description**: Implementation step 7.4 originally read `grep -n 'umask' skills/multi-agent-review/SKILL.md` MUST return zero matches.
- **Actual implementation**: Tightened to `grep -nE '^\s*umask [0-9]' skills/multi-agent-review/SKILL.md` (matches only actual `umask <mode>` command lines, not prose mentions). Reason: the Step 1-5 snippet added during Step 2-2 includes a one-line comment explaining *why* umask is not modified ("no umask modification is needed — other local users cannot traverse..."), which contains the literal word `umask`. A bare `grep -n 'umask'` would match the comment and falsely fail the verification; the refined regex targets only the failure mode the check was designed to catch.
- **Reason**: False-positive elimination in the verification check itself. Intent of the check (catch any `umask 077` / `umask 0077` command being added) is preserved; explanatory prose is correctly allowed.
- **Impact scope**: Verification grep pattern only; plan was updated to reflect the refined check. No SKILL.md behavior change.

## No other deviations

All 6 edit sites implemented exactly per plan:
1. Step 1-5 merge block (line 190 region): replaced with `mktemp -d` + Write-tool ORCHESTRATOR OBLIGATION comment + quoted `$MARV_DIR/...` paths + guarded cleanup.
2. Step 3-2b seed redirects (lines 501-503 region): prepended `mktemp -d`, quoted `$MARV_DIR/seed-*.txt` paths, appended `echo "MARV_DIR=$MARV_DIR"`.
3. Step 3-2 truncation loop (line 509 region): iteration uses `"$MARV_DIR"/seed-{func,sec,test}.txt`.
4. Step 3-3 Round 1 template (line 552 region): `/tmp/seed-<role>.txt` → `$MARV_DIR/seed-<role>.txt` with explicit orchestrator-substitution obligation prose.
5. Step 3-4 merge (line 693 region): Same shape as Step 1-5 but without local `mktemp` or `rm -rf` (reuses Step 3-2b's `$MARV_DIR`); Write-tool ORCHESTRATOR OBLIGATION comment added.
6. Step 3-9 final commit (line 817+ region): appended `[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"` with guard explanation comment.

All 5 post-implementation verification checks (after the D1 refinement) pass. `bash ./install.sh`-equivalent deployment (`cp skills/multi-agent-review/SKILL.md ~/.claude/skills/multi-agent-review/SKILL.md`) verified with `diff` showing identical content.
