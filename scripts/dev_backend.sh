#!/usr/bin/env bash
set -euo pipefail

# Starts the local development backend (Postgres + FastAPI) for the Flutter app.
# - Ensures the Postgres container is running
# - Applies migrations/seed data if requested
# - Runs uvicorn with auto-reload through Poetry

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"

PORT="${PORT:-8000}"
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

if [[ ! -f ".venv/bin/activate" ]]; then
  echo "==> Installing backend dependencies via Poetry"
  poetry install >/dev/null
fi

echo "==> Launching FastAPI backend on ${HOST}:${PORT}"
exec poetry run uvicorn app.main:app --host "${HOST}" --port "${PORT}" --reload
