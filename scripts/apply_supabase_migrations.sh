#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required" >&2
  exit 1
fi
PGPASSWORD=${SUPABASE_DB_PASSWORD:-}
export PGPASSWORD
find "$ROOT_DIR/supabase/migrations" -maxdepth 1 -type f -name '*.sql' | sort | while read -r file; do
  echo "Applying ${file}"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$file"
done
