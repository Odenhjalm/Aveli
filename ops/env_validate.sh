#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-${ROOT_DIR}/backend/.env}"

CI_MODE=false
if [[ -n "${CI:-}" ]]; then
  ci_value="${CI,,}"
  if [[ "$ci_value" != "false" && "$ci_value" != "0" ]]; then
    CI_MODE=true
  fi
fi

load_backend_env() {
  if [[ ! -f "$BACKEND_ENV_FILE" ]]; then
    echo "ERROR: backend/.env missing – create it from backend/.env.example" >&2
    exit 1
  fi
  eval "$(
    python3 - <<'PY' "$BACKEND_ENV_FILE"
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

load_backend_env

STATUS=0

warn() {
  local message="$1"
  if "$CI_MODE"; then
    echo "ERROR: $message" >&2
    STATUS=1
  else
    echo "WARN: $message" >&2
  fi
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
  local hint="${3:-}"
  if has_value "$name"; then
    note "  - $name: set"
  else
    note "  - $name: missing"
    if [[ "$required" == "required" ]]; then
      if [[ -n "$hint" ]]; then
        warn "$name is required; see $hint"
      else
        warn "$name is required"
      fi
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
  STRIPE_PRICE_REQUIRED="optional"
fi

note "==> Backend (required)"
report_var APP_ENV required
report_var SUPABASE_URL required
report_var SUPABASE_PUBLISHABLE_API_KEY required
report_var SUPABASE_SECRET_API_KEY required
report_var SUPABASE_DB_URL "${DB_REQUIRED}"
report_var DATABASE_URL "${DB_REQUIRED}"
report_var JWT_SECRET "${JWT_REQUIRED}"
report_var JWT_ALGORITHM "${JWT_REQUIRED}"
report_var JWT_EXPIRES_MINUTES "${JWT_REQUIRED}"
report_var JWT_REFRESH_EXPIRES_MINUTES "${JWT_REQUIRED}"
report_var STRIPE_SECRET_KEY required
report_var STRIPE_PUBLISHABLE_KEY required
report_var STRIPE_WEBHOOK_SECRET required
report_var STRIPE_BILLING_WEBHOOK_SECRET required
report_var STRIPE_PRICE_MONTHLY "${STRIPE_PRICE_REQUIRED}"
report_var STRIPE_PRICE_YEARLY "${STRIPE_PRICE_REQUIRED}"

note "==> Backend (optional/legacy)"
report_var SUPABASE_SERVICE_ROLE_KEY optional
report_var SUPABASE_ANON_KEY optional
report_var SUPABASE_JWT_SECRET optional
report_var MEDIA_SIGNING_SECRET optional

note "==> Stripe (required for mode switching)"
report_var STRIPE_TEST_SECRET_KEY required
report_var STRIPE_TEST_PUBLISHABLE_KEY required
report_var STRIPE_TEST_WEBHOOK_SECRET optional
report_var STRIPE_TEST_WEBHOOK_BILLING_SECRET required
if [[ "$ENV_MODE" == "prod" ]]; then
  report_var STRIPE_LIVE_SECRET_KEY required
  report_var STRIPE_LIVE_PUBLISHABLE_KEY required
  report_var STRIPE_LIVE_WEBHOOK_SECRET required
  report_var STRIPE_LIVE_BILLING_WEBHOOK_SECRET required
else
  report_var STRIPE_LIVE_SECRET_KEY optional
  report_var STRIPE_LIVE_PUBLISHABLE_KEY optional
  report_var STRIPE_LIVE_WEBHOOK_SECRET optional
  report_var STRIPE_LIVE_BILLING_WEBHOOK_SECRET optional
fi

note "==> Flutter (required for app clients)"
report_var API_BASE_URL required
report_var SUPABASE_URL required
if has_value SUPABASE_PUBLISHABLE_API_KEY || has_value SUPABASE_PUBLIC_API_KEY || has_value SUPABASE_ANON_KEY; then
  note "  - SUPABASE_PUBLISHABLE_API_KEY or SUPABASE_PUBLIC_API_KEY or SUPABASE_ANON_KEY: set"
else
  note "  - SUPABASE_PUBLISHABLE_API_KEY or SUPABASE_PUBLIC_API_KEY or SUPABASE_ANON_KEY: missing"
  warn "SUPABASE_PUBLISHABLE_API_KEY (or SUPABASE_PUBLIC_API_KEY / SUPABASE_ANON_KEY) is required for Flutter"
fi
report_var STRIPE_PUBLISHABLE_KEY required
report_var OAUTH_REDIRECT_WEB required
report_var OAUTH_REDIRECT_MOBILE required

note "==> Landing (Next.js)"
landing_hint=".env.example and docs/ENV_VARS.md"
report_var NEXT_PUBLIC_SUPABASE_URL required "$landing_hint"
report_var NEXT_PUBLIC_SUPABASE_ANON_KEY required "$landing_hint"
report_var NEXT_PUBLIC_API_BASE_URL required "$landing_hint"
report_var NEXT_PUBLIC_SENTRY_DSN optional
report_var SENTRY_DSN optional

note "==> Migrations/ops"
report_var SUPABASE_PROJECT_REF optional
report_var SUPABASE_PAT optional

if has_value DATABASE_URL && ! has_value SUPABASE_DB_URL; then
  warn "DATABASE_URL is set but SUPABASE_DB_URL is missing; backend requires SUPABASE_DB_URL"
fi

# Stripe key mode checks
if has_value STRIPE_TEST_SECRET_KEY && [[ "${STRIPE_TEST_SECRET_KEY}" != sk_test_* ]]; then
  warn "STRIPE_TEST_SECRET_KEY does not match sk_test_ pattern"
fi
if has_value STRIPE_TEST_PUBLISHABLE_KEY && [[ "${STRIPE_TEST_PUBLISHABLE_KEY}" != pk_test_* ]]; then
  warn "STRIPE_TEST_PUBLISHABLE_KEY does not match pk_test_ pattern"
fi
if has_value STRIPE_LIVE_SECRET_KEY && [[ "${STRIPE_LIVE_SECRET_KEY}" != sk_live_* ]]; then
  warn "STRIPE_LIVE_SECRET_KEY does not match sk_live_ pattern"
fi
if has_value STRIPE_LIVE_PUBLISHABLE_KEY && [[ "${STRIPE_LIVE_PUBLISHABLE_KEY}" != pk_live_* ]]; then
  warn "STRIPE_LIVE_PUBLISHABLE_KEY does not match pk_live_ pattern"
fi

if has_value STRIPE_WEBHOOK_SECRET && [[ "${STRIPE_WEBHOOK_SECRET}" != whsec_* ]]; then
  warn "STRIPE_WEBHOOK_SECRET does not match whsec_ pattern"
fi
if has_value STRIPE_BILLING_WEBHOOK_SECRET && [[ "${STRIPE_BILLING_WEBHOOK_SECRET}" != whsec_* ]]; then
  warn "STRIPE_BILLING_WEBHOOK_SECRET does not match whsec_ pattern"
fi
if has_value STRIPE_TEST_WEBHOOK_SECRET && [[ "${STRIPE_TEST_WEBHOOK_SECRET}" != whsec_* ]]; then
  warn "STRIPE_TEST_WEBHOOK_SECRET does not match whsec_ pattern"
fi
if has_value STRIPE_TEST_WEBHOOK_BILLING_SECRET && [[ "${STRIPE_TEST_WEBHOOK_BILLING_SECRET}" != whsec_* ]]; then
  warn "STRIPE_TEST_WEBHOOK_BILLING_SECRET does not match whsec_ pattern"
fi
if has_value STRIPE_LIVE_WEBHOOK_SECRET && [[ "${STRIPE_LIVE_WEBHOOK_SECRET}" != whsec_* ]]; then
  warn "STRIPE_LIVE_WEBHOOK_SECRET does not match whsec_ pattern"
fi
if has_value STRIPE_LIVE_BILLING_WEBHOOK_SECRET && [[ "${STRIPE_LIVE_BILLING_WEBHOOK_SECRET}" != whsec_* ]]; then
  warn "STRIPE_LIVE_BILLING_WEBHOOK_SECRET does not match whsec_ pattern"
fi

for key_name in \
  STRIPE_SECRET_KEY \
  STRIPE_PUBLISHABLE_KEY \
  STRIPE_WEBHOOK_SECRET \
  STRIPE_BILLING_WEBHOOK_SECRET \
  STRIPE_TEST_SECRET_KEY \
  STRIPE_TEST_PUBLISHABLE_KEY \
  STRIPE_TEST_WEBHOOK_SECRET \
  STRIPE_TEST_WEBHOOK_BILLING_SECRET \
  STRIPE_LIVE_SECRET_KEY \
  STRIPE_LIVE_PUBLISHABLE_KEY \
  STRIPE_LIVE_WEBHOOK_SECRET \
  STRIPE_LIVE_BILLING_WEBHOOK_SECRET; do
  if has_value "$key_name"; then
    if contains_placeholder "${!key_name}"; then
      warn "$key_name looks like a placeholder"
    fi
  fi
done

if [[ "$ENV_MODE" == "prod" ]]; then
  if has_value STRIPE_SECRET_KEY && has_value STRIPE_LIVE_SECRET_KEY && [[ "${STRIPE_SECRET_KEY}" != "${STRIPE_LIVE_SECRET_KEY}" ]]; then
    warn "STRIPE_SECRET_KEY does not match STRIPE_LIVE_SECRET_KEY in prod"
  fi
  if has_value STRIPE_PUBLISHABLE_KEY && has_value STRIPE_LIVE_PUBLISHABLE_KEY && [[ "${STRIPE_PUBLISHABLE_KEY}" != "${STRIPE_LIVE_PUBLISHABLE_KEY}" ]]; then
    warn "STRIPE_PUBLISHABLE_KEY does not match STRIPE_LIVE_PUBLISHABLE_KEY in prod"
  fi
  if has_value STRIPE_WEBHOOK_SECRET && has_value STRIPE_LIVE_WEBHOOK_SECRET && [[ "${STRIPE_WEBHOOK_SECRET}" != "${STRIPE_LIVE_WEBHOOK_SECRET}" ]]; then
    warn "STRIPE_WEBHOOK_SECRET does not match STRIPE_LIVE_WEBHOOK_SECRET in prod"
  fi
  if has_value STRIPE_BILLING_WEBHOOK_SECRET && has_value STRIPE_LIVE_BILLING_WEBHOOK_SECRET && [[ "${STRIPE_BILLING_WEBHOOK_SECRET}" != "${STRIPE_LIVE_BILLING_WEBHOOK_SECRET}" ]]; then
    warn "STRIPE_BILLING_WEBHOOK_SECRET does not match STRIPE_LIVE_BILLING_WEBHOOK_SECRET in prod"
  fi
else
  if has_value STRIPE_SECRET_KEY && has_value STRIPE_TEST_SECRET_KEY && [[ "${STRIPE_SECRET_KEY}" != "${STRIPE_TEST_SECRET_KEY}" ]]; then
    warn "STRIPE_SECRET_KEY does not match STRIPE_TEST_SECRET_KEY in dev"
  fi
  if has_value STRIPE_PUBLISHABLE_KEY && has_value STRIPE_TEST_PUBLISHABLE_KEY && [[ "${STRIPE_PUBLISHABLE_KEY}" != "${STRIPE_TEST_PUBLISHABLE_KEY}" ]]; then
    warn "STRIPE_PUBLISHABLE_KEY does not match STRIPE_TEST_PUBLISHABLE_KEY in dev"
  fi
  if has_value STRIPE_WEBHOOK_SECRET && has_value STRIPE_TEST_WEBHOOK_SECRET && [[ "${STRIPE_WEBHOOK_SECRET}" != "${STRIPE_TEST_WEBHOOK_SECRET}" ]]; then
    warn "STRIPE_WEBHOOK_SECRET does not match STRIPE_TEST_WEBHOOK_SECRET in dev"
  fi
  if has_value STRIPE_BILLING_WEBHOOK_SECRET && has_value STRIPE_TEST_WEBHOOK_BILLING_SECRET && [[ "${STRIPE_BILLING_WEBHOOK_SECRET}" != "${STRIPE_TEST_WEBHOOK_BILLING_SECRET}" ]]; then
    warn "STRIPE_BILLING_WEBHOOK_SECRET does not match STRIPE_TEST_WEBHOOK_BILLING_SECRET in dev"
  fi
fi

if ! has_value STRIPE_WEBHOOK_SECRET || ! has_value STRIPE_BILLING_WEBHOOK_SECRET; then
  warn "Missing active Stripe webhook signing secret (STRIPE_WEBHOOK_SECRET and STRIPE_BILLING_WEBHOOK_SECRET required)"
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
