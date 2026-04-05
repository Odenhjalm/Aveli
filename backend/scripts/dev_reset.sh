#!/usr/bin/env bash
set -euo pipefail

DEV_RESET_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DEV_RESET_SCRIPT_DIR="$(cd "$(dirname "$DEV_RESET_SCRIPT_PATH")" && pwd)"

echo "==> Rebuilding native local baseline state..."

"$DEV_RESET_SCRIPT_DIR/ensure_db.sh"
"$DEV_RESET_SCRIPT_DIR/replay_baseline.sh"
exec "$DEV_RESET_SCRIPT_DIR/start_backend.sh"
