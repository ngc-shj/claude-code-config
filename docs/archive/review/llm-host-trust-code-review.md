# Code Review: llm-host-trust

Date: 2026-07-11
Review rounds: 5 (Round 1 = external security audit of `main`; Round 2 = triangulate
verification of the S1/S2 fixes; Round 3 = incremental verification of Round-2
finding fixes; Round 4 = user review of the committed branch, finding S3;
Round 5 = triangulate verification of the S3 fix)
Termination: Round 5 — Functionality and Security "No findings"; Testing's T6 was
resolved by applying, verbatim, the test the Testing expert authored AND
red/green-mutation-verified inside the same round, so its verification
obligation was discharged by the finding's author (no Round 6).

## Round 1 — external security audit findings (verified by orchestrator)

### S1 [Critical]: unauthenticated LAN hosts can receive code and diffs

- File: `hooks/ollama-backend.sh` (`_probe_servers`, `_is_ollama_up`), `hooks/pre-review.sh:119-143`
- Evidence: any mDNS-enumerated or Tailscale-enumerated host answering
  `/api/version` joined the round-robin pool; `_ollama_generate` then POSTs
  prompts (git diffs and full changed-file contents from `pre-review.sh`) to
  `$host/api/generate` over plain HTTP with no server authentication.
- Attacker: any device on the same LAN able to advertise mDNS and serve a fake
  Ollama API (mimic `/api/version` + `/api/tags`).
- Impact: exfiltration of private code, unpublished vulnerabilities, config
  values, mistakenly committed credentials; poisoning of downstream fix
  decisions via fake review output.
- Additional: `README.md` and `skills/agent-review/SKILL.md` described this
  path as `private` / `local-only`.
- Status: **Fixed** (see Resolution Status).

### S2 [Major]: predictable /tmp caches trusted without ownership checks

- File: `hooks/ollama-backend.sh` (cache at `/tmp/.ollama-host-cache-<uid>`),
  `hooks/llamacpp-backend.sh` (`/tmp/.llamacpp-host-cache-<uid>`), plus derived
  `.rr` round-robin counter files read by `_pick_round_robin` (`hooks/llm-utils.sh`).
- Evidence: reads checked only regular-file + non-symlink + mtime < 5 min — not
  owner UID or mode. On a multi-user host, another user can pre-create the
  predictable path with their own server URL + model list; the victim process
  skips re-discovery and sends prompts there.
- Status: **Fixed** (see Resolution Status).

## Fix Summary (what Round 2 reviewed)

1. **S1** — auto-discovery is now opt-in. New `OLLAMA_DISCOVERY` env gate
   (`_ollama_discovery_enabled` in `hooks/ollama-backend.sh`): unset/`0`/`off`/`none`
   (default) disables both sources; `1`/`on`/`all` enables both; or a
   space/comma list of `mdns` / `tailscale`. `OLLAMA_EXTRA_HOSTS` is the primary
   explicit (trusted) multi-server configuration; `OLLAMA_HOST` pin unchanged.
   Trust model documented in the file header and README; `private`/`local-only`
   claims removed from README and `skills/agent-review/SKILL.md`.
2. **S2** — caches moved out of world-writable `/tmp`. New `_llm_state_dir`
   (`hooks/llm-utils.sh`): `XDG_RUNTIME_DIR` → `XDG_CACHE_HOME` → `~/.cache`,
   directory `claude-llm-hooks` created `0700`, accepted only if non-symlink
   directory owned by the current user, `chmod 0700` enforced; falls back to a
   per-process `mktemp -d`. New `_llm_trusted_file` predicate (regular file,
   non-symlink, owned by current user via `[ -O ]`) guards every cache and
   round-robin counter read in both backends and `_pick_round_robin`.
3. **Tests** — existing discovery tests updated to opt in explicitly; new
   `trust:` and `state dir:` tests added.

## Round 2 — expert verification of the S1/S2 fixes

### Functionality Findings

No findings. Verified directly: `_ollama_discovery_enabled` parsing across 19
value cases (all fail closed on unknown/malformed input); back-compat for
`OLLAMA_HOST` pin and `OLLAMA_EXTRA_HOSTS`-only users unchanged; zero-config
users degrade gracefully to localhost with the change documented; `_llm_state_dir`
edge cases (no HOME/XDG, unwritable TMPDIR, pre-existing wrong-mode dir,
source-time command substitution ordering) all degrade without crashing under
`set -euo pipefail`; no other consumer of the old /tmp cache paths; no stale
doc still claims default-on discovery; R43 — no boundary widening.

### Security Findings

No findings. Verified: no code path bypasses the discovery gate (single call
site per source, all entry points route through `llm-utils.sh`); `mkdir -p -m
0700` caveat neutralized by unconditional `chmod 0700`; `[ -O ]` ownership is
the operative invariant defeating cache preseeding, applied at every read site;
mktemp fallback is 0700 + unpredictable, so the "never world-writable /tmp"
claim holds; `_OLLAMA_HOST_CACHE`/`_LLAMACPP_HOST_CACHE` env overrides are not
a new abuse channel (require env control, a stronger precondition); README
trust-model wording accurate (plain-HTTP residual risk neither over- nor
understated); R43 — every touched predicate strictly narrows.

### Testing Findings

- T1 [Major]: `OLLAMA_DISCOVERY` alias values `on`/`all`/`none` untested —
  mutation (misgrouping `none` into the enable branch = fail-open on the S1
  invariant) left the suite green. **Resolved in Round 3.**
- T2 [Major]: comma-separated list form untested — dropping `${cfg//,/ }`
  translation left the suite green. **Resolved in Round 3.**
- T3 [Major]: `_pick_round_robin`'s trusted-file guard on the `.rr` counter had
  no red-on-revert test. **Resolved in Round 3.**
- T4 [Minor] [Adjacent → Security]: `_llm_trusted_file`'s `[ -O ]` clause has no
  test seam (bats cannot create foreign-uid files without root); symlink tests
  are not a proxy for it. **Closed in Round 3 — accepted (see Resolution Status).**
- T5 [Minor]: `_llm_state_dir`'s `~/.cache` tier and final mktemp tier untested.
  **Resolved in Round 3.**

## Round 3 — incremental verification (delta: test-only additions)

- Functionality: No findings. Confirmed the delta is purely appended tests
  (`@@ -584,0` pure addition), each a non-tautological exercise of real
  production code paths.
- Security: No findings. Confirmed hooks byte-identical to Round 2; all 7 new
  tests assert restrictive behavior; no test writes outside `BATS_TEST_TMPDIR`;
  R43 — nothing widened. Delivered the T4 disposition (below).
- Testing: No new findings. Independently re-ran all mutations: T1/T2/T3/T5
  fixes are load-bearing (each goes red when its guard/branch is reverted);
  no vacuous assertions, no state leakage, subshell env isolation verified,
  stat portability idiom consistent. One non-defect observation (missing `-d`
  assert in the `~/.cache` test) applied directly under tightening-only skip.

## Round 4 — user review of the committed branch

### S3 [Major]: cache reuse survives trust-configuration revocation for up to 5 min

- File: `hooks/ollama-backend.sh` (`_resolve_ollama_servers` cache read)
- Evidence: cache validity was judged only by owner/symlink/mtime; the current
  `OLLAMA_DISCOVERY`, `OLLAMA_EXTRA_HOSTS`, and each record's provenance were
  not part of the cache key. After e.g. `OLLAMA_DISCOVERY=mdns` cached an
  attacker's server, unsetting the opt-in still served the fresh cache — the
  trust-boundary revocation was not immediate. The pre-fix test
  "cache: fresh cache returns cached pool" codified this behavior.
- Status: **Fixed in Round 5** (see Resolution Status).

## Round 5 — expert verification of the S3 fix

- Functionality: No findings. The stale-cache fallback concern is unreachable
  for real callers (`_resolve_ollama_servers` always refreshes at source time
  before `ollama_host_for_model` can run); `tail -n +2` is POSIX; unset vs
  empty `OLLAMA_EXTRA_HOSTS` fingerprint identically; legacy headerless cache
  re-probes exactly once; `write_cache` helper correct in both heredoc and
  pipe forms; R43 — strictly narrowing.
- Security: No findings. Exactly two cache read sites, both routed through
  `_ollama_read_cache`; fingerprint unforgeable via `OLLAMA_EXTRA_HOSTS`
  (booleans precede the free-form field and derive solely from
  `OLLAMA_DISCOVERY`; embedded newlines cause only spurious re-probes);
  header/tail double-open TOCTOU is self-attack-only inside the 0700
  owned dir; llamacpp backend structurally immune (unpinned candidates are
  localhost-only, pinned path never touches the cache); alias normalization
  (1/on/all) verified as identical effective source sets, not widening;
  `.rr` counters carry only a rotation index — correctly out of
  fingerprint scope. R43 — no widening.
- Testing: T6 [Major] — `ollama_host_for_model`'s freshness branch had no
  dedicated red-on-revert test (only `_resolve_ollama_servers`' branch was
  covered). The expert authored the exact missing test and verified it green
  on the fix and red under the freshness-mutation. **Resolved: test applied
  verbatim.** All 6 S3 regression tests independently re-verified as
  load-bearing and non-vacuous; both orchestrator mutations reproduced.

## Round 6 — backend-agnostic trusted host list (`LLM_TRUSTED_HOSTS`)

Follow-up feature (user request): the trusted host list should serve BOTH
backends, not just Ollama. `LLM_TRUSTED_HOSTS` is now consumed by
ollama-backend.sh (probed with `OLLAMA_EXTRA_HOSTS`) and llamacpp-backend.sh
(unpinned candidates = `LLM_TRUSTED_HOSTS` + localhost:8080). Cache read/write
was factored into shared `_llm_cached_records` / `_llm_write_cache`
(llm-utils.sh); because llama.cpp's unpinned candidate set became
config-dependent, its cache gained the same S3 fingerprint binding — otherwise
llama.cpp would be an uncovered member of the S3 vulnerability class (R42:
audit scope was the seed, not the set). Fingerprint field renamed `extra=` →
`hosts=` (committed-era caches auto-invalidate once).

### Functionality Findings
- F1 [Major]: unquoted `set -- $var` / `for e in $var` word-splits in the two
  new fingerprint functions AND the candidate loops glob-expand a host entry
  containing `*`/`?`/`[...]` against the hook's CWD — ballooning the candidate
  list into every filename in the working directory and thrashing the cache.
  A regression I introduced (Round-5 fingerprint used the quoted form).
  **Fixed** (see Resolution Status).
- F2 [Minor]: a permanently-down trusted host is re-probed (~2 s) on every hook
  call — pre-existing "down is not cached" behavior, but its latency now scales
  with the trusted-list size. **Documented** (README trust-list note).

### Security Findings
No findings. S3-class completeness confirmed (every config-dependent cache read
routes through the shared helpers; pinned llama.cpp paths never touch the
cache); fingerprint normalization collisions occur only for identical effective
candidate sets (safe); the llamacpp candidate widening from {localhost} to
{LLM_TRUSTED_HOSTS + localhost} is user-directed (new env must be set), not an
R43 silent widening. Note (doc nuance, not a finding): a URL-form
`LLM_TRUSTED_HOSTS` entry like `http://host:11434` is probed verbatim by
llama.cpp on `/v1/models` — harmless since the host is user-trusted either way.

### Testing Findings
No new findings on the feature tests. Independently re-verified all three
mutation guards (candidates-ignore-list, fingerprint-drops-list, shared-helper
header-compare) reproduce red. Coverage gaps (whitespace-normalization
equivalence, legacy-`extra=`-header upgrade path) assessed as defensible skips.

## Round 6 (cont.) — verification of the F1 fix

`_llm_split_hosts` / `_llm_join_hosts` added to llm-utils.sh with a `set -f`
(noglob) guard that restores the prior noglob state; all four unquoted
word-splits (2 fingerprints + 2 candidate loops) rewired through them.
Glob-safety regression tests added to both suites and mutation-verified
(re-enabling globbing turns them red). Real-environment check: a
`LLM_TRUSTED_HOSTS="host *"` config with CWD=/tmp resolves to the literal host,
not the directory listing. Full suite 582/582.

## Adjacent Findings

- T4 routed Testing → Security; disposition recorded in Resolution Status.

## Quality Warnings

None (no VAGUE / NO-EVIDENCE / UNTESTED-CLAIM flags; merge performed
mechanically by the orchestrator — Ollama merge-findings not used because the
findings sets were small and disjoint by perspective).

## Recurring Issue Check

### Functionality expert (Round 2)
R1 OK (new helpers single-sourced, reused by both backends) / R3 OK (guard
propagated to all 4 call sites) / R12 OK / R16 OK / R17 OK / R19 OK / R30 OK /
R43 checked — no widening. All other R-rules N/A for this diff.

### Security expert (Round 2)
R1 OK / R3 OK / R17 OK / R18 OK / R22 OK / R30 OK / R34 N/A (both backends
migrated together) / R43 OK (all predicates strictly narrow). RS1-RS3, RS5,
RS6 N/A; RS4 OK. All other R-rules N/A for this diff.

### Testing expert (Round 2)
R1-R3 OK / R16 OK / R17 OK / R19-R22 OK / R31 OK / R36 OK / R41 OK /
R42 noted — alias-value class coverage gap captured as T1/T2 (fixed) /
R43 OK. RS1-RS6: RS4 OK, rest N/A. RT1 OK / RT2 OK (applied to T4) /
RT3 OK / RT5 OK / RT6 satisfied (helpers covered; call-site gap = T3, fixed) /
RT7 applied (mutation testing drove T1-T3) / RT4, RT8, RT9 N/A.

## Environment Verification Report

N/A — no environment constraints declared in Phase 1 (standalone Phase 3
invocation on external audit findings). All verification paths are
`verified-local`: `bats tests/` 573/573 after the Round-5 fixes
(`bash -n` clean on all touched hooks; shellcheck unavailable in this
environment).

## Tightening-only skip — Round 3

Findings applied directly (no Round 4 review):
- [Testing observation, non-finding] [Minor] `~/.cache` fallback test asserted
  only the path string — `tests/ollama-backend.bats` ("falls back to ~/.cache"
  test) — added `[ -d "$result" ]`, applied verbatim.
Justification: scoped within the Round-3 fix range, inline minor (test
assertion depth), no security-boundary touch.

## Resolution Status

### S1 [Critical] Unauthenticated LAN hosts can receive code — Fixed
- Action: auto-discovery gated behind explicit `OLLAMA_DISCOVERY` opt-in
  (default off); explicit-host configuration is the default path; trust model
  documented; misleading privacy claims corrected.
- Cross-perspective tradeoff protocol applied: the zero-config discovery
  feature (functionality) conflicts with the confidentiality boundary
  (security). Both-satisfying designs searched: (a) recipient-side
  verification — rejected, confidentiality is crossed at delivery; (b) TLS +
  server auth — Ollama servers expose no authenticated TLS surface, cost
  exceeds scope; (c) allowlist gating of discovered hosts — equivalent to
  explicit `OLLAMA_EXTRA_HOSTS` with extra machinery, so the simpler
  explicit-hosts + opt-in-discovery design was chosen. Security-wins default
  applied: zero-config-by-default is regressed intentionally; users restore
  multi-server via one-time `OLLAMA_EXTRA_HOSTS` (or accept the documented
  risk with `OLLAMA_DISCOVERY`).
- Residual (accepted, documented in README trust model): plain-HTTP transport
  to explicitly trusted hosts. Worst case: passive LAN sniffing of code sent
  to a trusted host. Likelihood: low on user-controlled networks; mitigated
  fully by using Tailscale hostnames (WireGuard-encrypted transport).
  Cost to fix: Ollama/llama.cpp have no native authenticated-TLS surface; a
  reverse-proxy requirement is out of scope for this repo. Tracked as
  documentation guidance, not code.
- Modified files: `hooks/ollama-backend.sh`, `README.md`,
  `skills/agent-review/SKILL.md`, `tests/ollama-backend.bats`.

### S2 [Major] Predictable /tmp cache trusted without ownership checks — Fixed
- Action: per-user private state dir with ownership/symlink verification and
  0700 modes; `_llm_trusted_file` ownership check on every cache/counter read;
  atomic writes retained (mktemp + mv inside the private dir).
- Modified files: `hooks/llm-utils.sh`, `hooks/ollama-backend.sh`,
  `hooks/llamacpp-backend.sh`, `tests/ollama-backend.bats`,
  `tests/llamacpp-backend.bats`.

### T1 [Major] Alias values on/all/none untested — Fixed
- Action: three tests added (`OLLAMA_DISCOVERY=on`, `=all`, `=none`);
  mutation-verified red-on-revert by orchestrator and independently by the
  Round-3 Testing expert.
- Modified file: `tests/ollama-backend.bats`.

### T2 [Major] Comma list form untested — Fixed
- Action: `OLLAMA_DISCOVERY='mdns,tailscale'` test added; mutation-verified.
- Modified file: `tests/ollama-backend.bats`.

### T3 [Major] rr-counter guard untested — Fixed
- Action: symlinked `.rr` counter rejection test added (idx forced to 0);
  mutation-verified red when the guard is dropped to bare `[ -f ]`.
- Modified file: `tests/ollama-backend.bats`.

### T4 [Minor] `[ -O ]` ownership clause has no test seam — Accepted
- **Anti-Deferral check**: acceptable risk (quantified below).
- **Justification**:
  - Worst case: a future refactor silently removes the `-O` clause and no test
    goes red; on a multi-user host the S2 preseeding vector partially reopens
    (still mitigated by the 0700 private state dir, which is itself
    ownership-checked and covered by a red-verified symlink test).
  - Likelihood: low — the clause is a single kernel-enforced POSIX primitive
    with no internal branching, centralized in one helper carrying a security
    comment, and the same helper is exercised red-verified via its symlink arm.
  - Cost to fix: an injectable-uid parameter would convert a hard-coded
    security invariant into a runtime value (a lever reachable from
    attacker-influenced env upstream) and violates "do not modify production
    code to simplify test setup". A root/two-uid CI harness exceeds this
    repo's test-infra scope. Security expert's recommendation (Round 3):
    keep as-is; correct escalation path, if ever needed, is a CI-only
    two-real-uid integration test, not a production seam.
- **Orchestrator sign-off**: acceptable-risk exception satisfied with the three
  values above; Security expert concurrence recorded in Round 3.

### T5 [Minor] Fallback tiers untested — Fixed
- Action: `~/.cache` tier test and mktemp last-resort test (0700 mode assert)
  added; mutation-verified. `-d` assert added to the `~/.cache` test under
  tightening-only skip.
- Modified file: `tests/ollama-backend.bats`.

### S3 [Major] Cache reuse survives trust-config revocation — Fixed
- Action: `_ollama_trust_fingerprint` (normalized effective sources +
  `OLLAMA_EXTRA_HOSTS`) is written as the cache's first line;
  `_ollama_read_cache` centralizes trusted-file + freshness + fingerprint
  checks and both read sites (`_resolve_ollama_servers`,
  `ollama_host_for_model`) route through it. Revoking/changing
  `OLLAMA_DISCOVERY` or `OLLAMA_EXTRA_HOSTS` invalidates the cache on the
  next call; legacy headerless caches never match. Design note: the simpler
  "skip cache when discovery disabled" alternative was rejected — it removes
  caching for the default explicit-hosts configuration (probing on every hook
  call) while the fingerprint preserves it for all configs.
- Regression tests (6, mutation-verified red-on-revert): discovery
  revocation, source-set change (mdns→tailscale), `OLLAMA_EXTRA_HOSTS`
  removal, alias spellings sharing the cache (probe-count equality),
  model-routing ignoring a mismatched-config cache, legacy headerless cache.
  Crafted-cache tests migrated to a header-writing `write_cache` helper,
  removing the test that codified the old behavior.
- Modified files: `hooks/ollama-backend.sh`, `README.md`,
  `tests/ollama-backend.bats`.

### LLM_TRUSTED_HOSTS [Feature] Backend-agnostic trusted host list — Done
- Action: `LLM_TRUSTED_HOSTS` consumed by both backends; cache read/write
  factored into shared `_llm_cached_records`/`_llm_write_cache`; llama.cpp
  cache fingerprint-bound (`#cfg hosts=...`); ollama fingerprint field
  `extra=` → `hosts=`. 7 feature tests (join, merge+dedup, exclusive override,
  invalidation on change for both backends), all mutation-verified.
- Modified files: `hooks/llm-utils.sh`, `hooks/ollama-backend.sh`,
  `hooks/llamacpp-backend.sh`, `tests/ollama-backend.bats`,
  `tests/llamacpp-backend.bats`, `README.md`, `settings.local.json.example`.

### F1 [Major] Unquoted word-split glob-expands host entries — Fixed
- Action: added `_llm_split_hosts`/`_llm_join_hosts` (noglob-guarded via
  `set -f`, restoring prior state) in llm-utils.sh; rewired both fingerprint
  functions and both candidate loops through them. Glob-safety regression
  tests added to both suites, mutation-verified red when globbing is
  re-enabled. Real-env verified (`LLM_TRUSTED_HOSTS="host *"`, CWD=/tmp →
  literal host, no expansion).
- Modified files: `hooks/llm-utils.sh`, `hooks/ollama-backend.sh`,
  `hooks/llamacpp-backend.sh`, `tests/ollama-backend.bats`,
  `tests/llamacpp-backend.bats`.

### F2 [Minor] Down trusted host re-probed every call — Documented (Accepted)
- **Anti-Deferral check**: acceptable risk (quantified below).
- **Justification**:
  - Worst case: ~2 s added latency per hook invocation per permanently-down
    trusted host (each hook is a fresh process; "down" is intentionally not
    cached so recovery is immediate).
  - Likelihood: low — only when a user leaves a decommissioned host in
    `LLM_TRUSTED_HOSTS`; self-inflicted and self-correcting once pruned.
  - Cost to fix: a known-down TTL marker adds state + a new invalidation
    dimension for marginal benefit; the pre-existing Ollama path made the same
    freshness/latency tradeoff. Documented in README (prune dead hosts) rather
    than adding caching complexity.
- **Orchestrator sign-off**: acceptable-risk exception satisfied.

### T6 [Major] Freshness branch of ollama_host_for_model untested — Fixed
- Action: "model routing: stale cache is not reused; falls back to default
  host" test applied verbatim from the Round-5 Testing expert's finding; the
  expert had already verified it green on the fix and red under the
  freshness-check mutation, discharging the fix-verification obligation
  within the same round.
- Modified file: `tests/ollama-backend.bats`.
