#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${BACKEND_ENV_FILE:-"$BACKEND_DIR/.env"}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[env] ERROR: env file not found at $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a
echo "[env] loaded BACKEND_ENV_FILE=$ENV_FILE"

PORT="${PORT:-8080}"

cd "$BACKEND_DIR"
if command -v poetry >/dev/null 2>&1; then
  source "$(poetry env info --path)"/bin/activate
fi

echo "[Backend] Starting Uvicorn on port ${PORT}..."
uvicorn app.main:app --reload --host 127.0.0.1 --port "${PORT}"
