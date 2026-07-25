# claude-code-config

Source of truth for this machine's Claude Code setup. `install.sh` copies
everything here into `~/.claude/`; the installed copy is what actually runs.

**The global rules that apply while working in this repo are not in this
file.** They live in `global/CLAUDE.md`, which is already loaded from
`~/.claude/CLAUDE.md`. Keep this file to repo-specific notes only — anything
duplicated from `global/CLAUDE.md` is loaded twice per session here.

## Editing config

Edit the source under this repo, then run `./install.sh`. Editing
`~/.claude/` directly is overwritten on the next install, and
`block-sensitive-files.sh` blocks writes to the installed hooks, settings,
and CLAUDE.md for that reason.

| Edit here | Lands at |
| --- | --- |
| `global/CLAUDE.md`, `global/RTK.md` | `~/.claude/` |
| `settings.json`, `hooks/`, `skills/`, `rules/` | `~/.claude/` |

## Context budget

`rules/common/*.md` declare no `paths:` frontmatter, so they are auto-injected
into every session (~1,200 tokens) — keep them short. The language overlays
under `rules/{lang}/` declare `paths:` and stay out of context until a
matching file is edited. Adding `paths:` to a `common/` file silently drops it
out of the always-loaded set; `tests/install.bats` asserts they have none.

## Tests

```bash
bats tests/                    # full suite
bats tests/install.bats        # installer contract
```

Hook changes need a matching test — most hooks are security gates, and an
unexercised gate reports PASS by never running.
