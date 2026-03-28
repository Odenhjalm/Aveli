#!/usr/bin/env bash
set -euo pipefail

# Starts the local development backend (Postgres + FastAPI) for the Flutter app.
# - Ensures the Postgres container is running
# - Applies migrations/seed data if requested
# - Runs uvicorn with auto-reload through Poetry

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
source "$ROOT_DIR/tools/runtime/python_paths.sh"

PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS:-false}"

echo "==> Ensuring Postgres container is up"
make -C "${ROOT_DIR}" db.up >/dev/null

if [[ "${APPLY_MIGRATIONS}" == "true" ]]; then
  echo "==> Applying migrations and seed data"
  make -C "${ROOT_DIR}" db.migrate
  make -C "${ROOT_DIR}" db.seed
fi

if ! command -v poetry >/dev/null 2>&1; then
  echo "Error: poetry is required but not installed. Install it via 'pip install poetry'." >&2
  exit 1
fi

cd "${BACKEND_DIR}"

if [[ ! -x ".venv/bin/python" ]]; then
  echo "==> Installing backend dependencies via Poetry"
  poetry install >/dev/null
fi

aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

echo "==> Launching FastAPI backend on ${HOST}:${PORT}"
exec "$AVELI_BACKEND_PYTHON" -m uvicorn app.main:app --host "${HOST}" --port "${PORT}" --reload
