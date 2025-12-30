#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/db_env.sh"

require_command psql

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "Migrations directory not found at ${MIGRATIONS_DIR}" >&2
  exit 1
fi

if [[ "${DB_TARGET}" == "local" ]]; then
  if [[ -z "${DB_URL:-}" ]]; then
    echo "DB_URL is required for local apply." >&2
    exit 1
  fi
  export SUPABASE_DB_URL="${SUPABASE_DB_URL:-${DB_URL}}"
  echo "[db_apply] Local apply using backend/scripts/apply_supabase_migrations.sh"
  "${REPO_ROOT}/backend/scripts/apply_supabase_migrations.sh"
  storage_policy_file="${MIGRATIONS_DIR}/021_storage_policies.sql"
  if [[ -f "${storage_policy_file}" ]]; then
    if [[ -z "${SUPABASE_STORAGE_ADMIN_DB_URL:-}" ]]; then
      derived=$(python3 - "${DB_URL}" <<'PY'
from urllib.parse import urlparse, urlunparse
import sys

url = sys.argv[1]
parsed = urlparse(url)
if not parsed.password:
    sys.exit(1)

netloc = f"supabase_storage_admin:{parsed.password}@{parsed.hostname}"
if parsed.port:
    netloc = f"{netloc}:{parsed.port}"
new_url = parsed._replace(netloc=netloc).geturl()
print(new_url)
PY
      ) || true
      if [[ -n "${derived}" ]]; then
        SUPABASE_STORAGE_ADMIN_DB_URL="${derived}"
      fi
    fi
    if [[ -n "${SUPABASE_STORAGE_ADMIN_DB_URL:-}" ]]; then
      echo "[db_apply] Applying storage policies with storage admin role."
      psql "${SUPABASE_STORAGE_ADMIN_DB_URL}" -v ON_ERROR_STOP=1 -f "${storage_policy_file}"
    else
      echo "[db_apply] SUPABASE_STORAGE_ADMIN_DB_URL not set; storage policy apply skipped." >&2
    fi
  fi
  exit 0
fi

# Remote mode (repair-forward only)
require_remote_mutation_guards

if [[ -z "${DB_URL:-}" ]]; then
  echo "DB_URL is required for remote apply." >&2
  exit 1
fi

REMOTE_SCOPE="${DB_REMOTE_APPLY_SCOPE:-repair-only}"
MIGRATION_FILES=()
while IFS= read -r file; do
  base="$(basename "${file}")"
  if [[ "${REMOTE_SCOPE}" == "repair-only" ]]; then
    if [[ "${base}" == repair_*.sql || "${base}" == *_repair_*.sql ]]; then
      MIGRATION_FILES+=("${file}")
    fi
  else
    MIGRATION_FILES+=("${file}")
  fi
done < <(find "${MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.sql' | sort)

if [[ ${#MIGRATION_FILES[@]} -eq 0 ]]; then
  echo "[db_apply] No migrations matched scope '${REMOTE_SCOPE}'." >&2
  exit 0
fi

psql "${DB_URL}" -v ON_ERROR_STOP=1 -q -t -A <<'SQL'
create schema if not exists app;
create table if not exists app.schema_migrations (
  filename text primary key,
  applied_at timestamptz not null default now()
);
SQL

applied_count=$(psql "${DB_URL}" -q -t -A -c "select count(*) from app.schema_migrations;")
if [[ "${applied_count:-0}" == "0" ]]; then
  if [[ "${DB_REMOTE_BOOTSTRAP:-}" == "1" ]]; then
    echo "[db_apply] Bootstrapping migration log for remote without applying migrations."
    for file in "${MIGRATION_FILES[@]}"; do
      base="$(basename "${file}")"
      psql "${DB_URL}" -q -t -A -c "insert into app.schema_migrations (filename) values ('${base}') on conflict do nothing;" >/dev/null
    done
    exit 0
  fi
  echo "[db_apply] app.schema_migrations is empty. Refusing to apply on remote." >&2
  echo "[db_apply] Set DB_REMOTE_BOOTSTRAP=1 to mark existing migrations as applied." >&2
  exit 1
fi

for file in "${MIGRATION_FILES[@]}"; do
  base="$(basename "${file}")"
  already=$(psql "${DB_URL}" -q -t -A -c "select 1 from app.schema_migrations where filename='${base}';")
  if [[ -n "${already}" ]]; then
    echo "[db_apply] Skipping already applied ${base}"
    continue
  fi
  echo "[db_apply] Applying ${base}"
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -f "${file}"
  psql "${DB_URL}" -q -t -A -c "insert into app.schema_migrations (filename) values ('${base}') on conflict do nothing;" >/dev/null
  echo "[db_apply] Applied ${base}"
done
