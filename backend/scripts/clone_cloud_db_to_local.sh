#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"

CMD="${1:-clone}"

REMOTE_DB_URL="${REMOTE_DB_URL:-${SUPABASE_DB_URL:-}}"
LOCAL_DB_URL="${LOCAL_DB_URL:-${DATABASE_URL:-}}"

DUMP_DIR_DEFAULT="${ROOT_DIR}/out/db_dumps"
DUMP_DIR="${DUMP_DIR:-$DUMP_DIR_DEFAULT}"
DUMP_PATH="${DUMP_PATH:-${DUMP_DIR}/supabase_$(date +%Y%m%d-%H%M%S).dump}"

VERIFY_SCHEMAS="${VERIFY_SCHEMAS:-app auth storage}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"

usage() {
  cat <<TXT
Usage: $(basename "$0") [clone|dump|restore|verify]

Env vars:
  REMOTE_DB_URL / SUPABASE_DB_URL   Remote (cloud) Postgres URL (REQUIRED)
  LOCAL_DB_URL / DATABASE_URL       Local Postgres URL (default: uses local_db.sh url)
  DUMP_PATH                         Dump file path (default: ${DUMP_PATH})
  VERIFY_SCHEMAS                    Schemas to compare (default: "${VERIFY_SCHEMAS}")
  SKIP_VERIFY                       Set to 1 to skip verification

Examples:
  SUPABASE_DB_URL='postgresql://...' $(basename "$0") clone
  SUPABASE_DB_URL='postgresql://...' DUMP_PATH=out/db_dumps/prod.dump $(basename "$0") dump
TXT
}

require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $bin" >&2
    exit 1
  fi
}

url_host() {
  python3 - <<'PY' "$1"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
print(parsed.hostname or "")
PY
}

url_target() {
  python3 - <<'PY' "$1"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
host = parsed.hostname or "unknown"
port = f":{parsed.port}" if parsed.port else ""
db = (parsed.path or "").lstrip("/") or "postgres"
print(f"{host}{port}/{db}")
PY
}

is_local_host() {
  local host="$1"
  host="${host,,}"
  case "$host" in
    localhost|127.0.0.1|::1|db|host.docker.internal) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_urls() {
  if [[ -z "$REMOTE_DB_URL" ]]; then
    echo "ERROR: REMOTE_DB_URL/SUPABASE_DB_URL is required." >&2
    exit 1
  fi

  if [[ -z "$LOCAL_DB_URL" ]]; then
    LOCAL_DB_URL="$("$SCRIPT_DIR/local_db.sh" url)"
  fi

  local remote_host
  remote_host="$(url_host "$REMOTE_DB_URL")"
  local local_host
  local_host="$(url_host "$LOCAL_DB_URL")"

  if [[ -z "$remote_host" ]]; then
    echo "ERROR: Could not parse remote DB host." >&2
    exit 1
  fi
  if [[ -z "$local_host" ]]; then
    echo "ERROR: Could not parse local DB host." >&2
    exit 1
  fi

  if is_local_host "$remote_host"; then
    echo "ERROR: Remote DB URL points to a local host (${remote_host}). Refusing." >&2
    exit 1
  fi
  if ! is_local_host "$local_host"; then
    echo "ERROR: Local DB URL does not look local (${local_host}). Refusing to restore." >&2
    echo "Set LOCAL_DB_URL to your local Postgres clone (e.g. 127.0.0.1) before continuing." >&2
    exit 1
  fi

  echo "Remote DB target: $(url_target "$REMOTE_DB_URL")"
  echo "Local  DB target: $(url_target "$LOCAL_DB_URL")"
}

dump_remote() {
  mkdir -p "$DUMP_DIR"
  echo "==> Dumping remote DB to ${DUMP_PATH}"
  pg_dump -F c --no-owner --no-privileges --dbname "$REMOTE_DB_URL" -f "$DUMP_PATH"
  echo "==> Dump complete"
}

restore_local() {
  echo "==> Restoring dump into local DB"
  pg_restore --no-owner --no-privileges --clean --if-exists --dbname "$LOCAL_DB_URL" "$DUMP_PATH"
  echo "==> Restore complete"
}

schemas_sql_list() {
  python3 - <<'PY' "$VERIFY_SCHEMAS"
import sys
schemas = [s.strip() for s in sys.argv[1].split() if s.strip()]
print(", ".join(repr(s) for s in schemas))
PY
}

psql_q() {
  local url="$1"
  local sql="$2"
  PGOPTIONS="-c default_transaction_read_only=on ${PGOPTIONS:-}" psql "$url" -v ON_ERROR_STOP=1 -At -F $'\t' -c "$sql"
}

dump_tables() {
  local url="$1"
  local out="$2"
  local schemas
  schemas="$(schemas_sql_list)"
  psql_q "$url" "select quote_ident(table_schema) || '.' || quote_ident(table_name) from information_schema.tables where table_type = 'BASE TABLE' and table_schema in (${schemas}) order by 1;" >"$out"
}

dump_row_counts() {
  local url="$1"
  local out="$2"
  local tables_file="$3"
  : >"$out"
  while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    local count
    count="$(psql_q "$url" "select count(*) from ${table};")"
    printf "%s\t%s\n" "$table" "$count" >>"$out"
  done <"$tables_file"
}

dump_enums() {
  local url="$1"
  local out="$2"
  local schemas
  schemas="$(schemas_sql_list)"
  psql_q "$url" "
    select n.nspname || '.' || t.typname as enum_name,
           string_agg(e.enumlabel, ',' order by e.enumsortorder) as labels
      from pg_type t
      join pg_namespace n on n.oid = t.typnamespace
      join pg_enum e on e.enumtypid = t.oid
     where n.nspname in (${schemas})
     group by 1
     order by 1;
  " >"$out"
}

dump_constraints() {
  local url="$1"
  local out="$2"
  local schemas
  schemas="$(schemas_sql_list)"
  psql_q "$url" "
    select n.nspname || '.' || c.relname as table_name,
           con.conname as constraint_name,
           con.contype as constraint_type,
           pg_get_constraintdef(con.oid, true) as definition
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = con.connamespace
     where n.nspname in (${schemas})
     order by 1, 2;
  " >"$out"
}

verify_clone() {
  if [[ "$SKIP_VERIFY" == "1" ]]; then
    echo "==> SKIP_VERIFY=1 set; skipping verification"
    return 0
  fi

  require_bin diff

  diff_or_fail() {
    local left="$1"
    local right="$2"
    local label="$3"
    if ! diff -u "$left" "$right"; then
      echo "ERROR: Verification failed (${label})." >&2
      exit 1
    fi
  }

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  echo "==> Verifying clone (schemas: ${VERIFY_SCHEMAS})"

  local remote_tables="$tmp_dir/remote_tables.txt"
  local local_tables="$tmp_dir/local_tables.txt"
  dump_tables "$REMOTE_DB_URL" "$remote_tables"
  dump_tables "$LOCAL_DB_URL" "$local_tables"
  diff_or_fail "$remote_tables" "$local_tables" "table list mismatch"

  local remote_counts="$tmp_dir/remote_counts.tsv"
  local local_counts="$tmp_dir/local_counts.tsv"
  dump_row_counts "$REMOTE_DB_URL" "$remote_counts" "$remote_tables"
  dump_row_counts "$LOCAL_DB_URL" "$local_counts" "$local_tables"
  diff_or_fail "$remote_counts" "$local_counts" "row count mismatch"

  local remote_enums="$tmp_dir/remote_enums.tsv"
  local local_enums="$tmp_dir/local_enums.tsv"
  dump_enums "$REMOTE_DB_URL" "$remote_enums"
  dump_enums "$LOCAL_DB_URL" "$local_enums"
  diff_or_fail "$remote_enums" "$local_enums" "enum mismatch"

  local remote_constraints="$tmp_dir/remote_constraints.tsv"
  local local_constraints="$tmp_dir/local_constraints.tsv"
  dump_constraints "$REMOTE_DB_URL" "$remote_constraints"
  dump_constraints "$LOCAL_DB_URL" "$local_constraints"
  diff_or_fail "$remote_constraints" "$local_constraints" "constraint mismatch"

  echo "==> Verification passed: tables, row counts, enums, and constraints match"
}

case "$CMD" in
  clone)
    require_bin python3
    require_bin pg_dump
    require_bin pg_restore
    require_bin psql
    ensure_urls
    "$SCRIPT_DIR/local_db.sh" up >/dev/null
    dump_remote
    restore_local
    verify_clone
    ;;
  dump)
    require_bin python3
    require_bin pg_dump
    ensure_urls
    dump_remote
    ;;
  restore)
    require_bin python3
    require_bin pg_restore
    require_bin psql
    ensure_urls
    "$SCRIPT_DIR/local_db.sh" up >/dev/null
    restore_local
    ;;
  verify)
    require_bin python3
    require_bin psql
    ensure_urls
    verify_clone
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: unknown command: $CMD" >&2
    usage >&2
    exit 2
    ;;
esac
