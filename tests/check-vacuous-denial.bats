#!/usr/bin/env bats
# Tests for check-vacuous-denial.sh (RT8).
#
# v1 flags Jest/Vitest `it`/`test` blocks that assert a denial status
# (403/429/503) when the file declares a mutation spy but the block has
# no negative call assertion (`.not.toHaveBeenCalled()` /
# `.toHaveBeenCalledTimes(0)`). The denial-status line must be in the
# diff `+` set to flag.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/check-vacuous-denial.sh"

setup() {
  WORK="$(mktemp -d)"
  (cd "$WORK" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$WORK/src/__tests__"
  printf 'import {it,expect} from "vitest"\nit("noop",()=>{expect(1).toBe(1)})\n' \
    > "$WORK/src/__tests__/baseline.test.ts"
  (cd "$WORK" && git add -A && git commit -qm initial)
}

teardown() {
  rm -rf "$WORK"
}

@test "RT8: vacuous denial block (status only, spy in file) fires Major" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
vi.mock('@/lib/prisma', () => ({ deleteMany: vi.fn() }))
describe('gate', () => {
  it('returns 403 only', async () => {
    const res = await handler(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "add vacuous test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  # discriminating substring unique to a finding line (the header always
  # prints "RT8", so asserting on that would be vacuous).
  [[ "$output" == *"denial-path block at"* ]]
}

@test "RT8: guarded denial block (.not.toHaveBeenCalled) is silent" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const deleteMock = vi.fn()
describe('gate', () => {
  it('returns 403 and does not delete', async () => {
    const res = await handler(req)
    expect(res.status).toBe(403)
    expect(deleteMock).not.toHaveBeenCalled()
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "add guarded test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
  [[ "$output" == *"Total findings: 0"* ]]
}

@test "RT8: toHaveBeenCalledTimes(0) counts as the guard" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const createMock = vi.fn()
describe('rate limit', () => {
  it('returns 429 and creates nothing', async () => {
    const res = await handler(req)
    expect(res.status).toBe(429)
    expect(createMock).toHaveBeenCalledTimes(0)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "add times0 test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT8: denial block with no mutation spy in file does not fire" {
  cat > "$WORK/src/__tests__/readonly.test.ts" <<'EOF'
import { describe, it, expect } from 'vitest'
describe('readonly', () => {
  it('returns 403', async () => {
    const res = await handler(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "add readonly test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT8: non-denial status (200) is not flagged" {
  cat > "$WORK/src/__tests__/ok.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const deleteMock = vi.fn()
describe('happy path', () => {
  it('returns 200', async () => {
    const res = await handler(req)
    expect(res.status).toBe(200)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "add ok test")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT8: untouched vacuous test (not in diff +) is not re-flagged" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
vi.mock('@/lib/prisma', () => ({ deleteMany: vi.fn() }))
describe('gate', () => {
  it('returns 403 only', async () => {
    const res = await handler(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "vacuous baseline")
  # Touch an unrelated line in the same file; the denial line is unchanged.
  printf '// trailing comment\n' >> "$WORK/src/__tests__/gate.test.ts"
  (cd "$WORK" && git add -A && git commit -qm "unrelated edit")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT8: read-only denial (GET) is suppressed even with a file-wide write spy" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const deleteMock = vi.fn()
describe('gate', () => {
  it('GET returns 403', async () => {
    const res = await GET(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "read-only denial")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Major]"* ]]
}

@test "RT8: negative control — same fixture with POST (mutating) fires Major" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const deleteMock = vi.fn()
describe('gate', () => {
  it('POST returns 403', async () => {
    const res = await POST(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "mutating denial")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
}

@test "RT8: verb-suffix mock name (mockEntityCreate) is detected as a write spy" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const mockBridgeCodeCreate = vi.fn()
describe('gate', () => {
  it('POST returns 403', async () => {
    const res = await POST(req)
    expect(res.status).toBe(403)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "suffix-verb spy")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
  [[ "$output" == *"Total findings: 1"* ]]
}

@test "RT8: .deleteMany( method-call spy shape is detected" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect } from 'vitest'
describe('rate limit', () => {
  it('PUT returns 429', async () => {
    const res = await PUT(req)
    expect(res.status).toBe(429)
    await prisma.user.deleteMany({ where: {} })
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "method-call spy")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Major]"* ]]
}

@test "RT8: multiple vacuous blocks in one file produce multiple findings" {
  cat > "$WORK/src/__tests__/gate.test.ts" <<'EOF'
import { describe, it, expect, vi } from 'vitest'
const deleteMock = vi.fn()
describe('gate', () => {
  it('POST returns 403', async () => {
    const res = await POST(req)
    expect(res.status).toBe(403)
  })
  it('PATCH returns 429', async () => {
    const res = await PATCH(req)
    expect(res.status).toBe(429)
  })
})
EOF
  (cd "$WORK" && git add -A && git commit -qm "two vacuous blocks")
  run bash -c "cd '$WORK' && bash '$HOOK' HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total findings: 2"* ]]
}

@test "RT8: invalid base-ref exits 1" {
  run bash -c "cd '$WORK' && bash '$HOOK' no-such-ref"
  [ "$status" -eq 1 ]
}
