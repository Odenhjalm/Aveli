#!/usr/bin/env bash
set -euo pipefail

ENSURE_DB_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ENSURE_DB_SCRIPT_DIR="$(cd "$(dirname "$ENSURE_DB_SCRIPT_PATH")" && pwd)"

# shellcheck source=/dev/null
source "$ENSURE_DB_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host
require_postgres_cli

echo "==> Ensuring native local Postgres is reachable..."
wait_for_local_postgres postgres
ensure_local_database_exists

echo "==> Local database ready: $(local_db_target)"
