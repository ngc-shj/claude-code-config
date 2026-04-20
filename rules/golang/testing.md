---
name: golang-testing
description: Go testing conventions — extends common/testing.md
scope: Go test files
paths:
  - "**/*_test.go"
---

# Go Testing

Extends [common/testing.md](../common/testing.md).

## Structure

- Test files live in the same package as the code (`foo_test.go` in package `foo`). Use `package foo_test` only when testing through the exported API is the point.
- Table-driven tests are the default. One `tests := []struct{...}` slice, one loop, `t.Run(tc.name, ...)` for subtests.
- Subtests get descriptive names — `empty_input`, not `tc1`.

## Assertions

- Use the standard library where possible. `t.Errorf` / `t.Fatalf` with a clear message is often enough.
- If using `testify` or similar, follow the project's existing choice. Do not mix assertion libraries.
- `cmp.Diff` (from `github.com/google/go-cmp`) beats manual field-by-field checks for structs.

## Test helpers

- Call `t.Helper()` at the top of any helper so failures point to the caller.
- Use `t.Cleanup` for teardown. Avoid `defer` in tests — it runs before subtests finish.
- `t.TempDir()` for temporary files — never `os.TempDir()` directly.

## Parallelism

- Call `t.Parallel()` on independent tests. Do not call it on tests that touch shared mutable state (env vars, working directory, global registries).
- When using table-driven tests with `t.Parallel()`, capture the loop variable: `tc := tc`.

## Mocking

- Prefer interfaces at the consumer side — they make test doubles trivial without a mocking framework.
- When a framework is unavoidable, follow the project's choice (`gomock`, `mockery`). Do not introduce a second one.
