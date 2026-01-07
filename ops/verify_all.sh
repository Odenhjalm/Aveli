#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${ROOT_DIR}/docs/verify/LAUNCH_READINESS_REPORT.md"
BACKEND_DIR="${ROOT_DIR}/backend"
LANDING_DIR="${ROOT_DIR}/frontend/landing"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-"${BACKEND_DIR}/.env"}"
BACKEND_ENV_OVERLAY_FILE="${BACKEND_ENV_OVERLAY_FILE:-""}"

append_report() {
  if [[ -f "$REPORT_PATH" ]]; then
    cat >>"$REPORT_PATH"
  fi
}

load_env_file() {
  local env_file="$1"
  if [[ -z "$env_file" ]]; then
    return 0
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: backend env file missing at ${env_file}" >&2
    return 1
  fi
  eval "$(
    python3 - <<'PY' "$env_file"
import os
import shlex
import sys

path = sys.argv[1]
for raw_line in open(path, "r", encoding="utf-8"):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if value and value[0] == value[-1] and value[0] in ("\"", "'"):
        value = value[1:-1]
    if not key:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
  )"
}

load_backend_env() {
  local status=0
  if ! load_env_file "$BACKEND_ENV_FILE"; then
    status=1
  fi
  if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
    if ! load_env_file "$BACKEND_ENV_OVERLAY_FILE"; then
      status=1
    fi
  fi
  return $status
}

normalize_env() {
  local raw="$1"
  raw="${raw,,}"
  case "$raw" in
    prod|production|live) echo "production" ;;
    *) echo "development" ;;
  esac
}

results=()
record_result() {
  results+=("$1: $2")
}

run_step() {
  local label="$1"
  shift
  if "$@"; then
    record_result "$label" "PASS"
    return 0
  fi
  record_result "$label" "FAIL"
  return 1
}

run_step_nonblocking() {
  local label="$1"
  shift
  if "$@"; then
    record_result "$label" "PASS"
    return 0
  fi
  record_result "$label" "FAIL (non-blocking)"
  return 0
}

overall_status=0

export BACKEND_ENV_FILE BACKEND_ENV_OVERLAY_FILE
if ! load_backend_env; then
  overall_status=1
fi

APP_ENV_VALUE="${APP_ENV:-${ENV:-${ENVIRONMENT:-development}}}"
ENV_MODE="$(normalize_env "$APP_ENV_VALUE")"

printf "==> verify_all (APP_ENV=%s)\n" "$APP_ENV_VALUE"
printf "==> Backend env file: %s\n" "$BACKEND_ENV_FILE"
if [[ -n "$BACKEND_ENV_OVERLAY_FILE" ]]; then
  printf "==> Backend env overlay: %s\n" "$BACKEND_ENV_OVERLAY_FILE"
else
  printf "==> Backend env overlay: none\n"
fi

# Guardrails
if ! run_step "Env guard (backend/.env not tracked)" bash "$ROOT_DIR/ops/ci_guard_env.sh"; then
  overall_status=1
fi

# Env validation
if ! run_step "Env validation" bash "$ROOT_DIR/ops/env_validate.sh"; then
  overall_status=1
fi

# Load backend env for subsequent steps
if ! load_backend_env; then
  overall_status=1
fi

# Backend deps
if command -v poetry >/dev/null 2>&1; then
  if ! run_step "Poetry install" bash -c "cd '$BACKEND_DIR' && poetry install"; then
    overall_status=1
  fi
else
  record_result "Poetry install" "FAIL (poetry missing)"
  overall_status=1
fi

# Env contract
if ! run_step "Env contract check" bash -c "cd '$BACKEND_DIR' && poetry run python scripts/env_contract_check.py"; then
  overall_status=1
fi

# Stripe verify
if ! run_step "Stripe test/live verification" bash -c "cd '$BACKEND_DIR' && poetry run python scripts/stripe_verify_test_mode.py"; then
  overall_status=1
fi

# Supabase verify
if ! run_step "Supabase env verification" bash -c "cd '$BACKEND_DIR' && poetry run python scripts/supabase_verify_env.py"; then
  overall_status=1
fi

# Remote DB verify
if [[ "$ENV_MODE" == "production" ]]; then
  if ! run_step "Remote DB verify (read-only, blocking)" bash "$BACKEND_DIR/scripts/db_verify_remote_readonly.sh"; then
    overall_status=1
  fi
else
  run_step_nonblocking "Remote DB verify (read-only, non-blocking)" bash "$BACKEND_DIR/scripts/db_verify_remote_readonly.sh"
fi

# Local DB reset (optional)
record_result "Local DB reset" "SKIP"

# Backend tests
if ! run_step "Backend tests" bash -c "cd '$BACKEND_DIR' && poetry run pytest"; then
  overall_status=1
fi

run_backend_smoke() {
  local backend_port="${PORT:-8080}"
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not available" >&2
    return 1
  fi
  if ! command -v poetry >/dev/null 2>&1; then
    echo "poetry not available" >&2
    return 1
  fi

  (
    cd "$BACKEND_DIR"
    poetry run uvicorn app.main:app --host 127.0.0.1 --port "${backend_port}" >/tmp/backend_uvicorn.log 2>&1 &
    echo $! >/tmp/backend_uvicorn.pid
  )
  local backend_pid
  backend_pid="$(cat /tmp/backend_uvicorn.pid)"
  trap 'if [[ -n "${backend_pid:-}" ]]; then kill "${backend_pid}" >/dev/null 2>&1 || true; fi' RETURN

  local ready=false
  for _ in {1..20}; do
    if curl -sf "http://127.0.0.1:${backend_port}/healthz" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "$ready" != "true" ]]; then
    echo "backend not ready" >&2
    return 1
  fi

  cd "$BACKEND_DIR"
  poetry run python scripts/qa_teacher_smoke.py --base-url "http://127.0.0.1:${backend_port}"
}

if ! run_step "Backend smoke" run_backend_smoke; then
  overall_status=1
fi

# Flutter tests
if command -v flutter >/dev/null 2>&1; then
  if ! run_step "Flutter tests" bash -c "cd '$ROOT_DIR/frontend' && flutter test"; then
    overall_status=1
  fi
  if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
    if ! run_step "Flutter integration tests" bash -c "cd '$ROOT_DIR/frontend' && flutter test integration_test -d ${FLUTTER_DEVICE}"; then
      overall_status=1
    fi
  else
    record_result "Flutter integration tests" "SKIP (FLUTTER_DEVICE not set)"
  fi
else
  record_result "Flutter tests" "SKIP (flutter not installed)"
  record_result "Flutter integration tests" "SKIP (flutter not installed)"
fi

# Landing tests/build
if [[ -d "$LANDING_DIR" ]]; then
  if command -v npm >/dev/null 2>&1; then
    if ! run_step "Landing deps" bash -c "cd '$LANDING_DIR' && npm install"; then
      overall_status=1
    fi
    if ! run_step "Landing tests" bash -c "cd '$LANDING_DIR' && npm run test"; then
      overall_status=1
    fi
    if ! run_step "Landing build" bash -c "cd '$LANDING_DIR' && npm run build"; then
      overall_status=1
    fi
  else
    record_result "Landing deps" "SKIP (npm not installed)"
    record_result "Landing tests" "SKIP (npm not installed)"
    record_result "Landing build" "SKIP (npm not installed)"
  fi
else
  record_result "Landing deps" "SKIP (landing missing)"
  record_result "Landing tests" "SKIP (landing missing)"
  record_result "Landing build" "SKIP (landing missing)"
fi

append_report <<TXT

## Verification Run (ops/verify_all.sh)
- Mode: ${APP_ENV_VALUE}
- Backend env file: ${BACKEND_ENV_FILE}
- Backend env overlay: ${BACKEND_ENV_OVERLAY_FILE:-none}
$(printf -- '- %s\n' "${results[@]}")
TXT

if [[ "$overall_status" -ne 0 ]]; then
  echo "verify_all: FAIL" >&2
  exit 1
fi

echo "verify_all: PASS"
