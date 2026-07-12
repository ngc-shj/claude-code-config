# Coding Deviation Log: retrospect-mining-system

## D1 — C10 latency above the eyeball target (accepted)

- Plan: C10 acceptance "expected <50ms" (eyeball check against the existing hook class).
- Actual: `session-retrospect-check.sh` benches at ~80ms avg (p95 ~88ms) — it shells out
  to `retro-state.sh` three times (`config` / `due --prompt-guard` / `mark-prompted`),
  each paying process startup + jq, versus single-process block-* hooks (~7–8ms).
- Disposition: accepted. 80ms is 1.6% of the hook's 5s timeout, runs once per session
  start, and the three shell-outs are the cost of the C2 single-owner design (S7) —
  inlining state parsing into C3 to save ~50ms would reopen the trusted-read
  single-chokepoint contract. Recorded for the C10 eyeball check.

## D2 — retro-state.sh usage() implemented as a heredoc, not doc-comment extraction

- Plan: no specific usage mechanism contracted. First implementation extracted the
  header comment by line numbers (brittle against edits); replaced with an explicit
  heredoc before tests were written. No contract impact.

## D4 — containment check must follow symlinks to their target (bug fixed in impl)

- Plan: C4/S2 "candidate file paths are resolved with a portable primitive … rejected
  unless contained within the configured repo directory".
- Initial impl resolved only the containing DIRECTORY, so a symlink INSIDE the repo whose
  target escaped the repo passed the check (its directory was inside the repo). Fixed
  `_resolve_contained` to `readlink` the entry and re-resolve against the target's real
  directory before the containment test. Caught by the S2 out-of-repo-symlink bats case
  and E2E; no contract change — the fix makes the impl match the locked S2 intent.

## D5 — transcripts Stage-1 filter must be per-line, not whole-file (bug fixed in impl)

- Plan: C4 transcripts "Stage 1 (structural, jq): extract only events matching failure
  signatures".
- Initial impl ran one `jq select` over the whole `.jsonl` file with `2>/dev/null ||
  file_events=""`, so a single blank separator line (transcripts routinely contain them)
  made jq error and discarded ALL of that file's events. Fixed to parse each line
  independently, suppressing per-line parse errors. Preserves the privacy invariant (errors
  still to /dev/null) while making event extraction actually work. Caught by the canary
  privacy bats cases + E2E.

## D6 — transcripts loopback gate needs a reachability probe (behavior clarified in impl)

- Plan: C4 fail-closed "LLM offline (or non-loopback without override) → … deferred".
- The S3 egress gate (all hosts loopback / consented) passing does not guarantee the host
  ANSWERS. A configured-but-unreachable loopback host would have let Stage 2 run, distill
  nothing, and advance the cursor — silently dropping content. Impl now probes reachability
  (an 8-token `llm_request` after the egress gate) and treats a non-answering backend as
  offline → deferred, cursor preserved. This is the fail-safe reading of the locked
  contract, not a deviation from it; recorded for review visibility.

## D3 — seed with config absent produces empty object expansion (edge noted)

- Plan: C2 seed expands artifacts/github scalars "to an object mapping every key
  currently configured". With no config present, the configured-repo list is empty, so
  the expansion writes `{}` (validator passes vacuously). Harmless — prescreen treats a
  missing per-repo key as epoch — and the README setup order (copy config, then seed)
  avoids the path. Recorded as an observed edge, not a behavior change.
