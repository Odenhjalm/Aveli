#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

cd "$ROOT_DIR"
BASELINE_MODE="${BASELINE_MODE:-V2}" "$AVELI_BACKEND_PYTHON" -m backend.bootstrap.baseline_v2
