#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATIONS_DIR="${REPO_ROOT}/supabase/migrations"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-${REPO_ROOT}/docs/ops/SUPABASE_ALLOWLIST.txt}"

load_env_file() {
  if [[ -n "${DB_ENV_FILE:-}" && -f "${DB_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${DB_ENV_FILE}"
    set +a
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

supabase_cli_available() {
  command -v supabase >/dev/null 2>&1
}

parse_db_url() {
  local url="$1"
  python3 - "$url" <<'PY'
from urllib.parse import urlparse
import sys
url = sys.argv[1]
parsed = urlparse(url)
host = parsed.hostname or ""
port = parsed.port or ""
dbname = (parsed.path or "").lstrip("/")
print(f"DB_HOST={host}")
print(f"DB_PORT={port}")
print(f"DB_NAME={dbname}")
PY
}

mask_db_url() {
  local url="$1"
  python3 - "$url" <<'PY'
from urllib.parse import urlparse
import sys
url = sys.argv[1]
parsed = urlparse(url)
netloc = parsed.hostname or ""
if parsed.port:
  netloc = f"{netloc}:{parsed.port}"
masked = parsed._replace(netloc=netloc).geturl()
print(masked)
PY
}

resolve_supabase_status() {
  if ! supabase_cli_available; then
    return 1
  fi
  if [[ ! -f "${REPO_ROOT}/supabase/config.toml" ]]; then
    return 1
  fi
  local status_json
  if ! status_json=$(supabase status --output json --workdir "${REPO_ROOT}" 2>/dev/null); then
    return 1
  fi
  STATUS_JSON=\"${status_json}\" python3 - <<'PY'
import json
import os

raw = os.environ.get("STATUS_JSON", "")
start = raw.find("{")
end = raw.rfind("}")
if start == -1 or end == -1 or end <= start:
    raise SystemExit(1)
payload = json.loads(raw[start:end + 1])

def pick(*keys):
    for key in keys:
        if key in payload and payload[key]:
            return payload[key]
    return None

api_url = pick("API_URL", "api_url")
db_url = pick("DB_URL", "db_url")
anon_key = pick("ANON_KEY", "anon_key")
service_role_key = pick("SERVICE_ROLE_KEY", "service_role_key")
jwt_secret = pick("JWT_SECRET", "jwt_secret")

if api_url:
    print(f"SUPABASE_URL={api_url}")
if db_url:
    print(f"SUPABASE_DB_URL={db_url}")
if anon_key:
    print(f"SUPABASE_ANON_KEY={anon_key}")
    print(f"SUPABASE_PUBLISHABLE_API_KEY={anon_key}")
if service_role_key:
    print(f"SUPABASE_SERVICE_ROLE_KEY={service_role_key}")
if jwt_secret:
    print(f"SUPABASE_JWT_SECRET={jwt_secret}")
PY
}

resolve_project_ref() {
  if [[ -n "${SUPABASE_PROJECT_REF:-}" ]]; then
    return 0
  fi
  if [[ -z "${SUPABASE_URL:-}" ]]; then
    return 0
  fi
  local host
  host=$(python3 - "${SUPABASE_URL}" <<'PY'
from urllib.parse import urlparse
import sys
parsed = urlparse(sys.argv[1])
print(parsed.hostname or "")
PY
)
  if [[ "${host}" == *".supabase.co" ]]; then
    SUPABASE_PROJECT_REF="${host%%.supabase.co}"
    export SUPABASE_PROJECT_REF
  fi
}

ensure_allowlisted_ref() {
  if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
    echo "SUPABASE_PROJECT_REF is required for remote operations." >&2
    exit 1
  fi
  if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
    echo "Allowlist file not found at ${ALLOWLIST_FILE}" >&2
    exit 1
  fi
  if ! grep -Fxq "${SUPABASE_PROJECT_REF}" "${ALLOWLIST_FILE}"; then
    echo "SUPABASE_PROJECT_REF ${SUPABASE_PROJECT_REF} is not allowlisted." >&2
    exit 1
  fi
}

require_remote_mutation_guards() {
  ensure_allowlisted_ref
  if [[ "${CONFIRM_NON_PROD:-}" != "1" ]]; then
    echo "CONFIRM_NON_PROD=1 is required for remote mutation." >&2
    exit 1
  fi
  case "${ENVIRONMENT:-}" in
    staging|devlive)
      ;; 
    *)
      echo "ENVIRONMENT must be staging or devlive for remote mutation." >&2
      exit 1
      ;;
  esac
}

require_remote_readonly_guards() {
  ensure_allowlisted_ref
}

load_env_file

DB_URL="${SUPABASE_DB_URL:-${DATABASE_URL:-}}"
if [[ -z "${DB_URL}" ]]; then
  if resolved=$(resolve_supabase_status); then
    eval "${resolved}"
    DB_URL="${SUPABASE_DB_URL:-${DATABASE_URL:-}}"
  fi
fi

if [[ -n "${DB_URL}" ]]; then
  eval "$(parse_db_url "${DB_URL}")"
  export DB_URL
  export SUPABASE_DB_URL="${SUPABASE_DB_URL:-${DB_URL}}"
  export DATABASE_URL="${DATABASE_URL:-${DB_URL}}"
fi

resolve_project_ref

DB_TARGET="${DB_TARGET:-}"
if [[ -z "${DB_TARGET}" ]]; then
  if [[ -n "${SUPABASE_PROJECT_REF:-}" ]]; then
    DB_TARGET="remote"
  elif [[ -n "${DB_HOST:-}" ]]; then
    case "${DB_HOST}" in
      localhost|127.0.0.1|0.0.0.0)
        DB_TARGET="local"
        ;;
      *)
        DB_TARGET="remote"
        ;;
    esac
  else
    DB_TARGET="local"
  fi
fi

export REPO_ROOT
export MIGRATIONS_DIR
export DB_TARGET
export DB_HOST
export DB_PORT
export DB_NAME
