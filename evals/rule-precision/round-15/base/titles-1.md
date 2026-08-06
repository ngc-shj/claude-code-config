# Findings already reported on this change

Three reviewers have already read this diff. These are the titles of what they reported — titles only, deliberately.

- `createMany` is absent from `MUTATIONS`, so the audit guard is fail-open for a whole Prisma action class
- `enterSystemOperation` sets the audit-suspension flag on the caller's shared context and never restores it
- an org admin can promote any account, including their own, to `owner`
- the docs state the promotion step is audited and that every membership change writes an audit record; neither is true as implemented
- the 5 MB cap is measured in UTF-16 code units and applied after the entire body is buffered
- the batch key is derived from a client-supplied header, so two imports in one org can collide
- no transaction, and staged member data leaks permanently when the import fails partway
- the audit control and the route this change adds ship with no tests at all
- `parseRows` reports a malformed header as a file full of rejected rows
- `parseRows` splits on newlines before parsing quotes, and the quoting tests do not reach it
- `contextSnapshot` is exported, unused, and its `Readonly` is a compile-time marker only
- `enterSystemOperation` mutates the live request context, so the audit bypass leaks over the whole import request
- the new `MUTATIONS` allowlist omits `createMany` and the raw-query actions, so those writes now skip the audit control application-wide
- an org admin can grant and revoke `owner` through the CSV
- the three import phases commit independently, so a failure strands staged rows forever
- `batchId` is built from a client-supplied header, so two concurrent imports in one org can process and delete each other's rows
- the 5 MB limit is neither a byte limit nor applied before the body is buffered
- an empty or column-shifted CSV either crashes the request or silently rejects every row
- the audit-guard change and every new export except the parser ship with no test
- docs/import.md and the guard's doc comment claim a control the implementation does not have
- `contextSnapshot` is exported but never called
- promotion is unbounded and one round-trip per row, while staging is carefully chunked
- email validity is decided deep in the promotion loop, not at the parse boundary, and rejections are unattributable
- `enterSystemOperation` grants the audit exemption to the whole request, not to the staging call
- bulk import lets an org admin grant `owner`, including to themselves
- the audit control is described as a refusal but on this route it can never refuse, and nothing writes an audit record
- stage → apply → cleanup are three independent commits with no transaction and no failure path
- the batch key is caller-controlled and `import_staging` has no tenancy column
- the 5 MB cap counts UTF-16 code units and runs after the whole body is buffered
- `parseRows` throws on an empty upload and silently empties every email when the header is misspelled
- quoted fields containing a newline are torn apart before the quote parser ever sees them
- every new export except the CSV parser ships with no test
- is `POST /api/import` behind the shared rate limiter?
- `contextSnapshot` is exported with no caller, and the one site that wants it does not use it
- the email check sits after the rows are already written, so `staged` counts rows that were never applicable
