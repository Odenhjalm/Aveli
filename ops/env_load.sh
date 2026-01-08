#!/usr/bin/env bash
set -euo pipefail

# Unified backend env loader. Sources baseline env then optional overlay, exporting
# all variables deterministically.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_ENV_FILE_DEFAULT="${ROOT_DIR}/backend/.env"

normalize_stripe_mode() {
  local raw="$1"
  raw="${raw,,}"
  case "$raw" in
    test|testing|dev|development) echo "test" ;;
    live|prod|production) echo "live" ;;
    *) echo "" ;;
  esac
}

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

  app_env_raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
  app_env_lower="${app_env_raw,,}"
  is_prod=false
  if [[ "$app_env_lower" == "prod" || "$app_env_lower" == "production" || "$app_env_lower" == "live" ]]; then
    is_prod=true
  fi

  explicit_raw="${STRIPE_KEYSET:-}"
  if [[ -z "$explicit_raw" ]]; then
    explicit_raw="$(printenv APP_ENV_MODE || true)"
  fi
  if [[ -n "$explicit_raw" ]]; then
    resolved_mode="$(normalize_stripe_mode "$explicit_raw")"
    if [[ -z "$resolved_mode" ]]; then
      echo "ERROR: STRIPE_KEYSET/APP_ENV_MODE must be 'test' or 'live'." >&2
      return 1
    fi
    APP_ENV_MODE="$resolved_mode"
    if [[ "$is_prod" == "true" && "$APP_ENV_MODE" == "test" ]]; then
      echo "ERROR: APP_ENV indicates production but Stripe mode is test; set STRIPE_KEYSET/APP_ENV_MODE=live." >&2
      return 1
    fi
  else
    if [[ "$is_prod" == "true" ]]; then
      APP_ENV_MODE="live"
    elif [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      APP_ENV_MODE="test"
    else
      has_test=false
      has_live=false
      for key in STRIPE_SECRET_KEY STRIPE_TEST_SECRET_KEY STRIPE_LIVE_SECRET_KEY; do
        value="${!key:-}"
        if [[ "$value" == sk_test_* ]]; then
          has_test=true
        elif [[ "$value" == sk_live_* ]]; then
          has_live=true
        fi
      done
      if [[ "$has_test" == "true" && "$has_live" != "true" ]]; then
        APP_ENV_MODE="test"
      else
        APP_ENV_MODE="live"
      fi
    fi
  fi

  export_mode=false
  if [[ -n "$explicit_raw" || -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    export_mode=true
  fi

  export BACKEND_ENV_FILE BACKEND_ENV_OVERLAY_FILE
  if [[ "$export_mode" == "true" ]]; then
    export APP_ENV_MODE
  fi

  overlay_note="none"
  if [[ "$APP_ENV_MODE" == "test" ]]; then
    if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      if [[ -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$BACKEND_ENV_OVERLAY_FILE"
        set +a
        overlay_note="$BACKEND_ENV_OVERLAY_FILE"
      else
        overlay_note="${BACKEND_ENV_OVERLAY_FILE} (missing)"
        echo "WARN: Backend env overlay not found at ${BACKEND_ENV_OVERLAY_FILE}; continuing with baseline only." >&2
      fi
    fi

    # Normalize Stripe keys for test mode: keep only canonical vars set to test values.
    test_secret="${STRIPE_TEST_SECRET_KEY:-}"
    if [[ -z "$test_secret" && "${STRIPE_SECRET_KEY:-}" == sk_test_* ]]; then
      test_secret="${STRIPE_SECRET_KEY}"
    elif [[ -z "$test_secret" && "${STRIPE_LIVE_SECRET_KEY:-}" == sk_test_* ]]; then
      test_secret="${STRIPE_LIVE_SECRET_KEY}"
    fi

    test_publishable="${STRIPE_TEST_PUBLISHABLE_KEY:-}"
    if [[ -z "$test_publishable" && "${STRIPE_PUBLISHABLE_KEY:-}" == pk_test_* ]]; then
      test_publishable="${STRIPE_PUBLISHABLE_KEY}"
    elif [[ -z "$test_publishable" && "${STRIPE_LIVE_PUBLISHABLE_KEY:-}" == pk_test_* ]]; then
      test_publishable="${STRIPE_LIVE_PUBLISHABLE_KEY}"
    fi

    test_webhook="${STRIPE_TEST_WEBHOOK_SECRET:-${STRIPE_WEBHOOK_SECRET:-}}"
    test_billing="${STRIPE_TEST_WEBHOOK_BILLING_SECRET:-${STRIPE_BILLING_WEBHOOK_SECRET:-}}"

    unset STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_WEBHOOK_SECRET STRIPE_BILLING_WEBHOOK_SECRET
    unset STRIPE_LIVE_SECRET_KEY STRIPE_LIVE_PUBLISHABLE_KEY STRIPE_LIVE_WEBHOOK_SECRET STRIPE_LIVE_BILLING_WEBHOOK_SECRET
    unset STRIPE_TEST_SECRET_KEY STRIPE_TEST_PUBLISHABLE_KEY STRIPE_TEST_WEBHOOK_SECRET STRIPE_TEST_WEBHOOK_BILLING_SECRET

    if [[ -n "$test_secret" ]]; then
      export STRIPE_SECRET_KEY="$test_secret"
    fi
    if [[ -n "$test_publishable" ]]; then
      export STRIPE_PUBLISHABLE_KEY="$test_publishable"
    fi
    if [[ -n "$test_webhook" ]]; then
      export STRIPE_WEBHOOK_SECRET="$test_webhook"
    fi
    if [[ -n "$test_billing" ]]; then
      export STRIPE_BILLING_WEBHOOK_SECRET="$test_billing"
    fi
  else
    if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
      overlay_note="${BACKEND_ENV_OVERLAY_FILE} (ignored; APP_ENV mode=live)"
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
