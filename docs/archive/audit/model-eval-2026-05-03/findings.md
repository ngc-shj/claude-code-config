# Model evaluation — 13-model comparison vs current routing (2026-05-03)

Bench harness: [`bench.sh`](./bench.sh) · Aggregator: [`aggregate.sh`](./aggregate.sh) · Ollama 0.22.0 on `gx10-a9c0`.

## TL;DR

**Keep current routing (`gpt-oss:20b` for short-output tasks, `gpt-oss:120b` for analysis tasks).** After 13 models tested across 5 rounds, only one challenger reproduces the bug-finding behavior of `gpt-oss:120b`: **`llama3.3:70b`** independently surfaces the U+001F separator-collision risk as a Major finding — the same key issue 120b finds. It is the first and only non-`gpt-oss` model in this bench to do so. However, llama3.3:70b is also slower on `commit-msg-check` (timeouts at 60s for medium/large) and `summarize-diff` (140-156s vs 120b's 14-19s), so it is not a clean replacement for any current routing slot.

Five rounds of measurement covered:
1. Initial 3×3×3 matrix: `gpt-oss:20b` / `gpt-oss:120b` / `qwen3.6:35b-a3b`.
2. Targeted re-tests on qwen3.6:35b-a3b: cold-start and `think:false`.
3. Addendum: `qwen3.6:27b` (dense Q4_K_M) — strictly dominated by the MoE sibling.
4. Coder/reasoning candidates: `qwen2.5-coder:32b` / `deepseek-coder-v2:16b` / `deepseek-r1:70b`.
5. Generic instruction-tuned candidates: `gemma3:27b` / `mistral-small3.2:24b` / `llama3.3:70b` / `command-r-plus` / `gemma4:26b` / `gemma4:31b`. (`mistral-medium-3.5:128b` was pulled but timed out on every cell — 80 GB dense exceeds usable VRAM/throughput on this hardware.)

Round 5 strengthens the round-4 lesson: **generic instruction-tuned > coder/reasoning specialist for code review.** All three "coding" specialists produced false negatives or vague style nits on the medium sample's real bug. Round 5 added 6 generic instruction-tuned candidates; only `llama3.3:70b` actually finds the U+001F bug. Two others (`gemma3:27b`, `mistral-small3.2:24b`) mention U+001F in their findings but only as comment-style nits, not as a correctness risk — surface engagement without depth.

Bonus findings:
- `mistral-small3.2:24b` is the **new speed champion** — `commit-msg-check` 0.95s and `summarize-diff` 15-25s with reasonable output. Faster than `deepseek-coder-v2:16b` on `summarize-diff` and competitive on `commit-msg-check`, with full format adherence on `analyze-functionality`. Pilot demotion candidate for `summarize-diff`.
- `gemma4:26b` returns **empty `.response`** via Ollama `/api/generate` for `commit-msg-check` and `analyze-functionality` despite generating tokens (`done_reason=length`, `eval_count` reaches `num_predict`). Output appears in `.message.thinking` via `/api/chat` instead. Likely an Ollama 0.22 + Gemma4 MoE interaction bug. Result: 26b inconclusive in current bench; 31b dense works fine.

## Background

Following the local availability of `qwen3.6:35b-a3b` (23 GB, MoE 35B/3B-active), the question was whether to:

- (A) repoint `pre-review.sh`'s `REVIEW_MODEL` from `gpt-oss:120b` to a faster model, or
- (B) demote some `gpt-oss:120b` calls in `ollama-utils.sh`, or
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

| short | full tag | architecture | size | added |
|---|---|---|---:|---|
| `20b`     | `gpt-oss:20b`           | dense, thinking-on    | 13 GB | round 1 |
| `120b`    | `gpt-oss:120b`          | dense, thinking-on    | 65 GB | round 1 |
| `q3.6-35a3` | `qwen3.6:35b-a3b`     | MoE 35B / 3B active   | 23 GB | round 1 |
| `q3.6-27` | `qwen3.6:27b`           | dense, thinking-on    | 17 GB | round 3 |
| `q2.5c-32` | `qwen2.5-coder:32b`    | dense, no thinking (pre-Qwen3 era) | 19 GB | round 4 |
| `dsc-v2-16` | `deepseek-coder-v2:16b` | MoE 16B / 2.4B active, no thinking | 8.9 GB | round 4 |
| `dsr1-70` | `deepseek-r1:70b`       | dense, reasoning (thinking-on) | 42 GB | round 4 |
| `g3-27`   | `gemma3:27b`            | dense, instruction-tuned | 17 GB | round 5 |
| `ms-24`   | `mistral-small3.2:24b`  | dense, instruction-tuned | 15 GB | round 5 |
| `l3.3-70` | `llama3.3:70b`          | dense, instruction-tuned | 42 GB | round 5 |
| `cmd-r+`  | `command-r-plus`        | dense, structured-output instruction | 59 GB | round 5 |
| `g4-26`   | `gemma4:26b`            | MoE 26B / 3.8B active, opt-in thinking | 17 GB | round 5 |
| `g4-31`   | `gemma4:31b`            | dense 31B, opt-in thinking | 19 GB | round 5 |
| _dropped_ | `mistral-medium-3.5:128b` | dense 128B, exceeds usable hardware | 80 GB | round 5 (dropped — every cell timed out) |

### Loop ordering

Models OUTER → samples → hooks. Each model warms up once (1-token ping) before its block, then runs 9 cells while resident in VRAM. `bench.sh` has `SKIP_EXISTING=1` (default) so adding a new model is incremental — only the 9 new cells executed in rounds 3, 4, and 5.

---

## Round 1 — initial matrix

### 1.1 Wall-clock latency (seconds, 7-model)

#### commit-msg-check

| sample | 20b | 120b | q3.6-35a3 | q3.6-27 | q2.5c-32 | dsc-v2-16 | dsr1-70 |
|---|---:|---:|---:|---:|---:|---:|---:|
| small  | 2.4 | 5.0 | 9.5 | 47.3 | 1.1 | **0.8** | timeout 60 |
| medium | 6.5 | 6.6 | 9.5 | 47.5 | 1.3 | **0.4** | timeout 60 |
| large  | 9.3 | 8.5 | 9.6 | 47.3 | 1.2 | **0.4** | timeout 60 |

`dsr1-70` (DeepSeek-R1, reasoning-thinking) cannot finish a 1-line commit-message judgment in 60s — same defect class as Qwen3.6's thinking-overrun, just slower. `dsc-v2-16` is **3-15× faster** than the current `20b` default.

#### summarize-diff

| sample | 20b | 120b | q3.6-35a3 | q3.6-27 | q2.5c-32 | dsc-v2-16 | dsr1-70 |
|---|---:|---:|---:|---:|---:|---:|---:|
| small  |  7.2 | 14.3 | 30.0 | 179.4 | 20.5 | **5.3** | 111.8 |
| medium | 11.1 | 14.8 | 34.0 | 150.7 | 19.4 | **8.2** | 127.0 |
| large  | 16.8 | 18.5 | 32.7 | 185.2 | 31.2 | **10.1** | 153.9 |

#### analyze-functionality

| sample | 20b | 120b | q3.6-35a3 | q3.6-27 | q2.5c-32 | dsc-v2-16 | dsr1-70 |
|---|---:|---:|---:|---:|---:|---:|---:|
| small  |  4.1 |  5.3 |  18.0 |  93.6 | **6.9** |  3.1 |  68.9 |
| medium | 38.8 | 46.4 | 171.7 | 574.5 | **7.6** |  9.7 |  93.4 |
| large  | 79.8 | 87.4 | 152.7 | timeout |11.6 | 35.1 | 186.6 |

Speed numbers in bold are the **best of any model**. But analyze-functionality speed wins are illusory — see §1.4.

### 1.2 Output volume (eval_count tokens) on `medium`

| model | commit-msg-check | summarize-diff | analyze-functionality |
|---|---:|---:|---:|
| 20b              |   352 |   544 | 2 085 |
| 120b             |   214 |   445 | 1 690 |
| q3.6-35a3        | 512† | 1 439 | 6 825 |
| q3.6-27          | 512† | 1 581 | 6 169 |
| q2.5c-32         |     2 |   127 |    12 |
| dsc-v2-16        |     2 |   231 |   255 |
| dsr1-70          | n/a (timeout) |   501 |   350 |

† `done_reason="length"` — thinking exhausted budget before answer.

The non-thinking models (`q2.5c-32`, `dsc-v2-16`) emit dramatically less output. For `analyze-functionality:medium`: `q2.5c-32` produced **12 tokens** (i.e. `No findings\n## END-OF-ANALYSIS`) where `120b` produced 1 690 tokens of structured findings. **This is the false-negative signature**, not "concise excellence."

### 1.3 Format adherence (`## END-OF-ANALYSIS` final-line check)

| sample | 20b | 120b | q3.6-35a3 | q3.6-27 | q2.5c-32 | dsc-v2-16 | dsr1-70 |
|---|---:|---:|---:|---:|---:|---:|---:|
| small  | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| medium | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| large  | ✅ | ✅ | ✅ | ✕ (timeout) | ✅ | ✅ | ✅ |

`dsc-v2-16` violates the format contract on `medium` — emits a finding then trails off without the sentinel. `_ollama_analyze_normalize` would discard the output. (Format adherence collapses entirely for qwen3.6:35b-a3b with `think:false` — see §3.2.)

### 1.4 Per-task quality observations (consolidated across rounds)

- **`commit-msg-check`**: All non-reasoning models emit `OK` / one-line suggestion as instructed and finish in seconds. `q3.6-35a3` and `q3.6-27` ignore the `"Reply with ONLY 'OK'"` instruction and emit a `"Here's a thinking process:"` preamble that overruns 512 tokens. `dsr1-70` cannot finish in the 60s timeout for any sample — reasoning models with default thinking are unsuitable for tight-budget classifiers.
- **`summarize-diff`**: All models that finish produce factually-correct summaries. Token counts diverge widely: `q2.5c-32` (127-195 tok) and `dsc-v2-16` (151-231 tok) are terse; `q3.6-*` (1 439-1 887 tok) are verbose; `120b` and `20b` (445-811 tok) are middle-of-the-road. No quality-vs-volume correlation; verbose outputs don't add facts.
- **`analyze-functionality`**: This is where models differentiate. **Only `gpt-oss:120b` reliably surfaces the U+001F separator-collision risk on `medium`**. `q3.6-35a3` and `q3.6-27` find a different real concern (DRY/duplication). All others — `20b`, `q2.5c-32`, `dsc-v2-16`, `dsr1-70` — produce false negatives or vague findings:
  - `20b`: `No findings` for all three.
  - `q2.5c-32`: `No findings` for all three (despite "coder" in the name).
  - `dsc-v2-16`: variable-rename suggestion on `medium` (vague, format-violating); on `large` 5×"inconsistent regex" complaints with no specific verb plus 1 fabricated "inconsistent header" finding.
  - `dsr1-70`: `No findings` for all three (despite reasoning + 70B params).

The "coder-tuned model = better reviewer" hypothesis is **refuted** on this benchmark. Coding fine-tunes optimize for *generating* code, not for finding bugs in code review.

Curated outputs in [§5 Appendix](#5-appendix-representative-outputs).

### 1.5 Bench config bug uncovered mid-round-1

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

## Round 2 — qwen3.6:35b-a3b targeted verification

Two hypotheses for qwen3.6:35b-a3b's poor showing on `analyze-functionality:medium` (171.7s):

1. **Cold-start contamination** — round-1 warmup was insufficient to actually load the MoE expert layers and KV cache.
2. **`think=true` overhead** — qwen3.6 emits long chain-of-thought before answering. If `think:false` disables this cleanly, the 3B-active path may genuinely beat 120b.

### 2.1 Cold-start re-test

| run | sample | total | load_ms | gen_ms | eval_count | tok/s |
|---|---|---:|---:|---:|---:|---:|
| warmup | small  | 23.8s  | **9 691** |  11 180 |   640 | 57 |
| 1      | medium | 102.5s |       161 |  97 728 | 5 565 | 57 |
| 2      | medium | 137.9s |       127 | 134 263 | 7 564 | 56 |
| 1      | large  | 105.2s |       154 |  98 318 | 5 435 | 55 |
| 2      | large  | 106.3s |       155 | 104 135 | 5 750 | 55 |

**Verdict: cold-start hypothesis mostly refuted.** First load is 9.7s but absorbed by the per-block warmup; from the second call onward, `load_duration<200ms`. Steady-state `medium` is 102-138s, governed by stochastic `eval_count` (5 565-7 564). The round-1 outlier (171.7s) is the high tail. Net effect: cold-start contributes ≤ 10s.

### 2.2 `think:false` experiment

| sample | think=true | think=false | speedup | response (B) | thinking (B) |
|---|---:|---:|---:|---:|---:|
| small  |   7.2s |  3.1s |  2.3× | 31 / 31    |  1 378 / 0 |
| medium |  70.1s |  7.1s |  9.9× | 30 / 861   | 13 931 / 0 |
| large  | 144.2s | 11.4s | 12.7× | 1 321 / 1 465 | 26 337 / 0 |

Speed numbers look excellent. Output quality does not:

1. **Stream-of-consciousness leaks into `.response`**: *"Let's trace: PARSED = ..., No, %% is longest suffix..."*
2. **Hallucinations**: on `medium` qwen-no-think repeatedly flagged a fabricated `jq , operator` bug — actual code uses `+` concatenation. The same fictional bug is restated 4-5 times with escalating severity.
3. **Format-contract violations**: ends with `No findings` (no sentinel) or `## END-ANALYSIS` (typo). `_ollama_analyze_normalize` would discard the output.

**Verdict: `think:false` is not a viable knob.** Thinking is the load-bearing mechanism for output quality, not pure overhead.

---

## Round 3 — qwen3.6:27b dense addendum

Question: is the smaller dense sibling faster, since it has fewer total params? **Answer: no.** On gx10 (Linux/CUDA), dense costs all 27B params per token while MoE 35b-a3b costs only 3B active — a 9× compute-per-token gap that wins out over the smaller total weight count.

Result: ~11 tok/s on qwen3.6:27b vs ~57 tok/s on the MoE sibling, same defect surface. `large × analyze-functionality` timed out at 600s. On `medium` the dense model surfaced the same DRY finding as the MoE — quality preserved, latency dominated. `qwen3.6:27b` is **strictly dominated** by `qwen3.6:35b-a3b` on this hardware.

---

## Round 4 — coder & reasoning candidates

Originally tried `qwen3.6:27b-coding-nvfp4` — Ollama returns HTTP 412 *"this model requires macOS"*, so the NVFP4 variant is MLX-only despite being on the Ollama library page. Pulled three non-OS-gated alternatives:

- **`qwen2.5-coder:32b`** — pre-Qwen3-era coder model, dense Q4_K_M, **no thinking** by default.
- **`deepseek-coder-v2:16b`** — MoE 16B / 2.4B-active, coder-tuned, **no thinking**.
- **`deepseek-r1:70b`** — reasoning model, dense 70B, thinking-on by default.

### 4.1 Speed-quality matrix (analyze-functionality:medium)

| model | latency | output tokens | finding quality |
|---|---:|---:|---|
| 20b              | 38.8s |  2 085 | ❌ False negative |
| **120b**         | 46.4s | 1 690  | ✅ U+001F collision (Major) — **only model to find this** |
| q3.6-35a3        | 171.7s | 6 825 | △ DRY duplication (Minor) — different valid concern |
| q3.6-27          | 574.5s | 6 169 | △ Same as 35a3 |
| q2.5c-32         | **7.6s** |    12 | ❌ False negative |
| dsc-v2-16        | 9.7s  |   255 | △ Variable rename (vague + format violation) |
| dsr1-70          | 93.4s |   350 | ❌ False negative |

**Coding-tuned models lose at code review on this benchmark.** `q2.5c-32` is fast because it produces 12 tokens of `No findings`; `dsc-v2-16` produces a vague style suggestion in 255 tokens; `dsr1-70` thinks for 93s and concludes `No findings`. None reaches the actionable depth of `120b`.

### 4.2 dsc-v2-16 (DeepSeek-Coder-V2:16b) — speed champion for short tasks

For commit-msg-check and summarize-diff, where the task is genuinely simple, `dsc-v2-16` is dramatically faster than the current defaults:

| hook | current default | dsc-v2-16 | speedup |
|---|---|---|---:|
| commit-msg-check (medium) | 20b: 6.5s | **0.4s** | 16× |
| commit-msg-check (large)  | 20b: 9.3s | **0.4s** | 23× |
| summarize-diff (small)    | 120b: 14.3s | **5.3s** | 2.7× |
| summarize-diff (medium)   | 120b: 14.8s | **8.2s** | 1.8× |
| summarize-diff (large)    | 120b: 18.5s | **10.1s** | 1.8× |

Output quality on `summarize-diff` is comparable to 120b (all three models surface the same key facts; output verbosity differs by ~2×). Output quality on `commit-msg-check` is identical (both emit `OK` for valid messages).

**Caveats** before any production demotion:
- One format-contract violation observed (`analyze-functionality:medium` — but that's the analyze hook, not the demotion target).
- Sample size is 3 commits per task. A wider A/B (10+ commits, including non-trivial commit messages) is the gating step.
- `dsc-v2-16` is a coder model, not a generic instruction-tuned model. Its priors are good for code-related summarization but unverified on prose-heavy commit messages.

### 4.3 dsr1-70 (DeepSeek-R1:70b) — verdict: bad fit

- `commit-msg-check` × all 3 samples: 60s timeout. Reasoning models with thinking-on cannot serve tight-budget classifiers — same defect class as Qwen3.6, just bigger.
- `analyze-functionality` × all 3 samples: `No findings`. 70B params + 60-180s of reasoning produce no actionable output.
- Throughput ~4 tok/s (vs 120b's ~40). For any task, slower than 120b without quality compensation.

No production hook is a win-case.

### 4.4 q2.5c-32 (qwen2.5-coder:32b) — verdict: niche at best

- Format-perfect (100% sentinel adherence, 100% format compliance on commit-msg-check).
- Content-empty on `analyze-functionality` (false-negative across the board).
- `summarize-diff` outputs are terse (127-195 tok) but accurate — could be a candidate for `summarize-diff` if extreme conciseness is desired. But 19-31s wall-clock isn't faster than `120b` (14-18s), so no clear win.
- `commit-msg-check` is fast (1.1-1.3s) and correct, but `dsc-v2-16` is faster (0.4-0.8s) and equally correct.

---

## Round 5 — generic instruction-tuned candidates

Round 4 closed by hypothesizing that *generic* instruction-tuned models would beat coder/reasoning specialists at code review. Round 5 tests this hypothesis with six new models. **Confirmed:** the only model in this entire 13-model bench (other than `gpt-oss:120b`) to find the U+001F separator-collision risk is `llama3.3:70b` — a generic instruction-tuned 70B dense.

### 5.1 Wall-clock latency on round-5 models (seconds)

#### commit-msg-check

| sample | g3-27 | ms-24 | l3.3-70 | cmd-r+ | g4-26 | g4-31 |
|---|---:|---:|---:|---:|---:|---:|
| small  | 2.7  | 1.4 | 10.1 | 17.4 | 9.3† | 52.5 |
| medium | 2.9  | 0.95 | timeout 60 | 4.8 | 9.3† | 34.2 |
| large  | 3.3  | 0.94 | timeout 60 | 4.5 | 9.3† | 52.9 |

#### summarize-diff

| sample | g3-27 | ms-24 | l3.3-70 | cmd-r+ | g4-26 | g4-31 |
|---|---:|---:|---:|---:|---:|---:|
| small  | 29.0 | 15.3 | 37.3  | 74.2 | 24.8 | 116.3 |
| medium | 29.7 | 19.1 | 140.2 | 88.3 | 18.6 |  68.4 |
| large  | 32.5 | 25.3 | 156.3 | 96.4 | 22.2 |  84.1 |

#### analyze-functionality

| sample | g3-27 | ms-24 | l3.3-70 | cmd-r+ | g4-26 | g4-31 |
|---|---:|---:|---:|---:|---:|---:|
| small  | 45.8 |  5.0 | 47.1  | 53.3 | 154.7† | 221.2 |
| medium | 73.8 | 60.4 | 175.8 | 27.6 | 155.8† | 296.3 |
| large  | 57.9 | 44.9 | 68.6  | 75.4 | 159.6† | 515.6 |

† `g4-26` reaches `num_predict=512` or `num_predict=8192` (`done_reason=length`) but `.response` returns empty via Ollama `/api/generate`. Raw output appears in `.message.thinking` via `/api/chat`. See §5.4.

### 5.2 Bug-finding contest — `analyze-functionality:medium`

The `medium` sample (`b2f907b`, the jq-consolidation perf commit) has at least one real correctness concern: if a command itself contains the U+001F byte used as the new separator, the Bash split logic mis-parses. Every model in the 13-model bench was scored on whether it surfaces this concrete risk vs. produces a false negative or stylistic noise.

| model | finding | bug found? |
|---|---|:-:|
| **gpt-oss:120b**  | "If the incoming `tool_input.command` itself contains this byte, the split will truncate the command, causing the hook to treat an unsafe command as empty and incorrectly approve it." (Major) | ✅ |
| **llama3.3:70b**  | "The code assumes that the `tool_name` will never contain the Unit Separator (U+001F) character … may lead to incorrect splitting and potential security issues." (Major) | ✅ **first non-gpt-oss model to find it** |
| qwen3.6:35b-a3b   | DRY/duplication finding (different real concern) | △ |
| qwen3.6:27b       | Same as 35b-a3b | △ |
| gpt-oss:20b       | "No findings" | ❌ |
| qwen2.5-coder:32b | "No findings" | ❌ |
| deepseek-coder-v2:16b | Vague variable-rename + format violation | △ |
| deepseek-r1:70b   | "No findings" | ❌ |
| gemma3:27b        | 15 "redundant comment / inconsistent variable naming" nits, mentions U+001F only as "comment is repeated across files" — does NOT flag collision risk | ❌ |
| mistral-small3.2:24b | 7 comment-consistency nits (e.g., "explanation about U+001F differs between files"), does NOT flag collision risk | ❌ |
| command-r-plus    | "No findings" | ❌ |
| gemma4:26b        | (output extraction broken, see §5.4) | inconclusive |
| gemma4:31b        | "No findings" | ❌ |

**Score: 2 of 13.** `gpt-oss:120b` and `llama3.3:70b` are the only two models that identify the actual security/correctness risk. `gemma3:27b` and `mistral-small3.2:24b` mention U+001F but only in cosmetic contexts (comment-style harmonization), missing the load-bearing point — surface engagement without comprehension.

### 5.3 Per-model verdict

- **`llama3.3:70b`** ✅ — Joins `gpt-oss:120b` as the only model that finds the U+001F bug. Speed is mixed: fast on small samples (10-47s) but slow on medium/large (140-176s for summarize-diff/analyze) and *times out* commit-msg-check at 60s for medium/large samples. **Could partially substitute for `gpt-oss:120b` on `analyze-functionality` only**, at half the disk size (42 GB vs 65 GB).
- **`mistral-small3.2:24b`** — Speed champion overall: `commit-msg-check` 0.95s, `summarize-diff` 15-25s. 100% format adherence on `analyze-functionality`. But on `analyze:medium` it produces 7 comment-consistency nits and misses the U+001F collision risk — same false-negative class as `gpt-oss:20b` for analyze-* purposes. **Pilot demotion candidate for `summarize-diff` and `commit-msg-check`** (subject to wider A/B), unsuitable for `analyze-*`.
- **`gemma3:27b`** — Format-perfect, fast enough (3-74s), but on `analyze:medium` produces 15 mostly-noise findings (style nits, variable-name nitpicks, "redundant comment" on each of 6 hook files). High volume of false positives is its own kind of unhelpful — review fatigue from noise vs review fatigue from missed bugs. Not a routing target.
- **`command-r-plus`** — Cohere flagship, structured-output strong on its training tasks but on this benchmark produces `No findings` for all three samples. 17-96s wall-clock. Fast `commit-msg-check` (4.5s on medium/large) but no clear advantage over `mistral-small3.2:24b` for that task. **Not a routing target** — bug-blind on this benchmark.
- **`gemma4:31b`** — Slowest of the 6 (52-516s), produces `No findings` on `analyze`. Opt-in thinking did not get triggered with our prompt. Format-perfect on the cells it completes. **Not a routing target.**
- **`gemma4:26b`** — Output extraction broken via `/api/generate` (see §5.4). **Test inconclusive** — would require switching `bench.sh` to `/api/chat` semantics to evaluate fairly. Deferred.
- **`mistral-medium-3.5:128b`** (dropped) — Pulled (80 GB) but every cell timed out. The 128B dense exceeds usable inference throughput on this hardware. Removed from the matrix; not a routing target.

### 5.4 Gemma4:26b output extraction issue

Probe via `/api/generate` (what `bench.sh` uses):

```json
{
  "response": "",
  "thinking": null,
  "eval_count": 50,
  "done_reason": "length"
}
```

50 tokens were generated (`eval_count=50`) but neither `.response` nor `.thinking` contains them. Same prompt via `/api/chat`:

```json
{
  "message": {
    "role": "assistant",
    "content": "",
    "thinking": "*   Constraint 1: Write exactly 5 words.\n    *   Constraint 2: Stop immediately after.\n    *   \"I am writing five words.\" (5 words)..."
  },
  "done_reason": "length",
  "eval_count": 50
}
```

The thinking content surfaces under `.message.thinking` in `/api/chat`. Likely an Ollama 0.22 + Gemma4 MoE interaction where `/api/generate` does not forward the thinking-channel tokens. The dense Gemma4:31b (same family, no MoE) does not have the issue.

This is a bench-infrastructure defect, not a model defect. Re-running gemma4:26b via `/api/chat` would require a `bench.sh` change; deferred since `gemma4:31b`'s false-negative result on the same prompt suggests `gemma4:26b` would also false-negative even if extracted correctly.

---

## 5. Appendix — representative outputs

### 5.1 commit-msg-check (medium)

| model | output | latency |
|---|---|---:|
| 20b              | `OK` | 6.5s |
| 120b             | `OK` | 6.6s |
| q3.6-35a3        | (thinking-process preamble, never reaches answer) `done_reason=length` | 9.5s |
| q3.6-27          | (same defect, slower preamble) | 47.5s |
| **q2.5c-32**     | `OK` | **1.3s** |
| **dsc-v2-16**    | `OK` | **0.4s** |
| dsr1-70          | (timeout, no output) | 60.0s |

### 5.2 analyze-functionality (medium) — finding contrast

The actual diff has at least one legitimate functional concern (U+001F separator collision: if a command itself contains the byte, the Bash split logic mis-parses).

**`gpt-oss:120b`** — surfaces the U+001F collision as Major (only model to do so).

```
[Major] hooks/block-audit-observability-destruction.sh:12 — The script splits the jq output on the Unit Separator (U+001F). If the incoming `tool_input.command` itself contains this byte, the split will truncate the command, causing the hook to treat an unsafe command as empty and incorrectly approve it. — Escape any occurrences of U+001F in the command before concatenation ...

[Minor] hooks/block-audit-observability-destruction.sh:9 — The same parsing logic (jq call + separator split) is duplicated verbatim in every `block-*` hook script ...

## END-OF-ANALYSIS
```

**`qwen3.6:35b-a3b`** — different valid concern (DRY duplication).

```
[Minor] hooks/block-audit-observability-destruction.sh:44 — Parsing logic is duplicated verbatim across 6 hook scripts, violating DRY ...
## END-OF-ANALYSIS
```

**`qwen2.5-coder:32b`** — false negative.

```
No findings
## END-OF-ANALYSIS
```

**`deepseek-coder-v2:16b`** — vague + format violation (no `## END-OF-ANALYSIS`).

```
[Minor] hooks/block-audit-observability-destruction.sh:39 — Consider improving readability by using more descriptive variable names for PARSED and TOOL_NAME.
... (suggested PARSED→OUTPUT rename) ...
This change would make the variable names more indicative of their role in the script, potentially improving overall readability and maintainability.
```

**`deepseek-r1:70b`** — false negative (despite 93s reasoning + 70B params).

```
No findings
## END-OF-ANALYSIS
```

---

## 6. Recommendations

1. **No changes to default routing for `analyze-*` hooks.** Keep `gpt-oss:120b`. Of 13 models tested, only `gpt-oss:120b` and `llama3.3:70b` surface the U+001F collision risk; 120b is faster on `summarize-diff` and `commit-msg-check`, so no clean swap.
2. **`llama3.3:70b` as a backup for `analyze-*`-only.** It is the second model in the bench to find the actual bug. Half the disk size of 120b (42 vs 65 GB). Latency is comparable on `analyze-functionality:small/large` (47/68s vs 5/87s) but slower on medium (175s vs 46s). Worth keeping as a fallback if `gpt-oss:120b` becomes unavailable.
3. **Keep `qwen3.6:35b-a3b` as a complementary "second opinion" model** for `analyze-*` tasks. Surfaces a different real concern (DRY duplication) at 2-3× wall-clock cost. Use only with thinking-on.
4. **(Optional) Pilot `mistral-small3.2:24b` as the new fast-default for `commit-msg-check` and `summarize-diff`.** Speed champion overall: `commit-msg-check` 0.95s on medium/large (vs `gpt-oss:20b`'s 6.5-9.3s); `summarize-diff` 15-25s with comparable quality to `gpt-oss:120b`. Format adherence is solid (100% sentinel compliance on `analyze-functionality` even though analyze quality is poor). Wider A/B (>=10 commits) gates production change.
5. **(Optional, alternative) `deepseek-coder-v2:16b` for `commit-msg-check`.** Slightly faster than `mistral-small3.2:24b` (0.4s vs 0.95s on medium/large). Less polished elsewhere (one format violation on `analyze:medium`). Pick whichever has cleaner outputs in the wider A/B.
6. **Do NOT use any of these for production:**
   - `qwen3.6:27b` — strictly dominated by the MoE sibling (5× slower, no quality gain).
   - `qwen2.5-coder:32b` — false-negative on analyze-*; no clear niche given other faster fast-default candidates.
   - `deepseek-r1:70b` — too slow for short tasks (60s timeouts), false-negative on analyze-*. Reasoning model is the wrong tool for these prompts.
   - `gemma3:27b` — high false-positive volume on analyze-* (15 style nits, missed the bug).
   - `command-r-plus` — bug-blind on analyze-*; no clear niche.
   - `gemma4:31b` — slow + false-negative on analyze-*.
   - `gemma4:26b` — output extraction broken via `/api/generate`; deferred.
   - `mistral-medium-3.5:128b` — exceeds usable inference throughput on this hardware; every cell timed out.
7. **Do NOT use `think:false` on qwen3.6** for structured-output tasks. Speedup is real; quality collapse is not survivable.
8. **Re-bench triggers.** Re-run [`bench.sh`](./bench.sh) on:
   - New point release of any tested model.
   - Ollama point release that changes default thinking semantics or fixes the Gemma4:26b output-extraction issue.
   - New model with credible code-review priors (e.g. an Anthropic-tuned local model, a "reviewer" rather than "coder" fine-tune).

   `SKIP_EXISTING=0 bash bench.sh` forces a full re-run; the default re-uses any cached `.out`/`.meta` pairs.

## 7. Why generic instruction-tuned beats coder/reasoning fine-tunes (working theory)

Across 13 models, the bug-finding leaderboard on `analyze-functionality:medium` is:

- **`gpt-oss:120b`** (generic instruction) ✅
- **`llama3.3:70b`** (generic instruction) ✅
- `qwen3.6:35b-a3b` (instruction-tuned, thinking-on) — different real concern (DRY)
- Everything else (coder, reasoning, smaller instruction-tuned) — false negatives or noise

Plausible reasons coder/reasoning fine-tunes lose:

- **Coder fine-tunes optimize for "what code would I write" not "what could go wrong with this code"**. Generation-mode priors weight plausibility of code, not hostile-input or boundary-condition reasoning.
- **Reasoning fine-tunes optimize for math/logic chains**, not for the heterogeneous "trace through this Bash + jq + regex" reasoning needed for hook safety review.
- **The two models that found the bug are both generic instruction-tuned at large scale** (`gpt-oss:120b`, `llama3.3:70b`). Their breadth of training (security write-ups, post-mortems, code review threads) plausibly gives them the bug-finding priors that specialized models lack. Smaller generic models (`mistral-small3.2:24b`, `gemma3:27b`, `gemma4:31b`) miss the bug too — *scale + generic instruction* both seem to matter.

Pragmatically: when picking a model for a code-review hook, **prefer large generic instruction-tuned models over coder-fine-tuned or reasoning-tuned variants**. A coder fine-tune's terse "No findings" answer is the most expensive kind of false negative — it looks correct.

---

## 8. Artifacts

- [`bench.sh`](./bench.sh) — matrix runner (samples × hooks × models, with warmup and `SKIP_EXISTING` cache)
- [`aggregate.sh`](./aggregate.sh) — regenerates raw-data tables and previews into a separate dump (kept for re-bench convenience; not the canonical report)
- [`bench.log`](./bench.log) — round-1 stdout
- [`bench-qwen3.6-27b.log`](./bench-qwen3.6-27b.log) — round-3 stdout
- [`bench-round4.log`](./bench-round4.log) — round-4 stdout (qwen2.5-coder, deepseek-coder-v2, deepseek-r1)
- [`bench-round5.log`](./bench-round5.log) — round-5 stdout (gemma3, mistral-small, llama3.3, command-r-plus, gemma4:26b/31b)
- [`samples/`](./samples/) — committed `.diff` and `.subject` per sample (frozen so re-runs use identical inputs)
- [`results/<sample>/<hook>_<model>.{out,meta}`](./results/) — round-1 + round-3 + round-4 + round-5 per-cell raw response + JSON metadata
- [`results-nothink/qwen-nothink_<sample>.{out,meta}`](./results-nothink/) — round-2 `think:false` outputs
