# Findings already reported on this change

Three reviewers have already read this diff. These are the titles of what they reported — titles only, deliberately.

- `enterSystemOperation()` grants the audit exemption to the whole request, not to the staging write
- `MUTATIONS` omits `createMany`, so the new early return disables the audit guard for a whole class of writes repo-wide
- an org admin can grant `owner` and can rewrite an existing owner's role through the CSV
- stage → apply → delete runs as three independent transactions, and staging rows are only ever cleaned up on the success path
- `batchId` is built from a caller-supplied header, so two requests can share one staging namespace
- the 5 MB upload limit is measured in UTF-16 code units and only after the whole body is buffered
- `parseRows` throws a raw `TypeError` on an empty body and silently rejects every row when the `email` column is missing
- `docs/import.md` claims the promotion step is audited and that the middleware refuses any unaudited mutation; the code does neither
- the only new test covers `parseRows`; every new export and the changed audit guard ship untested
- `contextSnapshot` is exported but never called, and its `Readonly` promise is compile-time only
- the same constants are restated in three places
- `enterSystemOperation()` disarms the audit guard for the whole remainder of the request
- the `MUTATIONS` allowlist omits `createMany` and every raw action, so the audit guard is fail-open by default
- an org admin can grant `owner` to any address, and can overwrite an existing owner's role
- no transaction and no failure-path cleanup around stage → apply → delete
- `batchId` is built from a client-controlled header, and `import_staging` has no tenancy column
- the 5 MB cap counts UTF-16 code units and is applied after the whole body is buffered
- `parseRows` throws on an empty body, and a header without an `email` column silently rejects every row
- the security control this change is built around ships with no test, and no check was proven able to fail
- `docs/import.md` and the `applyBatch` comment claim an audit guarantee the code does not provide
- `contextSnapshot` is unused, and `Readonly<T>` on a shallow copy is not immutability
- an audit bypass is logged below the default level and without the actor
- `import_staging` lacks a tenancy column, a role constraint, and a nullability match
- `enterSystemOperation()` grants the audit exemption to the whole request, so every membership write in an import is unaudited
- the new `MUTATIONS` allowlist turns the audit guard into a blacklist and omits `createMany` and the raw-SQL actions
- an org admin can promote any address — including their own — to `owner` through the CSV
- the new tables are created in SQL only — `prisma.importStaging` and `prisma.orgActivity` have no model
- `batchId` is derived from a client-supplied header, and the staging queries carry no tenancy predicate
- stage → apply → delete is three independent commits, so a failure leaves memberships half-applied and staging rows orphaned forever
- the new route has no rate limiter, and its size cap counts UTF-16 units after the whole body is already in memory
- every security-relevant symbol in the change ships with no test
- the docs and comments describe controls the code does not implement
- `parseRows` throws on an empty body and silently rejects everything when the header lacks `email`
- `contextSnapshot` is a new export with no caller and no test
- role matching is case-sensitive while the adjacent email is lower-cased
