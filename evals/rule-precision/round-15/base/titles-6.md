# Findings already reported on this change

Three reviewers have already read this diff. These are the titles of what they reported — titles only, deliberately.

- the audit exemption is set on the shared request frame and never released, so the rest of the request writes unaudited
- the new `MUTATIONS` allowlist omits `createMany`, so the audit guard is fail-open for a write this very diff performs
- an org admin can grant `owner` and rewrite existing members' roles through the CSV
- `docs/import.md` and the `enterSystemOperation` comment claim a boundary the code does not implement
- `runImport` has no transaction and no failure path, so a mid-import error leaves memberships half-applied and staged PII behind forever
- the upload size limit is applied after the whole body is buffered, and counts UTF-16 code units under a name that says bytes
- `batchId` is built from an unvalidated client-supplied header, and `import_staging` has neither an org column nor a uniqueness constraint
- `parseRows` throws a `TypeError` on an empty or blank-only CSV, returning a 500
- a missing or misspelled header column silently yields empty fields for every row, and the import reports success
- every new export except `parseRows` ships without a test, and the security control that changed has none at all
- `contextSnapshot` is exported but never called
- `applyBatch` reads the whole batch and upserts one row at a time
- `enterSystemOperation()` sets an ambient flag that is never released, so every write after the staging step runs unaudited
- the new `MUTATIONS` allowlist omits `createMany` and the raw-query actions, so `assertAudited` now returns early for writes it previously guarded
- an org admin can grant `owner` and rewrite any existing member's role, including their own and the current owner's
- `docs/import.md` and `assertAudited`'s doc comment both state a guarantee the code does not provide
- a CSV whose header omits `name` blanks the display name of every member it touches, and the endpoint reports success
- stage → apply → delete are three independent transactions, so a mid-batch failure half-applies the import and orphans the staging rows forever
- `batchId` is derived from a client-supplied header, and `import_staging` has no org column, so the batch key is caller-nameable and unscoped
- the 5 MB upload limit is measured in UTF-16 code units and only after the entire body is already in memory
- nothing bounds the number of rows, and each row is a separate sequential round trip
- every security-relevant symbol in the change ships with no test
- the audit-bypass event is logged at `debug`, below the level production runs at
- `contextSnapshot` is exported and never called
- the default role is declared in two places, and the migration's copy can never fire
- `skipAudit` is set on the caller's context frame and never cleared, so the whole request runs unaudited
- the new `MUTATIONS` allowlist omits `createMany` and the raw actions, so those writes bypass the audit guard everywhere in the codebase
- an org admin can grant `owner` — and overwrite an existing owner's role — through the CSV
- the documentation and the guard's own docstring both claim more than the code implements
- stage, apply and cleanup are three independent transactions, so a failure mid-import leaves memberships half-applied and staging rows orphaned forever
- the 5 MB limit is applied after the entire body has been buffered, and counts UTF-16 code units rather than bytes
- `batchId` is derived from a caller-supplied header, so two imports can collide on the same staging batch
- `parseRows` neither validates the header nor survives an empty upload
- the changed security control, the route's authorization, and the entire import path ship with no tests
- `contextSnapshot` is an unused export whose `Readonly` is shallow and unenforced
- `splitLine` accepts an unterminated quote silently
