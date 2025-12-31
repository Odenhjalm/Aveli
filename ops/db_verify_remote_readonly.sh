#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${REPORT_PATH:-${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md}"
ALLOWLIST_PATH="${ALLOWLIST_PATH:-${ROOT_DIR}/docs/ops/SUPABASE_ALLOWLIST.txt}"
MASTER_ENV_FILE="/home/oden/Aveli/backend/.env"

load_master_env() {
  if [[ ! -f "$MASTER_ENV_FILE" ]]; then
    echo "ERROR: master.env missing at ${MASTER_ENV_FILE}" >&2
    exit 1
  fi
  eval "$(
    python3 - <<'PY' "$MASTER_ENV_FILE"
import shlex
import sys

path = sys.argv[1]
for raw_line in open(path, "r", encoding="utf-8"):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if value and value[0] == value[-1] and value[0] in ("\"", "'"):
        value = value[1:-1]
    if not key:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
  )"
}

load_master_env

# SUPABASE_PROJECT_REF is required; if missing, derive it from SUPABASE_URL.
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
if [[ -z "$PROJECT_REF" && -n "${SUPABASE_URL:-}" ]]; then
  PROJECT_REF="$(python3 - <<'PY' "$SUPABASE_URL"
import sys
from urllib.parse import urlparse

url = sys.argv[1]
host = urlparse(url).hostname or ""
ref = host.split(".")[0] if host else ""
print(ref)
PY
  )"
fi
DB_URL="${SUPABASE_DB_URL:-}"

append_report() {
  if [[ -f "$REPORT_PATH" ]]; then
    cat >>"$REPORT_PATH"
  fi
}

if [[ -z "$PROJECT_REF" ]]; then
  append_report <<'TXT'

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not set and SUPABASE_URL not provided
TXT
  exit 2
fi

if [[ ! -f "$ALLOWLIST_PATH" ]]; then
  append_report <<TXT

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: Allowlist missing at docs/ops/SUPABASE_ALLOWLIST.txt
TXT
  exit 2
fi

if ! grep -qx "$PROJECT_REF" "$ALLOWLIST_PATH"; then
  append_report <<TXT

## Remote DB Verify (read-only)
Status: SKIPPED
Reason: SUPABASE_PROJECT_REF not allowlisted
TXT
  exit 2
fi

if [[ -z "$DB_URL" ]]; then
  append_report <<'TXT'

## Remote DB Verify (read-only)
Status: FAILED
Reason: SUPABASE_DB_URL not set in master.env
TXT
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  append_report <<'TXT'

## Remote DB Verify (read-only)
Status: FAILED
Reason: psql not available
TXT
  exit 1
fi

READONLY_PGOPTIONS="-c default_transaction_read_only=on"
run_sql() {
  PGOPTIONS="$READONLY_PGOPTIONS" psql "$DB_URL" -tA -F $'\t' -v ON_ERROR_STOP=1 -c "$1"
}

app_tables_raw=$(run_sql "select table_name from information_schema.tables where table_schema = 'app' and table_type = 'BASE TABLE' order by table_name;")
app_tables_count=$(echo "$app_tables_raw" | sed '/^$/d' | wc -l | tr -d ' ')

rls_disabled_raw=$(run_sql "select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and c.relkind = 'r' and c.relrowsecurity = false order by c.relname;")
rls_disabled=$(echo "$rls_disabled_raw" | sed '/^$/d')

no_policy_raw=$(run_sql "select t.table_name from information_schema.tables t left join pg_policies p on p.schemaname = 'app' and p.tablename = t.table_name where t.table_schema = 'app' and t.table_type = 'BASE TABLE' group by t.table_name having count(p.policyname) = 0 order by t.table_name;")
no_policy=$(echo "$no_policy_raw" | sed '/^$/d')

storage_exists=$(run_sql "select to_regclass('storage.buckets') is not null;")
if [[ "$storage_exists" == "t" ]]; then
  storage_buckets=$(run_sql "select id || ' (public=' || public || ')' from storage.buckets order by id;")
  storage_policies=$(run_sql "select policyname || ' [' || cmd || ']' from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname, cmd;")
  storage_rls=$(run_sql "select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'storage' and c.relname = 'objects';")
  public_media_public=$(run_sql "select public from storage.buckets where id = 'public-media';")
  course_media_public=$(run_sql "select public from storage.buckets where id = 'course-media';")
  lesson_media_public=$(run_sql "select public from storage.buckets where id = 'lesson-media';")
else
  storage_buckets=""
  storage_policies=""
  storage_rls=""
  public_media_public=""
  course_media_public=""
  lesson_media_public=""
fi

migrations_exists=$(run_sql "select to_regclass('supabase_migrations.schema_migrations') is not null;")
if [[ "$migrations_exists" == "t" ]]; then
  db_migrations=$(run_sql "select name from supabase_migrations.schema_migrations order by name;")
else
  db_migrations=""
fi

repo_migrations=$(find "$ROOT_DIR/supabase/migrations" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)

missing_in_db=""
extra_in_db=""
if [[ -n "$db_migrations" ]]; then
  missing_in_db=$(comm -23 <(echo "$repo_migrations") <(echo "$db_migrations") || true)
  extra_in_db=$(comm -13 <(echo "$repo_migrations") <(echo "$db_migrations") || true)
fi

storage_issue=""
if [[ -n "$storage_exists" && "$storage_exists" == "t" ]]; then
  if [[ "$public_media_public" != "t" ]]; then
    storage_issue="public-media should be public"
  elif [[ "$course_media_public" != "f" || "$lesson_media_public" != "f" ]]; then
    storage_issue="course-media and lesson-media should be private"
  elif [[ -z "$storage_policies" ]]; then
    storage_issue="storage.objects policies missing"
  elif [[ "$storage_rls" != "t" ]]; then
    storage_issue="storage.objects RLS disabled"
  fi
fi

append_report <<TXT

## Remote DB Verify (read-only)
Status: COMPLETED
- App tables: ${app_tables_count}
- RLS disabled tables: ${rls_disabled:-none}
- Tables without policies: ${no_policy:-none}
- Storage buckets: ${storage_buckets:-none}
- Storage objects RLS: ${storage_rls:-unknown}
- Storage policies: ${storage_policies:-none}
- Storage bucket sanity: ${storage_issue:-ok}
- Migration tracking: $(if [[ -n "$db_migrations" ]]; then echo "schema_migrations present"; else echo "no schema_migrations table"; fi)
- Migrations missing in DB: ${missing_in_db:-unknown}
- Migrations extra in DB: ${extra_in_db:-unknown}
TXT

if [[ -n "$rls_disabled" || -n "$no_policy" || -n "$storage_issue" ]]; then
  exit 1
fi
