#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

cd "$ROOT_DIR"

requested_mode="${BASELINE_MODE:-V2}"
requested_mode="${requested_mode^^}"
if [[ "$requested_mode" != "V2" ]]; then
  echo "ERROR: Baseline replay is V2-only; BASELINE_MODE=${requested_mode} is not allowed." >&2
  exit 1
fi

export BASELINE_MODE="V2"
"$AVELI_BACKEND_PYTHON" -c "from backend.bootstrap.baseline_v2 import verify_v2_lock; lock = verify_v2_lock(); print('BASELINE_V2_LOCK_OK=1'); print(f'BASELINE_V2_SLOT_COUNT={len(lock[\"slots\"])}')"
exec "$AVELI_BACKEND_PYTHON" -m backend.bootstrap.baseline_v2
