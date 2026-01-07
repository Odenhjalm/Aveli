#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"
BACKEND_DIR="$ROOT_DIR/backend"
REPORT_PATH="$ROOT_DIR/docs/verify/LAUNCH_READINESS_REPORT.md"

# Load env first (prints env paths).
# shellcheck source=/dev/null
source "$OPS_DIR/env_load.sh"

# Validate env; fail fast.
if ! bash "$OPS_DIR/env_validate.sh"; then
  echo "verify_all: FAIL (env validation)" >&2
  exit 1
fi

# Contract check; fail fast.
if ! python "$BACKEND_DIR/scripts/env_contract_check.py"; then
  echo "verify_all: FAIL (env contract check)" >&2
  exit 1
fi

# Additional checks/tests can be inserted here as needed.

if [[ "${VERIFY_WRITE_REPORT:-0}" == "1" ]]; then
  mkdir -p "$(dirname "$REPORT_PATH")"
  {
    echo "## Verification Run"
    echo "- Mode: ${APP_ENV:-${ENV:-${ENVIRONMENT:-development}}}"
    echo "- Backend env file: ${BACKEND_ENV_FILE}"
    echo "- Backend env overlay: ${BACKEND_ENV_OVERLAY_FILE:-none}"
    echo "- Status: PASS"
  } >"$REPORT_PATH"
else
  echo "Report: SKIPPED (set VERIFY_WRITE_REPORT=1 to write LAUNCH_READINESS_REPORT.md)"
fi

echo "verify_all: PASS"
