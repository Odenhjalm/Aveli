#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="${REPO_ROOT}/supabase/migrations"
LEGACY_MIGRATIONS_DIR="${REPO_ROOT}/backend/supabase/migrations"
PYTHON_BIN="$(command -v python3 || command -v python || true)"

is_truthy() {
  local raw="${1:-}"
  case "${raw,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_prod_env() {
  local raw="${APP_ENV:-${ENVIRONMENT:-${ENV:-}}}"
  case "${raw,,}" in
    prod|production|live)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_clean_worktree() {
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required when REQUIRE_CLEAN_WORKTREE=1 or APP_ENV=production." >&2
    exit 1
  fi
  if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Unable to verify git worktree state from $REPO_ROOT." >&2
    exit 1
  fi
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]]; then
    echo "Refusing to apply migrations: git worktree is not clean." >&2
    echo "Release migrations must run from a clean checkout of the exact commit being shipped." >&2
    exit 1
  fi
}

print_db_target() {
  if [[ -z "$PYTHON_BIN" ]]; then
    echo "Target DB: unable to derive target details automatically (python not available)"
    return 0
  fi
  "$PYTHON_BIN" - <<'PY' "$SUPABASE_DB_URL"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
host = parsed.hostname or "unknown"
port = f":{parsed.port}" if parsed.port else ""
dbname = parsed.path.lstrip("/") or "postgres"
username = parsed.username or ""
project_ref = ""

if username.startswith("postgres."):
    project_ref = username.split(".", 1)[1]
elif host.endswith(".supabase.co"):
    project_ref = host.split(".", 1)[0]

print(f"Target DB: {host}{port}/{dbname}")
if project_ref:
    print(f"Derived Supabase project ref: {project_ref}")
PY
}

verify_project_ref_match() {
  if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
    return 0
  fi
  if [[ -z "$PYTHON_BIN" ]]; then
    echo "Refusing to apply migrations: SUPABASE_PROJECT_REF was provided but no python interpreter is available for target verification." >&2
    exit 1
  fi
  local derived_ref
  derived_ref="$(
    "$PYTHON_BIN" - <<'PY' "$SUPABASE_DB_URL"
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
host = parsed.hostname or ""
username = parsed.username or ""

project_ref = ""
if username.startswith("postgres."):
    project_ref = username.split(".", 1)[1]
elif host.endswith(".supabase.co"):
    project_ref = host.split(".", 1)[0]

print(project_ref)
PY
  )"
  if [[ -n "$derived_ref" && "$derived_ref" != "$SUPABASE_PROJECT_REF" ]]; then
    echo "Refusing to apply migrations: SUPABASE_PROJECT_REF=$SUPABASE_PROJECT_REF does not match the DB target project ref ($derived_ref)." >&2
    exit 1
  fi
}

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required" >&2
  exit 1
fi
PGPASSWORD=${SUPABASE_DB_PASSWORD:-}
export PGPASSWORD

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "Migrations directory not found at ${MIGRATIONS_DIR}" >&2
  exit 1
fi

if is_truthy "${REQUIRE_CLEAN_WORKTREE:-0}" || is_prod_env; then
  require_clean_worktree
fi

if [[ -d "${LEGACY_MIGRATIONS_DIR}" ]] && find "${LEGACY_MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.sql' | grep -q .; then
  echo "WARNING: ignoring non-canonical migration path ${LEGACY_MIGRATIONS_DIR}." >&2
  echo "WARNING: production migrations come from ${MIGRATIONS_DIR} only." >&2
fi

echo "Using canonical migration source: ${MIGRATIONS_DIR}"
print_db_target
verify_project_ref_match

find "${MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.sql' | sort | while read -r file; do
  echo "Applying ${file}"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$file"
done
