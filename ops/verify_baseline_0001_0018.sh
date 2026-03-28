#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_REPO_PYTHON" "repo python"
MANIFEST_PATH="$ROOT_DIR/backend/supabase/baseline_slots.lock.json"
BASELINE_DIR="$ROOT_DIR/backend/supabase/baseline_slots"
CHECKER="$ROOT_DIR/ops/check_baseline_slots.py"
AUTH_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_auth_substrate.sql"
STORAGE_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_storage_substrate.sql"
BACKEND_DIR="$ROOT_DIR/backend"
BACKEND_URL="http://127.0.0.1:8080"

PROTECTED_SLOTS=(
  "0001_foundation_auth_profiles.sql"
  "0002_access_teacher_roles.sql"
  "0003_courses_core.sql"
  "0004_enrollments_core.sql"
  "0005_lessons_core.sql"
  "0006_access_grants_core.sql"
  "0007_media_objects_core.sql"
  "0008_lesson_media_core.sql"
  "0009_courses_enrolled_read_alignment.sql"
  "0010_media_assets_core.sql"
  "0011_lesson_media_asset_bridge.sql"
  "0012_runtime_media_lesson_projection_core.sql"
  "0013_runtime_media_lesson_sync_core.sql"
  "0014_runtime_media_context_sync_core.sql"
  "0015_runtime_media_lesson_backfill_core.sql"
  "0016_live_schema_media_home_player_alignment.sql"
  "0017_auth_commerce_runtime_blockers.sql"
  "0018_external_fk_cleanup.sql"
)

resolve_db_url() {
  if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
    printf '%s\n' "$SUPABASE_DB_URL"
    return 0
  fi
  if [[ -n "${DATABASE_URL:-}" ]]; then
    printf '%s\n' "$DATABASE_URL"
    return 0
  fi
  if command -v supabase >/dev/null 2>&1; then
    local status_env
    status_env="$(supabase status -o env)"
    local db_url
    db_url="$(printf '%s\n' "$status_env" | awk -F= '/^DB_URL=/{gsub(/"/,"",$2); print $2}')"
    if [[ -n "$db_url" ]]; then
      printf '%s\n' "$db_url"
      return 0
    fi
  fi
  return 1
}

derive_urls() {
  "$AVELI_REPO_PYTHON" - <<'PY' "$1" "$2"
from urllib.parse import urlparse, urlunparse
import sys

base_url = sys.argv[1]
scratch_db = sys.argv[2]
parsed = urlparse(base_url)
maintenance = parsed._replace(path="/postgres")
scratch = parsed._replace(path=f"/{scratch_db}")
print(urlunparse(maintenance))
print(urlunparse(scratch))
PY
}

db_host() {
  "$AVELI_REPO_PYTHON" - <<'PY' "$1"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
print(parsed.hostname or "")
PY
}

is_local_host() {
  local host="$1"
  host="${host,,}"
  case "$host" in
    localhost|127.0.0.1|::1|db|host.docker.internal) return 0 ;;
    *) return 1 ;;
  esac
}

port_8080_busy() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn '( sport = :8080 )' | tail -n +2 | grep -q .
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  return 1
}

http_status() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 2 "$1" || true
}

wait_for_200() {
  local url="$1"
  local label="$2"
  local code=""
  for _ in $(seq 1 60); do
    if [[ -n "${BACKEND_PID:-}" ]] && ! kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
      echo "baseline-replay-0018: backend exited before ${label} became healthy" >&2
      tail -n 80 "$BACKEND_LOG" >&2 || true
      exit 1
    fi
    code="$(http_status "$url")"
    if [[ "$code" == "200" ]]; then
      echo "baseline-replay-0018: ${label}=200"
      return 0
    fi
    sleep 1
  done
  echo "baseline-replay-0018: expected ${label}=200, got ${code:-none}" >&2
  tail -n 80 "$BACKEND_LOG" >&2 || true
  exit 1
}

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi

  if [[ "${BASELINE_KEEP_SCRATCH_DB:-0}" == "1" ]]; then
    echo "baseline-replay-0018: keeping scratch_db=${SCRATCH_DB:-unknown}"
  elif [[ -n "${MAINTENANCE_URL:-}" && -n "${SCRATCH_DB:-}" ]]; then
    psql "$MAINTENANCE_URL" -X -q -c "drop database if exists \"$SCRATCH_DB\" with (force);" >/dev/null 2>&1 || true
  fi

  if [[ -n "${BACKEND_LOG:-}" && -f "${BACKEND_LOG:-}" && "${BASELINE_KEEP_BACKEND_LOG:-0}" != "1" ]]; then
    rm -f "$BACKEND_LOG"
  fi
}
trap cleanup EXIT

if [[ -f "$ROOT_DIR/ops/env_load.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/ops/env_load.sh" >/dev/null 2>&1
fi

DB_URL="$(resolve_db_url || true)"
if [[ -z "$DB_URL" ]]; then
  echo "baseline-replay-0018: unable to resolve DB URL from SUPABASE_DB_URL, DATABASE_URL, or supabase status" >&2
  exit 2
fi

"$AVELI_REPO_PYTHON" "$CHECKER" --manifest "$MANIFEST_PATH" --baseline-dir "$BASELINE_DIR"

SCRATCH_DB="baseline_replay_0018_$(date +%Y%m%d_%H%M%S)_$$"
mapfile -t DERIVED_URLS < <(derive_urls "$DB_URL" "$SCRATCH_DB")
MAINTENANCE_URL="${DERIVED_URLS[0]}"
SCRATCH_URL="${DERIVED_URLS[1]}"

echo "baseline-replay-0018: scratch_db=$SCRATCH_DB"
echo "baseline-replay-0018: scratch_url=$SCRATCH_URL"
echo "baseline-replay-0018: replay_order=auth_substrate -> storage_substrate -> 0001-0018"

psql "$MAINTENANCE_URL" -X -q -v ON_ERROR_STOP=1 -c "drop database if exists \"$SCRATCH_DB\" with (force);"
psql "$MAINTENANCE_URL" -X -q -v ON_ERROR_STOP=1 -c "create database \"$SCRATCH_DB\";"
psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$AUTH_SUBSTRATE_SQL" >/dev/null
echo "baseline-replay-0018: applied minimal auth substrate"
psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$STORAGE_SUBSTRATE_SQL" >/dev/null
echo "baseline-replay-0018: applied minimal storage substrate"

for slot in "${PROTECTED_SLOTS[@]}"; do
  psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$BASELINE_DIR/$slot"
  echo "baseline-replay-0018: applied $slot"
done

external_fk_rows="$(psql "$SCRATCH_URL" -X -qAt -F '|' <<'SQL'
select
  con.conname,
  src_ns.nspname || '.' || src.relname,
  tgt_ns.nspname || '.' || tgt.relname
from pg_constraint con
join pg_class src on src.oid = con.conrelid
join pg_namespace src_ns on src_ns.oid = src.relnamespace
join pg_class tgt on tgt.oid = con.confrelid
join pg_namespace tgt_ns on tgt_ns.oid = tgt.relnamespace
where con.contype = 'f'
  and src_ns.nspname = 'app'
  and tgt_ns.nspname in ('auth', 'storage')
order by 1;
SQL
)"

if [[ -n "$external_fk_rows" ]]; then
  echo "baseline-replay-0018: external FK cleanup failed" >&2
  printf '%s\n' "$external_fk_rows" >&2
  exit 1
fi

profiles_fk_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_constraint where conname = 'profiles_user_id_fkey';")"
memberships_fk_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_constraint where conname = 'memberships_user_id_fkey';")"

[[ "$profiles_fk_count" == "0" ]] || {
  echo "baseline-replay-0018: profiles_user_id_fkey still exists" >&2
  exit 1
}
[[ "$memberships_fk_count" == "0" ]] || {
  echo "baseline-replay-0018: memberships_user_id_fkey still exists" >&2
  exit 1
}

SCRATCH_HOST="$(db_host "$SCRATCH_URL")"
if ! is_local_host "$SCRATCH_HOST"; then
  echo "baseline-replay-0018: scratch DB host is not local (${SCRATCH_HOST})" >&2
  exit 1
fi

if port_8080_busy; then
  echo "baseline-replay-0018: port 8080 is already in use; stop the running backend and retry" >&2
  exit 1
fi

BACKEND_LOG="$(mktemp /tmp/aveli_baseline_replay_0018_backend_XXXXXX.log)"
(
  cd "$BACKEND_DIR"
  # shellcheck source=/dev/null
  source ../ops/env_load.sh >/dev/null 2>&1
  export DATABASE_URL="$SCRATCH_URL"
  export SUPABASE_DB_URL="$SCRATCH_URL"
  export MCP_MODE="local"
  unset FLY_APP_NAME K_SERVICE
  poetry run uvicorn app.main:app --host 127.0.0.1 --port 8080
) >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

wait_for_200 "$BACKEND_URL/healthz" "/healthz"
wait_for_200 "$BACKEND_URL/readyz" "/readyz"
wait_for_200 "$BACKEND_URL/mcp/logs" "/mcp/logs"
wait_for_200 "$BACKEND_URL/mcp/verification" "/mcp/verification"
wait_for_200 "$BACKEND_URL/mcp/media-control-plane" "/mcp/media-control-plane"
wait_for_200 "$BACKEND_URL/mcp/domain-observability" "/mcp/domain-observability"

worker_payload="$(curl -sS -X POST "$BACKEND_URL/mcp/logs" \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_worker_health","arguments":{}}}')"

"$AVELI_REPO_PYTHON" - <<'PY' "$worker_payload"
import json
import sys

payload = json.loads(sys.argv[1])
worker_health = payload["result"]["data"]["worker_health"]
bad = {
    name: info.get("status")
    for name, info in worker_health.items()
    if info.get("status") != "ok"
}
if bad:
    raise SystemExit(f"baseline-replay-0018: worker health failure: {bad}")
print("baseline-replay-0018: worker_health=ok")
PY

echo "baseline-replay-0018: PASS"
