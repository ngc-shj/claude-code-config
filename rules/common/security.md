---
name: common-security
description: Language-agnostic security checklist that extends CLAUDE.md Safety section
scope: all source files
---

# Common Security

Extends the Safety section in CLAUDE.md with concrete patterns to check during edits and reviews.

## Secrets

- Never hardcode API keys, tokens, passwords, private keys, connection strings.
- Read secrets from environment variables or a secrets manager. Local dev uses `.env`, which must be gitignored.
- If a secret is committed, rotate it immediately — removing the commit is not enough.

## Input validation

- Validate at the boundary: HTTP handlers, CLI arg parsers, message consumers.
- Reject unknown fields rather than silently ignoring them when the schema is authoritative.
- Length-cap every user-supplied string before logging, storing, or comparing.

## Injection

- SQL — use parameterized queries or a query builder. Never concatenate user input into SQL.
- Shell — prefer language-native APIs over spawning a shell. If you must shell out, pass args as an array, not a single string.
- HTML — escape by default. Raw HTML insertion requires a comment explaining why it is safe.

## Authentication and authorization

- Check authorization on every handler that touches user data, not only at the gateway.
- Do not roll your own crypto. Use the platform's vetted library.
- Rate-limit authentication endpoints. Log failures with enough context to detect abuse.

## Dependency hygiene

- Pin versions. Review lock file changes in PRs.
- Do not add a dependency for something that is 10 lines of code.
- Audit for known CVEs before upgrading major versions.

## Logging

- Never log secrets, tokens, session IDs, or full request bodies.
- Log user identifiers by ID, not email or name, when possible.
