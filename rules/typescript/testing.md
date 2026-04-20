---
name: typescript-testing
description: TypeScript/JavaScript testing conventions — extends common/testing.md
scope: TypeScript and JavaScript test files
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.test.js"
  - "**/*.spec.ts"
  - "**/*.spec.js"
  - "**/__tests__/**"
---

# TypeScript Testing

Extends [common/testing.md](../common/testing.md).

## Framework detection

- Detect the framework from `package.json` (`jest`, `vitest`, `mocha`, `node --test`). Do not hardcode assumptions.
- Use the project's existing test setup file. Do not introduce a new global config to make one test pass.

## Mocking

- Prefer `vi.mock` / `jest.mock` at module scope over dynamic per-test mocking.
- When mocking a function returning a typed object, type the mock against the real type — not `as any`. Structural drift between mock and real type is a common source of false-green tests.
- For HTTP, use `msw` or a framework-native fetch mock. Do not mock `global.fetch` ad hoc.

## React / JSX components

- Test behavior through the rendered DOM (`@testing-library/react`), not component internals.
- Query by role or label, not by test-id, unless no accessible query is available.
- Avoid snapshot tests that capture entire component trees. Snapshots drift and nobody reads the diff.

## Async

- `await` every async assertion. Forgotten `await` on `expect(...).resolves` is a common silent pass.
- Prefer `findBy*` over `waitFor(() => getBy*)` — it is shorter and has the same semantics.
