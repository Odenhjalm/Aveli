#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/db_env.sh"

require_command supabase
require_command psql

if [[ "${DB_TARGET}" != "local" ]]; then
  echo "db_reset_local.sh can only run against local targets." >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/supabase/config.toml" ]]; then
  echo "supabase/config.toml missing. Run 'supabase init' first." >&2
  exit 1
fi

if ! supabase status --output json --workdir "${REPO_ROOT}" >/dev/null 2>&1; then
  echo "[db_reset_local] Starting local Supabase..."
  supabase start --workdir "${REPO_ROOT}"
fi

if resolved=$(resolve_supabase_status); then
  eval "${resolved}"
  export SUPABASE_DB_URL="${SUPABASE_DB_URL:-${DB_URL:-}}"
  export DATABASE_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
fi

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required after local start." >&2
  exit 1
fi

echo "[db_reset_local] Dropping app schema (local-only destructive reset)..."
psql "${SUPABASE_DB_URL}" -v ON_ERROR_STOP=1 -c "drop schema if exists app cascade; create schema app;"
psql "${SUPABASE_DB_URL}" -v ON_ERROR_STOP=1 -c "delete from storage.objects where bucket_id in ('public-media','course-media','lesson-media');"
psql "${SUPABASE_DB_URL}" -v ON_ERROR_STOP=1 -c "delete from storage.buckets where id in ('public-media','course-media','lesson-media');"

echo "[db_reset_local] Applying migrations from scratch..."
"${SCRIPT_DIR}/db_apply.sh"

"${SCRIPT_DIR}/db_verify.sh"
