#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${REPORT_PATH:-${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md}"
POETRY_INSTALL_ARGS="${POETRY_INSTALL_ARGS:---no-root}"

APP_ENV_VALUE=""
APP_ENV_MODE="unknown"
load_app_env() {
  if [[ -f "${ROOT_DIR}/backend/.env" ]]; then
    APP_ENV_VALUE="$(python3 - <<'PY' "${ROOT_DIR}/backend/.env"
import sys

path = sys.argv[1]
value = ""
for raw_line in open(path, "r", encoding="utf-8"):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, val = line.split("=", 1)
    if key.strip() == "APP_ENV":
        val = val.strip()
        if val and val[0] == val[-1] and val[0] in ("\"", "'"):
            val = val[1:-1]
        value = val
        break
print(value)
PY
)"
  fi

  local normalized="${APP_ENV_VALUE,,}"
  if [[ "$normalized" == "prod" || "$normalized" == "production" || "$normalized" == "live" ]]; then
    APP_ENV_MODE="prod"
  elif [[ -n "$normalized" ]]; then
    APP_ENV_MODE="dev"
  else
    APP_ENV_MODE="dev"
  fi
}

log() {
  echo "==> $1"
}

append_report() {
  if [[ -f "$REPORT_PATH" ]]; then
    cat >>"$REPORT_PATH"
  fi
}

overall_status=0

env_guard_status="SKIP"
env_status="SKIP"
env_contract_status="SKIP"
stripe_verify_status="SKIP"
supabase_verify_status="SKIP"
remote_status="SKIP"
local_reset_status="SKIP"
backend_tests_status="SKIP"
backend_smoke_status="SKIP"
flutter_tests_status="SKIP"
landing_tests_status="SKIP"
landing_build_status="SKIP"
backend_deps_ready=false

load_app_env
log "Verification mode: ${APP_ENV_VALUE:-unknown} (${APP_ENV_MODE})"
if [[ "$APP_ENV_MODE" == "prod" ]]; then
  log "Required checks: Env guard, Env validation, Env contract, Stripe verify, Supabase verify, Remote DB verify, Backend tests, Backend smoke, Flutter tests, Landing tests, Landing build"
else
  log "Required checks: Env guard, Env validation, Env contract, Stripe verify, Supabase verify"
fi

ensure_backend_deps() {
  if $backend_deps_ready; then
    return 0
  fi
  if (cd "${ROOT_DIR}/backend" && poetry install --no-interaction ${POETRY_INSTALL_ARGS}); then
    backend_deps_ready=true
    return 0
  fi
  backend_deps_ready=false
  return 1
}

detect_flutter_device() {
  if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
    echo "${FLUTTER_DEVICE}"
    return 0
  fi
  if ! command -v flutter >/dev/null 2>&1; then
    return 1
  fi
  local devices_json
  devices_json=$(flutter devices --machine 2>/dev/null || true)
  if [[ -z "$devices_json" ]]; then
    return 1
  fi
  DEVICES_JSON="$devices_json" python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("DEVICES_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

ids = [d.get("id") for d in data if d.get("id")]
for pref in ("chrome", "linux"):
    for dev_id in ids:
        if dev_id == pref:
            print(dev_id)
            sys.exit(0)
if ids:
    print(ids[0])
    sys.exit(0)
sys.exit(1)
PY
}

log "Env guard (backend/.env not tracked)"
if "${ROOT_DIR}/ops/ci_guard_env.sh"; then
  env_guard_status="PASS"
else
  env_guard_status="FAIL"
  overall_status=1
fi

log "Env validation"
if "${ROOT_DIR}/ops/env_validate.sh"; then
  env_status="PASS"
else
  env_status="FAIL"
  overall_status=1
fi

log "Env contract check"
if python3 "${ROOT_DIR}/backend/scripts/env_contract_check.py"; then
  env_contract_status="PASS"
else
  env_contract_status="FAIL"
  overall_status=1
fi

log "Stripe test-mode verification"
if command -v poetry >/dev/null 2>&1; then
  if ensure_backend_deps; then
    if (cd "${ROOT_DIR}/backend" && poetry run python scripts/stripe_verify_test_mode.py); then
      stripe_verify_status="PASS"
    else
      stripe_verify_status="FAIL"
      overall_status=1
    fi
  else
    echo "poetry install failed; skipping Stripe verification" >&2
    stripe_verify_status="FAIL"
    overall_status=1
  fi
else
  echo "poetry not found; skipping Stripe verification" >&2
  stripe_verify_status="FAIL"
  overall_status=1
fi

log "Supabase env verification"
if command -v poetry >/dev/null 2>&1; then
  if ensure_backend_deps; then
    if (cd "${ROOT_DIR}/backend" && poetry run python scripts/supabase_verify_env.py); then
      supabase_verify_status="PASS"
    else
      supabase_verify_status="FAIL"
      overall_status=1
    fi
  else
    echo "poetry install failed; skipping Supabase verification" >&2
    supabase_verify_status="FAIL"
    overall_status=1
  fi
else
  echo "poetry not found; skipping Supabase verification" >&2
  supabase_verify_status="FAIL"
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
  if [[ "$APP_ENV_MODE" == "prod" ]]; then
    overall_status=1
  fi
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
  if ensure_backend_deps; then
    if (cd "${ROOT_DIR}/backend" && REQUIRE_DB_TESTS=1 poetry run pytest); then
      backend_tests_status="PASS"
    else
      backend_tests_status="FAIL"
      overall_status=1
    fi
  else
    echo "poetry install failed; skipping backend tests" >&2
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
    if ensure_backend_deps; then
      (cd "${ROOT_DIR}/backend" && poetry run uvicorn app.main:app --host 127.0.0.1 --port "${backend_port}") &
      backend_pid=$!
    else
      echo "poetry install failed; cannot start backend" >&2
      backend_pid=""
    fi
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
  if ! ensure_backend_deps; then
    echo "poetry install failed; skipping backend smoke" >&2
    backend_smoke_status="FAIL"
    overall_status=1
  else
    if [[ "$APP_ENV_MODE" == "prod" ]]; then
      smoke_ci="true"
    else
      smoke_ci=""
    fi
    if [[ -n "$smoke_ci" ]]; then
      if (cd "${ROOT_DIR}/backend" && CI="$smoke_ci" QA_API_BASE_URL="$backend_url" poetry run python scripts/qa_teacher_smoke.py); then
        backend_smoke_status="PASS"
      else
        backend_smoke_status="FAIL"
        overall_status=1
      fi
    else
      if (cd "${ROOT_DIR}/backend" && QA_API_BASE_URL="$backend_url" poetry run python scripts/qa_teacher_smoke.py); then
        backend_smoke_status="PASS"
      else
        backend_smoke_status="FAIL"
        overall_status=1
      fi
    fi
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
  if (cd "${ROOT_DIR}/frontend" && flutter test --dart-define=DOTENV_FILE=.env); then
    if [[ "$APP_ENV_MODE" != "prod" && "${RUN_FLUTTER_INTEGRATION:-}" != "1" ]]; then
      echo "Skipping Flutter integration tests in ${APP_ENV_MODE} mode (set RUN_FLUTTER_INTEGRATION=1 to run)" >&2
      flutter_tests_status="SKIP"
    else
      flutter_device="$(detect_flutter_device || true)"
      if [[ -z "$flutter_device" ]]; then
        echo "No Flutter device found for integration tests" >&2
        flutter_tests_status="FAIL"
        overall_status=1
      elif (cd "${ROOT_DIR}/frontend" && flutter test integration_test -d "${flutter_device}" --dart-define=DOTENV_FILE=.env); then
        flutter_tests_status="PASS"
      else
        flutter_tests_status="FAIL"
        overall_status=1
      fi
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
  if (cd "${ROOT_DIR}/frontend/landing" && npm ci); then
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
    echo "npm ci failed; skipping landing tests/build" >&2
    landing_tests_status="FAIL"
    landing_build_status="FAIL"
    overall_status=1
  fi
else
  echo "npm not found; skipping landing tests/build" >&2
  landing_tests_status="FAIL"
  landing_build_status="FAIL"
  overall_status=1
fi

skipped_checks=()
[[ "$env_guard_status" == "SKIP" ]] && skipped_checks+=("Env guard")
[[ "$env_status" == "SKIP" ]] && skipped_checks+=("Env validation")
[[ "$env_contract_status" == "SKIP" ]] && skipped_checks+=("Env contract")
[[ "$stripe_verify_status" == "SKIP" ]] && skipped_checks+=("Stripe verify")
[[ "$supabase_verify_status" == "SKIP" ]] && skipped_checks+=("Supabase verify")
[[ "$remote_status" == "SKIP" ]] && skipped_checks+=("Remote DB verify")
[[ "$local_reset_status" == "SKIP" ]] && skipped_checks+=("Local DB reset")
[[ "$backend_tests_status" == "SKIP" ]] && skipped_checks+=("Backend tests")
[[ "$backend_smoke_status" == "SKIP" ]] && skipped_checks+=("Backend smoke")
[[ "$flutter_tests_status" == "SKIP" ]] && skipped_checks+=("Flutter tests")
[[ "$landing_tests_status" == "SKIP" ]] && skipped_checks+=("Landing tests")
[[ "$landing_build_status" == "SKIP" ]] && skipped_checks+=("Landing build")
if [[ ${#skipped_checks[@]} -eq 0 ]]; then
  skipped_summary="none"
else
  skipped_summary="$(IFS=', '; echo "${skipped_checks[*]}")"
fi
log "Skipped checks: ${skipped_summary}"

append_report <<TXT

## Verification Run (ops/verify_all.sh)
- APP_ENV: ${APP_ENV_VALUE:-unknown} (${APP_ENV_MODE})
- Skipped checks: ${skipped_summary}
- Env guard (backend/.env not tracked): ${env_guard_status}
- Env validation: ${env_status}
- Env contract check: ${env_contract_status}
- Stripe test verification: ${stripe_verify_status}
- Supabase env verification: ${supabase_verify_status}
- Remote DB verify: ${remote_status}
- Local DB reset: ${local_reset_status}
- Backend tests: ${backend_tests_status}
- Backend smoke: ${backend_smoke_status}
- Flutter tests: ${flutter_tests_status}
- Landing tests: ${landing_tests_status}
- Landing build: ${landing_build_status}
TXT

exit "$overall_status"
