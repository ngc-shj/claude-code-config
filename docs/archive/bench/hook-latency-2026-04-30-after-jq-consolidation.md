# Hook chain latency benchmark

Date: 2026-04-30T20:45:37+09:00
Iterations per hook: 100
Input: approve-path JSON (`echo hello`)

| Hook | Matcher | min | median | p95 | max | avg |
| --- | --- | ---:| ---:| ---:| ---:| ---:|
| block-audit-observability-destruction | Bash | 6 ms | 7 ms | 9 ms | 9 ms | 7 ms |
| block-authz-state-destruction | Bash | 6 ms | 8 ms | 9 ms | 9 ms | 7 ms |
| block-destructive-docker | Bash | 5 ms | 7 ms | 9 ms | 9 ms | 7 ms |
| block-recovery-path-destruction | Bash | 6 ms | 8 ms | 9 ms | 10 ms | 7 ms |
| block-secret-key-destruction | Bash | 6 ms | 8 ms | 9 ms | 10 ms | 7 ms |
| block-sensitive-files | Edit|Write|MultiEdit | 4 ms | 6 ms | 7 ms | 7 ms | 5 ms |
| block-vcs-history-rewrite | Bash | 5 ms | 7 ms | 9 ms | 9 ms | 7 ms |

## Per-matcher chain estimates

| Matcher | Hooks counted | Cumulative avg |
| --- | ---:| ---:|
| Bash (block-* hooks only) | 6 | **42 ms** |
| Edit \| Write \| MultiEdit | 1 | **5 ms** |

Notes:
- The Bash matcher also runs `commit-msg-check.sh`, which is excluded from this benchmark because (a) it short-circuits on non-`git commit` commands and (b) on a real `git commit` it calls Ollama, dominating wall time. The numbers above are the always-paid block-* tripwire cost.
- Per-iteration cost is dominated by `bash` process startup + a single `jq` invocation. The hooks emit `tool_name` and `tool_input.command` in one jq call separated by U+001F (Unit Separator) and split via bash parameter expansion — earlier 2-jq-call versions paid roughly twice this; an even earlier `@tsv` attempt was reverted because TAB inside command values collided with the TSV field separator.
- Numbers are wall time on a developer machine. Re-run on a quiescent system before drawing conclusions about per-call cost.
