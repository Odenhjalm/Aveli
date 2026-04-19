#!/usr/bin/env bash
set -euo pipefail

DEV_COMMON_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DEV_COMMON_DIR="$(cd "$(dirname "$DEV_COMMON_PATH")" && pwd)"
BACKEND_DIR="$(cd "$DEV_COMMON_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
LOCK_FILE="$BACKEND_DIR/supabase/baseline_v2_slots.lock.json"
AUTH_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_auth_substrate.sql"
STORAGE_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_storage_substrate.sql"

source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

resolve_postgres_cli_path() {
  local tool="$1"
  local env_key=""
  local configured_path=""
  local candidate=""

  case "$tool" in
    psql) env_key="AVELI_PSQL_PATH" ;;
    pg_isready) env_key="AVELI_PG_ISREADY_PATH" ;;
    *)
      echo "ERROR: unsupported PostgreSQL CLI tool: ${tool}" >&2
      exit 1
      ;;
  esac

  configured_path="${!env_key:-}"
  if [[ -n "$configured_path" ]]; then
    printf '%s\n' "$configured_path"
    return 0
  fi

  if candidate="$(command -v "$tool" 2>/dev/null)"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    "/mnt/c/Program Files/PostgreSQL"/*"/bin/${tool}.exe" \
    "/c/Program Files/PostgreSQL"/*"/bin/${tool}.exe"
  do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

POSTGRES_PSQL_BIN="${POSTGRES_PSQL_BIN:-$(resolve_postgres_cli_path psql 2>/dev/null || true)}"
POSTGRES_PG_ISREADY_BIN="${POSTGRES_PG_ISREADY_BIN:-$(resolve_postgres_cli_path pg_isready 2>/dev/null || true)}"

postgres_cli_uses_windows_exe() {
  local path="$1"
  [[ "${path,,}" == *.exe ]]
}

postgres_connection_uri() {
  local database="$1"
  local connection_target=""

  connection_target="$(
    "$AVELI_BACKEND_PYTHON" - <<'PY' \
      "$DATABASE_USER" \
      "$DATABASE_PASSWORD" \
      "$DATABASE_HOST" \
      "$DATABASE_PORT" \
      "$database" | tr -d '\r'
import sys
from urllib.parse import quote

user, password, host, port, database = sys.argv[1:]
if ":" in host and not host.startswith("["):
    host = f"[{host}]"

print(
    "postgresql://{user}:{password}@{host}:{port}/{database}".format(
        user=quote(user, safe=""),
        password=quote(password, safe=""),
        host=host,
        port=port,
        database=quote(database, safe=""),
    )
)
PY
  )"

  printf '%s\n' "$connection_target"
}

postgres_sql_literal() {
  local value="$1"

  "$AVELI_BACKEND_PYTHON" - <<'PY' "$value" | tr -d '\r'
import sys

value = sys.argv[1]
print("'" + value.replace("'", "''") + "'")
PY
}

postgres_sql_identifier() {
  local value="$1"

  "$AVELI_BACKEND_PYTHON" - <<'PY' "$value" | tr -d '\r'
import sys

value = sys.argv[1]
print('"' + value.replace('"', '""') + '"')
PY
}

load_backend_env() {
  if [[ -f "$ROOT_DIR/ops/env_load.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/ops/env_load.sh"
  fi
}

require_local_db_config() {
  local missing=()
  local key
  for key in DATABASE_HOST DATABASE_PORT DATABASE_NAME DATABASE_USER DATABASE_PASSWORD; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("$key")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing database settings: ${missing[*]}" >&2
    echo "Tip: copy backend/.env.local.example to backend/.env.local and set DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USER, and DATABASE_PASSWORD." >&2
    exit 1
  fi
}

require_local_db_host() {
  local db_host="${DATABASE_HOST,,}"
  case "$db_host" in
    localhost|127.0.0.1|::1) ;;
    *)
      echo "ERROR: local dev scripts require DATABASE_HOST=localhost/127.0.0.1/::1, got ${DATABASE_HOST}." >&2
      exit 1
      ;;
  esac
}

local_db_target() {
  printf '%s:%s/%s\n' "${DATABASE_HOST}" "${DATABASE_PORT}" "${DATABASE_NAME}"
}

require_postgres_cli() {
  local missing=()
  [[ -n "${POSTGRES_PSQL_BIN:-}" ]] || missing+=("psql")
  [[ -n "${POSTGRES_PG_ISREADY_BIN:-}" ]] || missing+=("pg_isready")

  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing PostgreSQL CLI tools: ${missing[*]}" >&2
    echo "Install the native PostgreSQL client tools and retry." >&2
    exit 1
  fi
}

db_psql() {
  local database="${DATABASE_NAME}"
  local connection_target=""
  if [[ $# -ge 2 && "$1" == "--database" ]]; then
    database="$2"
    shift 2
  fi

  if postgres_cli_uses_windows_exe "$POSTGRES_PSQL_BIN"; then
    connection_target="$(postgres_connection_uri "$database")"
    "$POSTGRES_PSQL_BIN" \
      -v ON_ERROR_STOP=1 \
      "$@" \
      "$connection_target"
    return 0
  fi

  PGPASSWORD="$DATABASE_PASSWORD" \
    "$POSTGRES_PSQL_BIN" \
      -v ON_ERROR_STOP=1 \
      -h "$DATABASE_HOST" \
      -p "$DATABASE_PORT" \
      -U "$DATABASE_USER" \
      -d "$database" \
      "$@"
}

db_pg_isready() {
  local database="${DATABASE_NAME}"
  local connection_target=""
  if [[ $# -ge 2 && "$1" == "--database" ]]; then
    database="$2"
    shift 2
  fi

  if postgres_cli_uses_windows_exe "$POSTGRES_PG_ISREADY_BIN"; then
    connection_target="$(postgres_connection_uri "$database")"
    "$POSTGRES_PG_ISREADY_BIN" \
      -d "$connection_target" \
      "$@"
    return 0
  fi

  PGPASSWORD="$DATABASE_PASSWORD" \
    "$POSTGRES_PG_ISREADY_BIN" \
      -h "$DATABASE_HOST" \
      -p "$DATABASE_PORT" \
      -U "$DATABASE_USER" \
      -d "$database" \
      "$@"
}

wait_for_local_postgres() {
  local database="${1:-postgres}"
  local wait_seconds="${LOCAL_DB_WAIT_SECONDS:-60}"
  local attempt

  for attempt in $(seq 1 "$wait_seconds"); do
    if db_pg_isready --database "$database" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "ERROR: local Postgres did not become ready within ${wait_seconds}s (${DATABASE_HOST}:${DATABASE_PORT}/${database})." >&2
  exit 1
}

target_database_exists() {
  local exists
  local db_name_sql=""
  db_name_sql="$(postgres_sql_literal "${DATABASE_NAME}")"
  exists="$(
    db_psql --database postgres -tA \
      -c "SELECT 1 FROM pg_database WHERE datname = ${db_name_sql};" | tr -d '[:space:]'
  )"
  [[ "$exists" == "1" ]]
}

ensure_local_database_exists() {
  local db_name_identifier=""

  if target_database_exists; then
    return 0
  fi

  db_name_identifier="$(postgres_sql_identifier "${DATABASE_NAME}")"
  echo "==> Creating native local database $(local_db_target)..."
  db_psql --database postgres -c "CREATE DATABASE ${db_name_identifier};"
}
