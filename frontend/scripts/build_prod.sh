#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRONTEND_ROOT/.." && pwd)"
BUILD_DIR="$FRONTEND_ROOT/build/web"
LEGACY_ROOT_BUILD_DIR="$REPO_ROOT/build/web"

cd "$FRONTEND_ROOT"
export BUILD_DIR

WEB_DEFINE_FILE="${WEB_DEFINE_FILE:-}"
# Optional: set WEB_DEFINE_FILE to a .env file for web builds (guarded).
DEFINE_ARGS=()

BUILD_NUMBER="${BUILD_NUMBER:-}"
if [[ -z "$BUILD_NUMBER" ]]; then
  # Always bump the build number to ensure deploys can never be served from an
  # old cached bundle without revalidation.
  BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)$$"
fi
export BUILD_NUMBER

if [[ -n "$WEB_DEFINE_FILE" ]]; then
  "$SCRIPT_DIR/guard_web_defines.sh" "$WEB_DEFINE_FILE"
  DEFINE_ARGS+=(--dart-define-from-file="$WEB_DEFINE_FILE")
else
  for var in API_BASE_URL SUPABASE_URL STRIPE_PUBLISHABLE_KEY OAUTH_REDIRECT_WEB; do
    if [[ -z "${!var:-}" ]]; then
      echo "Missing required env var: $var" >&2
      exit 1
    fi
  done
  SUPABASE_CLIENT_KEY="${SUPABASE_PUBLISHABLE_API_KEY:-${SUPABASE_PUBLIC_API_KEY:-}}"
  if [[ -z "$SUPABASE_CLIENT_KEY" ]]; then
    echo "Missing required env var: SUPABASE_PUBLIC_API_KEY (or SUPABASE_PUBLISHABLE_API_KEY)" >&2
    exit 1
  fi
  STRIPE_MERCHANT_DISPLAY_NAME="${STRIPE_MERCHANT_DISPLAY_NAME:-Aveli}"
  DEFINE_ARGS+=(
    --dart-define=API_BASE_URL="$API_BASE_URL"
    --dart-define=SUPABASE_URL="$SUPABASE_URL"
    --dart-define=SUPABASE_PUBLIC_API_KEY="$SUPABASE_CLIENT_KEY"
    --dart-define=STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY"
    --dart-define=STRIPE_MERCHANT_DISPLAY_NAME="$STRIPE_MERCHANT_DISPLAY_NAME"
    --dart-define=FRONTEND_URL="${FRONTEND_URL:-https://app.aveli.app}"
    --dart-define=OAUTH_REDIRECT_WEB="$OAUTH_REDIRECT_WEB"
  )

  if [[ -n "${SUBSCRIPTIONS_ENABLED:-}" ]]; then
    DEFINE_ARGS+=(--dart-define=SUBSCRIPTIONS_ENABLED="$SUBSCRIPTIONS_ENABLED")
  fi
  if [[ -n "${IMAGE_LOGGING:-}" ]]; then
    DEFINE_ARGS+=(--dart-define=IMAGE_LOGGING="$IMAGE_LOGGING")
  fi
fi

# Always inject a per-deploy build number for cache busting / diagnostics.
DEFINE_ARGS+=(--dart-define=BUILD_NUMBER="$BUILD_NUMBER")

if [[ ! -f "$FRONTEND_ROOT/pubspec.yaml" ]]; then
  echo "pubspec.yaml not found at $FRONTEND_ROOT/pubspec.yaml" >&2
  exit 1
fi

flutter clean
flutter pub get

# Prevent deploy surprises: remove both the canonical output and any stale
# root-level build dir from older scripts so only frontend/build/web can exist.
rm -rf "$BUILD_DIR"
if [[ "$LEGACY_ROOT_BUILD_DIR" != "$BUILD_DIR" && -d "$LEGACY_ROOT_BUILD_DIR" ]]; then
  rm -rf "$LEGACY_ROOT_BUILD_DIR"
fi

flutter build web --release --no-wasm-dry-run \
  --output="$BUILD_DIR" \
  --pwa-strategy=none \
  --build-number="$BUILD_NUMBER" \
  "${DEFINE_ARGS[@]}"

# Flutter may emit an empty placeholder `flutter_service_worker.js` even when
# PWA support is disabled. Overwrite it with our "kill" SW so older client
# registrations can update and uninstall themselves.
cp "$FRONTEND_ROOT/web/flutter_service_worker.js" "$BUILD_DIR/flutter_service_worker.js"

# NOTE: We intentionally KEEP /flutter_service_worker.js, but ship a "kill"
# service worker that unregisters itself and clears caches. This is required to
# free existing users from older cached Flutter SW bundles without manual cache
# clearing.

# Also strip SW registration from generated runtime files.
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python is required to post-process Flutter Web artifacts (python3 or python not found)." >&2
  exit 1
fi

"$PYTHON_BIN" <<'PY'
import os
from pathlib import Path

build_dir = Path(os.environ["BUILD_DIR"]).resolve()

if not build_dir.exists():
    raise SystemExit(f"Build directory missing: {build_dir}")
targets = [build_dir / "flutter_bootstrap.js", build_dir / "flutter.js"]

def _stub_load_service_worker(js: str) -> str:
    """
    Make service worker registration impossible even if some bootstrap code
    passes serviceWorkerSettings.

    We do not want new SW registrations at all, but we still ship a "kill"
    SW script at /flutter_service_worker.js so previously-registered SWs can
    update and unregister themselves.
    """

    marker = "loadServiceWorker("
    start = js.find(marker)
    # Skip call sites like ".loadServiceWorker(" (we only want the method
    # definition inside flutter.js / flutter_bootstrap.js).
    while start != -1 and start > 0 and js[start - 1] == ".":
        start = js.find(marker, start + 1)

    if start == -1:
        return js

    end_marker = "async _getNewServiceWorker"
    end = js.find(end_marker, start)
    if end == -1:
        return js

    return js[:start] + "loadServiceWorker(e){return Promise.resolve();}" + js[end:]

for path in targets:
    if not path.exists():
        continue

    original = path.read_text(encoding="utf-8")
    updated = _stub_load_service_worker(original)

    if updated != original:
        path.write_text(updated, encoding="utf-8")
PY

# Ensure SPA routing works on static hosting.
printf '/*  /index.html  200\n' > "$BUILD_DIR/_redirects"

if [[ ! -f "$BUILD_DIR/main.dart.js" ]]; then
  echo "Build output missing expected bundle: $BUILD_DIR/main.dart.js" >&2
  exit 1
fi

echo "PROD WEB BUILD DONE ($BUILD_DIR)"
