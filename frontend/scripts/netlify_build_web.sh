#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FRONTEND_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$FRONTEND_ROOT/.." && pwd -P)"
CANONICAL_BUILD_DIR="$FRONTEND_ROOT/build/web"
EXPECTED_MAIN_BRANCH="main"
EXPECTED_PROD_API_BASE_URL="https://aveli.fly.dev"
KNOWN_MAIN_MARKER="Ta bort video"

cd "$FRONTEND_ROOT"
if [[ "$(pwd -P)" != "$FRONTEND_ROOT" ]]; then
  echo "Refusing Netlify build: working directory must be $FRONTEND_ROOT" >&2
  exit 1
fi

# Netlify deployment invariants (non-negotiable):
# - Base directory: frontend
# - Build command: bash scripts/netlify_build_web.sh
# - Publish directory: frontend/build/web
# - Production deploys only from main
# - Branch deploys are previews only and must never ship production artifacts

: "${FLUTTER_API_BASE_URL:?Missing FLUTTER_API_BASE_URL}"
: "${FLUTTER_SUPABASE_URL:?Missing FLUTTER_SUPABASE_URL}"
: "${FLUTTER_STRIPE_PUBLISHABLE_KEY:?Missing FLUTTER_STRIPE_PUBLISHABLE_KEY}"
: "${FLUTTER_OAUTH_REDIRECT_WEB:?Missing FLUTTER_OAUTH_REDIRECT_WEB}"

FLUTTER_SUPABASE_CLIENT_KEY="${FLUTTER_SUPABASE_PUBLISHABLE_API_KEY:-${FLUTTER_SUPABASE_PUBLIC_API_KEY:-${FLUTTER_SUPABASE_ANON_KEY:-}}}"
if [[ -z "$FLUTTER_SUPABASE_CLIENT_KEY" ]]; then
  echo "Missing Supabase client key. Set FLUTTER_SUPABASE_PUBLISHABLE_API_KEY (preferred) or FLUTTER_SUPABASE_PUBLIC_API_KEY/FLUTTER_SUPABASE_ANON_KEY." >&2
  exit 1
fi

normalize_url() {
  local url="$1"
  echo "${url%/}"
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

NETLIFY_CONTEXT="${CONTEXT:-${DEPLOY_CONTEXT:-}}"
NETLIFY_BRANCH="${BRANCH:-${HEAD:-}}"

if [[ -z "$NETLIFY_CONTEXT" ]]; then
  echo "Missing Netlify CONTEXT/DEPLOY_CONTEXT. Refusing ambiguous build." >&2
  exit 1
fi

FLUTTER_API_BASE_URL="$(normalize_url "$FLUTTER_API_BASE_URL")"
FLUTTER_SUPABASE_URL="$(normalize_url "$FLUTTER_SUPABASE_URL")"
FLUTTER_OAUTH_REDIRECT_WEB="$(normalize_url "$FLUTTER_OAUTH_REDIRECT_WEB")"

if [[ "$NETLIFY_CONTEXT" == "production" ]]; then
  if [[ "$NETLIFY_BRANCH" != "$EXPECTED_MAIN_BRANCH" ]]; then
    echo "Refusing production build: branch must be $EXPECTED_MAIN_BRANCH (got ${NETLIFY_BRANCH:-<unset>})." >&2
    exit 1
  fi
  if [[ "$FLUTTER_API_BASE_URL" != "$EXPECTED_PROD_API_BASE_URL" ]]; then
    echo "Refusing production build: FLUTTER_API_BASE_URL must be $EXPECTED_PROD_API_BASE_URL (got $FLUTTER_API_BASE_URL)." >&2
    exit 1
  fi
  if [[ -n "${PULL_REQUEST:-}" && "${PULL_REQUEST}" != "false" ]]; then
    echo "Refusing production build: pull request context cannot deploy to production (PULL_REQUEST=${PULL_REQUEST})." >&2
    exit 1
  fi
else
  if [[ "$FLUTTER_API_BASE_URL" == "$EXPECTED_PROD_API_BASE_URL" ]]; then
    echo "Refusing non-production build: production API URL may only be used in production context." >&2
    exit 1
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required for branch/commit provenance checks." >&2
  exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Repository metadata not available; cannot verify commit provenance." >&2
  exit 1
fi

HEAD_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if [[ -n "${COMMIT_REF:-}" && "${COMMIT_REF}" != "$HEAD_COMMIT" ]]; then
  echo "Refusing build: COMMIT_REF ($COMMIT_REF) does not match checked out HEAD ($HEAD_COMMIT)." >&2
  exit 1
fi

MAIN_COMMIT=""
if [[ "$NETLIFY_CONTEXT" == "production" ]]; then
  if ! git -C "$REPO_ROOT" fetch --no-tags --depth=1 origin "$EXPECTED_MAIN_BRANCH"; then
    echo "Refusing production build: failed to fetch origin/$EXPECTED_MAIN_BRANCH for provenance check." >&2
    exit 1
  fi
  MAIN_COMMIT="$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)"
  if [[ "$HEAD_COMMIT" != "$MAIN_COMMIT" ]]; then
    echo "Refusing production build: HEAD ($HEAD_COMMIT) is not current origin/$EXPECTED_MAIN_BRANCH ($MAIN_COMMIT)." >&2
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
    local archive_path="${cache_dir}/${archive}"
    local url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}"
    curl -fsSL "${url}" -o "${archive_path}"

    if ! tar -xf "${archive_path}" -C "${cache_dir}" >/dev/null 2>&1; then
      local py=""
      if command -v python3 >/dev/null 2>&1; then
        py="python3"
      elif command -v python >/dev/null 2>&1; then
        py="python"
      else
        echo "Failed to extract Flutter archive and no python interpreter is available." >&2
        exit 1
      fi

      rm -rf "${flutter_root}"
      "${py}" - <<PY
import tarfile
from pathlib import Path

archive = Path("${archive_path}")
dest = Path("${cache_dir}")

with tarfile.open(archive, "r:*") as tf:
    tf.extractall(dest)
PY
    fi

    rm -f "${archive_path}"
  fi

  export PATH="${flutter_root}/bin:${PATH}"
}

install_flutter

flutter config --no-analytics >/dev/null 2>&1 || true

export API_BASE_URL="$FLUTTER_API_BASE_URL"
export SUPABASE_URL="$FLUTTER_SUPABASE_URL"
export SUPABASE_PUBLISHABLE_API_KEY="$FLUTTER_SUPABASE_CLIENT_KEY"
export SUPABASE_PUBLIC_API_KEY="$FLUTTER_SUPABASE_CLIENT_KEY"
export SUPABASE_ANON_KEY="$FLUTTER_SUPABASE_CLIENT_KEY"
export STRIPE_PUBLISHABLE_KEY="$FLUTTER_STRIPE_PUBLISHABLE_KEY"
export OAUTH_REDIRECT_WEB="$FLUTTER_OAUTH_REDIRECT_WEB"

export STRIPE_MERCHANT_DISPLAY_NAME="${FLUTTER_STRIPE_MERCHANT_DISPLAY_NAME:-Aveli}"
export SUBSCRIPTIONS_ENABLED="${FLUTTER_SUBSCRIPTIONS_ENABLED:-}"
export IMAGE_LOGGING="${FLUTTER_IMAGE_LOGGING:-}"
export FRONTEND_URL="${FLUTTER_FRONTEND_URL:-https://app.aveli.app}"
export BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)${RANDOM}}"
export BUILD_COMMIT_SHA="$HEAD_COMMIT"

echo "Netlify context: $NETLIFY_CONTEXT" >&2
echo "Netlify branch: ${NETLIFY_BRANCH:-<unset>}" >&2
echo "Netlify commit: $HEAD_COMMIT" >&2
echo "Flutter BUILD_NUMBER=$BUILD_NUMBER" >&2

"$SCRIPT_DIR/build_prod.sh"

if [[ ! -f "$CANONICAL_BUILD_DIR/main.dart.js" ]]; then
  echo "Build integrity check failed: missing $CANONICAL_BUILD_DIR/main.dart.js" >&2
  exit 1
fi

if ! grep -Fq "$API_BASE_URL" "$CANONICAL_BUILD_DIR/main.dart.js"; then
  echo "Build integrity check failed: API_BASE_URL=$API_BASE_URL not found in main.dart.js" >&2
  exit 1
fi

if ! grep -Fq "$KNOWN_MAIN_MARKER" "$CANONICAL_BUILD_DIR/main.dart.js"; then
  echo "Build integrity check failed: stable marker '$KNOWN_MAIN_MARKER' not found in main.dart.js" >&2
  exit 1
fi

if grep -Fq "api.aveli.app" "$CANONICAL_BUILD_DIR/main.dart.js"; then
  echo "Build integrity check failed: legacy api.aveli.app found in main.dart.js" >&2
  exit 1
fi

BUILD_COMMIT_FILE="$CANONICAL_BUILD_DIR/.build_commit"
if [[ ! -f "$BUILD_COMMIT_FILE" ]]; then
  echo "Build integrity check failed: missing commit stamp $BUILD_COMMIT_FILE" >&2
  exit 1
fi

ARTIFACT_COMMIT="$(tr -d '\r\n' < "$BUILD_COMMIT_FILE")"
if [[ "$ARTIFACT_COMMIT" != "$HEAD_COMMIT" ]]; then
  echo "Build integrity check failed: artifact commit ($ARTIFACT_COMMIT) != checked-out commit ($HEAD_COMMIT)." >&2
  exit 1
fi

if [[ "$NETLIFY_CONTEXT" == "production" && "$ARTIFACT_COMMIT" != "$MAIN_COMMIT" ]]; then
  echo "Build integrity check failed: artifact commit ($ARTIFACT_COMMIT) != current origin/$EXPECTED_MAIN_BRANCH ($MAIN_COMMIT)." >&2
  exit 1
fi

assert_single_canonical_build_dir

RESOLVED_OUTPUT_PATH="$(cd "$CANONICAL_BUILD_DIR" && pwd -P)"
if [[ "$RESOLVED_OUTPUT_PATH" != "$CANONICAL_BUILD_DIR" ]]; then
  echo "Build integrity check failed: resolved output path mismatch ($RESOLVED_OUTPUT_PATH)." >&2
  exit 1
fi

echo "Resolved output path: $RESOLVED_OUTPUT_PATH"
