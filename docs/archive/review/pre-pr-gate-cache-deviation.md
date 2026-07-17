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

