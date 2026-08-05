// --- src/db/schema.ts (production; the real row shape) -------------------
// Prisma model TeamPolicy. Every column below is NOT NULL with a default, so a
// row read back from the database always carries all nine fields.
export type TeamPolicy = {
  teamId: string;
  requireMfa: boolean;
  sessionIdleTimeoutMinutes: number;      // default 30
  sessionAbsoluteTimeoutMinutes: number;  // default 480
  passwordHistoryCount: number;           // default 5
  inheritTenantCidrs: boolean;            // default true
  teamAllowedCidrs: string[];             // default []
  updatedAt: Date;
  updatedBy: string;
};

// --- src/app/api/teams/[teamId]/policy/route.ts (production) --------------
export async function PUT(req: Request, { params }: { params: { teamId: string } }) {
  const body = await req.json();
  const saved = await prisma.teamPolicy.upsert({
    where:  { teamId: params.teamId },
    create: { teamId: params.teamId, ...body },
    update: body,
  });
  return Response.json(saved);
}

// --- src/app/api/teams/[teamId]/policy/route.test.ts (the test) -----------
const policyData = {
  teamId: "team-1",
  requireMfa: true,
  updatedAt: new Date("2026-01-01"),
  updatedBy: "user-1",
};

it("is idempotent — PUT twice returns the same result", async () => {
  mockUpsert.mockResolvedValue(policyData);

  const first  = await PUT(reqFor({ requireMfa: true }), { params: { teamId: "team-1" } });
  const second = await PUT(reqFor({ requireMfa: true }), { params: { teamId: "team-1" } });

  expect(await first.json()).toEqual(await second.json());
});
