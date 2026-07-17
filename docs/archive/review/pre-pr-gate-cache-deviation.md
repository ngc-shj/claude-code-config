# Coding Deviation Log: pre-pr-gate-cache

## D1 — compute_fingerprint: sha256sum stage wrapped in `(cd "$repo_root" && ...)`

- Plan (C1 / Technical approach) specified the untracked-file pipeline as
  `git ls-files --others --exclude-standard -z | LC_ALL=C sort -z | xargs -0 -r sha256sum`
  without a cwd for the final stage. `git ls-files` prints repo-root-relative
  paths, and `sha256sum` resolves them against the caller's cwd — the
  pipeline as written fails whenever the hook runs from outside the repo
  root, violating the plan's own invariant I1-2 ("output depends only on
  repo content ... not on cwd").
- Implemented as `| (cd "$repo_root" && xargs -0 -r sha256sum)`.
- Classification: necessary correction to satisfy a locked invariant, not a
  behavioral deviation. Contract outputs unchanged.

## D2 — cache_fresh exports CACHE_HIT_AGE; breadcrumb no longer re-reads the cache file

- Plan (C3/N3) requires the skip breadcrumb to state the cached pass's age
  but did not specify how the age is obtained. The sub-agent's first
  implementation re-read the cache file after cache_fresh succeeded to
  extract the stamp for display; orchestrator review flagged that the
  second read races a concurrent replace — non-numeric data reaching
  `$((now - stamp))` aborts the hook under `set -e`, and a crashed
  PreToolUse hook degrades every Bash tool call.
- Implemented: cache_fresh sets `CACHE_HIT_AGE` from the value it already
  validated; both breadcrumb call sites consume it. Single read, no TOCTOU.
- Classification: implementation hardening within contract bounds (N1
  fail-safe direction); observable behavior unchanged.

## D3 — hash-input line format changed by the `./`-prefix fix (2026-07-17, Phase 3 round 3)

- The round-2→round-3 fix (`sha256sum -- "./$f"` read loop replacing the
  xargs form) changes each hash-input line from `<hash>  name` to
  `<hash>  ./name`, so the final fingerprint differs across code versions
  for any tree with ≥1 untracked non-ignored file. Consequence: a cache
  entry recorded by the previous commit's code misses exactly once under
  the new code (full run, re-record) — fail-safe, self-healing, bounded by
  the 1 h default TTL, and the branch is unmerged so no released users hold
  old-format caches. The prefixed name in the output line is part of the
  fix (it encodes the disambiguation), not incidental — stripping it would
  reintroduce the `-`/`--` ambiguity.
- Scope note: the plan C1 acceptance "same tree → same hash" holds within a
  single code version; cross-version stability is explicitly NOT a contract
  property.

## D4 — cache flipped to opt-in; fingerprint rebuilt on real worktree content (2026-07-17, external security review)

- An external review (relayed by the operator) demonstrated three gate
  bypass/DoS paths in the locked design: (1) .gitattributes clean/textconv
  filters hide tracked-content changes from `git diff HEAD` → stale skip;
  (2) `--exclude-standard` excludes ignored files a pre-PR gate may read
  (.env, generated gate state) → stale skip; (3) an untracked symlink to
  /dev/zero hangs sha256sum up to the hook's 1800 s timeout.
- All three reproduced locally before changing anything.
- Contract amendments (supersede the corresponding locked C1/C2 clauses):
  - C1: fingerprint no longer uses `git diff`. It hashes HEAD sha plus one
    type-tagged line per path (tracked ∪ untracked-non-ignored ∪ declared
    extras): regular files → exec-bit + real worktree byte hash; symlinks →
    target string, never followed; fifo/socket/device → type marker, never
    opened; missing → deletion marker. Regular files above
    PRE_PR_CACHE_MAX_FILE_BYTES (default 100 MiB) abort fingerprinting
    (no fingerprint → full run).
  - C2: caching is OPT-IN. TTL resolution: explicit PRE_PR_CACHE_TTL wins;
    otherwise 3600 iff a declaration exists (scripts/pre-pr.cache-paths
    file or exported PRE_PR_CACHE_EXTRA_PATHS — either may be empty,
    meaning "gate reads tree only"; entries may name ignored files, which
    are then fingerprint inputs); otherwise 0 (gate always runs).
    Malformed PRE_PR_CACHE_TTL is treated as unset (note wording changed
    accordingly).
- Side effects: exec-bit changes on tracked files now invalidate the cache
  (shrinks the previously-accepted permission-bit blind spot to non-exec
  mode bits); the F5/S1 "second push skips by default" scenario now
  requires the one-time opt-in declaration.
- Tests: T19 reworked (malformed TTL → cache off, runs); T20-T27 added
  (default-off, declaration enable, ignored-extra invalidation,
  clean-filter invalidation, symlink no-hang + retarget, exec-bit flip,
  tracked delete, size cap). All are red against the pre-D4
  implementation by construction (each reproduces one demonstrated
  bypass/DoS).
- Amendment (round 6): the "type-tagged line per path" grammar above is
  NUL-framed (type tag and every field NUL-terminated, streamed straight
  into the hasher — never through a command substitution, which drops
  NULs). A newline-delimited grammar was proven forgeable via symlink
  targets containing "\n"/"\t" (two distinct states → one fingerprint →
  stale skip); NUL cannot appear in a git path or readlink output, so the
  framing is injective. Red-proven by T28.

## D5 — directory / submodule-gitlink inputs fail closed (2026-07-18, external security review round 2)

- The round-6 `_hash_path` mapped every non-regular, non-symlink, existing
  entry to a single `O` marker — including DIRECTORIES. A directory's
  contents were therefore never in the fingerprint. Two bypasses reproduced
  before fixing: (1) a declared IGNORED directory (`scripts/pre-pr.cache-paths`
  naming `.gate/`) whose `.gate/state` changed SAFE→UNSAFE stayed a cache
  hit; (2) a git submodule gitlink — a directory in the worktree — dirtied
  via `sub/gate.state` stayed a hit even though the super-repo reported
  `M sub`.
- Fix: `_hash_path` now detects `[ -d "$p" ]` and returns non-zero →
  compute_fingerprint aborts → no fingerprint → full run (fail closed).
  Directories are NOT recursively hashed by design: a submodule is its own
  repo with its own ignore rules, dirty/untracked state, and nested
  submodules — enumerating it correctly is a second fingerprint engine, out
  of scope. Consequence: a repo whose pre-PR gate reads inside a submodule
  or a declared directory does not get caching (safe direction). `git
  ls-files` never yields a plain tracked directory (only gitlinks); the
  other directory source is a declared-path entry.
- Tests: T30 (declared ignored dir → never cached, change never skipped),
  T31 (submodule gitlink → never cached, submodule dirt never skips). Both
  red-proven against the round-6 `O`-grammar hook.

## D6 — FIFO / socket / device inputs fail closed (2026-07-18, external security review round 3)

- After D5 closed the directory branch, the remaining `_hash_path` `else`
  still mapped every special file (FIFO, socket, block/char device) to a
  constant `O\0<path>` marker. Reproduced: a declared FIFO `gate-node`
  passed and was cached; swapping it for a Unix socket (a state a gate
  testing `[ -p ]` would reject) left the fingerprint unchanged as `O`, so
  the failing gate was skipped.
- Fix: the `else` now `return 1` — a special file aborts fingerprinting
  (no fingerprint -> full run, fail closed). A type marker cannot represent
  a FIFO's/device's dynamic content or a type swap, and opening one to hash
  could block indefinitely (the hang class the symlink non-follow guard
  already avoids). The `O` record type is therefore no longer emitted by
  any path; `_hash_path` now yields only `L`/`F`/`D` records or a
  fail-closed non-zero.
- Test: T32 (declared FIFO -> never cached; FIFO->socket swap never skips),
  red-proven against the D5 (`O`-emitting) implementation.
