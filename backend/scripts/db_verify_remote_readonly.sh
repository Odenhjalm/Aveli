#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_PATH="${REPORT_PATH:-${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md}"
MASTER_ENV_FILE="/home/oden/Aveli/backend/.env"
LOG_PATH="/tmp/aveli_remote_db_verify_$(date +%Y%m%d-%H%M%S).json"

EXIT_PASS=0
EXIT_SKIP=10
EXIT_WARN=20
EXIT_FAIL=2

SHOULD_LOG=false
LOG_STATUS=""
LOG_REASON=""

normalize_env() {
  local raw="$1"
  raw="${raw,,}"
  case "$raw" in
    prod|production|live) echo "production" ;;
    *) echo "development" ;;
  esac
}

APP_ENV_VALUE="${APP_ENV:-${ENV:-${ENVIRONMENT:-development}}}"
ENV_MODE="$(normalize_env "$APP_ENV_VALUE")"

emit_result() {
  local status="$1"
  local reason="${2:-}"
  local summary="${3:-}"
  local report="${4:-}"

  echo "REMOTE_DB_VERIFY_STATUS=${status}"
  if [[ -n "$reason" ]]; then
    echo "REMOTE_DB_VERIFY_REASON=${reason}"
  fi
  if [[ -n "$summary" ]]; then
    echo "REMOTE_DB_VERIFY_SUMMARY=${summary}"
  fi
  if [[ -n "$report" ]]; then
    echo "REMOTE_DB_VERIFY_REPORT=${report}"
  fi
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
PY
}

on_exit() {
  local exit_code=$?
  if [[ "$SHOULD_LOG" != "true" ]]; then
    return
  fi
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
  if [[ -f "$REPORT_PATH" ]]; then
    cat >>"$REPORT_PATH"
  fi
}

skip_verify() {
  local reason="$1"
  emit_result "SKIP" "$reason"
  exit "$EXIT_SKIP"
}

load_master_env() {
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

summarize_list() {
  local input="$1"
  local total
  local names
  total=$(printf '%s\n' "$input" | sed '/^$/d' | wc -l | tr -d ' ')
  names=$(printf '%s\n' "$input" | sed '/^$/d' | head -n 3 | paste -sd "," -)
  if [[ "$total" -gt 3 ]]; then
    echo "${names} (+$((total - 3)) more)"
  else
    echo "$names"
  fi
}

if [[ ! -f "$MASTER_ENV_FILE" ]]; then
  skip_verify "master env missing at ${MASTER_ENV_FILE}"
fi

load_master_env

DB_URL="${SUPABASE_DB_URL:-}"
if [[ -z "$DB_URL" ]]; then
  skip_verify "missing SUPABASE_DB_URL (in master env: ${MASTER_ENV_FILE})"
fi

allowlist_candidates=()
if [[ -n "${SUPABASE_ALLOWLIST_FILE:-}" ]]; then
  allowlist_candidates+=("$SUPABASE_ALLOWLIST_FILE")
fi
if [[ -n "${SUPABASE_ALLOWLIST_PATH:-}" ]]; then
  allowlist_candidates+=("$SUPABASE_ALLOWLIST_PATH")
fi
if [[ -n "${SUPABASE_DB_ALLOWLIST_FILE:-}" ]]; then
  allowlist_candidates+=("$SUPABASE_DB_ALLOWLIST_FILE")
fi
if [[ -n "${SUPABASE_DB_ALLOWLIST_PATH:-}" ]]; then
  allowlist_candidates+=("$SUPABASE_DB_ALLOWLIST_PATH")
fi
if [[ "${#allowlist_candidates[@]}" -eq 0 ]]; then
  for candidate in "$ROOT_DIR/SUPABASE_ALLOWLIST.txt" "$ROOT_DIR/SUPABASE_DB_ALLOWLIST.txt"; do
    if [[ -f "$candidate" ]]; then
      allowlist_candidates+=("$candidate")
    fi
  done
fi
if [[ "${#allowlist_candidates[@]}" -gt 0 ]]; then
  for candidate in "${allowlist_candidates[@]}"; do
    if [[ ! -f "$candidate" ]]; then
      skip_verify "missing allowlist file: ${candidate}"
    fi
  done
fi

if ! command -v psql >/dev/null 2>&1; then
  skip_verify "psql not available"
fi

SHOULD_LOG=true
export MASTER_ENV_FILE

READONLY_PGOPTIONS="-c default_transaction_read_only=on"
run_sql() {
  local output
  if ! output=$(PGOPTIONS="$READONLY_PGOPTIONS" psql "$DB_URL" -tA -F $'\t' -v ON_ERROR_STOP=1 -c "$1"); then
    LOG_REASON="psql failed running query"
    return 1
  fi
  printf '%s' "$output"
}

require_sql() {
  local __var="$1"
  local __query="$2"
  local __output
  if ! __output=$(run_sql "$__query"); then
    return 1
  fi
  printf -v "$__var" '%s' "$__output"
  return 0
}

fail_with_summary() {
  local summary="$1"
  local result_status="$2"
  local exit_code="$3"

  LOG_STATUS="FAILED"
  LOG_REASON="$summary"

  append_report <<TXT

## Remote DB Verify (read-only)
Status: ${result_status}
Reason: ${summary}
TXT

  emit_result "$result_status" "" "$summary" "$LOG_PATH"
  exit "$exit_code"
}

if ! require_sql app_tables_raw "select table_name from information_schema.tables where table_schema = 'app' and table_type = 'BASE TABLE' order by table_name;"; then
  fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi
app_tables_count=$(echo "$app_tables_raw" | sed '/^$/d' | wc -l | tr -d ' ')

if ! require_sql rls_disabled_raw "select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and c.relkind = 'r' and c.relrowsecurity = false order by c.relname;"; then
  fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi
rls_disabled=$(echo "$rls_disabled_raw" | sed '/^$/d')

if ! require_sql no_policy_raw "select t.table_name from information_schema.tables t left join pg_policies p on p.schemaname = 'app' and p.tablename = t.table_name where t.table_schema = 'app' and t.table_type = 'BASE TABLE' group by t.table_name having count(p.policyname) = 0 order by t.table_name;"; then
  fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi
no_policy=$(echo "$no_policy_raw" | sed '/^$/d')

if ! require_sql storage_exists "select to_regclass('storage.buckets') is not null;"; then
  fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi
if [[ "$storage_exists" == "t" ]]; then
  if ! require_sql storage_buckets "select id || ' (public=' || public || ')' from storage.buckets order by id;"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
  if ! require_sql storage_policies "select policyname || ' [' || cmd || ']' from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname, cmd;"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
  if ! require_sql storage_rls "select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'storage' and c.relname = 'objects';"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
  if ! require_sql public_media_public "select public from storage.buckets where id = 'public-media';"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
  if ! require_sql course_media_public "select public from storage.buckets where id = 'course-media';"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
  if ! require_sql lesson_media_public "select public from storage.buckets where id = 'lesson-media';"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
else
  storage_buckets=""
  storage_policies=""
  storage_rls=""
  public_media_public=""
  course_media_public=""
  lesson_media_public=""
fi

if ! require_sql migrations_exists "select to_regclass('supabase_migrations.schema_migrations') is not null;"; then
  fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi
if [[ "$migrations_exists" == "t" ]]; then
  if ! require_sql db_migrations "select name from supabase_migrations.schema_migrations where name is not null order by name;"; then
    fail_with_summary "psql failed running query" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
  fi
else
  db_migrations=""
fi

if ! repo_migrations=$(python3 - <<'PY' "$ROOT_DIR/supabase/migrations"
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
); then
  fail_with_summary "failed to read repo migrations" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "FAIL"; else echo "WARN"; fi)" "$(if [[ "$ENV_MODE" == "production" ]]; then echo "$EXIT_FAIL"; else echo "$EXIT_WARN"; fi)"
fi

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

issues=()
if [[ -n "$rls_disabled" ]]; then
  issues+=("RLS disabled: $(summarize_list "$rls_disabled")")
fi
if [[ -n "$no_policy" ]]; then
  issues+=("No policies: $(summarize_list "$no_policy")")
fi
if [[ -n "$storage_issue" ]]; then
  issues+=("Storage: $storage_issue")
fi
if [[ -n "$missing_in_db" ]]; then
  issues+=("Missing migrations: $(summarize_list "$missing_in_db")")
fi
if [[ -n "$extra_in_db" ]]; then
  issues+=("Extra migrations: $(summarize_list "$extra_in_db")")
fi

summary=""
if [[ "${#issues[@]}" -gt 0 ]]; then
  summary=$(printf '%s\n' "${issues[@]}" | head -n 3 | paste -sd ";" -)
fi

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

result_status="PASS"
exit_code="$EXIT_PASS"
if [[ -n "$summary" ]]; then
  if [[ "$ENV_MODE" == "production" ]]; then
    result_status="FAIL"
    exit_code="$EXIT_FAIL"
  else
    result_status="WARN"
    exit_code="$EXIT_WARN"
  fi
  LOG_STATUS="FAILED"
  LOG_REASON="remote DB checks failed"
else
  LOG_STATUS="COMPLETED"
  LOG_REASON=""
fi

append_report <<TXT

## Remote DB Verify (read-only)
Status: ${result_status}
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

emit_result "$result_status" "" "$summary" "$LOG_PATH"
exit "$exit_code"
