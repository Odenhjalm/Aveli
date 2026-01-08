#!/usr/bin/env bash
set -euo pipefail

# Unified backend env loader. Sources baseline env then optional overlay, exporting
# all variables deterministically.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_ENV_FILE_DEFAULT="${ROOT_DIR}/backend/.env"

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

  user_app_env="${APP_ENV:-}"

  set -a
  echo "==> Backend env file: ${BACKEND_ENV_FILE}"
  # shellcheck source=/dev/null
  source "$BACKEND_ENV_FILE"
  set +a

  overlay_note="none"
  if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    overlay_note="$BACKEND_ENV_OVERLAY_FILE"
    if [[ ! -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      echo "ERROR: backend env overlay missing at ${BACKEND_ENV_OVERLAY_FILE}" >&2
      echo "==> Backend env overlay: ${overlay_note}"
      return 1
    fi

    set -a
    # shellcheck source=/dev/null
    source "$BACKEND_ENV_OVERLAY_FILE"
    set +a

    if [[ -n "${STRIPE_TEST_SECRET_KEY:-}" ]]; then
      export STRIPE_SECRET_KEY="$STRIPE_TEST_SECRET_KEY"
    fi
    if [[ -n "${STRIPE_TEST_PUBLISHABLE_KEY:-}" ]]; then
      export STRIPE_PUBLISHABLE_KEY="$STRIPE_TEST_PUBLISHABLE_KEY"
    fi
    if [[ -n "${STRIPE_TEST_WEBHOOK_SECRET:-}" ]]; then
      export STRIPE_WEBHOOK_SECRET="$STRIPE_TEST_WEBHOOK_SECRET"
    fi
    if [[ -n "${STRIPE_TEST_WEBHOOK_BILLING_SECRET:-}" ]]; then
      export STRIPE_BILLING_WEBHOOK_SECRET="$STRIPE_TEST_WEBHOOK_BILLING_SECRET"
    fi

    unset STRIPE_TEST_SECRET_KEY STRIPE_TEST_PUBLISHABLE_KEY STRIPE_TEST_WEBHOOK_SECRET STRIPE_TEST_WEBHOOK_BILLING_SECRET
    unset STRIPE_LIVE_SECRET_KEY
  fi

  # Preserve caller-provided APP_ENV if the baseline file sets its own default.
  if [[ -n "${user_app_env:-}" ]]; then
    export APP_ENV="$user_app_env"
  fi

  export BACKEND_ENV_FILE BACKEND_ENV_OVERLAY_FILE
  echo "==> Backend env overlay: ${overlay_note}"

  export AVELI_ENV_LOADED=1
  return 0
}

aveli_load_env "$@"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  exit $?
fi
