#!/usr/bin/env bash
# Export all SECURITY DEFINER functions from the current DATABASE_URL connection
# into a versioned SQL file. Usage:
#   scripts/export_security_definers.sh [output_path]
# Defaults to supabase/security_definer_export.sql

set -euo pipefail

OUTPUT_PATH=${1:-supabase/security_definer_export.sql}

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL must be set for the export to run." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

{
  echo "-- SECURITY DEFINER export"
  echo "-- Generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') by scripts/export_security_definers.sh"
  echo "-- Source: \$DATABASE_URL"
  echo
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -At <<'SQL'
select format(
  '-- %s.%s(%s)' || E'\n' ||
  replace(pg_get_functiondef(p.oid), '%', '%%') || E'\n',
  n.nspname,
  p.proname,
  pg_get_function_identity_arguments(p.oid)
)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.prosecdef
order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);
SQL
} >"$OUTPUT_PATH"

count=$(grep -c '^CREATE OR REPLACE FUNCTION' "$OUTPUT_PATH" || true)
echo "Exported $count SECURITY DEFINER function(s) to $OUTPUT_PATH"
