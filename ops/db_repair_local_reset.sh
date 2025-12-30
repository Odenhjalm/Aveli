#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB_URL="${SUPABASE_DB_URL:-${DATABASE_URL:-}}"
if [[ -z "$DB_URL" ]]; then
  echo "SUPABASE_DB_URL (or DATABASE_URL) is required" >&2
  exit 1
fi

if [[ "${CONFIRM_LOCAL_RESET:-}" != "1" ]]; then
  echo "Refusing to reset without CONFIRM_LOCAL_RESET=1" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required for local reset" >&2
  exit 1
fi

host=$(python3 - <<'PY' "$DB_URL"
import sys
from urllib.parse import urlparse

raw = sys.argv[1]
parsed = urlparse(raw)
print(parsed.hostname or "")
PY
)

case "$host" in
  localhost|127.0.0.1|0.0.0.0|::1) ;;
  *)
    echo "Refusing to reset non-local database host" >&2
    exit 1
    ;;
 esac

export SUPABASE_DB_URL="$DB_URL"

cat <<'SQL' | psql "$DB_URL" -v ON_ERROR_STOP=1
begin;
drop schema if exists app cascade;
create schema app;
commit;
SQL

"${ROOT_DIR}/backend/scripts/apply_supabase_migrations.sh"

echo "Local Supabase reset complete."
