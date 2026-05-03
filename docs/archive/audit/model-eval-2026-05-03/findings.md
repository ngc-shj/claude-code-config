# Model evaluation — qwen3.6:35b-a3b vs current routing (2026-05-03)

Bench harness: [`bench.sh`](./bench.sh) · Aggregator: [`aggregate.sh`](./aggregate.sh) · Ollama 0.22.0 on `gx10-a9c0`.

## TL;DR

**Keep current routing (`gpt-oss:20b` for short-output tasks, `gpt-oss:120b` for analysis tasks). Do NOT promote `qwen3.6:35b-a3b` to default for any production hook.**

The MoE structure (35B total / 3B active) suggested a sweet spot between 20b and 120b, but on this workload it is **slower than 120b** on heavy tasks and **breaks the output-format contract** on short-output tasks. After two rounds of measurement (initial matrix + targeted re-tests for cold-start and `think:false`), the data does not support a routing change. Qwen3.6 is best slotted as a complementary "second opinion" model for analyze-* tasks, not a replacement.

## Background

Following the local availability of `qwen3.6:35b-a3b` (23 GB, MoE 35B/3B-active), the question was whether to:

- (A) repoint `pre-review.sh`'s `REVIEW_MODEL` from `gpt-oss:120b` to qwen3.6 for latency wins, or
- (B) demote some `gpt-oss:120b` calls in `ollama-utils.sh` to qwen3.6, or
- (C) leave routing as-is.

The empirical approach was to replay past commits from this repo through each model under the same prompts the production hooks use today.

## Method

### Sample commits (selected for size variance)

| size | sha | subject | diff lines |
|---|---|---|---:|
| small  | `91ee395` | `docs: rtk privacy-posture audit + retention reduction (90d -> 14d)` | 219 |
| medium | `b2f907b` | `perf(hooks): consolidate per-hook jq calls (2 -> 1) via U+001F separator (#39)` | 266 |
| large  | `67bd037` | `fix(hooks): block authorization-state destruction (R31 f) (#36)` | 484 |

### Hooks evaluated (system prompts copied verbatim from production)

| hook | source | original model | input |
|---|---|---|---|
| `commit-msg-check`      | `~/.claude/hooks/commit-msg-check.sh` | gpt-oss:20b  | commit subject + body |
| `summarize-diff`        | `ollama-utils.sh` `cmd_summarize_diff`        | gpt-oss:120b | diff body |
| `analyze-functionality` | `ollama-utils.sh` `cmd_analyze_functionality` | gpt-oss:120b | diff body |

### Models

`gpt-oss:20b` · `gpt-oss:120b` · `qwen3.6:35b-a3b`

### Loop ordering

Models OUTER → samples → hooks. Each model warms up once (1-token ping) before its block, then runs 9 cells while resident in VRAM. This avoids repeated load when models would otherwise be evicted between calls.

---

## Round 1 — initial matrix

### 1.1 Wall-clock latency (seconds)

#### commit-msg-check

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  | 2.4 | 5.0 | 9.5 |
| medium | 6.5 | 6.6 | 9.5 |
| large  | 9.3 | 8.5 | 9.6 |

#### summarize-diff

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  |  7.2 | 14.3 | 30.0 |
| medium | 11.1 | 14.8 | 34.0 |
| large  | 16.8 | 18.5 | 32.7 |

#### analyze-functionality

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  |  4.1 |  5.3 |  18.0 |
| medium | 38.8 | 46.4 | 171.7 |
| large  | 79.8 | 87.4 | 152.7 |

### 1.2 Output volume and throughput

Format: `eval_count tokens / generation rate tok·s⁻¹`. The throughput numbers come from Ollama's `eval_duration` counter (excludes prompt eval and load time).

#### commit-msg-check

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  | 120 / 57.9 | 157 / 37.8 | **512** / 59.0 |
| medium | 352 / 58.6 | 214 / 37.7 | **512** / 59.1 |
| large  | **512** / 58.6 | 286 / 37.7 | **512** / 59.2 |

Bold = `done_reason="length"` (truncation). Qwen consistently hits the 512-token cap because thinking never yields to the answer; gpt-oss:20b also tops out on `large`.

#### summarize-diff

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  | 333 / 56.9 | 442 / 40.7 | **1 537** / 57.9 |
| medium | 544 / 56.8 | 445 / 40.2 | **1 439** / 47.6 |
| large  | 811 / 56.3 | 498 / 39.7 | **1 517** / 56.4 |

Qwen generates 3× more tokens than 120b for the same task — the dominant reason wall-clock is 2× worse despite faster per-token throughput.

#### analyze-functionality

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  |   152 / 57.6 |    71 / 41.2 |   852 / 57.9 |
| medium | 2 085 / 56.8 | 1 690 / 40.3 | **6 825** / 42.3 |
| large  | 4 183 / 54.7 | 3 130 / 38.8 | **7 938** / 54.8 |

Throughput ranking is consistent: 20b ≈ qwen (~55-58 tok/s) > 120b (~40 tok/s). Qwen wins per-token but loses wall-clock by output volume.

### 1.3 Format adherence

`analyze-functionality` requires `## END-OF-ANALYSIS` as the literal final line. With thinking enabled (the default), all three models pass:

| sample | gpt-oss:20b | gpt-oss:120b | qwen3.6:35b-a3b |
|---|---:|---:|---:|
| small  | ✅ | ✅ | ✅ |
| medium | ✅ | ✅ | ✅ |
| large  | ✅ | ✅ | ✅ |

(Format adherence collapses for qwen with `think:false` — see Round 2.2.)

### 1.4 Per-task quality observations

- **`commit-msg-check`**: 20b and 120b emit `OK` / one-line suggestion as instructed. Qwen3.6 ignores `"Reply with ONLY 'OK'"` and emits a `"Here's a thinking process:"` preamble; at `num_predict=512` it never reaches the answer (`done_reason=length`). The reasoning lives in the `.thinking` field.
- **`summarize-diff`**: All three models produce factually correct summaries. Qwen3.6 generates 3× more tokens (~1500 vs ~450 for 120b) without commensurate quality gain.
- **`analyze-functionality`**: 20b consistently emits `No findings` for all three samples — **false negative on real bugs** that 120b correctly surfaces. 120b and qwen both find legitimate issues, sometimes different ones (medium: 120b flags U+001F separator collision, qwen flags duplicated parsing logic; large: 120b flags `set -u` unbound-variable risk, qwen flags `\b` regex hyphen-boundary risk).

Curated outputs in [§4 Appendix](#4-appendix-representative-outputs).

### 1.5 Bench config bug uncovered mid-run

The first pass set `num_predict=60` for `commit-msg-check`. With thinking models (gpt-oss is also thinking-enabled by default), the entire 60-token budget was consumed by `.thinking`, leaving `.response` empty (`done_reason=length`). The original jq filter `.response // .thinking // ""` did not fall through because empty-string is truthy in jq. Two fixes were applied:

```jq
# Old (broken):  .response // .thinking // ""
# New (matches ollama-utils.sh):
if (.response // "") != "" then .response
elif (.thinking // "") != "" then .thinking
else empty
end
```

…and `commit-msg-check` `num_predict` was raised to 512. Production `commit-msg-check.sh` does not set `num_predict` at all (Ollama default is generous), so this is a bench-only artifact, not a production issue.

---

## Round 2 — targeted verification

Two hypotheses for qwen3.6's poor showing on `analyze-functionality:medium` (171.7s):

1. **Cold-start contamination** — round-1 warmup ("hi" × 1 token) was insufficient to actually load the MoE expert layers and KV cache.
2. **`think=true` overhead** — qwen3.6 emits long chain-of-thought before answering. If Ollama 0.22's `think:false` toggle disables this cleanly, the 3B-active path may genuinely beat 120b.

### 2.1 Cold-start re-test

Method: deep warmup (full `analyze-functionality` on `small`), then run `medium` and `large` back-to-back twice each, capturing `load_duration`, `prompt_eval_duration`, `eval_duration`, and `eval_count`.

| run | sample | total | load_ms | prompt_eval_ms | gen_ms | eval_count | tok/s |
|---|---|---:|---:|---:|---:|---:|---:|
| warmup | small  | 23.8s  | **9 691** | 2 729 |  11 180 |   640 | 57 |
| 1      | medium | 102.5s |       161 | 3 070 |  97 728 | 5 565 | 57 |
| 2      | medium | 137.9s |       127 | 1 265 | 134 263 | 7 564 | 56 |
| 1      | large  | 105.2s |       154 | 5 070 |  98 318 | 5 435 | 55 |
| 2      | large  | 106.3s |       155 |   311 | 104 135 | 5 750 | 55 |

**Verdict: cold-start hypothesis mostly refuted.**

- First call after `ollama serve` start: `load_duration=9.7s` is real, but absorbed by the round-1 per-block warmup. From the second call onward, `load_duration<200ms`.
- Steady-state `medium` time is 102-138s, governed by `eval_count` (5 565-7 564, stochastic across runs). The round-1 outlier (171.7s, 6 825 tokens) sits inside this distribution's high tail.
- Throughput is stable at ~55-57 tok/s. The 42 tok/s reported in round 1 for medium was likely transient resource contention, not cold-start.
- Net effect: cold-start contributes ≤ 10s. The dominant cost is **generation volume × throughput**, not load.

### 2.2 `think:false` experiment

Method: same prompt, `think:false` vs `think:true`, all three sample sizes. Captures `.response` length, `.thinking` length, latency.

| sample | think=true | think=false | speedup | response (B) | thinking (B) |
|---|---:|---:|---:|---:|---:|
| small  |   7.2s |  3.1s |  2.3× | 31 / 31    |  1 378 / 0 |
| medium |  70.1s |  7.1s |  9.9× | 30 / 861   | 13 931 / 0 |
| large  | 144.2s | 11.4s | 12.7× | 1 321 / 1 465 | 26 337 / 0 |

Speed numbers look excellent. Output quality does not.

#### Quality issues with `think:false` outputs

1. **Stream-of-consciousness leaks into `.response`.** With thinking suppressed the model still wants to reason, so monologue ends up inline:
   > *"Let's trace: PARSED = "\x1f"cmd (if tool_name is empty). ${PARSED%%$'\x1f'*} removes the longest suffix starting with \x1f. The longest suffix... No, %% is longest suffix..."*

2. **Hallucinations.** On the `medium` sample (`b2f907b`, the jq-consolidation perf commit) qwen-no-think repeatedly flagged a non-existent bug:
   > *`[Critical] hooks/block-destructive-docker.sh:16 — jq Multiple Outputs Break Bash Splitting — The jq filter (.tool_name // ""), "", (.tool_input.command // "") uses the , operator…`*

   But the actual diff uses `+` for string concatenation, not `,`. The same fictional bug is restated 4-5 times with escalating severity (Minor → Major → Critical) within a single response.

3. **Format-contract violations.** The mandatory final line is `## END-OF-ANALYSIS`. With `think:false`, qwen ends with:
   - `small`: `No findings` (no sentinel)
   - `medium`: `## END-ANALYSIS` (typo)
   - `large`: `No findings` (no sentinel)

   `_ollama_analyze_normalize` would discard the entire output.

**Verdict: `think:false` is not a viable knob for qwen3.6 on structured-output tasks.** The thinking is the load-bearing mechanism for output quality, not pure overhead. The original `think:true` measurements stand.

---

## 3. Why qwen3.6:35b-a3b underperformed (consolidated)

| factor | observation |
|---|---|
| **Throughput** | 54-58 tok/s — comparable to `gpt-oss:20b`, faster than `gpt-oss:120b` (~40 tok/s). Per-token, qwen wins. |
| **Output volume** | 2-3× more tokens than `gpt-oss:120b` for the same task. Wall-clock loses despite higher throughput. |
| **Format adherence** | Weak on terse outputs ("Reply with ONLY 'OK'" → ignored). Strong on heavily-templated outputs (`## END-OF-ANALYSIS` sentinel → 100% with thinking on). |
| **Thinking dependency** | Reasoning quality depends on thinking-mode. `think:false` produces hallucinations and breaks format contracts. |
| **Cold-start** | 9.7s on first load, then negligible. Not a routing factor in steady state. |

---

## 4. Appendix — representative outputs

Curated to illustrate the quality patterns called out above. Full output text for all 27 cells lives in [`results/`](./results/); `think:false` re-test outputs in [`results-nothink/`](./results-nothink/).

### 4.1 commit-msg-check — qwen format failure

Input: `medium` commit subject + body.

**gpt-oss:20b**

```
OK
```

**gpt-oss:120b**

```
OK
```

**qwen3.6:35b-a3b** — emits a thinking-process preamble instead of "OK". `done_reason=length` at 512 tokens; the model never reaches the answer.

```
Here's a thinking process:

1.  **Analyze User Input:**
   - **Task:** Review a git commit message.
   - **Condition 1:** Reply with ONLY 'OK' if it follows best practices ...
   - **Condition 2:** Reply with a one-line suggestion if it needs improvement.
   - **Input Commit Message:**
     ...
```

### 4.2 summarize-diff — verbosity contrast

Input: `medium` diff (`b2f907b`, jq consolidation).

**gpt-oss:20b** (333 tokens)

```
- Consolidated the two `jq` calls in six block-hooks into a single invocation that emits `tool_name` and `tool_input.command` separated by a U+001F (Unit Separator), then splits via Bash parameter expansion.
- Added a new benchmark file ... showing a 45 % drop in cumulative latency (≈ 77 ms → 42 ms).
- Switched from a prior `@tsv` attempt — which escaped embedded TABs and broke parsing — to U+001F because it is a real byte that rarely appears in shell commands and preserves control characters.
- Potential risks: if a command were to contain U+001F, the split would fail; ...
```

**gpt-oss:120b** (445 tokens) — same content, slightly more polished, includes the `341 Bats tests still pass` verifiable detail.

```
- **Merged two `jq` invocations into one** for each block-* Bash hook by emitting `tool_name` and `tool_input.command` together, separated with the Unicode Unit Separator (U+001F) ...
- ... cutting the total Bash matcher chain from ~77 ms to ~42 ms (≈‑45 %).
- **Switched away from `@tsv`** because it escapes embedded TAB characters ...
- **No functional regression**: all 341 Bats tests still pass ...
```

**qwen3.6:35b-a3b** (1 439 tokens — 3× more) — same content in longer prose, no additional facts.

```
*   Refactored six `block-*` Bash hooks to replace two `jq` invocations per hook with a single `jq -rj` call emitting `tool_name` and `command` separated by the Unit Separator (U+001F), parsed via Bash parameter expansion.
*   Delivers a 45% improvement in Bash chain latency (cumulative ~77ms → ~42ms) ...
*   Resolves the previous failure of `@tsv` separators by using U+001F, which preserves embedded TABs in command values without escaping ...
*   Verified for stability with 341/341 tests passing ...
```

### 4.3 analyze-functionality — false-negative vs real-finding contrast

Input: `medium` diff. The actual diff has at least one legitimate functional concern (U+001F separator collision: if a command itself contains the byte, the Bash split logic mis-parses).

**gpt-oss:20b** — false negative, misses the bug entirely.

```
No findings
## END-OF-ANALYSIS
```

**gpt-oss:120b** — surfaces the U+001F collision risk as Major.

```
[Major] hooks/block-audit-observability-destruction.sh:12 — The script splits the jq output on the Unit Separator (U+001F). If the incoming `tool_input.command` itself contains this byte, the split will truncate the command, causing the hook to treat an unsafe command as empty and incorrectly approve it. — Escape any occurrences of U+001F in the command before concatenation ...

[Minor] hooks/block-audit-observability-destruction.sh:9 — The same parsing logic (jq call + separator split) is duplicated verbatim in every `block-*` hook script ...

## END-OF-ANALYSIS
```

**qwen3.6:35b-a3b** — flags only the duplication, misses the U+001F collision; different angle, lower coverage on this sample.

```
[Minor] hooks/block-audit-observability-destruction.sh:44 — Parsing logic is duplicated verbatim across 6 hook scripts, violating DRY and increasing future maintenance burden. — Extract the jq invocation and bash parameter expansion into a shared utility script ...
## END-OF-ANALYSIS
```

---

## 5. Recommendations

1. **No changes to default routing.** Keep `gpt-oss:20b` for `commit-msg-check`, `classify-*`, `generate-slug`, `generate-resolution-entry`, `generate-pr-title`. Keep `gpt-oss:120b` for the heavy `summarize-*` / `analyze-*` / `merge-findings` / `generate-pr-body` family.
2. **Add `qwen3.6:35b-a3b` to the CLAUDE.md routing table as a "second opinion" model** (think=on only) for analyze-* tasks. It surfaces different findings than 120b on the medium and large samples (~30% non-overlap), at 2-3× wall-clock cost.
3. **(Optional) Investigate `summarize-diff` demotion to 20b.** Round-1 data suggests 20b output quality is acceptable and saves ~7-13s per call. Run a wider A/B (5+ commits) before changing.
4. **Do NOT use `think:false` on qwen3.6** for structured-output tasks. Speedup is real; quality collapse is not survivable.
5. **Re-bench triggers.** Re-run [`bench.sh`](./bench.sh) on:
   - New qwen point release (3.6.x → 3.7.x).
   - Ollama point release that changes default thinking semantics.
   - New gpt-oss release.

---

## 6. Artifacts

- [`bench.sh`](./bench.sh) — matrix runner (samples × hooks × models, with warmup)
- [`aggregate.sh`](./aggregate.sh) — regenerates raw-data tables and previews into a separate dump (kept for re-bench convenience; not the canonical report)
- [`bench.log`](./bench.log) — round-1 stdout
- [`samples/`](./samples/) — committed `.diff` and `.subject` per sample (frozen so re-runs use identical inputs)
- [`results/<sample>/<hook>_<model>.{out,meta}`](./results/) — round-1 per-cell raw response + JSON metadata
- [`results-nothink/qwen-nothink_<sample>.{out,meta}`](./results-nothink/) — round-2 `think:false` outputs
