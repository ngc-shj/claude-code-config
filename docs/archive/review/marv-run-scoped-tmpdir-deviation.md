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

### D2: Added `: "${MARV_DIR:?...}"` parameter-expansion guards at 4 sites (post-review user request)

- **Plan description**: The plan specified `[ -n "${MARV_DIR:-}" ] &&` guards only for the two cleanup sites (Step 1-5 end, Step 3-9). Usage sites (Step 1-5 creation, Step 3-2b creation, Step 3-2 truncation loop, Step 3-4 merge) relied on downstream shell failure (EPERM on `/seed-func.txt`) or the sub-agent Seed Finding Disposition fallback to surface substitution/`mktemp` failures.
- **Actual implementation**: User request after Phase 3 completion: "make it safe on the shell side too." Added `: "${MARV_DIR:?<message>}"` parameter-expansion guards at 4 usage sites:
  - Step 1-5 (after `mktemp -d`): aborts if mktemp failed.
  - Step 3-2b (after `mktemp -d`): aborts if mktemp failed.
  - Step 3-2 truncation-detection loop (before the `for seed in ...`): aborts if orchestrator failed to substitute `$MARV_DIR` into the fresh shell.
  - Step 3-4 code-review merge (before the `cat "$MARV_DIR"/...`): same.
- **Reason**: Fail-fast with a specific error message is more debuggable than relying on permission-denied errors when `"$MARV_DIR"/seed-func.txt` expands to `/seed-func.txt`. The `:?` parameter-expansion form writes the message to stderr and aborts the script non-zero if the variable is unset OR empty — catching both `mktemp` failure (empty assignment under non-`set -e` execution) and orchestrator substitution failure (unset variable in fresh shell).
- **Impact scope**: `skills/multi-agent-review/SKILL.md` only. 4 new lines. No behavior change on the happy path. All 5 cross-cutting grep checks still pass (guard lines do not match any of the verification patterns).

### D3: `hooks/pre-review.sh:162` latent-issue note (not fixed — out of this PR's scope)

- **Observation**: `TMPDIR_REQ=$(mktemp -d)` at `hooks/pre-review.sh:162` and the subsequent `trap 'rm -rf "$TMPDIR_REQ"' EXIT` (line 163) have the same failure mode the D2 guards address in the skill: if `mktemp -d` fails, `$TMPDIR_REQ` is empty, and the downstream `printf ... > "$TMPDIR_REQ/system"` (line 164) writes to `/system` (EPERM). Less severe than the skill case because the trap's `rm -rf ""` is a no-op on GNU coreutils, but still lacks the specific error message.
- **Decision**: Out of scope. `hooks/pre-review.sh` is not in the `refactor/marv-run-scoped-tmpdir` diff; the pre-existing-in-changed-file rule does NOT apply (file is not in the diff). Recording here as a candidate for a future follow-up: `TODO(hook-mktemp-guards): apply the same `:?`-style guard to hooks/pre-review.sh:162 and audit other hook-level `mktemp` call sites for consistency`.
