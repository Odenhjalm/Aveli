#!/usr/bin/env bash
set -euo pipefail

# Starts the local development backend (Postgres + FastAPI) for the Flutter app.
# - Ensures the Postgres container is running
# - Delegates runtime startup to the canonical Baseline V2 bootstrap

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
source "$ROOT_DIR/tools/runtime/python_paths.sh"

PORT="${PORT:-8080}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS:-false}"

echo "==> Ensuring Postgres container is up"
make -C "${ROOT_DIR}" db.up >/dev/null

if [[ "${APPLY_MIGRATIONS}" == "true" ]]; then
  echo "ERROR: APPLY_MIGRATIONS=true is disabled for canonical runtime startup." >&2
  echo "Use the approved replay or migration workflow outside dev_backend.sh." >&2
  exit 1
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

export PORT
echo "==> Launching canonical backend bootstrap on 0.0.0.0:${PORT}"
exec "${BACKEND_DIR}/scripts/start_backend.sh"
