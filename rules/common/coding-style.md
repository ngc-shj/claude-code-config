---
name: common-coding-style
description: Language-agnostic coding style principles that extend CLAUDE.md Coding Style
scope: all source files
---

# Common Coding Style

These principles apply to every language. Language-specific rules in `rules/{lang}/coding-style.md` extend this baseline and may override idiom-dependent parts (e.g. Go mutability).

## Simplicity first

Pick the dumbest solution that works. Repetition is cheaper than the wrong abstraction, so let a pattern prove itself before extracting it, and build for the requirements you have rather than the ones you can imagine.

## Structure

Write code that reads like the surrounding code: match its naming, idiom, and file organization. A file or function that has outgrown a single idea is the signal to split — size is the symptom, not the rule. Deep nesting usually means a guard clause or an extracted helper is missing.

## Naming

Names describe purpose, not type (`users`, not `userArray`), and booleans read as predicates (`isReady`, `hasItems`). Abbreviate only where the short form is the domain's own vocabulary (`cfg`, `req`, `ctx`).

## Comments

Match the comment density of the surrounding code. A comment earns its place when it records something the code cannot show — a constraint, a workaround, a decision that looks wrong until you know why. Restating the code, or narrating the change you just made, is noise the moment the PR merges.

## Error handling

Fail fast at system boundaries: user input, external APIs, environment config. When you catch, catch to recover, and make the recovery explicit — a swallowed error trades a loud failure now for a silent one later, at a distance from its cause.

## Immutability

Treat data as immutable and functions as pure by default, keeping side effects at the edges of the system. Mutate where the language idiom expects it (see language-specific rules).
