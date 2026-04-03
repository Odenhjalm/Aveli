#!/usr/bin/env bash
set -euo pipefail
START_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
START_SCRIPT_DIR="$(cd "$(dirname "$START_SCRIPT_PATH")" && pwd)"
BACKEND_DIR="$(cd "$START_SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"
source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"
PORT="${PORT:-8080}"

truthy() {
  local raw="${1:-}"
  raw="${raw,,}"
  [[ "$raw" == "1" || "$raw" == "true" || "$raw" == "yes" || "$raw" == "y" || "$raw" == "on" ]]
}

is_prod_env() {
  local raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
  local lowered="${raw,,}"
  [[ "$lowered" == "prod" || "$lowered" == "production" || "$lowered" == "live" ]]
}

db_url_value() {
  "$AVELI_BACKEND_PYTHON" - <<'PY' \
    "${DATABASE_USER:-}" \
    "${DATABASE_PASSWORD:-}" \
    "${DATABASE_HOST:-}" \
    "${DATABASE_PORT:-}" \
    "${DATABASE_NAME:-}"
from urllib.parse import quote
import sys

user, password, host, port, name = sys.argv[1:]
host = host.strip()
if ":" in host and not host.startswith("["):
    host = f"[{host}]"
print(
    f"postgresql://{quote(user, safe='')}:{quote(password, safe='')}"
    f"@{host}:{port}/{quote(name, safe='')}"
)
PY
}

db_target() {
  printf '%s:%s/%s\n' "${DATABASE_HOST}" "${DATABASE_PORT}" "${DATABASE_NAME}"
}

db_host() {
  printf '%s\n' "${DATABASE_HOST}"
}

is_local_host() {
  local host="$1"
  host="${host,,}"
  case "$host" in
    localhost|127.0.0.1|::1|db|host.docker.internal) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -z "${STRIPE_KEYSET:-}" && -z "${APP_ENV_MODE:-}" && -n "${BACKEND_ENV_OVERLAY_FILE:-}" ]]; then
  app_env_raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
  app_env_lower="${app_env_raw,,}"
  if [[ "$app_env_lower" != "prod" && "$app_env_lower" != "production" && "$app_env_lower" != "live" ]]; then
    export APP_ENV_MODE="test"
  fi
fi

if [[ -f "$OPS_DIR/env_load.sh" ]]; then
  # shellcheck source=/dev/null
  source "$OPS_DIR/env_load.sh"
fi

missing_db_fields=()
for key in DATABASE_HOST DATABASE_PORT DATABASE_NAME DATABASE_USER DATABASE_PASSWORD; do
  if [[ -z "${!key:-}" ]]; then
    missing_db_fields+=("$key")
  fi
done

if is_prod_env && ! truthy "${AVELI_ALLOW_PROD_ENV_LOCAL:-}"; then
  echo "ERROR: APP_ENV indicates production; refusing to start local backend on 127.0.0.1." >&2
  echo "Use backend/.env.local (APP_ENV=local) for local development." >&2
  echo "If you really need this, set AVELI_ALLOW_PROD_ENV_LOCAL=1 to override." >&2
  exit 1
fi

if (( ${#missing_db_fields[@]} > 0 )); then
  echo "ERROR: missing database settings: ${missing_db_fields[*]}" >&2
  echo "Tip: copy backend/.env.local.example to backend/.env.local and set DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USER, and DATABASE_PASSWORD." >&2
  exit 1
fi

db_url="$(db_url_value)"
host="$(db_host)"
echo "==> DB target: $(db_target "$db_url")"
if ! is_local_host "$host" && ! truthy "${AVELI_ALLOW_REMOTE_DB:-}"; then
  echo "ERROR: DB host is not local (${host}); refusing to start." >&2
  echo "Set DATABASE_HOST to your local Postgres (localhost/127.0.0.1/db) or set AVELI_ALLOW_REMOTE_DB=1 to override." >&2
  exit 1
fi

export DATABASE_URL="$db_url"

cd "$BACKEND_DIR"

echo "[Backend] Starting Uvicorn on port ${PORT}..."
exec "$AVELI_BACKEND_PYTHON" -m uvicorn app.main:app --reload --host 127.0.0.1 --port "${PORT}"
