#!/usr/bin/env bash
set -euo pipefail

ENSURE_DB_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ENSURE_DB_SCRIPT_DIR="$(cd "$(dirname "$ENSURE_DB_SCRIPT_PATH")" && pwd)"

# shellcheck source=/dev/null
source "$ENSURE_DB_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host

echo "==> Ensuring local Postgres container is running..."
docker compose up -d db >/dev/null

"$ENSURE_DB_SCRIPT_DIR/wait_for_db.sh"
