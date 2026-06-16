# Code Review: llamacpp-backend

Date: 2026-06-16
Review round: 1 (triangulate Phase 3, standalone branch review)
Branch: feature/llamacpp-backend
Scope: `git diff main...HEAD` — local-LLM hook refactor into a common dispatcher
(`llm-utils.sh`) + two backend providers (`ollama-backend.sh`, `llamacpp-backend.sh`)
+ command library (`llm-commands.sh`), plus the new llama.cpp backend.

Project context: Claude Code config repo. Test infrastructure: bats (532 tests).
Backends used for this review: 3 Claude expert sub-agents (functionality / security
/ testing). Ollama-based pre-screen skipped (server intermittently down this session).

## Functionality Findings

### F-1 [Major] agent-review local backend gated on Ollama only — RESOLVED
- File: `skills/agent-review/review-backend.sh:36-52`
- Problem: `_ollama_available` decided local-backend availability solely by probing
  Ollama `/api/version`. After this branch added llama.cpp, a llama.cpp-only host
  (Ollama down) would report the free local reviewer unavailable and fall through to
  codex/claude — spending external quota/tokens, defeating the "free+private first"
  contract. A regression introduced by the same change that added llama.cpp.
- Fix: made the gate backend-aware — returns 0 when `llamacpp_available` succeeds
  (auto-preferred local backend), else falls back to the Ollama `/api/version` probe.

### F-2 [Minor] max_tokens:0 forwarded verbatim — RESOLVED
- File: `hooks/llamacpp-backend.sh:_llamacpp_request`, `hooks/ollama-backend.sh:_ollama_generate`
- Problem: `num_predict` guarded unset/empty but not literal `0`; a `0` would request
  a zero-token generation. Latent (no current caller passes 0).
- Fix: both providers now coerce empty OR `0` to the 16384 default.

### F-3 [Minor] install.sh sync deletes user-added top-level hooks — ACCEPTED
- Anti-Deferral check: acceptable risk (documented "source of truth" semantics).
- Worst case: a user's personal top-level `~/.claude/hooks/*.sh` not in the repo is
  removed on reinstall (one stdout line of notice). Likelihood: low (repo explicitly
  owns hooks/, overwritten on install). Cost to fix: a manifest allowlist (~15 LOC) —
  not justified vs. the documented intent. Subdirs and `hooks/lib/` are unaffected.

### F-4 [Minor] Ollama discovery runs at source even on llama.cpp-first hosts — ACCEPTED
- Anti-Deferral check: acceptable risk (pre-existing source-time behavior).
- Worst case: extra discovery latency on `agent-review` detection. Likelihood: every
  detect. Cost to fix: make Ollama discovery lazy (function-triggered) — a larger
  provider change, out of scope for this PR. F-1's short-circuit reduces the waste.

## Security Findings

No findings. The new llama.cpp path mirrors the audited Ollama path: response-body
suppression on non-200 (no echo of user code), jq `--arg`/`--rawfile` + `-d @file`
(no shell interpolation of env-supplied model/host into a command string), refs/prompts
passed as separate args. Local-first plaintext posture is unchanged and accepted (no
new attacker channel). `install.sh` rm-loop is directory-scoped (glob over the install
hooks dir, `basename` only for the existence check) and symlink-safe. settings.json
allowlist replaced one-for-one (no over-grant).

## Testing Findings

### T-1 [Critical] new llamacpp-backend.sh shipped with zero tests — RESOLVED
- Added `tests/llamacpp-backend.bats` (23 tests): model mapping (defaults / env
  override / passthrough), backend selection (pin / invalid→auto / auto-up / auto-down),
  host resolution (reachable / unreachable / model-filtering / single-record
  trailing-newline regression), pinned-host cache bypass, request paths (200 / 200+200
  / reasoning_content fallback / empty-stdin / HTTP 500 / 500-no-body-leak / no-host),
  and end-to-end `llm_request` through the llama.cpp arm + the num_predict=0 coercion.

### T-2 [Major] LLM_BACKEND=ollama pin masked the llama.cpp dispatch arm — RESOLVED
- The new `tests/llamacpp-backend.bats` pins `LLM_BACKEND=llamacpp` and asserts the
  `/v1/chat/completions` endpoint is hit, exercising the previously-unreached arm.

### T-3 [Major] install.sh stale-hook removal loop untested — RESOLVED
- Added two `tests/install.bats` cases: a stale hook absent from source is removed
  (with the "Removed stale hook" notice); a hook present in source survives and is
  overwritten from source.

### T-4 [Minor] round-robin tests remain meaningful after SCRIPT→llm-utils.sh — NO ACTION
- Verified: re-source rotation still advances (no source guard on llm-utils.sh). The
  rotation test will catch a future guard regression.

## Recurring Issue Check (consolidated)
- R1/R17/R22 helper reuse: PASS (providers reuse shared helpers; no reimplementation).
- R2 constants: PASS (llama.cpp defaults env-overridable; 300s TTL duplicated across
  two providers — pre-existing, not extracted).
- R3 propagation: PASS (no stale `ollama-utils.sh`/`resolve-ollama-host.sh` refs
  outside docs/archive; the only literal `OLLAMA-INPUT-SEPARATOR` retained is an
  intentional cross-file wire-protocol constant).
- R10 circular dep: PASS (acyclic: llm-utils → {ollama,llamacpp}-backend leaves).
- R25 persist/hydrate: PASS (llama.cpp cache write/read symmetric; pin bypasses both).
- RS1/RS3/RS4/R31: PASS (see Security).
- RT1/RT6/RT7: addressed by T-1..T-3.

## Resolution Status
- F-1: fixed — review-backend.sh `_ollama_available` backend-aware.
- F-2: fixed — both providers coerce num_predict 0/empty → default.
- F-3, F-4: accepted with Anti-Deferral justification above.
- T-1, T-2: fixed — tests/llamacpp-backend.bats (23 tests).
- T-3: fixed — tests/install.bats (+2 cases).
- Verification: full suite 532/532 pass; `review-backend.sh detect` lists ollama when
  llama.cpp reachable; shellcheck/bash -n clean on changed files.
