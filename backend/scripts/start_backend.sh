#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"
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
  if [[ -n "${DATABASE_URL:-}" ]]; then
    echo "${DATABASE_URL}"
    return 0
  fi
  if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
    echo "${SUPABASE_DB_URL}"
    return 0
  fi
  echo ""
}

db_target() {
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

db_host() {
  python3 - <<'PY' "$1"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
print(parsed.hostname or "")
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

if is_prod_env && ! truthy "${AVELI_ALLOW_PROD_ENV_LOCAL:-}"; then
  echo "ERROR: APP_ENV indicates production; refusing to start local backend on 127.0.0.1." >&2
  echo "Use backend/.env.local (APP_ENV=local) for local development." >&2
  echo "If you really need this, set AVELI_ALLOW_PROD_ENV_LOCAL=1 to override." >&2
  exit 1
fi

db_url="$(db_url_value)"
if [[ -z "$db_url" ]]; then
  echo "ERROR: DATABASE_URL or SUPABASE_DB_URL is required." >&2
  echo "Tip: copy backend/.env.local.example to backend/.env.local and edit DATABASE_URL." >&2
  exit 1
fi

host="$(db_host "$db_url")"
echo "==> DB target: $(db_target "$db_url")"
if ! is_local_host "$host" && ! truthy "${AVELI_ALLOW_REMOTE_DB:-}"; then
  echo "ERROR: DB host is not local (${host}); refusing to start." >&2
  echo "Set DATABASE_URL to your local Postgres (localhost/127.0.0.1) or set AVELI_ALLOW_REMOTE_DB=1 to override." >&2
  exit 1
fi

cd "$BACKEND_DIR"
if command -v poetry >/dev/null 2>&1; then
  source "$(poetry env info --path)"/bin/activate
fi

echo "[Backend] Starting Uvicorn on port ${PORT}..."
uvicorn app.main:app --reload --host 127.0.0.1 --port "${PORT}"
