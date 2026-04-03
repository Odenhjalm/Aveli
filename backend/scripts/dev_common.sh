#!/usr/bin/env bash
set -euo pipefail

DEV_COMMON_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DEV_COMMON_DIR="$(cd "$(dirname "$DEV_COMMON_PATH")" && pwd)"
BACKEND_DIR="$(cd "$DEV_COMMON_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
LOCK_FILE="$BACKEND_DIR/supabase/baseline_slots.lock.json"
AUTH_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_auth_substrate.sql"

source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

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

compose_psql() {
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d "${DATABASE_NAME}" "$@"
}
