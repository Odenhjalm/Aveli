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

  app_env_raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-development}}}"
  app_env_lower="${app_env_raw,,}"
  APP_ENV_MODE="test"
  if [[ "$app_env_lower" == "prod" || "$app_env_lower" == "production" || "$app_env_lower" == "live" ]]; then
    APP_ENV_MODE="live"
  fi

  if [[ "$APP_ENV_MODE" == "test" && -z "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    default_overlay="${ROOT_DIR}/backend/test.env"
    if [[ -f "$default_overlay" ]]; then
      BACKEND_ENV_OVERLAY_FILE="$default_overlay"
    fi
  fi

  if [[ ! -f "$BACKEND_ENV_FILE" ]]; then
    echo "ERROR: backend env file missing at ${BACKEND_ENV_FILE}" >&2
    return 1
  fi

  export BACKEND_ENV_FILE BACKEND_ENV_OVERLAY_FILE APP_ENV_MODE

  user_app_env="${APP_ENV:-}"

  set -a
  echo "==> Backend env file: ${BACKEND_ENV_FILE}"
  # shellcheck source=/dev/null
  source "$BACKEND_ENV_FILE"

  overlay_note="none"
  if [[ "$APP_ENV_MODE" == "test" ]]; then
    if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      if [[ -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$BACKEND_ENV_OVERLAY_FILE"
        overlay_note="$BACKEND_ENV_OVERLAY_FILE"
      else
        overlay_note="${BACKEND_ENV_OVERLAY_FILE} (missing)"
        echo "WARN: Backend env overlay not found at ${BACKEND_ENV_OVERLAY_FILE}; continuing with baseline only." >&2
      fi
    fi

    # Ensure live Stripe secrets are not active in test/dev runs.
    unset STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_WEBHOOK_SECRET STRIPE_BILLING_WEBHOOK_SECRET
    unset STRIPE_LIVE_SECRET_KEY STRIPE_LIVE_PUBLISHABLE_KEY STRIPE_LIVE_WEBHOOK_SECRET STRIPE_LIVE_BILLING_WEBHOOK_SECRET
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
  else
    if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      overlay_note="${BACKEND_ENV_OVERLAY_FILE} (ignored; APP_ENV=live)"
    fi
    # Ensure test Stripe secrets are not active in live runs.
    unset STRIPE_TEST_SECRET_KEY STRIPE_TEST_PUBLISHABLE_KEY STRIPE_TEST_WEBHOOK_SECRET STRIPE_TEST_WEBHOOK_BILLING_SECRET
    unset STRIPE_TEST_MEMBERSHIP_PRODUCT_ID STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY
    if [[ -n "${STRIPE_LIVE_SECRET_KEY:-}" && -z "${STRIPE_SECRET_KEY:-}" ]]; then
      export STRIPE_SECRET_KEY="$STRIPE_LIVE_SECRET_KEY"
    fi
    if [[ -n "${STRIPE_LIVE_PUBLISHABLE_KEY:-}" && -z "${STRIPE_PUBLISHABLE_KEY:-}" ]]; then
      export STRIPE_PUBLISHABLE_KEY="$STRIPE_LIVE_PUBLISHABLE_KEY"
    fi
    if [[ -n "${STRIPE_LIVE_WEBHOOK_SECRET:-}" && -z "${STRIPE_WEBHOOK_SECRET:-}" ]]; then
      export STRIPE_WEBHOOK_SECRET="$STRIPE_LIVE_WEBHOOK_SECRET"
    fi
    if [[ -n "${STRIPE_LIVE_BILLING_WEBHOOK_SECRET:-}" && -z "${STRIPE_BILLING_WEBHOOK_SECRET:-}" ]]; then
      export STRIPE_BILLING_WEBHOOK_SECRET="$STRIPE_LIVE_BILLING_WEBHOOK_SECRET"
    fi
  fi
  set +a

  # Preserve caller-provided APP_ENV if the baseline file sets its own default.
  if [[ -n "${user_app_env:-}" ]]; then
    export APP_ENV="$user_app_env"
  fi

  echo "==> Backend env overlay: ${overlay_note}"
  echo "==> APP_ENV mode: ${APP_ENV_MODE}"

  export AVELI_ENV_LOADED=1
  return 0
}

aveli_load_env "$@"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  exit $?
fi
