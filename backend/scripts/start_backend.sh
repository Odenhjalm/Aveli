#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"
PORT="${PORT:-8080}"

if [[ -f "$OPS_DIR/env_load.sh" ]]; then
  # shellcheck source=/dev/null
  source "$OPS_DIR/env_load.sh"
fi

cd "$BACKEND_DIR"
if command -v poetry >/dev/null 2>&1; then
  source "$(poetry env info --path)"/bin/activate
fi

echo "[Backend] Starting Uvicorn on port ${PORT}..."
uvicorn app.main:app --reload --host 127.0.0.1 --port "${PORT}"
