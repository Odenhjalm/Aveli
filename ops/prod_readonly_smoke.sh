#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_REPO_PYTHON" "repo python"
API_BASE_URL="${API_BASE_URL:-https://aveli.fly.dev}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Prod read-only smoke target: ${API_BASE_URL}"

fetch_json() {
  local path="$1"
  local output="$2"
  curl -fsS --max-time 20 "${API_BASE_URL}${path}" -o "${output}"
}

check_preflight() {
  local headers_file="$1"
  local status_line
  status_line="$(head -n 1 "${headers_file}" | tr -d '\r')"
  case "${status_line}" in
    *" 200 "*|*" 204 "*) ;;
    *)
      echo "Preflight failed: ${status_line}" >&2
      return 1
      ;;
  esac
  tr -d '\r' < "${headers_file}" | grep -iq '^access-control-allow-origin: https://app\.aveli\.app$'
}

echo "==> GET /healthz"
fetch_json "/healthz" "${TMP_DIR}/healthz.json"

echo "==> GET /readyz"
fetch_json "/readyz" "${TMP_DIR}/readyz.json"

echo "==> GET /courses?limit=3"
fetch_json "/courses?limit=3" "${TMP_DIR}/courses.json"

echo "==> GET /landing/popular-courses"
fetch_json "/landing/popular-courses" "${TMP_DIR}/popular.json"

echo "==> GET /landing/intro-courses"
fetch_json "/landing/intro-courses" "${TMP_DIR}/intro.json"

echo "==> OPTIONS /courses/me"
curl -fsS -D "${TMP_DIR}/preflight.headers" -o /dev/null \
  -X OPTIONS \
  -H 'Origin: https://app.aveli.app' \
  -H 'Access-Control-Request-Method: GET' \
  --max-time 20 \
  "${API_BASE_URL}/courses/me"
check_preflight "${TMP_DIR}/preflight.headers"

echo "==> GET /courses?limit=3 with gzip"
curl -fsS -D "${TMP_DIR}/gzip.headers" -o /dev/null \
  -H 'Accept-Encoding: gzip' \
  --max-time 20 \
  "${API_BASE_URL}/courses?limit=3"
tr -d '\r' < "${TMP_DIR}/gzip.headers" | grep -iq '^content-encoding: gzip$'

FIRST_COVER_URL="$(
"$AVELI_REPO_PYTHON" - "${TMP_DIR}/healthz.json" "${TMP_DIR}/readyz.json" "${TMP_DIR}/courses.json" "${TMP_DIR}/popular.json" "${TMP_DIR}/intro.json" <<'PY'
import json
import sys

health = json.load(open(sys.argv[1], "r", encoding="utf-8"))
ready = json.load(open(sys.argv[2], "r", encoding="utf-8"))
courses = json.load(open(sys.argv[3], "r", encoding="utf-8"))
popular = json.load(open(sys.argv[4], "r", encoding="utf-8"))
intro = json.load(open(sys.argv[5], "r", encoding="utf-8"))

assert health.get("ok") is True, health
assert ready.get("ok") is True, ready
assert ready.get("database") == "ready", ready

course_items = courses.get("items")
assert isinstance(course_items, list), courses
popular_items = popular.get("items")
assert isinstance(popular_items, list), popular
intro_items = intro.get("items")
assert isinstance(intro_items, list), intro

if course_items:
    first = course_items[0]
    assert first.get("title"), first
    assert first.get("slug"), first
    assert first.get("is_published") is True, first
    cover = first.get("cover_url") or ""
    print(cover)
else:
    print("")
PY
)"

if [[ -n "${FIRST_COVER_URL}" ]]; then
  NORMALIZED_COVER_URL="$(
  "$AVELI_REPO_PYTHON" - "${FIRST_COVER_URL}" <<'PY'
import sys
from urllib.parse import quote, urlsplit, urlunsplit

raw = sys.argv[1]
parts = urlsplit(raw)
path = quote(parts.path, safe="/:@")
query = quote(parts.query, safe="=&?/:@")
print(urlunsplit((parts.scheme, parts.netloc, path, query, parts.fragment)))
PY
  )"
  echo "==> Range probe first public cover"
  curl -fsS -D "${TMP_DIR}/cover.headers" -o /dev/null \
    -H 'Range: bytes=0-0' \
    --max-time 20 \
    "${NORMALIZED_COVER_URL}"
  if ! tr -d '\r' < "${TMP_DIR}/cover.headers" | grep -iq '^content-type: image/'; then
    echo "Cover probe did not return an image content-type" >&2
    exit 1
  fi
fi

echo "==> Smoke subset passed"
