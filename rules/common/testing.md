---
name: common-testing
description: Language-agnostic testing minimums and anti-patterns
scope: all test files
---

# Common Testing

## Minimum bar

- New logic ships with a test. Bug fixes ship with a regression test that fails before the fix.
- Tests must fail for a real reason. If removing the assertion does not break the test, the test is decorative.
- Run the full test suite before marking a task complete.

## Structure

- Arrange / Act / Assert — one concept per test, separated by blank lines.
- One behavioral assertion per test. Grouping unrelated checks hides which one failed.
- Test names state behavior: `returns empty list when input is empty`, not `testGetUsers1`.

## Mocking

- Mock at system boundaries (network, clock, filesystem), not internal collaborators.
- Prefer real objects and in-memory fakes over mocks for code you own.
- Never mock the database when the test's purpose is to validate SQL or migrations.

## Anti-patterns

- Do not assert implementation details (internal method calls, private state).
- Do not share mutable state across tests. Each test starts clean.
- Do not add `sleep` to make a flaky test pass — find the real race.
