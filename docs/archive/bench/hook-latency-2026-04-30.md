# Hook chain latency benchmark

Date: 2026-04-30T20:32:27+09:00
Iterations per hook: 100
Input: approve-path JSON (`echo hello`)

| Hook | Matcher | min | median | p95 | max | avg |
| --- | --- | ---:| ---:| ---:| ---:| ---:|
| block-audit-observability-destruction | Bash | 12 ms | 14 ms | 15 ms | 16 ms | 14 ms |
| block-authz-state-destruction | Bash | 12 ms | 13 ms | 15 ms | 16 ms | 13 ms |
| block-destructive-docker | Bash | 11 ms | 13 ms | 14 ms | 15 ms | 12 ms |
| block-recovery-path-destruction | Bash | 11 ms | 13 ms | 15 ms | 16 ms | 13 ms |
| block-secret-key-destruction | Bash | 11 ms | 13 ms | 15 ms | 17 ms | 13 ms |
| block-sensitive-files | Edit|Write|MultiEdit | 6 ms | 7 ms | 8 ms | 9 ms | 7 ms |
| block-vcs-history-rewrite | Bash | 10 ms | 13 ms | 15 ms | 16 ms | 12 ms |

## Per-matcher chain estimates

| Matcher | Hooks counted | Cumulative avg |
| --- | ---:| ---:|
| Bash (block-* hooks only) | 6 | **77 ms** |
| Edit \| Write \| MultiEdit | 1 | **7 ms** |

Notes:
- The Bash matcher also runs `commit-msg-check.sh`, which is excluded from this benchmark because (a) it short-circuits on non-`git commit` commands and (b) on a real `git commit` it calls Ollama, dominating wall time. The numbers above are the always-paid block-* tripwire cost.
- Per-iteration cost is dominated by `bash` process startup + two `jq` invocations (one for `tool_name`, one for `tool_input.command`). A future optimization could consolidate the `jq` calls if a TAB-safe variant is found (an earlier `@tsv` attempt was reverted because TAB inside the command value collided with the field separator).
- Numbers are wall time on a developer machine. Re-run on a quiescent system before drawing conclusions about per-call cost.
