# Defect sketch — F9 (audit-skip flag left set on the request context)

The post-change shape of the three files that carry the defect in
`../fixtures/F9-R54b.diff`, extracted so a panel can enumerate the properties a
correct fix must have without doing any detection work. Panellists see this file
and the neutral statement below, and nothing else — no rule set, no arm, no
review output. Method: rounds 5 and 6 (`../independent-rubric.md`,
`../panel-audit.md`).

## Neutral statement of what is wrong

`enterSystemOperation()` sets `skipAudit` on the request context so the
importer's staging writes can bypass the audit guard, and nothing ever clears
it. Every later write in the same request — the membership promotions and the
activity record — therefore passes the guard unaudited.

## `src/context/request.ts`

```ts
import { AsyncLocalStorage } from "node:async_hooks";

export interface RequestContext {
  requestId: string;
  actorId: string;
  orgId: string;
  /** When set, `assertAudited` lets a write through without an audit record. */
  skipAudit?: boolean;
}

const storage = new AsyncLocalStorage<RequestContext>();

export function runWithContext<T>(ctx: RequestContext, fn: () => Promise<T>): Promise<T> {
  return storage.run(ctx, fn);
}

export function currentContext(): RequestContext {
  const ctx = storage.getStore();
  if (!ctx) throw new Error("no request context");
  return ctx;
}

/**
 * A few internal operations legitimately write without an audit row — the
 * importer's staging writes, the nightly reconciler, the schema backfill.
 * They announce themselves here so `assertAudited` lets them through.
 *
 * Only system operations may call this.
 */
export function enterSystemOperation(): void {
  const ctx = currentContext();
  ctx.skipAudit = true;
}

export function contextSnapshot(): Readonly<RequestContext> {
  return { ...currentContext() };
}
```

## `src/audit/guard.ts`

```ts
import { currentContext } from "../context/request";
import { logger } from "../logger";

export class UnauditedWriteError extends Error {}

const MUTATIONS = new Set(["create", "update", "delete", "deleteMany", "updateMany", "upsert"]);

/**
 * Called by the Prisma middleware before every mutating query. A write that
 * carries no audit intent is refused — the audit trail is the control, and a
 * write that dodges it is the thing we are protecting against.
 */
export function assertAudited(model: string, action: string): void {
  if (!MUTATIONS.has(action)) return;

  const ctx = currentContext();
  if (ctx.skipAudit) {
    logger.debug({ model, action, requestId: ctx.requestId }, "audit skipped");
    return;
  }
  if (!ctx.actorId) {
    throw new UnauditedWriteError(`${action} on ${model} with no actor`);
  }
  logger.info({ model, action, actorId: ctx.actorId }, "audited write");
}
```

## `src/import/bulk.ts` (the caller)

```ts
/**
 * Stage the parsed rows into `import_staging`. These are scratch rows the
 * operator can inspect before applying, so they carry no audit record.
 */
async function stageRows(batchId: string, rows: ImportRow[]): Promise<number> {
  enterSystemOperation();

  let staged = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const chunk = rows.slice(i, i + CHUNK);
    await prisma.importStaging.createMany({
      data: chunk.map((r) => ({
        batchId,
        email: r.email,
        displayName: r.displayName,
        role: r.role,
      })),
    });
    staged += chunk.length;
  }
  return staged;
}

/**
 * Promote staged rows into real members. Each promotion is a real membership
 * change and is audited.
 */
async function applyBatch(batchId: string): Promise<{ applied: number; rejected: number }> {
  const ctx = currentContext();
  const staged = await prisma.importStaging.findMany({ where: { batchId } });

  let applied = 0;
  let rejected = 0;

  for (const row of staged) {
    if (!row.email.includes("@")) {
      rejected += 1;
      continue;
    }

    await prisma.membership.upsert({
      where: { orgId_email: { orgId: ctx.orgId, email: row.email } },
      create: { orgId: ctx.orgId, email: row.email, displayName: row.displayName, role: row.role },
      update: { displayName: row.displayName, role: row.role },
    });
    applied += 1;
  }

  return { applied, rejected };
}

export async function runImport(csv: string): Promise<ImportSummary> {
  const ctx = currentContext();
  const batchId = `${ctx.orgId}-${ctx.requestId}`;

  const rows = parseRows(csv);
  const staged = await stageRows(batchId, rows);
  const { applied, rejected } = await applyBatch(batchId);

  await prisma.importStaging.deleteMany({ where: { batchId } });

  return { staged, applied, rejected, batchId };
}
```

The route handler wraps `runImport` in `runWithContext({ requestId, actorId,
orgId }, ...)` after an admin/owner session check, and writes an
`orgActivity.create` record inside the same context once the import returns.
