// --- src/lib/http/retry.ts (production; exists already, exported) ---------
// Used by six call sites across the codebase.
export async function withRetry<T>(
  fn: () => Promise<T>,
  opts: { attempts?: number; baseMs?: number; jitter?: boolean } = {},
): Promise<T> {
  const attempts = opts.attempts ?? 3;
  const baseMs = opts.baseMs ?? 200;
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (i === attempts - 1) break;
      const backoff = baseMs * 2 ** i;
      const wait = opts.jitter === false ? backoff : backoff * (0.5 + Math.random());
      await sleep(wait);
    }
  }
  throw lastErr;
}

// --- src/integrations/billing/client.ts (added in this change) ------------
// New billing integration. The author did not find withRetry.
async function callWithRetries<T>(fn: () => Promise<T>): Promise<T> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt === 3) throw e;
      await new Promise((r) => setTimeout(r, 200 * attempt));
    }
  }
  throw new Error("unreachable");
}

export async function chargeInvoice(id: string) {
  return callWithRetries(() => billingApi.post(`/invoices/${id}/charge`, {}));
}
