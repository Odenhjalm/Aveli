#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"

if [[ "${AVELI_ENV_LOADED:-0}" != "1" ]]; then
  # shellcheck source=/dev/null
  source "$OPS_DIR/env_load.sh"
fi

errors=()
warnings=()

add_error() {
  errors+=("$1")
}

add_warning() {
  warnings+=("$1")
}

fail_if_any() {
  if [[ "${#errors[@]}" -gt 0 ]]; then
    echo "env_validate: FAIL" >&2
    for err in "${errors[@]}"; do
      echo "- ${err}" >&2
    done
    exit 1
  fi
}

overlay_requested=false
overlay_missing=false
if [[ -n "${BACKEND_ENV_OVERLAY_FILE:-}" ]]; then
  overlay_requested=true
  if [[ ! -f "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    overlay_missing=true
  fi
fi

app_env_raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-development}}}"
app_env_lower="${app_env_raw,,}"
if [[ "$app_env_lower" == "prod" || "$app_env_lower" == "production" || "$app_env_lower" == "live" ]]; then
  ENV_MODE="live"
else
  ENV_MODE="test"
fi

if $overlay_missing; then
  add_warning "Backend env overlay requested at ${BACKEND_ENV_OVERLAY_FILE} but file is missing"
fi

stripe_secret="${STRIPE_SECRET_KEY:-}"
stripe_test_secret="${STRIPE_TEST_SECRET_KEY:-}"
stripe_live_secret="${STRIPE_LIVE_SECRET_KEY:-}"

test_secrets=()
live_secrets=()

record_secret() {
  local value="$1"
  local source="$2"
  if [[ -z "$value" ]]; then
    return 0
  fi
  if [[ "$value" == sk_test_* ]]; then
    test_secrets+=("$value:$source")
  elif [[ "$value" == sk_live_* ]]; then
    live_secrets+=("$value:$source")
  else
    add_error "${source} must start with sk_test_ or sk_live_ (got: ${value:0:6}...)"
  fi
}

record_secret "$stripe_secret" "STRIPE_SECRET_KEY"
record_secret "$stripe_test_secret" "STRIPE_TEST_SECRET_KEY"
record_secret "$stripe_live_secret" "STRIPE_LIVE_SECRET_KEY"

# Only consider conflicts when multiple distinct values exist within the same mode.
if [[ "${#test_secrets[@]}" -gt 1 ]]; then
  mapfile -t unique_test_values < <(printf "%s\n" "${test_secrets[@]}" | cut -d':' -f1 | sort -u)
  if [[ "${#unique_test_values[@]}" -gt 1 ]]; then
    mapfile -t test_sources < <(printf "%s\n" "${test_secrets[@]}" | cut -d':' -f2)
    add_error "Conflicting Stripe test secrets set across ${test_sources[*]}."
  fi
fi

if [[ "${#live_secrets[@]}" -gt 1 ]]; then
  mapfile -t unique_live_values < <(printf "%s\n" "${live_secrets[@]}" | cut -d':' -f1 | sort -u)
  if [[ "${#unique_live_values[@]}" -gt 1 ]]; then
    mapfile -t live_sources < <(printf "%s\n" "${live_secrets[@]}" | cut -d':' -f2)
    add_error "Conflicting Stripe live secrets set across ${live_sources[*]}."
  fi
fi

fail_if_any

stripe_active_secret=""
stripe_active_source=""
if [[ "$ENV_MODE" == "live" ]]; then
  if [[ "${#live_secrets[@]}" -gt 0 ]]; then
    # Prefer STRIPE_SECRET_KEY if present for live.
    for pair in "${live_secrets[@]}"; do
      value="${pair%%:*}"
      source="${pair##*:}"
      if [[ "$source" == "STRIPE_SECRET_KEY" ]]; then
        stripe_active_secret="$value"
        stripe_active_source="$source"
        break
      fi
    done
    if [[ -z "$stripe_active_secret" ]]; then
      value="${live_secrets[0]%%:*}"
      source="${live_secrets[0]##*:}"
      stripe_active_secret="$value"
      stripe_active_source="$source"
    fi
  elif [[ "${#test_secrets[@]}" -gt 0 ]]; then
    add_error "APP_ENV indicates live but only test Stripe secrets are set."
  fi
else
  if [[ "${#test_secrets[@]}" -gt 0 ]]; then
    # Prefer STRIPE_TEST_SECRET_KEY if present for test/dev.
    for pair in "${test_secrets[@]}"; do
      value="${pair%%:*}"
      source="${pair##*:}"
      if [[ "$source" == "STRIPE_TEST_SECRET_KEY" ]]; then
        stripe_active_secret="$value"
        stripe_active_source="$source"
        break
      fi
    done
    if [[ -z "$stripe_active_secret" ]]; then
      value="${test_secrets[0]%%:*}"
      source="${test_secrets[0]##*:}"
      stripe_active_secret="$value"
      stripe_active_source="$source"
    fi
  elif [[ "${#live_secrets[@]}" -gt 0 ]]; then
    add_error "APP_ENV indicates test/dev but only live Stripe secrets are set."
  fi
fi

if [[ -z "$stripe_active_secret" ]]; then
  add_error "Stripe secret key missing for ${ENV_MODE} mode (set STRIPE_TEST_SECRET_KEY for test or STRIPE_SECRET_KEY/STRIPE_LIVE_SECRET_KEY for live)."
fi

stripe_mode="unknown"
if [[ "$stripe_active_secret" == sk_test_* ]]; then
  stripe_mode="test"
elif [[ "$stripe_active_secret" == sk_live_* ]]; then
  stripe_mode="live"
fi

if [[ "$stripe_mode" != "unknown" && "$stripe_mode" != "$ENV_MODE" ]]; then
  add_error "Stripe secret (${stripe_active_source:-unset}) does not match APP_ENV mode (${ENV_MODE})."
fi

if [[ "$stripe_mode" == "test" && "${#live_secrets[@]}" -gt 0 ]]; then
  mapfile -t live_sources < <(printf "%s\n" "${live_secrets[@]}" | cut -d':' -f2)
  add_warning "Live Stripe secret present (${live_sources[*]}) while APP_ENV=test; test keys will be used."
elif [[ "$stripe_mode" == "live" && "${#test_secrets[@]}" -gt 0 ]]; then
  mapfile -t test_sources < <(printf "%s\n" "${test_secrets[@]}" | cut -d':' -f2)
  add_warning "Test Stripe secret present (${test_sources[*]}) while APP_ENV=live; live keys will be used."
fi

active_publishable=""
active_publishable_source=""
if [[ "$stripe_mode" == "test" || "$stripe_mode" == "live" ]]; then
  if [[ "$stripe_mode" == "test" ]]; then
    if [[ -n "${STRIPE_TEST_PUBLISHABLE_KEY:-}" ]]; then
      active_publishable="${STRIPE_TEST_PUBLISHABLE_KEY}"
      active_publishable_source="STRIPE_TEST_PUBLISHABLE_KEY"
    elif [[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ]]; then
      active_publishable="${STRIPE_PUBLISHABLE_KEY}"
      active_publishable_source="STRIPE_PUBLISHABLE_KEY"
      add_warning "Prefer STRIPE_TEST_PUBLISHABLE_KEY for test/dev; using STRIPE_PUBLISHABLE_KEY."
    fi
  else
    if [[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ]]; then
      active_publishable="${STRIPE_PUBLISHABLE_KEY}"
      active_publishable_source="STRIPE_PUBLISHABLE_KEY"
    fi
  fi

  if [[ -z "$active_publishable" ]]; then
    add_error "Stripe publishable key missing for ${stripe_mode} mode"
  elif [[ "$stripe_mode" == "test" && "$active_publishable" != pk_test_* ]]; then
    add_error "Stripe publishable key must be pk_test_ when using sk_test_*"
  elif [[ "$stripe_mode" == "live" && "$active_publishable" != pk_live_* ]]; then
    add_error "Stripe publishable key must be pk_live_ when using sk_live_*"
  fi

  if [[ "$stripe_mode" == "test" ]]; then
    webhook_secret="${STRIPE_TEST_WEBHOOK_SECRET:-}"
    billing_secret="${STRIPE_TEST_WEBHOOK_BILLING_SECRET:-}"
  else
    webhook_secret="${STRIPE_WEBHOOK_SECRET:-}"
    billing_secret="${STRIPE_BILLING_WEBHOOK_SECRET:-}"
  fi

  if [[ -z "$webhook_secret" || -z "$billing_secret" ]]; then
    add_error "Stripe webhook secrets are missing for ${stripe_mode} mode"
  else
    if [[ "$webhook_secret" != whsec_* ]]; then
      add_warning "Stripe webhook secret does not start with whsec_ (${webhook_secret:0:6}...)"
    fi
    if [[ "$billing_secret" != whsec_* ]]; then
      add_warning "Stripe billing webhook secret does not start with whsec_ (${billing_secret:0:6}...)"
    fi
  fi
fi

fail_if_any

if [[ "${#warnings[@]}" -gt 0 ]]; then
  for warn in "${warnings[@]}"; do
    echo "WARN: ${warn}"
  done
fi

overlay_status="none"
if $overlay_requested; then
  overlay_status="${BACKEND_ENV_OVERLAY_FILE}"
  if $overlay_missing; then
    overlay_status="${BACKEND_ENV_OVERLAY_FILE} (missing)"
  elif [[ "$ENV_MODE" == "live" ]]; then
    overlay_status="${BACKEND_ENV_OVERLAY_FILE} (ignored; APP_ENV=live)"
  fi
fi
echo "env_validate: PASS (${stripe_mode} via ${stripe_active_source}, publishable ${active_publishable_source:-missing}, overlay ${overlay_status})"
