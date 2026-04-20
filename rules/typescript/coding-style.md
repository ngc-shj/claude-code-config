---
name: typescript-coding-style
description: TypeScript-specific coding style — extends common/coding-style.md
scope: TypeScript and JavaScript sources
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---

# TypeScript Coding Style

Extends [common/coding-style.md](../common/coding-style.md).

## Types

- Prefer `type` aliases for unions, primitives, and function signatures. Use `interface` when the shape needs declaration merging or when class-like extension helps.
- Never use `any`. When the type is truly unknown, use `unknown` and narrow explicitly.
- Narrow `unknown` with type predicates (`function isFoo(x: unknown): x is Foo`) or a schema validator (e.g. Zod) — not with casts.
- Avoid non-null assertion (`!`). If you know it is defined, express it in the type. If you do not, handle the undefined case.

## Immutability

- Default to `const`. Use `let` only when reassignment is the clearest expression.
- Prefer `readonly` arrays and object properties for data passed across module boundaries.

## Async

- Always `await` promises or return them. A floating promise is a bug.
- Wrap `Promise.all` only when operations are truly independent. Sequential awaits are fine when each step depends on the previous.

## Modules

- Use named exports. Default exports make refactors and re-exports painful.
- Keep `index.ts` barrel files shallow. Deep barrels break tree shaking and create import cycles.

## Errors

- Throw `Error` subclasses with meaningful names (`ValidationError`, `NotFoundError`), not plain strings.
- Catch clauses type the error as `unknown`. Narrow before accessing `.message`.

## Tooling

- Run the project's typecheck and lint before marking work complete. Detect the command from `package.json` scripts (`typecheck`, `lint`) rather than assuming `tsc --noEmit`.
