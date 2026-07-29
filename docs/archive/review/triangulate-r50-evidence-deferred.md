# Deferred: R50 verification-evidence mechanism

Date: 2026-07-28
Status: **deferred at plan stage** — not implemented, not scheduled. Split out of `triangulate-rt10-r50-detection-hooks-plan.md` after two review rounds.

This document preserves the design state so the work is not re-derived from scratch. It is not a plan to implement; every open item below must be settled before it becomes one.

## What was wanted

R50 says a verification's verdict is only as good as its own preconditions. The mechanization aimed at precondition (i) — the command's own exit status — plus part of (iii), subject identity:

- `hooks/run-verified.sh` wraps a verification command, passes its output through unchanged, records the command's own status (never a pipeline aggregate, R44), and exits with it.
- `hooks/check-verification-evidence.sh` validates a `## Verification Evidence` block in the round artifact: a whitelist record grammar, non-zero exits rejected, stale subject rejected, completeness checked against the recorder's own log.
- A new section in the Phase 3 artifact template holding either the records or an exact N/A line.

The user chose this shape over a prose-lint tripwire, and later chose to keep and harden the wrapper rather than drop it.

## Why it stopped

Each review round's fix grew new surface rather than closing the class:

| Round | Fix applied | Surface it created |
|---|---|---|
| 1 → 2 | Round binding via `--start-round` | a **truncation** primitive on an env-controlled path, with no contract, no axis, no mutation; and an author-resettable window that restores the selective-omission threat the completeness check was added to close |
| 1 → 2 | Containment via the extracted `_resolve_contained` | a **TOCTOU** window: the path is resolved before the wrapped command runs, and the wrapped command is the analyzed repo's own build/test suite, which can replace the resolved path with a symlink before the append |
| 1 → 2 | Redaction via the existing `cmd_scrub` | a hard dependency on `jq` (top-level gate) and `perl`, against the no-new-dependency requirement; and a filter that is not byte-transparent (appends `\n` to every argument, caps lines at 2000 chars, redacts `/home/<user>/…` and 20+ char tokens), contradicting the byte-exactness the record's own acceptance criteria demand |

That is the pattern R47 and R42 clause ①b name: when the third fix of the same class opens a new hole, replace the mechanism instead of patching it.

## Open items — each must be decided before implementation

1. **Containment root (Critical, unresolved).** `_resolve_contained(file, root)` needs a concrete root. Rooting at the XDG evidence dir rejects every `mktemp -d` fixture, so the test suite cannot run. Rooting at `dirname "$VERIFY_EVIDENCE"` is containment against the attacker's own choice and accepts `VERIFY_EVIDENCE=~/.claude/hooks/<any>.sh`, which is the round-1 Critical unchanged. A two-part predicate (root allowlist + a denylist refusing anything under `~/.claude/`) was proposed but not designed.
2. **TOCTOU (Critical, unresolved).** Resolution must be bound to the inode that is written — `exec 9>>"$resolved"` immediately after resolution (cost: the wrapped command inherits fd 9), or re-resolution immediately before the append (cost: narrows rather than closes). Neither was chosen.
3. **`XDG_STATE_HOME` is itself untrusted (RS5).** One variable moves both the default evidence path and the root it is contained against. `XDG_STATE_HOME=$HOME/.claude` makes an installed-hook target genuinely "contained".
4. **`--start-round` has no contract.** Path resolution, argv disambiguation (it is a subcommand of a script whose contract is "execute argv"), refusal conditions, exit codes — all unspecified. It is destructive, so R31 applies.
5. **Redaction.** Either extract a narrowed argv-appropriate redactor (a second adjudicator needing an explicit R48 argument) or accept `jq`+`perl` and restate the byte-identity criteria as "byte-exact after a declared normalisation", recording that a trailing-newline argument becomes unrepresentable and that shas and `/home/` paths are redacted — which degrades the subject identity the record exists to carry.
6. **C3 deadlock.** `jsonl ⊆ artifact` composed with "any non-zero record fails" makes a red-then-green round unpassable: pasting the failing record fails one check, omitting it fails the other. The fix is last-record-per-distinct-`cmd` supersession, which was recommended in round 1 and not implemented.
7. **`settings.local.json`.** The decision to add no `permissions.allow` entry is enforced only in `settings.json`, which is the file the test can read. The permission prompt's don't-ask-again writes the entry into `settings.local.json`, which `install.sh` never touches and no test reads — and that file already contains `Bash(python *)`, a live member of the same argv-laundering class. Whether `permissions.ask` outranks a local allow was not verified against the harness.
8. **The argv-laundering invariant is not mechanically decidable.** "A hook that executes caller-supplied argv" has no predicate a bats test can apply: a `"$@"` grep reds on five `*`-allowlisted scripts, and `hooks/check-migrations.sh:16` genuinely executes caller argv while being `*`-allowlisted today. A machine-readable marker in script headers was proposed, so membership is derivable from code rather than from a list.
9. **Pre-existing laundering entries.** `permissions.allow` currently holds `Bash(find *)`, `Bash(node *)`, `Bash(npx *)` and `Bash(docker run *)`, each of which launders the deny/ask list the same way. Holding a new script to a standard the surrounding config does not meet is defensible policy, but it must be stated, or the next reviewer reads the omission as unnecessary. R34 applies: defer with a cost justification, not silently.
10. **RT9 round-trip coverage.** The producer emits five fields and the validator decides on four; the proposed corpus varied only `cmd`. `head` can legitimately be the literal `no-git`, which an anchored 40-hex grammar would reject — twin drift in exactly the field pair the round-trip exists to protect.

## What is worth keeping if this restarts

- The record grammar as a repo-owned whitelist is sound, and the closure claim scoped to the grammar (never to the Markdown block locator) is the right calibration.
- The block locator's honest limits: fence-state tracking, both fence characters with CommonMark run-length matching, and a uniqueness requirement — with indented code blocks, Setext headings and container-nested sections declared unhandled.
- Reading the N/A literal from the real phase file rather than duplicating it (RT5).
- The finding that a prose-claim lint ("tests pass", "N passed") is surface-form adjudication and must not be the design.
- The scope-out that only precondition (i) and part of (iii) are mechanizable at all; (ii), (iv), (v), (vi) stay human-owned, and any rule-row sentence must say so or a reader inside a 50-line checklist will read "Mechanical detection" as "covered".

## Alternative not yet explored

Drop the wrapper entirely and keep only the artifact-structure validator, with the orchestrator recording `exit=$?` by hand. This removes items 1-5 and 7-9 outright. It was rated against keeping the wrapper before round 2's measurements existed; the evidence since suggests the wrapper's marginal value — preventing transcription error — is small next to the surface it carries, since the author curates the block either way.
