#!/usr/bin/env bash
set -euo pipefail

WAIT_FOR_DB_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
WAIT_FOR_DB_SCRIPT_DIR="$(cd "$(dirname "$WAIT_FOR_DB_SCRIPT_PATH")" && pwd)"

# shellcheck source=/dev/null
source "$WAIT_FOR_DB_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host
require_postgres_cli

echo "==> Waiting for native Postgres readiness on ${DATABASE_HOST}:${DATABASE_PORT}..."
wait_for_local_postgres postgres
