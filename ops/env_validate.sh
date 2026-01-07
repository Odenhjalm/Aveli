#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-"${ROOT_DIR}/backend/.env"}"
BACKEND_ENV_OVERLAY_FILE="${BACKEND_ENV_OVERLAY_FILE:-""}"

CI_MODE=false
if [[ -n "${CI:-}" ]]; then
  ci_value="${CI,,}"
  if [[ "$ci_value" != "false" && "$ci_value" != "0" ]]; then
    CI_MODE=true
  fi
fi

load_env_file() {
  local env_file="$1"
  if [[ -z "$env_file" ]]; then
    return 0
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: backend env missing at ${env_file}" >&2
    return 1
  fi
  eval "$(
    python3 - <<'PY' "$env_file"
import shlex
import sys

path = sys.argv[1]
for raw_line in open(path, "r", encoding="utf-8"):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if value and value[0] == value[-1] and value[0] in ("\"", "'"):
        value = value[1:-1]
    if not key:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
  )"
}

if ! load_env_file "$BACKEND_ENV_FILE"; then
  exit 1
fi
if ! load_env_file "$BACKEND_ENV_OVERLAY_FILE"; then
  exit 1
fi

echo "[env] loaded BACKEND_ENV_FILE=$BACKEND_ENV_FILE"
if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
  echo "[env] loaded BACKEND_ENV_OVERLAY_FILE=$BACKEND_ENV_OVERLAY_FILE"
else
  echo "[env] loaded BACKEND_ENV_OVERLAY_FILE=none"
fi

STATUS=0
OVERLAY_SET="false"
if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
  OVERLAY_SET="true"
fi

warn() {
  local message="$1"
  if "$CI_MODE"; then
    echo "ERROR: $message" >&2
    STATUS=1
  else
    echo "WARN: $message" >&2
  fi
}

critical() {
  local message="$1"
  echo "ERROR: $message" >&2
  STATUS=1
}

note() {
  echo "$1"
}

has_value() {
  [[ -n "${!1:-}" ]]
}

report_var() {
  local name="$1"
  local required="$2"
  if has_value "$name"; then
    note "  - $name: set"
  else
    note "  - $name: missing"
    if [[ "$required" == "required" ]]; then
      critical "$name is required"
    fi
  fi
}

lower() {
  echo "${1,,}"
}

get_url_host() {
  local url="$1"
  python3 - <<'PY' "$url"
import sys
from urllib.parse import urlparse

raw = sys.argv[1]
try:
    parsed = urlparse(raw)
    host = parsed.hostname or ""
except Exception:
    host = ""
print(host)
PY
}

is_local_host() {
  local host="$1"
  case "$host" in
    localhost|127.0.0.1|0.0.0.0|::1) return 0 ;;
    *) return 1 ;;
  esac
}

contains_placeholder() {
  local value="$1"
  local lowered
  lowered="$(lower "$value")"
  if [[ "$lowered" == *"replace"* || "$lowered" == *"your-project"* || "$lowered" == *"changeme"* ]]; then
    return 0
  fi
  return 1
}

ENV_NAME="${ENVIRONMENT:-${APP_ENV:-${ENV:-}}}"
ENV_LOWER="$(lower "$ENV_NAME")"
ENV_MODE="unknown"
if [[ -z "$ENV_LOWER" ]]; then
  warn "ENVIRONMENT/APP_ENV/ENV not set; assuming non-prod for key validation"
  ENV_MODE="nonprod"
elif [[ "$ENV_LOWER" == "prod" || "$ENV_LOWER" == "production" || "$ENV_LOWER" == "live" ]]; then
  ENV_MODE="prod"
else
  ENV_MODE="nonprod"
fi

DB_REQUIRED="required"
JWT_REQUIRED="required"
STRIPE_PRICE_REQUIRED="required"
if [[ "$ENV_MODE" == "nonprod" ]]; then
  DB_REQUIRED="optional"
  JWT_REQUIRED="optional"
fi

stripe_secret_names=()
stripe_secret_values=()
for key in STRIPE_SECRET_KEY STRIPE_TEST_SECRET_KEY STRIPE_LIVE_SECRET_KEY; do
  if has_value "$key"; then
    stripe_secret_names+=("$key")
    stripe_secret_values+=("${!key}")
  fi
done
unique_secret_count="$(printf "%s\n" "${stripe_secret_values[@]:-}" | sort -u | wc -l | tr -d ' ')"
if [[ "$unique_secret_count" -gt 1 ]]; then
  note "INFO: Multiple Stripe secrets detected; selecting active key by mode/priority (overlay prefers test keys)"
fi

STRIPE_ACTIVE_SECRET=""
STRIPE_ACTIVE_SOURCE=""
if [[ "$OVERLAY_SET" == "true" && -n "${STRIPE_TEST_SECRET_KEY:-}" ]]; then
  STRIPE_ACTIVE_SECRET="${STRIPE_TEST_SECRET_KEY}"
  STRIPE_ACTIVE_SOURCE="STRIPE_TEST_SECRET_KEY"
elif has_value STRIPE_SECRET_KEY; then
  STRIPE_ACTIVE_SECRET="${STRIPE_SECRET_KEY}"
  STRIPE_ACTIVE_SOURCE="STRIPE_SECRET_KEY"
elif has_value STRIPE_TEST_SECRET_KEY; then
  STRIPE_ACTIVE_SECRET="${STRIPE_TEST_SECRET_KEY}"
  STRIPE_ACTIVE_SOURCE="STRIPE_TEST_SECRET_KEY"
elif has_value STRIPE_LIVE_SECRET_KEY; then
  STRIPE_ACTIVE_SECRET="${STRIPE_LIVE_SECRET_KEY}"
  STRIPE_ACTIVE_SOURCE="STRIPE_LIVE_SECRET_KEY"
fi

STRIPE_MODE_RESOLVED="unknown"
if [[ -z "$STRIPE_ACTIVE_SECRET" ]]; then
  critical "Stripe secret key missing (set STRIPE_SECRET_KEY or STRIPE_TEST_SECRET_KEY or STRIPE_LIVE_SECRET_KEY)"
else
  if [[ "$STRIPE_ACTIVE_SECRET" == sk_test_* ]]; then
    STRIPE_MODE_RESOLVED="test"
  elif [[ "$STRIPE_ACTIVE_SECRET" == sk_live_* ]]; then
    STRIPE_MODE_RESOLVED="live"
  else
    critical "${STRIPE_ACTIVE_SOURCE:-STRIPE_SECRET_KEY} must start with sk_test_ or sk_live_"
  fi
fi

ACTIVE_PUBLISHABLE=""
ACTIVE_PUBLISHABLE_SOURCE=""
if [[ "$STRIPE_MODE_RESOLVED" == "test" && -n "${STRIPE_TEST_PUBLISHABLE_KEY:-}" ]]; then
  ACTIVE_PUBLISHABLE="${STRIPE_TEST_PUBLISHABLE_KEY}"
  ACTIVE_PUBLISHABLE_SOURCE="STRIPE_TEST_PUBLISHABLE_KEY"
elif has_value STRIPE_PUBLISHABLE_KEY; then
  ACTIVE_PUBLISHABLE="${STRIPE_PUBLISHABLE_KEY}"
  ACTIVE_PUBLISHABLE_SOURCE="STRIPE_PUBLISHABLE_KEY"
fi

if [[ -z "$ACTIVE_PUBLISHABLE" ]]; then
  if [[ "$STRIPE_MODE_RESOLVED" == "test" ]]; then
    critical "Stripe publishable key missing for test mode (set STRIPE_PUBLISHABLE_KEY or STRIPE_TEST_PUBLISHABLE_KEY)"
  elif [[ "$STRIPE_MODE_RESOLVED" == "live" ]]; then
    critical "Stripe publishable key missing for live mode (set STRIPE_PUBLISHABLE_KEY)"
  else
    critical "Stripe publishable key missing"
  fi
elif [[ "$STRIPE_MODE_RESOLVED" == "test" && "$ACTIVE_PUBLISHABLE" != pk_test_* ]]; then
  critical "Stripe publishable key must be pk_test_ when using sk_test_*"
elif [[ "$STRIPE_MODE_RESOLVED" == "live" && "$ACTIVE_PUBLISHABLE" != pk_live_* ]]; then
  critical "Stripe publishable key must be pk_live_ when using sk_live_*"
fi

ACTIVE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-}"; ACTIVE_WEBHOOK_SOURCE=""
if [[ "$STRIPE_MODE_RESOLVED" == "test" && -n "${STRIPE_TEST_WEBHOOK_SECRET:-}" ]]; then
  ACTIVE_WEBHOOK_SECRET="${STRIPE_TEST_WEBHOOK_SECRET}"
  ACTIVE_WEBHOOK_SOURCE="STRIPE_TEST_WEBHOOK_SECRET"
elif [[ -n "$ACTIVE_WEBHOOK_SECRET" ]]; then
  ACTIVE_WEBHOOK_SOURCE="STRIPE_WEBHOOK_SECRET"
fi

ACTIVE_BILLING_WEBHOOK_SECRET="${STRIPE_BILLING_WEBHOOK_SECRET:-}"; ACTIVE_BILLING_WEBHOOK_SOURCE=""
if [[ "$STRIPE_MODE_RESOLVED" == "test" && -n "${STRIPE_TEST_WEBHOOK_BILLING_SECRET:-}" ]]; then
  ACTIVE_BILLING_WEBHOOK_SECRET="${STRIPE_TEST_WEBHOOK_BILLING_SECRET}"
  ACTIVE_BILLING_WEBHOOK_SOURCE="STRIPE_TEST_WEBHOOK_BILLING_SECRET"
elif [[ -n "$ACTIVE_BILLING_WEBHOOK_SECRET" ]]; then
  ACTIVE_BILLING_WEBHOOK_SOURCE="STRIPE_BILLING_WEBHOOK_SECRET"
fi

if [[ -z "$ACTIVE_WEBHOOK_SECRET" || -z "$ACTIVE_BILLING_WEBHOOK_SECRET" ]]; then
  critical "Missing Stripe webhook signing secret for ${STRIPE_MODE_RESOLVED:-unknown} mode (set STRIPE_WEBHOOK_SECRET/STRIPE_BILLING_WEBHOOK_SECRET or test equivalents)"
else
  if [[ "$ACTIVE_WEBHOOK_SECRET" != whsec_* ]]; then
    warn "Stripe webhook secret does not match whsec_ pattern"
  fi
  if [[ "$ACTIVE_BILLING_WEBHOOK_SECRET" != whsec_* ]]; then
    warn "Stripe billing webhook secret does not match whsec_ pattern"
  fi
fi

note "==> Backend (required)"
report_var APP_ENV required
report_var SUPABASE_URL required
report_var SUPABASE_PUBLISHABLE_API_KEY required
report_var SUPABASE_SECRET_API_KEY required
report_var SUPABASE_DB_URL "$DB_REQUIRED"
report_var JWT_SECRET "$JWT_REQUIRED"
report_var JWT_ALGORITHM "$JWT_REQUIRED"
report_var JWT_EXPIRES_MINUTES "$JWT_REQUIRED"
report_var JWT_REFRESH_EXPIRES_MINUTES "$JWT_REQUIRED"

note "==> Backend (optional/legacy)"
report_var SUPABASE_SERVICE_ROLE_KEY optional
report_var SUPABASE_ANON_KEY optional
report_var SUPABASE_JWT_SECRET optional
report_var MEDIA_SIGNING_SECRET optional

note "==> Stripe (active config)"
note "  - Active mode: ${STRIPE_MODE_RESOLVED}"
note "  - Secret source: ${STRIPE_ACTIVE_SOURCE:-missing}"
note "  - Publishable source: ${ACTIVE_PUBLISHABLE_SOURCE:-missing}"
note "  - Webhook source: ${ACTIVE_WEBHOOK_SOURCE:-missing}"
note "  - Billing webhook source: ${ACTIVE_BILLING_WEBHOOK_SOURCE:-missing}"
report_var STRIPE_SECRET_KEY optional
report_var STRIPE_TEST_SECRET_KEY optional
report_var STRIPE_LIVE_SECRET_KEY optional
report_var STRIPE_PUBLISHABLE_KEY optional
report_var STRIPE_WEBHOOK_SECRET optional
report_var STRIPE_BILLING_WEBHOOK_SECRET optional
if [[ "$STRIPE_MODE_RESOLVED" == "live" ]]; then
  report_var AVELI_PRICE_MONTHLY "$STRIPE_PRICE_REQUIRED"
  report_var AVELI_PRICE_YEARLY "$STRIPE_PRICE_REQUIRED"
else
  report_var STRIPE_TEST_MEMBERSHIP_PRODUCT_ID optional
  report_var STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY optional
  report_var STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY optional
fi

note "==> Stripe (additional/test overrides)"
report_var STRIPE_TEST_PUBLISHABLE_KEY optional
report_var STRIPE_TEST_WEBHOOK_SECRET optional
report_var STRIPE_TEST_WEBHOOK_BILLING_SECRET optional

note "==> Flutter (required for app clients)"
report_var API_BASE_URL required
report_var SUPABASE_URL required
if has_value SUPABASE_PUBLISHABLE_API_KEY || has_value SUPABASE_PUBLIC_API_KEY || has_value SUPABASE_ANON_KEY; then
  note "  - SUPABASE_PUBLISHABLE_API_KEY or SUPABASE_PUBLIC_API_KEY or SUPABASE_ANON_KEY: set"
else
  note "  - SUPABASE_PUBLISHABLE_API_KEY or SUPABASE_PUBLIC_API_KEY or SUPABASE_ANON_KEY: missing"
  warn "SUPABASE_PUBLISHABLE_API_KEY (or SUPABASE_PUBLIC_API_KEY / SUPABASE_ANON_KEY) is required for Flutter"
fi
report_var STRIPE_PUBLISHABLE_KEY optional
report_var OAUTH_REDIRECT_WEB required
report_var OAUTH_REDIRECT_MOBILE required

note "==> Landing (Next.js)"
report_var NEXT_PUBLIC_SUPABASE_URL required
report_var NEXT_PUBLIC_SUPABASE_ANON_KEY required
report_var NEXT_PUBLIC_API_BASE_URL required
report_var NEXT_PUBLIC_SENTRY_DSN optional
report_var SENTRY_DSN optional

note "==> Migrations/ops"
report_var SUPABASE_PROJECT_REF optional
report_var SUPABASE_PAT optional

if has_value DATABASE_URL && ! has_value SUPABASE_DB_URL; then
  warn "DATABASE_URL is set but SUPABASE_DB_URL is missing; backend requires SUPABASE_DB_URL"
fi

if [[ -n "$STRIPE_ACTIVE_SECRET" ]]; then
  if contains_placeholder "$STRIPE_ACTIVE_SECRET"; then
    warn "Stripe secret key looks like a placeholder"
  fi
fi
if [[ -n "$ACTIVE_PUBLISHABLE" ]]; then
  if contains_placeholder "$ACTIVE_PUBLISHABLE"; then
    warn "Stripe publishable key looks like a placeholder"
  fi
fi
if [[ -n "$ACTIVE_WEBHOOK_SECRET" ]]; then
  if contains_placeholder "$ACTIVE_WEBHOOK_SECRET"; then
    warn "Stripe webhook secret looks like a placeholder"
  fi
fi
if [[ -n "$ACTIVE_BILLING_WEBHOOK_SECRET" ]]; then
  if contains_placeholder "$ACTIVE_BILLING_WEBHOOK_SECRET"; then
    warn "Stripe billing webhook secret looks like a placeholder"
  fi
fi

# Supabase URL sanity checks
if has_value SUPABASE_URL; then
  supabase_host="$(get_url_host "${SUPABASE_URL}")"
  if is_local_host "$supabase_host" && [[ "$ENV_MODE" == "prod" ]]; then
    warn "SUPABASE_URL points to localhost in prod"
  fi
  if contains_placeholder "${SUPABASE_URL}"; then
    warn "SUPABASE_URL looks like a placeholder"
  fi
fi

if has_value SUPABASE_DB_URL; then
  db_host="$(get_url_host "${SUPABASE_DB_URL}")"
  if is_local_host "$db_host" && [[ "$ENV_MODE" == "prod" ]]; then
    warn "SUPABASE_DB_URL points to localhost in prod"
  fi
  if contains_placeholder "${SUPABASE_DB_URL}"; then
    warn "SUPABASE_DB_URL looks like a placeholder"
  fi
fi

if has_value JWT_SECRET; then
  if [[ "${JWT_SECRET}" == "change-me" ]]; then
    warn "JWT_SECRET is set to the default value"
  fi
fi

exit "$STATUS"
