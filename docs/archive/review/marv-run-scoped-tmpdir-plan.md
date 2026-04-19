# Plan: marv-run-scoped-tmpdir

## Project context

- **Type**: config-only (claude-code-config repo — skill definitions and shell hooks)
- **Test infrastructure**: none
- Per skill policy, experts MUST NOT raise Major/Critical findings recommending automated tests / CI / test framework setup; downgrade to Minor informational notes only.

## Objective

Replace every hard-coded `/tmp/{func,sec,test}-findings.txt` and `/tmp/seed-{func,sec,test}.txt` reference in `skills/multi-agent-review/SKILL.md` with a uniform per-run `mktemp -d` directory convention. Eliminate two concrete failure modes:

1. **Parallel-run collision**: two `/multi-agent-review` invocations on the same machine (different IDE sessions, `/loop`, `schedule`-triggered runs, two users on a shared host) currently overwrite each other's intermediate findings files, silently corrupting merge output.
2. **`/tmp` world-readable exposure** (previously S2, accepted-as-is with `TODO(mktemp-migration)` marker): hard-coded files directly under `/tmp` inherit the user's default umask (often `022` → mode `644`), so any diff-quoted content is readable by other local users.

**Confidentiality mechanism**: `mktemp -d` creates the directory with mode `0700` (`drwx------`) owned by the invoking user, regardless of umask. Because `others` have no `x` permission on the parent directory, no other local user can traverse into it — files inside are unreachable externally even if they are created with a permissive umask. This makes a per-session `umask 077` unnecessary (and avoids the risk of leaking a restrictive umask to unrelated later commands in the skill run).

## Requirements

### Functional

1. Every SKILL.md step that currently writes to or reads from a hard-coded `/tmp/*-findings.txt` or `/tmp/seed-*.txt` path MUST be rewritten to use a per-run directory created with `mktemp -d -t marv-XXXXXX`.
2. No `umask` modification is required or permitted at the skill-narrative level. `mktemp -d` produces a mode-`0700` directory owned by the invoking user, which is sufficient for confidentiality (other local users cannot traverse the parent directory, so interior file permissions do not affect exposure). Explicitly NOT touching `umask` avoids the failure mode where a restrictive umask leaks into unrelated later commands in the skill run.
3. The convention MUST be uniform across Step 1-5 (plan review merge), Step 3-2b (seed generation), Step 3-2 truncation-detection loop, Step 3-3 Round 1 template (seed path reference), and Step 3-4 (code review merge). Do NOT introduce one convention for seed files and another for findings files.
4. Step 3-2 through 3-4 share a single directory (seed files from 3-2 are consumed by 3-3 template substitution and the merge in 3-4 operates on findings files in the same dir).
5. Step 1-5 uses its own, self-contained directory (created and cleaned up within the step) because Phase 1 review does not share data with Phase 3.
6. Cleanup: after the final merge (Step 1-5 end, Step 3-9 final commit), the per-run directory MUST be removed (`rm -rf "$MARV_DIR"`). If the skill is aborted mid-run, leftover directories are acceptable (they will be named `marv-XXXXXX` and can be manually cleaned or GC'd by the OS's `/tmp` policy).

### Non-functional

- Zero additional dependencies: `mktemp -d` is POSIX-standard.
- Zero impact on the happy path: the externally observable behavior (findings merging, seed consumption) is identical to the current skill.
- Path references in the Round 1 template MUST include a clear substitution note so orchestrators know to inline the literal absolute path, not treat `$MARV_DIR` as a user-facing variable inside the sub-agent prompt.

## Technical approach

### Convention (uniform across all sites)

Each site that needs the directory begins with a single line:

```bash
# mktemp -d creates the directory with mode 0700 (drwx------) owned by the
# invoking user — sufficient for confidentiality without any umask change.
MARV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX")
```

File names inside the directory:

- Plan review (Step 1-5): `"$MARV_DIR/func-findings.txt"`, `"$MARV_DIR/sec-findings.txt"`, `"$MARV_DIR/test-findings.txt"`
- Code review seed files (Step 3-2b): `"$MARV_DIR/seed-func.txt"`, `"$MARV_DIR/seed-sec.txt"`, `"$MARV_DIR/seed-test.txt"`
- Code review findings files (Step 3-4): `"$MARV_DIR/func-findings.txt"`, `"$MARV_DIR/sec-findings.txt"`, `"$MARV_DIR/test-findings.txt"` (same filenames as plan-review since the two merges never coexist in a single `MARV_DIR`)

Cleanup at the end of the step or phase:

```bash
rm -rf "$MARV_DIR"
```

### Step-by-step rewrite

**Step 1-5 (Plan review merge — self-contained tmpdir)**

Before:
```bash
cat /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
```

After:
```bash
MARV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX")
# ORCHESTRATOR OBLIGATION: after each expert sub-agent returns, the orchestrator
# MUST save the sub-agent's raw output to the corresponding file using the Write
# tool, substituting the LITERAL absolute path captured from the MARV_DIR= line:
#   Write "$MARV_DIR/func-findings.txt" ← Functionality expert output
#   Write "$MARV_DIR/sec-findings.txt"  ← Security expert output
#   Write "$MARV_DIR/test-findings.txt" ← Testing expert output
# Do NOT pass the shell variable $MARV_DIR as a literal to Write — it will not
# be expanded (Write tool is not a shell); pass the absolute path string.
cat "$MARV_DIR/func-findings.txt" "$MARV_DIR/sec-findings.txt" "$MARV_DIR/test-findings.txt" \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"
```

**Step 3-2b (Seed generation — MARV_DIR preserved for Steps 3-3 and 3-4)**

Before:
```bash
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-functionality > /tmp/seed-func.txt
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-security      > /tmp/seed-sec.txt
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-testing       > /tmp/seed-test.txt
```

After:
```bash
MARV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX")
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-functionality > "$MARV_DIR/seed-func.txt"
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-security      > "$MARV_DIR/seed-sec.txt"
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh analyze-testing       > "$MARV_DIR/seed-test.txt"
echo "MARV_DIR=$MARV_DIR"  # Orchestrator records this path for Steps 3-3 and 3-4
```

**Step 3-2 truncation-detection loop (consumes MARV_DIR from 3-2b)**

Before:
```bash
for seed in /tmp/seed-func.txt /tmp/seed-sec.txt /tmp/seed-test.txt; do
  if [ -s "$seed" ] && ! sed '/^[[:space:]]*$/d' "$seed" | tail -1 | grep -q '^## END-OF-ANALYSIS$'; then
    echo "Warning: $seed appears truncated ..." >&2
  fi
done
```

After:
```bash
for seed in "$MARV_DIR"/seed-func.txt "$MARV_DIR"/seed-sec.txt "$MARV_DIR"/seed-test.txt; do
  if [ -s "$seed" ] && ! sed '/^[[:space:]]*$/d' "$seed" | tail -1 | grep -q '^## END-OF-ANALYSIS$'; then
    echo "Warning: $seed appears truncated (missing END-OF-ANALYSIS sentinel) — sub-agent will fall back to full-diff review" >&2
  fi
done
```

**Step 3-3 Round 1 template (seed path reference)**

Before (template text):
```
[Orchestrator MUST select ONE of the three branches based on /tmp/seed-<role>.txt state ...]
```

After (template text):
```
[Orchestrator MUST select ONE of the three branches based on the seed file at $MARV_DIR/seed-<role>.txt (where $MARV_DIR is the absolute path recorded in Step 3-2b; substitute the literal path when rendering this prompt). <role> ∈ {func, sec, test}:

 (a) File is 0-byte OR does not end with `## END-OF-ANALYSIS` sentinel:
     Insert: "Seed unavailable or truncated — ..."
 (b) ...
 (c) ...
]
```

The critical detail: the template contains `$MARV_DIR/seed-<role>.txt` as a readable placeholder, but the orchestrator that renders the prompt MUST substitute the literal absolute path captured from Step 3-2b. Sub-agents do not need access to the variable — they need the concrete path to read.

**Step 3-4 (Code review merge — reuses MARV_DIR from 3-2b)**

Before:
```bash
cat /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
```

After:
```bash
# Reuses the $MARV_DIR created in Step 3-2b — substitute the literal absolute
# path when running this command in a fresh Bash tool invocation.
# ORCHESTRATOR OBLIGATION: after each expert sub-agent returns, save each raw
# output to the corresponding file via the Write tool with the literal path:
#   Write "$MARV_DIR/func-findings.txt"
#   Write "$MARV_DIR/sec-findings.txt"
#   Write "$MARV_DIR/test-findings.txt"
cat "$MARV_DIR/func-findings.txt" "$MARV_DIR/sec-findings.txt" "$MARV_DIR/test-findings.txt" \
  | bash ~/.claude/hooks/ollama-utils.sh merge-findings
```

Cleanup happens at Step 3-9 (final commit) via `[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"`.

### Persisting MARV_DIR across tool invocations

Because Claude's Bash tool spawns a fresh shell per invocation AND the Write tool is not a shell, `$MARV_DIR` does NOT survive automatically between Step 3-2b, 3-3 template rendering, each Write-tool call that saves a sub-agent's output, and Step 3-4. The skill's narrative MUST instruct the orchestrator (Claude) to:

1. Capture the `MARV_DIR=...` value printed at the end of the Step 3-2b snippet (treat it as the one authoritative value for this review round).
2. Substitute the literal absolute path when rendering the Step 3-3 template for each sub-agent prompt — the sub-agent sees the concrete path, never the `$MARV_DIR` placeholder.
3. Substitute the literal absolute path in every Write-tool call used to save sub-agent outputs (`"$MARV_DIR/func-findings.txt"`, `"$MARV_DIR/sec-findings.txt"`, `"$MARV_DIR/test-findings.txt"` in both Step 1-5 and Step 3-4). The Write tool does NOT perform shell expansion; passing the literal string `$MARV_DIR/...` as the path creates a file named `$MARV_DIR` in the current working directory, which is a correctness bug.
4. Re-inline the literal path in the Step 3-4 `cat ... | merge-findings` command (Bash tool invocation).
5. Use the literal path in the Step 1-5-end and Step 3-9 cleanup `rm -rf` commands, guarded by `[ -n "${MARV_DIR:-}" ]` so a missing variable never attempts an empty-string removal.

This is an orchestration responsibility, not a shell-scripting one. The skill text makes this explicit so future maintainers don't wonder why the bash variable isn't "magically" shared across tool calls.

### Out-of-scope sites (documented, not changed)

- `hooks/resolve-ollama-host.sh:13` uses `/tmp/.ollama-host-cache-$(id -u)` — already scoped per-UID, not a collision site.
- `skills/multi-agent-review/SKILL.md:307` (Step 2-1) uses `mktemp /tmp/shared-utils-inventory.XXXXXX` — already on `mktemp`; no change needed (could be harmonized to `mktemp -d -t marv-...` but that would reduce clarity since it's a single file, not a directory).
- Other skills (`pr-create`, `simplify`, `test-gen`, `explore`) — `grep -rn '/tmp/' skills/` returns no hits outside `multi-agent-review`, so they are not affected.
- `hooks/ollama-utils.sh` — uses `mktemp -d` internally in `_ollama_request`; already safe.

## Implementation steps

1. Edit `skills/multi-agent-review/SKILL.md` Step 1-5:
   1. Prepend the `MARV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX")` line (no umask).
   2. Add the orchestrator Write-tool save obligation as a comment block inside the snippet (addresses F1 + F3).
   3. Change the three hard-coded paths in the `cat` command to `"$MARV_DIR/..."`.
   4. Append `[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"` after the merge (addresses F4).
2. Edit `skills/multi-agent-review/SKILL.md` Step 3-2b (seed generation):
   1. Prepend the `MARV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX")` line (no umask).
   2. Replace the three `> /tmp/seed-*.txt` redirects with `> "$MARV_DIR/seed-*.txt"`.
   3. Append `echo "MARV_DIR=$MARV_DIR"` with a comment clarifying that the orchestrator captures this for later steps (Steps 3-3 template, Write-tool saves, Step 3-4 merge, Step 3-9 cleanup).
3. Edit `skills/multi-agent-review/SKILL.md` Step 3-2 truncation-detection loop:
   1. Change the `for seed in /tmp/seed-*.txt` to `for seed in "$MARV_DIR"/seed-*.txt` (or spell out the three paths with `$MARV_DIR` prefix).
4. Edit `skills/multi-agent-review/SKILL.md` Step 3-3 Round 1 template:
   1. Replace `/tmp/seed-<role>.txt` with `$MARV_DIR/seed-<role>.txt` and add a sentence making the literal-path-substitution obligation explicit.
5. Edit `skills/multi-agent-review/SKILL.md` Step 3-4 (code review merge):
   1. Change the three hard-coded paths to `"$MARV_DIR/..."`, add the orchestrator Write-tool save obligation comment block (addresses F1 + F3), and add a comment pointing back to Step 3-2b for the variable's origin.
6. Edit `skills/multi-agent-review/SKILL.md` Step 3-9 (final commit):
   1. Append `[ -n "${MARV_DIR:-}" ] && rm -rf "$MARV_DIR"` to the cleanup step after the final commit (addresses F4).
7. Cross-cutting verification:
   1. `grep -nE '(/tmp/(func|sec|test)-findings|/tmp/seed-(func|sec|test))\.txt' skills/ hooks/` MUST return zero matches.
   2. `grep -nE '\$MARV_DIR/(seed-|.*-findings)' skills/multi-agent-review/SKILL.md` MUST return matches in at least 5 locations (Step 1-5, 3-2b, 3-2 loop, 3-3 template, 3-4).
   3. `grep -nE 'mktemp -d "\$\{TMPDIR:-/tmp\}/marv-XXXXXX"' skills/multi-agent-review/SKILL.md` MUST return at least 2 matches (Step 1-5 and Step 3-2b). (Broader fallback: `grep -nE 'mktemp -d.*marv-'` returns the same matches — use whichever parses cleanly in your shell.)
   4. `grep -n 'umask' skills/multi-agent-review/SKILL.md` MUST return zero matches — we intentionally do NOT modify umask; confidentiality comes from the `0700` directory mode `mktemp -d` produces. A present `umask` line is a regression.
   5. `grep -n 'rm -rf "\$MARV_DIR"' skills/multi-agent-review/SKILL.md` MUST return at least 2 matches (Step 1-5 end and Step 3-9).
8. Smoke test: create a transient tmpdir manually and verify the directory mode:
   ```bash
   D=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX") && stat -c '%a %n' "$D" && ls -ld "$D" && rm -rf "$D"
   ```
   Expected: mode `700` (`drwx------`) on the directory. File mode inside is irrelevant for confidentiality (the parent directory blocks traversal for other users).
9. Concurrent-run test: in two shells simultaneously, run `D=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"); echo "$D"; sleep 2; rm -rf "$D"` — confirm both produce distinct directories and neither collides.
10. No `install.sh` re-deploy needed: this change touches only the SKILL.md in the repo; `~/.claude/skills/multi-agent-review/SKILL.md` is refreshed on the next user invocation of `bash ./install.sh`. The skill is re-read per invocation.

## Testing strategy

- **Smoke tests (manual, MANDATORY)**:
  - Directory permissions: `D=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"); stat -c '%a %n' "$D"; rm -rf "$D"` → expect `700 <path>`.
  - Abort-orphan mode persistence (addresses T1): `D=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"); stat -c '%a %n' "$D"; ls -ld "$D"; rm -rf "$D"` — confirm mode 700 before the final `rm` (simulates what a future inspector would see for an aborted-run orphan).
  - External-user reachability: confirm that a different local user cannot `cd` into, `ls`, or `cat` files inside a freshly-created `$MARV_DIR` (when available on a multi-user host). Skippable on a single-user dev box.
  - umask non-leak (regression guard): run `umask` before and after the skill's Step 3-2b-shaped snippet inside a single shell; confirm the value is unchanged (i.e., confirm the plan's no-umask-modification contract is preserved in the implementation).
  - Concurrent run: two terminals run `D=$(mktemp -d "${TMPDIR:-/tmp}/marv-XXXXXX"); echo "$D"` simultaneously; confirm distinct paths.
- **End-to-end dry run**:
  - Invoke `/multi-agent-review` on a small test branch after this migration is deployed; confirm (a) the review artifacts still produce correctly, (b) after Step 1-5 AND after Step 3-9 completion (addresses T3), `ls /tmp/func-findings.txt /tmp/sec-findings.txt /tmp/test-findings.txt /tmp/seed-*.txt 2>&1` returns `No such file or directory` for each path, (c) a `/tmp/marv-*` directory exists during Phase 3 and is cleaned up after Step 3-9, (d) **Seed Finding Disposition observability (addresses T2)**: each sub-agent's output contains a `## Seed Finding Disposition` section with actual `Verified`/`Rejected` entries rather than the fallback `Seed unavailable — no dispositions to record.` A fallback phrase signals that `$MARV_DIR` was not substituted into the sub-agent prompt with its literal path — fix the orchestrator's substitution before proceeding.
  - Run two `/multi-agent-review` sessions in parallel on unrelated branches; confirm each session's findings are correctly isolated in its own `$MARV_DIR`.
- **Cross-cutting grep checks** (run after implementation, before commit):
  - The five `grep` verifications listed in Implementation step 7.
- **No automated tests**: config-only repo; per skill policy, testing expert MUST NOT raise Major/Critical recommendations for adding automated tests.

## Considerations & constraints

### Risks

- **Variable persistence across Bash tool invocations**: Claude's Bash tool is stateless between calls. The orchestrator must capture the literal `MARV_DIR` path and use it in subsequent tool calls, not assume `$MARV_DIR` is defined in a fresh shell. The plan documents this explicitly; failure to follow it would cause Step 3-4's `cat` command to hit an empty variable and fail. Mitigation: the skill text explicitly says "substitute the literal path", and the Step 3-2b command includes `echo "MARV_DIR=$MARV_DIR"` to make the value visible to the orchestrator.
- **Mid-run abort leaves orphan directories**: if the skill is aborted between Step 3-2b and Step 3-9, the `marv-XXXXXX` directory persists in `/tmp`. Mitigation: `/tmp` is typically cleaned by the OS on reboot or by `systemd-tmpfiles`; the directory itself is mode `0700`, so contents remain inaccessible to other local users while they linger; the `marv-` prefix makes manual cleanup easy (`rm -rf /tmp/marv-*`).
- **Template-substitution error**: if the orchestrator forgets to substitute `$MARV_DIR` with the literal path when rendering the Step 3-3 sub-agent prompt, the sub-agent sees the literal string `$MARV_DIR/seed-func.txt` and cannot read the file. Mitigation: the template text calls out the substitution obligation explicitly; the sub-agent's verification contract would reject a "seed path not found" as equivalent to "seed unavailable" and fall back to full-diff review, so the worst case is loss of the token-saving optimization for that run — not a correctness failure.
- **`mktemp -d -t marv-XXXXXX` portability**: the `-t TEMPLATE` flag is supported on Linux (GNU coreutils) and BSD (including macOS), which are the two platforms this repo targets. Verified in `man mktemp` for both.

### Constraints

- The skill is narrative (Markdown instruction for Claude to follow), not a self-contained shell script. The directory-sharing contract between steps is orchestration-level, not process-level.
- `umask` is intentionally left untouched by the skill narrative. Confidentiality is enforced by the directory-level mode `0700` that `mktemp -d` produces; this avoids any possibility of a restrictive umask leaking into unrelated later commands within the same skill run.

### Out of scope

- `hooks/` changes (helper-level, not skill-level — per the user's scope statement).
- Lockfile / flock-based coordination between concurrent runs — with per-run tmpdirs, isolation is strict and no cross-run locking is needed.
- GC policy for orphan `marv-*` directories — relying on OS `/tmp` policy is acceptable for a manual-use config repo.
- Other skills (`pr-create`, `simplify`, `test-gen`, `explore`) — confirmed not to use the hard-coded `/tmp/*-findings.txt` pattern via `grep -rn '/tmp/' skills/`.

## User operation scenarios

1. **Normal path — single session**: User runs `/multi-agent-review`. Step 3-2b creates `/tmp/marv-aB3k9X/` (mode 700), writes three seed files inside. Step 3-3 sub-agents read from `/tmp/marv-aB3k9X/seed-{func,sec,test}.txt`. Step 3-4 merges `/tmp/marv-aB3k9X/{func,sec,test}-findings.txt`. Step 3-9 cleans up the directory.
2. **Parallel sessions — `/loop` or two IDE windows**: Two invocations of `/multi-agent-review` run concurrently on different branches. Each gets its own `mktemp -d` (e.g., `/tmp/marv-aB3k9X` and `/tmp/marv-Pz7M1v`). They read/write independently; no merge-file corruption. Each cleans up its own dir at Step 3-9.
3. **Shared multi-user host**: User A runs `/multi-agent-review`; User B is logged in on the same host. The `mktemp -d` directory is owned by User A with mode 700; User B cannot traverse into it or list its contents regardless of the internal file modes. No cross-user leakage.
4. **Abort mid-run**: User Ctrl-C's the skill after Step 3-2b but before Step 3-9. `/tmp/marv-aB3k9X` persists with directory mode 700, still unreachable by other users. User or OS cleanup removes it later.
5. **Orchestrator path-substitution mistake**: Orchestrator accidentally renders the Step 3-3 prompt with the literal string `$MARV_DIR/seed-func.txt` instead of the absolute path. Sub-agent tries to read that path, gets "file not found". Sub-agent's template logic treats this the same as "seed unavailable or truncated" (branch (a) of the three-way conditional) and falls back to full-diff review. Correctness preserved; only token savings are lost for that sub-agent.
6. **No migration mid-flight**: The change is purely a SKILL.md text update. The next invocation of `/multi-agent-review` reads the new text and follows the new convention. There is no partially-migrated state because each `/multi-agent-review` invocation starts fresh.
