---
name: common-security
description: Language-agnostic security checklist that extends CLAUDE.md Safety section
scope: all source files
---

# Common Security

Extends the Safety section in CLAUDE.md. Most of this is judgment; the few absolutes are marked, because those are the cases where a plausible exception is how the breach happens.

**Never commit a credential** — keys, tokens, passwords, connection strings. Read them from the environment or a secrets manager; keep `.env` gitignored. A pushed secret is compromised, so rotate it — deleting the commit does not un-publish it.

Validate untrusted data at the boundary where it enters (HTTP handlers, CLI parsers, message consumers), and treat it as checked past that point. Where the schema is the contract, reject unknown fields; bound the size of anything you store, log, or compare.

Injection is user data reaching an engine that interprets it as code. **Never build SQL by concatenation** — parameterize. Prefer native APIs over a shell, passing arguments as a list. Escape HTML by default; raw insertion needs a comment saying why it is safe.

Authorize in the handler that touches the data, not only at the gateway — gateways get bypassed, refactored, or reused for a second entry point. **Do not write your own crypto.** Rate-limit authentication paths and log failures with enough context to spot abuse, without logging what was attempted.

Every dependency is code you now own: pin versions, read lock file changes, check CVEs before a major upgrade. A ten-line utility is usually cheaper to own than to import.

Logs get shipped, indexed, and read by people never meant to see the payload. Keep secrets, tokens, session IDs, and full request bodies out; prefer opaque user IDs over names or emails.
