#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${REPORT_PATH:-${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md}"

log() {
  echo "==> $1"
}

append_report() {
  if [[ -f "$REPORT_PATH" ]]; then
    cat >>"$REPORT_PATH"
  fi
}

overall_status=0

env_status="SKIP"
remote_status="SKIP"
local_reset_status="SKIP"
backend_tests_status="SKIP"
backend_smoke_status="SKIP"
flutter_tests_status="SKIP"
landing_tests_status="SKIP"
landing_build_status="SKIP"
backend_deps_ready=false

ensure_backend_deps() {
  if ! $backend_deps_ready; then
    (cd "${ROOT_DIR}/backend" && poetry install --no-interaction --no-root)
    backend_deps_ready=true
  fi
}

log "Env validation"
if "${ROOT_DIR}/ops/env_validate.sh"; then
  env_status="PASS"
else
  env_status="FAIL"
  overall_status=1
fi

log "Remote DB verify (read-only)"
set +e
"${ROOT_DIR}/ops/db_verify_remote_readonly.sh"
remote_exit=$?
set -e
if [[ $remote_exit -eq 0 ]]; then
  remote_status="PASS"
elif [[ $remote_exit -eq 2 ]]; then
  remote_status="SKIP"
else
  remote_status="FAIL"
  overall_status=1
fi

log "Local DB reset (optional)"
if [[ "${LOCAL_DB_RESET:-}" == "1" || "${AUTO_LOCAL_RESET:-}" == "1" ]]; then
  set +e
  "${ROOT_DIR}/ops/db_repair_local_reset.sh"
  reset_exit=$?
  set -e
  if [[ $reset_exit -eq 0 ]]; then
    local_reset_status="PASS"
  else
    local_reset_status="FAIL"
    overall_status=1
  fi
else
  local_reset_status="SKIP"
fi

log "Backend tests"
if command -v poetry >/dev/null 2>&1; then
  ensure_backend_deps
  if (cd "${ROOT_DIR}/backend" && REQUIRE_DB_TESTS=1 poetry run pytest); then
    backend_tests_status="PASS"
  else
    backend_tests_status="FAIL"
    overall_status=1
  fi
else
  echo "poetry not found; skipping backend tests" >&2
  backend_tests_status="FAIL"
  overall_status=1
fi

log "Backend smoke"
backend_port="${BACKEND_PORT:-8080}"
backend_url="${QA_API_BASE_URL:-http://127.0.0.1:${backend_port}}"
backend_pid=""

start_backend=false
if [[ "${SKIP_BACKEND_START:-}" != "1" ]]; then
  start_backend=true
fi

if $start_backend; then
  if command -v poetry >/dev/null 2>&1; then
    ensure_backend_deps
    (cd "${ROOT_DIR}/backend" && poetry run uvicorn app.main:app --host 127.0.0.1 --port "${backend_port}") &
    backend_pid=$!
  else
    echo "poetry not found; cannot start backend" >&2
    backend_pid=""
  fi

  if [[ -n "$backend_pid" ]]; then
    trap 'kill "$backend_pid" >/dev/null 2>&1 || true' EXIT
    if command -v curl >/dev/null 2>&1; then
      for _ in {1..30}; do
        if curl -sf "${backend_url}/readyz" >/dev/null; then
          break
        fi
        sleep 1
      done
    else
      python3 - <<PY
import time
import urllib.request

url = "${backend_url}/readyz"
for _ in range(30):
    try:
        with urllib.request.urlopen(url, timeout=2) as resp:
            if resp.status == 200:
                break
    except Exception:
        time.sleep(1)
PY
    fi
  fi
fi

if command -v poetry >/dev/null 2>&1; then
  if (cd "${ROOT_DIR}/backend" && CI=true QA_API_BASE_URL="$backend_url" poetry run python scripts/qa_teacher_smoke.py); then
    backend_smoke_status="PASS"
  else
    backend_smoke_status="FAIL"
    overall_status=1
  fi
else
  echo "poetry not found; skipping backend smoke" >&2
  backend_smoke_status="FAIL"
  overall_status=1
fi

if [[ -n "$backend_pid" ]]; then
  kill "$backend_pid" >/dev/null 2>&1 || true
  backend_pid=""
fi

log "Flutter tests"
if command -v flutter >/dev/null 2>&1; then
  if (cd "${ROOT_DIR}/frontend" && flutter test); then
    flutter_device="${FLUTTER_DEVICE:-chrome}"
    if (cd "${ROOT_DIR}/frontend" && flutter test integration_test -d "${flutter_device}"); then
      flutter_tests_status="PASS"
    else
      flutter_tests_status="FAIL"
      overall_status=1
    fi
  else
    flutter_tests_status="FAIL"
    overall_status=1
  fi
else
  echo "flutter not found; skipping Flutter tests" >&2
  flutter_tests_status="FAIL"
  overall_status=1
fi

log "Landing tests/build"
if command -v npm >/dev/null 2>&1; then
  if [[ ! -d "${ROOT_DIR}/frontend/landing/node_modules" ]]; then
    (cd "${ROOT_DIR}/frontend/landing" && npm ci)
  fi
  if (cd "${ROOT_DIR}/frontend/landing" && npm test); then
    landing_tests_status="PASS"
  else
    landing_tests_status="FAIL"
    overall_status=1
  fi
  if (cd "${ROOT_DIR}/frontend/landing" && npm run build); then
    landing_build_status="PASS"
  else
    landing_build_status="FAIL"
    overall_status=1
  fi
else
  echo "npm not found; skipping landing tests/build" >&2
  landing_tests_status="FAIL"
  landing_build_status="FAIL"
  overall_status=1
fi

append_report <<TXT

## Verification Run (ops/verify_all.sh)
- Env validation: ${env_status}
- Remote DB verify: ${remote_status}
- Local DB reset: ${local_reset_status}
- Backend tests: ${backend_tests_status}
- Backend smoke: ${backend_smoke_status}
- Flutter tests: ${flutter_tests_status}
- Landing tests: ${landing_tests_status}
- Landing build: ${landing_build_status}
TXT

exit "$overall_status"
