#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_PATH="${REPORT_PATH:-${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md}"
MASTER_ENV_FILE="/home/oden/Aveli/backend/.env"
LOG_PATH="/tmp/aveli_remote_db_verify_$(date +%Y%m%d-%H%M%S).json"

LOG_STATUS=""
LOG_REASON=""
ENV_STAGE="dev"

is_prod_env() {
  local raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
  local lowered="${raw,,}"
  if [[ "$lowered" == "prod" || "$lowered" == "production" || "$lowered" == "live" ]]; then
    return 0
  fi
  return 1
}

write_log() {
  local status="$1"
  local reason="${2:-}"
  python3 - <<'PY' "$LOG_PATH" "$status" "$reason"
import json
import os
import sys

log_path, status, reason = sys.argv[1:4]

def split_lines(value: str) -> list[str]:
    return [line for line in value.splitlines() if line.strip()]

data = {
    "status": status,
    "reason": reason or None,
    "master_env": os.environ.get("MASTER_ENV_FILE"),
    "supabase_db_url_present": bool(os.environ.get("SUPABASE_DB_URL")),
    "app_tables_count": int(os.environ.get("APP_TABLES_COUNT", "0") or 0),
    "rls_disabled_tables": split_lines(os.environ.get("RLS_DISABLED", "")),
    "tables_without_policies": split_lines(os.environ.get("NO_POLICY", "")),
    "storage_buckets": split_lines(os.environ.get("STORAGE_BUCKETS", "")),
    "storage_objects_rls": os.environ.get("STORAGE_RLS", ""),
    "storage_policies": split_lines(os.environ.get("STORAGE_POLICIES", "")),
    "storage_bucket_sanity": os.environ.get("STORAGE_ISSUE", ""),
    "schema_migrations_present": os.environ.get("SCHEMA_MIGRATIONS_PRESENT", ""),
    "migrations_missing_in_db": split_lines(os.environ.get("MISSING_IN_DB", "")),
    "migrations_extra_in_db": split_lines(os.environ.get("EXTRA_IN_DB", "")),
}

with open(log_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
print(f"Remote DB verify log: {log_path}")
PY
}

on_exit() {
  local exit_code=$?
  if [[ -z "$LOG_STATUS" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      LOG_STATUS="COMPLETED"
    else
      LOG_STATUS="FAILED"
      LOG_REASON="${LOG_REASON:-unexpected failure}"
    fi
  fi
  write_log "$LOG_STATUS" "$LOG_REASON"
}

trap on_exit EXIT

append_report() {
  if [[ "${VERIFY_WRITE_REPORT:-0}" != "1" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$REPORT_PATH")"
  cat >>"$REPORT_PATH"
}

load_master_env() {
  if [[ ! -f "$MASTER_ENV_FILE" ]]; then
    echo "ERROR: master env missing at ${MASTER_ENV_FILE}" >&2
    LOG_STATUS="FAILED"
    LOG_REASON="master env missing"
    append_report <<TXT

## Remote DB Verify (read-only)
Status: FAILED
Reason: master env missing at ${MASTER_ENV_FILE}
TXT
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
if is_prod_env; then
  ENV_STAGE="live"
fi

DB_URL="${SUPABASE_DB_URL:-}"
if [[ -z "$DB_URL" ]]; then
  echo "ERROR: SUPABASE_DB_URL missing in master env (${MASTER_ENV_FILE})" >&2
  LOG_STATUS="FAILED"
  LOG_REASON="SUPABASE_DB_URL missing"
  append_report <<TXT

## Remote DB Verify (read-only)
Status: FAILED
Reason: SUPABASE_DB_URL missing in master env (${MASTER_ENV_FILE})
TXT
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not available" >&2
  LOG_STATUS="FAILED"
  LOG_REASON="psql not available"
  append_report <<TXT

## Remote DB Verify (read-only)
Status: FAILED
Reason: psql not available
TXT
  exit 1
fi

READONLY_PGOPTIONS="-c default_transaction_read_only=on"
run_sql() {
  LOG_REASON="psql failed running query"
  local output
  output=$(PGOPTIONS="$READONLY_PGOPTIONS" psql "$DB_URL" -tA -F $'\t' -v ON_ERROR_STOP=1 -c "$1")
  LOG_REASON=""
  printf "%s" "$output"
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
  db_migrations=$(run_sql "select name from supabase_migrations.schema_migrations where name is not null order by name;")
else
  db_migrations=""
fi

repo_migrations=$(
  python3 - <<'PY' "$ROOT_DIR/supabase/migrations"
import re
import sys
from pathlib import Path

migrations_dir = Path(sys.argv[1])
names: set[str] = set()
sync_names: set[str] = set()

if migrations_dir.exists():
    for path in migrations_dir.glob("*.sql"):
        base = path.name
        if base.lower().endswith(".sql"):
            base = base[:-4]
        normalized = re.sub(r"^\d+_", "", base)
        names.add(normalized)
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped.startswith("--"):
                continue
            lower = stripped.lower()
            if lower.startswith("-- sync-migration:") or lower.startswith("-- sync-migrations:"):
                payload = stripped.split(":", 1)[1]
                for item in re.split(r"[\s,]+", payload):
                    item = item.strip().strip("\"' ")
                    if item:
                        sync_names.add(item)

names |= sync_names
for name in sorted(names):
    print(name)
PY
)

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
else
  storage_issue="storage.buckets missing"
fi

status="COMPLETED"
reason=""
exit_code=0
has_rls_issue=false
has_storage_issue=false
has_migration_drift=false

if [[ -n "$rls_disabled" || -n "$no_policy" ]]; then
  has_rls_issue=true
fi
if [[ -n "$storage_issue" ]]; then
  has_storage_issue=true
fi
if [[ -n "$missing_in_db" || -n "$extra_in_db" ]]; then
  has_migration_drift=true
fi

if [[ "$has_rls_issue" == "true" || "$has_storage_issue" == "true" || "$has_migration_drift" == "true" ]]; then
  reasons=()
  if [[ "$has_rls_issue" == "true" ]]; then
    reasons+=("RLS/policy gaps")
  fi
  if [[ "$has_storage_issue" == "true" ]]; then
    reasons+=("storage bucket/policy issues")
  fi
  if [[ "$has_migration_drift" == "true" ]]; then
    reasons+=("migration drift")
  fi

  if [[ "$ENV_STAGE" == "dev" && "$has_migration_drift" == "true" && "$has_rls_issue" != "true" && "$has_storage_issue" != "true" ]]; then
    status="WARN"
    reason="migration drift (missing/extra migrations) in development"
    exit_code=2
  else
    status="FAILED"
    reason="$(IFS=", "; echo "${reasons[*]}")"
    exit_code=1
  fi
fi

export MASTER_ENV_FILE
export APP_TABLES_COUNT="$app_tables_count"
export RLS_DISABLED="$rls_disabled"
export NO_POLICY="$no_policy"
export STORAGE_BUCKETS="$storage_buckets"
export STORAGE_RLS="$storage_rls"
export STORAGE_POLICIES="$storage_policies"
export STORAGE_ISSUE="$storage_issue"
export SCHEMA_MIGRATIONS_PRESENT="$migrations_exists"
export MISSING_IN_DB="$missing_in_db"
export EXTRA_IN_DB="$extra_in_db"

append_report <<TXT

## Remote DB Verify (read-only)
Status: ${status}
$(if [[ -n "$reason" ]]; then echo "Reason: ${reason}"; fi)
- Master env: ${MASTER_ENV_FILE}
- SUPABASE_DB_URL: set
- App tables: ${app_tables_count}
- RLS disabled tables: ${rls_disabled:-none}
- Tables without policies: ${no_policy:-none}
- Storage buckets: ${storage_buckets:-none}
- Storage objects RLS: ${storage_rls:-unknown}
- Storage policies: ${storage_policies:-none}
- Storage bucket sanity: ${storage_issue:-ok}
- Migration tracking: $(if [[ -n "$db_migrations" ]]; then echo "schema_migrations present"; else echo "no schema_migrations table"; fi)
- Migrations missing in DB: ${missing_in_db:-none}
- Migrations extra in DB: ${extra_in_db:-none}
TXT

if [[ "$status" == "FAILED" ]]; then
  LOG_STATUS="FAILED"
  LOG_REASON="${reason:-remote DB checks failed}"
  echo "Remote DB verify: FAIL (${LOG_REASON})" >&2
  exit "$exit_code"
fi

if [[ "$status" == "WARN" ]]; then
  LOG_STATUS="WARN"
  LOG_REASON="$reason"
  echo "Remote DB verify: WARN (${reason})" >&2
  exit "$exit_code"
fi

LOG_STATUS="COMPLETED"
LOG_REASON=""
echo "Remote DB verify: PASS"
exit "$exit_code"
