---
name: common-coding-style
description: Language-agnostic coding style principles that extend CLAUDE.md Coding Style
scope: all source files
---

# Common Coding Style

These principles apply to every language. Language-specific rules in `rules/{lang}/coding-style.md` extend this baseline and may override idiom-dependent parts (e.g. Go mutability).

## Simplicity first

- KISS — pick the dumbest solution that works.
- DRY — extract only after the third duplication; premature abstraction costs more than repetition.
- YAGNI — do not add parameters, hooks, or extension points for hypothetical future needs.

## File and function size

- Prefer files under 300 lines. Split when a file exceeds 500 lines.
- Prefer functions under 40 lines. A function that does not fit on one screen is usually doing two things.
- Nesting depth of 3 is the soft cap. Flatten with early return or extraction.

## Naming

- Names describe purpose, not type (`users`, not `userArray`).
- Boolean identifiers read as predicates (`isReady`, `hasItems`).
- Avoid abbreviations unless they are domain-standard (`cfg`, `req`, `ctx` are fine).

## Comments

- Default to writing none. Good names and structure are primary documentation.
- Write a comment only when the *why* is non-obvious: a workaround, a hidden constraint, a counter-intuitive decision.
- Never write comments that restate the code or reference the current task (`// fix for issue #123`).

## Error handling

- Fail fast at system boundaries (user input, external APIs, env config).
- Do not add try/catch to silence errors. If a failure is recoverable, state the recovery explicitly.
- Never swallow errors with empty catch blocks.

## Immutability

- Treat data as immutable by default. Mutate only when the language idiom requires it (see language-specific rules).
- Prefer pure functions. Side effects belong at the edges of the system.
