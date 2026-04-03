#!/usr/bin/env bash
set -euo pipefail

WAIT_FOR_DB_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
WAIT_FOR_DB_SCRIPT_DIR="$(cd "$(dirname "$WAIT_FOR_DB_SCRIPT_PATH")" && pwd)"

# shellcheck source=/dev/null
source "$WAIT_FOR_DB_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host

echo "==> Waiting for Postgres readiness..."
until docker compose exec -T db pg_isready -U postgres -d "${DATABASE_NAME}" >/dev/null 2>&1; do
  sleep 1
done
