#!/usr/bin/env bash
set -euo pipefail

# Unified backend env loader. Sources baseline env then optional overlay, exporting
# all variables deterministically.

BACKEND_ENV_FILE_DEFAULT="/home/oden/Aveli/backend/.env"

aveli_load_env() {
  if [[ "${AVELI_ENV_LOADED:-0}" == "1" ]]; then
    return 0
  fi

  BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-$BACKEND_ENV_FILE_DEFAULT}"
  BACKEND_ENV_OVERLAY_FILE="${BACKEND_ENV_OVERLAY_FILE:-""}"

  if [[ ! -f "$BACKEND_ENV_FILE" ]]; then
    echo "ERROR: backend env file missing at ${BACKEND_ENV_FILE}" >&2
    return 1
  fi

  export BACKEND_ENV_FILE BACKEND_ENV_OVERLAY_FILE

  echo "==> Backend env file: ${BACKEND_ENV_FILE}"
  if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    echo "==> Backend env overlay: ${BACKEND_ENV_OVERLAY_FILE}"
  else
    echo "==> Backend env overlay: none"
  fi

  set -a
  # shellcheck source=/dev/null
  source "$BACKEND_ENV_FILE"
  if [[ -n "$BACKEND_ENV_OVERLAY_FILE" && -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$BACKEND_ENV_OVERLAY_FILE"
  fi
  set +a

  export AVELI_ENV_LOADED=1
  return 0
}

aveli_load_env "$@"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  exit $?
fi
