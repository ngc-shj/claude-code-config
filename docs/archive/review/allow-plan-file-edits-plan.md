# Plan: allow-plan-file-edits

## Objective

Allow Claude Code to read, edit, and write plan files under `~/.claude/plans/` without requiring user confirmation on every operation.

## Requirements

- Add `Read`, `Edit`, and `Write` permissions for `~/.claude/plans/*` to the project's `settings.json` allow list
- No other permission changes

## Technical approach

Add three permission entries to `settings.json` → `permissions.allow` array:
- `Read(~/.claude/plans/*)`
- `Edit(~/.claude/plans/*)`
- `Write(~/.claude/plans/*)`

## Implementation steps

1. Add the three permission strings to the `allow` array in `settings.json`

## Testing strategy

- Invoke multi-agent-review skill and verify plan file operations no longer trigger permission prompts

## Considerations & constraints

- Only `~/.claude/plans/` is affected; no broader file system access is granted
- The tilde `~` path expansion must be supported by Claude Code's permission matcher
