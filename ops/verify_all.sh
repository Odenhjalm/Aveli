#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_DIR="$ROOT_DIR/ops"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
LANDING_DIR="$ROOT_DIR/frontend/landing"
REPORT_PATH="${REPORT_PATH:-$ROOT_DIR/docs/verify/LAUNCH_READINESS_REPORT.md}"

# Default: install backend project (so "import app" works without PYTHONPATH hacks).
POETRY_INSTALL_ARGS="${POETRY_INSTALL_ARGS:-}"

resolve_stripe_selector() {
  if [[ -n "${STRIPE_KEYSET:-}" || -n "${APP_ENV_MODE:-}" ]]; then
    return 0
  fi

  if [[ -n "${BACKEND_ENV_OVERLAY_FILE:-}" ]]; then
    local app_env_raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
    local app_env_lower="${app_env_raw,,}"
    if [[ "$app_env_lower" != "prod" && "$app_env_lower" != "production" && "$app_env_lower" != "live" ]]; then
      export APP_ENV_MODE="test"
    fi
  fi
}


# ---- Env loading (single source of truth for loading) ----
# This prints:
#   ==> Backend env file: <path>
#   ==> Backend env overlay: <path|none>
# and exports vars deterministically (baseline then overlay).
resolve_stripe_selector
# shellcheck source=/dev/null
source "$OPS_DIR/env_load.sh"

APP_ENV_VALUE="${APP_ENV:-${ENVIRONMENT:-${ENV:-development}}}"
APP_ENV_LOWER="${APP_ENV_VALUE,,}"
APP_ENV_STAGE="dev"
if [[ "$APP_ENV_LOWER" == "prod" || "$APP_ENV_LOWER" == "production" || "$APP_ENV_LOWER" == "live" ]]; then
  APP_ENV_STAGE="live"
fi

stripe_selector="${STRIPE_KEYSET:-${APP_ENV_MODE:-}}"
if [[ -z "$stripe_selector" ]]; then
  stripe_selector="unknown"
fi

log() { echo "==> $1"; }

# ---- Status bookkeeping ----
overall_status=0

env_guard_status="SKIP"
env_status="SKIP"
env_contract_status="SKIP"
poetry_install_status="SKIP"
stripe_verify_status="SKIP"
supabase_verify_status="SKIP"
remote_status="SKIP"
backend_tests_status="SKIP"
backend_smoke_status="SKIP"
flutter_unit_status="SKIP"
flutter_integration_status="SKIP"
landing_deps_status="SKIP"
landing_tests_status="SKIP"
landing_build_status="SKIP"

# ---- Helpers ----
append_report() {
  # Report is opt-in.
  if [[ "${VERIFY_WRITE_REPORT:-0}" != "1" ]]; then
    echo "Report: SKIPPED (set VERIFY_WRITE_REPORT=1 to write LAUNCH_READINESS_REPORT.md)"
    return 0
  fi
  mkdir -p "$(dirname "$REPORT_PATH")"
  cat >>"$REPORT_PATH"
}

run_or_fail() {
  local label="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "verify_all: FAIL ($label)" >&2
  exit 1
}

run_step() {
  local label="$1"
  shift
  if "$@"; then
    echo "PASS: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  return 1
}

# Pick a free localhost port for smoke (avoids “address already in use”).
pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
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
  devices_json="$(flutter devices --machine 2>/dev/null || true)"
  [[ -n "$devices_json" ]] || return 1

  DEVICES_JSON="$devices_json" python3 - <<'PY'
import json, os, sys
raw = os.environ.get("DEVICES_JSON","")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

ids = [d.get("id") for d in data if d.get("id")]
# Prefer android emulator/device first for integration tests
for pref in ("emulator-5554",):
    if pref in ids:
        print(pref); sys.exit(0)

# otherwise pick any android if present
for dev in data:
    if dev.get("targetPlatform","").startswith("android") and dev.get("id"):
        print(dev["id"]); sys.exit(0)

# fallback to linux/chrome (not useful for integration_test usually, but keep deterministic)
for pref in ("linux", "chrome"):
    if pref in ids:
        print(pref); sys.exit(0)

if ids:
    print(ids[0]); sys.exit(0)
sys.exit(1)
PY
}

# ---- Start ----
log "verify_all (APP_ENV=${APP_ENV_VALUE} / stripe=${stripe_selector})"
log "Required checks: env guard, env validate, env contract, stripe verify, supabase verify, remote DB verify, backend tests, backend smoke, flutter unit, landing test+build"
if [[ "${RUN_FLUTTER_INTEGRATION:-0}" == "1" ]]; then
  log "Integration: Flutter integration tests enabled"
else
  log "Integration: Flutter integration tests SKIP by default (set RUN_FLUTTER_INTEGRATION=1)"
fi

# 1) Guardrails
log "Env guard (backend/.env not tracked)"
if run_step "env guard" bash "$OPS_DIR/ci_guard_env.sh"; then
  env_guard_status="PASS"
else
  env_guard_status="FAIL"
  overall_status=1
fi

# 2) Env validation (FAIL FAST)
log "Env validation"
run_or_fail "env validation" bash "$OPS_DIR/env_validate.sh"
env_status="PASS"

# Reload env after validation to reapply active Stripe selection.
export AVELI_ENV_LOADED=0
# shellcheck source=/dev/null
source "$OPS_DIR/env_load.sh"

# 3) Poetry install (backend deps)
log "Poetry install"
if command -v poetry >/dev/null 2>&1; then
  if (cd "$BACKEND_DIR" && poetry install --no-interaction $POETRY_INSTALL_ARGS); then
    poetry_install_status="PASS"
  else
    poetry_install_status="FAIL"
    echo "verify_all: FAIL (poetry install)" >&2
    exit 1
  fi
else
  poetry_install_status="FAIL"
  echo "verify_all: FAIL (poetry missing)" >&2
  exit 1
fi

# 4) Env contract (FAIL FAST)
log "Env contract check"
run_or_fail "env contract" bash -c "cd '$BACKEND_DIR' && poetry run python scripts/env_contract_check.py"
env_contract_status="PASS"

# 5) Stripe verify
log "Stripe verification"
if (cd "$BACKEND_DIR" && poetry run python scripts/stripe_verify_test_mode.py); then
  stripe_verify_status="PASS"
else
  stripe_verify_status="FAIL"
  echo "verify_all: FAIL (stripe verify)" >&2
  exit 1
fi

# 6) Supabase env verify
log "Supabase env verification"
if (cd "$BACKEND_DIR" && poetry run python scripts/supabase_verify_env.py); then
  supabase_verify_status="PASS"
else
  supabase_verify_status="FAIL"
  echo "verify_all: FAIL (supabase verify)" >&2
  exit 1
fi

# 7) Remote DB verify (blocking in prod; non-blocking in dev but recorded)
log "Remote DB verify (read-only)"
set +e
bash "$BACKEND_DIR/scripts/db_verify_remote_readonly.sh"
remote_exit=$?
set -e
if [[ $remote_exit -eq 0 ]]; then
  remote_status="PASS"
elif [[ $remote_exit -eq 2 ]]; then
  remote_status="WARN"
  echo "WARN: remote db verify reported warnings (non-blocking; see output above)" >&2
else
  if [[ "$APP_ENV_STAGE" == "live" ]]; then
    remote_status="FAIL"
    echo "verify_all: FAIL (remote db verify)" >&2
    exit 1
  else
    remote_status="WARN"
    echo "WARN: remote db verify failed in dev (non-blocking)" >&2
  fi
fi

# 8) Backend tests
log "Backend tests"
# Force non-prod mode for tests so Stripe test keys are allowed.
if (cd "$BACKEND_DIR" && APP_ENV=development poetry run pytest); then
  backend_tests_status="PASS"
else
  backend_tests_status="FAIL"
  echo "verify_all: FAIL (backend tests)" >&2
  exit 1
fi

# 9) Backend smoke (start server on free port + run QA smoke)
log "Backend smoke"
backend_port="${BACKEND_PORT:-$(pick_free_port)}"
backend_url="${QA_API_BASE_URL:-http://127.0.0.1:${backend_port}}"
backend_pid=""

( cd "$BACKEND_DIR"
  poetry run uvicorn app.main:app --host 127.0.0.1 --port "${backend_port}" >/tmp/backend_uvicorn.log 2>&1 &
  echo $! >/tmp/backend_uvicorn.pid
)
backend_pid="$(cat /tmp/backend_uvicorn.pid || true)"
trap '[[ -n "${backend_pid:-}" ]] && kill "$backend_pid" >/dev/null 2>&1 || true' EXIT

# wait for ready
ready=false
for _ in {1..30}; do
  if curl -sf "${backend_url}/readyz" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != "true" ]]; then
  echo "verify_all: FAIL (backend smoke: not ready) (see /tmp/backend_uvicorn.log)" >&2
  exit 1
fi

if (cd "$BACKEND_DIR" && QA_BASE_URL="$backend_url" QA_API_BASE_URL="$backend_url" poetry run python scripts/qa_teacher_smoke.py); then
  backend_smoke_status="PASS"
else
  backend_smoke_status="FAIL"
  echo "verify_all: FAIL (backend smoke) (see /tmp/backend_uvicorn.log)" >&2
  exit 1
fi

kill "$backend_pid" >/dev/null 2>&1 || true
backend_pid=""

# 10) Flutter unit tests
log "Flutter unit tests"
if command -v flutter >/dev/null 2>&1; then
  if (cd "$FRONTEND_DIR" && flutter test); then
    flutter_unit_status="PASS"
  else
    flutter_unit_status="FAIL"
    echo "verify_all: FAIL (flutter unit tests)" >&2
    exit 1
  fi
else
  flutter_unit_status="SKIP"
  echo "WARN: flutter not installed; skipping flutter tests" >&2
fi

# 11) Flutter integration tests (opt-in)
log "Flutter integration tests"
if [[ "${RUN_FLUTTER_INTEGRATION:-0}" == "1" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    integration_dir="$FRONTEND_DIR/integration_test"
    if [[ -d "$integration_dir" ]]; then
      shopt -s nullglob
      integration_tests=("$integration_dir"/*_test.dart)
      shopt -u nullglob
    else
      integration_tests=()
    fi

    if [[ ${#integration_tests[@]} -eq 0 ]]; then
      echo "WARN: no Flutter integration tests found; skipping" >&2
      flutter_integration_status="SKIP"
    else
      for test_file in "${integration_tests[@]}"; do
        echo "==> Flutter integration: integration_test/$(basename "$test_file")"
        if !(cd "$FRONTEND_DIR" && timeout 15m flutter test "integration_test/$(basename "$test_file")" -d linux); then
          flutter_integration_status="FAIL"
          echo "verify_all: FAIL (flutter integration tests)" >&2
          exit 1
        fi
      done
      flutter_integration_status="PASS"
    fi
  else
    flutter_integration_status="FAIL"
    echo "verify_all: FAIL (flutter missing but RUN_FLUTTER_INTEGRATION=1)" >&2
    exit 1
  fi
else
  flutter_integration_status="SKIP"
fi

# 12) Landing tests/build
log "Landing deps/tests/build"
if [[ -d "$LANDING_DIR" ]]; then
  if command -v npm >/dev/null 2>&1; then
    if (cd "$LANDING_DIR" && npm ci); then
      landing_deps_status="PASS"
    else
      landing_deps_status="FAIL"
      echo "verify_all: FAIL (landing deps)" >&2
      exit 1
    fi

    if (cd "$LANDING_DIR" && npm test); then
      landing_tests_status="PASS"
    else
      landing_tests_status="FAIL"
      echo "verify_all: FAIL (landing tests)" >&2
      exit 1
    fi

    if (cd "$LANDING_DIR" && npm run build); then
      landing_build_status="PASS"
    else
      landing_build_status="FAIL"
      echo "verify_all: FAIL (landing build)" >&2
      exit 1
    fi
  else
    landing_deps_status="FAIL"
    echo "verify_all: FAIL (npm missing)" >&2
    exit 1
  fi
else
  landing_deps_status="SKIP"
  landing_tests_status="SKIP"
  landing_build_status="SKIP"
fi

# ---- Report (opt-in) ----
append_report <<TXT

## Verification Run (ops/verify_all.sh)
- APP_ENV: ${APP_ENV_VALUE} (${APP_ENV_STAGE})
- Stripe mode: ${stripe_selector}
- Backend env file: ${BACKEND_ENV_FILE}
- Backend env overlay: ${BACKEND_ENV_OVERLAY_FILE:-none}
- Env guard: ${env_guard_status}
- Env validation: ${env_status}
- Poetry install: ${poetry_install_status}
- Env contract: ${env_contract_status}
- Stripe verify: ${stripe_verify_status}
- Supabase verify: ${supabase_verify_status}
- Remote DB verify: ${remote_status}
- Backend tests: ${backend_tests_status}
- Backend smoke: ${backend_smoke_status}
- Flutter unit tests: ${flutter_unit_status}
- Flutter integration tests: ${flutter_integration_status}
- Landing deps: ${landing_deps_status}
- Landing tests: ${landing_tests_status}
- Landing build: ${landing_build_status}
TXT

echo "verify_all: PASS"
exit 0
