#!/usr/bin/env bash
set -euo pipefail

# Netlify CI entrypoint for Flutter Web builds.
#
# IMPORTANT:
# - Values are injected at compile time via --dart-define and are public in the
#   resulting JS bundle. Do NOT pass backend secrets here.
# - This script fails fast if required variables are missing so production never
#   ships a misconfigured build (red config banner).

: "${FLUTTER_API_BASE_URL:?Missing FLUTTER_API_BASE_URL}"
: "${FLUTTER_SUPABASE_URL:?Missing FLUTTER_SUPABASE_URL}"
: "${FLUTTER_SUPABASE_PUBLIC_API_KEY:?Missing FLUTTER_SUPABASE_PUBLIC_API_KEY}"
: "${FLUTTER_STRIPE_PUBLISHABLE_KEY:?Missing FLUTTER_STRIPE_PUBLISHABLE_KEY}"
: "${FLUTTER_OAUTH_REDIRECT_WEB:?Missing FLUTTER_OAUTH_REDIRECT_WEB}"

normalize_url() {
  local url="$1"
  # Remove a trailing slash (common source of double-slash bugs).
  echo "${url%/}"
}

export FLUTTER_API_BASE_URL
export FLUTTER_SUPABASE_URL
export FLUTTER_OAUTH_REDIRECT_WEB
FLUTTER_API_BASE_URL="$(normalize_url "$FLUTTER_API_BASE_URL")"
FLUTTER_SUPABASE_URL="$(normalize_url "$FLUTTER_SUPABASE_URL")"
FLUTTER_OAUTH_REDIRECT_WEB="$(normalize_url "$FLUTTER_OAUTH_REDIRECT_WEB")"

NETLIFY_CONTEXT="${CONTEXT:-${DEPLOY_CONTEXT:-}}"
EXPECTED_PROD_API_BASE_URL="https://aveli.fly.dev"

# Hard fail for production builds if the backend URL is wrong. This prevents
# silently shipping a miscompiled bundle (String.fromEnvironment is compile-time).
if [[ "$NETLIFY_CONTEXT" == "production" ]]; then
  if [[ "$FLUTTER_API_BASE_URL" != "$EXPECTED_PROD_API_BASE_URL" ]]; then
    echo "Refusing production build: FLUTTER_API_BASE_URL must be ${EXPECTED_PROD_API_BASE_URL} (got ${FLUTTER_API_BASE_URL})" >&2
    exit 1
  fi
fi

FLUTTER_VERSION="${FLUTTER_VERSION:-3.35.7}"

install_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi

  echo "Flutter not found; installing Flutter ${FLUTTER_VERSION} (stable)..." >&2

  local cache_dir="${NETLIFY_CACHE_DIR:-$HOME/.cache}"
  local flutter_root="${cache_dir}/flutter"

  if [[ ! -x "${flutter_root}/bin/flutter" ]]; then
    mkdir -p "${cache_dir}"
    rm -rf "${flutter_root}"

    local archive="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    local url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}"
    curl -fsSL "${url}" -o "${archive}"
    tar -xf "${archive}" -C "${cache_dir}"
    rm -f "${archive}"
  fi

  export PATH="${flutter_root}/bin:${PATH}"
}

install_flutter

# Avoid analytics in CI logs.
flutter config --no-analytics >/dev/null 2>&1 || true

# Map Netlify env vars -> build script env vars -> --dart-define keys.
export API_BASE_URL="${FLUTTER_API_BASE_URL}"
export SUPABASE_URL="${FLUTTER_SUPABASE_URL}"
export SUPABASE_PUBLIC_API_KEY="${FLUTTER_SUPABASE_PUBLIC_API_KEY}"
export STRIPE_PUBLISHABLE_KEY="${FLUTTER_STRIPE_PUBLISHABLE_KEY}"
export OAUTH_REDIRECT_WEB="${FLUTTER_OAUTH_REDIRECT_WEB}"

# Optional toggles / metadata.
export STRIPE_MERCHANT_DISPLAY_NAME="${FLUTTER_STRIPE_MERCHANT_DISPLAY_NAME:-Aveli}"
export SUBSCRIPTIONS_ENABLED="${FLUTTER_SUBSCRIPTIONS_ENABLED:-}"
export IMAGE_LOGGING="${FLUTTER_IMAGE_LOGGING:-}"
export FRONTEND_URL="${FLUTTER_FRONTEND_URL:-https://app.aveli.app}"

echo "Netlify context: ${NETLIFY_CONTEXT:-unknown}" >&2
echo "Building Flutter Web with API_BASE_URL=${API_BASE_URL}" >&2

bash scripts/build_prod.sh

# Post-build integrity checks: ensure the compiled bundle contains the expected
# API base URL (compile-time constant) and doesn't contain legacy endpoints.
if [[ "$NETLIFY_CONTEXT" == "production" ]]; then
  main_js="build/web/main.dart.js"
  if [[ ! -f "$main_js" ]]; then
    echo "Build output missing: $main_js" >&2
    exit 1
  fi
  if ! grep -Fq "$EXPECTED_PROD_API_BASE_URL" "$main_js"; then
    echo "Build integrity check failed: ${EXPECTED_PROD_API_BASE_URL} not found in $main_js" >&2
    exit 1
  fi
  if grep -Fq "api.aveli.app" "$main_js"; then
    echo "Build integrity check failed: legacy api.aveli.app found in $main_js" >&2
    exit 1
  fi
fi
