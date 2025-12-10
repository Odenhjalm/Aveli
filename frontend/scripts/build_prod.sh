#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/web"

cd "$PROJECT_ROOT"
export BUILD_DIR

for var in SUPABASE_URL SUPABASE_PUBLISHABLE_API_KEY STRIPE_PUBLISHABLE_KEY STRIPE_MERCHANT_DISPLAY_NAME; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required env var: $var" >&2
    exit 1
  fi
done

if [[ ! -f "pubspec.yaml" ]]; then
  echo "pubspec.yaml not found next to scripts/build_prod.sh" >&2
  exit 1
fi

flutter clean
flutter pub get

rm -rf "$BUILD_DIR"

flutter build web --release --no-wasm-dry-run \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://aveli.fly.dev \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_API_KEY="$SUPABASE_PUBLISHABLE_API_KEY" \
  --dart-define=STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY" \
  --dart-define=STRIPE_MERCHANT_DISPLAY_NAME="$STRIPE_MERCHANT_DISPLAY_NAME" \
  --dart-define=FRONTEND_URL=https://app.aveli.app \
  --dart-define=OAUTH_REDIRECT_WEB=https://app.aveli.app/login-callback

# Remove service worker artifacts to avoid stale caching in production.
rm -f "$BUILD_DIR/flutter_service_worker.js"
rm -f "$BUILD_DIR/version.json"

# Also strip SW registration from generated runtime files.
python <<'PY'
import os
import re
from pathlib import Path

build_dir = Path(os.environ["BUILD_DIR"]).resolve()

if not build_dir.exists():
    raise SystemExit(f"Build directory missing: {build_dir}")
targets = [build_dir / "flutter_bootstrap.js", build_dir / "flutter.js"]

service_worker_block = re.compile(
    r'''if\s*\(\s*["']serviceWorker["']\s*in\s*navigator\s*\)\s*\{\s*
        window\.addEventListener\(\s*["']load["']\s*,\s*function\s*\(\s*\)\s*\{\s*
        navigator\.serviceWorker\.register\([^;]*flutter_service_worker\.js[^;]*;
        \s*\}\s*\)\s*;
        \s*\}''',
    flags=re.IGNORECASE | re.DOTALL | re.VERBOSE,
)

for path in targets:
    if not path.exists():
        continue

    original = path.read_text(encoding="utf-8")
    updated = original

    updated, _ = re.subn(
        r"serviceWorkerSettings\s*:\s*\{[^{}]*\}",
        "serviceWorkerSettings:null",
        updated,
        flags=re.DOTALL,
    )
    updated, _ = service_worker_block.subn("/* service worker registration removed */", updated)
    updated, _ = re.subn(
        r"navigator\.serviceWorker\.register\([^;]*flutter_service_worker\.js[^;]*;",
        "/* service worker registration removed */",
        updated,
        flags=re.IGNORECASE | re.DOTALL,
    )

    updated, _ = re.subn(
        r"loadServiceWorker\([^)]*\)\{.*?\}(?=async _getNewServiceWorker)",
        "loadServiceWorker(e){return Promise.resolve();}",
        updated,
        flags=re.DOTALL,
    )

    updated, _ = re.subn(
        r"let\{serviceWorker:r,\.\.\.t\}=e\|\|{},n=new g,s=new h;s\.setTrustedTypesPolicy\(n\.policy\),await s\.loadServiceWorker\(r\)\.catch\(.*?\);let a=new v;",
        "let{serviceWorker:r,...t}=e||{},n=new g;let a=new v;",
        updated,
        flags=re.DOTALL,
    )

    if updated != original:
        path.write_text(updated, encoding="utf-8")
PY

# Ensure SPA routing works on static hosting.
printf '/*  /index.html  200\n' > "$BUILD_DIR/_redirects"

echo "PROD WEB BUILD DONE (frontend/build/web)"
