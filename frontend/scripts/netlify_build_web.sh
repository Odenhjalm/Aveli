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

bash scripts/build_prod.sh
