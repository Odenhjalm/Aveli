#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"

if [[ "${AVELI_ENV_LOADED:-0}" != "1" ]]; then
  # shellcheck source=/dev/null
  source "$OPS_DIR/env_load.sh"
fi

overlay_requested=false
overlay_missing=false
if [[ -n "${BACKEND_ENV_OVERLAY_FILE:-}" ]]; then
  overlay_requested=true
  if [[ ! -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    overlay_missing=true
  fi
fi

app_env_raw="${APP_ENV:-${ENV:-${ENVIRONMENT:-development}}}"
app_env_lower="${app_env_raw,,}"
if [[ "$app_env_lower" == "prod" || "$app_env_lower" == "production" || "$app_env_lower" == "live" ]]; then
  ENV_MODE="production"
else
  ENV_MODE="development"
fi

if $overlay_missing; then
  echo "Overlay verify: SKIP (overlay file missing)"
  if [[ "$ENV_MODE" == "production" ]]; then
    exit 1
  fi
  exit 0
fi

stripe_active_secret=""
stripe_active_source=""
if $overlay_requested && [[ -n "${STRIPE_TEST_SECRET_KEY:-}" ]]; then
  stripe_active_secret="${STRIPE_TEST_SECRET_KEY}"
  stripe_active_source="STRIPE_TEST_SECRET_KEY"
elif [[ -n "${STRIPE_SECRET_KEY:-}" ]]; then
  stripe_active_secret="${STRIPE_SECRET_KEY}"
  stripe_active_source="STRIPE_SECRET_KEY"
fi

if [[ -z "$stripe_active_secret" ]]; then
  echo "ERROR: Stripe secret key missing (set STRIPE_SECRET_KEY or STRIPE_TEST_SECRET_KEY)" >&2
  exit 1
fi

stripe_mode="unknown"
if [[ "$stripe_active_secret" == sk_test_* ]]; then
  stripe_mode="test"
elif [[ "$stripe_active_secret" == sk_live_* ]]; then
  stripe_mode="live"
else
  echo "ERROR: ${stripe_active_source:-Stripe secret} must start with sk_test_ or sk_live_" >&2
  exit 1
fi

active_publishable=""
active_publishable_source=""
if [[ "$stripe_mode" == "test" && -n "${STRIPE_TEST_PUBLISHABLE_KEY:-}" ]]; then
  active_publishable="${STRIPE_TEST_PUBLISHABLE_KEY}"
  active_publishable_source="STRIPE_TEST_PUBLISHABLE_KEY"
elif [[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ]]; then
  active_publishable="${STRIPE_PUBLISHABLE_KEY}"
  active_publishable_source="STRIPE_PUBLISHABLE_KEY"
fi

if [[ -z "$active_publishable" ]]; then
  echo "ERROR: Stripe publishable key missing for ${stripe_mode} mode" >&2
  exit 1
fi

if [[ "$stripe_mode" == "test" && "$active_publishable" != pk_test_* ]]; then
  echo "ERROR: Stripe publishable key must be pk_test_ when using sk_test_*" >&2
  exit 1
elif [[ "$stripe_mode" == "live" && "$active_publishable" != pk_live_* ]]; then
  echo "ERROR: Stripe publishable key must be pk_live_ when using sk_live_*" >&2
  exit 1
fi

echo "env_validate: PASS (${stripe_mode} via ${stripe_active_source}, publishable ${active_publishable_source:-missing})"
