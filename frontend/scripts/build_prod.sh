#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FRONTEND_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$FRONTEND_ROOT/.." && pwd -P)"
CANONICAL_BUILD_DIR="$FRONTEND_ROOT/build/web"
export CANONICAL_BUILD_DIR

cd "$FRONTEND_ROOT"
if [[ "$(pwd -P)" != "$FRONTEND_ROOT" ]]; then
  echo "Refusing build: working directory must be $FRONTEND_ROOT" >&2
  exit 1
fi

remove_noncanonical_build_dirs() {
  local dir
  while IFS= read -r dir; do
    local resolved
    resolved="$(cd "$dir" && pwd -P)"
    if [[ "$resolved" != "$CANONICAL_BUILD_DIR" ]]; then
      echo "Removing non-canonical build directory: $resolved" >&2
      rm -rf "$resolved"
    fi
  done < <(find "$REPO_ROOT" -type d -path '*/build/web' -print)
}

assert_single_canonical_build_dir() {
  local expected="$CANONICAL_BUILD_DIR"
  local canonical_count=0
  local dir
  local resolved

  mapfile -t build_dirs < <(find "$REPO_ROOT" -type d -path '*/build/web' -print | sort)

  if [[ "${#build_dirs[@]}" -eq 0 ]]; then
    echo "Build integrity check failed: no build/web directory exists." >&2
    exit 1
  fi

  for dir in "${build_dirs[@]}"; do
    resolved="$(cd "$dir" && pwd -P)"
    if [[ "$resolved" == "$expected" ]]; then
      canonical_count=$((canonical_count + 1))
      continue
    fi
    echo "Build integrity check failed: unexpected build directory $resolved" >&2
    exit 1
  done

  if [[ "$canonical_count" -ne 1 ]]; then
    echo "Build integrity check failed: expected exactly one canonical build dir at $expected" >&2
    exit 1
  fi
}

normalize_url() {
  local url="$1"
  echo "${url%/}"
}

: "${API_BASE_URL:?Missing API_BASE_URL}"
: "${STRIPE_PUBLISHABLE_KEY:?Missing STRIPE_PUBLISHABLE_KEY}"
: "${OAUTH_REDIRECT_WEB:?Missing OAUTH_REDIRECT_WEB}"

API_BASE_URL="$(normalize_url "$API_BASE_URL")"
OAUTH_REDIRECT_WEB="$(normalize_url "$OAUTH_REDIRECT_WEB")"
FRONTEND_URL="$(normalize_url "${FRONTEND_URL:-https://app.aveli.app}")"

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)$$}"
if [[ -z "${BUILD_COMMIT_SHA:-}" ]]; then
  if ! BUILD_COMMIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    echo "Unable to resolve BUILD_COMMIT_SHA from git." >&2
    exit 1
  fi
fi

STRIPE_MERCHANT_DISPLAY_NAME="${STRIPE_MERCHANT_DISPLAY_NAME:-Aveli}"

echo "Build working directory: $(pwd -P)" >&2
echo "Canonical web output directory: $CANONICAL_BUILD_DIR" >&2

DEFINE_ARGS=(
  --dart-define=BUILD_NUMBER="$BUILD_NUMBER"
  --dart-define=BUILD_COMMIT_SHA="$BUILD_COMMIT_SHA"
  --dart-define=API_BASE_URL="$API_BASE_URL"
  --dart-define=STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY"
  --dart-define=STRIPE_MERCHANT_DISPLAY_NAME="$STRIPE_MERCHANT_DISPLAY_NAME"
  --dart-define=FRONTEND_URL="$FRONTEND_URL"
  --dart-define=OAUTH_REDIRECT_WEB="$OAUTH_REDIRECT_WEB"
)

if [[ -n "${SUBSCRIPTIONS_ENABLED:-}" ]]; then
  DEFINE_ARGS+=(--dart-define=SUBSCRIPTIONS_ENABLED="$SUBSCRIPTIONS_ENABLED")
fi
if [[ -n "${IMAGE_LOGGING:-}" ]]; then
  DEFINE_ARGS+=(--dart-define=IMAGE_LOGGING="$IMAGE_LOGGING")
fi

if [[ ! -f "$FRONTEND_ROOT/pubspec.yaml" ]]; then
  echo "pubspec.yaml not found at $FRONTEND_ROOT/pubspec.yaml" >&2
  exit 1
fi

remove_noncanonical_build_dirs
rm -rf "$CANONICAL_BUILD_DIR"

flutter clean
flutter pub get

flutter build web --release --no-wasm-dry-run \
  --output="$CANONICAL_BUILD_DIR" \
  --pwa-strategy=none \
  --build-number="$BUILD_NUMBER" \
  "${DEFINE_ARGS[@]}"

cp "$FRONTEND_ROOT/web/flutter_service_worker.js" "$CANONICAL_BUILD_DIR/flutter_service_worker.js"

stub_load_service_worker() {
  local target="$1"
  local tmp="${target}.tmp.$$"

  if [[ ! -f "$target" ]]; then
    return 0
  fi

  awk '
    BEGIN {
      marker = "loadServiceWorker("
      end_marker = "async _getNewServiceWorker"
      replacement = "loadServiceWorker(e){return Promise.resolve();}"
      sep = ""
    }
    {
      text = text sep $0
      sep = "\n"
    }
    END {
      start = index(text, marker)
      while (start > 1 && substr(text, start - 1, 1) == ".") {
        next_start = index(substr(text, start + 1), marker)
        if (next_start == 0) {
          start = 0
          break
        }
        start += next_start
      }

      if (start == 0) {
        printf "%s", text
        exit
      }

      rel_end = index(substr(text, start), end_marker)
      if (rel_end == 0) {
        printf "%s", text
        exit
      }

      end = start + rel_end - 1
      printf "%s%s%s", substr(text, 1, start - 1), replacement, substr(text, end)
    }
  ' "$target" >"$tmp"
  mv "$tmp" "$target"
}

stub_load_service_worker "$CANONICAL_BUILD_DIR/flutter_bootstrap.js"
stub_load_service_worker "$CANONICAL_BUILD_DIR/flutter.js"

printf '/*  /index.html  200\n' > "$CANONICAL_BUILD_DIR/_redirects"
printf '%s\n' "$BUILD_COMMIT_SHA" > "$CANONICAL_BUILD_DIR/.build_commit"
printf '%s\n' "$BUILD_NUMBER" > "$CANONICAL_BUILD_DIR/.build_number"

if [[ ! -f "$CANONICAL_BUILD_DIR/main.dart.js" ]]; then
  echo "Build output missing expected bundle: $CANONICAL_BUILD_DIR/main.dart.js" >&2
  exit 1
fi

remove_noncanonical_build_dirs
assert_single_canonical_build_dir

RESOLVED_OUTPUT_PATH="$(cd "$CANONICAL_BUILD_DIR" && pwd -P)"
if [[ "$RESOLVED_OUTPUT_PATH" != "$CANONICAL_BUILD_DIR" ]]; then
  echo "Build integrity check failed: output path mismatch (resolved $RESOLVED_OUTPUT_PATH)." >&2
  exit 1
fi

echo "Resolved output path: $RESOLVED_OUTPUT_PATH"
