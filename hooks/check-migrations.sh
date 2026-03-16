#!/bin/bash
# Check for pending database migrations
# Auto-detects migration tool and reports pending migrations
# Non-blocking: always exits 0
# Usage: bash ~/.claude/hooks/check-migrations.sh

set -uo pipefail

TIMEOUT=10
FOUND=0

# Helper: run a command with timeout, capture output and exit code
# Usage: run_check <command...>
# Sets: CHECK_OUTPUT, CHECK_EXIT
run_check() {
  CHECK_OUTPUT=$(timeout "$TIMEOUT" "$@" 2>&1); CHECK_EXIT=$?
  if [ "$CHECK_EXIT" -eq 124 ]; then
    echo "WARNING: Migration check timed out (>${TIMEOUT}s): $1"
    return 1
  elif [ "$CHECK_EXIT" -eq 127 ]; then
    echo "WARNING: Command not found: $1"
    return 1
  fi
  return 0
}

# Prisma (only check when migrations directory exists)
if [ -d "prisma/migrations" ]; then
  FOUND=1
  echo "=== Migration Check: Prisma ==="
  if run_check npx --no-install prisma migrate status; then
    if echo "$CHECK_OUTPUT" | grep -qiE "pending|not yet applied|drift|behind"; then
      echo "WARNING: Pending Prisma migrations detected"
      echo "$CHECK_OUTPUT"
    else
      echo "OK: No pending Prisma migrations"
    fi
  fi
fi

# Rails (db/migrate/)
if [ -d "db/migrate" ] && [ -f "bin/rails" ]; then
  # Verify bin/rails is a Ruby script
  if head -1 bin/rails 2>/dev/null | grep -q "ruby"; then
    FOUND=1
    echo "=== Migration Check: Rails ==="
    if run_check bin/rails db:migrate:status; then
      if echo "$CHECK_OUTPUT" | grep -q "down"; then
        echo "WARNING: Pending Rails migrations detected"
        echo "$CHECK_OUTPUT" | grep "down"
      else
        echo "OK: No pending Rails migrations"
      fi
    fi
  fi
fi

# Alembic (Python)
if [ -d "alembic" ] || [ -f "alembic.ini" ]; then
  FOUND=1
  echo "=== Migration Check: Alembic ==="
  if run_check alembic current; then
    if echo "$CHECK_OUTPUT" | grep -q "(head)"; then
      echo "OK: No pending Alembic migrations"
    else
      echo "WARNING: Pending Alembic migrations detected"
      echo "Current: $CHECK_OUTPUT"
    fi
  fi
fi

# Django
if [ -f "manage.py" ] && grep -q "django\.core\.management" "manage.py" 2>/dev/null; then
  FOUND=1
  echo "=== Migration Check: Django ==="
  if run_check python manage.py showmigrations --plan --no-input; then
    if echo "$CHECK_OUTPUT" | grep -q "\[ \]"; then
      echo "WARNING: Pending Django migrations detected"
      echo "$CHECK_OUTPUT" | grep "\[ \]"
    else
      echo "OK: No pending Django migrations"
    fi
  fi
fi

# Extensible: add more migration tools above this line

if [ "$FOUND" -eq 0 ]; then
  echo "No migration tool detected. Skipping migration check."
fi

exit 0
