---
name: common-testing
description: Language-agnostic testing minimums and anti-patterns
scope: all test files
---

# Common Testing

New logic ships with a test; a bug fix ships with one that fails before the fix. Prove a test can fail for the reason it claims — if deleting the assertion leaves it green, it is decorative and worse than nothing, because it reads as coverage. Run the full suite before calling work complete.

One concept per test, named for the behavior it pins down (`returns empty list when input is empty`) — the name is what a reader sees when it fails. Needing several unrelated assertions usually means two tests.

Mock at system boundaries (network, clock, filesystem); prefer real objects or in-memory fakes for code you own. A mock encodes a belief about a collaborator, and the more internal that collaborator, the more quietly the belief drifts from reality. Never mock the thing under test — a mocked database cannot validate SQL or migrations.

Assert observable behavior, not internal calls or private state, or the test breaks on every refactor while catching nothing. Start each test from clean state; shared mutable state makes failures depend on order. A test that needs `sleep` is reporting a real race — find it rather than widening the window.
